#import <UIKit/UIKit.h>

// TEMPORARY DESIGN PROTOTYPE. A contact sheet of six takes on the Select Action
// picker ("the functions menu"), so they can be compared side by side. Nothing
// here is used by the picker: RCActionPickerViewController is untouched.
//
// Entry point, from any row:
//   [self.navigationController pushViewController:
//       [RCFunctionsMenuPrototypeGalleryViewController galleryViewController] animated:YES];
@interface RCFunctionsMenuPrototypeGalleryViewController : UITableViewController
+ (instancetype)galleryViewController;
@end
