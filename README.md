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
- [Claude Max](https://claude.ai) subscription — generate an API key from your account settings
- [tmux](https://formulae.brew.sh/formula/tmux), [Node.js 20+](https://nodejs.org), [Python 3.11+](https://python.org)
- [Claude Code](https://claude.ai/code) CLI: `npm install -g @anthropic-ai/claude-code`
- [Instar](https://github.com/JKHeadley/instar): `npm install -g @jkheadley/instar`

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

```bash
brew install tmux node python@3.11
npm install
git submodule update --init --recursive
```

### 4. Get a Claude API key

Log in to [claude.ai](https://claude.ai) with your Claude Max account. Go to **Settings → API Keys** and create a new key. Keep it handy for the setup script.

### 5. Run the setup script

```bash
./setup/bootstrap.sh \
  --name YourHouseName \
  --user YourFirstName \
  --fg-url http://localhost:8000 \
  --fg-password your-funkygibbon-password
```

The script will:
- Generate `.instar/AGENT.md`, `MEMORY.md`, and `USER.md` from templates
- Create `.instar/config.json` and prompt for your Claude API key
- Install the Instar LaunchDaemon so the agent starts automatically
- Start the agent server on port 4040

### 6. Wake up the house on iMessage

Send a message from your personal iMessage to the house account:

> "Hello — are you there?"

The agent will respond, introduce itself, and ask for any initial configuration. From this point forward, you control the house by messaging it.

### 7. Verify

```bash
curl http://localhost:4040/health
```

You should see `{"status":"ok"}`.

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

The agent stores house knowledge in FunkyGibbon — a graph database of rooms, devices, relationships, and automations. Start it with:

```bash
cd the-goodies-python
pip install -e .
python -m funkygibbon
```

Then use `/room-walk` via iMessage to catalog each room.

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
