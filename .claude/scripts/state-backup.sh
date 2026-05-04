#!/bin/bash
# state-backup.sh — back up identity/learning state to the state-backup
# branch on origin. Designed to run as an hourly job. No-op if nothing changed.
#
# How it works:
#   1. AGENT_DIR = the parent project (.instar/ lives here).
#   2. WORKTREE  = a persistent git worktree of the state-backup branch
#                  at .instar/.backup-worktree/.
#   3. ITEMS     = whitelist of paths to copy from AGENT_DIR/.instar/ into
#                  WORKTREE/.instar/. Anything not on the whitelist (config.json,
#                  message DBs, logs, runtime state) is excluded.
#   4. After copying, if `git status --porcelain` is empty, we exit 0 with no
#      commit and no push (zero-effort skip).
#   5. Otherwise commit and push to origin/state-backup.
#
# Designed to be safe to run any number of times. Set up once by bootstrap.sh.

set -euo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKTREE="${AGENT_DIR}/.instar/.backup-worktree"
LOG_TAG="[state-backup]"

if [[ ! -d "${WORKTREE}/.git" && ! -f "${WORKTREE}/.git" ]]; then
    echo "${LOG_TAG} worktree missing at ${WORKTREE}; aborting" >&2
    exit 1
fi

# Whitelist of paths under AGENT_DIR/ to back up. Each entry is a path relative
# to AGENT_DIR. Files are copied; directories are mirrored with --delete so
# removals propagate.
ITEMS=(
    ".instar/AGENT.md"
    ".instar/MEMORY.md"
    ".instar/USER.md"
    ".instar/soul.md"
    ".instar/jobs.json"
    ".instar/context"
    ".instar/integrations"
    ".instar/episodes"
)

for item in "${ITEMS[@]}"; do
    src="${AGENT_DIR}/${item}"
    dst="${WORKTREE}/${item}"
    [[ ! -e "$src" ]] && continue
    mkdir -p "$(dirname "$dst")"
    if [[ -d "$src" ]]; then
        rsync -a --delete "${src}/" "${dst}/"
    else
        cp "$src" "$dst"
    fi
done

cd "$WORKTREE"

if [[ -z "$(git status --porcelain)" ]]; then
    echo "${LOG_TAG} no changes — skipping commit"
    exit 0
fi

git add -A
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
git -c user.name="Corfe Agent" -c user.email="agent@corfe.local" \
    commit -m "backup: state snapshot ${TIMESTAMP}" >/dev/null

if ! git push origin state-backup 2>&1 | tail -3; then
    echo "${LOG_TAG} push failed — backup committed locally only" >&2
    exit 2
fi

echo "${LOG_TAG} backed up at ${TIMESTAMP}"
