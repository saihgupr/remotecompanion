#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCClearNotificationsEditorViewController : UITableViewController

@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *variableActions;
@property (nonatomic, copy, nullable) void (^onSave)(NSString *command);

- (instancetype)initWithCommand:(nullable NSString *)command;

@end

NS_ASSUME_NONNULL_END

