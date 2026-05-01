# Home Consciousness Agent

A persistent, autonomous house agent built on [Instar](https://github.com/JKHeadley/instar). Runs on a Mac in your home, controls devices via HomeKit/Vantage/Alexa, and is accessible via iMessage from anywhere.

## What It Does

- Controls smart home devices by name over iMessage
- Catalogs rooms and devices via conversational room walks
- Monitors house systems (weather, wine cabinet, water heater)
- Manages away mode, morning weather reports, and scheduled jobs
- Maintains a persistent knowledge graph of your home ([FunkyGibbon](https://github.com/rolandcanyon-cmd/the-goodies-typescript))

## Prerequisites

- A Mac (Mac mini recommended for always-on operation)
- macOS with iMessage configured
- [Anthropic API key](https://console.anthropic.com) — generate one from the Anthropic Console (separate from any claude.ai subscription)
- [tmux](https://formulae.brew.sh/formula/tmux), [Node.js](https://nodejs.org) (latest), [Python 3](https://python.org) (latest) — installed via local Homebrew
- [Claude Code](https://claude.ai/code) CLI: `npm install -g @anthropic-ai/claude-code`
- [Instar](https://github.com/JKHeadley/instar): `npm install -g instar`

## Installation

### 1. Set up a dedicated house account

Create (or adopt) an Apple iCloud account dedicated to the house — e.g. `yourhouse@icloud.com`. This is the iMessage identity the agent will use. Sign in to iMessage on the Mac with this account.

Create a macOS user account for the house agent on the local machine, or use an existing admin account.

### 2. Clone the repo

```bash
git clone https://github.com/rolandcanyon-cmd/home-consciousness.git ~/house-agent
cd ~/house-agent
```

### 3. Install dependencies

Install a local Homebrew under your home directory — this is the recommended approach regardless of whether you have admin rights. It keeps everything self-contained and avoids conflicts with system packages or other users on the same machine.

```bash
mkdir ~/homebrew
curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip-components 1 -C ~/homebrew
echo 'export PATH="$HOME/homebrew/bin:$HOME/homebrew/sbin:$PATH"' >> ~/.zshrc
source ~/.zshrc
brew install tmux node python3
```

This installs the latest versions of each, all under `~/homebrew`. npm global packages (`claude`, `instar`) will also install there and be on your PATH automatically.

Then install project dependencies:

```bash
npm install
git submodule update --init --recursive
```

### 4. Install Claude Code and Instar

Install both into your local Homebrew prefix. This keeps everything self-contained under `~/homebrew` and requires no admin access, regardless of what else is installed system-wide.

```bash
npm install -g --prefix ~/homebrew @anthropic-ai/claude-code
npm install -g --prefix ~/homebrew instar
```

Since `~/homebrew/bin` is first in your PATH, these local installs will always take precedence.

Verify:

```bash
claude --version
instar --version
```

If either command isn't found, run `source ~/.zshrc` first.

### 5. Get a Claude API key

Go to [console.anthropic.com](https://console.anthropic.com), sign in (or create an account), and navigate to **Settings → API Keys** to create a new key. Keep it handy for the setup script.

Note: API access is billed separately from any claude.ai subscription (Max, Pro, etc.). The Anthropic Console is a distinct product.

### 6. Run the setup script

```bash
./setup/bootstrap.sh \
  --name YourHouseName \
  --user YourFirstName \
  --fg-url http://localhost:8000 \
  --fg-password your-funkygibbon-password
```

**`--name`** is the agent's identity — it's substituted into `AGENT.md` as the agent's name ("I'm YourHouseName, the consciousness for your house") and seeded into `MEMORY.md` so the agent knows what it's called from the very first session.

**`--user`** is your first name. It goes into `MEMORY.md` as the primary user, so the agent starts with context about who it works with rather than discovering it through conversation.

Both are initial seeds — the agent evolves its memory over time, but the name stays stable. Neither affects the Instar server config; they're purely identity and memory scaffolding.

The script generates identity files and sets up FunkyGibbon end-to-end:
- `.instar/AGENT.md` — the agent's identity
- `.instar/MEMORY.md` — initial long-term memory
- `.claude/settings.json` — Claude Code tool permissions and MCP servers
- Installs FunkyGibbon's Python dependencies
- Hashes your password and writes a `.env` to `the-goodies-python/funkygibbon/`
- Creates `~/Library/LaunchAgents/com.funkygibbon.plist` so FunkyGibbon starts automatically at login
- Starts FunkyGibbon and confirms it's responding

It does **not** create `config.json`, start the Instar server, or install the Instar LaunchDaemon. Those are the next steps.

The bootstrap also adds `NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem` to your `~/.zshrc`. This is required — Homebrew Node.js has a different CA bundle from Claude Code's bundled runtime, and without it Instar will fail with `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` when calling Anthropic APIs.

### 7. Configure the agent

Reload your shell config first (so the cert fix takes effect):

```bash
source ~/.zshrc
```

**Do not use `instar config set` for initial setup.** Before the API key is configured, `instar config set` spawns a Claude Code session to validate the change — which immediately asks for OAuth authentication, creating a chicken-and-egg problem. Edit the config file directly instead:

```python
python3 - <<'EOF'
import json, pathlib
path = pathlib.Path.home() / "house-agent/.instar/config.json"
c = json.loads(path.read_text()) if path.exists() else {}
c.setdefault("sessions", {})["anthropicApiKey"] = "sk-ant-YOUR_KEY"
c.setdefault("imessage", {})["allowedNumbers"] = ["you@icloud.com"]
path.write_text(json.dumps(c, indent=2))
print("Wrote", path)
EOF
```

Replace `sk-ant-YOUR_KEY` with your key from [console.anthropic.com](https://console.anthropic.com) and `you@icloud.com` with the iCloud address you'll message from. Phone numbers also work (e.g. `+15551234567`).

**Critical: configure the API key before starting the server.** The server reads it at startup. Once the key is set, `instar config set` commands work normally (they use the running server, which now has credentials).

### 8. Start the server

Start it with the cert variable in the same command — this ensures it takes effect even if you haven't sourced your shell config yet:

```bash
NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start
```

If the server is already running, stop it first:

```bash
instar server stop
NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start
```

To have it start automatically at login:

```bash
instar server install
```

The LaunchAgent created by `instar server install` uses a bundled Node.js binary that has proper CA certificates — it does not need `NODE_EXTRA_CA_CERTS`. That variable is only needed when running `instar server start` from a Homebrew Node.js terminal, which is why the bootstrap added it to `~/.zshrc`.

### 9. Verify

```bash
curl http://localhost:4040/health
```

You should see `{"status":"ok"}`.

### 10. Wake up the house on iMessage

Send a message from your personal iMessage to the house account:

> "Hello — are you there?"

The agent will respond and introduce itself. From this point forward, you control the house by messaging it.

---

## Configuration

All runtime configuration lives in `.instar/config.json` (gitignored — never committed). Key fields:

| Field | Description |
|-------|-------------|
| `agentName` | The agent's name (set by bootstrap) |
| `sessions.anthropicApiKey` | Your Claude API key |
| `imessage.allowedNumbers` | Phone numbers allowed to control the house |
| `telegram.*` | Optional Telegram integration |

## Knowledge Graph (FunkyGibbon)

The agent stores house knowledge in FunkyGibbon — a graph database of rooms, devices, relationships, and automations. The bootstrap script sets it up and starts it automatically. It will restart at login via the macOS LaunchAgent.

If you need to start it manually (e.g. after a crash before the LaunchAgent fires):

```bash
cd the-goodies-python
./start_funkygibbon.sh
```

`start_funkygibbon.sh` is generated by bootstrap — it activates the venv and sets the credentials. Do not run `python -m funkygibbon` directly; it won't have the right environment.

Once FunkyGibbon is running, use `/room-walk` via iMessage to catalog each room.

## Skills

Key slash commands available via iMessage:

| Command | Description |
|---------|-------------|
| `/room-walk <room>` | Catalog a room's devices conversationally |
| `/room-edit <room>` | Update an already-catalogued room |
| `/away-mode` | Departure/return checklist and automations |
| `/morning-weather` | Fetch and send today's weather |

## Architecture

```
iMessage ──▶ imsg CLI ──▶ Instar server (port 4040)
                               │
                    ┌──────────┼──────────────┐
                    ▼          ▼              ▼
              Claude Code   Job scheduler  FunkyGibbon
              (AI layer)    (cron jobs)    (knowledge graph)
```

## Troubleshooting

### Claude is prompting for OAuth / account login instead of using the API key

If a Claude auth prompt appears when the server first processes a message, it means the server started before the API key was configured, or Claude Code on this machine has an existing account session that took precedence.

Fix: stop the server, then start it again after the API key is set. The server reads `sessions.anthropicApiKey` from config at startup and passes it as an environment variable to spawned Claude sessions — this overrides any existing OAuth credentials on the machine.

```bash
instar server stop
# confirm API key is set: instar config get sessions.anthropicApiKey
instar server start
```

### `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` when starting the server

The bootstrap script adds `NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem` to `~/.zshrc` automatically. If you see this error, it means either the bootstrap hasn't been run yet, or the shell config hasn't been reloaded:

```bash
source ~/.zshrc
instar server start
```

If you're setting up without the bootstrap (manual install), add it yourself:

```bash
echo 'export NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem' >> ~/.zshrc
source ~/.zshrc
```

## Updating

```bash
instar update
```

Or run the `/imessage-fork-maintenance` skill to rebase the custom iMessage fork against upstream Instar.

## Uninstalling

```bash
instar nuke <agent-name>
```

This stops the server, removes the LaunchDaemon, pushes a final backup, and cleans up the agent directory.

---

## Repository Structure

```
.claude/
  scripts/     # HomeKit, iMessage, Vantage, weather integrations
  skills/      # Slash commands (/room-walk, /away-mode, etc.)
.instar/
  context/     # Behavioral context files (architecture, dev guide, etc.)
  hooks/       # Claude Code hooks (session-start, compaction-recovery, etc.)
  scripts/     # Maintenance scripts (log-rotate, sudoers template)
setup/
  bootstrap.sh # New install script
the-goodies-python/    # FunkyGibbon knowledge graph (Python)
the-goodies-typescript/ # FunkyGibbon TypeScript client (kittenkong)
```
