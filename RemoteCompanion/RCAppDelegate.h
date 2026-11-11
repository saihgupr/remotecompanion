#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

@interface RCAppDelegate : UIResponder <UIApplicationDelegate, UNUserNotificationCenterDelegate>
@property (nonatomic, strong) UIWindow *window;
// Asks once for permission to show notifications (Notification actions post as this app)
+ (void)requestNotificationPermission;
@end
