#!/usr/bin/env node
// Verify-Before-Done — observe-only Stop hook.
// Reads a bounded Claude transcript tail LOCALLY and sends structural metadata
// only. It never sends transcript_path, commands, tool results, or raw inputs.
let data = '';
process.stdin.on('data', chunk => (data += chunk));
process.stdin.on('end', async () => {
  try {
    const fs = await import('node:fs');
    const path = await import('node:path');
    const os = await import('node:os');
    const crypto = await import('node:crypto');
    const projectDir = process.env.CLAUDE_PROJECT_DIR || '.';
    const cfg = JSON.parse(fs.readFileSync(path.join(projectDir, '.instar', 'config.json'), 'utf8'));
    const feature = cfg.monitoring && cfg.monitoring.completionClaimVerification || {};
    const enabled = feature.enabled !== undefined ? feature.enabled === true : cfg.developmentAgent === true;
    if (!enabled) process.exit(0);
    const input = JSON.parse(data || '{}');
    const message = String(input.last_assistant_message || '');
    // Every non-empty authored response is eligible for the single bounded
    // server-side claim pass. No hook regex is allowed to define coverage.
    if (!message) process.exit(0);
    const transcript = typeof input.transcript_path === 'string' ? path.resolve(input.transcript_path) : '';
    // Confine reads to a Claude projects tree. CLAUDE_CONFIG_DIR must be
    // honoured: an agent running with a custom config dir (e.g.
    // ~/.claude-followme-<name>) keeps its transcripts under THAT dir, so a
    // hardcoded ~/.claude/projects rejects every transcript and the observer
    // records nothing — silently, since the guard just exits 0 (ACT-966,
    // second cause). Both roots are allowed so the guard works whether or not
    // the variable is set; each is still a Claude projects tree, so the
    // containment intent is unchanged.
    const claudeRoots = [];
    if (process.env.CLAUDE_CONFIG_DIR) claudeRoots.push(path.resolve(process.env.CLAUDE_CONFIG_DIR, 'projects'));
    claudeRoots.push(path.resolve(os.homedir(), '.claude', 'projects'));
    const withinClaudeRoot = claudeRoots.some(function (root) {
      return transcript === root || transcript.startsWith(root + path.sep);
    });
    if (!transcript || !withinClaudeRoot) process.exit(0);
    const stat = fs.statSync(transcript);
    if (!stat.isFile()) process.exit(0);
    const max = 512 * 1024;
    const start = Math.max(0, stat.size - max);
    const fd = fs.openSync(transcript, 'r');
    const buf = Buffer.alloc(stat.size - start);
    try { fs.readSync(fd, buf, 0, buf.length, start); } finally { fs.closeSync(fd); }
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
    const rows = [];
    for (const line of lines) { try { if (line.trim()) rows.push(JSON.parse(line)); } catch {} }
    let boundary = -1;
    const isObj = value => value && typeof value === 'object' && !Array.isArray(value);
    for (let i = 0; i < rows.length; i++) {
      const m = isObj(rows[i].message) ? rows[i].message : {};
      const content = Array.isArray(m.content) ? m.content : Array.isArray(rows[i].content) ? rows[i].content : [];
      const toolResultOnly = content.length > 0 && content.every(block => isObj(block) && block.type === 'tool_result');
      if (!toolResultOnly && (rows[i].type === 'user' || rows[i].role === 'user' || m.role === 'user')) boundary = i;
    }
    const calls = new Map();
    let anon = 0;
    const scrub = text => String(text)
      .replace(/gh[pousr]_[A-Za-z0-9]{20,}/g, 'gh***_REDACTED')
      .replace(/(sk|pk|rk)-[A-Za-z0-9]{16,}/g, '$1-REDACTED')
      .replace(/xox[baprs]-[A-Za-z0-9-]{10,}/g, 'xox*-REDACTED')
      .replace(/d{6,12}:[A-Za-z0-9_-]{30,}/g, 'TELEGRAM_BOT_TOKEN_REDACTED')
      .replace(/(?:AKIA|ASIA)[A-Z0-9]{16}/g, 'AWS_ACCESS_KEY_REDACTED')
      .replace(/[A-Za-z0-9_-]{20,}.[A-Za-z0-9_-]{6,}.[A-Za-z0-9_-]{20,}/g, 'JWT_REDACTED');
    const safe = value => {
      const text = typeof value === 'number' ? String(value) : value;
      if (typeof text !== 'string' || !/^[a-zA-Z0-9._/@:+-]{1,200}$/.test(text)) return undefined;
      const cleaned = scrub(text).slice(0, 256);
      return feature.redactIdentifiers === true
        ? 'id:' + crypto.createHash('sha256').update(cleaned.split('/').pop() || cleaned).digest('hex').slice(0, 16)
        : cleaned;
    };
    const extract = (name, rawInput) => {
      const x = isObj(rawInput) ? rawInput : {};
      const base = { tool: String(name).slice(0, 100), actionKind: 'other', ok: true };
      if (name === 'Bash' || name === 'functions.exec_command') {
        const command = typeof x.command === 'string' ? x.command : typeof x.cmd === 'string' ? x.cmd : '';
        if (!/[;&|\x60\n\r]/.test(command)) {
          const push = command.trim().match(/^git\s+push(?:\s+--[a-z-]+)*\s+([^\s]+)(?:\s+([^\s]+))?$/i);
          if (push) return { ...base, actionKind: 'pushed', targetSummary: [safe(push[1]), safe(push[2])].filter(Boolean).join('/') || undefined };
          if (/^git\s+commit(?:\s+.*)?$/i.test(command.trim())) return { ...base, actionKind: 'committed' };
          const merge = command.trim().match(/^git\s+merge\s+([^\s]+)$/i);
          if (merge) return { ...base, actionKind: 'merged', targetSummary: safe(merge[1]) };
        }
        return base;
      }
      if (['Edit','Write','MultiEdit','functions.apply_patch'].includes(name)) return { ...base, actionKind: 'fixed', targetSummary: typeof x.file_path === 'string' ? safe(path.basename(x.file_path)) : undefined };
      if (/slack|telegram|send_message|reply/i.test(name)) return { ...base, actionKind: 'sent', targetSummary: safe(x.channel) || safe(x.topicId) || safe(x.target) };
      if (/deploy/i.test(name)) return { ...base, actionKind: 'deployed', targetSummary: safe(x.project) };
      if (/merge/i.test(name)) return { ...base, actionKind: 'merged', targetSummary: safe(x.pull_number) };
      return base;
    };
    const result = block => {
      const id = typeof block.tool_use_id === 'string' ? block.tool_use_id : typeof block.id === 'string' ? block.id : '';
      const item = calls.get(id);
      if (item && (block.is_error === true || block.error != null || block.success === false)) calls.set(id, { ...item, ok: false, errorClass: 'tool-error' });
    };
    for (const row of rows.slice(boundary + 1)) {
      const m = isObj(row.message) ? row.message : {};
      const content = Array.isArray(m.content) ? m.content : Array.isArray(row.content) ? row.content : [];
      for (const block of content) {
        if (!isObj(block)) continue;
        if (block.type === 'tool_use' && typeof block.name === 'string') calls.set(typeof block.id === 'string' ? block.id : 'anon-' + anon++, extract(block.name, block.input));
        else if (block.type === 'tool_result') result(block);
      }
      if (row.type === 'tool_result') result(row);
    }
    const evidence = { hadToolCalls: calls.size > 0, toolCalls: [...calls.values()].slice(-200), truncated: start > 0, unavailable: false, canaryOk: rows.length === 0 || boundary >= 0 || calls.size > 0 };
    const auth = typeof cfg.authToken === 'string' ? cfg.authToken : process.env.INSTAR_AUTH_TOKEN || '';
    const topicRaw = process.env.INSTAR_CONVERSATION_ID;
    const topicId = topicRaw && Number.isFinite(Number(topicRaw)) ? Number(topicRaw) : undefined;
    const bindToken = process.env.INSTAR_BIND_TOKEN;
    const controller = new AbortController();
    // Dispatch and leave the hook path without awaiting either HTTP admission
    // or intelligence. One short event-loop turn lets the localhost write
    // begin; the hard exit bounds Stop-hook latency independently of server
    // health while the server owns all durable async processing.
    void fetch('http://127.0.0.1:' + (cfg.port || 4040) + '/completion-claim/observe', {
        method: 'POST',
        headers: Object.assign(
          { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + auth, 'X-Instar-Request': '1' },
          bindToken ? { 'X-Instar-Bind-Token': bindToken } : {},
        ),
        body: JSON.stringify({ hookSchemaVersion: 1, messageAttemptId: uuidv7(), message, turnEvidence: evidence, topicHint: topicId }), signal: controller.signal,
      }).catch(() => {});
    setTimeout(() => { controller.abort(); process.exit(0); }, 25);
    return;
  } catch {}
  process.exit(0); // signal-only; never blocks or rewrites a turn
});

