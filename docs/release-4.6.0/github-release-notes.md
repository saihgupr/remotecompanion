# RemoteCompanion v4.6.0

This release adds screen reading and real touch gestures, a local MCP server for assistants, native Apple timers, real iOS notifications, and Control Center buttons.

## Highlights

**Screen text.** Copy Text on Screen freezes the screen so you can drag a rectangle over any drawn text and copy the lines it touches. Copy All Text on Screen takes every line at once. Tap Text on Screen taps a matching line where it appears, and Wait for Text pauses until the text shows up. A Text on Screen condition works in If and Wait Until. Matching ignores case and prefers an exact line, then a line starting with the text, then one containing it. CLI: `screen copy`, `screen tap`, `screen wait`, `screen find`, `screen ocr`.

**Real touch gestures.** `gesture tap`, `hold`, `swipe`, `drag`, `swipe2`, `pinch` and `rotate` move the touchscreen itself, so apps receive them like a finger where the older `tap`, `hold` and `swipe` commands sometimes did not. Points follow screen rotation, and a touch that starts on an edge still starts the Home or Back gesture. New `screen capture` and `screen settle` write a JPEG and wait for the screen to stop changing.

**MCP server for assistants.** `tools/rc-mcp` is one Python file that lets an MCP client look at the screen, tap, swipe, type and run any RC command over SSH. Nothing is installed on the phone. It now includes an offline index of every command (`rc_help`), a one-call state read (`rc_state`), full trigger control (`rc_trigger`), config read and write with a backup and read-back (`rc_config`), sequence validation (`rc_sequence`), `remotecompanion://` navigation (`rc_deeplink`), and debugging for the log, runs, files, screenshots, the Test Kit and add-ons.

**Native Apple timers.** The Timer action and `timer` CLI use MobileTimer.framework, so timers are real Clock timers. They sync with the Lock Screen, Control Center, and Apple Watch, where you can stop or dismiss them. Start with `20m`, `1h30m`, `45s`, `20:00`, seconds or a variable, then pause, resume, stop or read the status. Labels work on iOS 17 and later.

**Standard iOS notifications.** `notify` posts a real notification as the RemoteCompanion app, with a banner, a sound and a Notification Center entry, whether or not the app is running. The Notification action editor covers the title, message, a symbol or app icon, Time Sensitive, Remove After, up to four buttons, and Wait for Response, whose answer becomes `{notify_response}`. Notification Tap triggers run from a tap or a button, and `notify clear` removes posted notifications.

**Control Center buttons.** New Trigger > Control Center Button creates a named button with an SF Symbol icon and its own action sequence. Buttons appear in Settings > Control Center as RemoteCompanion Button 1-4. Needs CCSupport and iOS 17 or earlier.

**New triggers and actions.** Airplane Mode On and Off fire from any source. Physical Orientation adds Portrait Up, Landscape Left, Landscape Right and Portrait Upside Down, read from the accelerometer so they follow how the phone is held even with rotation lock on. Set Orientation turns the screen and holds while rotation lock is on. Action Sequence Edited fires when any sequence changes, with a debounce so a run of edits runs once.

## Changed

- Compact New Trigger menu: tiles with the trigger icons, the category bar, and a check on types already added.
- Banner categories: the Select Action category bar now sits in Settings > Banners, with All and Enabled.
- Clear Notifications replaces Clear RC Notifications, and takes any app, chosen apps, and inline or pasted text filters.
- Tighter bar gesture zones: 25pt from the edge instead of 50pt, with two-finger slides keeping their wider zone.
- New Trigger opens with the same large title as the Triggers screen.

## Fixed

- The large title on the Triggers screen shows from launch and on the way back.
- `openssh-client` and `sshpass` ship with the package, so SSH actions work right after installing.
- Notification rows save as just `notify "Hi"`, with no empty message and no tap ID.
- Turning Wi-Fi off no longer fires the Wi-Fi Network disconnect trigger.
- Action and trigger cards redraw to the full width after rotating.
- Notification permission is asked on first launch.
- Long Clear Notifications `.txt` lists are sent in one write instead of being cut at 1 KB.
- The README, the export confirmation and the Web UI export toast carry a privacy warning.
- Imported Keyboard Maestro actions show their macro names.

Full changelog: https://github.com/saihgupr/remotecompanion/blob/main/CHANGELOG.md

Install from Havoc, or add `https://saihgupr.github.io/remotecompanion` as a source in Sileo or Zebra. The .deb is attached below.
