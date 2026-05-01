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

    # Start (or restart if already loaded)
    launchctl unload "${PLIST_PATH}" 2>/dev/null || true
    launchctl load "${PLIST_PATH}"

    # Tail the log for up to 15 seconds — show output and check for errors
    echo "  Waiting for FunkyGibbon to start (tailing log)..."
    echo "  ---"
    FG_READY=false
    for i in $(seq 1 15); do
        sleep 1
        # Print any new log lines
        if [[ -f "${FG_LOG}" ]]; then
            tail -n 5 "${FG_LOG}" 2>/dev/null | sed 's/^/  | /'
        fi
        FG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 "${FUNKYGIBBON_URL}/health" 2>/dev/null || echo "000")
        if [[ "$FG_STATUS" == "200" ]]; then
            FG_READY=true
            break
        fi
        # Bail early if log shows a fatal error
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

echo ""
echo "=== Next Steps ==="
echo "1. Configure .instar/config.json (auth token, Anthropic key, iMessage whitelist)"
echo "   See: instar config --help"
echo "2. Start the agent: instar server start"
echo "3. Verify: curl http://localhost:4040/health"
echo ""
echo "For HA integration, add HA scripts to .claude/scripts/ and context to .instar/context/"
