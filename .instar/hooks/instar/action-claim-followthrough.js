#!/usr/bin/env node
// Action-Claim Follow-Through — thin Stop hook (spec: action-claim-followthrough-sentinel.md).
//
// SIGNAL-ONLY: posts the finished turn's outbound text + topicId to the server's
// /action-claim/observe route, which (server-side) classifies a concrete future-action
// claim ("I'll restart it", "relaunching now") and opens an idempotent follow-through
// commitment. This hook NEVER blocks — it ALWAYS exit(0), pass or fail. Dark by default
// (messaging.actionClaim.enabled, code-default false).
//
// ESM-safe: fs/path are loaded via await import('node:...') INSIDE the async handler
// (works in both CJS and ESM host agents); a bare top-level require(...) crashes with
// "require is not defined in ES module scope" in an ESM-mode agent — see the 2026-05-27
// silent-stall postmortem (no-bare-require-in-generated-hooks regression test).

let data = '';
process.stdin.on('data', (chunk) => (data += chunk));
process.stdin.on('end', async () => {
  try {
    const { readFileSync } = await import('node:fs');
    const { join } = await import('node:path');

    let serverPort = 4040;
    let authToken = '';
    let enabled = false;
    try {
      const configPath = join(process.env.CLAUDE_PROJECT_DIR || '.', '.instar', 'config.json');
      const cfg = JSON.parse(readFileSync(configPath, 'utf-8'));
      serverPort = cfg.port || 4040;
      authToken = cfg.authToken || '';
      enabled = !!(cfg.messaging && cfg.messaging.actionClaim && cfg.messaging.actionClaim.enabled);
    } catch {}

    if (!enabled) process.exit(0);

    const input = JSON.parse(data);
    const message = input.last_assistant_message || '';
    const topicRaw = process.env.INSTAR_TELEGRAM_TOPIC;
    if (!message || message.length < 20 || !topicRaw) process.exit(0);
    const topicId = parseInt(topicRaw, 10);
    if (!Number.isFinite(topicId)) process.exit(0);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    try {
      await fetch('http://127.0.0.1:' + serverPort + '/action-claim/observe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + authToken },
        body: JSON.stringify({ message, topicId }),
        signal: controller.signal,
      });
    } catch {
      // network/timeout — signal-only, ignore
    } finally {
      clearTimeout(timeout);
    }
  } catch {
    // bad stdin — ignore
  }
  process.exit(0); // ALWAYS exit 0 — never block a turn
});
