#!/usr/bin/env node
// Doorway-scan command-allowlist guard — PreToolUse Bash hook
// (spec: DOORWAY-MODEL-KNOWLEDGE-REGISTRY-SPEC.md §2.7).
//
// The doorway-scan job session has Bash but NO Edit/Write tool. Bash can still
// write files a dozen ways (cp/dd/mv/heredoc/interpreters/git-checkout/patch/
// curl -o). This guard is the REAL "never edits source / never self-authorizes
// metered spend" enforcer: a strict command-shape ALLOWLIST with fully-specified,
// fail-closed match semantics.
//
// TWO fail-modes at DIFFERENT stages:
//  (a) SCOPE resolution fails OPEN — if this is not provably the doorway-scan
//      session (env-first, zero disk I/O on the hot path), ALLOW immediately.
//      A guard bug can NEVER block Bash in an unrelated instar-dev/interactive
//      session (exactly like the sibling pr-hand-lease-guard.js).
//  (b) COMMAND matching fails CLOSED — once confirmed IN the doorway-scan
//      session, any command not provably ONE sanctioned simple invocation is
//      REFUSED (exit 2).
//
// The parse IS the security boundary: a genuine stateful lexer (NOT a regex/
// byte-scan) tokenizes the command tracking quote state and recognizes any
// operator / redirection / expansion / substitution / env-prefix as a REFUSE.
// Only a single simple command of plain word tokens can match a sanctioned shape.

let data = '';
process.stdin.on('data', (chunk) => (data += chunk));
process.stdin.on('end', () => {
  // ── Region A: SCOPE resolution (fail OPEN) ──
  let command = '';
  try {
    const input = JSON.parse(data || '{}');
    if (input.tool_name !== 'Bash') return process.exit(0);
    command = (input.tool_input && input.tool_input.command) || '';
    if (typeof command !== 'string') return process.exit(0);
    // Env-first fast path: ZERO disk I/O. Only the scheduler-spawned doorway-scan
    // session carries INSTAR_JOB_SLUG=doorway-scan. Anything else → strict no-op.
    if (process.env.INSTAR_JOB_SLUG !== 'doorway-scan') return process.exit(0);
    // (Confirmed the doorway-scan session by the scheduler-set env marker.)
  } catch {
    return process.exit(0); // scope resolution error → fail OPEN (never block others)
  }

  // ── Region B: COMMAND matching (fail CLOSED) ──
  try {
    const verdict = classifyDoorwayScanCommand(command);
    if (verdict.allow) return process.exit(0);
    process.stderr.write(
      'doorway-scan-guard: refused — ' + verdict.reason + '. This session may run ONLY the ' +
      'sanctioned prober invocation (node scripts/doorway-scan.mjs --scope free-probes), a ' +
      'host-pinned localhost curl (no output-redirect flag), and read-only test -f / cat / jq -r. ' +
      'It must never edit source or self-authorize a metered scope.\n'
    );
    return process.exit(2); // block
  } catch {
    process.stderr.write('doorway-scan-guard: could not decompose the command — refusing (fail-closed).\n');
    return process.exit(2); // undecomposable → REFUSE
  }
});

// Backstop: never hang the tool if stdin never ends. This is the SCOPE-level
// timeout, so it fails OPEN (a stuck guard must not block an unrelated session).
setTimeout(() => process.exit(0), 8000);

/**
 * Tokenize a shell command with a genuine stateful lexer. Returns
 * { ok, tokens, reason }. ok:false when the command is NOT exactly one simple
 * command of plain word tokens (any operator / redirection / expansion /
 * substitution / newline / leading env-assignment → ok:false). tokens are the
 * unquoted argv of the single simple command when ok:true.
 */
