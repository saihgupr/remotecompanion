#import <UIKit/UIKit.h>
#import "RCTimerCommand.h"

NS_ASSUME_NONNULL_BEGIN

// The Timer editor's form view and the pieces it shares. The hero layout (a big
// duration readout over the wheels) is the editor's permanent look. The old
// A/B/C/D comparison build is gone.

// "Start", "Pause", "Resume", "Stop".
FOUNDATION_EXPORT NSString *RCTimerActionWord(RCTimerActionType action);

// H:MM:SS for a plain duration, the typed expression when it holds a
// {variable}, and --:--:-- while it cannot be read yet.
FOUNDATION_EXPORT NSString *RCTimerReadoutTextForExpression(NSString * _Nullable expression);

// The colors the editor draws with: the RCUITweaker keys the rest of the app
// uses, plus the app's blue accent (the color of chips and checks on the
// Actions, Symbols and Banner screens).
@interface RCTimerEditorTheme : NSObject

@property (nonatomic, strong, readonly) UIColor *background;    // settingsBackground
@property (nonatomic, strong, readonly) UIColor *panel;         // blockBackground
@property (nonatomic, strong, readonly) UIColor *panelBorder;   // borders
@property (nonatomic, strong, readonly) UIColor *separator;     // separators
@property (nonatomic, strong, readonly) UIColor *control;       // a quieter fill for fields and chips
@property (nonatomic, strong, readonly) UIColor *controlBorder;
@property (nonatomic, strong, readonly) UIColor *accent;
@property (nonatomic, strong, readonly) UIColor *accentSoft;    // the accent washed over a panel
@property (nonatomic, strong, readonly) UIColor *accentBorder;
@property (nonatomic, strong, readonly) UIColor *primaryText;
@property (nonatomic, strong, readonly) UIColor *secondaryText;
@property (nonatomic, strong, readonly) UIColor *tertiaryText;

+ (instancetype)themeForCurrentConfig;

// System-sized fonts that follow Dynamic Type, capped so a huge text size
// cannot push the wheels off the sheet.
- (UIFont *)textFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
- (UIFont *)monospacedFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;

@end

// The editor's form. The controller keeps every behavior (picker data, fields,
// variable menus, save state) and hands this view the controls it shows.
@interface RCTimerEditorFormView : UIView

- (instancetype)initWithTheme:(RCTimerEditorTheme *)theme;

@property (nonatomic, strong, readonly) RCTimerEditorTheme *theme;

@property (nonatomic, strong, readonly) UIPickerView *picker;
@property (nonatomic, strong, readonly) UITextField *durationField;
@property (nonatomic, strong, readonly, nullable) UITextField *labelField; // iOS 17 and later

// Presets are not drawn in this layout, so this is always an empty array.
@property (nonatomic, strong, readonly) NSArray<UIButton *> *presetButtons;

@property (nonatomic, assign) RCTimerActionType selectedAction;
@property (nonatomic, copy, nullable) void (^onActionChange)(RCTimerActionType action);

// The live duration summary over the wheels.
@property (nonatomic, copy, readonly) NSString *defaultReadoutCaption;
@property (nonatomic, copy, nullable) NSString *readoutCaption;
@property (nonatomic, copy, nullable) NSString *readoutText;

@property (nonatomic, assign, readonly) BOOL durationVisible;
- (void)setDurationVisible:(BOOL)visible animated:(BOOL)animated;

// The wheel row: the number in the brand's monospaced face, the unit small
// beside it. The controller stays the picker's data source and asks for this.
- (UILabel *)pickerRowLabelForRow:(NSInteger)row component:(NSInteger)component;

@end

NS_ASSUME_NONNULL_END
