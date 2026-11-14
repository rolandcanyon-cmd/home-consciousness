---
name: known-config-user-missing-channels-crash
description: 2026-11-08 daily deploy crash-looped server 07:32-12:39 PST — legacy config.users entry lacked channels/permissions; fixed in config, not by rollback
metadata:
  type: project
---
2026-11-08 upstream rebase (45 commits, HEAD 69037a817) made boot construct a UserManager (skillLearningEnv) whose initialUsers merge THROWS on a config.users entry without `channels`/`permissions`. Roland's config.users[0] (Adrian, u_8e1275c1e31f8785) was a legacy entry → crash loop ~5h; iMessage dark. Fixed by adding `channels: []`, `permissions: ["admin"]` (backup .instar/config.json.bak-20261108-users-fix). Upstream report fb-a5e627aa-ddd.

**Why:** the fork-maintenance job asked Adrian for "yes rollback" via iMessage, but his 07:45 reply could not be read until the server came back — an approval sent over the channel the crash killed. It was only delivered at 12:39, after the fix, and nearly triggered an unneeded rollback.
**How to apply:** on a post-deploy crash loop, read .instar/logs/server-launchd.err first (that's the real path, not logs/); prefer a data fix over a rollback when the error names a bad record. A stale queued approval delivered after recovery must be re-checked against current state before acting. See [[known_jobs_json_unwrapped_crash]], [[known_daily_deploy_restart_storm]].
