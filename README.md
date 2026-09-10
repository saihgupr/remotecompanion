# RemoteCompanion <img src="images/Icon.png" width="80" align="right" alt="RemoteCompanion" />

RemoteCompanion provides fast, scriptable system control for modern rootless jailbreaks. It lets you bind physical gestures and hardware buttons, or send commands remotely from your computer, to trigger system actions, control media playback, and run custom scripts.

> [!IMPORTANT]
> **What’s New in v3.6**
> - **Location Services in iOS Companion App**: Added Location Services directly to the iOS app action picker (Connectivity section), action display names/icons, and conditional branching (`If Condition... -> Location Services`).
> - **Integrations Hub**: Dedicated Settings sub-menu organizing external services into modular configuration screens (Home Assistant, Keyboard Maestro, and native MQTT Pub/Sub).
> - **Camera & Video Recording Automation**: Automated video recording modes and Lock Screen camera launch triggers.
> - **Time of Day Condition Target (`time_between`)**: Native conditional time evaluation (`If Time is Between ...`).
> - **Action Disable / Enable**: Easily disable and enable individual actions within an action sequence.
> - **Safe Mode Action & CLI**: Enter Safe Mode directly from CLI (`rc safemode`), Web UI, or iOS companion app.

<p align="center">
  <a href="https://saihgupr.github.io/remotecompanion/">Official Website</a> •
  <a href="#features">Features</a> •
  <a href="#web-ui--automations-hub">Web UI Hub</a> •
  <a href="#cli-commands--system-control">CLI Commands</a> •
  <a href="#integrations">Integrations</a> •
  <a href="#installation--setup">Installation</a> •
  <a href="#developer-tools--apis">Developer Tools</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

<p align="center">
  <img src="images/IMG_1514.PNG" width="160" alt="Main Interface" />
  <img src="images/IMG_1515.PNG" width="160" alt="Action Picker" />
  <img src="images/IMG_1517.PNG" width="160" alt="Design Engine" />
  <img src="images/IMG_1518.PNG" width="160" alt="Settings & Backup" />
  <img src="images/IMG_1516.PNG" width="160" alt="Trigger Config" />
</p>

## Features
- **Hardware Triggers**: Bind actions to Power/Volume buttons, Home button, Touch ID (Tap/Hold), or the Ringer Switch.
- **Universal Search**: Instantly find actions, shortcuts, and devices with integrated search bars in every picker.
- **Cross-Version Support**: Full compatibility for iOS 14 through iOS 16+, supporting Rootless, Rootful, and RootHide environments.
- **Advanced Automation**: Full support for NFC tags, custom Lua scripts (with `objc_call` support), and native Siri integration.
- **AI-Assisted Scripting**: Use any AI assistant to generate action sequences from plain English — see [SCRIPTING.md](SCRIPTING.md).
- **iPad Experience**: Native landscape orientation and optimized layouts for iPad power users.
- **Live Discovery**: Discovery-based live lists for nearby AirPlay and Bluetooth hardware.
- **Trigger Favorites**: Mark any trigger as a favorite for instant access at the top of the picker.
- **True Multitasking**: Concurrent server handling powered by GCD—zero battery drain, zero blocking.

---

## Web UI & Automations Hub

Access the desktop-class automation hub at `http://[DEVICE_IP]:8080` from any computer or tablet on your local network.

<p align="center">
  <img src="images/webui.png" width="600" alt="Web UI Interface" />
</p>

<p align="center">
  <img src="images/logs.png" width="380" alt="System & Trigger Logs" />
  <img src="images/health.png" width="380" alt="Device Diagnostics & Health" />
</p>

> [!TIP]
> **To Enable**: Toggle **Web UI** in the RemoteCompanion Settings (Gear icon) or use the command `rc webui on`.

