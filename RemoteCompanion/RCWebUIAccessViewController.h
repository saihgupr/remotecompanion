#import <UIKit/UIKit.h>

// Who can reach the Web UI: any network, only trusted Wi-Fi networks (listed and edited here),
// or only this iPhone
@interface RCWebUIAccessViewController : UITableViewController
+ (NSString *)titleForAccess:(NSString *)access;
@end
