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
      // Config home (actionclaim-config-shape-fix): a real install's `messaging` is
      // an ARRAY of adapters, so `messaging.actionClaim.*` is unreachable. Canonical
      // home is a TOP-LEVEL `actionClaim`; the legacy object-shaped
      // `messaging.actionClaim` is honored as a back-compat fallback.
      var acCfg = cfg.actionClaim || (cfg.messaging && !Array.isArray(cfg.messaging) ? cfg.messaging.actionClaim : undefined);
      enabled = !!(acCfg && acCfg.enabled);
    } catch {}

    if (!enabled) process.exit(0);

    const input = JSON.parse(data);
    const rawMessage = input.last_assistant_message || '';
    // slack-followthrough-generalization §4.4: key the conversation from
    // INSTAR_CONVERSATION_ID ONLY — NO INSTAR_TELEGRAM_TOPIC fallback (the fallback
    // re-introduces the lifeline cross-channel mis-delivery; a shared/lifeline
    // session never carries this env, so it registers nothing — a safe miss).
    // Number.isFinite admits a negative (minted Slack) id.
    const topicRaw = process.env.INSTAR_CONVERSATION_ID;
    if (!rawMessage || !topicRaw) process.exit(0);
    const topicId = parseInt(topicRaw, 10);
    if (!Number.isFinite(topicId)) process.exit(0);
    // Clamp the payload (§4.4): a pathological multi-MB reply would exceed the
    // server body-parser limit → a silent non-registration; the classifiers only
    // need the first 16KB. NO length floor — the high-precision classifiers are the
    // semantic filter, so terse promises ("I'll fix it") must not be dropped.
    const message = rawMessage.slice(0, 16384);
    const bindToken = process.env.INSTAR_BIND_TOKEN;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    try {
      await fetch('http://127.0.0.1:' + serverPort + '/action-claim/observe', {
        method: 'POST',
        headers: Object.assign(
          { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + authToken },
          bindToken ? { 'X-Instar-Bind-Token': bindToken } : {},
        ),
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
