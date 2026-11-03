#import <UIKit/UIKit.h>

// Settings > Test Kit: runs the tweak's on-device test suites (through the UNIX socket's
// "testkit" command), follows the run in progress, and lists the saved reports.
@interface RCTestKitViewController : UITableViewController

// "Guided triggers" for "guided", and so on
+ (NSString *)displayNameForSuite:(NSString *)suite;

// Sends "testkit <request>" to the tweak; json is nil (and error set) if it couldn't be
// reached or didn't answer with a JSON object
+ (void)sendRequest:(NSString *)request completion:(void (^)(NSDictionary *json, NSError *error))completion;

@end
