#import <UIKit/UIKit.h>

// Pieces shared by the Set Variable and Variable condition editors

// Letters, digits and _, not starting with a digit, at most 40, and not "round"
BOOL RCSetVariableNameValid(NSString *name);

// The insert menu for a value field: known variables by kind, then {round}
UIMenu *RCVariableInsertMenu(NSArray<NSString *> *runNames, NSArray<NSString *> *savedNames, void (^insert)(NSString *name));

// A footer whose text can change while a field in its section is being typed in
@interface RCSetVariableFooter : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *label;
@end

// One tile of a grid: kind is { op, title, icon, fallbackIcon? }
@interface RCSetVariableTile : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, copy) NSString *op;
- (instancetype)initWithKind:(NSDictionary *)kind compact:(BOOL)compact;
@end
