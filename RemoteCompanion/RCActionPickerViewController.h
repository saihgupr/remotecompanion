#import <UIKit/UIKit.h>

@interface RCActionPickerViewController : UITableViewController

@property (nonatomic, copy) void (^onActionSelected)(NSString *action);

// The action catalog this picker shows (sections of @{name, command, icon}), for other screens
- (NSArray<NSArray<NSDictionary *> *> *)catalogSections;
- (NSArray<NSString *> *)catalogSectionTitles;

@end
