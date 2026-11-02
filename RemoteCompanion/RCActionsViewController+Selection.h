#import "RCActionsViewController.h"

// Selecting actions on a trigger's actions screen to copy or delete them together, and pasting
// copied actions into any trigger. Copied actions go on the system clipboard under their own
// type, so they can be pasted into another trigger, even after the app is closed. An If, Else If,
// Else or End If brings its whole block along, so a copy is always complete.
@interface RCActionsViewController (Selection)

// Whether rows are being selected (the table is in multi-select editing)
@property (nonatomic, readonly) BOOL rc_isSelectingActions;

// Adds the ••• menu's section for the actions themselves: Select Actions, Paste (when actions are
// on the clipboard), and Import / Export Actions, moved in from the list if it has them
- (void)rc_addActionsSectionToMenuItems:(NSMutableArray<UIMenuElement *> *)menuItems;

// Called when a row is tapped while selecting
- (void)rc_selectionChanged;

@end
