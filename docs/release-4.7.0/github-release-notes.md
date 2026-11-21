# RemoteCompanion v4.7.0

This release ships everything new since the last public release (v4.4.0). Version 4.5.0 was never published, so its features are included here as well.

## Highlights

**Developer Mode annotation.** Freeze a screenshot, mark it up, add a typed or dictated note, and send both over SSH to OpenCode or Antigravity. OpenCode Auto-Send queues it in the active session through the local API. Antigravity opens the project folder and pastes into Agent chat. Gated behind Settings > Advanced Settings > Developer. Scriptable as `dev-annotate`.

**Apple Watch.** Actions for Theater Mode, Silent Mode, Wake on Wrist Raise, Water Lock, Always On, and Watch Face switching by name, UUID, next, or previous. Triggers for Watch Connected, Watch Disconnected, and Watch Face Changed. Watch Only notification option leaves the iPhone dark. CLI: `watch theater|silent|wake|water|alwayson`, `watch face`, `watch status`, `notify ... --watch-only`.

**Screen reading and touch.** Copy Text on Screen (drag a rectangle), Copy All Text on Screen, Tap Text on Screen, Wait for Text, and a Text on Screen condition for If and Wait Until. New `gesture` commands drive the real touchscreen (tap, hold, swipe, drag, two-finger swipe, pinch, rotate). New `screen capture`, `screen settle`, `screen tap`, `screen wait`, `screen find`, and `screen ocr` commands, plus the `rc-ocr` helper for iOS 15.

**Control Center buttons.** Create named buttons with SF Symbol icons, each with its own action sequence. They appear in Settings > Control Center dynamically. Requires CCSupport and iOS 17 or earlier.

**Native Apple timers.** Timer action and `timer` CLI use MobileTimer.framework. Real Clock timers sync with Lock Screen, Control Center, and Apple Watch. Supports `20m`, `1h30m`, `45s`, `20:00`, pause, resume, stop, status, and `--label` on iOS 17 and later.

**New triggers.** Airplane Mode On and Off. Four physical orientation triggers driven by the accelerometer. Long Press App Icon for one or several apps. Action Sequence Edited with debounce. Set Orientation action (Portrait, Landscape Left, Landscape Right, Portrait Upside Down, Auto Rotate).

**From 4.5.0 (previously unpublished).** Add-ons system with JSON files, validation, and a Settings screen. Full backup and restore covering integrations, SSH hosts, tokens, add-ons, gestures, filters, variables, and the app blacklist (`rc export`, `rc import`). Triggers screen starts empty with everything in the + menu. First-trigger onboarding. Remote RC actions run commands on a second device over its Web UI with the same editors as local actions. `rc pull-backup` fetches the newest IAmLazy backup to the Mac. Duplicate actions including whole If and Repeat blocks.

## Changed

- New Trigger menu has one Device State section. Compact tile layout option with per-category search. Banner categories with a category bar. Action summaries show names plainly without brackets. Set Variable selection shown by icon, title, and border. Watch rows hidden without the Watch app. Clear Notifications retargeted to any or chosen apps with text filters. Tighter 25pt bar gesture zones. Home Assistant toasts and actions read as plain names. Keyboard Maestro rows show the macro name. Stepper Delay editor and inline value editing in the action sequence. Timer editor redesign. MCP server gesture tools merged into one (21 tools). AudioStream auto-start is opt-in. Built-in triggers can be deleted back into the + menu. Integrations fold into single rows. Dimmed rows for switched-off integrations. REST and terminal editor polish. Run strip waits for slow runs.

## Security and backup

- `read file` and `http-request` now need the API token when they arrive from another device, like `root` and `exec`. A REST API Call to the phone's own address is no longer trusted as local.
- The Web UI reads an origin as an address instead of matching text, so a public name like `10.example.com` no longer counts as a local page. The Keyboard Maestro password is masked in the config like the other secrets.
- REST API Call and Remote RC check HTTPS certificates. A request to a home server with a self-signed certificate can add `"insecure": true`.
- A full backup keeps add-on icon images and the switched-off add-ons list, leaves out the add-on catalog and the Run as Root list, so importing a file from elsewhere cannot grant root. A restore writes only the files a backup holds, and add-ons go to the jailbreak's own folder even when it does not exist yet.

## Fixed

- Touch ID triggers stay quiet during iOS fingerprint prompts. Pause Music no longer starts playback. Notification actions save without empty fields and tap IDs. Wi-Fi off skips the disconnect trigger briefly. Cards redraw to full width after rotation. Notifications permission asked on first launch. Clear Notifications handles long .txt filter lists in one write. Backup privacy warning in README, app, and Web UI. Imported Keyboard Maestro actions show macro names. Home Button action is instant on Home-button devices. Schedule trigger names update at once. Test Kit works on iOS 26. Two-finger and Bluetooth trigger icons redrawn. MQTT Topic hidden from the + menu until MQTT is enabled. Add-on exec steps work on rootless. Test Kit passcode Forever option survives respring and restart.

Full changelog: https://github.com/saihgupr/remotecompanion/blob/main/CHANGELOG.md

Install from Havoc, or add `https://saihgupr.github.io/remotecompanion` as a source in Sileo or Zebra. The .deb is attached below.
