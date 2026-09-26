---
name: feedback-apply-fix-dont-just-note-it
description: "When a known_* memory records a fix that is cheap and reversible, apply it in the same session — a diagnosis note reads as \"done\" and stops future sessions from closing it"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 442663bb-9453-4547-aba6-1b73ecf13189
  modified: 2026-08-02T14:36:39.822Z
---

When I root-cause an issue and the fix is known, cheap, and reversible, I apply
it in that same session. I do not write a `known_*` memory that records the fix
for "later".

**Why:** on 2026-07-27 I correctly diagnosed the `dashboard-link-refresh` retry
loop and wrote a detailed memory including the exact fix. It then ran unfixed
for another full day — still producing ~85% of all scheduler log volume and
drowning the activity log every reflection run — because nothing re-surfaced the
action. A "known issue, don't re-diagnose" note is actively harmful when the fix
is known but unapplied: it teaches every future session to skip past the item
instead of closing it. Diagnosis notes read as done.

**How to apply:** after writing any `known_*` memory, ask "is the fix cheap and
reversible?" If yes — apply it now, then rewrite the note as RESOLVED with what
changed and how to revert. If it genuinely can't be applied (needs a decision,
credential, or risky change), open a commitment or action item so something
re-surfaces it; never let the fix live only inside a memory note. Take a backup
snapshot first when the target file is not git-tracked (`.instar/jobs.json` and
`config.json` both are not — verified 2026-08-02). See
[[known-job-config-edits-need-restart]], [[known-config-json-not-backed-up]].
