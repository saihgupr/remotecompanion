#import <UIKit/UIKit.h>

@interface RCSSHActionEditorViewController : UITableViewController

- (instancetype)initWithHostId:(NSString *)hostId command:(NSString *)command;

// Called when Save is tapped. The caller dismisses or pops this screen.
@property (nonatomic, copy) void (^onSave)(NSString *hostId, NSString *command);

@end
