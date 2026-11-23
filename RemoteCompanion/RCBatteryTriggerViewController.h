#import <UIKit/UIKit.h>

// Creates or edits a Battery Level trigger (iPhone or Apple Watch): dropping to, or rising to, a level.
// Keys: trigger_device_battery_below_<N> / trigger_device_battery_above_<N>,
//       trigger_watch_battery_below_<N> / trigger_watch_battery_above_<N>.
@interface RCBatteryTriggerViewController : UITableViewController
- (instancetype)initWithTriggerKey:(NSString *)triggerKey;
- (instancetype)initWithTriggerKey:(NSString *)triggerKey isWatch:(BOOL)isWatch;
@end
