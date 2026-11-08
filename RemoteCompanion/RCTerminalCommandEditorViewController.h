#import <UIKit/UIKit.h>

@interface RCTerminalCommandEditorViewController : UITableViewController

- (instancetype)initWithCommand:(NSString *)command isRoot:(BOOL)isRoot;

// The trigger's actions: when set, the keyboard bar gets a + menu that inserts a variable
@property (nonatomic, copy) NSArray *variableActions;

// Called when Save is tapped. The caller dismisses or pops this screen.
@property (nonatomic, copy) void (^onSave)(NSString *command, BOOL isRoot);

@end
