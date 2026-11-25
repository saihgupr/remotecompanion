#import <Foundation/Foundation.h>

// Choose from Menu: a card in the middle of the screen, over any app and over the lock screen,
// with a title, a row per option (its name and SF Symbol) and Cancel. Runs on a trigger's thread:
// it shows the card on the main thread and waits for a pick.
//   options: @[@{ @"name": ..., @"icon": ... }]
//   timeout: seconds (0 or less: until a pick); the card counts it down
//   stopped: checked while waiting; YES closes the card (the run was stopped)
// Returns the option picked, RCMenuPromptCancelled (Cancel, or a tap outside the card) or
// RCMenuPromptTimedOut.
#define RCMenuPromptCancelled (-1)
#define RCMenuPromptTimedOut (-2)
NSInteger RCMenuPromptRun(NSString *title, NSArray<NSDictionary *> *options, double timeout, BOOL (^stopped)(void));
