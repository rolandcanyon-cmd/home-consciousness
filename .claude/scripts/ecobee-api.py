#!/usr/bin/env python3
"""
ecobee-api.py — Ecobee cloud API client for reading thermostat and sensor data.

Requires:
  - API key from developer.ecobee.com (stored in .instar/state/ecobee-api-key.txt)
  - Access token from PIN authentication (stored in .instar/state/ecobee-tokens.json)

Usage:
    python3 ecobee-api.py auth              # Start PIN auth flow
    python3 ecobee-api.py auth-complete     # Complete auth (exchange PIN for token)
    python3 ecobee-api.py thermostats       # List all thermostats
    python3 ecobee-api.py sensors           # List all remote sensors with temperatures
    python3 ecobee-api.py wine              # Get wine cabinet temperatures only
    python3 ecobee-api.py check-token       # Verify token is valid

Credentials stored in:
    .instar/state/ecobee-api-key.txt   — your ecobee App API key
    .instar/state/ecobee-tokens.json   — access/refresh tokens (auto-refreshed)
"""

import sys
import os
import json
import time
import urllib.request
import urllib.parse
import urllib.error
import argparse
from datetime import datetime

BASE_URL = 'https://api.ecobee.com'
STATE_DIR = os.path.join(os.path.dirname(__file__), '../../.instar/state')
API_KEY_FILE = os.path.join(STATE_DIR, 'ecobee-api-key.txt')
TOKEN_FILE = os.path.join(STATE_DIR, 'ecobee-tokens.json')
PIN_FILE = os.path.join(STATE_DIR, 'ecobee-pin-pending.json')


def read_api_key():
    """Read ecobee API key from state file."""
    try:
        with open(API_KEY_FILE) as f:
            return f.read().strip()
    except FileNotFoundError:
        print("Error: No ecobee API key found.", file=sys.stderr)
        print(f"Create {API_KEY_FILE} with your API key from developer.ecobee.com", file=sys.stderr)
        sys.exit(1)


def read_tokens():
    """Read stored tokens."""
    try:
        with open(TOKEN_FILE) as f:
            return json.load(f)
    except FileNotFoundError:
        print("Error: No ecobee tokens found. Run: python3 ecobee-api.py auth", file=sys.stderr)
        sys.exit(1)


def save_tokens(tokens):
    """Save tokens to state file."""
    tokens['saved_at'] = datetime.utcnow().isoformat() + 'Z'
    with open(TOKEN_FILE, 'w') as f:
        json.dump(tokens, f, indent=2)


def api_request(method, path, params=None, data=None, access_token=None):
    """Make an API request to ecobee."""
    url = BASE_URL + path
    if params:
        url += '?' + urllib.parse.urlencode(params)

    headers = {'Content-Type': 'application/json;charset=UTF-8'}
    if access_token:
        headers['Authorization'] = f'Bearer {access_token}'

    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        try:
            return json.loads(error_body)
        except:
            raise


def refresh_access_token(tokens, api_key):
    """Refresh the access token using refresh token."""
    data = {
        'grant_type': 'refresh_token',
        'code': tokens['refresh_token'],
        'client_id': api_key,
    }
    result = api_request('POST', '/token', params=data)
    if 'access_token' in result:
        tokens.update(result)
        save_tokens(tokens)
        return tokens
    return None


def get_valid_token():
    """Get a valid access token, refreshing if necessary."""
    api_key = read_api_key()
    tokens = read_tokens()

    # Try to refresh if we have a refresh token
    if 'refresh_token' in tokens:
        try:
            tokens = refresh_access_token(tokens, api_key)
            if tokens:
                return tokens['access_token']
        except Exception as e:
            print(f"Token refresh failed: {e}", file=sys.stderr)

    return tokens.get('access_token')


def cmd_auth():
    """Start PIN authentication flow."""
    api_key = read_api_key()
    result = api_request('GET', '/authorize', params={
        'response_type': 'ecobeePin',
        'client_id': api_key,
        'scope': 'smartRead',
    })

    if 'ecobeePin' in result:
        pin = result['ecobeePin']
        code = result['code']
        expires_in = result.get('expires_in', 900)  # seconds

        # Save pending auth
        with open(PIN_FILE, 'w') as f:
            json.dump({'code': code, 'pin': pin, 'api_key': api_key,
                      'created_at': time.time()}, f, indent=2)

        print(f"\nEcobee PIN Authentication")
        print(f"=" * 40)
        print(f"PIN: {pin}")
        print(f"\n1. Go to ecobee.com/home")
        print(f"2. Sign in to your ecobee account")
        print(f"3. My Apps → Add Application")
        print(f"4. Enter PIN: {pin}")
        print(f"\nThen run: python3 ecobee-api.py auth-complete")
        print(f"(PIN expires in {expires_in // 60} minutes)")
        return {'pin': pin, 'code': code}
    else:
        print(f"Error: {result}", file=sys.stderr)
        sys.exit(1)


def cmd_auth_complete():
    """Complete authentication by exchanging the PIN code for tokens."""
    try:
        with open(PIN_FILE) as f:
            pending = json.load(f)
    except FileNotFoundError:
        print("Error: No pending auth. Run: python3 ecobee-api.py auth first", file=sys.stderr)
        sys.exit(1)

    api_key = pending['api_key']
    code = pending['code']

    result = api_request('POST', '/token', params={
        'grant_type': 'ecobeePin',
        'code': code,
        'client_id': api_key,
    })

    if 'access_token' in result:
        save_tokens(result)
        os.remove(PIN_FILE)
        print("Authentication successful! Tokens saved.")
        print(json.dumps({'status': 'authenticated', 'token_type': result.get('token_type')}, indent=2))
    else:
        print(f"Error: {result}", file=sys.stderr)
        print("Make sure you entered the PIN at ecobee.com/home before running this command.", file=sys.stderr)
        sys.exit(1)


