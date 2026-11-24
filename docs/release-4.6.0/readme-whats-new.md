> [!IMPORTANT]
> **What’s New in v4.6.0**
> - **Screen text actions**: Copy Text on Screen (drag a rectangle over the words), Copy All Text on Screen, Tap Text on Screen, Wait for Text, and a Text on Screen condition for If and Wait Until. Any text drawn in any app counts, and matching ignores case.
> - **Real touch gestures**: the `gesture` family (tap, hold, swipe, drag, two-finger swipe, pinch, rotate) drives the touchscreen itself, so apps that ignored the older simulated taps respond. Plus `screen capture` and `screen settle`.
> - **MCP server for assistants**: `tools/rc-mcp` lets an MCP client read the screen, tap, swipe, type and run any RC command over SSH, with an offline command index, one-call state, full trigger and config control, and debugging tools.
> - **Native Apple timers**: real Clock timers that sync with the Lock Screen, Control Center and Apple Watch, with pause, resume, stop, status and labels.
> - **Standard iOS notifications**: `notify` posts real notifications with a title, message, icon, buttons, Time Sensitive and Wait for Response, whether or not the app is running, and Notification Tap triggers run from them.
> - **Control Center buttons**: up to four named buttons with SF Symbol icons, each running its own action sequence from Control Center. Needs CCSupport and iOS 17 or earlier.
> - **New triggers and actions**: Airplane Mode On and Off, Physical Orientation from the accelerometer, Set Orientation, and Action Sequence Edited with a debounce.
> - **Smaller polish**: a compact New Trigger menu, banner categories, Clear Notifications for any app with text filters, a Test Kit passcode that can last Forever, and tighter bar gesture zones.
