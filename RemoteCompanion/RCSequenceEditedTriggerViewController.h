#import <UIKit/UIKit.h>

// Creates or edits the Action Sequence Edited trigger: it runs when the actions of any trigger
// change, from the app, the web UI or the CLI. Key: trigger_sequence_edited.
@interface RCSequenceEditedTriggerViewController : UITableViewController
- (instancetype)initWithTriggerKey:(NSString *)triggerKey;
@end
