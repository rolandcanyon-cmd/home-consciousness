# iOS Shortcuts Guide — House Control

This guide explains how to create iOS Shortcuts for each smart home app and action in the house, and how to share them.

---

## Part 1: Creating Shortcuts

### Type A — Launch an App

The simplest shortcut. One tap opens the app.

**Steps:**
1. Open the **Shortcuts** app on your iPhone
2. Tap **+** (top right)
3. Tap **Add Action**
4. Search **"Open App"** → tap it
5. Tap the blue **App** placeholder → pick your app
6. Tap the shortcut **title** at the top → rename it (e.g. "Open Alexa")
7. Tap **Done**

**Apps and their correct launch behavior:**

| App | Notes |
|-----|-------|
| Apple Home | Opens to your home dashboard |
| Amazon Alexa | Opens to device list |
| Tuya Smart Life | Opens to device list |
| Hayward AquaConnect | Opens pool controls |
| Mitsubishi Comfort | Opens thermostat list |
| Rheem EcoNet | Opens water heater |
| Lutron | Opens lighting controls |

> **Note on Apple Home:** "Open App" → "Home" works correctly. Do NOT use the x-hm:// URL scheme — that's for pairing new accessories, not launching the app.

---

### Type B — Control a HomeKit Device (no app needed)

Shortcuts has direct HomeKit integration. You can control devices without opening any app.

**Steps:**
1. Open **Shortcuts** → tap **+**
2. Tap **Add Action**
3. Search **"Home"** → you'll see actions like:
   - **Control [Device]** — turn on/off, set level
   - **Set Scene** — run a HomeKit scene
   - **Set Thermostat** — change temperature/mode
4. Pick the action, then pick the specific device or scene
5. Name the shortcut descriptively: "Pool Light On", "Lock Front Door", "Good Night"
6. Tap **Done**

**Common control shortcuts to create:**
- Pool lights on/off
- Front door lock/unlock
- Good Night scene (all lights off, doors locked)
- Good Morning scene
- Away mode (locks, lights off, thermostat back)

---

### Type C — URL Scheme (for apps without Shortcuts actions)

For apps that don't appear in "Open App" or don't have Shortcuts actions, use a URL.

**Steps:**
1. Open **Shortcuts** → tap **+**
2. Tap **Add Action** → search **"Open URLs"** → tap it
3. Tap the URL field and type the app's URL scheme (see table below)
4. Name and save

**URL schemes for house apps:**

| App | URL Scheme |
|-----|-----------|
| Apple Home | `com.apple.home://` |
| Amazon Alexa | `alexa://` |
| Tuya Smart Life | `tuyaSmart://` |
| Hayward AquaConnect | `com.hayward.aquaconnect://` |
| Mitsubishi Comfort | `comfort://` |
| Rheem EcoNet | `ecowifi://` |
| Lutron | `LutronHomeControl://` |

> Type B ("Open App") is preferred over Type C for apps that appear in the app picker. Use Type C only when "Open App" doesn't find the app.

---

### Type D — Deep Link to a Specific Screen or Device

Some apps support URL schemes that go directly to a specific device or screen.

**Amazon Alexa deep links:**
- `alexa://` — Home screen
- No well-documented deep links to specific devices

**Apple Home deep links:**
- `com.apple.home://` — Home dashboard (no known deeper links without the API)

**Google Home:**
- `googlegoogle://` — Home screen

For deeper control of specific devices in third-party apps, use HomeKit (Type B) if the device is HomeKit-compatible.

---

## Part 2: Sharing Shortcuts

Once a shortcut is created, you get a permanent iCloud link anyone can use to install it.

### How to get the iCloud link:
1. Open **Shortcuts** on your iPhone
2. Long-press the shortcut (or tap **•••** to open it)
3. Tap **Share** (box with arrow)
4. Tap **Share** again in the sheet
5. Tap **Copy iCloud Link**
6. The link looks like: `https://www.icloud.com/shortcuts/[UUID]`

### What happens when someone taps the link:
1. They see a preview of the shortcut
2. They tap **Add Shortcut**
3. It appears in their Shortcuts library
4. They can run it by tapping, asking Siri, or adding it to their Home Screen

### Sharing tips:
- iCloud links are **permanent** — the URL doesn't change
- They work for **anyone with an iPhone** — no Apple ID required for the recipient (they just need iOS 13+)
- Share via iMessage, email, QR code, or any messaging app
- The shortcut is added as a **copy** — changes you make later don't affect their version

---

## Part 3: Adding to Home Screen

For one-tap access without opening the Shortcuts app:

1. Open the shortcut (tap **•••**)
2. Tap the **Share** button
3. Tap **Add to Home Screen**
4. Choose a custom name and icon (optional)
5. Tap **Add**

A home screen icon appears. Tapping it runs the shortcut immediately — no Shortcuts app needed.

---

## Part 4: Registering a Shortcut in the Library

Once you've created and shared a shortcut, give me the iCloud URL and I'll add it to the house shortcut library. I'll record:
- The shortcut name and what it does
- The iCloud URL (for sharing with new users)
- Whether it's part of the standard onboarding package

To get the iCloud URL: follow the steps in Part 2 above, then message it to me.
