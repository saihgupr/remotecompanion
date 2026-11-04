#import <UIKit/UIKit.h>

// The Set Variable editor on one screen: the kind of change as tiles (a new value, or a change
// to an existing variable's number), the variable, the kind's fields and This Run Only.
// Present it inside a navigation controller.
@interface RCSetVariableViewController : UITableViewController

// action: the one being edited, or nil for a new one.
// otherActions: the trigger's other actions, for the variables they set.
- (instancetype)initWithAction:(NSDictionary *)action otherActions:(NSArray *)otherActions;

// Called with the finished set_variable action when Save is tapped
@property (nonatomic, copy) void (^onSave)(NSDictionary *action);

@end
