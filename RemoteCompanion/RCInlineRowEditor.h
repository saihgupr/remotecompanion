#import <UIKit/UIKit.h>

#import "RCInlineRowItem.h"

typedef NS_ENUM(NSInteger, RCInlineRowEditorStyle) {
    RCInlineRowEditorStyleCompact = 0,   // under a row, in the sequence
    RCInlineRowEditorStyleRegular,       // full size, in a panel or a sheet
};

// The editor a row opens in place: the caption with its variable menu, then the value itself. A
// number gets the round step buttons and an exact field, a choice its options, text a single well.
@interface RCInlineRowEditor : UIView

- (instancetype)initWithItem:(RCInlineRowItem *)item;
// otherActions: the trigger's actions, for the variables it sets. The regular style is the same
// editor at panel size, with the note under it that the number and text panels carry.
- (instancetype)initWithItem:(RCInlineRowItem *)item
                       style:(RCInlineRowEditorStyle)style
                otherActions:(NSArray *)otherActions;

@property (nonatomic, strong, readonly) RCInlineRowItem *item;
@property (nonatomic, assign, readonly) RCInlineRowEditorStyle style;
// A value changed: the row and its chip should read it again
@property (nonatomic, copy) void (^onChange)(void);
// Return, or the keyboard going away: the value is ready to keep
@property (nonatomic, copy) void (^onCommit)(void);
- (void)refresh;
- (void)endEditing;
// How tall it needs to be at a width, for the row's own height
- (CGFloat)preferredHeightForWidth:(CGFloat)width;

@end
