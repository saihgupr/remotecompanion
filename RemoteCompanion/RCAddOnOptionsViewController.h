#import <UIKit/UIKit.h>

// The options and field of an add-on (add-on) action, as rows with arrows like the New Trigger
// menu: a row for each option shows the choice (Keep Current by default) and opens its list; the
// field is a row too. Add or Save builds the full command.
@interface RCAddOnOptionsViewController : UITableViewController

// action: the add-on action; base: "<add-on id> <action command>"; current: the words after the
// action's own, whose choices are ticked (empty for a new action)
- (instancetype)initWithAction:(NSDictionary *)action base:(NSString *)base current:(NSArray<NSString *> *)current editing:(BOOL)editing;

// Called with the full command
@property (nonatomic, copy) void (^onDone)(NSString *command);

// Whether to leave this screen after Add or Save (when the caller doesn't close everything)
@property (nonatomic, assign) BOOL popsWhenDone;

@end
