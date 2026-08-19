#!/usr/bin/env node
// Duplicate-session stand-down muzzle — PreToolUse hook on the '*' matcher.
// Spec: docs/specs/duplicate-session-standdown.md
//
// Blocks NEW work in a session whose conversation is being served on another
// machine. Fail-OPEN on every uncertainty. See PostUpdateMigrator.getStandDownGuardHook
// for the full rationale; the short version:
//   1. feature gate  → exit 0 (dark: config read only)
//   2. marker file   → exit 0 unless THIS session is listed (no HTTP)
//   3. evaluate      → the server's authoritative verdict, 1.5s budget
// Tools that are genuinely observation-local are never blocked; every other tool
// name — including ones that do not exist yet — is treated as mutating.

// Observation-local ONLY. Write/Edit/Task/WebFetch are deliberately ABSENT:
// mutating a file is action, spawning a subagent is starting new work (and would
// block drain forever), and a fetch is egress.
var ALLOWLIST = ['Read', 'Glob', 'Grep', 'TodoWrite'];

var data = '';
process.stdin.on('data', function (c) { data += c; });
process.stdin.on('end', async function () {
  try {
    var input = JSON.parse(data || '{}');
    var toolName = input.tool_name || '';
    if (ALLOWLIST.indexOf(toolName) !== -1) return process.exit(0);

    var sessionName = process.env.INSTAR_SESSION_NAME || '';
    // A session without the env (headless one-shots) is outside this hook's reach.
    if (!sessionName) return process.exit(0);

    var fsMod = await import('node:fs');
    var pathMod = await import('node:path');
    // The AGENT HOME, not the project dir. A worktree session's CLAUDE_PROJECT_DIR
    // is the checkout — which has no .instar/config.json and no state/ — so
    // resolving agent-scoped files from it made this guard silently no-op for
    // exactly the sessions doing mutating work. INSTAR_AGENT_HOME is injected at
    // spawn; CLAUDE_PROJECT_DIR remains the fallback for a session started
    // outside that path (where the fail-open is then honest, not hidden).
    var agentHome = process.env.INSTAR_AGENT_HOME || process.env.CLAUDE_PROJECT_DIR || '.';

    // ── Gate 1: is the feature on here? An explicit false wins even on a dev
    //    agent — no per-call chatter when deliberately disabled.
    var serverPort = 4040;
    // INSTAR_AUTH_TOKEN FIRST — never bare cfg.authToken. After secret
    // externalization the config holds the MARKER {"secret": true}, not the
    // token, so 'Bearer ' + cfg.authToken stringifies to 'Bearer [object
    // Object]', /standdown/evaluate 401s, and this hook fail-opens on every
    // single call — forever, silently, with green tests (a stub server that
    // never checks Authorization cannot see it). The env var is injected at
    // every spawn site; the config read is the fallback, type-guarded so a
    // marker object can never become a token string.
    var authToken = process.env.INSTAR_AUTH_TOKEN || '';
    var enabled = false;
    try {
      var cfg = JSON.parse(fsMod.readFileSync(pathMod.join(agentHome, '.instar', 'config.json'), 'utf-8'));
      serverPort = cfg.port || 4040;
      if (!authToken && typeof cfg.authToken === 'string') authToken = cfg.authToken;
      var sd = (cfg.monitoring && cfg.monitoring.standDown) || {};
      enabled = sd.enabled === false ? false : (sd.enabled === true || cfg.developmentAgent === true);
    } catch (e) { return process.exit(0); }
    if (!enabled) return process.exit(0);

    // ── Gate 2: the marker fast path. Steady state for ~100% of calls.
    var listed = false;
    try {
      // <agentHome>/.instar/state/ — NOT <agentHome>/state/. config.stateDir IS
      // the .instar directory, so the registry writes under .instar/state/. The
      // first version of this line dropped the .instar segment while the config
      // read one line above kept it, so the two disagreed inside one file and the
      // marker read always ENOENT'd → exit 0 → the tool muzzle could not fire at
      // all, in production, with 24 green tests over the wrong path.
      var markerRaw = fsMod.readFileSync(pathMod.join(agentHome, '.instar', 'state', 'standdown-active.json'), 'utf-8');
      var marker = JSON.parse(markerRaw);
      listed = Array.isArray(marker.sessions) && marker.sessions.indexOf(sessionName) !== -1;
    } catch (e) { return process.exit(0); } // absent/unreadable/torn → fail-open
    if (!listed) return process.exit(0);

    // ── Gate 3: the server holds the authority. The marker only says "ask".
    var controller = new AbortController();
    var timer = setTimeout(function () { controller.abort(); }, 1500);
    var body = null;
    try {
      var resp = await fetch('http://127.0.0.1:' + serverPort + '/standdown/evaluate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + authToken },
        body: JSON.stringify({ sessionName: sessionName, tool: toolName }),
        signal: controller.signal,
      });
      body = await resp.json();
    } catch (e) {
      return process.exit(0); // server down/slow → fail-open
    } finally {
      clearTimeout(timer);
    }

    if (!body || body.verdict !== 'block') return process.exit(0);

    // The message interpolates ONLY the server's charset-clamped machine id —
    // never a nickname or a free-text reason. A peer-influenced string in
    // instruction position is a prompt-injection surface.
    var owner = typeof body.ownerMachineId === 'string' ? body.ownerMachineId : 'another machine';
    process.stderr.write(
      'This session is standing down: the conversation and its work continue on machine ' +
      owner + '. Do not retry this call or route around the block; stop, and remain idle.\n'
    );
    process.exit(2);
  } catch (e) {
    process.exit(0); // own-crash fail-open
  }
});

// Backstop: never hang a tool call if stdin never ends.
setTimeout(function () { process.exit(0); }, 4000);
