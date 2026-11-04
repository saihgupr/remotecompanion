#import <UIKit/UIKit.h>

// Actions on what's on the screen, found by its text (the tweak runs rc-screen for them):
//   screen tap "Text"            presses it (a real tap if pressing doesn't work)
//   screen wait "Text" SECONDS   waits until it's on screen
//   screen scroll-to "Text"      scrolls the list until it shows
@interface RCScreenActions : NSObject

// The verbs, in picker order: tap, wait, scroll-to
+ (NSArray<NSString *> *)verbs;
+ (NSString *)commandForVerb:(NSString *)verb text:(NSString *)text seconds:(double)seconds;
// NO for anything that isn't a screen action
+ (BOOL)parseCommand:(NSString *)command verb:(NSString **)verb text:(NSString **)text seconds:(double *)seconds;
// "Tap “Wi-Fi”", "Wait for “Done”", "Scroll to “Privacy”"; nil for anything else
+ (NSString *)nameForCommand:(NSString *)command;
+ (NSString *)iconForVerb:(NSString *)verb;
// Asks for the text (and, to wait, how long), with an existing action's values filled in
+ (void)promptForVerb:(NSString *)verb existing:(NSString *)command from:(UIViewController *)controller
               done:(void (^)(NSString *command))done;

@end
