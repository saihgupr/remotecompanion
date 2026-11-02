#import <UIKit/UIKit.h>

// Creates or edits a Battery Level trigger: the battery dropping to, or rising to, a level.
// Keys: trigger_device_battery_below_<N> and trigger_device_battery_above_<N>.
@interface RCBatteryTriggerViewController : UITableViewController
- (instancetype)initWithTriggerKey:(NSString *)triggerKey;
@end