def cmd_thermostats():
    """List all thermostats."""
    token = get_valid_token()
    selection = json.dumps({
        'selection': {
            'selectionType': 'registered',
            'selectionMatch': '',
            'includeRuntime': True,
            'includeSettings': True,
            'includeSensors': True,
        }
    })
    result = api_request('GET', '/1/thermostat', params={'json': selection}, access_token=token)
    print(json.dumps(result, indent=2))


def cmd_sensors():
    """List all remote sensors with current temperatures."""
    token = get_valid_token()
    selection = json.dumps({
        'selection': {
            'selectionType': 'registered',
            'selectionMatch': '',
            'includeRuntime': True,
            'includeSensors': True,
        }
    })
    result = api_request('GET', '/1/thermostat', params={'json': selection}, access_token=token)

    thermostats = result.get('thermostatList', [])
    output = []

    for t in thermostats:
        thermostat_name = t.get('name', 'Unknown')
        runtime = t.get('runtime', {})

        # Main thermostat temperature
        actual_temp_f = runtime.get('actualTemperature', 0) / 10.0 if runtime else None

        thermostat_info = {
            'thermostat': thermostat_name,
            'identifier': t.get('identifier'),
            'temperature_f': actual_temp_f,
            'humidity': runtime.get('actualHumidity') if runtime else None,
            'sensors': []
        }

        # Remote sensors
        for sensor in t.get('remoteSensors', []):
            sensor_data = {
                'name': sensor.get('name'),
                'type': sensor.get('type'),
                'in_use': sensor.get('inUse', False),
            }

            for cap in sensor.get('capability', []):
                if cap['type'] == 'temperature':
                    try:
                        temp_raw = int(cap['value'])
                        sensor_data['temperature_f'] = temp_raw / 10.0
                        sensor_data['temperature_c'] = (temp_raw / 10.0 - 32) * 5 / 9
                    except (ValueError, TypeError):
                        sensor_data['temperature_f'] = None
                elif cap['type'] == 'humidity':
                    sensor_data['humidity'] = cap.get('value')
                elif cap['type'] == 'occupancy':
                    sensor_data['occupancy'] = cap.get('value') == 'true'

            thermostat_info['sensors'].append(sensor_data)

        output.append(thermostat_info)

    print(json.dumps(output, indent=2))


def cmd_wine():
    """Get wine cabinet temperatures specifically."""
    token = get_valid_token()
    selection = json.dumps({
        'selection': {
            'selectionType': 'registered',
            'selectionMatch': '',
            'includeRuntime': True,
            'includeSensors': True,
        }
    })
    result = api_request('GET', '/1/thermostat', params={'json': selection}, access_token=token)

    thermostats = result.get('thermostatList', [])
    wine_sensors = []

    for t in thermostats:
        thermostat_name = t.get('name', 'Unknown')
        # Look for wine-related thermostats and sensors
        if any(word in thermostat_name.lower() for word in ['wine', 'closet']):
            for sensor in t.get('remoteSensors', []):
                sensor_info = {'thermostat': thermostat_name, 'sensor': sensor.get('name')}
                for cap in sensor.get('capability', []):
                    if cap['type'] == 'temperature':
                        try:
                            temp_raw = int(cap['value'])
                            sensor_info['temperature_f'] = temp_raw / 10.0
                            sensor_info['temperature_c'] = round((temp_raw / 10.0 - 32) * 5 / 9, 1)
                        except (ValueError, TypeError):
                            pass
                wine_sensors.append(sensor_info)

    if not wine_sensors:
        # If no wine-labeled thermostat, show all sensors and let the user identify them
        print("No 'wine' thermostat found. Showing all sensors:", file=sys.stderr)
        for t in thermostats:
            for sensor in t.get('remoteSensors', []):
                info = {'thermostat': t.get('name'), 'sensor': sensor.get('name')}
                for cap in sensor.get('capability', []):
                    if cap['type'] == 'temperature':
                        try:
                            temp_raw = int(cap['value'])
                            info['temperature_f'] = temp_raw / 10.0
                        except: pass
                wine_sensors.append(info)

    print(json.dumps(wine_sensors, indent=2))


def cmd_check_token():
    """Verify the stored token is valid."""
    try:
        token = get_valid_token()
        result = api_request('GET', '/1/thermostat', params={
            'json': json.dumps({'selection': {'selectionType': 'registered', 'selectionMatch': ''}})
        }, access_token=token)
        count = len(result.get('thermostatList', []))
        print(json.dumps({'status': 'valid', 'thermostats': count}, indent=2))
    except Exception as e:
        print(json.dumps({'status': 'invalid', 'error': str(e)}, indent=2))


def main():
    parser = argparse.ArgumentParser(description='Ecobee API client')
    parser.add_argument('command', choices=['auth', 'auth-complete', 'thermostats', 'sensors', 'wine', 'check-token'])
    args = parser.parse_args()

    os.makedirs(STATE_DIR, exist_ok=True)

    if args.command == 'auth':
        cmd_auth()
    elif args.command == 'auth-complete':
        cmd_auth_complete()
    elif args.command == 'thermostats':
        cmd_thermostats()
    elif args.command == 'sensors':
        cmd_sensors()
    elif args.command == 'wine':
        cmd_wine()
    elif args.command == 'check-token':
        cmd_check_token()


if __name__ == '__main__':
    main()
