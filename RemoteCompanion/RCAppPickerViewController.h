#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCAppPickerViewController : UITableViewController

@property (nonatomic, copy) void (^onAppSelected)(NSString *name, NSString *bundleId);
@property (nonatomic, assign) BOOL suppressAutoPop;
@property (nonatomic, copy) NSSet<NSString *> *selectedBundleIDs;

@end

NS_ASSUME_NONNULL_END
