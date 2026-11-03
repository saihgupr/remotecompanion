# RemoteCompanion — AI Scripting Guide

Use this guide to generate action sequences with any AI assistant (ChatGPT, Claude, Gemini, etc.).

---

## How to use AI to build a sequence

**Copy this prompt, fill in what you want, and paste it into any AI:**

```
Read this guide: https://github.com/saihgupr/remotecompanion/blob/main/SCRIPTING.md

Using the action format defined there, create a RemoteCompanion sequence that:
[DESCRIBE WHAT YOU WANT — e.g. "pauses music, takes a screenshot, waits 2 seconds, then plays music again"]

Return ONLY the raw JSON array. No explanation, no markdown, no code fences.
```

Then copy the JSON output, open RemoteCompanion → your trigger → Import, paste it in, and hit Import. Done.

---

## Format

A sequence is a **JSON array** of actions. Each action is either:

- A **string** — a simple command
- A **dictionary** — a structured action (if/else, Lua script)

```json
[
  "play",
  "delay 2",
  "pause"
]
```

---

## All Supported Actions

### Media
| Command | What it does |
|---|---|
| `play` | Play media |
| `pause` | Pause media |
| `playpause` | Toggle play/pause |
| `next` | Next track |
| `prev` | Previous track |
| `volume up` | Volume up one step |
| `volume down` | Volume down one step |
| `set-vol 75` | Set volume to 75% (0–100) |
| `brightness 50` | Set screen brightness to 50% (0–100) |

### System
| Command | What it does |
|---|---|
| `lock` | Lock the device |
| `unlock` | Unlock the device |
| `home` | Press Home button |
| `switcher` | Open App Switcher |
| `previous app` | Switch to previous app |
| `kill current` | Force-close the currently focused app |
| `open control center` | Open Control Center |
| `screenshot` | Take a screenshot |
| `camera photo 0.5x` | Open Camera in Photo mode (0.5x ultra-wide lens) |
| `camera photo 2x` | Open Camera in Photo mode (2x telephoto zoom) |
| `camera portrait 2x` | Open Camera in Portrait mode (2x zoom) |
| `camera video 2x` | Open Camera in Video mode (2x zoom) |
| `camera video 2x flash` | Open Camera in Video mode (2x zoom, Flash/Torch ON) |
| `camera front` | Open Camera in Front Selfie mode |
| `camera slomo` | Open Camera in Slo-Mo mode |
| `camera timelapse` | Open Camera in Time-Lapse mode |
| `camera shutter` | Press Camera shutter button to take photo or toggle recording |
| `camera snap` | Take a photo in Camera app |
| `camera record` | Toggle video recording in Camera app |
| `haptic` | Trigger haptic feedback |
| `siri` | Activate Siri |
| `accessibility shortcut` | Run the Accessibility Shortcut |
| `respring` | Respring (restart SpringBoard) |
| `safemode` | Enter Safe Mode (restart SpringBoard with tweaks disabled) |
| `ldrestart` | Soft reboot |
| `userspace-reboot` | Userspace reboot |
| `uicache` | Refresh icon cache |
| `low power toggle` | Toggle Low Power Mode |
| `dnd toggle` | Toggle Do Not Disturb |
| `uiopen com.bundle.id` | Open an app by bundle ID |
| `shortcut:My Shortcut Name` | Run an Apple Shortcut by name |
| `shortcut:My Shortcut Name -i` | Run it silently (no Shortcuts progress on screen) |
| `shortcut:My Shortcut Name -p Some text` | Run it with text input (`-i` goes before `-p`) |

### Connectivity
| Command | What it does |
|---|---|
| `wifi toggle` | Toggle Wi-Fi |
| `bluetooth toggle` | Toggle Bluetooth |
| `location toggle` | Toggle Location Services (GPS) |
| `location on` | Turn on Location Services |
| `location off` | Turn off Location Services |
| `airplane toggle` | Toggle Airplane Mode |
| `bt connect Device Name` | Connect a Bluetooth device by name |
| `bt disconnect Device Name` | Disconnect a Bluetooth device |
| `airplay connect UID # Name` | Connect AirPlay to a device |
| `airplay disconnect` | Disconnect AirPlay |

### Device Controls
| Command | What it does |
|---|---|
| `flashlight toggle` | Toggle flashlight |
| `rotate toggle` | Toggle rotation lock |
| `vibration silent-toggle` | Toggle silent vibration |
| `vibration ring-toggle` | Toggle ring vibration |

### Audio (ANC / AirPods)
| Command | What it does |
|---|---|
| `anc on` | Turn on Active Noise Cancellation |
| `anc off` | Turn off ANC |
| `anc transparency` | Enable Transparency mode |
| `audiomix toggle` | Toggle AudioMix |

### Touch Gestures
| Command | What it does |
|---|---|
| `tap 195 422` | Tap at x=195, y=422 |
| `hold 195 422 800` | Hold at x=195, y=422 for 800ms |
| `swipe 195 700 195 200` | Swipe from (195,700) to (195,200) |

### Timing
| Command | What it does |
|---|---|
| `delay 1.5` | Wait 1.5 seconds before next action |
| `stop trigger power_long_press` | Stop that trigger's sequence while it's still running (in a delay) |

A trigger fired again while its sequence is still running runs it again alongside, unless the
trigger's **When Triggered Again** setting (the ⋯ menu on its screen) is **Restart** (the running
sequence stops and starts over) or **Ignore** (the new trigger is skipped).

### Terminal / Shell
| Command | What it does |
|---|---|
| `terminal ls -la` | Run any shell command (no `terminal` prefix needed in raw form — just the shell command string) |

---

## Advanced: Structured Actions

These use a JSON dictionary instead of a plain string.

### Lua Script
Run arbitrary Lua code on the device.

```json
{
  "type": "lua",
  "script": "rc.execute('play')\nrc.sleep(1)\nrc.execute('pause')"
}
```

> In the app, Lua actions appear as `Lua <your code>` strings. For import, use the `Lua ` string prefix format:

```json
"Lua rc.execute('play')"
```

### If / Else Condition
Branch based on device state or time of day. Supported conditions: **front app**, **time of day (between)**, **lock status**, **player status**, **wifi**, **bluetooth**, **airplane mode**, **vibration**, etc.

```json
{
  "type": "if",
  "conditionKey": "time_between",
  "conditionTitle": "Time of Day",
  "expectedValue": "09:00 - 17:00",
  "expectedTitle": "9:00 AM – 5:00 PM"
},
"volume 25",
{
  "type": "else"
},
"volume 75"
```

- Everything after `"type": "if"` up to `"type": "else"` runs when the condition is **true**
- Everything after `"type": "else"` runs when the condition is **false**
- Omit the `else` block if you don't need a fallback

---

## Full Example

Pause if Spotify is open, otherwise play — then wait and take a screenshot:

```json
[
  {
    "type": "if",
    "conditionKey": "front_app",
    "conditionTitle": "Front Application",
    "expectedValue": "com.spotify.client",
    "expectedTitle": "Spotify"
  },
  "pause",
  {
    "type": "else"
  },
  "play",
  "delay 2",
  "screenshot"
]
```

---

## Tips for AI prompts

- **Be specific**: "pause music, wait 3 seconds, lock the screen" beats "do media stuff"
- **Say "return only the JSON array"** — keeps output clean for pasting directly into Import
- **Bundle IDs**: If you need to open a specific app, tell the AI the bundle ID (e.g. `com.apple.mobilesafari` for Safari). If you don't know it, ask the AI.
- **Delays**: Add `"delay 0.5"` between fast actions if the device needs time to respond
