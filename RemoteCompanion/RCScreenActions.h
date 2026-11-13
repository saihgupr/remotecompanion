#import <UIKit/UIKit.h>

// Actions on what's on the screen, found by its text (the tweak reads the screen with text
// recognition, so any text that's drawn counts):
//   screen tap "Text"            taps the middle of it
//   screen wait "Text" SECONDS   waits until it's on screen
//   screen copy                  copies all text on screen
//   screen copy rect [SECONDS]   lets you drag a box and copies the text inside
@interface RCScreenActions : NSObject

// The verbs that ask for text in the app picker, in order: tap, wait
+ (NSArray<NSString *> *)verbs;
+ (NSString *)commandForVerb:(NSString *)verb text:(NSString *)text seconds:(double)seconds;
// NO for anything that isn't a parameterized screen action (tap/wait)
+ (BOOL)parseCommand:(NSString *)command verb:(NSString **)verb text:(NSString **)text seconds:(double *)seconds;
// "Tap “Wi-Fi”", "Wait for “Done”", "Copy Text on Screen", "Copy All Text on Screen"; nil for anything else
+ (NSString *)nameForCommand:(NSString *)command;
+ (NSString *)iconForVerb:(NSString *)verb;
+ (NSString *)iconForCommand:(NSString *)command;
// Asks for the text (and, to wait, how long), with an existing action's values filled in
+ (void)promptForVerb:(NSString *)verb existing:(NSString *)command from:(UIViewController *)controller
               done:(void (^)(NSString *command))done;

@end
