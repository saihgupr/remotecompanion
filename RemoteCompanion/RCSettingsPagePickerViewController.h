#import <UIKit/UIKit.h>

// The pages of the Settings app an Open Settings Page action can open: the common ones (with the
// rows they lead to, one level at a time), an installed app's own page, or a name typed in. The
// tweak opens Settings and taps each row in turn, scrolling if needed. Used when adding the action
// and when an existing one is tapped.
// Shows a Cancel button when it is the root of a presented navigation stack.
@interface RCSettingsPagePickerViewController : UITableViewController

// Starts the list at this page, with the rows above it carried along by each push. Pass nil or
// an empty array for the top level.
- (instancetype)initWithPath:(NSArray<NSString *> *)path;

// The page the action uses now, e.g. "General > About", ticked when it is one of the listed pages
@property (nonatomic, copy) NSString *currentLabel;
// The full path, each row joined by " > ", exactly as the Settings app shows it. The caller closes
// the picker.
@property (nonatomic, copy) void (^onSelect)(NSString *label);

@end
