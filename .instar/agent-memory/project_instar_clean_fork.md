---
name: Instar clean fork requirement
description: We should run a clean build of our fork (instar-dev) plus our own commits — not the npm-published version
type: project
originSessionId: 9ecfd839-8359-4ad6-a608-aa8f8a1025a1
---
We should always be running a clean build of our fork plus our own commits, not the npm-published instar version.

**Why:** The npm-published version lags behind our fork. Fixes made in instar-dev may not be reflected in the installed version. A rebase/sync in instar-fork (the @rolandcanyon-cmd/instar package) can drop local patches if they weren't committed before the merge.

**How to apply:** When investigating why a fix isn't working, first check that the installed version (`instar --version` or `cat ~/homebrew/lib/node_modules/instar/package.json`) matches instar-dev HEAD. If it doesn't, rebuild from instar-dev and reinstall via npm link or local install, then restart via launchctl.

Current state as of 2026-04-27: shadow-install = v0.28.75 + destructive containment (18a6735b). Zero divergence from upstream — all 17 custom iMessage commits were superseded by upstream's evolved versions. instar-dev/main = JKHeadley/instar/main = rolandcanyon-cmd/instar/main at 18a6735b.

Rebase conflict pattern: When upstream force-pushes or diverges significantly from our base commit (merge-base), git sees add/add conflicts on iMessage files. Resolution: verify upstream has all our features, then git reset --hard origin/main (clean reset, not rebase). This is correct when zero divergence is the goal.
