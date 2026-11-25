#import <UIKit/UIKit.h>

// The Settings pages that hold groups of options (Advanced Settings before 4.7). Each page is a
// list of sections, each a list of rows named by an ID, so Settings' search can find every row.
typedef NS_ENUM(NSInteger, RCSettingsPage) {
    RCSettingsPageLayout,
    RCSettingsPageBanners,
    RCSettingsPageButtons,
    RCSettingsPageSwipeTriggers,
    RCSettingsPageNFC,
    RCSettingsPageDiagnostics,
    RCSettingsPageSecurity,
    RCSettingsPageCount,
};

// A Settings row's icon, as in iOS Settings: a white symbol (or glyph) on a rounded square of color
UIImage *RCSettingsIcon(NSString *symbol, UIColor *color);
UIImage *RCSettingsIconWithGlyph(UIImage *glyph, UIColor *color);
// A settings row's height, at least 50: a name too long for its line wraps onto the next, beside
// the row's icon, value and switch or chevron. The cell's textLabel needs numberOfLines 0.
CGFloat RCSettingsRowHeight(UITableView *tableView, UITableViewCell *cell);

@interface RCSettingsPageViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
- (instancetype)initWithPage:(RCSettingsPage)page;
// A row to scroll to and flash once the page shows (from a search result)
@property (nonatomic, copy) NSString *highlightRowID;

// The screen a page opens as: Banners is its own list (Wake Screen above it); the others are
// pages of rows. rowID: a row to flash once it shows (nil: none)
+ (UIViewController *)viewControllerForPage:(RCSettingsPage)page highlightRowID:(NSString *)rowID;
+ (NSString *)titleForPage:(RCSettingsPage)page;
+ (NSString *)symbolForPage:(RCSettingsPage)page;
+ (UIColor *)colorForPage:(RCSettingsPage)page;
// Every row on the page as {title, rowID}, in order, for search
- (NSArray<NSDictionary<NSString *, NSString *> *> *)searchEntries;
@end
