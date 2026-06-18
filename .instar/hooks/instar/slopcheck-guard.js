#!/usr/bin/env node
// Slopcheck guard — package-legitimacy check on install commands.
// PreToolUse hook for Bash. When the command is a package install
// (npm/pnpm/yarn/pip/cargo), it extracts the package names and checks
// whether each is already known to the project (present in a lockfile
// or manifest). Unfamiliar packages get a confirmation nudge — does NOT
// block, just surfaces the legitimacy question before a slopsquatted or
// hallucinated package gets installed.
//
// Cherry-picked into Instar 2026-05-23 from the GSD-Instar integration
// spike (gsd-executor Rule 3 exclusion: package installs are NOT
// auto-fixable because a failed/typo'd install may be a slopsquat).
// Signal-only — decision: approve + additionalContext. The agent decides.
//
// ESM-SAFE: dynamic `await import(...)` inside an async IIFE so this runs in
// both CJS and ESM host package types. Bare top-level `require(...)` throws
// in ESM scope when the host package.json has "type":"module" — silently
// killed this PreToolUse guard on every tool call. See hook-event-reporter.js.

(async () => {
  const fs = await import('node:fs');
  const path = await import('node:path');

  // Install-command patterns → capture the args portion after the verb.
  const INSTALL_PATTERNS = [
    { re: /\bnpm\s+(?:i|install|add)\s+([^&|;]+)/i, mgr: 'npm' },
    { re: /\bpnpm\s+(?:i|install|add)\s+([^&|;]+)/i, mgr: 'pnpm' },
    { re: /\byarn\s+add\s+([^&|;]+)/i, mgr: 'yarn' },
    { re: /\bpip3?\s+install\s+([^&|;]+)/i, mgr: 'pip' },
    { re: /\bcargo\s+add\s+([^&|;]+)/i, mgr: 'cargo' },
  ];

  // Flags to strip when extracting package names.
  const FLAG_RE = /^-/;

  function parsePackages(argStr) {
    return argStr
      .trim()
      .split(/\s+/)
      .filter(tok => tok && !FLAG_RE.test(tok))
      // Strip version specifiers: pkg@1.2.3, pkg==1.2.3, pkg~=1.0
      .map(tok => tok.replace(/[@=~<>!].*$/, '').replace(/\[.*$/, ''))
      .filter(Boolean);
  }

  // Returns the set of package names already known to the project from
  // any manifest/lockfile present in the project dir.
  function knownPackages(projectDir) {
    const known = new Set();
    const add = (name) => { if (name && typeof name === 'string') known.add(name.toLowerCase()); };

    // package.json deps + devDeps + lock
    try {
      const pkg = JSON.parse(fs.readFileSync(path.join(projectDir, 'package.json'), 'utf-8'));
      for (const k of ['dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies']) {
        if (pkg[k]) Object.keys(pkg[k]).forEach(add);
      }
    } catch { /* no package.json */ }
    // package-lock.json — names appear as keys; cheap substring presence check via raw read
    let lockRaw = '';
    for (const lf of ['package-lock.json', 'pnpm-lock.yaml', 'yarn.lock', 'requirements.txt', 'Cargo.toml', 'Cargo.lock', 'Pipfile', 'pyproject.toml']) {
      try { lockRaw += '\n' + fs.readFileSync(path.join(projectDir, lf), 'utf-8'); } catch { /* absent */ }
    }
    return { known, lockRaw: lockRaw.toLowerCase() };
  }

  let data = '';
  try {
    for await (const chunk of process.stdin) data += chunk;
  } catch { process.exit(0); }

  try {
    const input = JSON.parse(data);
    if (input.tool_name !== 'Bash') process.exit(0);
    const command = (input.tool_input || {}).command || '';
    if (!command) process.exit(0);

    let matched = null;
    for (const p of INSTALL_PATTERNS) {
      const m = command.match(p.re);
      if (m) { matched = { mgr: p.mgr, args: m[1] }; break; }
    }
    if (!matched) process.exit(0);

    const pkgs = parsePackages(matched.args);
    if (pkgs.length === 0) process.exit(0);

    const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const { known, lockRaw } = knownPackages(projectDir);

    // A package is "familiar" if it's in the manifest deps OR appears as a
    // token in any lockfile (covers transitive + already-installed).
    const unfamiliar = pkgs.filter(pkg => {
      const low = pkg.toLowerCase();
      if (known.has(low)) return false;
      // Word-boundary-ish presence in lockfiles (quoted or pathed)
      if (lockRaw.includes('"' + low + '"') || lockRaw.includes('/' + low) ||
          lockRaw.includes(low + '@') || lockRaw.includes(low + ' ') || lockRaw.includes(low + '==')) return false;
      return true;
    });

    if (unfamiliar.length === 0) process.exit(0);

    const checklist = [
      'SLOPCHECK — installing package(s) not already known to this project: ' + unfamiliar.join(', '),
      '',
      'Before installing an unfamiliar package, confirm it is legitimate (not a',
      'slopsquat or a hallucinated name):',
      '',
      '1. Is the spelling exactly right? Typosquats differ by one or two characters.',
      '2. Does the package actually exist on its registry, with real download counts',
      '   and a credible publisher? (npmjs.com / pypi.org / crates.io)',
      '3. Did YOU choose this package deliberately, or did it come from an LLM',
      '   suggestion that might be hallucinated?',
      '4. Is there a more-established alternative you already trust?',
      '',
      'This is a nudge, not a block. If the package is legitimate, proceed.',
    ];
    process.stdout.write(JSON.stringify({ decision: 'approve', additionalContext: checklist.join('\n') }));
  } catch { /* never block on errors */ }
  process.exit(0);
})();
