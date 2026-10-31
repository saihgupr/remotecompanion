#import <UIKit/UIKit.h>

// The Toast action on one screen: title, subtitle and icon, with a + menu on the title and
// subtitle that inserts a variable. Present it inside a navigation controller.
@interface RCToastEditorViewController : UITableViewController

// command: the toast action being edited ("toast "Title" "Sub" "icon""), or nil.
// otherActions: the trigger's actions, for the variables they set.
- (instancetype)initWithCommand:(NSString *)command otherActions:(NSArray *)otherActions;

// Called on Save with the finished toast command
@property (nonatomic, copy) void (^onSave)(NSString *command);

@end
