# App Walk Cross-Reference TODO

## What needs doing

After completing app walks, each device in an app entity has `fg_entity_id: null`.
These need to be linked to canonical device entities in FunkyGibbon.

## Apps with unlinked devices

### Alexa (entity: fb3e1b7a-781b-4e92-b952-114a89afdbe0)
Devices needing fg_entity_id resolution:
- Xmas Pool Lights x 2
- Inverter Room Fan
- Ice Maker
- Garage (smart plug)
- Bedroom Hot Water Pump
- Pool House Hot Water Pump
- Garage (door/sensor)
- Garage TV (Workshop) — also links to Sonos entity
- Kitchen Hot Water Pump
- Bug Zapper
- Alexa on this Phone
- Garage (Ring Camera)
- Roland Entrance (Ring Camera)

## How to cross-reference

For each device:
1. Search FunkyGibbon for a matching entity by name
2. If found: set fg_entity_id on the app device entry
3. If not found: create a new device entity, then link it

Script to run once search is fixed:
```
python3 .claude/scripts/app_cross_reference.py fb3e1b7a-781b-4e92-b952-114a89afdbe0
```
(Script doesn't exist yet — create it when the search API is fixed)

## Blocker

FunkyGibbon search API returns 405 on GET /api/v1/graph/search.
Fix tracked separately. Do not attempt cross-referencing until search works.

## Created
2026-04-29