function uuidv7() {
  // Uses globalThis.crypto.getRandomValues, NOT node:crypto's randomBytes.
  // This function is at MODULE scope while the `const crypto = await
  // import('node:crypto')` above lives inside the stdin 'end' callback, so a
  // bare `crypto` here resolves to the global WebCrypto object — which has
  // getRandomValues but NOT randomBytes. That made every invocation throw
  // "crypto.randomBytes is not a function" and exit(0) silently, so the
  // observer recorded nothing (ACT-966). getRandomValues needs no import and
  // works identically under an ESM or CJS host, so the scope trap cannot
  // return. Hex is formatted manually because Uint8Array has no toString('hex').
  const bytes = new Uint8Array(16);
  globalThis.crypto.getRandomValues(bytes);
  const now = BigInt(Date.now());
  for (let i = 5; i >= 0; i--) bytes[5 - i] = Number((now >> BigInt(i * 8)) & 255n);
  bytes[6] = (bytes[6] & 15) | 112;
  bytes[8] = (bytes[8] & 63) | 128;
  const h = Array.from(bytes, function (b) { return b.toString(16).padStart(2, '0'); }).join('');
  return h.slice(0,8)+'-'+h.slice(8,12)+'-'+h.slice(12,16)+'-'+h.slice(16,20)+'-'+h.slice(20);
}
