#import <UIKit/UIKit.h>

// Creates or edits a Focus trigger: a chosen Focus (or any) turning on or off.
// Keys: trigger_device_focus_on|off for any Focus, trigger_device_focus_on_<name> and
// trigger_device_focus_off_<name> for one.
@interface RCFocusTriggerViewController : UITableViewController
- (instancetype)initWithTriggerKey:(NSString *)triggerKey;
@end
