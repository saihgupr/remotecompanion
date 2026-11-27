#import <UIKit/UIKit.h>

// The Triggers screen: a table (List) or a grid of tiles (Compact), chosen in Settings
@interface RCTriggersViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
- (instancetype)initWithStyle:(UITableViewStyle)style;
- (void)openSettings;
- (void)addNewItem;
- (void)openTriggerWithKey:(NSString *)triggerKey;
// What the New Trigger menu offers: {title, section, icon, and "key" for a built-in trigger or "kind"
// (the prefix of its keys) for one that's created}, for Test Kit > Coverage
+ (NSArray<NSDictionary *> *)newTriggerCatalog;
@end

@interface RCTriggersViewController (Icons)
// A trigger's icon wherever it's listed: an add-on's picture, an app's icon, the phone drawing,
// or its symbol (with a created trigger's letter). size: the symbol's point size.
+ (UIImage *)iconImageForTrigger:(NSString *)triggerKey size:(CGFloat)size;
// A chained trigger's icon, drawn from its first two steps' icons (nil for any other trigger)
+ (UIImage *)chainIconForTrigger:(NSString *)triggerKey size:(CGFloat)size;
// The SF Symbol a trigger's row shows (also used by the trigger picker)
+ (NSString *)iconNameForTrigger:(NSString *)triggerKey;
@end
