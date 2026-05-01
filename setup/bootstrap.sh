#!/bin/bash
# House consciousness agent bootstrap script.
# Run this after cloning the repo on a new machine.
# Safe to rerun — every step checks whether it's already done before acting.
#
# Usage:
#   ./setup/bootstrap.sh --name AGENT_NAME --user YOUR_NAME [options]
#
# Options:
#   --name NAME            Agent name (required)
#   --user PRIMARY_USER    Your first name (required)
#   --api-key KEY          Anthropic API key (prompted if not set)
#   --imessage-user ADDR   iMessage address/phone to whitelist (prompted if not set)
#   --fg-url URL           FunkyGibbon URL (default: http://localhost:8000)
#   --fg-password PASS     FunkyGibbon password (prompted if FunkyGibbon not running)
#   --no-kittenkong        Omit kittenkong MCP server from settings.json
#   --force                Overwrite existing AGENT.md and MEMORY.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${AGENT_DIR}/.instar/config.json"

AGENT_NAME=""
PRIMARY_USER=""
API_KEY=""
IMESSAGE_USER=""
FUNKYGIBBON_URL="http://localhost:8000"
FUNKYGIBBON_PASSWORD=""
NO_KITTENKONG=false
FORCE=false
CREATED_DATE="$(date +%Y-%m-%d)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)          AGENT_NAME="$2"; shift 2 ;;
        --user)          PRIMARY_USER="$2"; shift 2 ;;
        --api-key)       API_KEY="$2"; shift 2 ;;
        --imessage-user) IMESSAGE_USER="$2"; shift 2 ;;
        --fg-url)        FUNKYGIBBON_URL="$2"; shift 2 ;;
        --fg-password)   FUNKYGIBBON_PASSWORD="$2"; shift 2 ;;
        --no-kittenkong) NO_KITTENKONG=true; shift ;;
        --force)         FORCE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$AGENT_NAME" ]]; then
    echo "Error: --name is required"
    echo "Usage: $0 --name AGENT_NAME --user YOUR_NAME [options]"
    exit 1
fi

