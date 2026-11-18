#import <UIKit/UIKit.h>

// TEMPORARY DESIGN PROTOTYPE, not used by the action sequence. Five takes on
// the row an action shows after you pick it, plus the three value panels those
// rows open. A contact sheet to judge from: nothing here is wired into an
// action, and nothing is saved.
@interface RCActionRowPrototypeGalleryViewController : UITableViewController

// The one call the settings row needs:
//   [self.navigationController pushViewController:
//       [RCActionRowPrototypeGalleryViewController prototypeGallery] animated:YES];
// A plain alloc/init works too.
+ (instancetype)prototypeGallery;

@end
