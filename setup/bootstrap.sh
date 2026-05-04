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
#   --github-user USER     GitHub username for the house account (prompted if not set)
#   --github-token TOKEN   GitHub personal access token with repo scope (prompted if not set)
#   --backup-repo NAME     Name for the private backup repo (default: house-agent)
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
GITHUB_USER=""
GITHUB_TOKEN=""
BACKUP_REPO_NAME="house-agent"
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
        --github-user)   GITHUB_USER="$2"; shift 2 ;;
        --github-token)  GITHUB_TOKEN="$2"; shift 2 ;;
        --backup-repo)   BACKUP_REPO_NAME="$2"; shift 2 ;;
        --fg-url)        FUNKYGIBBON_URL="$2"; shift 2 ;;
        --fg-password)   FUNKYGIBBON_PASSWORD="$2"; shift 2 ;;
        --no-kittenkong) NO_KITTENKONG=true; shift ;;
        --force)         FORCE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Load existing values as defaults (before prompts) ---
# So rerunning the script doesn't re-prompt for things already configured.

# Agent name from existing AGENT.md
_agent_md="${AGENT_DIR}/.instar/AGENT.md"
if [[ -z "$AGENT_NAME" && -f "$_agent_md" ]]; then
    _existing_name=$(grep -m1 '^\*\*Name\*\*:' "$_agent_md" | sed 's/\*\*Name\*\*:[[:space:]]*//' | xargs 2>/dev/null || echo "")
    [[ -n "$_existing_name" ]] && AGENT_NAME="$_existing_name"
fi

# Primary user from existing MEMORY.md
_memory_md="${AGENT_DIR}/.instar/MEMORY.md"
if [[ -z "$PRIMARY_USER" && -f "$_memory_md" ]]; then
    _existing_user=$(grep -m1 'Primary user:' "$_memory_md" | sed 's/.*Primary user:[[:space:]]*//' | xargs 2>/dev/null || echo "")
    [[ -n "$_existing_user" ]] && PRIMARY_USER="$_existing_user"
fi

if [[ -z "$AGENT_NAME" ]]; then
    read -rp "Agent name (e.g. Forest, Corfe): " AGENT_NAME
    [[ -z "$AGENT_NAME" ]] && { echo "Error: agent name is required"; exit 1; }
fi

if [[ -z "$PRIMARY_USER" ]]; then
    read -rp "Your first name (e.g. Roland): " PRIMARY_USER
    [[ -z "$PRIMARY_USER" ]] && { echo "Error: your name is required"; exit 1; }
fi

