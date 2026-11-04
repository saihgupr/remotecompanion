#import <UIKit/UIKit.h>

// The gesture library: recordings of what you did on the screen, by name ("gesture list" from the
// tweak). Records new ones (the app steps aside, you use the phone, then tap Stop), plays, renames
// and deletes them. Picks one for a Play Gesture action. Shows a Cancel button when it's the root
// of a presented navigation stack.
@interface RCGesturesViewController : UITableViewController

// The gesture the action plays now: ticked (or listed as "Not Found")
@property (nonatomic, copy) NSString *currentName;
// Set when picking for an action: a tapped gesture, or one just recorded, is passed on (@"" for
// Latest Recording, listed first). The caller closes the screen.
@property (nonatomic, copy) void (^onSelected)(NSString *name);

// The action that plays a gesture, and the gesture an action plays (nil for other actions).
// An empty name is Latest Recording: whichever gesture was recorded last.
+ (NSString *)commandForGesture:(NSString *)name;
+ (NSString *)gestureForCommand:(NSString *)command;

// The Record Gesture action: run once it starts recording, run again it stops and asks for a name
// (the Stop pill stops it too)
+ (NSString *)recordCommand;

@end
