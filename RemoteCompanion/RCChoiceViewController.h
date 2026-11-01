#import <UIKit/UIKit.h>

// An action with a few settings (Wi-Fi On / Off / Toggle, Auto-Lock times, camera modes...): its
// icon and name, its choices with a checkmark on one, and a note. Tapping a choice moves the
// checkmark; Save (or Add) confirms it. Works pushed (in the action picker) or as the root of a presented navigation
// controller (editing an action), which it closes before onPick.
@interface RCChoiceViewController : UITableViewController

// info: RCConfigManager's toggleInfoForCommand: for one of the action's commands.
// current: the command being edited (its choice gets the checkmark), or nil.
- (instancetype)initWithToggleInfo:(NSDictionary *)info current:(NSString *)current otherActions:(NSArray *)otherActions;

// The confirm button's title: "Add" while adding, "Save" (the default) when editing
@property (nonatomic, copy) NSString *saveTitle;

// The finished command ("wifi on", "autolock 2m", "button triggers pause 30"), on Save
@property (nonatomic, copy) void (^onPick)(NSString *command);

// Whether a command is Button Triggers paused for a time of the user's own ("button triggers pause 30")
+ (BOOL)isTimedPauseCommand:(NSString *)command;

@end
