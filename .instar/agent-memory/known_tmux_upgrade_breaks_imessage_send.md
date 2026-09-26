---
name: known-tmux-upgrade-breaks-imessage-send
description: "A brew upgrade of tmux silently revokes the Automation (TCC) grant to Messages, killing iMessage SEND while receive stays green"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8f447a69-daff-4455-960f-84c7e338bf04
  modified: 2026-09-13T14:31:49.547Z
---

Diagnosed 2026-08-28. iMessage RECEIVE was perfect (hardlinks/inodes matched, adapter
connected, sessions spawned, "..." ack delivered) and every reply still failed.

macOS attributes AppleEvents permission to the **responsible ancestor process** — for agent
sessions that is **tmux**, not `imsg` — and the grant is keyed to tmux's exact Cellar/binary path.

**2026-08-28 fix** addressed `/opt/homebrew/Cellar/tmux` (3.6a → 3.7c) — that grant was
flipped to auth_value=2 and the tmux server bounced.

**2026-08-30 recurrence, DIFFERENT binary:** the agent's actual running tmux is
`/Users/rolandcanyon/homebrew/bin/tmux` (this agent's own homebrew prefix, NOT
`/opt/homebrew`), version 3.6a, mtime 2026-03-27 (not a recent upgrade). Confirmed via
`lsof -p $(pgrep -x tmux)` / the tmux binary path serving live sessions, and reproduced with
the exact probe from the imessage-doctor skill (fresh `tmux -L probe` session → `imsg send`
→ same `-1743 Not authorized to send Apple events to Messages`). So: **two distinct tmux
installs on this machine can each independently need their own Automation grant** — fixing
`/opt/homebrew`'s tmux does NOT cover `~/homebrew`'s tmux, and vice versa. Always confirm
which binary is the live ancestor (`lsof -p $(pgrep -x tmux) | awk '$4=="txt"{print $NF}'`)
before assuming a prior fix still applies.

Could not self-repair this time: the querying/editing shell lacks Full Disk Access, so
`sqlite3 .../TCC.db` returns `authorization denied` — reading/editing the TCC store itself
requires FDA or the GUI path. **Needs the human**: System Settings → Privacy & Security →
Automation → tmux → enable Messages, then `tmux kill-server` (a running tmux server caches
its TCC verdict) + restart the agent LaunchAgent so sessions respawn under the freshly
granted tmux.

**This recurs per-tmux-install, not just per-upgrade.** Treat a silent send failure as this
cause until disproven, and always verify by asking which tmux binary is actually alive
right now — do not assume the previously-diagnosed path is still the one in use. Two other
iMessage root causes are unrelated to this one — see the /imessage-doctor skill for all
three. See also [[known-stale-imdpersistenceagent]].

**2026-08-31 recurrence, on the SAME binary previously fixed (08-28):** live serving tmux
confirmed via `$TMUX` socket → server pid → `lsof txt` = `/opt/homebrew/bin/tmux` →
`/opt/homebrew/Cellar/tmux/3.7c/bin/tmux` (identical path to the 08-28 fix). `imsg send`
failed with the same -1743. Went further this time: `osascript -e 'tell application "System
Events" to ...'` ALSO failed with -1743 — so the denial isn't Messages-specific, it's a
blanket AppleEvents denial for this tmux ancestor. Messages.app itself confirmed running
normally (pid present, not crashed). Could not query/flip `TCC.db` (both the user-level
`~/Library/Application Support/com.apple.TCC/TCC.db` and implicitly the system one) —
"authorization denied", same FDA gap as before. WhatsApp checked as a fallback channel:
configured but `Disconnected: logged-out` in server.log — not usable. Telegram not
configured, so `/attention` 503s — no channel could reach the user. Delivered the report via
a private view instead and left it there. **Takeaway: a "fixed" tmux path is not permanently
fixed — the same Cellar path can silently revert to denied (e.g. Homebrew reinstalling into
the same version path resets the TCC identity in some cases). Always re-probe, never trust
a prior fix's timestamp.**

