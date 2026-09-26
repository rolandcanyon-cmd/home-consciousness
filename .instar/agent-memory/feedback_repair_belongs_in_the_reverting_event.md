---
name: feedback-repair-belongs-in-the-reverting-event
description: "When a setting keeps reverting, put the repair inside the recurring event that reverts it — re-applying by hand is guaranteed to lose"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f7b20b98-f422-4c09-964f-cf8cb09311c1
  modified: 2026-08-01T07:04:30.225Z
---

When a setting reverts repeatedly, the useful question is not "what value should it be?" but
**"what EVENT reverts it, and how often?"** Find that event, then put the repair *inside* it.

**Why:** a hand-applied override that is outside the preserving mechanism will be wiped every
time the event fires. Re-applying it manually converts a permanent problem into a recurring
chore that depends on remembering — which is exactly the failure mode
"Structure > Willpower" names. Landing the value once is not the fix; owning the reverting
event is.

**How to apply:** correlate the reverted files' mtimes against the activity log to identify
the event (a deploy job, an update, a restart). If that event is something I control — a
skill, a job, a script — add the repair to it, positioned after the step that destroys the
value and before the step that consumes it. If the event is upstream and not mine, the fix is
a feedback report, not another local edit. Concrete case: schedule-file `priority` was reverted
daily by the `imessage-fork-maintenance` deploy, and the repair now lives in that skill's
Deploy step, next to the two identical pre-existing repairs for the node symlink and
node-candidates.json. See [[known-low-priority-jobs-quota-shed]] and
[[feedback-verify-durability-not-just-landing]].

**Corollary — identify the reverting STEP, not just the reverting event (2026-08-01).** Naming
the event is only half the work; the repair still has to sit after the exact step that destroys
the value. That first attempt put the repair before the deploy's `launchctl kickstart` because
`npm install` looked like the regenerator. It wasn't: the npm artifacts carried months-old
mtimes while every regenerated file landed one second *between* `scheduler_stop` and
`scheduler_start` — regeneration is part of **boot**, so a repair placed before the restart is
wiped by the very boot it precedes. A correctly-identified event with a wrongly-placed repair
is still zero repairs. **The test is mtime ordering against the `scheduler_stop`/`scheduler_start`
pair in `activity-*.jsonl`, never the narrative order of the deploy script** — and when the
consuming step is the boot itself, the repair must go after it and force a second restart.
