#!/bin/bash
# House consciousness agent bootstrap script.
# Run this after cloning the repo on a new machine.
#
# Usage:
#   ./setup/bootstrap.sh --name AGENT_NAME [options]
#
# Options:
#   --name NAME            Agent name (required)
#   --user PRIMARY_USER    Primary user name (required)
#   --fg-url URL           FunkyGibbon URL (default: http://localhost:8000)
#   --fg-password PASS     FunkyGibbon password (prompted if omitted)
#   --no-kittenkong        Omit kittenkong MCP server from settings.json
#   --force                Overwrite existing AGENT.md and MEMORY.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

AGENT_NAME=""
PRIMARY_USER=""
FUNKYGIBBON_URL="http://localhost:8000"
FUNKYGIBBON_PASSWORD=""
NO_KITTENKONG=false
FORCE=false
CREATED_DATE="$(date +%Y-%m-%d)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)         AGENT_NAME="$2"; shift 2 ;;
        --user)         PRIMARY_USER="$2"; shift 2 ;;
        --fg-url)       FUNKYGIBBON_URL="$2"; shift 2 ;;
        --fg-password)  FUNKYGIBBON_PASSWORD="$2"; shift 2 ;;
        --no-kittenkong) NO_KITTENKONG=true; shift ;;
        --force)        FORCE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$AGENT_NAME" ]]; then
    echo "Error: --name is required"
    echo "Usage: $0 --name AGENT_NAME [--user NAME] [--fg-url URL] [--fg-password PASS]"
    exit 1
fi

if [[ "$NO_KITTENKONG" == false && -z "$FUNKYGIBBON_PASSWORD" ]]; then
    read -rsp "FunkyGibbon password (Enter to skip kittenkong MCP): " FUNKYGIBBON_PASSWORD
    echo
    if [[ -z "$FUNKYGIBBON_PASSWORD" ]]; then
        NO_KITTENKONG=true
    fi
fi

echo "=== House Consciousness Bootstrap ==="
echo "Agent:     $AGENT_NAME"
echo "Directory: $AGENT_DIR"
echo "User:      $PRIMARY_USER"
echo ""

# --- Ensure submodules are initialized and up to date ---
echo "Updating submodules..."
git -C "${AGENT_DIR}" submodule update --init --recursive
echo "  ✓ Submodules ready"
echo ""

# --- settings.json ---
echo "Generating .claude/settings.json..."
TEMPLATE="${SCRIPT_DIR}/settings.json.template"
TARGET="${AGENT_DIR}/.claude/settings.json"

if [[ "$NO_KITTENKONG" == true ]]; then
    # Strip kittenkong block — remove from "kittenkong": { ... } through closing brace
    python3 - <<PYEOF
import json, sys

with open("${TEMPLATE}") as f:
    s = json.load(f)

s.get("mcpServers", {}).pop("kittenkong", None)

with open("${TARGET}", "w") as f:
    json.dump(s, f, indent=4)
    f.write("\n")
PYEOF
    # Then do the path substitution in-place
    python3 - <<PYEOF
content = open("${TARGET}").read()
content = content.replace("{{AGENT_DIR}}", "${AGENT_DIR}")
open("${TARGET}", "w").write(content)
PYEOF
else
    python3 - <<PYEOF
content = open("${TEMPLATE}").read()
content = content.replace("{{AGENT_DIR}}", "${AGENT_DIR}")
content = content.replace("{{FUNKYGIBBON_URL}}", "${FUNKYGIBBON_URL}")
content = content.replace("{{FUNKYGIBBON_PASSWORD}}", "${FUNKYGIBBON_PASSWORD}")
open("${TARGET}", "w").write(content)
PYEOF
fi
echo "  ✓ .claude/settings.json"

# --- AGENT.md ---
if [[ -f "${AGENT_DIR}/.instar/AGENT.md" && "$FORCE" == false ]]; then
    echo "  ⚠ .instar/AGENT.md already exists, skipping (use --force to overwrite)"
else
    sed \
        -e "s|{{AGENT_NAME}}|${AGENT_NAME}|g" \
        -e "s|{{CREATED_DATE}}|${CREATED_DATE}|g" \
        "${SCRIPT_DIR}/AGENT.md.template" > "${AGENT_DIR}/.instar/AGENT.md"
    echo "  ✓ .instar/AGENT.md"
fi

