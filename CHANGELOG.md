# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **MCP server: state, triggers and debugging tools**: the local `tools/rc-mcp` server now has an offline index of every command (`rc_help`), a one-call state read (`rc_state`), full trigger control (`rc_trigger`: list, inspect, run, stop, create, edit, enable, delete), config read and write with a backup and read-back (`rc_config`), sequence validation (`rc_sequence`), and `remotecompanion://` navigation (`rc_deeplink`). Debugging covers the app log, running and recent runs, files, screenshots, the Test Kit (probe, journal, mark, suites, reports, snapshot, restore) and add-ons (validate, parse, trace, reload).
- **Native Apple Timer action, UI & CLI**: added **Timer...** under Device Controls (and `timer` in CLI/scripting/WebUI) using `MobileTimer.framework` so timers run as real Apple Clock timers—syncing with Lock Screen, Control Center, and vibrating your Apple Watch where you can stop or dismiss them. Supports start durations (`20m`, `1h30m`, `45s`, `20:00`, seconds, or `{variable}`), `pause`, `resume`, `stop`, `status`, and optional `--label` naming on iOS 17+.
- **Copy Text on Screen**: two actions and CLI commands that read drawn text anywhere on the screen with Apple's text recognition and copy it to the clipboard. **Copy Text on Screen** (`screen copy rect [SECONDS]`, default 20 s, at most 120) captures the screen first and lets you drag a rectangle over text with one finger to copy the lines it touches (falling back to cropping and enlarging small text); tapping cancels without changing the clipboard. **Copy All Text on Screen** (`screen copy`) copies every line on the screen at once, and both return the copied text.
- **Control Center Button trigger**: New Trigger > Control Center Button makes a button for Control Center with a name, an SF Symbol icon and its own action sequence; tapping it runs the actions. Up to 4 buttons, added in Settings > Control Center as RemoteCompanion Button 1-4. Needs CCSupport and iOS 17 or earlier.
- **Real touches for gesture commands**: `gesture tap`, `hold`, `swipe`, `drag`, `swipe2`, `pinch` and `rotate` move the touchscreen itself, so apps receive them like a finger, where the older `tap`, `hold` and `swipe` commands do not always reach them and stay as they are. Points are screen points as the screen is turned, a touch that starts on an edge still starts the home or back gesture, and a still finger keeps reporting so long presses register. After a reboot, touch the screen once before the first touch command (#157).
- **Screenshot command**: `screen capture [PATH] [SCALE] [QUALITY]` writes a JPEG of the screen, half size in points unless told otherwise, with `grid` for labelled lines to read positions off the picture. `screen settle [SECONDS]` waits until the screen stops changing, for actions that run after a page slides in or an app opens. `screen` and `gesture` are privileged commands, so they need the API token when they arrive over the network (#157).
- **Tap Text on Screen and Wait for Text**: actions that read the screen with Apple's text recognition, so any text that is drawn counts, in any app, then tap it where it shows or wait until it appears. Matching ignores case and takes the same text first, then a line starting with it, then one containing it. `screen tap`, `screen wait`, `screen find` and `screen ocr` do the same from the CLI, and the new `rc-ocr` tool reads the screen on iOS 15 where SpringBoard's own careful read fails (#158).
- **Text on Screen condition**: in If and Wait Until, true while the text shows anywhere on the screen (#158).
- **MCP server for assistants**: `tools/rc-mcp` is one Python file that lets an MCP client look at the screen, tap, swipe, type and run any RC command over SSH. Nothing is installed on the phone (#159).
- **Compact New Trigger menu**: Settings > Advanced Settings > Layout has a New Trigger row, List or Compact. Compact shows the trigger types as tiles with the icons their triggers use, the same category bar as Triggers, and a check on types already added; a search stays within the picked category. Choosing a search result now opens its setup screen instead of dropping the tap (#146).
- **Banner categories**: Settings > Banners now has the same category bar as Select Action, with All, Enabled and a chip per category. A category chip shows all of its actions whether checked or not, Enabled shows only the checked ones, and each chip has its category icon; the bar hides while scrolling down (#156).
- **Standard iOS notifications**: `notify` now posts a real notification as the RemoteCompanion app, with a banner, a sound and an entry in Notification Center, whether or not the app is running. The Notification action gets an editor for the title, message, a symbol or app icon, Time Sensitive, Remove After, up to four buttons, and Wait for Response, whose answer becomes `{notify_response}`. Notification Tap triggers run from a tap or a button, and `notify clear` removes them (#153).

### Changed
- **MCP server: one gesture tool**: tap, hold, swipe, drag, two-finger swipe and pinch are now one `gesture` tool with a `kind`, so the server lists 21 tools instead of 26 and sends about 650 fewer tokens of tool schemas.
- **Clear Notifications action and CLI**: replaced **Clear RC Notifications** with **Clear Notifications**, letting you target Any App or specific apps (including RemoteCompanion) and add or paste as many case-insensitive text filters as you want. `rc clear notification` (and `rc notify clear`) now accepts `--all`, `--app`, inline filter strings, and line-by-line `.txt` files.
- **Tighter bar gesture zones**: the status bar and bottom bar gesture areas now cover 25pt from the edge instead of 50pt, so a touch has to land closer to the bar. Two-finger slides keep their wider 75pt landing zone.

## [4.5.0] - 2026-11-11

### Added
- **Full backup and restore**: Settings > Backup > Export Configuration now writes one file with everything on the device, including integrations, SSH hosts, tokens, add-ons, gestures, notification filters, variables and the app blacklist. Import Configuration puts it back on a new device exactly as it was, and still accepts older configuration files. `rc backup [path]` and `rc restore <path>` do the same from a terminal.
- **Triggers only when added**: the Triggers screen now starts empty and lists only the triggers you add. Every built-in trigger moved into the + menu, including volume, power, status bar, edge and bottom bar gestures, multi-finger slides, Home/Touch ID, ringer, motion, device state, media, calls and Apple Watch, so the list stays short instead of showing dozens of unused rows.
- **First-trigger onboarding**: with nothing added, the app shows a friendly invitation and a hand-drawn arrow curving up to the + button, plus an Add a Trigger button. The Web UI has the same empty state and add menu.
- **Remote RC actions**: Settings > Integrations > Remote RC Clients stores another device's address and Web UI port (8080 by default) plus an optional API token. A new Remote RC action runs regular RC commands on that device over its Web UI, with no SSH needed. Creating one opens the normal action list filtered for the remote, so play, lock, volume, shortcuts and the rest are picked and parameterized the same way as local actions.
- **Remote actions edit like local actions**: a remote Mute action shows the same blue Toggle suffix and opens the same state picker, and every parameter editor (volume, delay, shortcuts, Home Assistant, Keyboard Maestro, MQTT, toast, SSH and the rest) works on the remote command exactly as it does locally, while keeping the target client. The long-press menu has Remote Client... to change the device.
- **Duplicate actions**: the long-press action menu can duplicate a row in place, and the Web UI's right-click menu has the same. If and Repeat blocks, including their Else branches, duplicate whole so a block is never split.

### Changed
- **AudioStream auto-start is opt-in**: `/api/audiostream/start` now returns 403 unless AudioStream auto-start is enabled. The switch lives under Settings > Integrations > AudioStream in the app and the Web UI, only appears when AudioStream is installed, and is off by default, so a NAS or other client timing out can no longer wake the iPhone streaming daemon.
- **Built-in triggers can be deleted**: removing a button or gesture trigger puts it back in the + menu, just like a tag, network, app or schedule trigger. The list never shows a trigger that was not added.
- **Integrations fold into their own lists**: Snapper and SneakyCam show as one row each in Select Action > Integrations with a chevron, opening just their actions, so the section stays short. Search still finds every action directly, and Settings > Banners keeps the full flat list.
- **Variables icon**: the Variables row uses an orange italic x, in the style of Shortcuts' variable glyph. Set Variable actions use the same x in the normal action icon color.
- **Terminal command editor**: creating or editing an `exec` or `root` action now uses the same Settings-style screen as the SSH command editor, with the root switch in its own section above the monospaced command field.
- **Home Assistant actions edit like the entity picker**: tapping an existing HA action in the app, or clicking one in the Web UI, shows its Toggle, Turn On and Turn Off choices with the current one ticked, plus Change Entity. Raw and custom commands keep an Edit Command option instead of being overwritten.
- **REST API Call editor**: the app's editor uses one-line hints instead of long footer paragraphs and shorter header and body fields, so the whole request fits without the dead space.

### Fixed
- **Control Center on iOS 18**: later iOS 18 releases dropped the single Control Center controller RC used, so the action and `rc control-center` did nothing. They now open it through `SBControlCenterCoordinator` (#148).
- **App Switcher on iOS 18 and 26**: the old toggle method is gone on iOS 18, so the action and `rc switcher` failed. They now use the main screen's switcher controller, and iOS 17 keeps the old call (#149).
- **Quick Shortcuts and Camera modes on iOS 26**: a Quick Shortcut now runs through the class iOS 26 moved it to, and a Camera action with a mode or lens applies it now that the mode method has a new name. The two fallbacks behind it were also wrong and are fixed (#150).
- **Lua objc_call with arguments**: arguments are kept alive until the call finishes, so a string, number or boolean argument no longer crashes SpringBoard. Float arguments arrive at their real size, and float, double and unsigned returns come back correctly (#144).
- **Trigger name after editing a schedule**: the trigger's screen updates its title as soon as a new time or days are saved, instead of showing the old name until you go back and open it again (#145).
- **Test Kit on iOS 26**: Spotlight and the Today view are found and closed through the home screen controller, so a step starts on the right screen. Test Kit only, no user-facing change (#151).
- **Two-finger and Bluetooth trigger icons**: each two-finger slide has its own drawing instead of the same generic hand, and Bluetooth Device triggers show a drawn Bluetooth logo instead of a lightning bolt (#154).
- **Add-on programs run again**: every add-on `exec` step and exec condition failed with "stopped or killed" on rootless, because the runner waited on its output pipes with `poll()`, which SpringBoard's sandbox refuses with `EPERM`. The pipes are read without `poll()` now, so `exec` steps and exec conditions work, including the Uptime add-on.

## [4.4.0] - 2026-11-06

### Added
- **REST API Call action**: a new action that calls any http:// or https:// URL with the method, headers and body you choose. It is empty by default, so it can hit a webhook, a local service, or this iPhone's own `/api/command` endpoint. Requests run in the background and the reply is written to the log. In the app, pick **REST API Call...** under Integrations to edit it; in the Web UI it is in the same section. Also available as the `http-request` command for scripts and imports.
- **Compact layout**: Triggers, Select Action and Settings > Banners can each show a grid of tiles instead of a list, chosen in Advanced Settings > Layout. List stays the default. Trigger tiles are cards with the icon beside the name, with Triggers per Row at 2, 3 or 4, an optional Compact Sections mode that puts every trigger in one grid, and a 1 to 3 line category bar. Edit adds a star (favorite) and a minus (delete, asked first) to each tile, and favorites can be dragged to reorder. Select Action and Banners tiles show an icon over the name, with a small chevron for actions that open another screen, and enabled banners tinted and checked (#110).
- **Trigger icons and names**: button and gesture triggers are drawn as a tiny phone with the pressed button, or the touched part of the screen, marked and the outcome in the middle (2x, a clock for a hold, + for two buttons). App Launch and App Exit show the app's icon with a green check or red x. Category chips and section titles each have an icon, and created triggers (NFC tags, networks and devices) get theirs too. "Screen Gestures" now reads "Status Bar" (#110).
- **Trigger search**: the New Trigger screen has a search field that filters as you type by trigger name, section, detail and keywords, ignoring case and punctuation, so "wifi" finds Wi-Fi Network and "applaunch" finds App Launch. Sections with no matches drop out, an empty result says "No Triggers Found", and choosing a result closes search before the setup screen opens.
- **Gesture Recorder**: Settings > Gestures records a mix of taps, swipes and scrolls, then names the recording and plays it back. Play Gesture runs a recording at 0.5x to 3x, or the latest one; Record Gesture starts and stops recording from a trigger. Each gesture can be trimmed, re-recorded, replaced, renamed, exported and imported, with Show Touches and Stop on Touch options (#120).
- **App Quick Action**: choose an app in the icon or search picker, then one of its registered shortcuts, read live from SpringBoard's application model so the Home Screen menu no longer has to be opened first. Same-type shortcuts with different payloads are told apart, and unavailable or changed shortcuts are reported instead of running stale data (#126).
- **Excluded Apps**: Settings > Advanced Settings > Options lists every trigger that has actions, grouped and ordered like the Triggers page and searchable. Each row shows its action sequence and the apps where that trigger should not fire, and the list follows the Wrap Long Names setting (#126).
- **Rotation triggers**: Rotated to Landscape and Rotated to Portrait fire when the screen finishes rotating, after a half-second settle so a quick turn and back does nothing. They follow the screen, so rotation lock or a portrait-only app fires nothing (#111).
- **Find My Sound trigger**: runs when Play Sound is sent to the phone from Find My or iCloud.com. Keep Default Action is on by default and the sound plays as usual; switched off, the ping is silent, with no sound, vibration, flash or alert. Pings sent to AirPods don't count (#112).
- **Call triggers**: Incoming Call, Call Started and Call Ended, for Phone, FaceTime and other calling apps. They follow the phone as a whole, so a call relayed from another device on the account still fires each one once (#113).
- **Battery Level trigger**: fires once when the battery drops to, or rises to, a chosen level from 1 to 100% (#114).
- **Focus triggers**: run when a chosen Focus, or any Focus, turns on or off, including switches straight from one Focus to another (#115).
- **Copy and paste actions**: Select Actions in a trigger's ••• menu highlights actions to copy or delete together, and Paste adds them to any trigger. An If block brings its whole block along, and the clipboard survives closing the app (#116).
- **Loops and waits**: Repeat runs a block up to 1,000 times, Repeat While repeats while a condition holds, Exit Repeat leaves the loop, and Wait Until waits for a condition with a time limit (60 seconds unless set, up to a day) and then carries on either way. Blocks nest with If blocks in either order, `{round}` inside a loop becomes the round number, and each round takes at least 0.1 seconds so a loop with no delay cannot lock up SpringBoard. Adding a loop switches the trigger to Restart when triggered again, and deleting a block with actions asks whether to keep or delete them (#104).
- **Running page and Run History**: Settings > Diagnostics > Running lists the triggers running now with the step, loop round and length, plus Stop for each run or Stop All, and tapping a run opens its actions read-only with the current action highlighted. Run History in a trigger's ••• menu and Recent on the Running page keep each run's time, length and result, replay the actions as they were, and show what happened at each If, loop and Wait Until. Keep sets 0, 5, 10, 25 or 50 runs per trigger (10 by default), and the Web UI has the same Running sheet with Stop and recent runs (#104).
- **Web UI light mode**: the Web UI now follows the system appearance. Every surface, card, dialog, log viewer and control has a light palette driven by `prefers-color-scheme`, and the dark theme is unchanged.
- **Toasts on the lock screen**: toasts now show over the lit lock screen instead of behind it. With the screen off they wait and show one after another on the next wake (up to three, dropped after 30 minutes), or turn the screen on right away with the new Advanced Settings > Banners > Wake Screen switch, off by default, while the phone stays locked (#117).
- **Only Unlock Out of Pocket**: Settings > Advanced Settings > Options (and the Web UI's Advanced panel) has an off-by-default toggle that makes Unlock Device, `rc unlock` and lock toggle skip unlocking while the proximity sensor is covered, such as in a pocket. The check turns the sensor on briefly and blocks if it cannot confirm the phone is clear.
- **Variables**: the Set Variable action saves a value, changes it with math or an RC command, or keeps it for one run only. `{name}` in action text becomes its value, a Variable condition compares it, and Settings > Advanced Settings > Variables lists saved values. The number, time, command and Toast editors have a + menu to insert one (#108).
- **Two-finger slides**: the bottom bar and the status bar now recognize a two-finger slide up or slide down as their own triggers (`trigger_bottom_two_finger_swipe_up` and `trigger_statusbar_two_finger_swipe_down`), with distance-based firing, a widened landing zone, Control Center suppression mid-gesture, and a Lock Scrolling During Gestures toggle (off by default) that keeps lists still while gesturing.
- **SSH host editor**: adding or editing a host now opens a proper Settings-style screen (Server details plus a Password / Private Key picker) instead of a cramped popup. The password field is masked with a show/hide eye button and never displays the saved password: leave it blank to keep the current one.
- **SSH command editor**: creating or editing an `ssh-run` action now shows a host picker plus a full command editor, instead of a one-line popup with the raw `ssh-run <id> ...` string.
- **API token gating for `/api/command`**: `root`, `sudo`, `exec`, and TestKit test runs require an API token when called from the network. Unauthenticated callers from the local network receive a 403 Forbidden response for privileged actions, while safe commands (`lock`, `unlock`, `volume`, `media`, etc.) remain accessible. Local IPC calls over `/var/mobile/Documents/rc.sock` bypass auth. Tokens can be provided via HTTP headers (`Authorization: Bearer <TOKEN>` or `X-API-Key: <TOKEN>`), query parameters (`?token=<TOKEN>` or `?key=<TOKEN>`), or a JSON body. Settings > Web UI > Access generates and copies tokens, `rc webui token` does the same from the CLI, and the Web UI dashboard prompts for a token and caches it in localStorage.
- **Run Action in the action menu**: the long-press action menu has a "Run Action" option at the top that runs just the highlighted action via `RCServerClient executeCommand:`, matching the Web UI's "Run Action Now". It is hidden for non-executable If/Else structural rows.
- **Per-trigger toast toggle**: the trigger options menu (`...`) has a Toast Notifications toggle in both the iOS app and the Web UI, on by default. Unchecked, all HUD toasts, action banners and integration notifications from that trigger's actions are suppressed.
- **Per-trigger haptics toggle**: the trigger actions menu (`...`) has a Haptic Feedback toggle in both the iOS app and the Web UI, with sensible defaults (tactile buttons, screen gestures and NFC tags enabled; background event and app triggers disabled) and opt-in vibration on event triggers.
- **Auto-Lock (Display Sleep)**: renamed Auto-Lock to "Auto-Lock (Display Sleep)" with search keywords (`display`, `sleep`, `timeout`, `time off`, `screen`), added "Never (Off)" to the duration selector, and added `rc display sleep [duration]` and `rc display time off`.

### Changed
- **Stop Trigger picks from a list**: adding or editing a Stop Trigger action now opens a list styled like the Triggers screen, with each trigger's icon, the same sections and order, a search field, and the current trigger ticked, instead of one long action sheet (#106).
- **Action reordering rebuilt**: the action list now uses its own drag, with a floating copy of the row or whole block, a landing line indented to the depth it will sit at, edge scrolling, and only drop points that keep blocks whole. This fixes the empty dragged row on iOS 14, the missing drag handles, and the drop position depending on where the finger was on the row (#104).

### Security
- **Hardened `ssh-run`**: the remote command, user@host and key path are now POSIX single-quoted, so `$(...)` and backticks are evaluated only on the remote host and never on the phone. Passwords are passed through `sshpass -e` (the `SSHPASS` environment variable) instead of `-p`, so they no longer appear in `ps`. Host and username starting with `-` or containing spaces are rejected to block ssh option injection.
- **Single-quoted SSH action variables**: variable replacements in `ssh-run` commands are now safely POSIX single-quoted alongside shell actions, preventing command injection on remote targets when expanding dynamic trigger variables.
- **`rc-root` caller check**: the setuid helper now runs shell commands and touch injection only when its parent process is SpringBoard (where RemoteCommand spawns it). Other apps, tweaks, or scripts running as `mobile` that call `rc-root <command>` directly are refused instead of getting root. Root actions, `rc -r`, and touch injection (`rc-root iohid …`) work as before. Settings > Advanced Settings > Security > Allow Direct Root Helper Calls switches the check off for scripts, terminals and other tools; it is off by default. Note: the toggle lives in the shared config file, so treat it as convenience, not a boundary against other local mobile processes.
- **Test Kit unlocks only from the phone**: `POST /api/testkit/unlock` now refuses requests from the network, so someone on the same Wi-Fi can no longer unlock the phone while a Test Kit passcode is set; `rc-client "testkit unlock"` on the phone still works. The passcode also survives a respring (still forgotten after 30 minutes, a failed unlock, or a restart) and is kept in the device-only Keychain (#124).
- **Privileged trigger gating**: triggers containing privileged actions (`root`, `sudo`, `exec`, or TestKit actions) invoked via `/api/trigger/<key>` now require an API token when called from the network, preventing unauthenticated remote execution of sensitive actions via pre-configured triggers.
- **Secret masking in config API**: `GET /api/config` masks `webUIApiToken`, `haToken`, `mqttPassword`, and SSH host passwords as `••••••••` for unauthenticated remote callers. `POST /api/config` requires a valid API token when configured, and preserves masked credentials so existing secrets are not overwritten on save.
- **Origin-based CORS validation**: cross-origin requests from public websites to the Web UI API are rejected with 403 Forbidden. Permitted origins are restricted to localhost, loopback addresses (`127.0.0.1`, `::1`), `.local` mDNS domains, and RFC 1918 private IPv4 subnets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`).
- **Configuration file permissions**: `save_trigger_config()` now creates and updates `/var/mobile/Documents/rc_triggers.plist` with `0600` permissions (read/write by owner only), preventing unprivileged local mobile processes from inspecting stored tokens and secrets.

### Fixed
- **Center Bottom Swipe Up blocked Control Center**: with only the center zone set up, swiping up from the bottom-right corner no longer opens Control Center because the touch was counted as a bottom gesture for every zone. A touch now counts only when its own zone has actions.
- **SSH banner toggle never fired**: ticking SSH in Settings > Banners saved the picker's internal id as the match pattern, so no real `ssh-run` command could match it. It now matches the `ssh-run ` prefix, so enabled SSH actions banner like everything else (re-tick SSH once to pick up the fix).
- **SSH action editor stranded on Save**: creating an SSH action via + left you on the picker instead of returning to the actions list like other editors. Save now dismisses both and lands back on the actions sequence.
- **Top-button Touch ID triggers died after lock**: on Touch ID power-button devices (iPad mini 6, iPad Air) the sensor sleeps with the screen, so triggers only worked while Settings was open. The tweak now holds a finger-detection assertion so the sensor stays awake (#99).
- **Terminal command hangs while waiting for a response**: `rc wifi off` (and toggle-to-off) now returns `WiFi Disabled` immediately and performs the actual shutoff 0.5s later, so a remote call over WiFi SSH gets its reply before the transport drops; redundant `wifi on`/`off` calls short-circuit with `Already ON/OFF` without touching the radio. Remote `rc` ssh also has a dead-connection bound so killing WiFi mid-session can't hang automations.
- **Lock tweaks only locked once per respring**: DoubleTapToLock, GetDown and similar tweaks that lock the phone in software stopped working after the first lock while a multi-click Power trigger was set up. Presses the hardware listener has not seen now go straight to iOS instead of being held back as a possible multi-click (#119).
- **Run strip and banner narrower than the action cards**: the green run strip and the "If triggered again while running" banner inset their margins twice and ended up 20pt narrower per side, and long step names were tail-truncated. They now share the cards' edges, and the step name wraps with the header growing as needed (#125).
- **Action list fixes**: a second tap while the action list was closing no longer adds the action twice, and reused rows no longer keep another row's font, such as a Terminal Command's monospace, after scrolling or pasting (#104).
- **Trigger options retrigger mode presentation**: Present "When Triggered Again" as a clean row with current mode subtitle in the trigger options menu (`...`) that opens a native action sheet dropdown on tap, eliminating iOS nested submenu bleed-through.
- **App pickers listed non-app bundles**: hidden system services that declare no icons, such as `AAUIViewService`, no longer appear in any select-app window. Hidden bundles that do have icons, like Apple TV Remote and Apple Media Services, are still listed.
- **Find My Sound missing from the Web UI**: the Keep Default Action toggle now appears for it, defaulting to On like the app.

### Upgrade Notes
- Root commands from scripts and terminals now need **Settings > Advanced Settings > Security > Allow Direct Root Helper Calls** turned on. Everything else works as before.
- SSH actions now send commands exactly as typed, and passwords no longer show up in the process list.

## [4.1.0] - 2026-10-31

### Added
- **Web UI access control**: Settings > General > Access limits where the Web UI can be reached from — Any Network (default, as before), Trusted Networks (only while on listed Wi-Fi networks), or This iPhone Only. The check runs per-connection before any endpoint, so it covers `/api/*` too, and the phone itself can always connect. Also `rc webui access any|networks|local` and `rc webui wifi` (#105).
- **CarPlay triggers and condition**: new CarPlay Connected / Disconnected triggers plus a CarPlay connection condition; device/media triggers flattened in the New Trigger screen, Home Button section hidden on button-less phones (#67).
- **On-device test kit**: Settings > Diagnostics > Test Kit self-tests conditions, toggles, gestures, and button presses and produces a shareable report; also fixed a SpringBoard crash when saving config from the Web UI (#68).
- **Focus modes**: new Set Focus action (on/toggle/off) and Focus If condition on iOS 15+; Do Not Disturb actions/conditions now only affect the Do Not Disturb Focus (#80).
- **Shortcuts without SpringCuts**: shortcuts run in the background and appear in the picker with no SpringCuts install required; failures and unknown names are logged, and each shortcut action can optionally Run Silently (#94).
- **Retrigger options and Stop Trigger**: each trigger has a "When Triggered Again" option (Run Alongside / Restart / Ignore) so retriggering a delayed sequence restarts or skips it, plus a new Stop Trigger action to cancel another trigger's running sequence (#95).
- **Experimental NFC mode**: opt-in mode (iPhone XS+) using iOS's own background tag reader so Apple Pay, Express Transit, and car keys keep working; new NFC Scanner pause/resume/toggle action and dedicated NFC settings section (#98).
- **Ping iPhone triggers**: Ping iPhone and Ping iPhone (Hold) triggers so tapping or holding Ping on a paired Apple Watch runs custom actions (no Watch app or Wi-Fi needed); with no actions assigned the normal ping sound/flash still plays (#100).
- **Keep Default Action**: per-trigger option so button actions run alongside stock behavior (Siri, screenshot, Wallet, App Switcher, Accessibility Shortcut). Power Double-Tap with actions now blocks Wallet unless this is on (#101).
- **Home Button (Hold) and Home + Power triggers** on Home-button iPhones; replace Siri / screenshot-and-sleep by default or run alongside with Keep Default Action (#102).
- **Button Triggers action**: pause button triggers for 15 min / 1 hour / until resumed (event triggers like NFC and schedules keep working), with a pause banner and Resume button on the Triggers screen; plus an API so other tweaks can hook button events (#103).
- **Accessibility Shortcut action**: run the Accessibility Shortcut from any trigger; fixed triple-click firing both the shortcut and Power Double-Tap, and a bound Power/Home Triple Click now takes over the shortcut from iOS (#92).
- **Lock Toggle passcode support**: added optional passcode argument to lock toggle (`lock-toggle <pin>` / `lock toggle <pin>`), enabling automatic passcode unlocking when the device is locked, with dedicated configuration dialogs in the iOS action picker, action editor, and Web UI (#99).
- **Kill Current App action**: new `kill current` command (aliases `kill front`, `kill foreground`, `kill current app`, `kill front app`) force-closes the currently focused app, available in the iOS action picker, Web UI, and `rc` shell commands (#93).
- **Web UI Settings parity with iOS**: Settings root now mirrors iOS (General / Buttons / Integrations / Advanced Settings / Backup & Diagnostics) with dedicated sub-panels for Button Timing, Integrations (HA/KM/MQTT), Advanced (Banners/NFC/Logging), and Backup & Diagnostics.
- **Web UI Advanced Settings parity with iOS**: added the missing Experimental NFC toggle, NFC With Screen Off picker (with long-window confirmation), Wrap Long Names display preference, Lock Scrolling During Gestures toggle, and Banners/NFC footers to match `RCAdvancedSettingsViewController`.
- **Deep Linking URL Scheme & CLI Navigation**: added `remotecompanion://` URL scheme support and `rc nav <panel>` CLI command to jump directly into Settings, Integrations (Home Assistant, Keyboard Maestro, MQTT), New Trigger picker, or Triggers list from Siri Shortcuts, automation scripts, or terminal.

### Changed
- **Apple Watch triggers hidden until configured**: Ping iPhone / Ping iPhone (Hold) no longer sit empty in the main list. The Apple Watch section only appears once a Watch trigger has actions, and both triggers are now addable from the + menu (Device section) with swipe-to-delete.
- **Banners screen groups enabled first**: ticked actions show in an "Enabled" section at the top, moving instantly when toggled (#89).
- **Toast dialog simplified**: Web UI Toast editor now has labeled Title / Message (optional) / Icon (optional) fields, plain-word icon presets, and a slimmer live preview pill.
- **Settings reorganization**: slim root (General, Buttons, Integrations, Advanced Settings, Backup & Diagnostics) with button timing in Buttons, NFC/Banners/Wrap Long Names/Web UI/Logging in Advanced Settings, and Export/Import/Test Kit in Backup & Diagnostics.
- **Backup & Diagnostics dissolved into Settings root**: the sub-panel is gone on iOS and Web UI. Diagnostics (Test Kit on iOS, Device Diagnostics & Health on Web) is its own section, and Backup (Export/Import Configuration) sits at the bottom of the main Settings screen.
- **iOS 14 architecture docs clarified**: Clarified that RemoteCompanion ships fat `arm64 + arm64e` binaries with native `arm64e` (ABI v2) support on A12+ devices across iOS 14+, and `arm64` for A11 and older devices. `build.sh` enforces that packaged dylibs and helper tools retain both architectures so both modern and legacy devices remain supported.

### Fixed
- **Power Long Press put device to sleep on release**: releasing the side button after a Power Long Press trigger fired iOS's native single-press handler and slept the phone on non-Face ID devices (iPhone 8 / iOS 14). Suppressed the native sleep action when Power Long Press has executed (#109).
- **Long commands cut at 1KB**: the tweak read its local socket in one 1KB read, truncating long commands. It now keeps reading while more arrives (up to 256KB); `rc` piped input is also sent in full (#107).
- **Apple Pay/Wallet with NFC scanning on**: fixed Wallet showing "Updating Cards" for up to a minute by stepping the tag scan aside while Apple Pay or Wallet is on screen (#97).
- **Toast editor preview clipped message**: the live preview pill stayed at the stale single-line row height when a message was typed, squeezing the message's bottom padding unlike the fired toast. The preview row is now re-measured when the pill height changes (40pt / 50pt).
- **Toast action editor reuse**: creating a Toast from the Web UI picker now opens the same title/message/icon dialog with live preview as editing (previously a single-field prompt that dropped subtitle/icon), and editing a Toast in the iOS action list now reopens the same 3-field editor used at creation instead of a generic single-field alert.
- **Bottom swipe-up left/right zones mirrored in landscape**: `RC_ProgressAlongEdge` returned `y/L` for LandscapeLeft and `1-y/L` for LandscapeRight, which is backwards (west is device-bottom in LandscapeLeft, device-top in LandscapeRight). Swapped so left/center/right triggers fire on the correct side in both landscape orientations; also fixes the mirrored top status-bar hold zones which share the helper.
- **Orientation central for bar/edge triggers**: top bar, bottom bar, bottom swipe-up zones, edge sides, and swipe direction now share one orientation mapping (single helpers + orientation latched at touch Began). Field logs proved touch coordinates are device-fixed portrait coords (window stays 414x736 in landscape), so landscape top/bottom zones were corrected to the device-left/device-right strips with progress along the long axis, and edge zones to short-axis thresholds; `[RCOrient]` began log also reports the resolved edge progress.
- **Landscape orientation for edge and bar triggers**: top bar, bottom bar, bottom swipe-up zones, and left/right edge swipes now rotate as one logical block using SpringBoard active orientation, with corrected landscape left/right mapping, thresholds, and swipe direction.
- **Control Center from Bottom Swipe Up triggers**: the `open control center` action no longer gets swallowed when fired from a Bottom Swipe Up zone. Intentional opens now bypass the bottom-swipe suppression window in `SBControlCenterController`, and the post-fire gesture-cancel that interfered with the programmatic open on iOS 16+ was removed (native swipe-up is still suppressed by the gesture hooks) (#57).
- **Settings footer**: RemoteCompanion version label now scrolls with Settings content (table footer) instead of floating over it.
- **Settings Web UI URL**: Open Web UI row now shows the device IP address instead of localhost.
- **Unlock Device security**: Removed hardcoded fallback PIN, redacted passcodes from command logs, hex dumps, and HTTP API responses, masked passcodes in iOS action list and edit dialogs (`RCActionsViewController`), masked passcodes in the Web UI trigger lists and action sequences (`rc_webui.html`), added secure passcode configuration with wake fallback, and prevented lockout attempts when no passcode is configured (#41).
- **Web UI Diagnostics buttons fixed**: added the missing `showConfirm` dialog (Respring/Safe Mode/Clear Log were throwing `ReferenceError`), hardened `triggerActionApi`/command fetches with status checks and failure toasts, and fixed Web UI URL Copy on plain HTTP with a textarea fallback.

## [4.0.0]

### Added
- **Button Timing Engine & Settings**:
  - New dedicated **Settings > Button Timing** menu allowing granular control of sequence and click windows.
  - Configurable timing for **Volume Sequence** (default 0.38s), **Power Clicks** (default 0.4s), **Home Clicks** (default 0.35s on Home-button devices), **Volume Hold** (default 0.35s), and **Power Hold** (default 0.5s).
  - Fast-path native passthrough: single volume button taps reach iOS immediately with zero sequence delay unless a hold or combo trigger requires suppression.
  - Multi-click power press detection on dark/sleeping screen: waking press is counted as click 1 without replaying an extra press that turns the screen back off.
  - Unclaimed Power press handling: re-sleeps the screen via SpringBoard's native sleep routine (`SBSleepWakeHardwareButtonInteraction`) on iOS 14+ rather than delaying 1.3s for synthetic replay.
  - Power Long Press on sleeping screen: holds device in sleep mode (no wake, no Siri prompt, no power-off slider) while executing the bound trigger.
- **Sound & Haptics Category**:
  - New dedicated **Sound** category in the action picker with custom icons for every action.
  - **Silent Mode**: discrete commands for `ringer silent`, `ringer ring`, and `ringer toggle`.
  - **Ringer Volume**: configurable percentage level via `ringer volume <0-100>`.
  - **Haptics Control**: switch haptics behavior between `always`, `silent-only`, `ring-only`, and `never`.
  - **Unified Noise Control (ANC)**: consolidated active noise cancellation actions (`anc on`, `anc transparency`, `anc off`).
  - Relative volume steps: fine-tuned volume adjustments using `volume up N` and `volume down N`.
- **UI & Navigation Overhaul**:
  - Dedicated **New Trigger** picker screen replacing the legacy action sheet.
  - Category navigation bar on both Triggers and Action Picker screens with auto-hide on downward scroll and reveal on upward scroll.
  - Interactive **Device Picker** modal list for quickly selecting discovered AirPlay and Bluetooth audio routes.
  - Configurable action banners (**Settings > Banners**): customize which actions display banner alerts and optionally mute default notifications.
  - Performance Logging setting (**Settings > Logging**): choose between `Off`, `Minimal`, and `Full` verbosity for faster event dispatch.
- **Expanded Automation & Conditions**:
  - 13 new If Conditions including Auto-Lock timeout state, Haptics mode, Silent/Ring vibration states, and more.
  - **Auto-Lock** system action and condition support (`autolock toggle`, `never`, `30s`, `1m`, etc.).
  - Bottom Bar Swipe Left/Right gesture support on bezel-less Face ID devices.
- App Exit trigger: fires when a chosen app is switched away from (the inverse of App Launch).
- App Launch and App Exit triggers can cover several apps: tick as many as needed in the app picker and one trigger runs its actions for any of them.
- Audio Output triggers fire when an AirPlay, Bluetooth, or iPhone output device is set or unset.
- Auto-Lock action and condition support.
- Configurable banners for action triggers.
- Smaller relative volume steps with `volume up N` and `volume down N`.

### Fixed
- **iOS 15+ & 17 Compatibility & Shortcuts**:
  - Fixed Power and Volume hardware button hooks and synthetic HID event dispatch.
  - Resolved Camera Shutter action crashing the native Camera app on iOS 17.
  - Fixed Camera zoom levels, Time-Lapse mode selection, and flashlight state for video actions.
  - Fixed Siri activation, App Switcher toggle, and Ringer Switch triggers on iOS 17.
  - Fixed Low Power Mode toggle commands on iOS 15+.
  - Shortcuts now run reliably on iOS 17 without silent loss when `siriactionsd` stops, removing the dependency on SpringCuts (#78).
- **Hardware Button & Gesture Reliability**:
  - Resolved race condition where two rapid Power presses dropped the second event as a phantom press.
  - Fast Home multi-clicks are now counted accurately so three or four rapid presses fire Double, Triple, or Quadruple clicks consistently (#73).
  - Home Double Click replaces the native App Switcher, and Triple or Quadruple clicks no longer open the App Switcher or send the user home (#74).
  - Power + Volume Up/Down triggers now fire on the Lock Screen on iOS 14 instead of putting the device to sleep (#71).
  - Edge swipe gestures continue working properly after being toggled off and back on without requiring a respring (#66).
  - Bottom Swipe Up gesture zones no longer block Lock Screen interactions (Face ID unlock or Control Center pull-down) (#72).
  - Moved foreground app identification off SpringBoard's main thread with a 25ms timeout to prevent button event lag during device wake.
  - Fixed Volume Both Press firing twice on overlapping button presses.
  - Fixed screenshot combo (`Volume Up + Power` and `Home + Power`) sleeping the device after capturing.
- **System States & Conditions**:
  - Pulling down Notification Center no longer falsely triggers Device Locked/Unlocked events, and the Locked condition no longer evaluates as `Locked` while CoverSheet is pulled down (#75).
  - Fixed Media Player condition reading `Stopped` properly when no media is playing.
  - Corrected `End If` conditional block nesting and parsing.
- **UI & Layout**:
  - Fixed Trigger cards not updating width dynamically when rotating screen orientation (#76).
  - Fixed missing checkmark indicator for Bluetooth "Connected to Device" trigger state (#77).
- **Web UI & Performance**:
  - Fixed empty Web UI app picker by adding dedicated `/api/apps` endpoint serving installed application names and bundle IDs (#88).
  - Optimized config lookup on fresh installs by throttling app folder searches and suppressing repetitive "No trigger config found" log spam (#79).


## [3.7.0] - 2026-10-01

### Added
- Screen recording controls.
- Snapper 2 and Snapper 3 actions.
- Three bottom-edge swipe-up triggers.
- Volume button sequence triggers.
- AudioStream auto-connect.

### Fixed
- **iOS 15+ & 17 Compatibility & Shortcuts**:
  - Fixed Power and Volume hardware button hooks and synthetic HID event dispatch.
  - Resolved Camera Shutter action crashing the native Camera app on iOS 17.
  - Fixed Camera zoom levels, Time-Lapse mode selection, and flashlight state for video actions.
  - Fixed Siri activation, App Switcher toggle, and Ringer Switch triggers on iOS 17.
  - Fixed Low Power Mode toggle commands on iOS 15+.
  - Shortcuts now run reliably on iOS 17 without silent loss when `siriactionsd` stops, removing the dependency on SpringCuts (#78).
- **Hardware Button & Gesture Reliability**:
  - Resolved race condition where two rapid Power presses dropped the second event as a phantom press.
  - Fast Home multi-clicks are now counted accurately so three or four rapid presses fire Double, Triple, or Quadruple clicks consistently (#73).
  - Home Double Click replaces the native App Switcher, and Triple or Quadruple clicks no longer open the App Switcher or send the user home (#74).
  - Power + Volume Up/Down triggers now fire on the Lock Screen on iOS 14 instead of putting the device to sleep (#71).
  - Edge swipe gestures continue working properly after being toggled off and back on without requiring a respring (#66).
  - Bottom Swipe Up gesture zones no longer block Lock Screen interactions (Face ID unlock or Control Center pull-down) (#72).
  - Moved foreground app identification off SpringBoard's main thread with a 25ms timeout to prevent button event lag during device wake.
  - Fixed Volume Both Press firing twice on overlapping button presses.
  - Fixed screenshot combo (`Volume Up + Power` and `Home + Power`) sleeping the device after capturing.
- **System States & Conditions**:
  - Pulling down Notification Center no longer falsely triggers Device Locked/Unlocked events, and the Locked condition no longer evaluates as `Locked` while CoverSheet is pulled down (#75).
  - Fixed Media Player condition reading `Stopped` properly when no media is playing.
  - Corrected `End If` conditional block nesting and parsing.
- **UI & Layout**:
  - Fixed Trigger cards not updating width dynamically when rotating screen orientation (#76).
  - Fixed missing checkmark indicator for Bluetooth "Connected to Device" trigger state (#77).
- **Web UI & Performance**:
  - Fixed empty Web UI app picker by adding dedicated `/api/apps` endpoint serving installed application names and bundle IDs (#88).
  - Optimized config lookup on fresh installs by throttling app folder searches and suppressing repetitive "No trigger config found" log spam (#79).

- **iOS 17 Compatibility & Shortcuts**:
  - Fixed Power and Volume hardware button hooks and synthetic HID event dispatch.
  - Resolved Camera Shutter action crashing the native Camera app on iOS 17.
  - Fixed Camera zoom levels, Time-Lapse mode selection, and flashlight state for video actions.
  - Fixed Siri activation, App Switcher toggle, and Ringer Switch triggers on iOS 17.
  - Fixed Low Power Mode toggle commands on iOS 15+.
  - Shortcuts now run reliably on iOS 17 without silent loss when `siriactionsd` stops, removing the dependency on SpringCuts (#78).
- **Hardware Button & Gesture Reliability**:
  - Resolved race condition where two rapid Power presses dropped the second event as a phantom press.
  - Fast Home multi-clicks are now counted accurately so three or four rapid presses fire Double, Triple, or Quadruple clicks consistently (#73).
  - Home Double Click replaces the native App Switcher, and Triple or Quadruple clicks no longer open the App Switcher or send the user home (#74).
  - Power + Volume Up/Down triggers now fire on the Lock Screen on iOS 14 instead of putting the device to sleep (#71).
  - Edge swipe gestures continue working properly after being toggled off and back on without requiring a respring (#66).
  - Bottom Swipe Up gesture zones no longer block Lock Screen interactions (Face ID unlock or Control Center pull-down) (#72).
  - Moved foreground app identification off SpringBoard's main thread with a 25ms timeout to prevent button event lag during device wake.
  - Fixed Volume Both Press firing twice on overlapping button presses.
  - Fixed screenshot combo (`Volume Up + Power` and `Home + Power`) sleeping the device after capturing.
- **System States & Conditions**:
  - Pulling down Notification Center no longer falsely triggers Device Locked/Unlocked events, and the Locked condition no longer evaluates as `Locked` while CoverSheet is pulled down (#75).
  - Fixed Media Player condition reading `Stopped` properly when no media is playing.
  - Corrected `End If` conditional block nesting and parsing.
- **UI & Layout**:
  - Fixed Trigger cards not updating width dynamically when rotating screen orientation (#76).
  - Fixed missing checkmark indicator for Bluetooth "Connected to Device" trigger state (#77).
- **Web UI & Performance**:
  - Fixed empty Web UI app picker by adding dedicated `/api/apps` endpoint serving installed application names and bundle IDs (#88).
  - Optimized config lookup on fresh installs by throttling app folder searches and suppressing repetitive "No trigger config found" log spam (#79).


## [3.6.4] - 2026-09-10

### Added
- **Sequential Volume Button Triggers (#35)**:
  - Added Activator-style one-handed pocket gestures: **Volume Up then Down** (`volume_up_then_down`) and **Volume Down then Up** (`volume_down_then_up`).
  - Integrated sequence detection window (380ms) in SpringBoard's `SBVolumeHardwareButtonActions`.
  - Intelligently suppresses volume changes and triggers haptic feedback when the sequence is completed, while seamlessly replaying normal volume step adjustments if the second button is not pressed.
  - Multi-tap volume adjustments immediately cancel pending sequence windows to ensure fast, continuous volume stepping with zero dropped presses or responsiveness degradation.
  - Added configuration support, display names, and `arrow.up.and.down.circle.fill` SF Symbol mapping across the iOS Companion App (`Volume Buttons` section) and Web UI.
- **Dedicated Screen Recording Action**:
  - Added native SpringBoard ReplayKit integration via `rc screenrecord [toggle|start|stop|status]`.
  - Added **Screen Recording** to the Companion App action picker under System controls with interactive toggle cycle support (`RCConfigManager`).
  - Added action picker builder item, styling, and icon mappings (`record_circle_fill` / `stop_circle_fill`) in Web UI.
- **Dedicated Snapper Integration**:
  - Added dedicated Snapper actions (`rc snapper [open|freeze|instant|close|last|history]`) separate from the standard screenshot action.
  - Directly triggers Snapper 2 and Snapper 3 overlay functions via system Distributed Notification Center and Darwin notifications (`com.jontelang.snapper3.force.open`, `forcefreeze.open`, `forceinstant.open`, `close.all`, `closecrop`, `openlast`, `history`) on SpringBoard's main queue.
  - Added strict installation detection filtering (ignoring stale leftover preferences plists) so Snapper only shows in the action picker when actively installed, reported dynamically via `/api/capabilities` in Web UI and verified on disk in iOS Companion App.
- **3-Zone Bottom Screen Swipe-Up Gestures**:
  - Added 3 distinct horizontal zones for swipe-up gestures along the bottom screen edge: **Bottom Swipe Up (Left)** (`trigger_bottom_swipe_up_left`), **Bottom Swipe Up (Center)** (`trigger_bottom_swipe_up_center`), and **Bottom Swipe Up (Right)** (`trigger_bottom_swipe_up_right`).
  - Integrated into `%hook UIApplication sendEvent:` with orientation awareness, responsive in-flight trigger execution upon reaching upward vertical displacement threshold, and haptic feedback.
  - Fully backwards-compatible with existing horizontal bottom bar swipes (`trigger_bottombar_swipe_left`, `trigger_bottombar_swipe_right`).
  - Configurable across iOS Companion App (`Bottom Bar Gestures` section) and Web UI with custom icon and title mappings.

## [3.6.3] - 2026-09-03

### Fixed
- **Location Services Action Editor**: Added `location` to `toggleInfoForCommand:` so Location Services actions in action sequences can be tapped to interactively cycle or select between **On**, **Off**, and **Toggle**.

## [3.6.2] - 2026-09-03

### Added
- **Location Services in iOS Companion App**:
  - Added **Location Services** (`location toggle`) directly to the **Connectivity** actions list in the action picker (`RCActionPickerViewController`).
  - Added full display name mappings and SF Symbol icon definitions for `location on`, `location off`, `location toggle`, and `location status` (`RCConfigManager`).
  - Added **Location Services** condition target (`ON` / `OFF`) to the `If Condition...` picker (`RCActionsViewController`).

## [3.6.1] - 2026-09-03

### Added
- **Native MQTT 3.1.1 Integration (Actions & Inbound Triggers)**: Complete native MQTT 3.1.1 implementation across the entire RemoteCompanion stack with zero third-party dependencies and near-zero battery consumption.
  - **Publish Actions**: Trigger MQTT publish events from any hardware button, physical gesture, or automation sequence with customizable topics and text/JSON payloads.
  - **Inbound Subscription Triggers (`RCMQTTTriggerViewController`)**: Added **MQTT Topic** to the `+` (New Trigger) menu to subscribe to broker topics (with optional payload matching) and trigger local iOS actions (alarms, haptics, flashlight, TTS, app launching, etc.) when MQTT messages arrive.
  - **Background SpringBoard Listener**: Embedded lightweight TCP client with auto-reconnect and 60s keep-alive pings that only runs when active MQTT triggers exist.
  - **CLI & Web UI**: Added `rc mqtt pub <topic> [payload]`, `/api/mqtt/test`, and `/api/mqtt/publish` endpoints with full Web UI sequence builder and trigger support.
- **Nested Integrations Hub Architecture**:
  - Refactored Settings with a dedicated **Integrations** disclosure menu (`RCIntegrationsViewController`) cleanly organizing external services into modular sub-menus.
  - Dedicated sub-screens for **Home Assistant** (`RCHASettingsViewController`), **Keyboard Maestro** (`RCKMSettingsViewController`), and **MQTT** (`RCMQTTSettingsViewController`).
- **Visual Keyboard Maestro Macro Selector & Discovery**: Added visual macro selector across Web UI and native iOS companion app (`RCKMMacroPickerViewController`).
  - Automatically fetches and parses all macros grouped by category from `/authenticated.html`.
  - Supports live search across macro names, groups, and UUIDs.
  - Background automatic macro name-to-UUID resolution with dual-tier fallback (`/authenticatedaction.html` & `/action.html`) ensuring seamless execution even for private/protected macros.
  - Tap / long-press parameter management: directly configure, update, or remove `%TriggerValue%` parameter values on any KM action within action sequences.
  - Restored dedicated `command` SF symbol toast HUD notifications and exact case-sensitive macro title preservation.
- **Time of Day Condition Target (`time_between`)**: Added native conditional time evaluation (`If Time is Between ...` / `Else If Time is Between ...`) allowing automation sequences to branch based on the current time of day.
  - **Web UI & iOS App**: Configurable time range selector supporting 12-hour AM/PM and 24-hour time ranges, live preview hints, and overnight ranges crossing midnight (e.g. `22:00` to `06:00`).
  - **Backend**: Optimized `rc_is_current_time_in_range` evaluator handling all standard time formats in live action sequence executions.
- **Lock Screen Camera Launch Trigger**: Added inter-process notification bridging between `com.apple.camera`'s `CAMViewfinderViewController` and `SpringBoard` so that `app_launch_com.apple.camera` triggers execute reliably even when the camera is opened directly from the Lock Screen / CoverSheet while the device is locked.
- **Disable/Enable Actions**: Added the ability to disable and enable individual actions within action sequences without deleting them.
  - **iOS App**: Long-press any action to select **Disable Action** / **Enable Action**; disabled actions are automatically dimmed/greyed out.
  - **Web UI**: Right-click (or touch-and-hold) any action in the sequence builder to toggle disable/enable state.
  - **Execution Engine**: `rc_execute_action_sequence` automatically skips disabled actions in live and simulation modes.
- **Location Services Toggle (GPS)**: Added native Location Services toggle and status queries across CLI (`rc location on|off|toggle|status`), Web UI (Action Picker, Quick Toggles, and Conditional Evaluator), Lua scripting (`setLocationServices(bool)` / `getLocationServices()`), and hardware/Bluetooth trigger sequences (e.g. automatically enable Location Services when connected to a vehicle Bluetooth device).
- **Safe Mode**: Added native Safe Mode support across the CLI (`rc safemode`), Web UI (Action Picker & Quick Maintenance panel in System Info), and native iOS Companion App (Action Picker & Config Manager). Safely restarts SpringBoard into Safe Mode with tweaks disabled using Substrate/ElleKit exception triggering and marker flags.
- **Home Assistant Entity Picker**: Integrated full-screen entity browser in the iOS app with live states, domain icons, search, quick action sheets (Toggle, Turn On, Turn Off), and manual command fallback.

### Changed
- **Streamlined Camera Action Picker**: Simplified camera options in the iOS and Web UI action pickers to clean, minimal **Open Camera** and **Open Video Camera** items while preserving specialized parameter variations when manually configured or imported.
- **Wider Web UI Modals**: Increased the modal dialog widths for App Launch and Time Range trigger selectors for better readability on desktop and mobile browsers.

### Fixed
- **Power Button Lock & Proximity Sensor Suppression (#34)**:
  - Resolved an issue where pressing the power button to lock the screen was unresponsive or delayed while the proximity sensor was covered (e.g. holding or handling the top of the device).
  - Multi-click power button suppression logic now only intercepts events when multi-click power triggers (`power_double_tap`, `power_triple_click`, `power_quadruple_click`) are actively enabled in configuration, restoring immediate native `%orig` handling when unassigned.
  - Power long press handling now checks whether `power_long_press` is actively enabled before intercepting `performLongPressActions`, allowing standard lock and system behavior to proceed without latency or sensor blocking.

## [3.5.2] - 2026-08-29

### Fixed
- **Siri Shortcuts Execution & Discovery**:
  - Modernized native shortcut invocation using `VoiceShortcutClient` (`WFSiriWorkflowRunRequest` / `WFSiriWorkflowRunnerClient`) and `WorkflowKit` (`WFWorkflowRunnerClient`).
  - Added robust fallback via `springcuts` `posix_spawn` with a background watchdog process to prevent hanging.
  - Added URL scheme fallback (`shortcuts://run-shortcut?name=...`) for background execution on iOS 15+.
  - Added `popen` fallback to the companion app shortcut picker to guarantee shortcut discovery even when `NSTask` fails.
- **SpringBoard Respring Fallback**:
  - Improved respring reliability across jailbreaks by chaining `sbreload` -> `_relaunchSpringBoardNow` -> `FBSystemService` -> `exit(0)`.
- **Volume Button Dual-Press & Combo Detection**:
  - Fixed race conditions and accidental single-press execution when performing simultaneous Volume Up + Volume Down or Power + Volume button combos.
- **Web UI & Server Reliability**:
  - Set `FD_CLOEXEC` on server listening sockets and child process spawns to prevent socket leaks and port locking.
  - Added IPv6/IPv4 dual-stack binding with quick 8080 retry and graceful sequential port fallback.

## [3.5.1] - 2026-08-13

### Fixed
- **Dynamic Config Path Resolution (`find_config_path`)**: Fixed trigger resolution in rootless, NathanLR, and Sileo environments by checking file modification timestamps (`NSFileModificationDate`) across shared (`/var/mobile/Documents/`), rootless (`/var/jb/var/mobile/Documents/`), and app container (`/var/mobile/Containers/Data/Application/*/Documents/`) paths to ensure trigger updates saved in the companion app are immediately picked up by SpringBoard.
- **Notification Trigger Observer**: Moved `%hook BBServer` before `%ctor` so that `%init(_ungrouped)` correctly registers notification hooks.
- **Immediate Tweak Observer Registration**: Config loading and Darwin notification listeners now initialize synchronously on tweak load instead of waiting on a delayed 5-second timer.

## [3.5.0] - 2026-08-09

### Added
- **SneakyCam Integration**: Added native `sneakycam photo` and `sneakycam video` triggers across CLI, iOS Companion App, and Web UI using system Darwin notifications (`com.spark.SneakyCam.takephoto` and `com.spark.SneakyCam.startstopvideo`).
- **Web UI Modal Action Editors**: Dedicated popup modals for editing **Terminal Actions** (with root privilege toggle) and **HUD Toast Notifications** (with title/subtitle/icon inputs, SF Symbol preset chips, and a live HUD toast preview).
- **Web UI Action Copy & Paste**: Added **Copy** and **Paste** options to the right-click context menu for action sequence items.
- **Web UI Live System Log Viewer**: Real-time streaming log viewer console panel in the Web UI backed by a new `/api/logs` HTTP endpoint in the tweak web server.
- **Power Event Triggers**:
  - Added **Power Connected** (`trigger_power_connect`) and **Power Disconnected** (`trigger_power_disconnect`) system event triggers.
  - Automatically listens to Cocoa Touch `UIDeviceBatteryStateDidChangeNotification`, `UIDeviceBatteryLevelDidChangeNotification`, Darwin power source notifications (`com.apple.system.powersources.*`), and hooks `SBUIController` in SpringBoard for instant trigger execution when connecting or disconnecting AC power/chargers.
  - Fully integrated across the native iOS Companion App (System Event picker, Device State table section, and trigger list icons) and Web UI (`rc_webui.html`).

## [3.5.0] - 2026-07-09

### Added
- **Shuffle All Songs Action**: Added a first-class `shuffleall` action to trigger the AudioStream/AudioReceiver app to shuffle the entire device music library and start playback.
- **AudioStream/AudioReceiver Integration**:
  - Implemented the Darwin notification listener for `com.saihgupr.audiostream.shuffleall` inside `AudioPlayerService`.
  - Added native iOS Companion App action picker and config manager support for the "Shuffle All Songs" command.
  - Exposed **Queue Current Album**, **Queue Artist (Shuffle)**, and **Shuffle All Songs** actions directly inside the Web UI dashboard (`rc_webui.html`).

## [3.4.0] - 2026-06-22

### Added
- **Cellular Data Control**: Added native toggle and status query support for Cellular Data (`cellular on`, `cellular off`, `cellular toggle`, `cellular status`) via the CLI, Web UI, and Action conditions, utilizing private CoreTelephony server connection APIs.
- **Dynamic Web UI Port Selection**: The Web UI server now scans ports sequentially starting from `8080` (up to `8099`) and binds to the first available port. This prevents binding failures and conflicts when other web servers (such as AutoTouch) are already listening on port `8080`.
- **HUD Toast Action Picker Option**: Exposed the HUD Toast action (`toast`) under the "Scripting & Logic" section in both the native iOS Companion App and Web UI action pickers. The companion app now offers a native 3-field input controller (Title, Subtitle, SF Symbol name), and both list views render the action with the text bubble icon and highlight parameters dynamically.
- **Action Sequence Play Button**: Added a play icon in the iOS companion app's action sequence view to instantly run/simulate the current sequence. The play icon is positioned to the left of the edit settings button.
- **Proximity Sensor & Pocket Detection**:
  - Implemented the `proximity` CLI command (`rc proximity`, `rc proximity on`, `rc proximity off`, `rc proximity debug`).
  - Added a first-class **Proximity Sensor** condition to the iOS companion app's visual rule builder, supporting evaluations for `Near` and `Far`.
  - Added support for `proximity`, `pocket`, and `device_in_pocket` condition keys in action sequence IF/ELSE blocks.
- **Forced Proximity State Override**:
  - Automatically activates the proximity sensor during the power button down hold sequence.
  - Implemented a forced state override (`g_forceProximityDetection`) to prevent SpringBoard's backlight policy or lockscreen lifecycle from turning off the sensor while the button is held, ensuring 100% consistent detection.
  - Automatically deactivates the sensor on button release to ensure zero standby battery drain.
- **Lock State Queries**:
  - Implemented the `rc is-locked` and `rc lock status` CLI commands (previously documented but missing in the SpringBoard tweak daemon), returning `locked` or `unlocked`.
- **Appearance Action**: Added `appearance dark/light/toggle` commands to control the device's Light/Dark mode via CLI, Web UI, and iOS App.
- **Status Bar Double Tap Trigger**: Added a new gesture trigger to bind actions to double-tapping the status bar.
- **AudioMix Integration**: Added first-class control actions (`audiomix`, `audiomix on`, `audiomix off`, `audiomix toggle`, `audiomix status`) to control KingPuffdaddi's AudioMix tweak settings.
- **Heads-Up Display (HUD) Toast**: Implemented a system-wide dropdown glassmorphism HUD toast notification that animates with spring physics to confirm toggling states.
- **Consolidated Toggle Actions**: Consolidated redundant toggle options (On/Off/Toggle) into single entries in the Action Picker for both the iOS app and Web UI, displaying states as interactive links that open slide-up sheets to edit them.
- **Native iOS Alert Styling in Web UI**: Redesigned the Web UI edit action dialog to mirror the native iOS `UIAlertController` style, featuring a translucent dark-mode card, centered text input field, and hairline-separated blue buttons.
- **Auto-Sync & Pull-to-Refresh**: Integrated background configuration reloading when returning to the iOS app, and implemented a manual pull-to-refresh control on the main screen.
- **Sequential Else If Conditional Blocks**: Added first-class support for sequential `Else If` (`else_if`) blocks in the execution engine, iOS App, and Web UI. Sibling conditions are evaluated sequentially if preceding branches are false.
- **Action Sequence Import/Export Sharing Enhancements**:
  - Separated action creation (direct `+` button) from action sharing/importing (moved to a new ellipsis `...` menu).
  - Added option to **Append** vs **Replace** when importing sequences on both the iOS app and the Web UI.
  - Fixed a bug to support importing full dictionary block structures (like `if` / `else_if`) rather than discarding them.
  - Enlarged the import text container in the Web UI to twice its original height and simplified clipboard confirmation messages.
  - Integrated the dropdown glassmorphism HUD toast for iOS companion app copy/paste actions to reduce notification clutter.
- **Improved UI Navigation & Settings**:
  - Fixed a bug where selecting a Front App condition dismissed the entire view stack, returning the user to the main menu.
  - Hid the non-functional settings edit icon for non-configurable triggers in the action view navigation bar.
- **Kill App Action & Picker Autocomplete Enhancements**:
  - Implemented a first-class **Kill App** action in the action sequence builders for both the native iOS App and the Web UI.
  - Resolved bundle ID names to friendly application names (e.g. "Kill YouTube") in action displays.
  - Linked applications to their real springboard icons (using `USER_APP:<bundleId>`) for both open and kill app list items.
  - Re-implemented the Web UI app selection picker with a custom, high-fidelity iOS-style autocomplete search overlay (replacing the native browser `<datalist>`) for both Open App and Kill App configurations.
  - Fixed a selection dismissal bug in the native app picker that caused duplicate action insertions.
  - Removed outdated helper text ("Swipe left on an action to delete it") from the Web UI.


## [3.3.1] - 2026-06-19

### Fixed
- **Light Mode Support**: Fixed settings and action picker views rendering with incorrect background colors in Light Mode. All view controllers now dynamically adapt to system appearance changes via `traitCollectionDidChange:`.

## [3.3.0] - 2026-06-13

### Added
- **Previous App**: Added the `rc previous app` (or `rc last app`) command to instantly return to the previously active application. Accessible via the Web UI and iOS App Action Pickers.
- **Device Lock/Unlock Triggers**: Added new automation triggers for device lock and unlock events, allowing for complex routines when the device state changes.
- **Media Playback Triggers**: Added new automation triggers for media events (`Media Playing`, `Media Paused`, and `Media Track Changed`) utilizing private `MediaRemote` observers.
- **Web UI & Companion App Integration**: Integrated the new media triggers with custom iconography and control flows across both the iOS companion app and the web configuration interface.

## [3.2.0] - 2026-05-16

### Added
- **Roothide Support**: Native compatibility for the Roothide bootstrap. The build system has been unified to support rootless, rootful, and roothide environments in a single project.
- **AirPlay Connect (Web UI)**: Added a dedicated 'Connect AirPlay' action to the browser interface with automatic device discovery.
- **Right-Click Context Menus**: Added intuitive right-click options for action items in the Web UI for faster management.

### Improved
- **Web UI Layout**: Refined spacing, footer placement, and mobile responsiveness for the browser interface.
- **Icon Refresh**: Updated branding and iconography across the application and tweak.
- **CLI Robustness**: Improved `rc url` and `rc unlock` commands with better error handling and state detection.

## [3.1.0] - 2026-05-12

### Improved
- **Stable Unlock Sequence**: Fixed a potential 10-second hang when using `rc unlock` or `rc url`. The tweak now intelligently checks the screen state and only sends a wake signal if the screen is actually off, with optimized delays for reliable passcode entry.
- **Robust URL Handling**: The `rc url` command now automatically strips surrounding quotes and prepends `http://` if a scheme is missing, making it much more resilient to user input errors.

## [3.0.1] - 2026-04-17

### Added
- **Connect AirPlay Action**: Added a functional 'Connect AirPlay' action to the Web UI.
- **AirPlay Device Discovery**: The action picker now automatically discovers and lists available AirPlay speakers and TVs from the iPhone, providing a native-like experience.

## [3.0.0] - 2026-04-14

### Added
- **Full Automation Management**: Creating, renaming, and deleting dynamic triggers is now fully supported from the browser.
- **Automations API**: Introduced structured discovery endpoints at `GET /api/triggers` and `GET /api/commands`. These return clean JSON.
- **Scheduled Triggers**: Run action sequences at specific times of the day and on specific days of the week. Perfect for daily cleanups, automated system checks, or time-based alerts.
- **Notification Triggers**: Bind actions to incoming notifications from any app. Filter by bundle ID or specific text within the notification (title/subtitle/message).
- **Flashlight Intensity Control**: The `rc flashlight` command now supports values from 1-100 for fine-tuned intensity of the device torch (e.g., `rc flashlight 50`).
- **Web UI CLI Control**: Manage the Web UI server status remotely via the new `rc webui [on|off|status]` command.
- **UI Refinement**: Removed the "Edit" button from the main Triggers view for a cleaner, favorites-focused interface.



## [2.4.0~beta1] - 2026-03-23

### Added
- **Shake Trigger**: New "Motion Gestures" section with "Shake Device" trigger support. Assign any action sequence to fire when the device is physically shaken.
- **Action Copy-Paste**: You can now long-press any action entry to copy it to a global clipboard. Once copied, long-press any row to "Paste Above" or "Paste Below", or long-press empty space to paste at the end of the sequence.
- **App Launch Trigger**: Added a new trigger type that fires when a specific application is opened. Features a built-in search-enabled app picker.
- **Conditional Actions ("Else" Branch)**: "If" actions now support an optional "Else" branch. Long-press any "If" action in the sequence list to toggle the Else branch on or off.
- **Conditional Actions ("Front Application")**: Added a new condition type to check the currently active foreground application. Integrated the native app picker for easy configuration.
- **Edit Condition**: Added a native "Edit Condition" option to the long-press menu for "If" actions, allowing you to swap conditions or values without deleting the entire block.

### Improved
- **Trigger Workflow**: Creating a new trigger (App Launch, NFC, etc.) now automatically redirects you to the action sequence configuration immediately for a faster setup process.

### Fixed
- **App Launch Reliability**: Re-engineered the launch detection hook using `SpringBoard frontDisplayDidChange:` with a micro-delay, ensuring the active app is correctly identified on modern iOS versions.
- **Action UI**: Improved readability of the action sequence list. Terminal commands and Lua scripts now show their actual code in the main label for faster identification.
- **Truncation Logic**: Switched to tail truncation for long commands, ensuring the most relevant code is visible at a glance.
- **Visual Polish**: "Else" and "End If" markers now use consistent secondary styling to clearly demarcate control flow blocks.

## [2.3.0] - 2026-03-04

### Changed
- **Conditional Actions ("If" Blocks)**: Introduced a powerful new "If" action type. Create smart sequences that only fire if certain conditions are met. Nested actions now move together perfectly when reordering.
- **NFC, WiFi & Bluetooth Triggers**: Bind actions to physical NFC tags, specific WiFi network connections, or Bluetooth device states.
- **App Blacklist System**: Managed via CLI, this system prevents triggers from firing while specific apps (like banking or camera apps) are in the foreground.
- **Refined Design**: A polished monochromatic UI with custom-tuned separators and borders.
- **Improved Action Sequences**: Redesigned the drag-and-drop logic for action chains, ensuring that "If" blocks and their nested children move together seamlessly as a single unit during reordering.

### Added
- **Network & Hardware Triggers**: Tap the "+" button to add new event-based triggers:
  - **NFC Tag**: Scan a physical NFC tag and bind actions to its unique UID.
  - **WiFi Network**: Fire actions when connecting to or disconnecting from a specific SSID.
  - **Bluetooth Device**: Fire actions when a specific Bluetooth device connects or disconnects.
- **Additional Features**: Added native **Unlock Device** and **Control Center** actions, plus a new **Orientation Status** query (Portrait/Landscape) designed for use from CLI or with the new conditional action.
- **Dynamic Trigger Interface**: The triggers list now automatically hides categories like "NFC Tags" or "WiFi Network" if they contain no configured triggers, keeping your overview focused.
- **UI "Tweaker" System**: Added a centralized design engine to live-preview color adjustments. Refined the app to use a sleek monochrome aesthetic with high-saturation gold accents (RGB 242, 195, 80) for favorite triggers.

### Fixed
- **UI Consistency**: Standardized background and separator colors across all trigger creation and picker views.
- **Shadow Clean-up**: Removed obsolete shadow logic and UI controls to prioritize a clean, flat design.
- **CLI Robustness**: Refined the `rc` script to handle rootless and rootful paths more reliably, and optimized command delivery across all jailbreak environments.
- **Networking Stability**: Fixed intermittent connection failures caused by "TCP Server" port exhaustion or conflicts.

## [2.2.5] - 2026-02-26

- Refactored project structure for better rootless and rootful compatibility.
- Isolated `rc-root` tool into its own subproject.
- Integrated the `RemoteCompanion` app as a subproject for a unified build process.
- Optimized architectures: `arm64` for app/tool, `arm64 arm64e` for tweak.

## [2.2.4] - 2026-02-25

### Fixed
- **arm64e Crash (iOS 14)**: Resolved a critical launch crash on A12+ devices running iOS 14.4.1. This was achieved by unifying architecture support across all build schemes and ensuring correct PAC signing for rootful environments.
- **Architecture Synchronization**: Real-time detection of jailbreak environment (rootless vs. rootful) in `deploy.sh` to ensure the correct binary and signing are used.
- **Native arm64e Slices**: Both rootless and rootful packages now natively include `arm64e` slices for maximum compatibility and performance.

## [2.2.3] - 2026-02-25

### Added
- Root Access Control setting (guards root commands).
### Removed
- ntfy integration for improved privacy.
### Changed
- Minor version bump.

## [2.2.2] - 2026-02-24

### Fixed
- **POSIX Compliance**: Corrected the `postinst` script to use POSIX-compliant syntax (replacing Bash arrays with string iteration). This ensures the script runs correctly on Procursus-based rootless jailbreaks (e.g., Dopamine, Palera1n) where `dpkg` uses `dash`.

## [2.2.1] - 2026-02-22

### Added
- **Shortcuts Integration Methods**: Expanded documentation for iOS Shortcuts. Added instructions for running commands via native **SSH to Localhost** (recommended for reliability) and **Powercuts** (shell).

### Fixed
- Improved `rc` CLI with automatic on-device detection (defaults to `127.0.0.1` when run on iPhone, fixing connection issues for local users).
- **Universal Root Permissions**: Fixed `rc-root` permission handling to support both **Rootful** and **Rootless** jailbreak environments in the post-install script.

## [2.2.0] - 2026-02-14

### Added
- **Root Execution Toggle**: Terminal commands now feature a native "Execute as Root" toggle directly in the editor. No more separate menu items; just toggle it on for system-level actions.
- **Trigger Favorites**: You can now mark any trigger as a "Favorite" for lightning-fast access at the top of the picker for instant access to edit or long-press to run.
- **Enhanced Status Queries**: Added a suite of new status commands to query device state without toggling. Use `rc dnd status`, `rc lpm status`, `rc wifi status`, `rc bt status`, and the restored `rc player status` command to get instant feedback.
- **CLI Root Support**: The `rc` command-line tool now supports `-r` and `--root` flags to quickly fire off root commands from your Mac (e.g., `rc -r ldrestart`).
- **New System Actions**: Added `ldrestart`, `userspace-reboot`, and `uicache` as first-class selectable actions in the app for quick system maintenance.
- **Bottom Bar Gestures**: Added new "Bottom Bar Swipe Left" and "Bottom Bar Swipe Right" triggers, allowing you to run actions by swiping horizontally along the home bar area.
- **System Vibration Control**: New `rc vibration` command to **Turn On/Off** or Toggle the system-wide "Vibrate on Silent" and "Vibrate on Ring" settings directly from the CLI or Action Picker. Added status commands for financial usage.
- **Lua Dynamic Bridge**: Lua scripts now support `dlopen` and `objc_call`, allowing for full dynamic invocation of Objective-C methods and loading of private frameworks directly from your scripts.
- **Debug Logging**: Added `rc log` to stream live logs from the device, making it easier to debug custom scripts and system actions.

### Improved
- **Always-Editable Sequences**: Removed the "Edit" button in favor of permanent reorder handles and intuitive swipe-to-delete functionality. Manage your actions faster without extra taps.
- **Modern Terminal UI**: Redesigned the terminal input screen with a "pro" console aesthetic. Features a charcoal-grey, high-contrast text area with rounded corners and monospaced typography.
- **Consolidated Actions**: Merged "Terminal Command" and "Terminal Command (Root)" into a single, intuitive entry.
- **Smart Editing**: When editing an existing terminal command, the editor now correctly remembers and displays the root toggle state.
- **Haptic Intelligence**: Haptic feedback now only fires when a trigger is actually enabled and assigned an action, eliminating phantom vibrations for unconfigured gestures (Status Bar, Bottom Bar, and Edge gestures).
- **UI Polish**: Removed placeholder text from volume and brightness inputs for a cleaner look, and reordered the Action Picker to place "Volume Up" logically above "Volume Down".

### Changed
- **Unified Action Picker**: Streamlined the action selection menu by removing redundant "Root" variants in favor of the new editor-integrated toggles.
- **Gesture Organization**: The Triggers menu now correctly separates "Bottom Bar Gestures" and "Edge Gestures" into their own dedicated sections.

## [2.1.2] - 2026-02-06

### Fixed
- **RC Tool Output**: Fixed an issue where the `rc` tool would not display the server's response (e.g., for `status` commands).
- **RC Tool Compatibility**: Removed `-4` flag from `nc` calls and prioritized bash `/dev/tcp` for wider compatibility.
- **Installation Failures**: Fixed a critical bug where the package would fail to install on rootless/Roothide jailbreaks due to an incorrect architecture and nested file paths.

## [2.1.0] - 2026-02-05

### Improved
- **Export Configuration**: Replaced the document picker with a native iOS Share Sheet. This fixes the cut-off spinning indicator and provides more flexible export options (AirDrop, Messages, etc.).
- **Action Labels**: Refined all system labels for clarity. "set-vol" is now "Set Volume", "brightness" is now "Set Brightness", and abbreviations like LPM, DND, and ANC have been expanded to their full names.
- **Label Readability**: Increased truncation limit to 40 characters for better visibility of long device and shortcut names.
- **Instant Commands**: Optimized `rc` command execution to be virtually instant (~0.25s) by fixing TCP probe timeouts that were causing unnecessary SSH fallbacks.
- **Server Stability**: Rewrote the internal server to handle multiple connections concurrently, preventing freezes/crashes when a connection hangs.
- **Port Reliability**: Moved server ports to 12340-12344 to avoid conflicts with system services like `debugserver`.

### Added
- **Action Editing**: You can now edit any existing action in your sequence just by tapping it. This re-opens the picker (for apps, shortcuts, devices) or an alert (for delay, volume, brightness) to quickly swap values.
- **Unified Device Pickers**: Implemented a consistent, discovery-based picker for both AirPlay and Bluetooth devices. The app now fetches a live list of available devices (using `airplay list` and `bluetooth list`) to ensure you're always selecting from active nearby hardware.
- **Home Button Action**: Added a new action to simulate a physical Home Button press with robust support across all device models (physical buttons and gesture-based), useful for returning home or closing apps within a sequence.
- **Modern Code Editor**: Completely redesigned the Terminal and Lua editor pages with a modernized, edge-to-edge iOS 17 style. Removed unnecessary buttons for a cleaner, more focused editing experience.
- **Refined Labels**: Simplified "Lua" and "Terminal" labels in the main panel for a cleaner look, and updated "Wait" labels to show the duration (e.g., "Wait 5s").
- **Auto-Launch on Deploy**: The `deploy.sh` script now automatically opens the RemoteCompanion app on your device after a successful install, using a more robust launch method.
- **iOS 14 & Rootful Compatibility**: Added support for iOS 14 and traditional rootful jailbreak environments. This includes dynamic path resolution for binaries like `springcuts` and `killall` (supporting both `/var/jb/usr/bin` and `/usr/bin`), SF Symbol fallbacks for older firmware, and iOS 14 specific DND fallback research.
- **iPad Experience**: Added official support for iPads with full landscape orientation support and optimized layouts.
- **Dependency-Free Client**: The `rc` command-line tool now uses native bash networking (`/dev/tcp`) instead of relying on `netcat`, ensuring higher reliability and performance on all jailbreak types.

### Fixed
- **Connectivity**: Fixed an issue where `rc lock` would execute but report failure due to a missing response from the server.


## [2.0.0] - 2026-02-02

### Fixed
- **Safe Mode Crash**: Resolved a race condition and main-thread violation when re-enabling triggers from Settings.

## [2.0.0~beta5] - 2026-01-31

### UI Overhaul (Visual Refresh)
- **Modern Header**: Updated the main navigation bar to use Large Titles with a native translucent blur effect (frosted glass), moving away from the "web-view" look.
- **Improved Readability**: Command strings (like `curl`) now use a Monospace font and are middle-truncated (e.g., `curl -X...7DB5fjv`) to keep the UI clean.
- **Visual Contrast**: Added SF Symbols (icons) to every trigger row for faster scanning.
- **Section Polish**: Refined section headers with smaller, all-caps styling and better spacing.
- **Action Sequence**: Overhauled the action list with Large Titles, subtitle-style rows for commands (showing code neatly), and a proper Edit button.
- **Action Selection**: Updated the "Add Action" screen with Large Titles, larger touch targets (60pt), and visual cues (chevrons) for actions that require input.
- **Settings**: Polished the Settings page with Large Titles, consistent headers, and a **sticky footer** for version info.
- **App Icon**: Updated with a new modern design and flattened assets to resolve system rendering artifacts.
- **NFC Scanning Toggle**: Added a toggle in Settings to enable/disable NFC scanning, preventing conflicts with Apple Pay.

## [2.0.0~beta4] - 2026-01-30

### Removed
- **Volume Combo Trigger**: Removed "Volume Up + Down" trigger due to conflicts with NFC scanning logic.
    - **Home Button (Double Tap)**: Removed this trigger to prevent conflicts with native Reachability and improve system stability. Since Double Click exists, Double Tap (Touch) was redundant and problematic.

### Added
- **Siri Activation**: Added the `button siri` command and a native "Activate Siri" action in the Action Picker. Uses a robust multi-stage activation sequence (HID + Programmatic Fallbacks) for maximum reliability on iOS 15+.
- **Power + Volume Triggers**: Added support for **Power + Volume Up** and **Power + Volume Down** combos.
- **Touch ID Triggers**: Added support for **Single Tap** and **Hold** triggers on Touch ID devices.
- **Shortcuts Picker Search**: Added a search bar to the "Select Shortcut" screen, making it easier to find specific shortcuts in your library.
- **UI Polish**: Shortcuts picker icons now match the system accent color (grey).

### Fixed
- **Touch ID Stability**: Fixed a crash related to background thread event access in the biometric handler.
- **Rootless Injection (iOS 15)**: Fixed a critical architecture mismatch in the Tweak control file (`iphoneos-arm` -> `iphoneos-arm64`) that prevented the tweak from loading on rootless jailbreaks.
- **Shortcuts Menu Regression**: Fixed an issue where selecting "Run Shortcut..." would immediately close the menu without showing the picker.
- **Search Selection Bug**: Fixed a bug where selecting an action from search results in the Action Picker would fail to correctly dismiss the view.

## [2.0.0~beta3] - 2026-01-29

### Added
- **Search in Action Picker**: Added a search bar to the Action Selection menu, allowing users to quickly find actions by name or command. 
- **UI Polish**: Reduced the header gap in the Action Selection menu for a cleaner look. 

### Fixed
- **Ringer Trigger**: Fixed an issue where ringer actions would fire on respring/reboot based on the current switch position. Actions now only fire when the state actually changes.

## [2.0.0~beta2] - 2026-01-29

### Added
- **Ringer Switch Automation**: Triggers for muting, unmuting, and toggling the ringer switch (works with hardware switch and Control Center).
- **Respring Action**: Added a native "Respring Device" action to the UI and improved the `respring` command reliability by using `killall backboardd`.

## [1.1.2] - 2026-01-30

### Fixed
- **Volume Button Responsiveness**: Improved reliability of native volume buttons when custom triggers are disabled.

## [1.1.1] - 2026-01-29

### Fixed
- **Open App Action**: Fixed "Open App" action failing by restoring the missing `uiopen` command handler in the Tweak.
- **Custom Command Repair**: Fixed "Custom Command" actions failing when using `rc <command>` by intercepting the `rc` prefix and executing it internally.

## [1.1.0] - 2026-01-29

### Added
- **Volume Combo Trigger**: Added support for **Volume Up + Down** simultaneous press.

### Fixed
- **NFC Scanning Regression**: Resolved an issue where NFC scanning would fail to start after waking the device by reverting conflicting HID listener changes in `Tweak.x`.
- **System Resource Unavailable**: Fixed error when adding tags in the App by restoring IPC callbacks to properly release NFC hardware.

## [1.0.4] - 2026-01-28

### Added
- **Home Button Triggers**: Added support for **Double Click**, **Triple Click**, and **Quadruple Click**.
- **Improved Multi-Click Detection**: Re-engineered logic to handle rapid multi-clicks reliably without interference.
- **Open App Action**: New application picker to launch any installed app directly from a trigger.
- **Native RC Commands**: Run `rc` commands directly from the terminal or the Custom Command action.
- **Connectivity Toggles**: Wi-Fi and Bluetooth toggle commands (`wifi toggle`, `bluetooth toggle`).

### Fixed
- **Apple Pay Conflict**: Fixed "System Failure" when using Apple Pay by moving logging to an asynchronous background queue, eliminating main-thread blocking.
- **UI Consistency**: Fixed missing labels and sections for new triggers in the app.

## [1.0.3] - 2026-01-22

### Added
- - Shortcuts (via Powercuts)
- **Custom Command**: You can now use `rc haptic` / `rc screenshot` / `rc siri` (or any other `rc` command) directly in the Custom Command action to open apps or trigger any system action.
- **Settings UI**: Added version label (e.g., `v1.0.3`) to the bottom of the Settings menu.
- **Improved Layout**: Refactored Settings screen to pin the version label to the bottom of the view, ensuring consistent positioning regardless of screen size.
- **UI Details**: Matched version label styling to native table view footers (font, color).

### Fixed
- **Home Button Interference**: Fixed an issue where the Double Click trigger would fire before you could complete a Triple Click. Double Click now waits briefly if Triple Click is enabled.

## [1.0.2] - 2026-01-22

### Added
- **Toggle Support**: Added `toggle` command for various system features:
  - Low Power Mode (`rc lpm toggle`)
  - Do Not Disturb (`rc dnd toggle`)
  - Orientation Lock (`rc orientation toggle`)
  - Mute (`rc mute toggle`)
- **Better SpringCuts Error Handling**: Added user-friendly notifications and UI alerts if SpringCuts is missing instead of silent failure.

### Fixed
- **UI Consistency**: Fixed missing icons for new toggle commands in the action sequence list.
- **Custom Command Flexibility**: Supported `rc` and `sudo` prefixes in custom commands, allowing commands like `rc open Music` to work directly from the app.
- **Improved Labels**: Renamed "Vol Up/Down" to "Volume Up/Down" in the main panel for better clarity.
- **Edge Gesture Interference**: Fixed issue where edge gestures would interfere with native iOS gestures (Back gesture, swipe-to-type, etc.) even when disabled.

### Changed
- Bumped version to 1.0.2.
