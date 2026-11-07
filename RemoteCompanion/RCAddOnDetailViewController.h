#import <UIKit/UIKit.h>

// One add-on's page in Settings > Integrations: a switch that turns it on or off ("addons enable"
// / "addons disable"), what it adds (actions, triggers, conditions), a switch for each of its
// actions' banners, and where its file is. Follows the tweak's catalog as it changes.
@interface RCAddOnDetailViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

- (instancetype)initWithAddOnId:(NSString *)identifier;

@end