function lexSimpleCommand(cmd) {
  const tokens = [];
  let cur = '';
  let curHasChar = false; // distinguishes an empty quoted token '' from no token
  let i = 0;
  const n = cmd.length;
  const flush = () => { if (curHasChar) { tokens.push(cur); cur = ''; curHasChar = false; } };
  while (i < n) {
    const c = cmd[i];
    // Whitespace (token separator).
    if (c === ' ' || c === '\t') { flush(); i++; continue; }
    // Newline / carriage return → a command list separator: REFUSE.
    if (c === '\n' || c === '\r') return { ok: false, reason: 'newline (command list)' };
    // Operators / redirections / control chars outside quotes → REFUSE.
    if (c === ';' || c === '|' || c === '&' || c === '<' || c === '>' || c === '(' || c === ')' || c === '{' || c === '}' || c === '\n') {
      return { ok: false, reason: 'shell operator/redirection "' + c + '"' };
    }
    if (c === '`') return { ok: false, reason: 'backtick command substitution' };
    // Expansion: $VAR, ${...}, $(...) all begin with $ → REFUSE (no expansions).
    if (c === '$') return { ok: false, reason: 'variable/command expansion "$"' };
    // Backslash escape (outside quotes) — take next char literally (benign).
    if (c === '\\') {
      if (i + 1 < n) { cur += cmd[i + 1]; curHasChar = true; i += 2; continue; }
      return { ok: false, reason: 'trailing backslash' };
    }
    // Single-quoted span: literal, no expansion inside.
    if (c === "'") {
      i++;
      while (i < n && cmd[i] !== "'") { cur += cmd[i]; curHasChar = true; i++; }
      if (i >= n) return { ok: false, reason: 'unterminated single quote' };
      curHasChar = true; // an empty '' is still a token
      i++; // skip closing quote
      continue;
    }
    // Double-quoted span: reject $ and backtick inside (expansion), else literal.
    if (c === '"') {
      i++;
      while (i < n && cmd[i] !== '"') {
        const d = cmd[i];
        if (d === '$') return { ok: false, reason: 'expansion inside double quotes' };
        if (d === '`') return { ok: false, reason: 'backtick inside double quotes' };
        if (d === '\\' && i + 1 < n) { cur += cmd[i + 1]; curHasChar = true; i += 2; continue; }
        cur += d; curHasChar = true; i++;
      }
      if (i >= n) return { ok: false, reason: 'unterminated double quote' };
      curHasChar = true;
      i++;
      continue;
    }
    // Ordinary character.
    cur += c; curHasChar = true; i++;
  }
  flush();
  if (tokens.length === 0) return { ok: false, reason: 'empty command' };
  // Leading env-assignment prefix (NAME=value cmd ...) → REFUSE (the money-gate bypass).
  if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[0])) return { ok: false, reason: 'leading env-var assignment prefix' };
  return { ok: true, tokens, reason: 'ok' };
}

function isLocalhostHttpUrl(tok) {
  return /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?(\/|$)/.test(tok);
}

/**
 * Classify a command against the exhaustive sanctioned shapes. Returns
 * { allow, reason }. Fails CLOSED: anything not provably sanctioned → allow:false.
 */
function classifyDoorwayScanCommand(command) {
  const lex = lexSimpleCommand(command);
  if (!lex.ok) return { allow: false, reason: lex.reason };
  const t = lex.tokens;
  // 1) The prober invocation — exact executable + argv.
  if (t[0] === 'node' && t[1] === 'scripts/doorway-scan.mjs' && t[2] === '--scope' && t[3] === 'free-probes' && t.length === 4) {
    return { allow: true, reason: 'prober' };
  }
  // 2) test -f <literal path>
  if (t[0] === 'test' && t[1] === '-f' && t.length === 3) return { allow: true, reason: 'test-f' };
  // 3) cat <literal path>
  if (t[0] === 'cat' && t.length === 2) return { allow: true, reason: 'cat' };
  // 4) jq -r <literal filter> <literal file>
  if (t[0] === 'jq' && t[1] === '-r' && t.length === 4) return { allow: true, reason: 'jq' };
  // 5) curl — host-pinned localhost, read-only flags, NO output-redirect flag.
  if (t[0] === 'curl') {
    const OUTPUT_REDIRECT = new Set(['-o', '-O', '--output', '--remote-name', '--create-dirs']);
    const ALLOWED_FLAGS = new Set(['-s', '-f', '-S', '-sf', '-sS', '-fsS', '-sfS', '--silent', '--fail', '--show-error']);
    let urlCount = 0;
    for (let k = 1; k < t.length; k++) {
      const a = t[k];
      if (OUTPUT_REDIRECT.has(a)) return { allow: false, reason: 'curl output-redirect flag' };
      if (a.startsWith('-')) {
        if (!ALLOWED_FLAGS.has(a)) return { allow: false, reason: 'curl flag not allowlisted (' + a + ')' };
        continue;
      }
      // A non-flag arg must be a localhost URL.
      if (!isLocalhostHttpUrl(a)) return { allow: false, reason: 'curl url not host-pinned to localhost' };
      urlCount++;
    }
    if (urlCount === 1) return { allow: true, reason: 'localhost-curl' };
    return { allow: false, reason: 'curl must carry exactly one localhost url' };
  }
  return { allow: false, reason: 'not a sanctioned command shape (' + t[0] + ')' };
}