# --- MEMORY.md ---
if [[ -f "${AGENT_DIR}/.instar/MEMORY.md" && "$FORCE" == false ]]; then
    echo "  ⚠ .instar/MEMORY.md already exists, skipping (use --force to overwrite)"
else
    sed \
        -e "s|{{AGENT_NAME}}|${AGENT_NAME}|g" \
        -e "s|{{CREATED_DATE}}|${CREATED_DATE}|g" \
        -e "s|{{PRIMARY_USER}}|${PRIMARY_USER}|g" \
        "${SCRIPT_DIR}/MEMORY.md.template" > "${AGENT_DIR}/.instar/MEMORY.md"
    echo "  ✓ .instar/MEMORY.md (fresh)"
fi

# --- FunkyGibbon setup ---
# Mirrors the approach used by install.sh in the-goodies-python:
# venv at the-goodies-python/venv, start_funkygibbon.sh for startup,
# LaunchAgent pointing to that script for auto-start.
if [[ "$NO_KITTENKONG" == false ]]; then
    FG_PARENT_DIR="${AGENT_DIR}/the-goodies-python"
    FG_DIR="${FG_PARENT_DIR}/funkygibbon"
    FG_VENV="${FG_PARENT_DIR}/venv"
    FG_START_SCRIPT="${FG_PARENT_DIR}/start_funkygibbon.sh"
    FG_LOG="${HOME}/Library/Logs/funkygibbon.log"
    echo ""
    echo "Setting up FunkyGibbon..."

    # Create virtual environment if needed (at the-goodies-python/venv, matching install.sh)
    if [[ ! -d "${FG_VENV}" ]]; then
        echo "  Creating Python virtual environment..."
        python3 -m venv "${FG_VENV}"
    fi
    VENV_PYTHON="${FG_VENV}/bin/python"
    VENV_PIP="${FG_VENV}/bin/pip"

    # Install dependencies
    echo "  Installing FunkyGibbon dependencies..."
    "${VENV_PIP}" install --quiet --upgrade pip wheel
    "${VENV_PIP}" install --quiet -r "${FG_DIR}/requirements.txt"
    echo "  ✓ Dependencies installed"

    # Hash the admin password (same method as install.sh)
    FG_PASSWORD_HASH=$("${VENV_PYTHON}" -c "
import sys
sys.path.insert(0, '${FG_PARENT_DIR}')
from funkygibbon.auth.password import PasswordManager
pm = PasswordManager()
print(pm.hash_password('${FUNKYGIBBON_PASSWORD}'))
")
    JWT_SECRET=$("${VENV_PYTHON}" -c "import secrets; print(secrets.token_hex(32))")
    echo "  ✓ Admin password configured"

    # Generate start_funkygibbon.sh (same pattern as install.sh)
    cat > "${FG_START_SCRIPT}" <<STARTSCRIPT
#!/bin/bash
# Auto-generated by bootstrap — do not edit manually, re-run bootstrap to update

export ADMIN_PASSWORD_HASH='${FG_PASSWORD_HASH}'
export JWT_SECRET="${JWT_SECRET}"

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
cd "\$SCRIPT_DIR"

source venv/bin/activate
export PYTHONPATH="\$SCRIPT_DIR:\$PYTHONPATH"

echo "Starting FunkyGibbon server..."
python -m funkygibbon
STARTSCRIPT
    chmod +x "${FG_START_SCRIPT}"
    echo "  ✓ start_funkygibbon.sh generated"

    # Create macOS LaunchAgent pointing to the start script
    PLIST_PATH="${HOME}/Library/LaunchAgents/com.funkygibbon.plist"
    mkdir -p "${HOME}/Library/LaunchAgents"
    cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.funkygibbon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${FG_START_SCRIPT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${FG_LOG}</string>
    <key>StandardErrorPath</key>
    <string>${FG_LOG}</string>
</dict>
</plist>
PLIST
    echo "  ✓ LaunchAgent installed (auto-starts at login)"

    # Truncate log before starting so we only see output from this run
    : > "${FG_LOG}"

    # Start (or restart if already loaded)
    launchctl unload "${PLIST_PATH}" 2>/dev/null || true
    launchctl load "${PLIST_PATH}"

    # Tail the log for up to 15 seconds — show output and check for errors
    echo "  Waiting for FunkyGibbon to start (tailing log)..."
    echo "  ---"
    FG_READY=false
    LAST_LINES=0
    for i in $(seq 1 15); do
        sleep 1
        # Print any new log lines since last check
        if [[ -f "${FG_LOG}" ]]; then
            CURRENT_LINES=$(wc -l < "${FG_LOG}" 2>/dev/null || echo 0)
            if [[ "$CURRENT_LINES" -gt "$LAST_LINES" ]]; then
                tail -n +"$((LAST_LINES + 1))" "${FG_LOG}" 2>/dev/null | sed 's/^/  | /'
                LAST_LINES="$CURRENT_LINES"
            fi
        fi
        FG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 "${FUNKYGIBBON_URL}/health" 2>/dev/null || echo "000")
        if [[ "$FG_STATUS" == "200" ]]; then
            FG_READY=true
            break
        fi
        # Bail early if log shows a fatal startup error
        if [[ -f "${FG_LOG}" ]] && grep -q "ImportError\|ModuleNotFoundError\|Traceback" "${FG_LOG}" 2>/dev/null; then
            echo "  ---"
            echo "  ✗ FunkyGibbon crashed on startup — full log:"
            cat "${FG_LOG}" | sed 's/^/  | /'
            break
        fi
    done
    echo "  ---"

    if [[ "$FG_READY" == true ]]; then
        echo "  ✓ FunkyGibbon is running at ${FUNKYGIBBON_URL}"
    else
        echo "  ✗ FunkyGibbon did not start — see log above"
        echo "    To retry manually: ${FG_START_SCRIPT}"
    fi
fi

# --- NODE_EXTRA_CA_CERTS ---
# Homebrew Node.js has a different CA bundle from Claude Code's bundled runtime.
# Without this, Instar fails with UNABLE_TO_GET_ISSUER_CERT_LOCALLY when calling
# Anthropic APIs. Set it now for the current shell and persist it to .zshrc.
echo ""
echo "Configuring Node.js TLS certificates..."
CA_EXPORT='export NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem'
ZSHRC="${HOME}/.zshrc"
if ! grep -qF "$CA_EXPORT" "$ZSHRC" 2>/dev/null; then
    echo "$CA_EXPORT" >> "$ZSHRC"
    echo "  ✓ Added NODE_EXTRA_CA_CERTS to ~/.zshrc"
else
    echo "  ✓ NODE_EXTRA_CA_CERTS already in ~/.zshrc"
fi
export NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem

CONFIG_FILE="${AGENT_DIR}/.instar/config.json"

# --- Initial config.json (API key + iMessage whitelist) ---
# Write directly to config.json rather than using 'instar config set'.
# 'instar config set' spawns Claude Code for validation, which requires auth —
# creating a chicken-and-egg problem before the API key is configured.
echo ""
echo "=== Initial Configuration ==="
echo "Edit ${CONFIG_FILE} to set your credentials."
echo ""
echo "Add your Anthropic API key (get one at https://console.anthropic.com):"
echo ""
python3 - <<PYEOF
import json, pathlib

path = pathlib.Path("${CONFIG_FILE}")
config = json.loads(path.read_text()) if path.exists() else {}

# Show current state
sessions = config.get("sessions", {})
imessage = config.get("imessage", {})
key = sessions.get("anthropicApiKey", "")
allowed = imessage.get("allowedNumbers", [])

print("  Current sessions.anthropicApiKey:", repr(key) if key else "(not set)")
print("  Current imessage.allowedNumbers: ", allowed if allowed else "(not set)")
PYEOF

echo ""
echo "To set the API key without spawning Claude:"
echo "  python3 -c \""
echo "import json, pathlib"
echo "path = pathlib.Path('${CONFIG_FILE}')"
echo "c = json.loads(path.read_text()) if path.exists() else {}"
echo "c.setdefault('sessions', {})['anthropicApiKey'] = 'sk-ant-YOUR_KEY'"
echo "c.setdefault('imessage', {})['allowedNumbers'] = ['you@icloud.com']"
echo "path.write_text(json.dumps(c, indent=2))"
echo "\""
echo ""
echo "Then start the agent:"
echo "  NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start"
echo ""
echo "Verify:"
echo "  curl http://localhost:4040/health"
echo ""
echo "Optional — auto-start at login (after the key is set and server confirmed working):"
echo "  instar server install"
echo ""
echo "For HA integration, add HA scripts to .claude/scripts/ and context to .instar/context/"
