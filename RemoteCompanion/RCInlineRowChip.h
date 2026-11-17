#import <UIKit/UIKit.h>

// The value on the right of a row: a pill with the current value and a small up/down caret that
// says the value can be changed right here. Accented, it takes the row's tint.
@interface RCInlineRowChip : UIControl
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UIImageView *caretView;
@property (nonatomic, assign, getter=isAccented) BOOL accented;
// NO where the row already has its own chevron (the action sequence's rows do)
@property (nonatomic, assign) BOOL showsCaret;
- (void)setValueText:(NSString *)text;
@end
