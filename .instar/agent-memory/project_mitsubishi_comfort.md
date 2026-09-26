---
name: Mitsubishi thermostats — Comfort app (was Kumo Cloud)
description: Four Mitsubishi thermostats controlled by the new Comfort app; user wants a local interface
type: project
originSessionId: cc4d5e38-5972-45ae-8a99-e1731a59fc67
---
House has four Mitsubishi thermostats controlled by the "Comfort app" (rebrand of Kumo Cloud). On 2026-04-19 the user asked to figure out how to interface with them programmatically.

Known facts:
- App was renamed Kumo Cloud → Comfort. The new Comfort app does NOT work with the existing Home Assistant integrations (user: "New comfort app, no HA").
- UniFi knows the IP addresses of the four thermostats — start there for local discovery rather than cloud API.
- Kitchen + Pool House share a condenser (see [[comfort-cli — Mitsubishi thermostat CLI]]) — always-same-mode constraint applies regardless of interface.

**Why:** User wants local control / automation beyond the vendor app. Existing Kumo-era HA integrations (pykumo, kumo_JNX) target the old cloud protocol.

**How to apply:** If extending HVAC control, investigate the Comfort app's local/LAN protocol (pull IPs from UniFi, inspect traffic) rather than porting old kumo_JNX code. Check `comfort-cli` in the project for current state — it may already be the scaffolding for this work.
