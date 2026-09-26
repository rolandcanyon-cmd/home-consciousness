---
name: known-instar-fork-standards-coverage-unfixable
description: "The instar fork's standards-coverage CI job fails permanently and has no downstream fix; do not try to guard or skip it"
metadata: 
  node_type: memory
  type: project
  originSessionId: 862147a6-3bfd-4f03-8b1e-31f848541da9
  modified: 2026-09-03T15:00:11.859Z
---

Diagnosed 2026-09-03. On rolandcanyon-cmd/instar the `standards-coverage`
("Standards Enforcement Coverage") CI job fails on EVERY push regardless of the
change under test: a fork's checkout cannot resolve the protected merge base on
canonical main (`fatal: Not a valid object name …`), so the check aborts before
measuring and fails closed ("zero-of-zero is never clean"). Its verdict is
constant and carries no information.

**Do not try to fix this downstream — I tried and was correctly refused.** The
Root self-wiring contract in `scripts/standards-coverage.mjs` asserts
`exactKeys(job, ['name','runs-on','permissions','steps'])` AND pins the ordered
step prefix and the check step's `env` map. So you can neither add
`if: github.repository == 'JKHeadley/instar'` (a fifth key fails the contract,
caught by `tests/unit/standards-coverage-ratchet.test.ts`) nor add a
`git fetch upstream` step to make the base resolvable. Both plausible fixes are
closed at the workflow layer, deliberately — the contract's comment says it is
"EXACT so the CI wiring cannot be quietly rearranged".

The fix belongs upstream inside `standards-coverage.mjs` (an unresolvable base on
a non-canonical repo could report the already-modelled
`protectedBaseStatus: 'not-assessed'` instead of `invalid`). Reported upstream as
**fb-034c177f-a3f**.

**Update 2026-09-03:** `tests/unit/standards-coverage-ratchet.test.ts` now
PASSES on the fork (38/38, both node 20 and 22) as of upstream commit
`1b46533a7`. The unit-test half of this issue appears resolved upstream —
only the `Standards Enforcement Coverage` CI job itself (below) is still
expected to stay red. Original addendum was filed as **fb-2046fe05-1ae**
(same-cause diagnosis, now superseded for the test — kept for history):
`tests/unit/standards-coverage-ratchet.test.ts` had failed on the fork for
the same reason (2 cases, arrived with the v1.3.1219 rebase; assertion traces
to #1926 W3.4) — passed locally (38/38) but failed in fork CI because
`git cat-file -e 1a5c86656bca^{commit}` succeeds in a full local clone that
fetched upstream, and failed in the fork's shallow CI checkout.

**Practical consequence:** the fork's CI is expected to stay red.
Do not read fork CI as a pass/fail gate — read the per-job list and ignore
`Standards Enforcement Coverage`. A permanently-red run masks real failures: it
hid a genuine `upgrade-guide-check` break for two weeks (08-15 → 09-01).

**General lesson:** before adding a condition to a CI job in instar, check
whether a self-wiring contract pins that job's shape. See also
[[known-instar-clean-fork]].
