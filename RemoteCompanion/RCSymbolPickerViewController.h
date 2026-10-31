#import <UIKit/UIKit.h>

// Picks an SF Symbol from a searchable grid of icon tiles, filtered by category chips.
// Typing a symbol name that isn't in the grid offers it too. Push it onto a navigation stack.
@interface RCSymbolPickerViewController : UIViewController

// selected: the current symbol name, or nil. allowsNone: offers a "None" tile.
- (instancetype)initWithSelectedSymbol:(NSString *)selected allowsNone:(BOOL)allowsNone;

// Called with the picked name ("" for None); the picker then goes back
@property (nonatomic, copy) void (^onPick)(NSString *name);

@end
