# RemoteCompanion 4.7.0

Format notes from the last three posts: `[Update]` prefix, `Update` flair, gallery or text post, body opens with what it is for newcomers, then `# What's New in X`, then compatibility, links, and a credit line. Closest match to this draft is the v4.4.0 post.

## Title options (pick one)

1. `[Update] RemoteCompanion v4.7.0 - Annotate a screenshot and send it to your editor, Apple Watch actions and triggers, and real touch gestures`
2. `[Update] RemoteCompanion v4.7.0 - Apple Watch control, tap text on screen, Control Center buttons, and native Apple timers`
3. `[Update] RemoteCompanion v4.7.0 - Control Center buttons, tap any text on screen, and full backup and restore`

## Gallery order (upload from `docs/images/4.7.0/`)

1. `reddit-01-annotate-editor.png` - Edit Annotate & Send, with the username and IP blurred
2. `reddit-02-annotate-actions.png` - the two annotate actions in a real sequence
3. `reddit-03-watch-actions.png` - Watch actions in Select Action
4. `reddit-04-timer-editor.png` - the redesigned Timer editor
5. `reddit-05-screen-text.png` - the screen text actions in Select Action

All five are 1242x2208 PNGs captured on the iPhone running 4.7.0.

## Post body

RemoteCompanion 4.7.0 is out. Update through Sileo or Zebra, or from the GitHub releases page.

RemoteCompanion is an Activator replacement for jailbroken iPhones on iOS 14 through 17, with partial iOS 26 support. You bind triggers like button presses, gestures, or device state to action sequences. You can also drive the phone from your Mac over SSH, from the Web UI, or from Shortcuts.

New to RemoteCompanion? The app gives you a trigger list and an action sequence editor that reads like Shortcuts. The same commands run from a terminal with `rc`, from the bundled Web UI, and from the local MCP server for assistants.

# What's New in 4.7.0

**Annotate a screenshot and send it to your editor.** Developer Mode adds an action that freezes a screenshot so you can mark it up and attach a typed or dictated note, then sends both over SSH to OpenCode or Antigravity on your Mac. With OpenCode and Auto-Send on, it queues the note in your active session through the local API and opens that session in a background tab. With Antigravity it opens your project folder and pastes into Agent chat. Find it under Settings > Advanced Settings > Developer.

**Apple Watch control, both ways.** Five new actions set Theater Mode, Silent Mode, Wake on Wrist Raise, Water Lock, and Always On. A Watch Face action switches faces by name or steps to the next or previous face. Three triggers fire on Watch Connected, Watch Disconnected, and Watch Face Changed. The Notification action has a Watch Only option that buzzes the wrist and leaves the iPhone screen dark.

**Read and tap text on screen.** Copy Text on Screen lets you drag a rectangle over any drawn text to copy it. Copy All Text on Screen grabs every line at once. Tap Text on Screen taps a matching line where it appears, and Wait for Text pauses until the text shows up. A Text on Screen condition works in If and Wait Until. Matching ignores case and prefers an exact match first.

**Real touch gestures.** The `gesture` family (tap, hold, swipe, drag, two-finger swipe, pinch, rotate) now drives the touchscreen itself, so apps that ignored the older simulated taps respond. Points follow screen rotation. After a reboot, touch the screen once before the first touch command.

**Control Center buttons.** New Trigger > Control Center Button creates a named button with an SF Symbol icon and its own action sequence. Buttons show up in Settings > Control Center under their own name and run the sequence on tap. There is no four button limit. Needs CCSupport on iOS 17 or earlier.

**Native Apple timers.** The Timer action now creates real Clock timers. They show on the Lock Screen and in Control Center and vibrate the Watch. Start with plain durations like `20m` or `1h30m`, with pause, resume, stop, and status. Labels work on iOS 17 and later.

**New triggers.** Airplane Mode On and Off fire from any source. Four physical orientation triggers (Portrait Up, Landscape Left, Landscape Right, Portrait Upside Down) read the accelerometer, so they fire for how the phone is held even with rotation lock on. Long Press App Icon fires when a Home Screen icon is held, for one app or several. Action Sequence Edited fires when any sequence changes, with a debounce so a burst of edits runs once.

**Set Orientation action.** Pick Portrait, Landscape Left, Landscape Right, Portrait Upside Down, or Auto Rotate. The screen turns at once and holds while rotation lock is on. Auto Rotate releases the hold.

# Also in this release

This version also ships everything from 4.5.0, which was never announced. That means the add-ons system (one JSON file per add-on in the AddOns folder), full backup and restore of the whole config with `rc export` and `rc import`, a Triggers screen that starts empty with everything in the + menu, and Remote RC actions that run commands on a second device over its Web UI.

Security and backup: `read file` and `http-request` now need the API token when they arrive from another device, a REST API Call to the phone's own address is no longer trusted as local, and the Web UI reads an origin as an address so a public name like `10.example.com` does not count as local. REST API Call and Remote RC now check HTTPS certificates, with `"insecure": true` for a self-signed home server. Backups keep add-on icons and the switched-off add-ons list, leave out the Run as Root list, and a restore writes only the files a backup holds.

Also here: standard iOS notifications from `notify` with a title editor, buttons, and tap triggers; a compact tile layout for the New Trigger menu; banner categories; one Device State section in the trigger menu; clearer Home Assistant and Keyboard Maestro row names; inline steppers for Delay, Volume, and Brightness rows; a redesigned Timer editor; and a Test Kit passcode Forever option that survives respring and restart. The sequence editor also gains undo and redo up to 50 steps, swipe right on a row to copy, paste or cut it, nested If and Repeat cards that indent to their block, and a Test button on SSH hosts that reports Connected or the exact failure.

# Compatibility

iOS 14.0 through 17.x, with partial iOS 26 support that still needs broader testing. Rootless, rootful, and RootHide: Dopamine, palera1n, unc0ver, Taurine, XinaA15, NathanLR. arm64 and arm64e slices.

Install from Havoc, or add `https://saihgupr.github.io/remotecompanion` as a source in Sileo or Zebra. The deb is also on the GitHub releases page.

# Known limitations

- Control Center Button needs CCSupport and iOS 17 or earlier.
- Touch gesture commands need one physical screen touch after each reboot.
- Watch actions and triggers only appear when the Apple Watch app is installed.
- Add-on folder paths differ between rootless and rootful installs.
- A Forever Test Kit passcode is usable after a reboot only once the phone has been unlocked.
- iOS 15.8 on an iPhone SE (2016) was reported broken since 4.1.0. If you hit it, open an issue with your build variant and the steps, and it gets looked at.

# Links

- Website: https://saihgupr.github.io/remotecompanion/
- GitHub: https://github.com/saihgupr/remotecompanion
- All release notes: https://github.com/saihgupr/remotecompanion/releases

Thanks to u/GoldenAppleGuy for the security and backup review that landed in this release.

Bug reports and feature requests are welcome in the comments. If something breaks, include your iOS version, jailbreak type, and the exact trigger and action combo, or open a GitHub issue.

New releases every Sunday morning.
