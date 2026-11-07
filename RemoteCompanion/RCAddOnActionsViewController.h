#import <UIKit/UIKit.h>

// The actions of one add-on (add-on), opened from the action picker's Add-ons category
@interface RCAddOnActionsViewController : UITableViewController

- (instancetype)initWithAddOn:(NSString *)identifier title:(NSString *)title;

// Called with the picked entry: { name, command, icon }
@property (nonatomic, copy) void (^onSelect)(NSDictionary *action);

@end
