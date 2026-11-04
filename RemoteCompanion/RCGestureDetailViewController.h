#import <UIKit/UIKit.h>

// A gesture's own page (tap it in Settings > Gestures): a drawing of its finger paths, replayed
// with the recorded timing, what it holds, and what can be done with it. The actions are handed
// back to the library, which runs them (its alerts show over this page).
@interface RCGestureDetailViewController : UITableViewController

@property (nonatomic, copy) NSString *name; // set again after a rename

// "play", "record", "rename", "export" or "delete", with the row it came from
@property (nonatomic, copy) void (^onAction)(NSString *action, UIView *source);
// After the gesture itself changed here (Trim), so the library can show it fresh
@property (nonatomic, copy) void (^onChange)(void);

@end
