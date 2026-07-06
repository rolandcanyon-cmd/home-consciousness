#!/usr/bin/env node
// Working-Set Artifact Recorder — PostToolUse Write/Edit hook (spec: intelligent-working-set-lazy-sync.md, F8).
//
// SIGNAL-ONLY / fire-and-forget: on a SUCCESSFUL Write/Edit/MultiEdit under the .instar/ jail,
// POSTs {topicId, relPath} to the server's POST /coherence/working-set/record so the INTERACTIVE
// artifact (a file the agent wrote conversationally, with NO autonomous run) enters the computed
// working-set manifest — the exact case WorkingSetManifest.computeWorkingSet misses. It NEVER
// blocks — ALWAYS exit(0), pass or fail. Records NOTHING for a file OUTSIDE the .instar/ jail
// (project files are git-synced; F10) or when the feature is off (code-default OFF ⇒ dark:
// coherenceJournal.workingSet.recordInteractive). relPath is stateDir-relative + forward-slash
// normalized — the exact convention computeWorkingSet Source-3 resolves (path.resolve(stateDir,rel)).
//
// ESM-safe: node: imports INSIDE the async handler (works in BOTH CJS and ESM host agents); a
// bare top-level require(...) crashes an ESM-mode agent — see the 2026-05-27 silent-stall postmortem.

let data = '';
process.stdin.on('data', (chunk) => (data += chunk));
process.stdin.on('end', async () => {
  try {
    const { readFileSync } = await import('node:fs');
    const { join, resolve, relative, isAbsolute } = await import('node:path');

    const projectDir = process.env.CLAUDE_PROJECT_DIR || '.';
    let serverPort = 4040;
    let authToken = '';
    let enabled = false;
    try {
      const cfg = JSON.parse(readFileSync(join(projectDir, '.instar', 'config.json'), 'utf-8'));
      serverPort = cfg.port || 4040;
      authToken = cfg.authToken || '';
      enabled = !!(cfg.coherenceJournal && cfg.coherenceJournal.workingSet && cfg.coherenceJournal.workingSet.recordInteractive);
    } catch {}
    if (!enabled) process.exit(0);

    const input = JSON.parse(data);
    const tool = input.tool_name || '';
    if (tool !== 'Write' && tool !== 'Edit' && tool !== 'MultiEdit') process.exit(0);
    // A failed tool-call records nothing (F8) — deletes are NOT inferred from a write.
    const resp = input.tool_response;
    if (resp && (resp.error || resp.success === false)) process.exit(0);

    const filePath = input.tool_input && input.tool_input.file_path;
    if (!filePath || typeof filePath !== 'string') process.exit(0);

    // Conversation id — key from INSTAR_CONVERSATION_ID ONLY (a shared/lifeline session carries
    // none → records nothing, a safe miss). Number.isFinite admits a minted-negative (Slack) id.
    const topicRaw = process.env.INSTAR_CONVERSATION_ID;
    if (!topicRaw) process.exit(0);
    const topicId = parseInt(topicRaw, 10);
    if (!Number.isFinite(topicId)) process.exit(0);

    // Derive relPath vs the .instar/ jail (stateDir-relative). Outside the jail ⇒ skip (F10).
    const stateDir = resolve(projectDir, '.instar');
    const rawRel = relative(stateDir, resolve(filePath));
    if (!rawRel || rawRel.startsWith('..') || isAbsolute(rawRel)) process.exit(0);
    const segs = rawRel.split(/[/\\]+/);
    if (segs.includes('.git')) process.exit(0); // never a git internal
    const relPath = segs.join('/'); // forward-slash normalized for cross-machine identity

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    try {
      await fetch('http://127.0.0.1:' + serverPort + '/coherence/working-set/record', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + authToken },
        body: JSON.stringify({ topicId, relPath }),
        signal: controller.signal,
      });
    } catch {
      // network/timeout — fire-and-forget, ignore
    } finally {
      clearTimeout(timeout);
    }
  } catch {
    // bad stdin — ignore
  }
  process.exit(0); // ALWAYS exit 0 — never block a tool
});
