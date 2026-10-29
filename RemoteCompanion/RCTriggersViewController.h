#import <UIKit/UIKit.h>

@interface RCTriggersViewController : UITableViewController
@end

@interface RCTriggersViewController (Icons)
// The SF Symbol a trigger's row shows (also used by the trigger picker)
+ (NSString *)iconNameForTrigger:(NSString *)triggerKey;
@end
