#import "RCActionsViewController.h"

// Selecting actions on a trigger's actions screen to copy or delete them together, and pasting
// copied actions into any trigger. A copy is kept in the app's own store, so it survives a
// relaunch, and is also written to the system pasteboard so it can be pasted outside the app.
// Menus and buttons check the store without reading the pasteboard; the pasteboard is read only
// when the person chooses Paste. An If, Else If, Else or End If brings its whole block along, so
// a copy is always complete.
@interface RCActionsViewController (Selection)

// Whether rows are being selected (the table is in multi-select editing)
@property (nonatomic, readonly) BOOL rc_isSelectingActions;

// Adds the ••• menu's section for the actions themselves: Select Actions, Paste (when there are
// copied actions), and Import / Export Actions, moved in from the list if it has them
- (void)rc_addActionsSectionToMenuItems:(NSMutableArray<UIMenuElement *> *)menuItems;

// The app's own copy of the copied actions, or nil. Read from NSUserDefaults, never from the
// pasteboard, so building a menu or button cannot trigger the system's "pasted from" banner
+ (NSArray *)rc_storedActionClipboard;

// Keeps a copy in the app's own store (clears it when empty) and writes it to the system
// pasteboard, so a copy also pastes outside the app
+ (void)rc_storeActionClipboard:(NSArray *)actions;

// Whether there are copied actions to paste, using only checks that read no clipboard content:
// the app's own store, then whether the pasteboard holds the app's action type
+ (BOOL)rc_hasPasteableActions;

// Puts actions on the shared pasteboard under the app's own type, alongside the app's own store
+ (void)rc_putActionsOnPasteboard:(NSArray *)actions;

// The actions on the shared pasteboard (including plain JSON text on iOS 15 and earlier), or nil.
// Must only be called from an actual paste; menus and buttons never read clipboard content
+ (NSArray *)rc_actionsOnPasteboard;

// Called when a row is tapped while selecting
- (void)rc_selectionChanged;

@end
