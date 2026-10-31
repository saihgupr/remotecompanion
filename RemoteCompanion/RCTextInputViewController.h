#import <UIKit/UIKit.h>

@interface RCTextInputViewController : UIViewController

@property (nonatomic, copy) NSString *promptTitle;
@property (nonatomic, copy) NSString *promptMessage;
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, assign) BOOL showRootToggle;
@property (nonatomic, assign) BOOL isRootToggled;

// The trigger's actions: when set, the keyboard bar gets a + menu that inserts a variable
@property (nonatomic, copy) NSArray *variableActions;

@property (nonatomic, copy) void (^onComplete)(NSString *text);

@end
