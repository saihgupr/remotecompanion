#import <UIKit/UIKit.h>

@interface RCRCClientEditorViewController : UIViewController

- (instancetype)initWithClient:(NSDictionary *)client;
// Called once the device is saved and the editor has closed (an action picker carries on with it)
@property (nonatomic, copy) void (^onSave)(NSDictionary *client);

@end
