#import <UIKit/UIKit.h>

// One add-on's page in Settings > Add-ons: a switch that turns it on or off ("addons enable"
// / "addons disable"), what it adds (actions, triggers, conditions), a switch for each of its
// actions' banners, and where its file is. Follows the tweak's catalog as it changes.
@interface RCAddOnDetailViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

- (instancetype)initWithAddOnId:(NSString *)identifier;

// A setting to open (as tapping its row does) once the page has read the values: for a
// remotecompanion://addon?id=<add-on>&setting=<setting> link
@property (nonatomic, copy) NSString *openSettingId;

@end
