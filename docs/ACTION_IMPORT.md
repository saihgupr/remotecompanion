# RemoteCompanion Action Import Reference Guide

This document serves as a complete reference sheet for users and AI coding assistants (like Claude, Gemini, ChatGPT) to generate, format, and share **Action Sequences** that can be imported into RemoteCompanion.

---

## 1. Supported Formats

RemoteCompanion accepts action sequences in two formats:

### Format A: JSON Array (Recommended for AI & Sharing)
A valid JSON array containing strings representing command lines. Special characters (like quotes in shortcut names or toasts) must be escaped.
```json
[
  "flashlight toggle",
  "delay 1.5",
  "toast \"Light Check\" \"Flashlight toggled!\" \"bolt.fill\""
]
```

### Format B: Raw Newline-Separated Lines (Simple Text)
Each non-empty line is treated as a separate command. Quotes do not need to be escaped unless required by the command syntax (e.g. shortcut names).
```text
flashlight toggle
delay 1.5
toast "Light Check" "Flashlight toggled!" "bolt.fill"
```

---

## 2. Command Reference Dictionary

Here is the complete list of valid commands you can write, along with parameters and examples:

### System & Navigation Controls
| Command Syntax | Description | Example |
| :--- | :--- | :--- |
| `lock` | Lock the iOS device screen | `lock` |
| `unlock <passcode>` | Unlock screen using passcode (plain text) | `unlock 1234` |
| `home` | Press the native Home Button | `home` |
| `screenshot` | Take a screenshot | `screenshot` |
| `open control center` | Slide down the Control Center | `open control center` |
| `app switcher` | Show multitasking App Switcher | `app switcher` |
| `open <bundle_id>` | Launch an app by its bundle identifier | `open com.apple.Preferences` |
| `kill <bundle_id>` | Force close/kill an app in background | `kill com.amazon.Amazon` |
| `kill current` (or `kill front`, `kill foreground`) | Force close the currently focused app | `kill current` |
| `respring` | Restart SpringBoard | `respring` |
| `ldrestart` | Perform a soft-reboot of the system | `ldrestart` |
| `previous app` (or `last app`) | Return to the previously active application | `previous app` |
| `haptic` | Trigger a subtle haptic feedback vibration | `haptic` |

### Media Playback & Volume
| Command Syntax | Description | Example |
| :--- | :--- | :--- |
| `play` | Start audio playback | `play` |
| `pause` | Pause active playback | `pause` |
| `next` | Skip to the next track | `next` |
| `prev` | Skip to the previous track | `prev` |
| `toggle` | Toggle playback between play/pause | `toggle` |
| `vol up` | Raise system volume by 1 step | `vol up` |
| `vol down` | Lower system volume by 1 step | `vol down` |
| `volume <0-100>` | Set system volume to specific percentage | `volume 50` |

### Tweak & Device Hardware Toggles
| Command Syntax | Description | Example |
| :--- | :--- | :--- |
| `flashlight toggle` | Toggle flashlight on/off | `flashlight toggle` |
| `flashlight <1-100>` | Turn flashlight on at specific brightness level | `flashlight 50` |
| `flashlight on` / `flashlight off` | Turn flashlight solid ON or OFF | `flashlight on` |
| `brightness <0-100>` | Set screen brightness percentage | `brightness 75` |
| `bt on` / `bt off` / `bt toggle` | Turn Bluetooth on, off, or toggle state | `bt toggle` |
| `wifi on` / `wifi off` / `wifi toggle` | Turn Wi-Fi on, off, or toggle state | `wifi toggle` |
| `airplane on` / `airplane off` / `airplane toggle` | Turn Airplane Mode on, off, or toggle state | `airplane toggle` |
| `dnd on` / `dnd off` / `dnd toggle` | Turn Do Not Disturb on, off, or toggle state | `dnd toggle` |
| `audiomix on` / `audiomix off` / `audiomix toggle` | Turn AudioMix on, off, or toggle state | `audiomix toggle` |
| `low power on` / `low power off` / `low power toggle` | Turn Low Power Mode on, off, or toggle state | `low power toggle` |
| `mute` | Toggle silent/ringer mode | `mute` |
| `rotate lock` / `rotate unlock` / `rotate toggle` | Turn Orientation Lock on, off, or toggle state | `rotate toggle` |

### Automations & Execution
| Command Syntax | Description | Example |
| :--- | :--- | :--- |
| `delay <seconds>` | Block execution queue for X seconds | `delay 2.5` |
| `shortcut "<shortcut_name>"` | Execute a Siri Shortcut | `shortcut "Calculate Tip"` |
| `trigger <trigger_id>` | Fire a RemoteCompanion trigger by ID | `trigger shake` |

### Toast Notifications (HUD)
Displays system-wide dropdown glassmorphic notification banner with custom title, subtitle, and icon.
- **Syntax**: `toast "<title>" ["<subtitle>" "<sf_symbol>"]`
- **Arguments**: 
  - Subtitle and SF symbol are optional.
  - Wrap arguments in quotes.
- **Examples**:
  - `toast "Hello World"` (Title only)
  - `toast "AudioMix" "Enabled" "music.note"` (Title, Subtitle, and SF Symbol)
  - `toast "Alert!" "bolt.fill"` (Title and SF Symbol, no Subtitle)

---

## 3. Recommended SF Symbols for HUD/Toasts
Use standard Apple SF Symbols to add icons to your toasts:
- 🎵 Music: `music.note`, `play.fill`, `pause.fill`
- ⚡ Flashlight/Power: `bolt.fill`, `bolt.slash.fill`, `power`
- 📶 Connections: `wifi`, `bolt.horizontal.fill` (Bluetooth)
- 🔔 Alerts: `bell.fill`, `bell.slash.fill`, `exclamationmark.triangle.fill`
- 🔒 Security: `lock.fill`, `lock.open.fill`, `touchid`
- ⚙️ Settings: `gear`, `slider.horizontal.3`

---

## 4. Example Action Sequences

Here are copy-pasteable examples to copy and import directly:

### Example A: Night Mode Setup
Turns off Bluetooth, turns on Low Power Mode and Do Not Disturb, sets brightness to 10%, and shows a confirmation toast:
```json
[
  "bt off",
  "low power on",
  "dnd on",
  "brightness 10",
  "toast \"Night Mode\" \"Ready for sleep\" \"bed.double.fill\""
]
```

### Example B: Toggling AudioMix with HUD feedback
Toggles the AudioMix tweak, waits 1 second, and shows a custom HUD toast confirmation:
```json
[
  "audiomix toggle",
  "delay 1",
  "toast \"AudioMix\" \"Toggled\" \"music.note\""
]
```

### Example C: Open Camera & Delay
Opens the Preferences app, waits 2 seconds, and simulates home button:
```text
open com.apple.Preferences
delay 2
home
```
