#import <UIKit/UIKit.h>

// "New Trigger": the trigger types you can add, grouped into sections with icons.
// Each item is @{ title, icon, section, detail?, handler }; sections appear in the order
// of their first item. Choosing an item runs its handler, which pushes its setup
// screen on top (so Back returns here). Once a trigger's action editor is showing, the
// picker drops out of the stack, so Back from the editor goes to the Triggers list.
@interface RCNewTriggerViewController : UITableViewController <UINavigationControllerDelegate>

- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items;

@end
