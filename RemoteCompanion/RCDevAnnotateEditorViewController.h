#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCDevAnnotateEditorViewController : UITableViewController

@property (nonatomic, copy, nullable) void (^onSave)(NSString *actionString);

- (instancetype)initWithActionString:(nullable NSString *)actionString;

@end

NS_ASSUME_NONNULL_END
