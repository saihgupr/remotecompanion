#import <UIKit/UIKit.h>

// New Trigger > Notification: the Notification actions in all triggers, each with its buttons.
// Choosing one opens the actions that run when its notification is tapped (notiftap_<tap ID>) or
// when that button is pressed (notifbtn_<button ID>).
// Opened for an existing one (its settings button), it lists that kind only, and choosing one
// links it to that trigger, for when its notification or button was deleted or replaced.
@interface RCNotificationTapTriggerViewController : UITableViewController
- (instancetype)init;
- (instancetype)initWithTapTriggerKey:(NSString *)triggerKey;
// After a link, before going back
@property (nonatomic, copy) void (^onLinked)(void);
@end
