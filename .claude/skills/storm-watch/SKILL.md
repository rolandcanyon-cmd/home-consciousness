---
name: storm-watch
description: Hourly check of Tempest lightning, PurpleAir PM2.5, and nearby CAL FIRE incidents during an active Red Flag Warning. Alerts only on concerning change. Self-stops when the warning lifts.
metadata:
  user_invocable: "false"
---

# Storm Watch (Red Flag Warning monitor)

Runs hourly while a National Weather Service Red Flag Warning (dry lightning risk) is active
and the operator is away from the house. Checks three sources, decides whether the situation
is concerning enough to interrupt the operator, and self-retires once the warning lifts.

State file: `.instar/state/storm-watch-state.json` — read it first, you'll need it to detect
*changes* (new fires, worsening containment, lightning getting closer), not just current readings.

## Step 1 — Check whether the Red Flag Warning is still active (the stop condition)

1. Navigate (Playwright `browser_navigate`) to `https://tempestwx.com/station/125865/` (the house's
   Tempest station — confirm this URL is still current via FunkyGibbon if in doubt: search
   `kittenkong`/FunkyGibbon for "tempest weather station", read `station_url`).
2. Wait ~2-3s for the page to render, then check whether the text "Red Flag Warning" appears
   in the snapshot (`browser_find` for "Red Flag Warning" or full `browser_snapshot`).
3. **If the warning is GONE and `state.stopped` is not already true:**
   - Send ONE final iMessage: plain-English "the Red Flag Warning has lifted — stopping the
     hourly storm watch" message. Mention current PM2.5/lightning/fire status briefly as a
     clean closing summary if you have time to gather it, but don't block the all-clear on it.
   - Update the state file: set `"stopped": true`, `"lastRedFlagWarningSeen": false`, update
     `lastRun`. This is what makes the job's gate script (`storm-watch-gate.sh`) skip all future
     scheduled runs — no server restart needed, no further action required.
   - Stop here. Do not run steps 2-4.
4. If the warning is still active, continue below.

## Step 2 — Lightning (from the same Tempest session)

1. Click the "Observations" button (or navigate to `/station/125865/grid`) and find the
   lightning card: fields are "Last Detected" (age), "Distance" (of that last detection),
   and "Last 3 Hrs" (strike count in the last 3 hours — this is the live indicator).
2. Compare `Last 3 Hrs` against `state.lastLightning.last3HrStrikes`:
   - **Alert-worthy**: `Last 3 Hrs` > 0 (active nearby lightning detected — the Tempest sensor's
     range is roughly 25 miles, so any nonzero count while under a dry-lightning red flag warning
     is meaningful) OR the reported distance bucket has gotten closer since the last run.
   - Otherwise, just update state — no alert on this alone.

## Step 3 — Air quality (PurpleAir Flex, local sensor — no browser needed)

Run: `node .claude/scripts/ambient-weather.mjs --json`

- Trusted reading is `pm25Category` (Good/Moderate/Unhealthy for Sensitive Groups/Unhealthy/Very
  Unhealthy/Hazardous) — this is the corroborated PurpleAir Flex reading, the one to alarm on.
- **Alert-worthy**: `pm25Category` is "Unhealthy for Sensitive Groups" or worse (i.e. PM2.5 > 35.4
  µg/m³), OR `pm25Category` just got worse than last run's `state.lastPm25.category` (e.g.
  Good→Moderate is a real trend worth a heads-up even if not yet "bad", since this is a fire/smoke
  watch — use judgment: a first-time move off "Good" during an active red-flag/fire situation is
  worth a mention, a fluctuation between Moderate and Good repeatedly is not).
- If `pm25Unavailable` appears (sensor unreachable), note it but don't alarm on a single miss —
  only mention if unavailable 2+ consecutive runs (check `state.lastPm25` for a prior unavailable
  flag you may have stored).
- If `pm25Reference` (the regional Open-Meteo model) diverges sharply HIGHER than the local
  PurpleAir reading (e.g. reference reads several multiples of the local value) while the local
  sensor still reads clean, that can mean smoke aloft not yet at ground level — worth ONE mention
  the first time you see it, not every hour.

## Step 4 — Nearby fires (CAL FIRE public incident API — no browser needed)

Run: `python3 .claude/scripts/calfire-nearby.py --radius 60`

This is the same underlying data Watch Duty aggregates from, read directly from CAL FIRE's public
API (far more reliable for unattended hourly automation than scraping Watch Duty's interactive
map). Compare the returned `incidents[].uniqueId` list against `state.knownFireIds`:

- **Alert-worthy**: a genuinely NEW `uniqueId` appears within the radius that wasn't in
  `knownFireIds` — this is a brand new nearby fire.
- **Alert-worthy**: an already-known nearby fire (say, within ~30 miles) shows containment
  DROPPING or acreage growing substantially (e.g. >25% acreage increase) since `lastFireSnapshot`.
- Otherwise (same fires, stable/improving), just refresh state — no alert.

## Step 5 — Decide and act

- If ANY of steps 2-4 are alert-worthy, send ONE consolidated iMessage covering everything
  relevant (don't send three separate texts) — plain English, lead with the most urgent item,
  skip anything that's fine (no need to say "air quality: still fine" if lightning is the news).
- If NOTHING is alert-worthy, send NOTHING. Silence is correct — this runs hourly for
  potentially days, and the operator only wants to hear about it when something changed for
  the worse. Do not send a routine "all clear, nothing new" text every hour.
- **Always** update `.instar/state/storm-watch-state.json` with the latest readings
  (`lastLightning`, `lastPm25`, `knownFireIds`, `lastFireSnapshot`, `lastRun`,
  `lastRedFlagWarningSeen`) regardless of whether you alerted, so the next run has an accurate
  baseline to diff against.

## Sending the message

```
PHONE=$(python3 -c "
import json
d = json.load(open('.instar/config.json'))
phone = d.get('imessage', {}).get('userPhone', '')
if not phone:
    for m in d.get('messaging', []):
        if m.get('type') == 'imessage':
            contacts = m.get('config', {}).get('authorizedContacts', [])
            phone = next((c for c in contacts if c.startswith('+')), contacts[0] if contacts else '')
            break
print(phone)
")
cat <<MSG | .claude/scripts/imessage-reply.sh "$PHONE"
YOUR MESSAGE HERE
MSG
```

## Notes

- This job was set up 2026-08-28 at the operator's request while away from the house for an
  active Red Flag Warning (dry lightning risk); Tesla Powerwalls are in storm mode. Runs hourly
  via the `storm-watch` job (schedule `0 * * * *`, gated by `storm-watch-gate.sh` so it goes
  silent for free once stopped — no server restart needed to stop it).
- House coordinates: 36.5556, -121.7180 (San Benancio, off Hwy 68, Monterey County).
- Don't fabricate distance/direction detail beyond what the sources actually report.
- If the Tempest page fails to load or the lightning card can't be found, say so plainly in
  state/notes rather than guessing — but don't let a Tempest hiccup suppress the fire/air checks.
