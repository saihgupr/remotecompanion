#import <UIKit/UIKit.h>

// One add-on's triggers, opened from the New Trigger menu. A trigger with states opens its list
// in place (Any State, then each state) and one without adds at a tap; the trigger's action list
// opens on top of this screen, so Back returns here and then to the New Trigger menu.
@interface RCAddOnTriggersViewController : UITableViewController
- (instancetype)initWithAddOn:(NSString *)identifier title:(NSString *)title;
@end
