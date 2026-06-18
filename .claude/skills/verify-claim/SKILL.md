---
name: verify-claim
description: Verify a claim that something is built/wired/working using the 4-tier protocol (Existence -> Substantive -> Wired -> Data-Flow). Use before saying "shipped", "wired in", or "it works".
metadata:
  user_invocable: "true"
---

# /verify-claim

Goal-backward verification of a single claim about the codebase. Cherry-picked from the GSD verifier methodology during the GSD-Instar integration spike.

Use this BEFORE you tell a user something is "shipped", "wired in", "running", "done", or "working" — and any time green CI + passing unit tests are NOT sufficient evidence that a feature is actually alive (they often aren't: a component can be defined, compile, and have unit tests yet never be instantiated in the real boot path).

## The 4-tier protocol

Run the levels in order. A claim is VERIFIED only if it passes all applicable levels. Stop and report the first level that fails.

**Level 1 — EXISTENCE.** Does the artifact exist? (`[ -f path ]`)

**Level 2 — SUBSTANTIVE.** Is it real, not a stub? (`wc -l`, grep for TODO/FIXME/not-implemented). A file that exists but is 3 lines of stub fails Level 2.

**Level 3 — WIRED.** Is it imported AND invoked from the real path? This is the level green tests most often skip. Grep for the import, then for construction (`new X` / `X(`) NOT just the import, then — for server features — confirm it is mounted/started in `src/commands/server.ts` / `src/server/AgentServer.ts`. A component imported but never constructed, or constructed but never started, fails Level 3: it is ORPHANED dead code even with green unit tests. (Exact failure from the "verify a component is actually wired" lesson — PR #334 shipped sentinels as dead code with a false "wired into server startup" claim.)

**Level 4 — DATA-FLOW.** Does real data actually flow through it? Hit the endpoint and confirm a real payload (not 503/empty); confirm a renderer shows real source data; write-then-re-read a store through a fresh instance.

## Status taxonomy (report one per claim)

- VERIFIED — passes all four.
- HOLLOW — wired but no real data flows.
- ORPHANED — exists + substantive but not wired (dead code).
- STUB — exists but not substantive.
- MISSING — does not exist.

## Output

State the claim, the level reached, the status, and the exact commands you ran with their results. If anything below VERIFIED, say so plainly — do NOT round up to "done".

## When to use

- Before any "shipped" / "wired in" / "running" / "it works" message.
- When green CI + unit tests are your only evidence (they prove the code COMPILES and works in isolation — not that it is instantiated in production).
- During /build Phase 3 VERIFY, on each must-have.

## Why

Cherry-picked from the GSD verifier role. The insight: task completion is not goal achievement. A placeholder counts as a completed task but fails the goal. Goal-backward verification checks whether the supporting code actually exists, is substantive, is wired, and carries real data — the four ways "done" silently isn't.
