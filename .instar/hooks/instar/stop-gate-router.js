#!/usr/bin/env node
// Unjustified Stop Gate router.
//
// Thin client: reads Stop-hook JSON from stdin, asks the local Instar server
// for hot-path state, and in shadow/enforce mode submits trusted evidence
// metadata to /internal/stop-gate/evaluate. Shadow mode only records telemetry;
// enforce mode blocks only on a server-side "continue" decision.
//
// ESM-SAFE: dynamic `await import(...)` inside an async IIFE so this runs in
// both CJS and ESM host package types. A bare top-level `require(...)` throws
// "require is not defined in ES module scope" when the host package.json has
// "type":"module" (which silently killed this gate — the gate meant to PREVENT
// unjustified silent stalls). A bare top-level `import` is a syntax error in
// CJS scope; dynamic import works in BOTH. See hook-event-reporter.js header.

(async () => {
  const fs = await import('node:fs');
  const path = await import('node:path');
  const childProcess = await import('node:child_process');

  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const configPath = path.join(projectDir, '.instar', 'config.json');
  let serverPort = 4040;
  // INSTAR_AUTH_TOKEN env first — SessionManager injects it per spawned session
  // and it survives secret-externalization. Legacy plaintext-config fallback
  // with string-type guard so the { secret: true } placeholder cannot leak.
  let authToken = process.env.INSTAR_AUTH_TOKEN || '';
  try {
    const cfg = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    serverPort = cfg.port || 4040;
    if (!authToken && typeof cfg.authToken === 'string') authToken = cfg.authToken;
  } catch {}

  function postJson(urlPath, payload, timeoutMs) {
    const controller = new AbortController();
    const timer = setTimeout(function () { controller.abort(); }, timeoutMs);
    return fetch('http://127.0.0.1:' + serverPort + urlPath, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + authToken,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    }).then(async function (res) {
      clearTimeout(timer);
      if (!res.ok) throw new Error('http ' + res.status);
      return res.json();
    }, function (err) {
      clearTimeout(timer);
      throw err;
    });
  }

  function getJson(urlPath, timeoutMs) {
    const controller = new AbortController();
    const timer = setTimeout(function () { controller.abort(); }, timeoutMs);
    return fetch('http://127.0.0.1:' + serverPort + urlPath, {
      headers: { 'Authorization': 'Bearer ' + authToken },
      signal: controller.signal,
    }).then(async function (res) {
      clearTimeout(timer);
      if (!res.ok) throw new Error('http ' + res.status);
      return res.json();
    }, function (err) {
      clearTimeout(timer);
      throw err;
    });
  }

  function git(args) {
    try {
      return childProcess.execFileSync('git', ['-C', projectDir].concat(args), {
        encoding: 'utf-8',
        timeout: 800,
        stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();
    } catch {
      return '';
    }
  }

  function firstLine(value) {
    return String(value || '').split(/\r?\n/).filter(Boolean)[0] || null;
  }

  function listEvidenceArtifacts(sessionStartTs) {
    const out = git(['ls-files']);
    if (!out) return [];
    const files = out.split(/\r?\n/).filter(function (file) {
      if (!file) return false;
      if (!/\.(md|markdown|json|jsonl|txt)$/i.test(file)) return false;
      return /(^|\/)(docs\/specs|specs|plans?|tasks?|upgrades|MEMORY\.md|AGENTS\.md)|spec|plan|handoff|todo|next|round/i.test(file);
    }).slice(0, 30);
    return files.map(function (file) {
      const introducingCommit = firstLine(git(['log', '--follow', '--format=%H', '--reverse', '--', file]));
      const latestCommit = firstLine(git(['log', '--format=%H', '-1', '--', file]));
      let createdThisSession = false;
      let modifiedThisSession = false;
      if (sessionStartTs && latestCommit) {
        const ts = Number(firstLine(git(['show', '-s', '--format=%ct', latestCommit])) || '0') * 1000;
        modifiedThisSession = ts >= sessionStartTs;
        if (introducingCommit) {
          const createdTs = Number(firstLine(git(['show', '-s', '--format=%ct', introducingCommit])) || '0') * 1000;
          createdThisSession = createdTs >= sessionStartTs;
        }
      }
      return {
        path: file,
        introducingCommit: introducingCommit,
        latestCommit: latestCommit,
        createdThisSession: createdThisSession,
        modifiedThisSession: modifiedThisSession,
      };
    });
  }

  function buildSignals(stopReason, message) {
    const text = String(stopReason || '') + '\n' + String(message || '');
    return {
      mentionsContextLimit: /context|window|token|compact/i.test(text),
      mentionsFreshSession: /fresh session|new session|restart|continue in a new/i.test(text),
      claimsShouldStopForContext: /stop|pause|wrap up|hand off/i.test(text) && /context|fresh|compact/i.test(text),
    };
  }

  function exitOpen() {
    process.exit(0);
  }

  // Read the Stop-hook JSON from stdin (works in both CJS + ESM).
  let data = '';
  try {
    for await (const chunk of process.stdin) data += chunk;
  } catch {
    exitOpen();
    return;
  }

  let input;
  try {
    input = data ? JSON.parse(data) : {};
  } catch {
    exitOpen();
    return;
  }

  if (input.stop_hook_active) { exitOpen(); return; }
  const sessionId = String(input.session_id || input.sessionId || process.env.INSTAR_SESSION_ID || 'unknown');

  // ── Stated-continuation guard (mode-INDEPENDENT). ───────────────────────────
  // Catches the specific silent-stall pattern that shadow mode lets through: the
  // agent's FINAL message tells the user it is about to act this turn ("I'll
  // build X now", "starting now", "next phase: ship ...") and then the turn ENDS
  // without doing it. Blocks ONCE (the stop_hook_active guard above prevents a
  // loop) regardless of the gate's shadow/enforce mode — shadow is exactly when
  // these stalls slip through (telemetry only). The re-feed allows a clean exit:
  // do the work, OR send the user one honest message that you are stopping and
  // why. Pure substring matching (no regex-escape hazards in this template).
  (function statedContinuationGuard() {
    const lc = String(input.last_assistant_message || '').toLowerCase();
    if (lc.length < 8) return;
    function hasAny(arr) { for (let i = 0; i < arr.length; i++) { if (lc.indexOf(arr[i]) !== -1) return arr[i]; } return null; }
    const commit = hasAny([
      "i'm going to", 'i am going to', "i'll ", 'i will ', 'about to ', 'gonna ',
      'next phase', 'next step', 'next up', 'next round', 'kicking off',
      'getting started', 'starting now', 'on it', "i'll build", "i'll ship",
      "i'll continue", "i'll finish", "i'll fix", "i'll start", "i'll do",
    ]);
    const imminent = hasAny([
      ' now', 'right now', 'immediately', 'starting now', 'next phase',
      'next step', 'next up', 'this turn', 'this session', 'then i',
    ]);
    if (!commit || !imminent) return;
    process.stdout.write(JSON.stringify({
      decision: 'block',
      reason: 'STOP-GATE (stated-continuation): your final message tells the user you are about to act ("' + commit + '" / "' + imminent + '") but you are ending the turn without doing it. Do NOT give the impression you are continuing and then stall silently. Either (a) actually do that work now, or (b) if you are genuinely blocked, finished, or need the user, send ONE short honest message saying you are stopping and exactly why — then you may stop. This guard fires once.',
    }));
    process.exit(2);
  })();

  try {
    const hot = await getJson('/internal/stop-gate/hot-path?session=' + encodeURIComponent(sessionId), 1500);

    // green-pr-automerge Layer 2 (MODE-INDEPENDENT — the UnjustifiedStopGate mode
    // ships 'off', so this must act on the hot-path field BEFORE the mode gate,
    // exactly like the stated-continuation guard above). One-shot per session+PR
    // via a tmp marker so the agent is never trapped. NO runnable merge command.
    if (hot && hot.greenPrBlock && hot.greenPrBlock.pr && !hot.killSwitch && !hot.compactionInFlight) {
      try {
        const os = await import('node:os');
        const marker = path.join(os.tmpdir(), 'instar-greenpr-block-' + encodeURIComponent(sessionId) + '-' + hot.greenPrBlock.pr);
        if (!fs.existsSync(marker)) {
          try { fs.writeFileSync(marker, String(Date.now())); } catch {}
          process.stdout.write(JSON.stringify({ decision: 'block', reason: 'STOP-GATE (green-pr): ' + String(hot.greenPrBlock.message) }));
          process.exit(2);
          return;
        }
      } catch {}
    }

    if (!hot || hot.killSwitch || hot.mode === 'off' || hot.compactionInFlight) { exitOpen(); return; }

    const message = String(input.last_assistant_message || '');
    const stopReason = String(input.stop_reason || input.reason || message || '');
    const evidenceMetadata = {
      artifacts: listEvidenceArtifacts(hot.sessionStartTs || null),
      signals: buildSignals(stopReason, message),
      sessionStartTs: hot.sessionStartTs || null,
    };

    const result = await postJson('/internal/stop-gate/evaluate', {
      sessionId: sessionId,
      evidenceMetadata: evidenceMetadata,
      untrustedContent: {
        stopReason: stopReason,
        recentTurns: message ? [{ source: 'agent', text: message }] : [],
      },
    }, 2500);

    if (hot.mode === 'enforce' && result && result.decision === 'continue' && result.reminder) {
      process.stdout.write(JSON.stringify({ decision: 'block', reason: result.reminder }));
      process.exit(2);
      return;
    }
    exitOpen();
  } catch {
    exitOpen();
  }
})();
