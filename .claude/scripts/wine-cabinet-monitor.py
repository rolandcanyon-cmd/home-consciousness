#!/usr/bin/env python3
"""
wine-cabinet-monitor.py — Monitor wine cabinet temperatures via ecobee API.

Reads Left and Right Wine Cabinet sensor temperatures. If either exceeds
the alert threshold (default: 65°F), sends an iMessage alert.

This runs as a scheduled job. Requires ecobee credentials:
    .instar/state/ecobee-api-key.txt
    .instar/state/ecobee-tokens.json

Run manually:
    python3 wine-cabinet-monitor.py           # check and alert if needed
    python3 wine-cabinet-monitor.py --status  # just print current temps
"""

import sys
import os
import json
import subprocess
import time
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

STATE_DIR = os.path.join(SCRIPT_DIR, '../../.instar/state')
ALERT_STATE_FILE = os.path.join(STATE_DIR, 'wine-cabinet-alert-state.json')

# Temperature threshold in °F — above this triggers an alert
ALERT_THRESHOLD_F = 65.0
# Don't re-alert unless the last alert was more than this many seconds ago
ALERT_COOLDOWN_SECONDS = 3600  # 1 hour

USER_PHONE = '+14084424360'

# Wine sensor keywords — matched against sensor names (case-insensitive)
WINE_SENSOR_KEYWORDS = ['wine cabinet', 'wine closet', 'ebers']


def find_wine_sensors(sensor_data: list) -> list:
    """Extract wine cabinet sensors from ecobee sensor data."""
    wine_sensors = []
    for thermostat in sensor_data:
        thermostat_name = thermostat.get('thermostat', '')
        for sensor in thermostat.get('sensors', []):
            name = sensor.get('name', '').lower()
            t_name = thermostat_name.lower()
            if any(k in name or k in t_name for k in WINE_SENSOR_KEYWORDS):
                if sensor.get('temperature_f') is not None:
                    wine_sensors.append({
                        'name': sensor['name'],
                        'thermostat': thermostat_name,
                        'temperature_f': sensor['temperature_f'],
                        'temperature_c': sensor.get('temperature_c'),
                    })
    return wine_sensors


def load_alert_state() -> dict:
    try:
        with open(ALERT_STATE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_alert_state(state: dict) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(ALERT_STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


def send_imessage(message: str) -> None:
    reply_script = os.path.join(SCRIPT_DIR, 'imessage-reply.sh')
    subprocess.run([reply_script, USER_PHONE, message], check=False)


def run_check(status_only: bool = False) -> dict:
    """Run the temperature check. Returns result dict."""
    # Get current temperatures via ecobee API
    ecobee_script = os.path.join(SCRIPT_DIR, 'ecobee-api.py')
    result = subprocess.run(
        [sys.executable, ecobee_script, 'sensors'],
        capture_output=True, text=True, timeout=30
    )

    if result.returncode != 0:
        error = result.stderr.strip() or 'unknown error'
        print(f'Error reading ecobee: {error}', file=sys.stderr)
        return {'error': error}

    try:
        sensor_data = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        print(f'JSON parse error: {e}', file=sys.stderr)
        return {'error': str(e)}

    wine_sensors = find_wine_sensors(sensor_data)

    if not wine_sensors:
        # Fallback: show all sensors
        print('No wine sensors found. All sensor data:', file=sys.stderr)
        print(json.dumps(sensor_data, indent=2), file=sys.stderr)
        return {'error': 'no wine sensors found'}

    now = datetime.utcnow().isoformat() + 'Z'
    reading = {
        'checked_at': now,
        'sensors': wine_sensors,
        'max_temp_f': max(s['temperature_f'] for s in wine_sensors),
    }

    if status_only:
        print(json.dumps(reading, indent=2))
        return reading

    # Check thresholds
    over_threshold = [s for s in wine_sensors if s['temperature_f'] > ALERT_THRESHOLD_F]

    if over_threshold:
        # Check cooldown
        alert_state = load_alert_state()
        last_alert_ts = alert_state.get('last_alert_at', 0)
        seconds_since = time.time() - last_alert_ts

        if seconds_since >= ALERT_COOLDOWN_SECONDS:
            # Send alert
            lines = ['⚠️ Wine cabinet temperature alert!']
            for s in over_threshold:
                lines.append(f"  {s['name']}: {s['temperature_f']:.1f}°F ({s['temperature_c']:.1f}°C)")
            lines.append(f'Threshold: {ALERT_THRESHOLD_F}°F')
            lines.append('Check that the Wine Guardian thermostat is on.')
            send_imessage('\n'.join(lines))
            print(f'Alert sent: {", ".join(s["name"] for s in over_threshold)}')

            # Update state
            alert_state['last_alert_at'] = time.time()
            alert_state['last_alert_temps'] = {s['name']: s['temperature_f'] for s in over_threshold}
            save_alert_state(alert_state)
        else:
            remaining = int(ALERT_COOLDOWN_SECONDS - seconds_since)
            print(f'Temp over threshold but in cooldown ({remaining}s remaining)')
    else:
        # All good — clear alert state if previously alerting
        alert_state = load_alert_state()
        if alert_state.get('last_alert_at'):
            prev_max = max(alert_state.get('last_alert_temps', {}).values() or [0])
            if prev_max > ALERT_THRESHOLD_F:
                # Temperatures normalized — send an "all clear" message
                temps_str = ', '.join(f'{s["name"]}: {s["temperature_f"]:.1f}°F' for s in wine_sensors)
                send_imessage(f'✅ Wine cabinet temperatures back to normal: {temps_str}')
            alert_state['last_alert_at'] = 0
            save_alert_state(alert_state)
        ok_str = ', '.join(f'{s["name"]} {s["temperature_f"]:.1f}°F' for s in wine_sensors)
        print(f'OK: {ok_str}')

    return reading


if __name__ == '__main__':
    status_only = '--status' in sys.argv
    result = run_check(status_only=status_only)
    if 'error' in result:
        sys.exit(1)
