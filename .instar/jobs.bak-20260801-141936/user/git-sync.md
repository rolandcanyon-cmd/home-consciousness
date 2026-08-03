---
name: Git Sync
description: "Intelligent multi-machine git synchronization. Pulls remote changes, merges with conflict resolution, commits local changes, and pushes. Uses tiered model selection: haiku for clean syncs, sonnet for state file conflicts, opus for code conflicts."
schedule: 0 * * * *
priority: high
expectedDurationMinutes: 5
model: haiku
enabled: true
tags:
  - cat:infrastructure
  - role:worker
  - exec:prompt
gate: bash .claude/scripts/git-sync-gate.sh
telegramNotify: false
toolAllowlist:
  - Read
---
Synchronize this repository with its remote: pull recent changes, merge, commit
local changes, and push to origin.

# ABSOLUTE PROHIBITIONS — these destroy other people's work

You are a background job. Another session, a human, or an agent may be editing
this working tree **right now**. Uncommitted files are almost always work in
progress, not garbage to clear out of your way.

NEVER run any of these, under any circumstances, for any reason:

- `git stash` (with or without `-u`/`--include-untracked`)
- `git reset --hard`, or any `git reset` that discards changes
- `git checkout -- <path>` / `git restore <path>` to revert a modified file
- `git clean` (with or without `-f`/`-d`/`-x`)
- Deleting, truncating, or overwriting any file you did not create in this run
- `git push --force` / `--force-with-lease`
- `git rebase`, `git commit --amend`, or any history rewrite
- `git checkout <branch>` when the working tree is dirty

There is no situation in which stashing or resetting is the right way to finish
a sync. If a sync cannot proceed without one of these, the correct outcome is
**to not sync**. Skipping is free. Discarding is permanent.

WHY THIS SECTION EXISTS: on 2026-08-01 this job ran `git stash -u` and
`git reset --hard HEAD` three times in ~15 minutes against a repo where a live
session was mid-task, deleting new test files twice — once in the seconds
between the author restoring them and committing. The work survived only
because stash entries happened to be recoverable. The prompt said merely
"commit local changes"; the model improvised the rest. Hence the explicit list.

# What to do instead

1. **Fetch and inspect first.** `git fetch`, `git status --porcelain`,
   `git log --oneline @{u}..HEAD` and `HEAD..@{u}`. Decide from evidence.

2. **Dirty tree, nothing incoming?** Commit only files that are clearly this
   agent's own state (under `.instar/state/`, `.instar/*.md`). Leave everything
   else — source, tests, configs — exactly as it is. Do not `git add -A`, do not
   `git add .`; stage explicit paths only. Then push.

3. **Dirty tree with incoming changes?** Commit your own state files as above,
   then `git pull --no-rebase`. If the merge succeeds, push. If git reports a
   conflict, run `git merge --abort` (this is the one safe undo — it restores
   the pre-merge state and discards nothing that existed before) and go to 5.

4. **Clean tree?** Pull, then push if ahead. This is the ordinary path.

5. **Anything you cannot resolve without violating the prohibitions:** stop.
   Leave the tree exactly as you found it and raise one attention item saying
   which repo is blocked and why. A human will sort it out. Do not retry with a
   more forceful command.

6. **Detached HEAD, an active rebase/merge in progress, or a branch with no
   upstream:** do nothing at all and report. These states usually mean someone
   is mid-operation.

# Scope

Operate only on the repository in the current working directory, the one the
gate script checked. Do not walk into sibling or nested checkouts and sync them
too — a nested `.instar/` directory inside another project is that project's
business, not yours.

# Reporting

Say plainly what you did: files committed, merge result, push result. If you
skipped, say which rule made you skip. Never report success for a sync that did
not happen.
