#!/usr/bin/env node
// Parallel-Hand PR Lease guard — PreToolUse Bash hook (spec: parallel-hand-pr-lease.md).
//
// Before a session runs `git push`, this asks the server whether another LIVE
// session of THIS agent already owns that branch's lease; if so the server says
// deny and this hook exits 2 (blocks the push). Coordinates the agent's OWN
// cooperating hands only — never authority over a principal. Dev-gated + dryRun.
//
// FAIL-OPEN is the load-bearing safety property: the ENTIRE body is wrapped so
// that ANY error (bad stdin, no config, server down/slow, internal throw) exits 0
// (ALLOW). A PreToolUse hook that exits non-zero blocks the command, so a crashing
// guard must never lock out every push (the hook-event-reporter.js lockout class).
//
// ESM-safe: node:fs via await import() inside the async handler (works in CJS+ESM).

let data = '';
process.stdin.on('data', (chunk) => (data += chunk));
process.stdin.on('end', async () => {
  try {
    const input = JSON.parse(data || '{}');
    // Only gate the Bash tool, and only a literal `git push` in the command.
    if (input.tool_name !== 'Bash') process.exit(0);
    const command = (input.tool_input && input.tool_input.command) || '';
    if (typeof command !== 'string' || !/\bgit\b[^\n;&|]*\bpush\b/.test(command)) process.exit(0);

    const { readFileSync } = await import('node:fs');
    const { join } = await import('node:path');
    let serverPort = 4040;
    let authToken = '';
    let enabled = false;
    try {
      const cfg = JSON.parse(readFileSync(join(process.env.CLAUDE_PROJECT_DIR || '.', '.instar', 'config.json'), 'utf-8'));
      serverPort = cfg.port || 4040;
      authToken = cfg.authToken || '';
      // Dev-gated dark: only the development agent runs the guard (matches the route gate).
      enabled = !!(cfg.developmentAgent === true || (cfg.monitoring && cfg.monitoring.prHandLease));
    } catch {}
    if (!enabled) process.exit(0);

    const topicRaw = process.env.INSTAR_TELEGRAM_TOPIC;
    // INSTAR_SESSION_NAME is injected = the tmux session name (SessionManager spawn),
    // which is exactly what the store's running-set probe matches on (M-C consistency).
    const sessionName = process.env.INSTAR_SESSION_NAME || '';
    if (!topicRaw || !sessionName) process.exit(0); // can't evaluate → fail-open
    const topicId = parseInt(topicRaw, 10);
    if (!Number.isFinite(topicId)) process.exit(0);
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    let decision = 'allow';
    let body = null;
    try {
      const resp = await fetch('http://127.0.0.1:' + serverPort + '/pr-leases/evaluate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + authToken },
        body: JSON.stringify({ command, cwd, topicId, sessionName }),
        signal: controller.signal,
      });
      body = await resp.json();
      decision = (body && body.decision) || 'allow';
    } catch {
      // server down/slow/timeout → fail-open (never block a push on a transient).
      process.exit(0);
    } finally {
      clearTimeout(timeout);
    }

    if (decision === 'deny') {
      const h = (body && body.holder) || {};
      const who = h.holderTopicId ? ('topic ' + h.holderTopicId + (h.intent ? ' (' + h.intent + ')' : '')) : 'another live session';
      process.stderr.write(
        'pr-hand-lease: another live hand (' + who + ') holds this branch\'s push lease. ' +
        'Standing down to avoid a competing push. If your change is genuinely distinct, ' +
        'land it as a follow-up commit/PR once that hand releases.\n'
      );
      process.exit(2); // block the push
    }
    process.exit(0); // allow / escalate / dryRun-would-deny → never block here
  } catch {
    process.exit(0); // own-crash fail-open — a broken guard must never block a push
  }
});

// Backstop: if stdin never ends, never hang the tool — allow after a bounded wait.
setTimeout(() => process.exit(0), 8000);
