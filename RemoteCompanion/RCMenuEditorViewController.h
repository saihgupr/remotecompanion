#import <UIKit/UIKit.h>

// Choose from Menu's own page: its title, its options (renamed, given an icon, reordered with their
// actions, added and deleted), its time limit and what a timeout does. Works on the whole block:
// block is @[menu, (actions before the first option), option, its actions..., ..., end_menu], or nil
// for a new menu. Save hands back the block to put in its place.
@interface RCMenuEditorViewController : UITableViewController
- (instancetype)initWithBlock:(NSArray *)block;
@property (nonatomic, copy) void (^onSave)(NSArray *block);
@end
