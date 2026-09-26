---
name: known-macos-passwords-app-unreadable
description: The macOS Passwords app (iCloud Keychain) cannot be read by any CLI — use Secret Drop + the encrypted vault instead
metadata: 
  node_type: memory
  type: reference
  originSessionId: 30164ac5-1517-43cb-bb47-5b01b51408c9
---

**The macOS Passwords app is NOT readable by Instar, and never will be.** Its items live in iCloud Keychain ("Local Items"), which the `security(1)` CLI does not expose — `security list-keychains` only returns `login.keychain-db` and `System.keychain`. Attempting `security find-generic-password` against Passwords-app items either finds nothing or triggers a **GUI authorization prompt that hangs the Bash tool forever**. Do not go down this path.

**The correct way to give the agent a credential** (verified working 2026-07-08):

1. Create a one-time link: `POST /secrets/request` with a `fields` array (multi-field supported, e.g. username + password).
2. Send the user the link. It's single-use, expires in 15 min, CSRF-protected. **Localhost links are refused by the outbound guard** — if the tunnel is down, use the LAN URL (`http://<lan-ip>:4040/...`; the server binds `*:4040`, so this works from a phone on the same WiFi).
3. The submitted value persists store-first into the AES-256-GCM encrypted vault.
4. Promote it to a stable name so it survives the one-time token:
   `node .instar/scripts/secret-drop-retrieve.mjs <token> <field> | node .instar/scripts/secret-set.mjs <stable_name>`
5. Read it later: `node .instar/scripts/secret-get.mjs <stable_name>` (value → stdout only; pipe it, never echo).

**`secret-set.mjs` was written on 2026-07-08** (commit `bfeefca`) because `secret-get.mjs` existed but nothing could WRITE a named key. It reads the value from **stdin, never argv**, so secrets never appear in the process table, shell history, or an agent transcript. `--delete` removes a key.

The vault is `.instar/secrets/config.secrets.enc` (gitignored). If it ever reports DECRYPT-FAILED: do **not** repair, rotate, or delete — surface to the operator. See [[project-ambient-weather-login-blocked]] for the first real use.
