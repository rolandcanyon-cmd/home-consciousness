---
name: known-subscription-pool-login-history-query-bug
description: "subscription-pool-routes.test.ts login-history literal-route test fails deterministically; pre-existing, not caused by our fork, reported upstream fb-9ff9e624-a9c"
metadata: 
  node_type: memory
  type: project
  originSessionId: 862147a6-3bfd-4f03-8b1e-31f848541da9
  modified: 2026-09-03T14:59:43.840Z
---

Discovered 2026-09-03 during daily imessage-fork-maintenance CI check.
`tests/integration/subscription-pool-routes.test.ts > "serves bounded login
history on the literal route without confusing it for an account id"` fails
deterministically (2 local runs + fork CI, node 20 and 22, 7/8 other tests in
the file pass).

Test calls `ledger.recordStatus({accountId: 'claude-acct-1', status:
'needs-reauth', ...})` then GETs
`/subscription-pool/login-history?accountId=claude-acct-1&limit=1&summary=1`
expecting `count:1` + one episode back. Actual: `count:0`, `episodes:[]`,
`summary.statusEpisodes.total/open:0` — the accountId-filtered query isn't
finding the recorded status.

**Confirmed pre-existing, not a regression from any of our rebases**: reproduces
identically via `git worktree` on commit `c5ea44a8d` (our main tip *before* the
2026-09-03 rebase pulled in upstream `1b46533a7`). Not caused by our fork
customizations (those are confined to CI workflow files + the imessage
adapter). Reported upstream as **fb-9ff9e624-a9c**.

**Practical consequence:** don't re-diagnose this on future daily syncs. It's
a real bug (likely a query-param filtering issue or ledger-instance test
isolation bug), just not ours to fix and not new. If fork CI shows exactly
this one test + `Standards Enforcement Coverage` failing, that's the expected
baseline — check the job list for anything ELSE before treating the run as
healthy. See also [[known-instar-fork-standards-coverage-unfixable]].
