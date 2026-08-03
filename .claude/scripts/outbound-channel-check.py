#!/usr/bin/env python3
"""
outbound-channel-check.py — probe every channel by which this agent surfaces
something to the outside world, and report the ones that are degraded.

Why this exists (EVO-058 / LRN-016, LRN-017, LRN-018): every outbound surface
here degrades WITHOUT ERRORING at the point of use, and a READ of each surface
looks healthy while the WRITE is broken:

  - attention queue: GET /attention returns 0 items whether nothing needed
    attention or nothing CAN be written. POST is what actually fails (503).
  - feedback ring: the store holds 1000 entries, which looks full and healthy,
    while ~99% are one repeated degradation report evicting everything real.
  - tunnel: the `url` field is often populated even when the link is not
    reachable, so a link handed to Adrian can be dead on arrival.

So each check here is a WRITE probe or a DISTINCT-VALUE count (per EVO-056),
never a bare read of a surface that cannot distinguish empty from broken.

Prints nothing when all channels are healthy. Prints one line per degraded
channel otherwise. Dedup state lives in
.instar/state/outbound-channel-notified.json so a chronically-dead channel
nags at most once per calendar day.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

AGENT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG_PATH = os.path.join(AGENT_DIR, ".instar", "config.json")
STATE_PATH = os.path.join(AGENT_DIR, ".instar", "state", "outbound-channel-notified.json")

# Below this share of distinct titles, the feedback ring is a flood: real
# reports are being evicted by one repeated entry.
FEEDBACK_DISTINCT_FLOOR = 0.10


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


def call(method, url, auth, payload=None, timeout=10):
    """Return (status_code, parsed_body_or_None). Never raises."""
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {auth}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode()
            try:
                return r.status, json.loads(raw)
            except json.JSONDecodeError:
                return r.status, None
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, None
    except Exception:
        return 0, None


def check_attention(auth, port):
    """WRITE probe. A read of GET /attention cannot tell empty from broken."""
    status, body = call(
        "POST", f"http://localhost:{port}/attention", auth,
        {
            "title": "[selftest] outbound-channel write probe",
            "body": "Automated write probe from guardian-pulse. Safe to ignore; "
                    "resolved immediately on success.",
            "priority": "low",
            "source": "outbound-channel-check",
        },
    )
    if 200 <= status < 300:
        # Healthy — clean up after ourselves so the probe leaves no junk.
        item_id = (body or {}).get("id") or ((body or {}).get("item") or {}).get("id")
        if item_id:
            call("PATCH", f"http://localhost:{port}/attention/{item_id}", auth,
                 {"status": "resolved", "resolution": "self-test probe"})
        return None
    reason = (body or {}).get("error") or f"HTTP {status}"
    return ("attention",
            f"- Attention queue is WRITE-DEAD: POST /attention -> {reason}. Every built-in "
            f"guard that escalates through it (guard-posture tripwire, sentinel escalations, "
            f"resume-queue give-ups, burn detection, scope-accretion holds) is a silent no-op. "
            f"An empty attention queue here means nothing CAN be written, not that nothing "
            f"needed attention. Escalate by iMessage instead.")


def check_tunnel(auth, port):
    """The `url` field is populated even when the link is unreachable."""
    status, body = call("GET", f"http://localhost:{port}/tunnel", auth)
    if status == 0 or body is None:
        return ("tunnel", "- Tunnel status unreadable (GET /tunnel failed) — assume no remote links.")
    lifecycle = body.get("lifecycle") or {}
    state = lifecycle.get("state")
    url = body.get("url")
    if state == "active" and url:
        return None  # link exists right now; reachability is checked at moment of use
    return ("tunnel",
            f"- Tunnel is not serving links: lifecycle.state={state!r}, url={url!r} "
            f"(last failure: {lifecycle.get('lastFailureReason')}). Private-view and dashboard "
            f"links will not work remotely until this recovers. It is INTERMITTENT, not "
            f"permanently dead — re-read GET /tunnel at the moment you need a link.")


def check_feedback(auth, port):
    """DISTINCT-value count. 1000 entries looks healthy; 2 distinct is not."""
    status, body = call("GET", f"http://localhost:{port}/feedback", auth, timeout=20)
    items = (body or {}).get("feedback") or []
    if status == 0 or not items:
        return None  # nothing to judge; an empty ring is not evidence of flood
    total = len(items)
    distinct = len({(i.get("title") or "").strip() for i in items})
    if distinct / total >= FEEDBACK_DISTINCT_FLOOR:
        return None
    # Name the flooding title so the report is actionable.
    counts = {}
    for i in items:
        t = (i.get("title") or "").strip()
        counts[t] = counts.get(t, 0) + 1
    top_title, top_n = max(counts.items(), key=lambda kv: kv[1])
    return ("feedback",
            f"- Feedback ring is {100 * top_n // total}% flood: {top_n} of {total} entries are "
            f"the same report ({top_title[:80]!r}), leaving only {distinct} distinct titles. "
            f"Real feedback filed here is evicted within about a day. Do not rely on "
            f"POST /feedback as a durable record until the flood source is fixed.")


def main():
    cfg = load_config()
    auth = cfg.get("authToken") or ""
    port = cfg.get("port") or 4040
    state = load_state()
    today = datetime.now(timezone.utc).date().isoformat()

    findings = [f for f in (check_attention(auth, port),
                            check_tunnel(auth, port),
                            check_feedback(auth, port)) if f]

    lines = []
    for key, line in findings:
        if state.get(key) == today:
            continue  # already nagged about this channel today
        state[key] = today
        lines.append(line)

    # Clear the dedup stamp for channels that recovered, so a later relapse reports again.
    degraded = {k for k, _ in findings}
    for key in ("attention", "tunnel", "feedback"):
        if key not in degraded:
            state.pop(key, None)

    save_state(state)

    if lines:
        print("Outbound channels degraded — these are the paths by which I surface things to you:")
        print("\n".join(lines))
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
