#import <UIKit/UIKit.h>

// Creates or edits a Control Center Button trigger: a button in Control Center with an icon of
// its own that runs the trigger's actions when tapped.
// Keys: trigger_cc_button_<id>, exposed dynamically to CCSupport via RCCCButtonProvider
// (Tweak/rc-ccmodule); the data is name, optional customName, icon (SF Symbol), actions.
extern NSString *const RCControlCenterButtonKeyPrefix;

@interface RCControlCenterTriggerViewController : UITableViewController
- (instancetype)initWithTriggerKey:(NSString *)triggerKey;
@end
