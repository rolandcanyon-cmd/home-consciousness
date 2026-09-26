---
name: Build and deploy workflow for instar
description: How to maintain, sync, and deploy the instar fork — PR strategy, daily sync, and install sequence
type: feedback
originSessionId: 67f47c70-56f3-4e73-8e04-1c28e1822ca4
---
## Fork Structure

- **Dev source**: `~/instar-dev` (same as `~/homebrew/lib/node_modules/instar` — symlinked or same path)
- **Remotes**: `origin` = upstream `JKHeadley/instar`, `fork` = `rolandcanyon-cmd/instar`
- **Installed via**: shadow-install at `.instar/shadow-install/node_modules/@rolandcanyon-cmd/instar` → `file:../../../../../instar-dev` (direct link, no copy)
- **Shadow-install deps**: both `@rolandcanyon-cmd/instar` AND `instar` point to the same `~/instar-dev`

## Maintenance Strategy — CORRECTED 2026-07-13

The "PR-based" strategy below was the ORIGINAL intent but is NOT what actually happens. Verified via `gh pr list --repo rolandcanyon-cmd/instar --state all` → zero PRs, ever. In practice: custom fixes are committed **directly to `main`** on the fork (e.g. commits `ceced62f7`, `c25121418` landed this way on 2026-07-13) and pushed straight through `git push fork main`. There is no branch/PR review step on this fork — it's a single-operator setup. Treat "keep custom work as tracked PRs" as aspirational/stale; the real workflow is direct-to-main commits, gated by the fork's own pre-push hooks (lint chain + release-note-fragment guard — see below).

1. **Daily sync**: `cd ~/instar-dev && git fetch origin && git rebase origin/main` (rebase custom commits on top)
2. **Build**: `cd ~/instar-dev && npm run build`
3. **No npm install needed** — shadow-install uses a `file:` reference; after build, dist/ is live
4. **Restart server**: `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland`
5. **Verify**: `curl -s http://localhost:4040/health`

## Pre-push gate on instar-dev (2026-07-13)

Pushing to `fork` main runs husky pre-push hooks: a lint chain, then `scripts/pre-push-gate.js`, which BLOCKS (no bypass — `INSTAR_PRE_PUSH_SKIP=1` does not cover this specific check) any push where a "release-relevant" file changed (workflow files, scripts, etc., per `scripts/release-relevant-paths.mjs`) without an accompanying `upgrades/next/<slug>.md` fragment (required sections: `## What Changed`, `## What to Tell Your User` — no backticks/camelCase inside this section, `## Summary of New Capabilities`; `## Evidence` is additionally required if `## What Changed` claims a bug fix). Fragments get consumed/renamed to `upgrades/<version>.md` at release-cut time (a `chore: release vX.Y.Z` commit bumping `package.json`). See `docs/specs/PRE-PUSH-RELEASE-FRAGMENT-GUARD-SPEC.md` for the full rule.

## GitHub Actions workflows on the fork (as of 2026-07-13)

Only 3 of 10 workflows on `rolandcanyon-cmd/instar` are actually needed and left **active**: `CI` (runs full test suite on every push — has occasional flaky tests, e.g. a timing-sensitive `subscription-enrollment-routes` integration test with a 2ms race), `Docs Coverage Weekly Audit` (fixed 2026-07-13 — see [[known-vault-master-key-mismatch]] session notes / commit `ceced62f7`), and `worktree-trailer-sig-check`.

**Disabled** (via `gh workflow disable "<name>" --repo rolandcanyon-cmd/instar`), all at Adrian's explicit request 2026-07-13:
- `Publish to npm` — no npm registry credentials configured on the fork; fork doesn't publish packages anyway (deploy is via the `file:` symlink above, not npm install).
- `Publish threadline-mcp` — same shape, single failed run from April, never retriggered.
- `class-closure-gate`, `decision-audit-gate`, `eli16-pr-gate`, `release-fragment-gate`, `runbook-pr-gate` — all trigger ONLY on `pull_request` events. Since this fork never has open PRs (confirmed: zero, always — everything goes direct-to-main), these never fire. Dead weight, safely disabled.

**Standing instruction from Adrian (2026-07-13)**: disable workflows that aren't needed, but always confirm with him before disabling anything new going forward — this was a one-time explicit sweep-and-ask, not a blanket auto-disable policy for future PR-only or newly-added workflows.

## Historical stale branches (unverified as of 2026-07-13, worth a cleanup pass)

- `docs/imessage-attachments-watcher`, `docs/attachments-watcher-upstream`, `feat/launchdaemon-enablement` — noted stale as of 2026-05-04, iMessage code already merged to main. Not re-checked this session.

## What NOT to do

- Don't `npm install /path/to/instar-dev` directly — installs as `instar` not `@rolandcanyon-cmd/instar`
- Don't modify `node_modules/` directly (no hot patching)
- Don't let custom commits pile up on main without being tracked as branches/PRs

**Why:** The shadow-install depends on `@rolandcanyon-cmd/instar`, not the unscoped `instar`. A direct install creates a second copy the server ignores. The file: symlink means builds are live immediately after `npm run build` — no reinstall needed.
