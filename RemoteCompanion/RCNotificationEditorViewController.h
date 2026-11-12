#import <UIKit/UIKit.h>

// The Notification action's editor, for new ones and edits: a preview, Title and Message, a
// picture (a symbol or an app's icon), Time Sensitive, Remove After, and up to four buttons for
// its long-press menu. Opened as a card (in its own navigation controller).
@interface RCNotificationEditorViewController : UITableViewController
// command: the action's notify command, or nil for a new one
- (instancetype)initWithCommand:(NSString *)command;
// The saved command; it keeps the tap ID and button IDs, so their triggers stay linked
@property (nonatomic, copy) void (^onSave)(NSString *command);
// The trigger's actions: their Set Variable names go in the + menus on Title and Message
@property (nonatomic, copy) NSArray *variableActions;
@end
