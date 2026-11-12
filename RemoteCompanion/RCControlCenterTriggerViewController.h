#import <UIKit/UIKit.h>

// Creates or edits a Control Center Button trigger: a button in Control Center with an icon of
// its own that runs the trigger's actions when tapped.
// Keys: trigger_cc_button_<slot>, one for each of the RCControlCenterButtonSlots module slots
// (the module for a slot is Tweak/rc-ccmodule; the data is name, icon (SF Symbol), actions).
extern const NSInteger RCControlCenterButtonSlots;
extern NSString *const RCControlCenterButtonKeyPrefix;

@interface RCControlCenterTriggerViewController : UITableViewController
- (instancetype)initWithTriggerKey:(NSString *)triggerKey;
@end

