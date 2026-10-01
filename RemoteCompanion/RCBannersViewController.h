#import <UIKit/UIKit.h>

// Settings > Banners: pick the actions that show a banner when a trigger runs them.
@interface RCBannersViewController : UITableViewController
// How many actions in the list are ticked (for the Settings row)
+ (NSUInteger)checkedCount;
@end
