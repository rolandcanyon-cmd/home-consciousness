#!/usr/bin/env bash
# add-user.sh — Add an authorized iMessage contact to config.json
#
# Keeps both contact locations in sync:
#   config.imessage.allowedNumbers                (read by instar config commands)
#   config.messaging[].config.authorizedContacts  (read by iMessage adapter)
#
# Usage: ./setup/add-user.sh "corfehill@icloud.com"
#        ./setup/add-user.sh "+14085551234"
#        ./setup/add-user.sh --list
#        ./setup/add-user.sh --remove "addr"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${AGENT_DIR}/.instar/config.json"

if [[ ! -f "${CONFIG}" ]]; then
    echo "Error: config.json not found at ${CONFIG}"
    echo "Run ./setup/bootstrap.sh first."
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 \"imessage-address-or-phone\""
    echo "       $0 --list"
    echo "       $0 --remove \"imessage-address-or-phone\""
    exit 1
fi

case "$1" in
    --list)
        python3 - "${CONFIG}" <<'PYEOF'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())

allowed = cfg.get("imessage", {}).get("allowedNumbers", [])
authorized = []
for m in cfg.get("messaging", []):
    if m.get("type") == "imessage":
        authorized = m.get("config", {}).get("authorizedContacts", [])
        break

all_contacts = sorted(set(allowed) | set(authorized))
if all_contacts:
    print("Authorized iMessage contacts:")
    for c in all_contacts:
        locs = []
        if c in allowed:     locs.append("allowedNumbers")
        if c in authorized:  locs.append("authorizedContacts")
        note = "" if len(locs) == 2 else f"  ⚠ only in {locs[0]}"
        print(f"  {c}{note}")
else:
    print("No authorized contacts configured.")
PYEOF
        exit 0
        ;;
    --remove)
        ACTION="remove"
        ADDRESS="${2:-}"
        [[ -z "$ADDRESS" ]] && { echo "Error: --remove requires an address"; exit 1; }
        ;;
    -*)
        echo "Unknown option: $1"; exit 1
        ;;
    *)
        ACTION="add"
        ADDRESS="$1"
        ;;
esac

python3 - "${CONFIG}" "${ACTION}" "${ADDRESS}" <<'PYEOF'
import json, pathlib, sys

config_path = pathlib.Path(sys.argv[1])
action      = sys.argv[2]
address     = sys.argv[3]

cfg = json.loads(config_path.read_text())

# Location 1: config.imessage.allowedNumbers
allowed = cfg.setdefault("imessage", {}).setdefault("allowedNumbers", [])

# Location 2: config.messaging[imessage].config.authorizedContacts
messaging = cfg.setdefault("messaging", [])
adapter = next((m for m in messaging if m.get("type") == "imessage"), None)
if adapter is None:
    adapter = {"type": "imessage", "enabled": True, "config": {}}
    messaging.append(adapter)
authorized = adapter.setdefault("config", {}).setdefault("authorizedContacts", [])

if action == "add":
    changed = False
    if address not in allowed:
        allowed.append(address)
        changed = True
    if address not in authorized:
        authorized.append(address)
        changed = True
    if changed:
        config_path.write_text(json.dumps(cfg, indent=2) + "\n")
        print(f"  ✓ Added to both locations: {address}")
    else:
        print(f"  Already authorized: {address}")

elif action == "remove":
    changed = False
    if address in allowed:
        allowed.remove(address)
        changed = True
    if address in authorized:
        authorized.remove(address)
        changed = True
    if changed:
        config_path.write_text(json.dumps(cfg, indent=2) + "\n")
        print(f"  ✓ Removed from both locations: {address}")
    else:
        print(f"  Not found: {address}")
        sys.exit(1)
PYEOF

echo ""
echo "Restart to apply: instar server stop && NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start"
