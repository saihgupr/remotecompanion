#import <UIKit/UIKit.h>

// The triggers that have actions, grouped like the Triggers screen, with their icons and actions,
// and a search field. Used by the Stop Trigger action. Shows a Cancel button when it's the root of
// a presented navigation stack.
@interface RCTriggerPickerViewController : UITableViewController

// excludedKey: left out of the list (the trigger whose actions are being edited)
- (instancetype)initWithTitle:(NSString *)title excludingTrigger:(NSString *)excludedKey;

// The trigger the action uses now: ticked, and listed even if it no longer has actions
@property (nonatomic, copy) NSString *currentKey;
// Shown below the list
@property (nonatomic, copy) NSString *footerText;
// The caller closes the picker
@property (nonatomic, copy) void (^onSelected)(NSString *triggerKey);

@end
