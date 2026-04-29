# New User Onboarding — House Apps & Shortcuts

This guide is for onboarding a new person (family member, houseguest, partner) to the smart home apps and controls.

---

## What Onboarding Covers

1. **Which apps they need** on their phone
2. **Which shortcuts to install** — one tap per shortcut
3. **What each app and shortcut does**
4. **Quick reference** for common tasks

---

## Step 1: Install the Apps

These are the main apps used in the house. Not everyone needs all of them — see the "Who needs this" column.

| App | App Store | Who needs it |
|-----|-----------|-------------|
| Apple Home | Built into iPhone | Everyone |
| Amazon Alexa | [Amazon Alexa](https://apps.apple.com/us/app/amazon-alexa/id944011620) | Everyone |
| Tuya Smart Life | [Tuya Smart Life](https://apps.apple.com/us/app/smart-life-smart-living/id1115101477) | House residents |
| Hayward AquaConnect | [Hayward](https://apps.apple.com/us/app/hayward-omni/id1001680855) | Pool users |
| Mitsubishi Comfort | [Comfort](https://apps.apple.com/us/app/comfort-by-mitsubishi-electric/id1451480609) | House residents (HVAC control) |
| Rheem EcoNet | [EcoNet](https://apps.apple.com/us/app/rheem-econet/id858675088) | House residents |

---

## Step 2: Install the Shortcuts

Tap each link below to add the shortcut to your phone. You'll see a preview — tap **Add Shortcut** to install it.

*(Links are filled in as shortcuts are created and registered in `.instar/state/shortcut-library.json`)*

### Launch Shortcuts
These open the app directly:

| Shortcut | Link | What it does |
|----------|------|-------------|
| Open Home | *(pending)* | Opens Apple Home for lights, locks, sensors |
| Open Alexa | *(pending)* | Opens Amazon Alexa for voice devices & routines |

### Control Shortcuts  
These control specific devices — no app needed:

| Shortcut | Link | What it does |
|----------|------|-------------|
| *(Add as created)* | | |

### Scene Shortcuts
These run multi-device scenes:

| Shortcut | Link | What it does |
|----------|------|-------------|
| *(Add as created)* | | |

---

## Step 3: What Controls What

Quick reference for common questions:

### Lights
- **Vantage keypads** on the walls control most lights
- **Apple Home app** → Lights for app control
- **Alexa** → "Alexa, turn on [room] lights"

### Locks
- **Apple Home app** → Locks
- **Shortcut: Lock Front Door** (when created)
- Schlage keypad on exterior doors has a code

### Thermostats (HVAC)
- **Mitsubishi Comfort app** — 4 zones: Kitchen, Pool House, Office, Gym
- Kitchen and Pool House share a condenser — they must be set to the same mode (heat/cool/off)
- **Apple Home** shows thermostat status but Comfort app has full control

### Pool
- **Hayward AquaConnect app** — pump, heater, lights, waterfalls
- Pool light shortcut (when created) is the quickest way

### Voice Control
- **Alexa** ("Hey Alexa, ...") for Amazon smart plugs and Echo devices
- **Siri** for HomeKit devices
- Ask either: "Turn on [device name]"

### Ice Maker
- Controlled via **Alexa app** → Devices
- There's also a routine — ask Alexa: "Alexa, turn on ice maker"

---

## Step 4: Getting Help

- Ask Roland or text the house assistant for anything not covered here
- The house assistant can tell you which app controls any specific device
- If a shortcut doesn't work, check that the relevant app is installed and you're on the home WiFi

---

## For the Person Running Onboarding

When sending the onboarding package to a new user:

1. Check `.instar/state/shortcut-library.json` for current iCloud URLs — ask me to generate the current onboarding message
2. Send them this sequence via iMessage:
   - Welcome message (see `onboarding_message` in shortcut-library.json)
   - One message per shortcut link (so each is a separate tappable link)
   - Link to this guide if they want more detail
3. After they've installed everything, do a quick walkthrough — Alexa, Apple Home, and the thermostat are the most important

**To get the current onboarding package**: tell me "generate the onboarding package" and I'll compose the iMessage sequence from the registered shortcuts.
