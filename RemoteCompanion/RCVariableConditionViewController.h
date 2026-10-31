#import <UIKit/UIKit.h>

// The Variable condition editor (If, Else If, Repeat While, Wait Until) on one screen:
// the comparison as tiles, the variable from a menu (or a typed name), and the value
// to compare with. Present it inside a navigation controller.
@interface RCVariableConditionViewController : UITableViewController

// condition: the action being edited (with variable, comparison, expectedValue), or nil.
// otherActions: the trigger's actions, for the variables they set.
- (instancetype)initWithCondition:(NSDictionary *)condition otherActions:(NSArray *)otherActions;

// Called on Save with the variable's name, the comparison code and the value ("" when none)
@property (nonatomic, copy) void (^onSave)(NSString *variable, NSString *comparison, NSString *value);

// Display title of a comparison code ("Is Above")
+ (NSString *)titleForComparison:(NSString *)comparison;

@end
