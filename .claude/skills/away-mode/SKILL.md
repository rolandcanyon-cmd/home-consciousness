---
name: away-mode
description: Activate or deactivate house Away Mode — disable Alexa routines, set water heater to vacation mode, and generate departure/return checklists
metadata:
  user_invocable: "true"
---

# /away-mode

Handle house Away Mode transitions — departure preparation and return restoration.

## Invocation

- "we're leaving" / "activate away mode" / "set vantage away mode" → run **Departure** flow
- "we're home" / "we're back" / "deactivate away mode" → run **Return** flow

## Vantage Away Mode

Vantage controller at 10.0.0.50. Use vantage_probe.py to invoke tasks:

```
python3 .claude/scripts/vantage_probe.py task 6647   # AWAY  (departure)
python3 .claude/scripts/vantage_probe.py task 6643   # Home  (return)
```

Note: The physical keypads require a complex 3-press sequence ([7426] AWAY 3 PRESS / [7425] HOME 3 PRESS) that is easy to forget. Always invoke programmatically via tasks 6647/6643 instead.

---

## Departure Flow

Confirm the following are done (ask user to confirm each or check remotely where possible):

### Physical (manual — no remote access)
- [ ] Studio garage thermostat set manually (leave at 55°F for absence)
- [ ] Studio amplifiers and music gear powered off and stowed
- [ ] Fridges and pantry cleared of perishables
- [ ] Hot tub cover on (set temp to 85°F for maintenance)

### Networked — check/action
- [ ] **Rheem heat pump water heater** — set to vacation mode via Rheem app
- [ ] **Alexa routines** — switch to Away mode:
  - Disable: "kitchen pump on", "Ice Maker On", "pool house hot water pump on"
  - Keep enabled: "hot water pumps off", "Ice Maker Off", "bug zapper on", "bug zapper off"
- [ ] **EcoWater softener** — check salt level (self-alerting, top up if low)
- [ ] **Ambient Weather** — confirm All Batteries OK (check dashboard)

### Verify running
- [ ] Instar agent is running and scheduled jobs are active
- [ ] Morning weather reports configured
- [ ] Wine cabinet monitoring active (if ecobee API key configured)

---

## Return Flow

When user says "we're home" or "we're back":

1. **Welcome back message** with how long the house was unoccupied
2. **Return checklist** — restore everything to Home mode:

### Networked — restore
- [ ] **Rheem heat pump water heater** — switch from vacation → normal mode (Rheem app)
- [ ] **Alexa routines** — re-enable Home mode:
  - Re-enable: "kitchen pump on", "Ice Maker On"
  - Check if "pool house hot water pump on" should be re-enabled
- [ ] Check EcoWater softener salt level
- [ ] Check Ambient Weather — All Batteries OK

### Physical — check on-site
- [ ] Studio garage thermostat — set back to normal operating temperature
- [ ] Hot tub — adjust temperature from 85°F if desired
- [ ] Studio gear — power up as needed
- [ ] Water utility room — visual check, no leaks

### Optional
- [ ] Check FunkyGibbon for any notes or alerts logged during absence
- [ ] Review morning weather reports from the absence period

---

## Key Device Reference

| Device | Location | Away State | Return Action |
|--------|----------|------------|---------------|
| Studio thermostat | Studio garage | 55°F manual | Check + adjust |
| Hot tub | Rear exterior | 85°F, covered | Adjust if needed |
| Rheem HPWH (kitchen) | Water Mech Room | Vacation mode | → Normal mode |
| Rheem HPWH (bedrooms) | East Wing Mech Room | — | Check |
| EcoWater softener | Water Mech Room | Running, full | Check salt |
| Kitchen circulation pump | Water Mech Room | Alexa routine off | Re-enable |
| Pool house hot water pump | Pool area | Alexa routine off | Re-enable |
| Ice Maker | Kitchen | Alexa routine off | Re-enable |
| Bug zapper | Exterior | Running unchanged | No action |
| Mitsubishi heat pump | East Wing Mech Room | Normal operation | No action |
| Wine AC system | Attic above garage | Ecobee-controlled | No action |
