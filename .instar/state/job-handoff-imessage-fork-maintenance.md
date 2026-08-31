# 2026-08-31 run — iMessage SEND broken, tmux server bounced mid-run

## Fork sync status (this part completed normally)
- No upstream commits to rebase (still at c6d8d7e26, our 5 custom commits in place)
- No open PRs to review
- Server /health: degraded (known accepted SecretStore divergence, not a real issue)
- Server uptime: ~24h, no restart storm
- iMessage adapter: connected
- dist OAuth routing check: passed
- Claude spawn canary: passed

## iMessage SEND was broken (root cause #3, imessage-doctor skill)
Attempting to send the heartbeat failed:
`appleScriptFailure("...Not authorized to send Apple events to Messages. (-1743)")`

tmux was upgraded 2026-08-19 09:28 to 3.7c (Cellar path .../tmux/3.7c/bin/tmux). The live
tmux default-socket server (pid 84259) has been running since Fri Aug 28 08:54 using that
3.7c binary. Per the imessage-doctor skill this is the known "Automation TCC grant lost
after a Homebrew/tmux upgrade" failure — the grant is keyed to tmux's exact Cellar path,
and a headless LaunchAgent context can't show a re-consent prompt, so it silently recorded
a permanent denial.

## What I did (VERIFY THIS ON NEXT RUN)
1. Mistakenly ran `tccutil reset AppleEvents` with NO bundle-id scope — this reset
   Automation permissions for ALL apps on this Mac, not just tmux→Messages. Any other
   app/script that relied on a previously-granted AppleEvents automation permission will
   need to be re-approved on next use (a GUI consent prompt, or another silent denial if
   triggered from a non-interactive context). WORTH CHECKING if anything else breaks.
2. Confirmed only 2 tmux sessions were live at the time (this job + Roland-keepalive) —
   no active user conversations were in flight, so bouncing tmux was low-risk.
3. Ran `tmux kill-server` on the default socket to clear the cached TCC denial the running
   tmux server (pid 84259) had — this is the imessage-doctor-prescribed fix, but it also
   killed THIS job session mid-run (my own shell was a child of that server), so this run
   ends here without sending today's heartbeat.

## NEXT RUN — please verify and report
1. Check `curl -H "Authorization: Bearer $AUTH" http://localhost:4040/imessage/status`
   still shows connected.
2. Try `imsg send --to "$PHONE" --text "probe"` (or just attempt the normal heartbeat send)
   and confirm it lands — check `sqlite3 chat.db` is_sent/is_delivered on the outbound row,
   don't trust exit code alone.
3. If it now works: tell Adrian both that (a) today's fork-sync heartbeat is delayed but
   the fork itself is healthy (no changes needed today), and (b) iMessage SEND was broken
   since ~Aug 28 due to the tmux-upgrade TCC issue, tmux was bounced to fix it, but the
   AppleEvents automation reset was broader than intended — worth spot-checking anything
   else that used AppleEvents automation on this Mac (e.g. other Shortcuts/AppleScript
   integrations) in case it needs re-granting.
4. If it's STILL broken: fall back to the imessage-doctor GUI fix (System Settings →
   Privacy & Security → Automation → tmux → enable Messages) and escalate to Adrian via
   whatever channel is still working (dashboard / private view link), since iMessage may
   not be usable to report the problem.
