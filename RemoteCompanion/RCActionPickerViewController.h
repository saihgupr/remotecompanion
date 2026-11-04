#import <UIKit/UIKit.h>

@interface RCActionPickerViewController : UITableViewController

@property (nonatomic, copy) void (^onActionSelected)(NSString *action);
// Actions that lead to another screen: the picker stays open under it (Cancel there comes back
// here), and whoever opened the picker closes it once the action is added
@property (nonatomic, copy) BOOL (^staysOpenFor)(NSString *action);

// The action catalog this picker shows (sections of @{name, command, icon}), for other screens
- (NSArray<NSArray<NSDictionary *> *> *)catalogSections;
- (NSArray<NSString *> *)catalogSectionTitles;

@end
