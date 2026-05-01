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

# --- FunkyGibbon connectivity check ---
if [[ "$NO_KITTENKONG" == false ]]; then
    echo ""
    echo "Checking FunkyGibbon at ${FUNKYGIBBON_URL}..."
    FG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -u ":${FUNKYGIBBON_PASSWORD}" \
        "${FUNKYGIBBON_URL}/api/health" 2>/dev/null || echo "000")
    if [[ "$FG_STATUS" == "200" ]]; then
        echo "  ✓ FunkyGibbon reachable and password accepted"
    elif [[ "$FG_STATUS" == "401" || "$FG_STATUS" == "403" ]]; then
        echo "  ✗ FunkyGibbon reachable but password rejected (HTTP ${FG_STATUS})"
        echo "    Check your FunkyGibbon password and re-run with --force"
    elif [[ "$FG_STATUS" == "000" ]]; then
        echo "  ✗ FunkyGibbon not reachable at ${FUNKYGIBBON_URL}"
        echo "    Make sure FunkyGibbon is running before starting the agent"
    else
        echo "  ⚠ FunkyGibbon returned HTTP ${FG_STATUS} — check it is running correctly"
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
