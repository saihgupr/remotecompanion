#import <UIKit/UIKit.h>
#import "RCVariableEditorParts.h"

// ---------------------------------------------------------------------------
// TEMPORARY DESIGN PROTOTYPE - shared kit
//
// The shared look and the base class every delay prototype panel builds on.
// Nothing here is referenced by the shipping Delay flow.
// ---------------------------------------------------------------------------

@class RCDelayVariantView;
typedef RCDelayVariantView *(^RCDelayVariantFactory)(void);

extern const CGFloat RCDelayColumnBreak;

UIColor *RCDelayPageColor(void);
UIColor *RCDelayBlockColor(void);
UIColor *RCDelayBorderColor(void);
UIColor *RCDelaySeparatorColor(void);
UIColor *RCDelayAccent(UIView *view);

CGFloat RCDelayBasePointSize(UIFontTextStyle style);
UIFont *RCDelayFont(UIFontTextStyle style, UIFontWeight weight);
UIFont *RCDelayDigitFontOfSize(CGFloat size, UIFontTextStyle style, UIFontWeight weight);
UIFont *RCDelayDigitFont(UIFontTextStyle style, UIFontWeight weight);
UIFont *RCDelayMonoFont(CGFloat size, UIFontTextStyle style, UIFontWeight weight);

UILabel *RCDelayNoteLabel(NSString *text);
NSString *RCDelayTrimZeroes(NSString *text);
NSString *RCDelayFormat(double value, NSInteger decimals);
BOOL RCDelayNumberFromText(NSString *text, double *outValue);

@interface RCDelayVariantView : UIView
@property (nonatomic, copy) NSString *valueText;
- (void)valueTextDidChange;                       // subclasses refresh their controls
- (void)insertVariableNamed:(NSString *)name;
- (UIButton *)makeVariableButton;
- (UITextField *)makeNumberField;
@end
