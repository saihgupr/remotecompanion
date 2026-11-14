#import <UIKit/UIKit.h>

@interface RCIAmLazySettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

// YES when IAmLazy's command line tool is installed on this device
+ (BOOL)isIAmLazyInstalled;

@end