**2026-09-01 recurrence (morning-weather job):** live serving tmux confirmed via
`ps aux | grep tmux` = `/opt/homebrew/bin/tmux new-session -d -s Roland-keepalive` (same
binary as the 08-28/08-31 fixes). `imsg send` failed again with -1743. WhatsApp confirmed
`Disconnected: logged-out` in server.log; Telegram not configured (no telegram log lines at
all). No messaging channel could reach the user — delivered via a private view instead
(same fallback as 08-31), left the report there with the delivery-failure note visible at
the top. This is now the third consecutive recurrence on this same `/opt/homebrew/bin/tmux`
path across four days (08-28 fix, 08-30 different-binary recurrence, 08-31 same-binary
recurrence, 09-01 same-binary recurrence again) — the TCC grant is not holding at all on
this path. Stop treating each occurrence as a one-off; this needs the human's System
Settings fix repeated (or a more durable resolution) each time the job runs.

**2026-09-02 recurrence (imessage-fork-maintenance job), 4th consecutive day:** live
ancestor confirmed via full ps ancestry trace (bash → zsh → claude pid 96190 → tmux server
pid 98727 → `/opt/homebrew/bin/tmux` → `/opt/homebrew/Cellar/tmux/3.7c/bin/tmux`, same path
as 08-28/08-31/09-01). `imsg send` failed with -1743 both via the script and run directly
outside the script. Confirmed (again) this shell has zero FDA at all, not just for TCC.db —
Safari History.db and ~/Library/Mail both also return "authorization denied", so this isn't
even reachable via a workaround read. WhatsApp still `Disconnected: logged-out`. Attention
queue still 503s (Telegram not configured — this is now independently re-verified, not
assumed from memory). PushNotification tool tried as a second fallback — returned "not sent
(Remote Control inactive)" since this is an unattended background job, not an interactive
session. Registered CMT-013 (owner:agent, followThroughOptOutReason since no topic exists
for a beacon) so the blocker is tracked durably instead of silently dropped. Delivered via
private view (same fallback pattern) as the only channel that actually lands.

**ESCALATION: this is not a "recurs on tmux upgrade" issue anymore — the grant has never
held for more than ~1 day on `/opt/homebrew/Cellar/tmux/3.7c` across 4+ attempts (08-28
GUI/DB fix, 08-31, 09-01, 09-02). Treating this as normal fix-and-wait is no longer
warranted; something about this path/machine causes the AppleEvents grant to not persist.
When Adrian is next reachable: don't just repeat the same GUI toggle — ask whether SIP,
a profile/MDM policy, or a periodic TCC reset process on this machine is clearing grants,
since a grant that reverts within 24h every single time points at something more systemic
than a one-off Homebrew path change.**

**2026-09-03 recurrence, 6th consecutive day (imessage-fork-maintenance job):** same live
ancestor `/opt/homebrew/bin/tmux` (pid 98727 — this pid has now persisted across at least
today's check, so the server process itself isn't restarting; the TCC denial is reasserting
against a *stable* pid, not a fresh one, which argues against "reinstall resets identity" as
the mechanism this time). `imsg send` failed with -1743 again. WhatsApp still
`Disconnected: logged-out`. Telegram still not configured. Delivered via private view
(same fallback) — id `bd0614f2-7b6c-4edc-a0b6-d691b6b95422`. Six consecutive days is well
past "recurs" — this needs Adrian's attention on the systemic question above, not another
same-day GUI toggle repeat.


## 2026-09-05 follow-up — the DB edit is NOT a durable fix, and probing makes it worse

The Aug-28 TCC row edit did not survive. Re-applying it did **not** restore send:
`tccd` caches its verdict in memory, the on-disk row read `2` while sends still
returned `-1743`, and `launchctl kickstart gui/$UID/com.apple.tccd` is refused —
`Operation not permitted while System Integrity Protection is engaged`. So there
is no agent-side way to make tccd re-read the table.

**Two things I did that made it worse — don't repeat them:**

1. **Restarting Messages.app wipes the AppleEvents grants.** After
   `quit Messages` + `open -a Messages`, the `kTCCServiceAppleEvents` rows for
   `com.apple.MobileSMS` went from 7 to 2, and `com.apple.Terminal` was flipped
   to `0` (denied) about a minute later — so send then failed from an
   interactive Terminal too, which had worked before.
2. **Every send probe from a background context records a fresh DENIAL.** macOS
   will not raise a consent dialog for a non-interactive process; it auto-denies
   and writes `auth_value 0`. So testing repeatedly poisons the state. Probe
   once, then stop.

