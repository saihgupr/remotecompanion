#import <UIKit/UIKit.h>

// The triggers running now, like a task manager: each with the step it's on (and the round of the
// loop it's in) and how long it's been going, and Stop. Refreshes while it's open.
@interface RCRunningViewController : UITableViewController
// Only this trigger's runs (opened from its page); Stop All ends just those
- (instancetype)initWithTriggerKey:(NSString *)triggerKey;
@end
