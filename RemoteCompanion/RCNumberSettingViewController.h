#import <UIKit/UIKit.h>

// A number setting (Delay, Repeat, Time Limit, a percentage) on a small screen: an optional
// choice (Above / Below), the number or a variable picked from the + menu, and a note.
// Present it inside a navigation controller.
@interface RCNumberSettingViewController : UITableViewController

// value: the current number or "{name}", or nil. otherActions: the trigger's actions, for the
// variables they set.
- (instancetype)initWithTitle:(NSString *)title label:(NSString *)label value:(NSString *)value otherActions:(NSArray *)otherActions;

@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, copy) NSString *note;            // under the field
@property (nonatomic, assign) double minimum;          // default 0
@property (nonatomic, assign) double maximum;          // default 1,000,000
@property (nonatomic, assign) BOOL allowsDecimals;
@property (nonatomic, copy) NSArray<NSString *> *choices;  // shown as a segmented control when set
@property (nonatomic, assign) NSInteger selectedChoice;
@property (nonatomic, copy) NSString *saveTitle;       // default Save

// value: an NSNumber in range, or an NSString "{name}"; choice: the selected choice's index
// Whether {round} can be chosen: only inside a Repeat does it have a value (default YES)
@property (nonatomic, assign) BOOL allowsRound;
@property (nonatomic, copy) void (^onSave)(id value, NSInteger choice);

@end
