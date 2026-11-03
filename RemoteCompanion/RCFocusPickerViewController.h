#import <UIKit/UIKit.h>

// The phone's Focus modes, fetched from the tweak ("focus list"), each with its own icon, below
// fixed rows (Off). Used when adding or editing a Set Focus action. Shows a Cancel button when
// it's the root of a presented navigation stack.
@interface RCFocusPickerViewController : UITableViewController

// fixedRows: @{ @"name": ..., @"value": ..., @"icon": ... } shown above the Focus modes
- (instancetype)initWithTitle:(NSString *)title fixedRows:(NSArray<NSDictionary *> *)fixedRows;

// The value the action uses now: ticked (or listed as "Not Found"); @"" ticks Off
@property (nonatomic, copy) NSString *currentValue;
// row: @{ @"name": ..., @"value": ... } - a Focus mode's value is its name. The caller closes
// the picker.
@property (nonatomic, copy) void (^onSelected)(NSDictionary *row);
// For the Set Focus action: choosing a Focus asks Turn On or Toggle, and the row passed on
// carries the action as @"command" ("focus on|toggle <name>", or "focus off" for a fixed row
// whose value is empty)
@property (nonatomic, assign) BOOL buildsCommand;

@end
