---
name: GitHub repos — rolandcanyon-cmd
description: All GitHub repos under rolandcanyon-cmd account, their purposes, and local paths
type: project
originSessionId: 3d008a33-f8b5-4e57-97b0-405171b5d02d
---
**Corrected 2026-07-13** — `gh repo list rolandcanyon-cmd` shows 7 repos, not 5. Full current list:

- **the-goodies**: Fork of adrianco/the-goodies. FunkyGibbon Python server + Blowing-Off Python client + Oook CLI + Inbetweenies protocol. Local: `~/the-goodies`. Smart home knowledge graph backend. Issues disabled on this repo.
- **the-goodies-typescript**: **DEPRECATED as of 2026-09-13** — the primary copy moved to the `adrianco` account alongside the main repo; this one is history only, do not invest in it (see [[project-goodies-upgrade-and-repo-move]]). Previously: owned, not a fork, because no adrianco TS upstream existed. `kittenkong` (TypeScript FunkyGibbon client + MCP server, ported from blowing-off) and `inbetweenies` (protocol). Local: `~/.instar/agents/Roland/the-goodies-typescript`. Built ~2026-04-07. MCP server added 2026-04-19. No CI configured.
- **home-consciousness**: Main house config repo. Device interfaces, schemas, sync scripts. Note: kittenkong/server.py was deleted (Python impostor) — kittenkong MCP server now lives in the-goodies-typescript. No CI configured.
- **c11s-house-config**: Separate repo from home-consciousness despite the similar local path name (`~/c11s-house-config` was previously documented as home-consciousness's local checkout — needs re-verification which repo actually lives there). No CI configured.
- **roland-state**: This agent's own `.instar/` state repo — `git remote -v` in `~/.instar/agents/Roland` shows `origin` pushing to BOTH roland-state.git and home-consciousness.git (dual push-url setup, one `git push` updates both). No CI configured.
- **aiovantage**: Fork of Python library for Vantage InFusion home automation. Kept for older firmware compatibility. See memory entry. Issues disabled on this repo.
- **instar**: Fork of JKHeadley/instar. Local: `~/instar-dev`. The only repo with real CI activity (daily rebase, CI, docs-coverage-weekly, publish-to-npm workflows). **Publish-to-npm has no npm auth configured** — worked so far only because there was nothing queued to publish (skip=true path); the first real publish attempt (2026-07-13) failed with ENEEDAUTH. Fork doesn't use npm at all (deploy is via `file:` symlink to instar-dev per [[feedback-build-deploy]]), so this is a dormant gap, not urgent — asked Adrian whether to disable the workflow or leave it failing harmlessly.

**Why:** All work should start by checking existing repos before building new. The-goodies already has Python client (blowing-off) and test patterns (test_ugc_features.py has Mitsubishi thermostat entity patterns). kittenkong TypeScript is in the-goodies-typescript, not something to build fresh.

**How to apply:** Before writing a new client, tool, or integration, check these repos first. Before claiming "5 repos" — there are 7; re-verify with `gh repo list rolandcanyon-cmd` rather than trusting this count from memory.
