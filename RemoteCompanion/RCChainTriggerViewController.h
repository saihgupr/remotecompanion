#import <UIKit/UIKit.h>

// A Chained Trigger's setup: its name, its steps (triggers, in order) and how long each step may
// take after the one before. New Trigger opens it empty, then opens the new trigger's action list;
// the action list's settings button opens it for the chain being edited.
@interface RCChainTriggerViewController : UITableViewController
- (instancetype)initWithTriggerKey:(NSString *)triggerKey; // nil for a new one
@end
