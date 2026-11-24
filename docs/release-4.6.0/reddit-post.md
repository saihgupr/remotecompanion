# RemoteCompanion 4.6.0

Format notes from the last posts: `[Update]` prefix, `Update` flair, text post is fine if there are no fresh images, body opens with what it is for newcomers, then `# What's New in X`, then compatibility, links and a credit line.

## Title options (pick one)

1. `[Update] RemoteCompanion v4.6.0 - Copy or tap any text on screen, real touch gestures, and native Apple timers`
2. `[Update] RemoteCompanion v4.6.0 - Screen text actions, a local MCP server, and standard iOS notifications`
3. `[Update] RemoteCompanion v4.6.0 - Control Center buttons, real Clock timers, and text recognition on any screen`

## Gallery

No 4.6 screenshots exist yet. If you want a gallery, capture these on the 4.6 build and upload in this order:

1. Copy Text on Screen mid-drag, with the rectangle over a paragraph
2. Tap Text on Screen and Wait for Text in Select Action
3. The Timer screen with a running timer
4. The Notification action editor with buttons filled in
5. Control Center with the RemoteCompanion buttons

All at 1242x2208. The two shots in `docs/images/4.7.0/` named `reddit-04-timer-editor.png` and `reddit-05-screen-text.png` show 4.6 features, so they can be copied over if time is short.

## Post body

RemoteCompanion 4.6.0 is out. Update through Sileo or Zebra, or from the GitHub releases page.

RemoteCompanion is an Activator replacement for jailbroken iPhones on iOS 14 through 17, with partial iOS 26 support. You bind triggers like button presses, gestures, or device state to action sequences. You can also drive the phone from your Mac over SSH, from the Web UI, or from Shortcuts.

New to RemoteCompanion? The app gives you a trigger list and an action sequence editor that reads like Shortcuts. The same commands run from a terminal with `rc`, from the bundled Web UI, and from the local MCP server for assistants.

# What's New in 4.6.0

**Read and tap text on screen.** Copy Text on Screen freezes the screen so you can drag a rectangle over any drawn text and copy the lines it touches. Copy All Text on Screen takes every line at once. Tap Text on Screen taps a matching line where it appears, and Wait for Text pauses until the text shows up. A Text on Screen condition works in If and Wait Until. It uses Apple's text recognition, so any text the system draws counts, in any app.

**Real touch gestures.** The `gesture` family now drives the touchscreen itself: tap, hold, swipe, drag, two-finger swipe, pinch and rotate. Apps that ignored the older simulated taps respond. Points follow screen rotation, and a touch that starts on an edge still starts the Home or Back gesture. Two new commands, `screen capture` and `screen settle`, write a JPEG and wait for the screen to stop changing.

**A local MCP server for assistants.** `tools/rc-mcp` lets an MCP client look at the screen, tap, swipe, type and run any RC command over SSH, with nothing installed on the phone. It now has an offline index of every command, a one-call state read, full trigger and config control with backups, sequence checks, deeplinks, and debugging for logs, runs, files, screenshots, the Test Kit and add-ons.

**Native Apple timers.** The Timer action and `timer` command create real Clock timers through MobileTimer.framework. They show on the Lock Screen and in Control Center, and vibrate the Watch where you can stop or dismiss them. Start with `20m`, `1h30m`, `45s`, `20:00`, seconds or a variable, then pause, resume, stop or read the status. Labels work on iOS 17 and later.

**Standard iOS notifications.** `notify` now posts a real notification as the RemoteCompanion app, with a banner, a sound and a Notification Center entry, whether or not the app is running. The Notification action gets an editor for the title, message, a symbol or app icon, Time Sensitive, Remove After, up to four buttons, and Wait for Response. Notification Tap triggers run from a tap or a button, and `notify clear` removes posted notifications.

**Control Center buttons.** New Trigger > Control Center Button makes a named button with an SF Symbol icon and its own action sequence. Up to four buttons appear in Settings > Control Center as RemoteCompanion Button 1-4. Needs CCSupport on iOS 17 or earlier.

**New triggers and actions.** Airplane Mode On and Off fire from any source. Physical Orientation adds four triggers read from the accelerometer, so they follow how the phone is held even with rotation lock on. Set Orientation turns the screen and holds while rotation lock is on. Action Sequence Edited fires when any sequence changes, with a debounce so a burst of edits runs once.

**Smaller things.** The New Trigger menu has a compact tile layout with the category bar and a check on types already added. Settings > Banners gets the same category bar as Select Action. Clear Notifications now targets any app or chosen apps and takes as many text filters as you want, inline or from a file. The Test Kit passcode row gains a Forever choice that survives a respring and a restart.

# Also in this release

The large title on the Triggers screen now shows from launch and on the way back. `openssh-client` and `sshpass` ship with the package, so SSH actions work right after installing. Notification rows save as just `notify "Hi"` without empty fields. Turning Wi-Fi off no longer fires the Wi-Fi Network disconnect trigger. Cards redraw to full width after rotating. Notification permission is asked on first launch. Long Clear Notifications lists arrive in one write. Backups carry a privacy warning, and imported Keyboard Maestro actions show their macro names.

# Compatibility

iOS 14.0 through 17.x, with partial iOS 26 support that still needs broader testing. Rootless, rootful, and RootHide: Dopamine, palera1n, unc0ver, Taurine, XinaA15, NathanLR. arm64 and arm64e slices.

Install from Havoc, or add `https://saihgupr.github.io/remotecompanion` as a source in Sileo or Zebra. The deb is also on the GitHub releases page.
