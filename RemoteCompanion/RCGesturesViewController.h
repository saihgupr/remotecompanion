#import <UIKit/UIKit.h>

// The gesture library (Settings > Gestures): recordings of what you did on the screen, by name
// ("gesture list" from the tweak). Records new ones (the app steps aside, you use the phone, then
// tap Stop), plays, renames and deletes them, and holds the recording tab's options. A Play
// Gesture action is edited on its own page (RCPlayGestureViewController).
@interface RCGesturesViewController : UITableViewController

// The action that plays a gesture, and the gesture an action plays (nil for other actions).
// An empty name is Latest Recording: whichever gesture was recorded last.
+ (NSString *)commandForGesture:(NSString *)name;
+ (NSString *)gestureForCommand:(NSString *)command;

// Playback speed (1 is as recorded). The action keeps it after the name: gesture play "N" 2x.
+ (NSString *)commandForGesture:(NSString *)name speed:(double)speed;
+ (double)speedForCommand:(NSString *)command;
+ (NSString *)titleForSpeed:(double)speed; // "2×"
+ (NSArray<NSNumber *> *)speeds;          // the speeds a Play Gesture action offers

// The Record Gesture action: run once it starts recording, run again it stops and asks for a name
// (the Stop tab stops it too)
+ (NSString *)recordCommand;

@end
