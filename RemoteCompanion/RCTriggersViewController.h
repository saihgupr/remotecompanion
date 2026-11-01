#import <UIKit/UIKit.h>

// The Triggers screen: a table (List) or a grid of tiles (Compact), chosen in Settings
@interface RCTriggersViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
- (instancetype)initWithStyle:(UITableViewStyle)style;
- (void)openSettings;
- (void)addNewItem;
- (void)openTriggerWithKey:(NSString *)triggerKey;
@end

@interface RCTriggersViewController (Icons)
// The SF Symbol a trigger's row shows (also used by the trigger picker)
+ (NSString *)iconNameForTrigger:(NSString *)triggerKey;
@end
