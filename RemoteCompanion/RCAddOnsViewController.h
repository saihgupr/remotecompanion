#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, RCAddOnsList) {
    RCAddOnsListNotInstalled = 0,   // add-ons whose app or tweak isn't installed
    RCAddOnsListProblems,           // files that didn't load, each with its reason
};

// One of the lists Settings > Integrations links to under Add-ons, read from the tweak's catalog
// (RCAddOnCatalog) and again each time it changes. Each add-on that loaded has its own page
// (RCAddOnDetailViewController).
@interface RCAddOnsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

- (instancetype)initShowing:(RCAddOnsList)list;

@end
