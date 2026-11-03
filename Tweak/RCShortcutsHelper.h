// Shared by the tweak (SpringBoard) and RCShortcutsHelper (siriactionsd)

// Posted by the helper when siriactionsd is ready to run shortcuts; its state is siriactionsd's pid
#define kRCShortcutsHelperNotification "com.saihgupr.remotecompanion.shortcuts-helper"

// SpringBoard and the helper talk with distributed notifications, which carry a dictionary.
// Requests: to run a shortcut, id, name, and optionally input (text) and silent (YES: no Shortcuts
// progress on screen); to list them, id and action "list".
// Replies: id, state and sometimes error. A run is answered "started", "missing" (no shortcut by
// that name) or "unsupported" (this iOS lacks what the helper needs), and a started one again
// when it ends: "finished", "cancelled" or "failed". A list is answered "list", with names.
#define kRCShortcutsRunRequest @"com.saihgupr.remotecompanion.shortcuts.run"
#define kRCShortcutsRunReply   @"com.saihgupr.remotecompanion.shortcuts.reply"
