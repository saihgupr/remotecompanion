#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCTimerEditorViewController : UITableViewController

@property (nonatomic, copy, nullable) NSArray *variableActions;
@property (nonatomic, copy, nullable) void (^onSave)(NSString *command);

- (instancetype)initWithCommand:(nullable NSString *)command;

@end

NS_ASSUME_NONNULL_END

