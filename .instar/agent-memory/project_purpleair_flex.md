---
name: project-purpleair-flex
description: PurpleAir Flex is the sole PM2.5 source — local JSON at 10.0.0.140, needs a 15s timeout (cold-start latency), A/B channels averaged
metadata:
  node_type: memory
  type: project
  originSessionId: 30164ac5-1517-43cb-bb47-5b01b51408c9
  modified: 2026-08-02T14:35:19.468Z
---

A PurpleAir Flex is the sole pm2.5 source, replacing the Ambient Weather PM2.5
station which drifted badly (read 914, then 188, while real air at its own
coordinates was ~5–7 µg/m³). Installed and wired in 2026-07-13.

**Live operational facts:**
- `PurpleAir-88c4` (mac `f0:24:f9:c6:88:c4`) at **`10.0.0.140`**, on the "Pool
  House Kitchen" AP. IP is **DHCP** — re-resolve with
  `python3 .claude/scripts/unifi_probe.py find purple` if it stops answering.
- Local JSON endpoint `http://10.0.0.140/json`, no auth/API key.
  **Latency quirk**: the first request after idle takes ~8.5s (the device builds
  the response on demand); back-to-back requests answer in <100ms.
  `ambient-weather.mjs` uses a **15s timeout** for exactly this reason — a
  shorter one misreports a slow-but-alive sensor as unreachable.
- Fields `pm2_5_atm` (channel A) and `pm2_5_atm_b` (channel B), averaged. Two
  laser modules sample the same air, so **divergence between A and B means one
  module is dying** — that self-detection, not accuracy specs, was the buying
  criterion (the Ambient's failure mode was silent drift with nothing on the
  device able to know).
- `ambient-weather.mjs` corroborates any pm2.5 reading against Open-Meteo for
  the station's coordinates before raising an alarm: >3× the reference (and
  >20 µg/m³) ⇒ `pm25DriftSuspected`, alarm suppressed, value still surfaced as
  `pm25Suspect`. **Fails OPEN** — an unreachable reference records
  `pm25ReferenceUnavailable` and does not suppress the reading, because a
  missing check must never masquerade as a passed check.
- The old Ambient PM2.5 device stays in `SUSPECT_DEVICES` for historical display
  only and no longer feeds `pm25Category`.

**Sensor physics worth remembering:** laser particle counters over-read in humid
air (particles absorb water and scatter more), so a good unit applies a humidity
correction. Modules genuinely wear out over a few years — drift on an older
sensor is end-of-life, not a defect. Blowing out dust/insects helped the Ambient
(914 → 75) but did not restore calibration.

See [[project-ambient-weather-login-blocked]] for the station/slot map.
