#import <UIKit/UIKit.h>

@interface RCSSHHostEditorViewController : UIViewController

- (instancetype)initWithHost:(NSDictionary *)host;
// Called once the host is saved and the editor has closed (an action picker carries on with it)
@property (nonatomic, copy) void (^onSave)(NSDictionary *host);

@end
