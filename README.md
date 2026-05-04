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
- **Xcode** — install from the App Store and **launch it at least once** while logged in as an admin user to accept the license agreement. The Xcode command-line tools are required by Homebrew and must be accepted before switching to the house account.
- **A GitHub account for the house** — created during Step 1 using the house Apple ID. Used to back up agent state to a private repo.
- [Anthropic API key](https://console.anthropic.com) — generate one from the Anthropic Console (separate from any claude.ai subscription)
- [tmux](https://formulae.brew.sh/formula/tmux), [Node.js](https://nodejs.org) (latest), [Python 3](https://python.org) (latest) — installed via local Homebrew in the steps below
- [Claude Code](https://claude.ai/code) CLI — installed in Step 4
- [Instar](https://github.com/JKHeadley/instar) — installed in Step 4

## Installation

### 1. Set up a dedicated house account

Create a **standard (non-admin) macOS user account** on the local machine dedicated to the house agent. This keeps the agent isolated from your personal account and administrator privileges.

**Naming convention:** base the names on your house address or nickname. For example, for "123 Forest View":

| What | Example |
|------|---------|
| iCloud / Apple ID | `forestview123@icloud.com` |
| macOS full name | `Forest View` |
| macOS username / home dir | `forestview` → `/Users/forestview` |
| Agent name (used in `AGENT.md`) | `Forest` (or whatever you prefer) |

To create the account: **System Settings → Users & Groups → Add User** — set the account type to **Standard** (not Administrator).

**Enable fast user switching (admin account):** while still logged in as admin, go to **System Settings → Control Centre**, find **Fast User Switching**, and set it to show the **Account Name** in the menu bar. This makes it easy to switch between your account and the house account without logging out.

**Switch to the house account:** click the account name in the menu bar and select the house account. Log in for the first time.

**Sign in to iCloud:** macOS will automatically prompt for iCloud login when you first log in to a new account. Sign in with the house Apple ID (e.g. `forestview123@icloud.com`). Once signed in, enable iMessage in Messages.app — this is the iMessage identity the agent will reply from.

**Enable fast user switching (house account):** repeat the same step — **System Settings → Control Centre → Fast User Switching → Account Name** — so you can switch back to your admin account without logging out.

**Open the install instructions:** open Safari and browse to `https://github.com/rolandcanyon-cmd/home-consciousness` — keep this README visible in the browser so you can follow along during setup.

**Open Terminal:** click the search icon (magnifying glass) in the top-right of the menu bar to open Spotlight, type `terminal`, and press Return. All remaining setup steps run from here.

**Create a GitHub account for the house:** in Safari, go to [github.com](https://github.com) and create a new account using the house Apple ID (e.g. `forestview123@icloud.com`). This account will own a private repo that backs up the agent's state (memory, jobs, skills) automatically.

**Generate a personal access token:** once logged in to GitHub, go to **Settings → Developer settings → Personal access tokens → Tokens (classic)**, click **Generate new token (classic)**, give it a name like `house-agent`, select the **repo** scope, and click **Generate token**. Copy the token — you'll need it when the setup script runs. Store it somewhere safe (e.g. paste it into Notes temporarily).

### 2. Clone the repo

Copy and paste this into Terminal:

```bash
git clone https://github.com/rolandcanyon-cmd/home-consciousness.git ~/house-agent
cd ~/house-agent
```

You should see git printing a series of `Receiving objects` progress lines, finishing with `Resolving deltas`. No errors means it worked.

### 3. Install dependencies

Each block below can be copy-pasted separately. Run them in order and check the expected result before moving on.

**3a. Create a local Homebrew directory**

```bash
mkdir ~/homebrew
```

No output means success. If you see `mkdir: /Users/…/homebrew: File exists`, that's fine — it already exists.

**3b. Download and install Homebrew into it**

```bash
curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip-components 1 -C ~/homebrew
```

This will print curl download progress followed by tar extraction. No errors means it worked.

**3c. Add Homebrew to your PATH and fix Node certificate trust**

```bash
echo 'export PATH="$HOME/homebrew/bin:$HOME/homebrew/sbin:$PATH"' >> ~/.zshrc
echo 'export NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem' >> ~/.zshrc
source ~/.zshrc
```

No output means success. The `NODE_EXTRA_CA_CERTS` line is required — Homebrew-installed Node.js does not use the macOS system certificate store by default, which causes `npm install` to fail with SSL issuer errors without it.

Verify Homebrew is on your PATH:

```bash
brew --version
```

You should see a version string like `Homebrew 4.x.x`.

**3d. Install system packages**

```bash
brew install tmux node python3 go
```

This takes a few minutes. Each package prints `==> Installing …` lines. When it finishes you should be back at the prompt with no errors.

**3e. Install imsg (iMessage CLI)**

```bash
brew tap steipete/tap && brew install imsg
```

You should see `==> Tapping steipete/tap` followed by `==> Installing imsg`. Verify it installed:

```bash
imsg --version
```

You should see a version number.

**3f. Install project dependencies**

```bash
npm install
```

You should see packages being fetched and a summary line like `added N packages`. No errors means it worked.

**3g. Initialise git submodules**

```bash
git submodule update --init --recursive
```

You should see lines like `Cloning into '…'` for each submodule. No errors means it worked.

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
  --fg-password your-funkygibbon-password
```

The script prompts for anything not supplied on the command line. You'll be asked for:
- **FunkyGibbon password** — if not passed via `--fg-password`
- **Anthropic API key** — get one from [console.anthropic.com](https://console.anthropic.com) → Settings → API Keys (input is hidden like a password prompt)
- **Your iMessage address** — the account you'll message the house from (e.g. `you@icloud.com` or `+15551234567`)
- **GitHub username** — the house GitHub account (e.g. `forestview123`)
- **GitHub personal access token** — with `repo` scope, created at GitHub → Settings → Developer settings → Personal access tokens

**`--name`** is the agent's identity — substituted into `AGENT.md` and `MEMORY.md` so the agent knows who it is from the first session.

**`--user`** is your first name — seeded into `MEMORY.md` as the primary user.

The script does everything end-to-end:
- Generates `.instar/AGENT.md`, `.instar/MEMORY.md`, `.claude/settings.json`
- Installs FunkyGibbon dependencies, configures the password, creates the macOS LaunchAgent, starts and verifies FunkyGibbon
- Adds `NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem` to `~/.zshrc` (required for Homebrew Node.js to reach Anthropic APIs)
- Creates a **private GitHub repo** (`house-agent`) under the house account and pushes the agent state to it — this is the backup target for the hourly git-sync job
- Writes your API key and iMessage whitelist directly to `.instar/config.json`
- Hardlinks the Messages database into `.instar/imessage/` via `setup/link-imessage-db.sh` (stops Messages, links all three SQLite files, restarts Messages)
- Starts the Instar server and verifies it's healthy

**Order matters for the iMessage database.** The hardlinks must be created while the server is stopped and Messages is quit. The `link-imessage-db.sh` script handles this correctly. If you ever need to redo the links (e.g. after moving the database), run:

```bash
./setup/link-imessage-db.sh
NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start
```

When bootstrap finishes you should see `✓ Agent server running at http://localhost:4040`. Send a message from your iMessage account to the house account to wake it up.

### 7. Auto-start at login (optional)

To have the Instar server restart automatically after a reboot:

```bash
instar server install
```

The LaunchAgent this creates uses a bundled Node.js binary that has proper CA certificates built in — no `NODE_EXTRA_CA_CERTS` needed there. The `~/.zshrc` export is only needed when running `instar server start` manually from a Homebrew terminal.

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

### iMessage not responding — agent shows connected but never replies

Symptom: `imsg chats` timestamps don't update when messages arrive, and the activity log shows no iMessage events.

Cause: the Messages database hardlinks were created in the wrong order (server or Messages was running when the links were made), leaving the SQLite WAL lock in a broken state.

Fix — run the dedicated link script which handles the correct order:

```bash
./setup/link-imessage-db.sh
NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start
```

To add or remove authorized iMessage senders:

```bash
./setup/add-user.sh "you@icloud.com"      # add
./setup/add-user.sh "+15551234567"         # add phone
./setup/add-user.sh --list                 # show current
./setup/add-user.sh --remove "addr"        # remove
```

Then restart the server to apply.

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
