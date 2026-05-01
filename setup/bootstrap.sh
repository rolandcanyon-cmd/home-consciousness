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
if [[ "$NO_KITTENKONG" == false ]]; then
    FG_DIR="${AGENT_DIR}/the-goodies-python/funkygibbon"
    PYTHON3="$(which python3)"
    echo ""
    echo "Setting up FunkyGibbon..."

    # Install Python dependencies
    echo "  Installing FunkyGibbon dependencies..."
    pip3 install --quiet -r "${FG_DIR}/requirements.txt"
    pip3 install --quiet -e "${FG_DIR}"
    echo "  ✓ Dependencies installed"

    # Hash the admin password using Argon2id (same algorithm FunkyGibbon uses)
    FG_PASSWORD_HASH=$(python3 -c "
from argon2 import PasswordHasher
ph = PasswordHasher(time_cost=2, memory_cost=65536, parallelism=1, hash_len=32, salt_len=16)
print(ph.hash('${FUNKYGIBBON_PASSWORD}'))
")
    JWT_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")

    # Write .env for FunkyGibbon (readable only by the current user)
    cat > "${FG_DIR}/.env" <<ENV
ADMIN_PASSWORD_HASH=${FG_PASSWORD_HASH}
JWT_SECRET=${JWT_SECRET}
API_HOST=127.0.0.1
API_PORT=8000
ENV
    chmod 600 "${FG_DIR}/.env"
    echo "  ✓ Admin password configured"

    # Create macOS LaunchAgent for auto-start at login
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
        <string>${PYTHON3}</string>
        <string>-m</string>
        <string>funkygibbon</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${FG_DIR}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>ADMIN_PASSWORD_HASH</key>
        <string>${FG_PASSWORD_HASH}</string>
        <key>JWT_SECRET</key>
        <string>${JWT_SECRET}</string>
        <key>API_HOST</key>
        <string>127.0.0.1</string>
        <key>API_PORT</key>
        <string>8000</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/funkygibbon.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/funkygibbon.log</string>
</dict>
</plist>
PLIST
    echo "  ✓ LaunchAgent installed (auto-starts at login)"

    # Start (or restart if already loaded)
    launchctl unload "${PLIST_PATH}" 2>/dev/null || true
    launchctl load "${PLIST_PATH}"

    # Wait up to 10 seconds for FunkyGibbon to be ready
    echo "  Waiting for FunkyGibbon to start..."
    FG_READY=false
    for i in $(seq 1 10); do
        FG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "${FUNKYGIBBON_URL}/health" 2>/dev/null || echo "000")
        if [[ "$FG_STATUS" == "200" ]]; then
            FG_READY=true
            break
        fi
        sleep 1
    done

    if [[ "$FG_READY" == true ]]; then
        echo "  ✓ FunkyGibbon is running at ${FUNKYGIBBON_URL}"
    else
        echo "  ✗ FunkyGibbon did not respond within 10 seconds"
        echo "    Check logs: tail -f ~/Library/Logs/funkygibbon.log"
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
