---
name: known-funkygibbon-starlette-crash-loop-fixed
description: FunkyGibbon crash-looped on a starlette/fastapi version mismatch (fixed 2026-08-19) — requirements.txt still has no starlette pin so it could recur
metadata: 
  node_type: memory
  type: project
  originSessionId: 716df541-e8b0-49e7-9037-9fc7c4bf2f8e
  modified: 2026-08-19T16:17:01.819Z
---

On 2026-08-19 FunkyGibbon (`~/the-goodies`) was found crash-looping under launchd (`com.rolandcanyon.funkygibbon`): venv had `starlette==1.0.0` but `fastapi==0.135.3`, and 1.0.0 predates the on_startup/on_shutdown removal fastapi 0.135.3 expects — `TypeError: Router.__init__() got an unexpected keyword argument 'on_startup'` in `funkygibbon/api/routers/sync_metadata.py`. It had been restarting continuously and written 1.6GB to `logs/funkygibbon.err`.

**Fix applied:** `venv/bin/pip install -U starlette` (→ 1.6.0), then `launchctl kickstart -k gui/$(id -u)/com.rolandcanyon.funkygibbon`. Confirmed healthy + stable PID + working `/api/v1/graph/search`. Truncated the 4 bloated log files in `~/the-goodies/logs/` in place (freed ~2GB).

**Root cause / still open:** `requirements.txt` pins `fastapi>=0.104.0` with no upper bound and **no starlette entry at all** — nothing prevents this drift from happening again on a future `pip install -U fastapi` (or any partial dependency upgrade) that doesn't also bump starlette in lockstep. Consider pinning starlette explicitly, or at minimum re-check `pip show fastapi starlette` after any dependency upgrade in this repo.

Diagnostic tip: `funkygibbon.err` traceback paths reveal which Python actually ran — if they show `/Library/Frameworks/Python.framework/.../site-packages/...` instead of `~/the-goodies/venv/lib/.../site-packages/...`, the venv wasn't actually what crashed (a stale/interleaved manual test), so re-check via the real launchd-managed process, not a hand-rolled repro.

See [[project_github_repos]] for the-goodies repo context.
