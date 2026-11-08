#import <UIKit/UIKit.h>

@interface RCRemoteActionEditorViewController : UITableViewController

- (instancetype)initWithClientId:(NSString *)clientId command:(NSString *)command;

// Called when Save is tapped. The caller dismisses or pops this screen.
@property (nonatomic, copy) void (^onSave)(NSString *clientId, NSString *command);

@end