# API key and iMessage address from existing config.json
if [[ -f "${CONFIG_FILE}" ]]; then
    _existing_key=$(python3 -c "
import json, pathlib
c = json.loads(pathlib.Path('${CONFIG_FILE}').read_text())
print(c.get('sessions', {}).get('anthropicApiKey', ''))
" 2>/dev/null || echo "")
    _existing_imessage=$(python3 -c "
import json, pathlib
c = json.loads(pathlib.Path('${CONFIG_FILE}').read_text())
msgs = c.get('messaging', [])
cfg = next((m.get('config', {}) for m in msgs if m.get('type') == 'imessage'), {})
contacts = cfg.get('authorizedContacts', [])
print(contacts[0] if contacts else '')
" 2>/dev/null || echo "")
    [[ -z "$API_KEY" && -n "$_existing_key" ]]           && API_KEY="$_existing_key"
    [[ -z "$IMESSAGE_USER" && -n "$_existing_imessage" ]] && IMESSAGE_USER="$_existing_imessage"
fi

# GitHub user from existing git remote (origin → https://github.com/USER/REPO.git)
if [[ -z "$GITHUB_USER" ]]; then
    _origin_url=$(git -C "${AGENT_DIR}" remote get-url origin 2>/dev/null || echo "")
    _existing_gh_user=$(echo "$_origin_url" | sed -n 's|https://github.com/\([^/]*\)/.*|\1|p' | xargs 2>/dev/null || echo "")
    [[ -n "$_existing_gh_user" ]] && GITHUB_USER="$_existing_gh_user"
fi

# GitHub token from ~/.git-credentials (https://USER:TOKEN@github.com)
if [[ -z "$GITHUB_TOKEN" && -n "$GITHUB_USER" ]]; then
    _existing_gh_token=$(grep -m1 "github.com" "${HOME}/.git-credentials" 2>/dev/null \
        | sed -n "s|https://[^:]*:\([^@]*\)@github.com|\1|p" | xargs 2>/dev/null || echo "")
    [[ -n "$_existing_gh_token" ]] && GITHUB_TOKEN="$_existing_gh_token"
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
    echo "Anthropic API key (from console.anthropic.com → Manage → API Keys):"
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

if [[ -z "$GITHUB_USER" ]]; then
    echo "GitHub username for the house account (for private state backup):"
    read -rp "  e.g. forestview123 : " GITHUB_USER
    echo
fi

if [[ -z "$GITHUB_TOKEN" && -n "$GITHUB_USER" ]]; then
    echo "GitHub personal access token for ${GITHUB_USER} (repo scope required):"
    echo "  Create one at: https://github.com/settings/tokens/new?scopes=repo"
    read -rsp "  ghp_... : " GITHUB_TOKEN
    echo
    [[ -z "$GITHUB_TOKEN" ]] && echo "Warning: no GitHub token — skipping private backup repo setup"
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

mkdir -p "${AGENT_DIR}/.instar/bin" "${AGENT_DIR}/.instar/logs"
if [[ -f "${ATTSYNC_BIN}" ]]; then
    echo "attachments-sync binary already built — skipping"
    echo "  ✓ ${ATTSYNC_BIN}"
elif command -v go &>/dev/null; then
    echo "Building attachments-sync..."
    (cd "${ATTSYNC_SRC}" && go build -o "${ATTSYNC_BIN}" .)
    echo "  ✓ Binary built: ${ATTSYNC_BIN}"
else
    echo "attachments-sync: Go not found — install with: brew install go, then rerun"
fi

# Install LaunchAgent if not already loaded
mkdir -p "${HOME}/Library/LaunchAgents"
_attsync_loaded=$(launchctl list 2>/dev/null | grep -c "ai.instar.AttachmentsWatcher" || true)
if [[ "$_attsync_loaded" -gt 0 && -f "${ATTSYNC_BIN}" ]]; then
    echo "AttachmentsWatcher LaunchAgent already loaded — skipping"
    echo "  ✓ ai.instar.AttachmentsWatcher"
else
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
        echo "  ⚠ LaunchAgent written but not loaded — binary missing (install Go and rerun)"
    fi
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

# --- Private backup repo ---
if [[ -n "$GITHUB_USER" && -n "$GITHUB_TOKEN" ]]; then
    echo ""
    echo "Setting up private backup repo..."

    # Create private repo via GitHub API (safe to call even if it already exists)
    HTTP_CODE=$(curl -s -o /tmp/gh-create-repo.json -w "%{http_code}" \
        -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/user/repos \
        -d "{\"name\":\"${BACKUP_REPO_NAME}\",\"private\":true,\"description\":\"Private state backup for ${AGENT_NAME} house agent\"}")

    if [[ "$HTTP_CODE" == "201" ]]; then
        echo "  ✓ Created private repo: ${GITHUB_USER}/${BACKUP_REPO_NAME}"
    elif [[ "$HTTP_CODE" == "422" ]]; then
        echo "  ✓ Repo already exists: ${GITHUB_USER}/${BACKUP_REPO_NAME}"
    else
        echo "  ✗ Failed to create repo (HTTP ${HTTP_CODE})"
        cat /tmp/gh-create-repo.json
    fi

    # Store credentials in ~/.git-credentials so git can push without prompting
    GIT_CREDENTIALS_FILE="${HOME}/.git-credentials"
    CREDENTIAL_LINE="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com"
    if ! grep -qF "github.com" "${GIT_CREDENTIALS_FILE}" 2>/dev/null; then
        echo "${CREDENTIAL_LINE}" >> "${GIT_CREDENTIALS_FILE}"
        chmod 600 "${GIT_CREDENTIALS_FILE}"
    fi
    git config --global credential.helper store
    echo "  ✓ GitHub credentials configured"

    # Point the repo remote at the private backup repo
    PRIVATE_REMOTE="https://github.com/${GITHUB_USER}/${BACKUP_REPO_NAME}.git"
    git -C "${AGENT_DIR}" remote set-url origin "${PRIVATE_REMOTE}" 2>/dev/null \
        || git -C "${AGENT_DIR}" remote add origin "${PRIVATE_REMOTE}"
    echo "  ✓ Remote origin → ${PRIVATE_REMOTE}"

    # Keep home-consciousness as 'upstream' so updates can be pulled with: git pull upstream main
    PUBLIC_REMOTE="https://github.com/rolandcanyon-cmd/home-consciousness.git"
    git -C "${AGENT_DIR}" remote set-url upstream "${PUBLIC_REMOTE}" 2>/dev/null \
        || git -C "${AGENT_DIR}" remote add upstream "${PUBLIC_REMOTE}"
    echo "  ✓ Remote upstream → ${PUBLIC_REMOTE} (pull updates with: git pull upstream main)"

    # Initial push
    if git -C "${AGENT_DIR}" push -u origin main 2>&1; then
        echo "  ✓ Initial push to private backup repo"
    else
        echo "  ✗ Push failed — check token permissions and try: git push -u origin main"
    fi
fi

# --- iMessage database hardlinks ---
# All three SQLite files must be hardlinked in the correct order:
# server stopped → Messages quit → link → Messages reopen → server start.
# Skip if hardlinks are already correct (same inode = same file).
echo ""
echo "Checking iMessage database hardlinks..."
_src_db="${HOME}/Library/Messages/chat.db"
_dst_db="${AGENT_DIR}/.instar/imessage/chat.db"
_src_inode=$(stat -f "%i" "${_src_db}" 2>/dev/null || echo "")
_dst_inode=$(stat -f "%i" "${_dst_db}" 2>/dev/null || echo "")
if [[ -n "$_src_inode" && -n "$_dst_inode" && "$_src_inode" == "$_dst_inode" ]]; then
    echo "  ✓ iMessage database hardlinks already in place (inode ${_src_inode})"
else
    echo "  Hardlinks missing or stale — running link script..."
    bash "${SCRIPT_DIR}/link-imessage-db.sh"
fi

# --- Initialise iMessage poll offset ---
# Set the watermark to the current max ROWID so the agent only processes
# messages received after this install, not the entire history.
_imessage_db="${HOME}/Library/Messages/chat.db"
_offset_file="${AGENT_DIR}/.instar/imessage-poll-offset.json"
if [[ ! -f "$_offset_file" ]]; then
    _max_rowid=$(sqlite3 "$_imessage_db" "SELECT COALESCE(MAX(ROWID),0) FROM message;" 2>/dev/null || echo "0")
    echo "{\"lastRowId\":${_max_rowid},\"savedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$_offset_file"
    echo "  ✓ iMessage poll offset initialised at ROWID ${_max_rowid} (ignoring history)"
fi

# --- Initialise Claude Code ---
# On a fresh account, Claude Code shows a first-run ToS/auth screen the first time
# it runs. If instar spawns a session before this is accepted, it times out with
# "Claude not ready". Run a quick non-interactive check now so first-run is done
# before the server starts. Skip if already initialised (marker: ~/.claude exists).
echo ""
echo "Initialising Claude Code..."
_claude_bin=$(command -v claude 2>/dev/null || echo "")
if [[ -n "$_claude_bin" ]]; then
    if [[ -d "${HOME}/.claude" ]]; then
        echo "  ✓ Claude Code already initialised (~/.claude exists)"
    else
        # -p runs non-interactively; ANTHROPIC_API_KEY tells Claude Code to skip OAuth
        ANTHROPIC_API_KEY="$API_KEY" "$_claude_bin" -p "." --dangerously-skip-permissions \
            2>/dev/null | head -1 >/dev/null && echo "  ✓ Claude Code initialised" \
            || echo "  ⚠ Claude Code init returned non-zero — may need manual first-run (open Terminal and run: claude)"
    fi
else
    echo "  ⚠ claude not found in PATH — run 'source ~/.zshrc' and rerun this script"
fi

# --- Start server ---
echo ""
echo "Starting agent server..."
_server_health=$(curl -s --max-time 2 http://localhost:4040/health 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
if [[ "$_server_health" == "ok" || "$_server_health" == "degraded" ]]; then
    echo "  ✓ Server already running at http://localhost:4040"
else
    NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start
fi

# Install launchd auto-start (crash recovery + login persistence)
# Must be run explicitly — the server's internal self-healing can fail silently.
echo ""
echo "Installing launchd auto-start..."
if instar autostart status 2>/dev/null | grep -qi "installed\|running\|loaded"; then
    echo "  ✓ Auto-start already installed"
else
    instar autostart install && echo "  ✓ Auto-start installed (server restarts on crash and login)" \
        || echo "  ⚠ Auto-start install failed — run 'instar autostart install' manually"
fi

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

    # Install startup-announce LaunchAgent — fires on every login to report version + health
    _announce_plist="${HOME}/Library/LaunchAgents/ai.instar.${AGENT_NAME}.Announce.plist"
    _announce_script="${AGENT_DIR}/setup/startup-announce.sh"
    chmod +x "$_announce_script"
    mkdir -p "${HOME}/Library/LaunchAgents"
    _announce_label="ai.instar.${AGENT_NAME}.Announce"
    _announce_loaded=$(launchctl list 2>/dev/null | grep -c "${_announce_label}" || true)
    if [[ "$_announce_loaded" -gt 0 ]]; then
        echo "  ✓ Startup announce LaunchAgent already loaded"
    else
        cat > "$_announce_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.instar.${AGENT_NAME}.Announce</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${_announce_script}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${AGENT_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${AGENT_DIR}/.instar/logs/startup-announce.log</string>
    <key>StandardErrorPath</key>
    <string>${AGENT_DIR}/.instar/logs/startup-announce.log</string>
</dict>
</plist>
PLIST
        launchctl unload "$_announce_plist" 2>/dev/null || true
        launchctl load "$_announce_plist"
        echo "  ✓ Startup announce LaunchAgent installed (sends version + health on every login)"
    fi

    # Also send the initial welcome now
    if [[ -n "$IMESSAGE_USER" ]]; then
        _auth=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}')).get('authToken',''))" 2>/dev/null || echo "")
        _version=$(curl -s --max-time 5 -H "Authorization: Bearer ${_auth}" http://localhost:4040/updates 2>/dev/null \
            | python3 -c "import json,sys; print(json.load(sys.stdin).get('currentVersion','unknown'))" 2>/dev/null || echo "unknown")
        _welcome="${AGENT_NAME} v${_version} is online and ready."
        imsg send "$IMESSAGE_USER" "$_welcome" 2>/dev/null \
            && echo "  ✓ Welcome message sent to ${IMESSAGE_USER}" \
            || echo "  ✗ Welcome message failed — iMessage may need a moment to settle"
    fi

    echo ""
    echo "=== Done ==="
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
echo "To reinstall auto-start: instar autostart install"
echo "For HA integration, add scripts to .claude/scripts/ and context to .instar/context/"
