#!/usr/bin/env python3
"""
scheduler-health-check.py — detect scheduled jobs that are silently stuck
(retry-exhausted with no successful run since), plus current quota/memory
pressure that would explain it. Prints a human-readable report if anything
new is worth reporting; prints nothing if all clear.

Dedup state lives in .instar/state/scheduler-health-notified.json so a
chronically-stuck job nags at most once per calendar day, not every run of
this check.
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone, timedelta

AGENT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG_PATH = os.path.join(AGENT_DIR, ".instar", "config.json")
SERVER_LOG = os.path.join(AGENT_DIR, "logs", "server.log")
STATE_PATH = os.path.join(AGENT_DIR, ".instar", "state", "scheduler-health-notified.json")

EXHAUST_RE = re.compile(
    r'^(?P<ts>[\d\-T:.]+Z) \[LOG\] \[scheduler\] Job "(?P<slug>[^"]+)" '
    r'exhausted \d+ retries \(last skip: (?P<reason>[^)]+)\) — waiting for next cron window'
)


def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)


def load_state():
    try:
        with open(STATE_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state):
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    with open(STATE_PATH, "w") as f:
        json.dump(state, f, indent=2)


def parse_iso(ts):
    ts = ts.rstrip("Z")
    return datetime.fromisoformat(ts).replace(tzinfo=timezone.utc)


def get_jobs(auth, port):
    import urllib.request

    req = urllib.request.Request(
        f"http://localhost:{port}/jobs",
        headers={"Authorization": f"Bearer {auth}"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.load(resp)["jobs"]


def get_quota(port):
    import urllib.request

    try:
        with urllib.request.urlopen(f"http://localhost:{port}/quota", timeout=10) as resp:
            return json.load(resp)
    except Exception:
        return None


def memory_pressure():
    """Mirror instar's own hostMemoryPressure.ts formula exactly (available =
    free + inactive + purgeable), NOT a naive os.freemem()-style calc — macOS
    keeps raw "Pages free" near zero by design, which would misreport a normal
    machine as critically low. Returns (usedPercent, availableGB) or (None, None).
    """
    try:
        out = subprocess.check_output(["vm_stat"], text=True)
        pagesize_match = re.search(r"page size of (\d+) bytes", out)
        pagesize = int(pagesize_match.group(1)) if pagesize_match else 16384

        def pages(label):
            m = re.search(rf"{label}:\s+(\d+)\.", out)
            return int(m.group(1)) if m else 0

        free_p = pages("Pages free")
        active_p = pages("Pages active")
        inactive_p = pages("Pages inactive")
        wired_p = pages("Pages wired down")
        compressor_p = pages("Pages occupied by compressor")
        purgeable_p = pages("Pages purgeable")

        total_p = free_p + active_p + inactive_p + wired_p + compressor_p
        available_p = free_p + inactive_p + purgeable_p
        used_p = total_p - available_p
        if total_p == 0:
            return None, None
        used_percent = round(100 * used_p / total_p, 1)
        available_gb = round(available_p * pagesize / (1024 ** 3), 2)
        return used_percent, available_gb
    except Exception:
        return None, None


def main():
    config = load_config()
    auth = config.get("authToken", "")
    port = config.get("port", 4040)
    now = datetime.now(timezone.utc)
    today = now.strftime("%Y-%m-%d")

    state = load_state()
    lines = []

    # ── 1. Retry-exhausted jobs with no success since ──
    exhaustions = {}
    if os.path.exists(SERVER_LOG):
        try:
            grep_out = subprocess.run(
                ["grep", "-F", "exhausted", SERVER_LOG],
                capture_output=True, text=True, timeout=20,
            ).stdout
        except Exception:
            grep_out = ""
        for line in grep_out.splitlines():
            m = EXHAUST_RE.match(line)
            if not m:
                continue
            slug = m.group("slug")
            ts = parse_iso(m.group("ts"))
            reason = m.group("reason")
            if slug not in exhaustions or ts > exhaustions[slug][0]:
                exhaustions[slug] = (ts, reason)

    try:
        jobs = get_jobs(auth, port)
    except Exception as e:
        print(f"(scheduler-health-check: could not reach /jobs — {e})")
        return

    jobs_by_slug = {j["slug"]: j for j in jobs}
    stuck = []
    for slug, (exhaust_ts, reason) in exhaustions.items():
        job = jobs_by_slug.get(slug)
        if not job or not job.get("enabled"):
            continue
        last_run_raw = job.get("state", {}).get("lastRun")
        last_run = parse_iso(last_run_raw) if last_run_raw else None
        if last_run and last_run > exhaust_ts:
            continue  # it has succeeded since — not stuck anymore
        # Still stuck as of the most recent exhaustion. Only nag once/day.
        last_notified = state.get("jobs", {}).get(slug)
        if last_notified == today:
            continue
        stuck.append((slug, exhaust_ts, reason, last_run))

    if stuck:
        state.setdefault("jobs", {})
        for slug, exhaust_ts, reason, last_run in stuck:
            state["jobs"][slug] = today
            age = now - (last_run or exhaust_ts)
            days = age.days
            when = f"{days}d" if days >= 1 else f"{int(age.total_seconds() // 3600)}h"
            last_ok = last_run_raw if (last_run_raw := (last_run.isoformat() if last_run else None)) else "never"
            lines.append(
                f"- \"{slug}\" hasn't completed in over {when} — the scheduler keeps hitting "
                f"\"{reason}\" and giving up until the next cron window (last success: {last_ok})."
            )

    # ── 2. Quota / usage limit ──
    quota = get_quota(port)
    if quota and quota.get("recommendation") not in (None, "normal"):
        last_notified = state.get("quota")
        if last_notified != today:
            state["quota"] = today
            lines.append(
                f"- Claude usage is at {quota.get('usagePercent')}% "
                f"(recommendation: {quota.get('recommendation')})."
            )

    # ── 3. Current memory pressure context (only shown alongside a real finding) ──
    if lines:
        used_pct, avail_gb = memory_pressure()
        if used_pct is not None:
            tier = "critical" if used_pct >= 90 else "elevated" if used_pct >= 75 else "warning" if used_pct >= 60 else "normal"
            lines.append(
                f"- Current memory pressure: {used_pct}% used ({avail_gb}GB available), tier={tier} "
                f"— background job spawning is blocked at elevated/critical (your interactive chat is never blocked)."
            )

    if lines:
        save_state(state)
        print("\n".join(lines))


if __name__ == "__main__":
    main()
