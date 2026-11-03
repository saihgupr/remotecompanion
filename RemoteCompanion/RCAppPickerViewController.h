#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCAppPickerViewController : UITableViewController

@property (nonatomic, copy) void (^onAppSelected)(NSString *name, NSString *bundleId);
@property (nonatomic, assign) BOOL suppressAutoPop;

// Several apps can be ticked; Done hands them over, in the order they were ticked.
// selectedBundleIds are ticked to begin with.
@property (nonatomic, assign) BOOL allowsMultipleApps;
@property (nonatomic, copy, nullable) NSArray<NSString *> *selectedBundleIds;
@property (nonatomic, copy, nullable) void (^onAppsSelected)(NSArray<NSString *> *names, NSArray<NSString *> *bundleIds);

@end

NS_ASSUME_NONNULL_END