# --- Load existing config values as defaults ---
# So rerunning the script doesn't re-prompt for things already configured.
if [[ -f "${CONFIG_FILE}" ]]; then
    _existing_key=$(python3 -c "
import json, pathlib
c = json.loads(pathlib.Path('${CONFIG_FILE}').read_text())
print(c.get('sessions', {}).get('anthropicApiKey', ''))
" 2>/dev/null || echo "")
    _existing_imessage=$(python3 -c "
import json, pathlib
c = json.loads(pathlib.Path('${CONFIG_FILE}').read_text())
nums = c.get('imessage', {}).get('allowedNumbers', [])
print(nums[0] if nums else '')
" 2>/dev/null || echo "")
    [[ -z "$API_KEY" && -n "$_existing_key" ]]      && API_KEY="$_existing_key"
    [[ -z "$IMESSAGE_USER" && -n "$_existing_imessage" ]] && IMESSAGE_USER="$_existing_imessage"
fi

# --- Check if FunkyGibbon is already running ---
FG_ALREADY_RUNNING=false
if [[ "$NO_KITTENKONG" == false ]]; then
    _fg_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "${FUNKYGIBBON_URL}/health" 2>/dev/null || echo "000")
    [[ "$_fg_status" == "200" ]] && FG_ALREADY_RUNNING=true
fi

# --- Prompts (only for values still missing) ---
if [[ "$NO_KITTENKONG" == false && "$FG_ALREADY_RUNNING" == false && -z "$FUNKYGIBBON_PASSWORD" ]]; then
    read -rsp "FunkyGibbon password (Enter to skip kittenkong MCP): " FUNKYGIBBON_PASSWORD
    echo
    [[ -z "$FUNKYGIBBON_PASSWORD" ]] && NO_KITTENKONG=true
fi

if [[ -z "$API_KEY" ]]; then
    echo "Anthropic API key (from console.anthropic.com → Settings → API Keys):"
    read -rsp "  sk-ant-... : " API_KEY
    echo
    if [[ -z "$API_KEY" ]]; then
        echo "Error: API key is required"
        exit 1
    fi
fi

if [[ -z "$IMESSAGE_USER" ]]; then
    echo "Your iMessage address or phone number (the account you'll message FROM):"
    read -rp "  e.g. you@icloud.com or +15551234567 : " IMESSAGE_USER
    echo
    [[ -z "$IMESSAGE_USER" ]] && echo "Warning: no iMessage user set — you can add one later in ${CONFIG_FILE}"
fi

# --- Header ---
echo ""
echo "=== House Consciousness Bootstrap ==="
echo "Agent:     $AGENT_NAME"
echo "Directory: $AGENT_DIR"
echo "User:      $PRIMARY_USER"
echo ""

# --- Submodules ---
echo "Updating submodules..."
git -C "${AGENT_DIR}" submodule update --init --recursive
echo "  ✓ Submodules ready"
echo ""

# --- imsg (iMessage CLI) ---
echo "Checking imsg..."
if command -v imsg &>/dev/null; then
    echo "  ✓ imsg already installed ($(which imsg))"
else
    echo "  Installing imsg (steipete/tap)..."
    brew tap steipete/tap
    brew install imsg
    echo "  ✓ imsg installed"
fi
echo ""

# --- attachments-sync (Go helper) ---
# Mirrors iMessage photo attachments to a readable location.
# Needs Full Disk Access — see the FDA prompt at the end of this script.
ATTSYNC_SRC="${AGENT_DIR}/.instar/tools/attachments-sync"
ATTSYNC_BIN="${AGENT_DIR}/.instar/bin/instar-attachments-sync"
ATTSYNC_PLIST="${HOME}/Library/LaunchAgents/ai.instar.AttachmentsWatcher.plist"
ATTSYNC_LOG="${AGENT_DIR}/.instar/logs/attachments-watcher.log"
ATTSYNC_ERR="${AGENT_DIR}/.instar/logs/attachments-watcher.err"

echo "Building attachments-sync..."
mkdir -p "${AGENT_DIR}/.instar/bin" "${AGENT_DIR}/.instar/logs"
if command -v go &>/dev/null; then
    (cd "${ATTSYNC_SRC}" && go build -o "${ATTSYNC_BIN}" .)
    echo "  ✓ Binary built: ${ATTSYNC_BIN}"
else
    echo "  ✗ Go not found — install with: brew install go"
    echo "    Then rerun this script to build attachments-sync"
fi

# Install LaunchAgent (idempotent)
mkdir -p "${HOME}/Library/LaunchAgents"
cat > "${ATTSYNC_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.instar.AttachmentsWatcher</string>
    <key>Program</key>
    <string>${ATTSYNC_BIN}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${ATTSYNC_LOG}</string>
    <key>StandardErrorPath</key>
    <string>${ATTSYNC_ERR}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
PLIST

if [[ -f "${ATTSYNC_BIN}" ]]; then
    launchctl unload "${ATTSYNC_PLIST}" 2>/dev/null || true
    launchctl load "${ATTSYNC_PLIST}"
    echo "  ✓ AttachmentsWatcher LaunchAgent installed"
else
    echo "  ⚠ LaunchAgent written but not loaded — binary missing (build Go first)"
fi
echo ""

# --- settings.json ---
echo "Generating .claude/settings.json..."
TEMPLATE="${SCRIPT_DIR}/settings.json.template"
TARGET="${AGENT_DIR}/.claude/settings.json"

if [[ "$NO_KITTENKONG" == true ]]; then
    python3 - <<PYEOF
import json
with open("${TEMPLATE}") as f:
    s = json.load(f)
s.get("mcpServers", {}).pop("kittenkong", None)
with open("${TARGET}", "w") as f:
    json.dump(s, f, indent=4)
    f.write("\n")
PYEOF
    python3 - <<PYEOF
content = open("${TARGET}").read().replace("{{AGENT_DIR}}", "${AGENT_DIR}")
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
    echo "  ✓ .instar/AGENT.md already exists (use --force to overwrite)"
else
    sed \
        -e "s|{{AGENT_NAME}}|${AGENT_NAME}|g" \
        -e "s|{{CREATED_DATE}}|${CREATED_DATE}|g" \
        "${SCRIPT_DIR}/AGENT.md.template" > "${AGENT_DIR}/.instar/AGENT.md"
    echo "  ✓ .instar/AGENT.md"
fi

# --- MEMORY.md ---
if [[ -f "${AGENT_DIR}/.instar/MEMORY.md" && "$FORCE" == false ]]; then
    echo "  ✓ .instar/MEMORY.md already exists (use --force to overwrite)"
else
    sed \
        -e "s|{{AGENT_NAME}}|${AGENT_NAME}|g" \
        -e "s|{{CREATED_DATE}}|${CREATED_DATE}|g" \
        -e "s|{{PRIMARY_USER}}|${PRIMARY_USER}|g" \
        "${SCRIPT_DIR}/MEMORY.md.template" > "${AGENT_DIR}/.instar/MEMORY.md"
    echo "  ✓ .instar/MEMORY.md"
fi

# --- FunkyGibbon setup ---
if [[ "$NO_KITTENKONG" == false ]]; then
    FG_PARENT_DIR="${AGENT_DIR}/the-goodies-python"
    FG_DIR="${FG_PARENT_DIR}/funkygibbon"
    FG_VENV="${FG_PARENT_DIR}/venv"
    FG_START_SCRIPT="${FG_PARENT_DIR}/start_funkygibbon.sh"
    FG_LOG="${HOME}/Library/Logs/funkygibbon.log"
    echo ""
    echo "Setting up FunkyGibbon..."

    if [[ "$FG_ALREADY_RUNNING" == true ]]; then
        echo "  ✓ FunkyGibbon already running at ${FUNKYGIBBON_URL} — skipping setup"
    else
        # Create venv if needed
        if [[ ! -d "${FG_VENV}" ]]; then
            echo "  Creating Python virtual environment..."
            python3 -m venv "${FG_VENV}"
        fi
        VENV_PYTHON="${FG_VENV}/bin/python"
        VENV_PIP="${FG_VENV}/bin/pip"

        # Install/upgrade dependencies
        echo "  Installing FunkyGibbon dependencies..."
        "${VENV_PIP}" install --quiet --upgrade pip wheel
        "${VENV_PIP}" install --quiet -r "${FG_DIR}/requirements.txt"
        echo "  ✓ Dependencies installed"

        # Hash the admin password
        FG_PASSWORD_HASH=$("${VENV_PYTHON}" -c "
import sys
sys.path.insert(0, '${FG_PARENT_DIR}')
from funkygibbon.auth.password import PasswordManager
pm = PasswordManager()
print(pm.hash_password('${FUNKYGIBBON_PASSWORD}'))
")
        JWT_SECRET=$("${VENV_PYTHON}" -c "import secrets; print(secrets.token_hex(32))")
        echo "  ✓ Admin password configured"

        # Generate start_funkygibbon.sh
        cat > "${FG_START_SCRIPT}" <<STARTSCRIPT
#!/bin/bash
# Auto-generated by bootstrap — rerun bootstrap to update

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

        # LaunchAgent
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

        # Start (or restart)
        : > "${FG_LOG}"
        launchctl unload "${PLIST_PATH}" 2>/dev/null || true
        launchctl load "${PLIST_PATH}"

        # Tail log until healthy or error
        echo "  Waiting for FunkyGibbon to start (tailing log)..."
        echo "  ---"
        FG_READY=false
        LAST_LINES=0
        for i in $(seq 1 15); do
            sleep 1
            if [[ -f "${FG_LOG}" ]]; then
                CURRENT_LINES=$(wc -l < "${FG_LOG}" 2>/dev/null || echo 0)
                if [[ "$CURRENT_LINES" -gt "$LAST_LINES" ]]; then
                    tail -n +"$((LAST_LINES + 1))" "${FG_LOG}" 2>/dev/null | sed 's/^/  | /'
                    LAST_LINES="$CURRENT_LINES"
                fi
            fi
            _fg_http=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 "${FUNKYGIBBON_URL}/health" 2>/dev/null || echo "000")
            if [[ "$_fg_http" == "200" ]]; then
                FG_READY=true
                break
            fi
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
fi

# --- NODE_EXTRA_CA_CERTS ---
# Homebrew Node.js has a different CA bundle from Claude Code's bundled runtime.
# Without this, Instar fails with UNABLE_TO_GET_ISSUER_CERT_LOCALLY when calling
# Anthropic APIs.
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

# --- config.json ---
# Write directly — never use 'instar config set' before the API key is present,
# as it spawns Claude Code which then requires OAuth auth (chicken-and-egg).
echo ""
echo "Writing config.json..."
python3 - <<PYEOF
import json, pathlib, secrets

path = pathlib.Path("${CONFIG_FILE}")
config = json.loads(path.read_text()) if path.exists() else {}

import shutil, os

# --- API key ---
config.setdefault("sessions", {})["anthropicApiKey"] = "${API_KEY}"

# --- Auth token ---
if not config.get("authToken"):
    config["authToken"] = secrets.token_hex(32)

# --- Session paths (critical — without these instar can't spawn Claude headlessly) ---
claude_path = shutil.which("claude") or os.path.expanduser("~/homebrew/bin/claude")
tmux_path   = shutil.which("tmux")   or "/opt/homebrew/bin/tmux"
sessions = config.setdefault("sessions", {})
sessions.setdefault("claudePath", claude_path)
sessions.setdefault("tmuxPath",   tmux_path)
sessions.setdefault("maxSessions", 10)
sessions.setdefault("idlePromptKillMinutes", 60)
sessions.setdefault("defaultMaxDurationMinutes", 480)

# --- Scheduler ---
config.setdefault("scheduler", {})["enabled"] = True
config["scheduler"].setdefault("maxParallelJobs", 2)

# --- Tunnel (quick Cloudflare tunnel for remote access) ---
config.setdefault("tunnel", {"enabled": True, "type": "quick"})

# --- iMessage messaging adapter ---
imessage_user = "${IMESSAGE_USER}".strip()
imsg_path = shutil.which("imsg") or os.path.expanduser("~/homebrew/bin/imsg")
imessage_dir = "${AGENT_DIR}/.instar/imessage"
db_path = imessage_dir + "/chat.db"
os.makedirs(imessage_dir, exist_ok=True)

messaging = config.setdefault("messaging", [])
imessage_adapter = next((m for m in messaging if m.get("type") == "imessage"), None)
if imessage_adapter is None:
    imessage_adapter = {"type": "imessage", "enabled": True, "config": {}}
    messaging.append(imessage_adapter)

cfg = imessage_adapter.setdefault("config", {})
cfg["cliPath"] = imsg_path
cfg.setdefault("autoReconnect", True)
cfg.setdefault("maxReconnectAttempts", 10)
cfg.setdefault("immediateAck", {"enabled": True, "message": "...", "cooldownSeconds": 30})
cfg.setdefault("directMessageTrigger", "always")
cfg["dbPath"] = db_path

if imessage_user:
    contacts = cfg.setdefault("authorizedContacts", [])
    if imessage_user not in contacts:
        contacts.append(imessage_user)

path.write_text(json.dumps(config, indent=2) + "\n")
print(f"  claudePath: {claude_path}")
print(f"  tmuxPath:   {tmux_path}")
print(f"  imsg:       {imsg_path}")
PYEOF
echo "  ✓ config.json written"

# --- iMessage database hardlink ---
# The instar iMessage adapter reads from a hardlink to the real Messages DB.
# This requires Terminal (or the running shell) to have Full Disk Access.
IMESSAGE_DIR="${AGENT_DIR}/.instar/imessage"
IMESSAGE_DB="${IMESSAGE_DIR}/chat.db"
SYSTEM_DB="${HOME}/Library/Messages/chat.db"
mkdir -p "${IMESSAGE_DIR}"
echo ""
echo "Linking iMessage database..."
if [[ -f "${IMESSAGE_DB}" ]]; then
    echo "  ✓ chat.db already linked"
elif [[ ! -f "${SYSTEM_DB}" ]]; then
    echo "  ✗ ~/Library/Messages/chat.db not found — Messages app may not have been set up yet"
else
    if ln "${SYSTEM_DB}" "${IMESSAGE_DB}" 2>/dev/null; then
        echo "  ✓ chat.db hardlinked from ~/Library/Messages/chat.db"
    else
        echo "  ✗ Could not create hardlink — Terminal needs Full Disk Access"
        echo "    Fix: System Settings → Privacy & Security → Full Disk Access → add Terminal"
        echo "    Then rerun this script."
    fi
fi

# --- Start server ---
echo ""
echo "Starting agent server..."
instar server stop 2>/dev/null || true
sleep 1
NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start

# Wait for health (30s — server can be slow on first start)
HEALTH_OK=false
for i in $(seq 1 30); do
    sleep 1
    _status=$(curl -s --max-time 1 http://localhost:4040/health 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
    if [[ "$_status" == "ok" || "$_status" == "degraded" ]]; then
        HEALTH_OK=true
        break
    fi
done

echo ""
if [[ "$HEALTH_OK" == true ]]; then
    echo "  ✓ Agent server running at http://localhost:4040"
    echo ""
    echo "=== Done ==="
    if [[ -n "$IMESSAGE_USER" ]]; then
        echo "Send a message from ${IMESSAGE_USER} to the house iMessage account to wake the agent."
    else
        echo "Send a message from your iMessage account to the house account to wake the agent."
    fi
else
    echo "  ✗ Server did not respond — check: tmux attach -t house-agent-server"
    echo ""
    echo "=== Incomplete ==="
    echo "Fix the server issue above, then rerun this script."
fi

echo ""
echo "=== Manual step required: Full Disk Access ==="
echo "The attachments-sync helper needs Full Disk Access to read iMessage attachments."
echo "Without it, photos sent via iMessage will not be visible to the agent."
echo ""
echo "  1. Open: System Settings → Privacy & Security → Full Disk Access"
echo "  2. Click + and add: ${ATTSYNC_BIN}"
echo "  3. Toggle it ON"
echo ""
echo "This only needs to be done once. You can open the pane now:"
echo "  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles'"
echo ""
echo "To auto-start at login:  instar server install"
echo "For HA integration, add scripts to .claude/scripts/ and context to .instar/context/"
