#import <UIKit/UIKit.h>

// RC commands that answer with a value (a level or a state), for Set Variable's RC Command.
// Each row shows the command's answer on this phone right now. Push it onto a navigation stack.
@interface RCCommandPickerViewController : UITableViewController

- (instancetype)initWithSelectedCommand:(NSString *)selected;

// Called with the picked command, and whether its answer is best kept as a number; then goes back
@property (nonatomic, copy) void (^onPick)(NSString *command, BOOL number);

@end
