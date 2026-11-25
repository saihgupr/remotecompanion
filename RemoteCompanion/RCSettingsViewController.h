#import <UIKit/UIKit.h>

// Settings. The same screen also shows two of its pages: Web UI (its switch, Access, Open in Safari,
// Address) and Backup (Export, Import).
extern NSString *const RCSettingsSubpageWebUI;
extern NSString *const RCSettingsSubpageBackup;

@interface RCSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
// One of the pages above (nil: Settings itself)
+ (instancetype)subpage:(NSString *)subpage;
@property (nonatomic, copy, readonly) NSString *subpage;
// A row to scroll to and flash once the screen shows (from a search result)
@property (nonatomic, copy) NSString *highlightRowID;
@end
