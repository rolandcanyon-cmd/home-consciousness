---
name: shortcut-library
description: Manage the house iOS Shortcuts library — add shortcuts, generate onboarding packages, list what's registered, and guide shortcut creation.
metadata:
  user_invocable: "true"
---

# /shortcut-library

Manages the house's collection of iOS Shortcuts. Tracks each shortcut's iCloud URL, generates onboarding packages for new users, and guides creation of new shortcuts.

## When to use

- User says "add this shortcut" / "register this shortcut" and gives an iCloud URL
- User asks "what shortcuts do we have?" or "which are missing?"
- User asks to onboard a new person to the house apps
- User asks "generate the onboarding package"
- During `/app-walk` — after cataloguing an app, ask if they want to create a launch shortcut for it
- User asks how to create a specific shortcut

## State file

Library lives at `.instar/state/shortcut-library.json`. Schema:

```json
{
  "shortcuts": [
    {
      "id": "launch-home",
      "name": "Open Home",
      "category": "launch | control | scene | url",
      "app": "homekit | alexa | tuya | hayward | comfort | rheem | lutron",
      "description": "What it does in plain English",
      "scheme": "com.apple.home://",
      "icloud_url": "https://www.icloud.com/shortcuts/UUID",
      "tested": true,
      "onboarding": true
    }
  ],
  "onboarding_message": "Welcome text sent to new users",
  "notes": "..."
}
```

- `icloud_url: null` means the shortcut hasn't been created yet
- `onboarding: true` means it's included in the standard new-user package

## Commands

### List the library

```python
import json
lib = json.load(open(".instar/state/shortcut-library.json"))
registered = [s for s in lib["shortcuts"] if s["icloud_url"]]
pending = [s for s in lib["shortcuts"] if not s["icloud_url"]]
```

Report as two groups: registered (with URLs) and pending (still needed).

### Register a new shortcut

When user provides an iCloud URL and description:

```python
import json
lib = json.load(open(".instar/state/shortcut-library.json"))

# Check if it updates an existing entry or adds a new one
existing = next((s for s in lib["shortcuts"] if s["id"] == shortcut_id), None)
if existing:
    existing["icloud_url"] = "https://www.icloud.com/shortcuts/UUID"
    existing["tested"] = True
else:
    lib["shortcuts"].append({
        "id": "new-id",
        "name": "Name",
        "category": "launch",
        "app": "homekit",
        "description": "What it does",
        "scheme": None,
        "icloud_url": "https://www.icloud.com/shortcuts/UUID",
        "tested": True,
        "onboarding": False,  # ask the user if this should be in onboarding
    })

with open(".instar/state/shortcut-library.json", "w") as f:
    json.dump(lib, f, indent=2)
```

After registering, ask: "Should this be included in the onboarding package for new users?"

### Generate the onboarding package

Compose the iMessage sequence for sending to a new user:

```python
lib = json.load(open(".instar/state/shortcut-library.json"))
onboarding = [s for s in lib["shortcuts"] if s["onboarding"] and s["icloud_url"]]
pending_onboarding = [s for s in lib["shortcuts"] if s["onboarding"] and not s["icloud_url"]]
```

Format as separate messages (one link per message so iMessage renders each as tappable):

```
Message 1: [welcome message from lib["onboarding_message"]]
Message 2: Open Home: https://www.icloud.com/shortcuts/UUID
Message 3: Open Alexa: https://www.icloud.com/shortcuts/UUID
... etc
```

If there are pending onboarding shortcuts (no URL yet), flag them: "Note: X onboarding shortcuts haven't been created yet: [names]."

To actually send via iMessage to a specific number:
```bash
for url in <urls>:
    echo "Name: URL" | .claude/scripts/imessage-reply.sh "+1XXXXXXXXXX"
```

### Guide shortcut creation

Read `.instar/context/shortcut-guide.md` for full instructions. Summarize the relevant section based on what the user wants to create:

- **Launch app**: Type A steps
- **Control a HomeKit device**: Type B steps  
- **App with no Shortcuts integration**: Type C (URL scheme) steps
- **Deep link to specific screen**: Type D steps

Always end with: "Once you've created it and shared it, send me the iCloud link and I'll add it to the library."

### App-walk integration

At the end of every `/app-walk` session, offer:

> "Want to create a launch shortcut for [App]? I'll walk you through it — takes about 30 seconds. Once you share the iCloud link, I'll add it to the library and include it in future onboarding packages."

If they say yes, guide them through Type A (Open App) steps for that app.

## Context files

- `.instar/context/shortcut-guide.md` — full creation instructions (read this when guiding)
- `.instar/context/user-onboarding.md` — full onboarding guide (read this when generating packages)
