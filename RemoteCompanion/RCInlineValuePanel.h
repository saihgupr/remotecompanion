#import <UIKit/UIKit.h>

// The number editor an action row opens in place (Delay, Volume, Ringer Volume, Brightness): the
// caption, the big readout with its -/+ steps, and the exact field with the variable menu. It sits
// under the row's own title, inside the same cell, so the row stays where it was.
@interface RCInlineValuePanel : UIView

// prefix: the command's ("delay ", "set-vol "...). value: the number or "{name}" it starts with,
// or nil. otherActions: the trigger's actions, for the variables they set.
- (instancetype)initWithCaption:(NSString *)caption
                           unit:(NSString *)unit
                         prefix:(NSString *)prefix
                          value:(NSString *)value
                   otherActions:(NSArray *)otherActions;

@property (nonatomic, assign) double minimum;       // default 0
@property (nonatomic, assign) double maximum;       // default 100
@property (nonatomic, assign) double step;          // default 1
@property (nonatomic, assign) BOOL allowsDecimals;  // default NO. A step of 0.5 needs it
@property (nonatomic, assign) BOOL allowsRound;     // default YES. {round} only has a value inside a Repeat

// "set-vol 40" for what's showing, or nil when the text isn't a number in range (or a valid variable)
- (NSString *)currentCommand;

// How tall it needs to be at a width, for the cell's height
- (CGFloat)preferredHeightForWidth:(CGFloat)width;

// Return on a hardware keyboard: the value is ready. The owner folds the row and keeps it.
@property (nonatomic, copy) void (^onCommit)(void);

@end
