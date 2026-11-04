#import <UIKit/UIKit.h>

// A Play Gesture action's own page: which gesture it plays (or Latest Recording) and at what
// speed, kept with Save. Recording and the recording tab's options live in Settings > Gestures.
@interface RCPlayGestureViewController : UITableViewController

// The action being edited (nil for a new one)
@property (nonatomic, copy) NSString *command;
// Save: the action's new command. The caller closes the page.
@property (nonatomic, copy) void (^onSave)(NSString *command);

@end
