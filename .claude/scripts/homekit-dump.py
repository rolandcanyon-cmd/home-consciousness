#!/usr/bin/env python3
"""
homekit-dump.py — Dump all HomeKit accessories from the macOS HomeKit database.

Reads ~/Library/HomeKit/core.sqlite directly (requires Full Disk Access for Terminal).
Outputs JSON with all homes, rooms, and accessories including their public keys.

Usage:
    python3 homekit-dump.py                    # full dump to stdout
    python3 homekit-dump.py --save             # save to .instar/state/homekit-dump.json
    python3 homekit-dump.py --room "Kitchen"   # filter by room name
    python3 homekit-dump.py --brief            # just names, no HAP details
"""

import sys
import os
import json
import sqlite3
import argparse
import base64
from datetime import datetime

HOMEKIT_DB = os.path.expanduser('~/Library/HomeKit/core.sqlite')


def read_homekit_db(room_filter=None):
    """Read HomeKit accessories from the local database."""
    if not os.path.exists(HOMEKIT_DB):
        return {"error": f"HomeKit database not found at {HOMEKIT_DB}. Requires Full Disk Access for Terminal."}

    try:
        conn = sqlite3.connect(HOMEKIT_DB)
        c = conn.cursor()

        # Get all rooms
        c.execute('SELECT Z_PK, ZNAME FROM ZMKFROOM ORDER BY ZNAME')
        rooms = {r[0]: r[1] for r in c.fetchall()}

        # Get all accessories with full details
        c.execute('''
            SELECT
                a.Z_PK, a.ZCONFIGUREDNAME, a.ZMODEL, a.ZMANUFACTURER,
                a.ZSERIALNUMBER, a.ZROOM, a.ZACCESSORYCATEGORY,
                a.ZUNIQUEIDENTIFIER, a.ZPUBLICKEY, a.ZPAIRINGUSERNAME,
                a.ZFIRMWAREVERSION, a.ZDISPLAYABLEFIRMWAREVERSION
            FROM ZMKFACCESSORY a
            ORDER BY a.ZROOM, a.ZCONFIGUREDNAME
        ''')
        acc_rows = c.fetchall()

        # Get services for each accessory
        c.execute('''
            SELECT s.ZACCESSORY, s.Z_PK, s.ZINSTANCEID, s.ZNAME,
                   s.ZASSOCIATEDSERVICETYPE
            FROM ZMKFSERVICE s
        ''')
        services_by_acc = {}
        for row in c.fetchall():
            acc_pk = row[0]
            if acc_pk not in services_by_acc:
                services_by_acc[acc_pk] = []
            services_by_acc[acc_pk].append({
                'pk': row[1],
                'instance_id': row[2],
                'name': row[3],
                'type': row[4],
            })

        # Build the output
        accessories_by_room = {}
        for row in acc_rows:
            pk, name, model, mfr, sn, room_fk, cat, uid, pub_key, pairing_user, fw, fw_display = row
            room_name = rooms.get(room_fk, 'Unassigned')

            if room_filter and room_filter.lower() not in room_name.lower():
                continue

            acc = {
                'name': name,
                'model': model,
                'manufacturer': mfr,
                'serial': sn,
                'room': room_name,
                'category': cat,
                'uuid': uid,
                'firmware': fw_display or fw,
                'services': services_by_acc.get(pk, []),
            }

            if pub_key:
                acc['public_key_hex'] = pub_key.hex() if isinstance(pub_key, bytes) else pub_key
                acc['public_key_b64'] = base64.b64encode(pub_key).decode() if isinstance(pub_key, bytes) else None

            if pairing_user:
                acc['pairing_username'] = pairing_user

            if room_name not in accessories_by_room:
                accessories_by_room[room_name] = []
            accessories_by_room[room_name].append(acc)

        # Sort rooms
        rooms_list = []
        for room_name in sorted(accessories_by_room.keys(), key=lambda x: x or ''):
            rooms_list.append({
                'name': room_name,
                'accessories': sorted(accessories_by_room[room_name], key=lambda x: x['name'] or ''),
            })

        conn.close()

        total = sum(len(r['accessories']) for r in rooms_list)
        return {
            'dumped_at': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
            'source': HOMEKIT_DB,
            'total_accessories': total,
            'total_rooms': len(rooms_list),
            'rooms': rooms_list,
        }

    except PermissionError:
        return {"error": "Permission denied reading HomeKit database. Grant Full Disk Access to Terminal in System Settings."}
    except Exception as e:
        return {"error": str(e)}


def brief_output(data):
    """Print a concise listing of rooms and accessory names."""
    if 'error' in data:
        print(f"Error: {data['error']}")
        return

    print(f"HomeKit Accessories — {data['total_accessories']} total across {data['total_rooms']} rooms")
    print(f"(as of {data['dumped_at']})\n")
    for room in data['rooms']:
        print(f"  {room['name']} ({len(room['accessories'])})")
        for acc in room['accessories']:
            model_str = f" [{acc['model']}]" if acc['model'] else ""
            print(f"    • {acc['name']}{model_str}")
    print()


def main():
    parser = argparse.ArgumentParser(description='Dump HomeKit accessories from macOS database')
    parser.add_argument('--save', action='store_true', help='Save to .instar/state/homekit-dump.json')
    parser.add_argument('--room', help='Filter by room name (case-insensitive)')
    parser.add_argument('--brief', action='store_true', help='Print concise human-readable summary')
    args = parser.parse_args()

    data = read_homekit_db(room_filter=args.room)

    if args.brief:
        brief_output(data)
    else:
        output = json.dumps(data, indent=2, default=str)
        print(output)

    if args.save and 'error' not in data:
        save_path = os.path.join(os.path.dirname(__file__), '../../.instar/state/homekit-dump.json')
        save_path = os.path.abspath(save_path)
        full_data = data if not args.room else read_homekit_db()  # save full dump even if filtered
        with open(save_path, 'w') as f:
            json.dump(full_data, f, indent=2, default=str)
        print(f"[Saved to {save_path}]", file=sys.stderr)


if __name__ == '__main__':
    main()
