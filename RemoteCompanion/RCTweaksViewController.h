#import <UIKit/UIKit.h>

// Settings > iOS Tweaks: switches that change how iOS itself behaves, apart from triggers
@interface RCTweaksViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
// A row to scroll to and flash once the screen shows (from a search result)
@property (nonatomic, copy) NSString *highlightRowID;
// Every row as {title, rowID}, for Settings' search
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)searchEntries;
@end
