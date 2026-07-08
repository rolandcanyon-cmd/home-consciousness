#!/usr/bin/env node
/**
 * secret-set.mjs — write ONE secret value into the agent's encrypted SecretStore
 * vault, reading the VALUE FROM STDIN. The write-side sibling of secret-get.mjs.
 *
 * Why stdin and never argv: a value passed as a command-line argument is visible
 * in the process table, in shell history, and — critically for an agent — in the
 * tool-call transcript. Reading from stdin lets a secret move from one trusted
 * process to another without ever being rendered as text anywhere.
 *
 * Containment contract (same rules as secret-get.mjs / secret-drop-retrieve.mjs):
 *   - The value is read from stdin ONLY. It is never echoed, logged, or printed.
 *   - ALL diagnostics go to stderr and are limited to key NAMES, lengths, and
 *     error categories — never values.
 *   - stdout stays EMPTY, so this composes safely inside a pipeline.
 *
 * Usage:
 *   node .instar/scripts/secret-get.mjs <srcKey> | node .instar/scripts/secret-set.mjs <dstKey>
 *   printf '%s' "$TOKEN" | node .instar/scripts/secret-set.mjs github_token
 *
 *   node .instar/scripts/secret-set.mjs <keyPath> --delete
 *     → removes the key. Reads no stdin.
 *
 * Exit codes:
 *   0 — key written (or deleted)
 *   1 — vault undecryptable, empty stdin, or write failed
 *   2 — usage error (missing key, cannot resolve the instar dist)
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import { createRequire } from 'node:module';

const args = process.argv.slice(2);
const doDelete = args.includes('--delete');
const keyPath = args.filter((a) => !a.startsWith('--'))[0];

if (!keyPath) {
  process.stderr.write('usage: <value on stdin> | secret-set.mjs <keyPath>   |   secret-set.mjs <keyPath> --delete\n');
  process.exit(2);
}

const require = createRequire(import.meta.url);
const candidates = [
  path.resolve('.instar/shadow-install/node_modules/instar/dist/core/SecretStore.js'),
  path.resolve('dist/core/SecretStore.js'),
];
let SecretStore = null;
for (const c of candidates) {
  if (fs.existsSync(c)) {
    try {
      ({ SecretStore } = require(c));
      break;
    } catch {
      // try the next candidate
    }
  }
}
if (!SecretStore) {
  process.stderr.write('secret-set: cannot resolve the instar SecretStore module (run from the agent home)\n');
  process.exit(2);
}

const stateDir = path.resolve('.instar');
let store;
try {
  store = new SecretStore({ stateDir });
} catch {
  process.stderr.write('secret-set: could not open the vault\n');
  process.exit(1);
}

if (doDelete) {
  try {
    store.delete(keyPath);
    process.stderr.write(`secret-set: deleted "${keyPath}"\n`);
    process.exit(0);
  } catch {
    process.stderr.write(`secret-set: failed to delete "${keyPath}"\n`);
    process.exit(1);
  }
}

// Read the value from stdin. Never echoed.
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const value = Buffer.concat(chunks).toString('utf8');

if (!value.length) {
  process.stderr.write('secret-set: refusing to store an EMPTY value (nothing on stdin)\n');
  process.exit(1);
}

try {
  store.set(keyPath, value);
} catch {
  process.stderr.write(`secret-set: vault write failed for "${keyPath}" (decrypt/master-key problem?). Do NOT repair or delete the vault — surface to the operator.\n`);
  process.exit(1);
}

// Read back to confirm the write landed, comparing LENGTH only — never the value.
let ok = false;
try {
  ok = String(new SecretStore({ stateDir }).get(keyPath) ?? '').length === value.length;
} catch {
  ok = false;
}
if (!ok) {
  process.stderr.write(`secret-set: wrote "${keyPath}" but read-back did not confirm — treat as FAILED\n`);
  process.exit(1);
}

process.stderr.write(`secret-set: stored "${keyPath}" (${value.length} chars)\n`);
process.exit(0);
