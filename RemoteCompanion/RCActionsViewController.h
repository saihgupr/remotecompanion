#import <UIKit/UIKit.h>

@interface RCActionsViewController : UITableViewController

- (instancetype)initWithTriggerKey:(NSString *)triggerKey;
// The debugger view of one run (from the Running page): its current action highlighted, read-only
- (instancetype)initWithTriggerKey:(NSString *)triggerKey followingRun:(NSString *)runID;

@end
