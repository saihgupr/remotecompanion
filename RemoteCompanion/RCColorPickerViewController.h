#import <UIKit/UIKit.h>

// The colors the Gestures row icon can take. Names are what the config stores, so
// they stay readable in an exported file and survive a restore.
@interface RCColorPickerViewController : UITableViewController

+ (NSArray<NSString *> *)colorNames;
+ (NSString *)titleForName:(NSString *)name;
+ (UIColor *)colorForName:(NSString *)name;

- (instancetype)initWithSelectedName:(NSString *)name;

@property (nonatomic, copy) void (^onPick)(NSString *name);

@end
