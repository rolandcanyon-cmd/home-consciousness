---
name: project-goodies-upgrade-and-repo-move
description: the-goodies is being upgraded; the primary the-goodies-typescript moves to the adrianco account and the rolandcanyon-cmd copy is deprecated; Corfe pilots the upgrade first
metadata:
  type: project
---

Told by Adrian on **2026-09-13**. Note-only for now — no action requested yet.

**Three things are changing:**

1. **Upgrade work is starting on `the-goodies`** (FunkyGibbon / Blowing-Off / Oook /
   Inbetweenies — the smart-home knowledge graph stack).
2. **The PRIMARY `the-goodies-typescript` moves to the `adrianco` account**, alongside
   the main `the-goodies` repo. Until now no adrianco TypeScript upstream existed, which
   is why the rolandcanyon-cmd copy was owned rather than a fork — that is no longer true.
3. **`rolandcanyon-cmd/the-goodies-typescript` is DEPRECATED.** Treat it as read-only
   history. Do not invest in it. See [[project-github-repos]].

**Rollout order — Corfe first, here second.** [[project-corfe-uk-install]] is mid-upgrade
as of 2026-09-13. When Corfe's upgrade completes, the learnings from it drive the upgrade
on this house. So the correct posture right now is WAIT, not start.

**How to apply:** before touching anything in `the-goodies-typescript` — especially the
open KittenKong sync-push defect in [[kittenkong-update-sync-push-broken]] — check whether
the work now belongs in the adrianco repo instead. Fixing a bug in a deprecated repo is
wasted effort, and that note predates this change (2026-07-15), so it reads as live work
when it may no longer be. Do not start the local upgrade until Adrian says Corfe is done.