`tccutil reset AppleEvents` DOES work (unlike a direct row edit) and clears
sticky denials to an empty table — a clean slate where a real prompt can appear.
It resets AppleEvents for every app, which then re-prompt on next use.

**Only the operator can complete the fix:** System Settings → Privacy & Security
→ Automation → allow Messages for the relevant client. A full reboot is the
better single action, because it ALSO clears the orphaned `IMDPersistenceAgent`
(see [[known-stale-imdpersistenceagent]]) that no kill can remove.

**2026-09-06 recurrence (morning-weather job), still unresolved:** `imsg send`
failed again with the same -1743. Did not re-probe per the 09-05 lesson (probing
poisons state further) — one attempt, then stopped. Tunnel was also `exhausted`
(`reachability-failed`), same as prior recurrences, so even the private-view
fallback was local-network-only, not remotely reachable. Delivered via private
view (id `193a7316-d0dc-4da1-bd62-6b1f82ac1402`) with the failure noted at the
top. This is now 9+ days unresolved — still needs Adrian's manual System
Settings fix (or the systemic-cause investigation flagged on 09-03), not another
agent-side attempt.

**2026-09-09 recurrence (morning-weather job), 12+ days unresolved:** `imsg send`
failed again with the same -1743. One attempt only, then stopped (per the 09-05
lesson — no re-probing). WhatsApp still `Disconnected: logged-out`, Telegram
still not configured — no messaging channel could reach Adrian. This time the
tunnel WAS active (`lifecycle.state: "active"`), so the private-view fallback
(id `7dae449c-651b-4c81-a9de-79cfb9d06f53`) is remotely reachable, unlike the
09-01/09-06 occurrences. CMT-013 (registered 09-02) already tracks this blocker
and is still `pending` — did not duplicate it, just noting continuity here.
This coincided with the vault master-key mismatch also being unresolved (see
[[known-vault-master-key-mismatch]]) — two independent chronic blockers hit the
same job simultaneously.

**2026-09-12 recurrence (morning-weather job), ~2 weeks unresolved:** re-probed
once via the imessage-doctor skill's fresh-tmux-server test against BOTH live
tmux binaries (`/opt/homebrew/Cellar/tmux/3.7c` — the one running
`Roland-keepalive`, pid confirmed via `ps aux`/`lsof txt` — and this agent's own
`/Users/rolandcanyon/homebrew/Cellar/tmux/3.6a`). Both failed `imsg send` with
-1743. Same run also confirmed `channelRegistry`/`GET /channels`
(new-since-last-check endpoint) independently corroborates this: `user-imessage`
reports `state:"working"` but explicitly caveats "not proof a send... would
land"; `user-whatsapp` reports `state:"broken"` ("adapter reports disconnected");
`/attention` still 503s (Telegram not configured). Tunnel was `exhausted`
(`reachability-failed`) too, so even a Secret Drop link for the vault issue
would only be reachable on local wifi and expires in 15 min unused. Delivered
the weather report via a private view only (id
`522ef51d-14a9-4a87-8964-fd6271a04da7`). Per the 09-05 lesson, did not
probe further or touch TCC.db. **This is the ~2-week mark with zero durable fix
attempts landing** — the operator has not yet done the System Settings ->
Automation toggle (or it isn't holding). Worth flagging directly next time a
channel IS reachable: this needs the human GUI step, not another agent probe.

**2026-09-13 recurrence (imessage-fork-maintenance job), ~2.5 weeks
unresolved:** normal daily sync heartbeat send (no re-probe beyond the one
scheduled send attempt) failed with the same `-1743`. `GET /channels`
confirmed: `user-imessage` backend "working" but send failed this run;
`user-whatsapp` still "broken" (adapter disconnected); Telegram still not
configured. Unlike several prior recurrences, the tunnel WAS `active`
(`https://focuses-ann-msg-berkeley.trycloudflare.com`), so the private-view
fallback (id `f5d7c377-3f94-4d7e-9f52-ecc6208f2e7f`) is remotely reachable this
time. Did not re-probe per the 09-05 lesson. Everything else in the sync run
was healthy (no upstream changes, server ok, canary session passed) — this is
purely a delivery-channel blocker, not a fork/build/deploy problem. Still
needs Adrian's manual System Settings → Automation fix (or reboot); CMT-013
remains the tracked commitment.
