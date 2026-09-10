# Changelog

All notable changes to this project will be documented in this file.

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
