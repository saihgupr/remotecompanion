#import <UIKit/UIKit.h>

@interface RCSSHSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
+ (BOOL)isSSHInstalled;
+ (BOOL)isSSHPassInstalled;
+ (BOOL)ensureSSHInstalledInViewController:(UIViewController *)viewController requireSSHPass:(BOOL)requireSSHPass;
@end

