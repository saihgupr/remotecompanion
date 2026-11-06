#import <UIKit/UIKit.h>

@interface RCHTTPRequestEditorViewController : UITableViewController

// anAction is nil for a new request, or the http-request action being edited.
- (instancetype)initWithActionString:(NSString *)anAction;

// Called on Save with the finished http-request action. The caller closes this screen.
@property (nonatomic, copy) void (^onSave)(NSString *action);

@end
