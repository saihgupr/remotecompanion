#import <Foundation/Foundation.h>

// Add-ons (ADDONS.md): JSON files that add actions, conditions and banners for other apps and
// tweaks. Read from the Add-ons folders at start and again when they change (the folders are
// watched). What loaded is written to /var/mobile/Documents/rc_addons.json for the app.

// Runs an add-on command ("<add-on id> <action> [options]"), or "addons [reload]". Returns nil
// when no add-on has that id. Called after the built-in commands, so they always come first.
NSString *RCAddOnsHandleCommand(NSString *cmd);

// Whether a command runs an add-on action that shows a banner of its own (so no generic banner)
BOOL RCAddOnsCommandShowsOwnBanner(NSString *cmd);

// The value of an add-on condition ("addon:<add-on id>:<condition id>"), or nil if unknown.
// *isNumber says whether it's compared as a number.
NSString *RCAddOnsConditionValue(NSString *key, BOOL *isNumber);

// For Wait Until: calls changed (on a background queue) each time the notification an add-on condition
// reads its state from is posted. Returns a token for RCAddOnsConditionStopWatching, or -1 when the
// condition isn't read from a notification (exec) or doesn't exist.
int RCAddOnsConditionWatch(NSString *key, dispatch_block_t changed);
void RCAddOnsConditionStopWatching(int token);

// The image an add-on's icon names (name nil), or one of its other icons (an action's, trigger's or
// condition's), and its content type; nil when it isn't an image the add-on lists
NSData *RCAddOnsIconData(NSString *addOnId, NSString *name, NSString **contentType);

// The add-ons offered on this device, as JSON for the Web UI: {"addons": [...], "problems": [...]}
NSString *RCAddOnsCatalogJSON(void);

// Loads the add-ons, registers their events and starts watching the folders. Call once in SpringBoard.
void RCAddOnsStart(void);
