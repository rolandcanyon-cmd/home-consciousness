---
name: zone2-pandora
description: Control Yamaha Zone 2 Pandora - turn on, select station by name
metadata:
  user_invocable: "true"
---

# Zone 2 Pandora Control

Play Pandora stations on Yamaha RX-A1070 Zone 2 (whole-house audio). Searches for the requested station and starts playback.

## Common Usage

User says: "Play Santana on Zone 2" or "Zone 2 Pink Floyd" or just "Santana"

The skill will:
1. Power on Zone 2 if it's off
2. Set input to Pandora
3. Search through Pandora stations for the requested name
4. Select and play the station

## Yamaha API Endpoints

**Base URL**: `http://10.0.0.128/YamahaRemoteControl/ctrl`

All commands are XML POST requests.

### Zone 2 Control

**Power On Zone 2:**
```bash
curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
  -d '<YAMAHA_AV cmd="PUT"><Zone_2><Power_Control><Power>On</Power></Power_Control></Zone_2></YAMAHA_AV>'
```

**Set Zone 2 Input to Pandora:**
```bash
curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
  -d '<YAMAHA_AV cmd="PUT"><Zone_2><Input><Input_Sel>Pandora</Input_Sel></Input></Zone_2></YAMAHA_AV>'
```

**Get Zone 2 Status:**
```bash
curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
  -d '<YAMAHA_AV cmd="GET"><Zone_2><Basic_Status>GetParam</Basic_Status></Zone_2></YAMAHA_AV>'
```

### Pandora Station Control

**List Stations (shows 8 at a time):**
```bash
curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
  -d '<YAMAHA_AV cmd="GET"><Pandora><List_Info>GetParam</List_Info></Pandora></YAMAHA_AV>'
```

**Navigate Down in List:**
```bash
curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
  -d '<YAMAHA_AV cmd="PUT"><Pandora><List_Control><Cursor>Down</Cursor></List_Control></Pandora></YAMAHA_AV>'
```

**Navigate Up in List:**
```bash
curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
  -d '<YAMAHA_AV cmd="PUT"><Pandora><List_Control><Cursor>Up</Cursor></List_Control></Pandora></YAMAHA_AV>'
```

**Jump to Line (select specific station by line number 1-8):**
```bash
curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
  -d '<YAMAHA_AV cmd="PUT"><Pandora><List_Control><Direct_Sel>Line_2</Direct_Sel></List_Control></Pandora></YAMAHA_AV>'
```

**Select Current Station (start playback):**
```bash
curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
  -d '<YAMAHA_AV cmd="PUT"><Pandora><List_Control><Cursor>Sel</Cursor></List_Control></Pandora></YAMAHA_AV>'
```

**Get Currently Playing:**
```bash
curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
  -d '<YAMAHA_AV cmd="GET"><Pandora><Play_Info>GetParam</Play_Info></Pandora></YAMAHA_AV>'
```

## Station Search Algorithm

The Pandora list shows 8 stations at a time, with a cursor position indicating where you are in the full list (e.g., line 2 of 33 total).

To find a station by name:
1. Get the current list
2. Search visible lines (Line_1 through Line_8) for fuzzy match
3. If found in visible lines, select that line directly using `Direct_Sel`
4. If not found, navigate down to see more stations
5. Keep searching until found or reach max_line
6. Once found, select the line, then send `Cursor>Sel</Cursor>` to play

## Common Stations

Based on the list retrieved (33 total stations):
- Pink Floyd Radio
- Santana Radio
- Cardiacs Radio
- Owner's Prog Radio
- Budgie Radio
- The Merriest Hawaiian Christmas Radio
- It's Christmas, Baby, Please Come Home
- (and 25+ more)

## Implementation Steps

When user requests a station (extract station name from their message):

1. **Power on Zone 2:**
   ```bash
   curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
     -d '<YAMAHA_AV cmd="PUT"><Zone_2><Power_Control><Power>On</Power></Power_Control></Zone_2></YAMAHA_AV>'
   ```
   Wait 2 seconds for zone to power on.

2. **Set input to Pandora:**
   ```bash
   curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
     -d '<YAMAHA_AV cmd="PUT"><Zone_2><Input><Input_Sel>Pandora</Input_Sel></Input></Zone_2></YAMAHA_AV>'
   ```
   Wait 3 seconds for Pandora to load.

3. **Search for station:**
   - Get list
   - Fuzzy match station name (case-insensitive, partial match)
   - Navigate if needed
   - Select when found

4. **Start playback:**
   Once the correct line is highlighted, send:
   ```bash
   curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl \
     -d '<YAMAHA_AV cmd="PUT"><Pandora><List_Control><Cursor>Sel</Cursor></List_Control></Pandora></YAMAHA_AV>'
   ```

5. **Verify:**
   Get play info to confirm the right station is playing.

## Example Usage

User: "Play Santana on Zone 2"

Steps:
1. Extract station name: "Santana"
2. Power on Zone 2
3. Set input to Pandora
4. Get station list
5. Find "Santana Radio" on Line_3
6. Select Line_3 directly: `Direct_Sel>Line_3`
7. Confirm selection: `Cursor>Sel`
8. Report: "Zone 2 playing Santana Radio"

## Fuzzy Matching

Match user input flexibly:
- "santana" → "Santana Radio"
- "pink floyd" → "Pink Floyd Radio"
- "prog" → "Owner's Prog Radio"
- Case-insensitive
- Partial match OK
- Match first result if multiple hits

## Important Notes

- **Always use Zone_2**, never Main_Zone (that's for the TV)
- Allow time for state changes (2-3 seconds between power/input changes)
- The station list cursor position matters - Direct_Sel uses Line_1 through Line_8
- After using Direct_Sel to highlight a line, you MUST send Cursor>Sel to actually play it
- The list has 33 stations total, but only 8 visible at a time
- Navigation wraps around (going down from bottom goes to top)

## Error Handling

- If station not found after searching all 33 lines, list available stations and ask user to clarify
- If Pandora is unavailable (network issue), report the error
- If Zone 2 is already playing the requested station, just confirm it's playing
