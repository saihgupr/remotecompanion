#import <UIKit/UIKit.h>

// A trigger's last runs (or every trigger's, newest first): when, how long, and whether it finished
// or was stopped; tapping one shows its actions as they were for that run, with what happened at
// each (the If branches it took, its loops' rounds, its waits). Keep sets how many are kept.
@interface RCRunHistoryViewController : UITableViewController
// nil for every trigger's runs
- (instancetype)initWithTriggerKey:(NSString *)triggerKey;

// For the Running page's list of recent runs
+ (NSString *)whenText:(double)started;
+ (NSString *)durationText:(double)seconds;
+ (NSString *)summaryForRun:(NSDictionary *)run;
+ (UIViewController *)detailForRun:(NSDictionary *)run;
// Deletes one run from the history; done runs on the main queue
+ (void)deleteRun:(NSDictionary *)run completion:(void (^)(void))done;
@end
