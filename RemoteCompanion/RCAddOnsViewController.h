#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, RCAddOnsList) {
    RCAddOnsListAll = 0,            // Settings > Add-ons: each add-on, then Not Installed and Problems
    RCAddOnsListNotInstalled,       // add-ons whose app or tweak isn't installed
    RCAddOnsListProblems,           // files that didn't load, each with its reason
};

// Settings > Add-ons and the two lists it links to, read from the tweak's catalog (RCAddOnCatalog)
// and again each time it changes. Each add-on that loaded has its own page
// (RCAddOnDetailViewController).
@interface RCAddOnsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

- (instancetype)initShowing:(RCAddOnsList)list;

@end