### Key Features
- **Visual Workflow Editor**: Build complex action sequences with an intuitive drag-and-drop interface.
- **Live Device Discovery**: Dynamically search and select installed Apps, nearby Bluetooth hardware, and Wi-Fi networks using integrated search bars.
- **Remote Testing**: Trigger actions and troubleshoot sequences directly from your browser with live execution buttons.
- **One-Tap API Integration**: Every trigger has a dedicated **Copy API Link** button providing a direct URL to fire that trigger from any network-connected hardware or custom scripts.
- **API Link Copying**: In the Web UI, you can swipe any trigger and tap the **Copy** icon to instantly get the full API URL (including your device's IP).
- **Device Diagnostics & Health Dashboard**: Native iOS-styled inset grouped dashboard monitoring battery, storage, RAM, thermal state, uptime, and quick maintenance actions (Respring, UICache, Flush DNS, Clear Logs).
- **Negligible Battery Impact**: The Web UI server is extremely efficient, consuming zero CPU cycles when idle. It uses a background thread with a blocking `accept()` loop that sits dormant until a connection is made.
- **Configuration Management**: Import and export your entire trigger database for easy backups and migration between devices.

---

## CLI Commands & System Control

### Media & Volume
- `rc play` / `rc pause` / `rc playpause` / `rc next` / `rc prev` - Control media playback.
- `rc volume 0-100` - Set volume level.
- `rc mute [on|off|toggle|status]` - Control media mute state.
- `rc anc [on|off|transparency]` - Control headphone ANC (requires Sonitus).

### Device Control
- `rc lock` / `rc lock toggle` - Lock the screen.
- `rc unlock <pin>` - Wakes and unlocks the device.
- `rc button [power|lock|home|volup|voldown|mute]` - Simulate physical button presses.
- `rc brightness 0-100` - Set screen brightness.
- `rc flashlight [on|off|toggle]` - Control the torch.
- `rc rotate [lock|unlock|toggle]` - Orientation lock control.
- `rc appearance [dark|light|toggle]` - Set light/dark appearance.
- `rc dnd [on|off|toggle]` - Toggle Do Not Disturb.
- `rc low power mode [on|off|toggle]` - Toggle battery saver.
- `rc airplane [on|off|toggle]` - Control Airplane Mode.
- `rc haptic` / `rc screenshot` - Haptic feedback / Screenshot.
- `rc screenrecord [toggle|start|stop|status]` - Native SpringBoard screen recording control.
- `rc snapper [open|freeze|instant|close]` - Direct Snapper 2 / Snapper 3 overlay trigger.
- `rc control-center` - Opens the system Control Center.
- `rc switcher` - Opens/toggles the App Switcher.
- `rc previous app` / `rc last app` - Returns to the previously active application.
- `rc vibration [silent-toggle|ring-toggle]` - System "Vibrate on Silent/Ring" settings.

### Apps, URLs & Shortcuts
- `rc open <alias|bundleID>` (e.g., `youtube`, `spotify`, `settings`, `messages`, `home`, `photos`, `camera`, `clock`, `maps`, `calendar`, `weather`, `notes`, `reminders`, `appstore`, `mail`, `music`, `phone`, `stocks`, `calculator`, `tv`, `wallet`, `facetime`, `files`).
- `rc kill <alias|bundleID>` - Force close an app.
- `rc shortcut -r "Name" [-p "Input"]` - Run any Shortcut (requires SpringCuts).
- `rc url "https://google.com"` - Open any link (with smart unlock).
- `rc spotify <playlist|album|artist> <id>` - Play specific Spotify content.
- `rc spotify play` - Resume Spotify playback.

### Connectivity
- `rc wifi [on|off|toggle]` / `rc cellular [on|off|toggle]` / `rc bluetooth [on|off|toggle]` / `rc location [on|off|toggle]`
- `rc bluetooth [connect|disconnect] <name>` - Manage paired devices.
- `rc airplay list` - See speakers and their UIDs.
- `rc airplay connect <name|UID>` - Stream audio to an AirPlay receiver.
- `rc airplay disconnect` - Stop AirPlay streaming.

### Text & Notifications
- `rc type "Text"` - Type text (supports symbols).
- `rc paste "Text"` - Paste into clipboard.
- `rc toast "Title" ["Subtitle"] ["SF Symbol"]` - Display a HUD toast notification. *(Use single quotes if passing special characters like `!` to prevent shell history expansion).*
- `rc key <hex>` - Specific keyboard keys (e.g., `0x04` for 'A', `0x28` for Enter).
- `rc log` - View the RemoteCompanion server logs.

### Status & Queries
- `rc volume` - Returns current volume %.
- `rc app` - Returns foreground app bundle ID.
- `rc is-locked` / `rc lock status` - Returns `locked` or `unlocked`.
- `rc player status` - Returns detailed playback state (`Playing`, `Paused`, `Stopped`, etc.).
- `rc mute status` - Returns current media mute state and level.
- `rc logs` - Stream live debug logs from the device (tail `/tmp/remotecommand.log`).
- `rc vibration [silent-status|ring-status]` - Check current system vibration state.
- `rc orientation status` - Returns `PORTRAIT` or `LANDSCAPE`.
- `rc rotate status` - Returns orientation lock state.
- `rc dnd status` - Returns Do Not Disturb state.
- `rc lpm status` - Returns Low Power Mode state.
- `rc airplane status` - Returns Airplane Mode state.
- `rc wifi status` / `rc cellular status` / `rc bt status` / `rc location status` - Returns connectivity and GPS states.
- `rc flashlight status` - Returns torch state.
- `rc proximity` - Returns `near` or `far`. *(Note: iOS powers off the sensor when the screen is asleep. To test manually while the screen is awake, run `rc proximity on` to force it active, then `rc proximity off` to disable it.)*

### System & Diagnostics
- `rc uicache` - Refresh the icon cache.
- `rc respring` - Restart SpringBoard.
- `rc safemode` - Enter Safe Mode (tweaks disabled).
- `rc ldrestart` - Soft-reboot the device.
- `rc userspace-reboot` - Restart userspace.
- `rc webui [on|off|status]` - Enable, disable, or check the status of the Web UI server.

<details>
<summary><b>Hardware Triggers Reference (Tweak App)</b></summary>

Configure these in the `RemoteCompanion` app for custom action sequences. Tip: **Long-press** any trigger in the app to instantly test and run its assigned actions.

- **Hardware Buttons**:
  - **Power**: Double-tap, Long-press, **Triple/Quadruple click**, or **Power + Volume Up/Down** combos.
  - **Volume**: Long hold Up/Down (0.3s), **Volume Up + Down** combo, or sequential **Volume Up then Down** / **Volume Down then Up** one-handed pocket gestures.
  - **Home**: Double-tap (Touch ID), Double, Triple, or Quadruple click.
- **Touch ID Sensor**: **Single Tap** and **Hold (Rest Finger)** triggers.
- **NFC Triggers**: Scan physical NFC tags to run actions on screen wake (Optional toggle in Settings).
- **Ringer Switch**: Mute, Unmute, or Toggle triggers.
- **Gestures**: 
  - **Status Bar**: Hold (Left/Center/Right), Double-Tap, or Swipe Left/Right.
  - **Edge Gestures**: Vertical swipe on left/right edges.
  - **Bottom Bar Gestures**: Swipe Left/Right, or **3-Zone Swipe Up** (Left 33%, Center 34%, Right 33%).
- **Motion Gestures**:
  - **Shake**: Fire actions when the device is physically shaken.
- **System Events**:
  - **Scheduled**: Run actions at specific times (e.g., Daily at 4 PM).
  - **WiFi/Bluetooth**: Trigger actions on network or device connectivity.
  - **App Launch**: Fire actions when a specific app is opened.

</details>

<details>
<summary><b>Blacklist (App Exclusion)</b></summary>

RemoteCompanion includes a blacklist system to prevent hardware triggers and gestures from firing while specific apps are in the foreground. This is useful for avoiding conflicts with apps that use the same buttons or gestures (e.g. games, camera apps).

Use the `rc blacklist` command to manage the list:
- `rc blacklist list`: View currently blacklisted bundle IDs.
- `rc blacklist add <bundleID>`: Add an app to the blacklist (e.g. `rc blacklist add com.apple.camera`).
- `rc blacklist remove <bundleID>`: Remove an app from the blacklist.
- `rc blacklist reset`: Reset the blacklist to the factory defaults.

</details>

<details>
<summary><b>Conditional Actions & Proximity Rules</b></summary>

Combine status queries with actions for smart automation:
- **Pocket/Proximity-Awareness**: `If Proximity Sensor is Near (Covered / Pocket)` -> `Skip Action` (perfect for preventing accidental pocket flashlight activation).
- **Orientation-Awareness**: `If Orientation is Landscape` -> `Flashlight Toggle`.
- **Bluetooth/Wi-Fi State**: `If Wi-Fi is OFF` -> `Wi-Fi ON`.
- **Time of Day**: `If Time is Between 22:00 and 07:00` -> `Do Not Disturb ON`.

> [!NOTE]
> **Proximity Sensor Cooldown**: To conserve battery, the proximity sensor is only powered on dynamically during button holds and is shut off immediately on release. Due to iOS kernel-level hardware power-gating, rapid consecutive clicks (within ~5 seconds) may temporarily bypass proximity evaluation until the sensor's hardware cooldown window resets.

</details>

<details>
<summary><b>Integrations CLI Commands (HA, Keyboard Maestro, MQTT)</b></summary>

### Home Assistant
- `rc ha toggle <entity_id>` - Toggle a Home Assistant light, switch, or entity (e.g. `rc ha toggle light.bedroom_lights`).
- `rc ha turn_on <entity_id>` / `rc ha turn_off <entity_id>` - Turn on or off a Home Assistant entity.
- `rc ha call <domain.service> <entity_id>` - Call any Home Assistant service (e.g. `rc ha call light.turn_on light.bedroom_lights` or `rc ha call scene.turn_on scene.movie_night`).
- `rc ha raw <domain.service> <json_payload>` - Send custom JSON payloads to any Home Assistant service endpoint (e.g. `rc ha raw light.turn_on '{"entity_id":"light.bedroom","brightness":200}'`).

### Keyboard Maestro
- `rc km trigger <macro_name_or_uuid> [value]` - Trigger a Keyboard Maestro macro on your Mac by Name or UUID (e.g. `rc km trigger "Sleep Display"` or `rc km trigger 12345678-ABCD-EF01-2345-6789ABCDEF01 "MyParam"`).
- `rc km url <web_trigger_url>` - Trigger a full Keyboard Maestro Web Server action URL (e.g. `rc km url "http://192.168.1.50:4490/action.html?macro=Sleep%20Display"`).

### MQTT
- `rc mqtt pub <topic> [payload]` / `rc mqtt publish <topic> [payload]` - Publish messages to an MQTT broker (e.g. `rc mqtt pub "home/livingroom/light/set" "TOGGLE"` or `rc mqtt pub "remotecompanion/device/ping"`).

</details>

---

## Integrations

<details>
<summary><b>Home Assistant Integration</b></summary>

### 1. Controlling Home Assistant from RemoteCompanion

Enable two-way automation between your iOS device and Home Assistant:

1. In the Web UI or iOS App, go to **Settings** &rarr; **Integrations** &rarr; **Home Assistant**.
2. Toggle on **Enable Home Assistant**.
3. Enter your **Server URL** (e.g., `http://192.168.1.100:8123`) and a **Long-Lived Access Token** (generated under your Home Assistant Profile &rarr; Long-Lived Access Tokens).
4. Click **Test Connection** to verify setup.

Once configured:
- Use **Control Home Assistant Entity…** in any trigger sequence to search and select entities (lights, switches, scenes, scripts, automations, locks) with live state badges and quick action options (Toggle, Turn On, Turn Off), or enter custom commands manually.
- Execute HA commands directly via CLI: `rc ha toggle light.bedroom_lights`, `rc ha call light.turn_on light.bedroom_lights`, or `rc ha raw light.turn_on '{"entity_id":"light.bedroom","brightness":200}'`.

### 2. Controlling RemoteCompanion from Home Assistant

Control your iPhone or iPad directly from Home Assistant via SSH `shell_command`:

```yaml
shell_command:
  iphone_remote: >
    ssh -o "StrictHostKeyChecking=no" mobile@YOUR_IPHONE_IP "rc {{ cmd }}"
```
Then call it in automations or scripts:

```yaml
service: shell_command.iphone_remote
data:
  cmd: 'play'
```

Alternatively, call the Automations API endpoint: `http://[DEVICE_IP]:8080/api/command?cmd=lock`.

</details>

<details>
<summary><b>Keyboard Maestro Integration</b></summary>

### Controlling Keyboard Maestro from RemoteCompanion

Trigger macros on your Mac directly from iPhone hardware gestures, buttons, NFC tags, or scripts:

1. In Keyboard Maestro on your Mac, open **Preferences** &rarr; **Web Server** and check **Enable Web Server**.
2. Note your Mac's IP address and Port (default: `4490`), and set a Username/Password if desired.
3. In the RemoteCompanion Web UI or iOS App, go to **Settings** &rarr; **Integrations** &rarr; **Keyboard Maestro**.
4. Toggle on **Enable Keyboard Maestro**.
5. Enter your **Web Server URL** (e.g., `http://192.168.1.50:4490`) and optional **Username** and **Password** (supports HTTP Basic Authentication).
6. Click **Test Connection** to verify connectivity.

Once configured:
- **Visual Macro Picker**: Open **Keyboard Maestro: Trigger Macro…** in the action picker to browse and search all macros categorized by group, with instant live filtering and parameter selection.
- **Parameter Support**: Tapping or long-pressing any KM action in an action sequence allows you to edit or remove its `%TriggerValue%` parameter, test execution immediately, or switch to a different macro.
- **CLI & Scripts**: Execute KM commands directly via CLI: `rc km trigger "Sleep Display"` or `rc km "My Macro Name" "Optional Value"`.

</details>

<details>
<summary><b>MQTT Integration (Pub / Sub)</b></summary>

### 1. Publishing to MQTT from RemoteCompanion

Connect directly to local or cloud MQTT brokers (e.g. Mosquitto, EMQX, Home Assistant Mosquitto add-on) with zero external dependencies and near-zero battery impact:

1. In the RemoteCompanion Web UI or iOS App, go to **Settings** &rarr; **Integrations** &rarr; **MQTT**.
2. Toggle on **Enable MQTT**.
3. Enter your **Broker Host** (e.g. `192.168.1.50` or `homeassistant.local`), **Port** (`1883`), **Client ID**, and optional **Username** & **Password**.
4. Set an optional **Default Topic Prefix** (e.g. `home/bedroom` or `remotecompanion`).
5. Tap **Test Connection** to confirm broker communication.

Once configured:
- **Action Picker**: Select **MQTT: Publish Topic…** to assign publish actions with customizable topics and payloads (strings, numbers, or JSON) to any gesture, hardware button, or scheduled trigger.
- **CLI**: Publish directly from scripts or terminal using `rc mqtt pub <topic> [payload]`.

### 2. Inbound MQTT Subscription Triggers

Subscribe to topics on your broker and execute local iOS action sequences whenever an MQTT message arrives:

1. In the iOS App or Web UI, tap **`+`** (New Trigger) &rarr; **MQTT Topic**.
2. Enter the **MQTT Topic** to monitor (e.g. `home/alerts/phone`, `remotecompanion/wake`, or wildcards like `sensors/+/state`).
3. (Optional) Enter an exact **Payload Match** (e.g. `ON`, `RING`), or leave empty to trigger on any message.
4. Add your desired action sequence (Haptic alert, audio alarm, flashlight toggle, TTS speech, app launch, etc.).

The background listener daemon runs inside SpringBoard with automatic 60s keep-alives, auto-reconnect, and shuts down whenever no MQTT triggers are active to ensure zero idle battery drain.

</details>

---

## Installation & Setup

### 1. Requirements
- A **Jailbroken Device** running iOS 14 through iOS 16+.
- Compatible with **Rootless**, **Rootful**, and **RootHide** jailbreak environments (Dopamine, Palera1n, unc0ver, Taurine, XinaA15, NathanLR).

### 2. Installation

#### Option 1: Package Manager Repository (Recommended)
Add `https://saihgupr.github.io/remotecompanion` to your package manager:
- [Add to Sileo](sileo://source/https://saihgupr.github.io/remotecompanion)
- [Add to Zebra](zbra://sources/add/https://saihgupr.github.io/remotecompanion)

#### Option 2: Manual .deb Installation
Download the latest `.deb` package from [Releases](https://github.com/saihgupr/remotecompanion/releases) and install via Sileo, Filza, or `dpkg -i`.

#### Option 3: Build from Source
Ensure you have [Theos](https://theos.dev) installed.
```bash
git clone https://github.com/saihgupr/remotecompanion.git
cd remotecompanion
./build.sh
```
By default, `./build.sh` builds the unified rootless `.deb` package (companion app, web UI, CLI, and tweak). You can also pass `--rootful`, `--roothide`, `--all`, or `--clean`.


### 3. Usage Methods

#### Method A: Computer Terminal via `rc` Script (Easiest)
Control your iPhone from your computer terminal using the included `rc` client script. It communicates over SSH into a local UNIX socket on the device:

1. Copy the script to your computer's PATH:
   ```bash
   chmod +x rc
   sudo cp rc /usr/local/bin/rc
   ```
2. Set your iPhone's IP or hostname in your shell profile (e.g., `~/.zshrc`):
   ```bash
   export RC_IPHONE_IP=iphone.local
   ```
3. Run any command:
   ```bash
   rc play
   rc volume 50
   rc flashlight toggle
   ```

#### Method B: Direct SSH
Run commands directly on the iPhone over SSH:
```bash
ssh mobile@iphone.local "rc lock"
ssh mobile@iphone.local "rc volume 50"
ssh mobile@iphone.local "rc respring"
```

#### Method C: iOS Shortcuts
Trigger RemoteCompanion commands inside iOS Shortcuts automations:
- **Native SSH Action**: Add the **Run script over SSH** action in Shortcuts (`Host: localhost`, `Port: 22`, `User: mobile`, `Script: rc flashlight toggle`).
- **Powercuts Action**: If you have **Powercuts** installed, add **Run shell command** with `rc open Music`.

---

## Developer Tools & APIs

<details>
<summary><b>Lua Scripting & Objective-C Bridge</b></summary>

RemoteCompanion introduces a powerful Lua bridge that allows you to execute arbitrary Lua scripts within the tweak's process. The exact same context is available whether you run a script file from the CLI or paste code into the "Lua Script" action in the app.

### How to Run
- **From CLI**: `rc lua /path/to/script.lua`
- **From UI**: Add Action → System → **Custom Lua Script**. Paste your code directly into the prompt.

### API Bindings

| Function | Description |
| :--- | :--- |
| `log(msg)` | Writes to the system log (syslog). |
| `delay(seconds)` | Pauses execution for `seconds`. |
| `haptic()` | Triggers a standard haptic feedback. |
| `openURL(url)` | Opens a URL scheme (e.g. `prefs:root=General`). |
| `dlopen(path)` | Loads a dynamic library. Returns `true` on success. |
| `objc_call(target, selector, args...)` | Calls an Objective-C method. `target` can be a class name string or an instance. |

### Examples

**Trigger Haptic and Log**
```lua
log("Starting haptic engine...")
haptic()
delay(0.2)
haptic()
log("Finished haptic feedback.")
```

**Call a Class Method (get a shared instance)**
```lua
-- objc_call(className, selector) returns an instance
local device = objc_call("UIDevice", "currentDevice")
if device then
    objc_call(device, "setBatteryMonitoringEnabled:", true)
    local level = objc_call(device, "batteryLevel")
    log("Battery: " .. tostring(level * 100) .. "%")
end
```

> [!NOTE]
> `objc_call` works like standard Objective-C messaging — it does not scan memory for existing instances. To call an instance method, you first need to obtain the instance via a class-level accessor (e.g. `sharedInstance`, `currentDevice`) or by allocating a new one with `alloc`/`init`.

</details>

<details>
<summary><b>AI-Assisted Sequence Builder</b></summary>

Use any AI assistant (ChatGPT, Claude, Gemini, etc.) to build action sequences from plain English, then paste the result directly into the app using **Import**.

**[→ Full guide + copy-paste AI prompt: SCRIPTING.md](SCRIPTING.md)**

Example prompt:
```
Read this guide: https://github.com/saihgupr/remotecompanion/blob/main/SCRIPTING.md

Using the action format defined there, create a RemoteCompanion sequence that:
pause music, wait 2 seconds, take a screenshot, then play music again

Return ONLY the raw JSON array. No explanation, no markdown, no code fences.
```

Copy the JSON output → open your trigger → tap **⋯** → **Import** → paste → **Import**.

</details>

<details>
<summary><b>Automations API & HTTP REST Server</b></summary>

Control your device from any network-connected hardware via simple HTTP calls.

> [!IMPORTANT]
> The **Web UI** toggle must be enabled in the RemoteCompanion settings (or via `rc webui on`) for the HTTP server to be active.

**1. Discover Commands & Triggers:**
Get a list of all supported system commands or your custom automation triggers:
- Commands: `http://[device_ip]:8080/api/commands`
- Triggers: `http://[device_ip]:8080/api/triggers`

**2. Execute a System Command:**
Send command strings via `GET` or `POST`:
- **Example (GET)**: `http://[device_ip]:8080/api/command?cmd=play`
- **Example (POST)**: `curl -X POST "http://[device_ip]:8080/api/command" -d "haptic"`

**3. Fire an Automation Trigger:**
Execution URLs for your specific triggers:
- **Example**: `http://[device_ip]:8080/api/trigger/trigger_1`

#### Performance & Implementation
* **Speed**: The HTTP API is significantly faster than SSH (~0.1s faster) by skipping the heavy SSH handshake.
* **Efficiency**: The Web UI server sits in a dormant `accept()` loop, consuming **zero CPU cycles** when idle.

</details>

---

## Security

RemoteCompanion implements several measures to ensure your device remains secure:

- **Local Execution**: Local apps and the `rc` CLI communicate securely via a local UNIX socket file, ensuring zero network exposure.
- **Web UI & Automations API**: When enabled, the Automations Hub server transmits data in **plain-text** over your local network. No authentication is required for API access. It is **highly recommended** to only enable the Web UI on trusted, private networks.

---

<details id="troubleshooting">
<summary><h2>Troubleshooting</h2></summary>

### Apple Pay Issues
If you experience the "Updating Cards" screen or other conflicts with Apple Pay when waking your device, you can disable the background NFC scanning feature.
1. Go to the **Settings** tab (gear icon).
2. Toggle off **NFC Scanning**.

This ensures the tweak does not attempt to access the NFC controller on wake, resolving conflicts with system services.

### iOS 14 arm64e (A12+) Compatibility
Due to Pointer Authentication Code (PAC) changes in modern toolchains, iOS 14 on **arm64e (A12 and newer)** devices is currently unsupported and may cause a Safe Mode loop.
- **Supported**: iOS 14 on A11 and below (iPhone 8/X and older, iPad Air 2, etc.)
- **Supported**: iOS 15+ on all devices.
- **Workaround**: If you are on iOS 14 with a newer device, you may need to compile the tweak using **Xcode 15.4** or earlier to ensure correct PAC signatures.

</details>

---

## Support & Feedback

If you encounter any issues or have feature requests, please [open an issue](https://github.com/saihgupr/remotecompanion/issues) on GitHub.

RemoteCompanion is open-source and free. If you find it useful, consider giving it a star on GitHub or making a small [donation](https://ko-fi.com/saihgupr) to support development.