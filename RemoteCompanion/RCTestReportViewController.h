#import <UIKit/UIKit.h>

// One saved test report: its summary, the tests grouped as failed / skipped / passed (tap
// one for its full detail), and Share - a readable summary plus the JSON report, with
// personal values hidden unless the user chooses to include them.
@interface RCTestReportViewController : UITableViewController

- (instancetype)initWithReportId:(NSString *)reportId;

@end
