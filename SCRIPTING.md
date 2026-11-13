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
| `notify "Title" ["Message"]` | Post a standard iOS notification; add `--tap ID`, `--button "ID|Title|flags"`, `--image-url URL` or `--wait SECONDS` |
| `notify clear` | Remove RC's notifications from Notification Center |
| `clear notification [--all] [--app BUNDLE\|rc] [--text TEXT]` | Clear notifications by app and/or matching text (`notify clear {"apps":[...],"texts":[...]}`) |
| `timer <duration\|stop\|pause\|resume\|status>` | Start (`20m`, `1h30m`, `45s`, `20:00`), pause, resume, stop, or inspect the Apple Clock timer (supports `--label "Name"`) |

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

The `gesture` touches below use the real touchscreen, so apps receive them like a finger. Points
are screen points in the current orientation, and the next action starts once the touch is done.

| Command | What it does |
|---|---|
| `gesture tap 195 422` | Tap at x=195, y=422 |
| `gesture hold 195 422 0.8` | Hold for 0.8 seconds (default 1) |
| `gesture swipe 195 700 195 200` | Swipe; add seconds to set the speed (default 0.3). Starting on a screen edge makes it an edge swipe: `gesture swipe 195 852 195 450` goes home |
| `gesture drag 195 700 195 400` | Drag and let go slowly, so the content stops where it is put |
| `gesture swipe2 195 600 195 300` | A two-finger swipe, e.g. to pan a map |
| `gesture pinch 195 422 2` | Two fingers spreading around (195,422) to zoom in (0.5 zooms out) |
| `gesture rotate 195 422 90` | Two fingers turning 90° clockwise (negative turns the other way) |

After a reboot, touch the screen once before the first `gesture` touch, so RemoteCompanion knows the touchscreen.

### Screenshot
| Command | What it does |
|---|---|
| `screen capture` | Saves a JPEG of the screen to `/var/mobile/tmp/rc-screen.jpg` at half its size in points |
| `screen capture /var/mobile/tmp/shot.jpg 1 0.8` | Another path (in `/var/mobile/tmp` or `/tmp`), full size, JPEG quality 0.8 |
| `screen capture grid` | With labelled lines every 100 points (`grid 50` for every 50), to read positions off the picture |
| `screen settle 3` | Waits until the screen stops changing (a page sliding in, an app opening), at most 3 seconds |

The reply is the path, the picture's size and its bytes. Both `gesture` and `screen` need the API token when sent over the network.

### Text on the Screen
These read the screen with Apple's text recognition, so any text that's drawn counts, in any app.
Matching ignores case: the same text first, then a line starting with it, then one containing it.

| Command | What it does |
|---|---|
| `screen tap "Wi-Fi"` | Waits for the screen to stop moving, then taps the text where it shows (Tap Text on Screen in the app). A home screen app's name is a label on iOS, not part of its button, so use `open_app` or `uiopen` for those |
| `screen wait "Done" 10` | Waits up to 10 seconds for the text to show, then for the screen to stop moving (Wait for Text) |
| `screen find "Wi-Fi"` | Where the text is, in points |
| `screen copy` | Copies every line of text on the screen to the clipboard, one per line, and returns it (Copy All Text on Screen in the app) |
| `screen copy rect [SECONDS]` | Grabs the screen, lets you drag a box over text with one finger, copies the touched lines to the clipboard, and returns them. Defaults to 20 seconds, at most 120 (Copy Text on Screen) |
| `screen ocr` | Every line of text with its box in points (`--json` for JSON, `fast` for a quicker, rougher read) |

The **Text on Screen** condition (in If and Wait Until) is true while the text shows.

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

### Remote RC
Run a command on another device through its RemoteCompanion Web UI.

| Command | What it does |
|---|---|
| `rc-run <clientId> play` | Run an RC command on the saved client with that id |
| `rc-run <clientId> lock` | Lock the other device |
| `rc-run <clientId> shortcut:My Shortcut` | Run a Shortcut on the other device |

Client ids come from **Settings > Integrations > Remote RC Clients** (or the `rcClients` array in `rc_triggers.plist`). The other device needs its Web UI on; privileged commands need that device's API token saved on the client.

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

### REST API Call
Call any HTTP endpoint. The action is one `http-request` string holding the request as JSON:

```json
"http-request {\"method\":\"POST\",\"url\":\"https://example.com/hook\",\"headers\":{\"Authorization\":\"Bearer TOKEN\"},\"body\":\"{\\\"event\\\":\\\"ping\\\"}\"}"
```

- `method` defaults to GET. GET, POST, PUT, PATCH, DELETE, HEAD and OPTIONS work.
- `headers` and `body` are optional. A body can also be a JSON object instead of an escaped string:
  ```json
  "http-request {\"method\":\"POST\",\"url\":\"https://example.com/hook\",\"body\":{\"event\":\"ping\"}}"
  ```
- A JSON body is sent as `application/json` unless you set a Content-Type header.
- The request runs in the background, so the next action starts right away. The reply is written to `rc logs`.
- HTTPS endpoints with self-signed certificates work, like the Home Assistant and Keyboard Maestro integrations.
- A bare URL is a GET: `"http-request https://example.com/ping"`.
- To run an RC command on this iPhone from a trigger, call the local Web UI API (the Web UI must be on):
  ```json
  "http-request {\"method\":\"GET\",\"url\":\"http://127.0.0.1:8080/api/command?cmd=play\"}"
  ```

In the app, pick **REST API Call...** under Integrations, which fills in this string for you.

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
