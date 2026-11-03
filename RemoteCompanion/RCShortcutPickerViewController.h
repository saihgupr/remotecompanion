#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCShortcutPickerViewController : UITableViewController

@property (nonatomic, copy) void (^onShortcutSelected)(NSString *shortcutName);
// A Run Silently switch above the list (no Shortcuts progress on screen); runSilently is its
// state, set before showing and read in onShortcutSelected
@property (nonatomic) BOOL showsSilentOption;
@property (nonatomic) BOOL runSilently;

@end

NS_ASSUME_NONNULL_END
