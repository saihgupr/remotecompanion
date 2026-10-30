#import <UIKit/UIKit.h>

@interface RCTriggersViewController : UITableViewController
// The SF Symbol a trigger's row shows (also used by the trigger picker)
+ (NSString *)iconNameForTrigger:(NSString *)triggerKey;
@end
