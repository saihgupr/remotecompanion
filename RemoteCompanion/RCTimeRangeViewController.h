#import <UIKit/UIKit.h>

// The Time of Day condition: a start and an end time on time wheels.
// Present it inside a navigation controller.
@interface RCTimeRangeViewController : UITableViewController

// range: the stored value being edited ("09:00 - 17:00", "9 AM - 5 PM"...), or nil for 09:00 - 17:00
- (instancetype)initWithRange:(NSString *)range;

@property (nonatomic, copy) NSString *saveTitle;

// Called on Save. value is stored ("09:00 - 17:00", 24-hour); title is shown ("9:00 AM – 5:00 PM")
@property (nonatomic, copy) void (^onSave)(NSString *value, NSString *title);

@end
