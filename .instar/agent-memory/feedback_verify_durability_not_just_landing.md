---
name: feedback-verify-durability-not-just-landing
description: A config override that landed once is not proven durable — regeneration silently reverts any key outside the preserved set
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 1f7801e3-fd33-431a-9c27-2fc4fffc3174
  modified: 2026-07-31T03:02:27.429Z
---

When I verify a fix "landed" (the API now reports the new value, the bad signal stopped), I have
proven one thing: it was true at that moment. I have NOT proven it will still be true tomorrow.
Local overrides to generated files get wiped by the next regeneration, and the revert is silent —
no error, no log line, nothing except the old behavior quietly resuming.

**Why:** Instar regenerates built-in job/hook files from shipped templates on update, build, and
deploy. Only an explicitly preserved key set survives — for `.instar/jobs/schedule/<slug>.json`
that is `enabled`, and CLAUDE.md documents exactly that key and no other. `priority` is not
preserved, so the low→medium fix in [[known-low-priority-jobs-quota-shed]] survived 28 hours and
was wiped by a wholesale rewrite of all 33 schedule files (identical mtimes), one second before a
scheduler restart picked up the reverted values.

**How to apply:**
1. Before editing a generated file, ask *which keys are preserved?* If the key I'm changing is not
   on that list, my edit has a shelf life. Say so in the note, and prefer the upstream fix.
2. Add a re-verify step to the deploy/build routine, not only to the session that applied the fix.
   The natural checkpoint is right after `npm run build` + restart in
   [[feedback-build-deploy]] — that is the moment the revert happens.
3. State findings with their scope. "Verified `GET /jobs` reports medium as of 07-29 11:00Z" is
   honest; "RESOLVED" implies durability I did not test.
4. A recurrence of a symptom I marked resolved is a **durability** question first, not a
   re-diagnosis. Check the file mtimes before re-deriving the root cause — a batch of identical
   mtimes is the regeneration fingerprint.

5. **A quiet window is not evidence — the triggering event is.** This revert is caused by an
   *event* (regeneration), not by decay over time, so elapsed calm carries zero information about
   durability while *feeling* like reassurance. Concretely (07-31 03:05Z): 12 hours with all four
   jobs at `medium` and zero quota skips is a real *behavioral* pass, but the prior application of
   the same fix lasted 28 hours — 12h sits inside that envelope and settles nothing. Report the
   behavioral result and the durability question as two separate claims, and probe for the event
   directly (compare mtimes across all 33 schedule files; a jump to a new shared mtime = a
   regeneration ran, re-check `priority` immediately). Recorded as LRN-006.

Related: [[known-job-config-edits-need-restart]] (writing to disk is not in effect until restart)
and [[feedback-apply-fix-dont-just-note-it]] (a cheap fix belongs in the diagnosing session). This
note completes the chain: written → in effect → **still in effect**.
