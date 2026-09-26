---
name: known-instar-upgrades-next-convention
description: instar pending release fragments go in upgrades/next/<slug>.md, not upgrades/ and not upgrades/NEXT.md
metadata:
  type: project
---

Learned 2026-09-03 by getting it wrong first.

A pending per-PR release fragment belongs at **`upgrades/next/<slug>.md`** — a
SUBDIRECTORY. Descriptive slugs are correct there.

Files placed directly in `upgrades/` must be semver-named (`1.2.3.md`),
`NEXT.md`, or `*.eli16.md`, or `tests/unit/upgrade-guide-check.test.ts` fails
them. That test uses `fs.readdirSync(upgradesDir)`, which does NOT recurse — so
anything under `upgrades/next/` is exempt by construction. That is the whole
reason the subdirectory exists.

`upgrades/NEXT.md` still parses but `scripts/pre-push-gate.js` explicitly calls
it **legacy**: `"upgrades/next/<slug>.md (or legacy upgrades/NEXT.md)"`. Do not
use it, and never consolidate several fragments into one file — the release flow
consumes them per-fragment.

**The failure mode I hit:** two fragments sat in `upgrades/` with descriptive
names and failed CI for two weeks. I read it as "misnamed" and merged them into
`upgrades/NEXT.md`. They were **misplaced**, not misnamed — the fix was `git mv`
into `upgrades/next/`. The tell I initially missed: the paired side-effects
artifact already cited the intended path as `upgrades/next/<slug>.md`.

**General lesson:** when a naming rule seems to make a legitimate file
impossible, check whether the file is in the wrong DIRECTORY before inventing a
new name. Also: read the gate script for the convention rather than inferring it
from the test's regex alone. See also
[[known-instar-fork-standards-coverage-unfixable]].
