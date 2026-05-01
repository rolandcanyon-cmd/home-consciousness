#!/usr/bin/env bash
# add-user.sh — Add an authorized iMessage contact to config.json
# Usage: ./setup/add-user.sh "corfehill@icloud.com"
#        ./setup/add-user.sh "+14085551234"
#        ./setup/add-user.sh --list        (show current contacts)
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

ACTION="add"
ADDRESS=""

case "$1" in
    --list)
        python3 - <<PYEOF
import json, pathlib
cfg = json.loads(pathlib.Path("${CONFIG}").read_text())
contacts = cfg.get("messaging", [{}])
contacts = next((m for m in contacts if m.get("type") == "imessage"), {})
contacts = contacts.get("config", {}).get("authorizedContacts", [])
if contacts:
    print("Authorized iMessage contacts:")
    for c in contacts:
        print(f"  {c}")
else:
    print("No authorized contacts configured.")
PYEOF
        exit 0
        ;;
    --remove)
        ACTION="remove"
        ADDRESS="${2:-}"
        if [[ -z "$ADDRESS" ]]; then
            echo "Error: --remove requires an address"
            exit 1
        fi
        ;;
    -*)
        echo "Unknown option: $1"
        exit 1
        ;;
    *)
        ADDRESS="$1"
        ;;
esac

python3 - <<PYEOF
import json, pathlib, sys

config_path = pathlib.Path("${CONFIG}")
cfg = json.loads(config_path.read_text())

messaging = cfg.setdefault("messaging", [])
adapter = next((m for m in messaging if m.get("type") == "imessage"), None)
if adapter is None:
    adapter = {"type": "imessage", "enabled": True, "config": {}}
    messaging.append(adapter)

contacts = adapter.setdefault("config", {}).setdefault("authorizedContacts", [])
address = "${ADDRESS}"
action = "${ACTION}"

if action == "add":
    if address in contacts:
        print(f"  Already authorized: {address}")
    else:
        contacts.append(address)
        config_path.write_text(json.dumps(cfg, indent=2) + "\n")
        print(f"  ✓ Added: {address}")
elif action == "remove":
    if address not in contacts:
        print(f"  Not found: {address}")
        sys.exit(1)
    else:
        contacts.remove(address)
        config_path.write_text(json.dumps(cfg, indent=2) + "\n")
        print(f"  ✓ Removed: {address}")
PYEOF

echo ""
echo "Restart the server to apply: instar server stop && NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start"
