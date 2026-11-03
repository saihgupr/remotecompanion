#import <UIKit/UIKit.h>

// Before a step-by-step run: who does the steps (Gestures & Sensors, Stock vs Tweak), then the
// suite's steps on this device, grouped, each with how many times to do it (0 leaves it out).
// Remembers the choices per suite.
@interface RCTestKitSetupViewController : UITableViewController

- (instancetype)initWithSuite:(NSString *)suite;

// Called with the options for "suite/run" (e.g. "&auto=1&steps=a,b:2")
@property (nonatomic, copy) void (^onStart)(NSString *options);

@end
