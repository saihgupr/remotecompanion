#import "RCInlineRowEditor.h"

#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCVariableEditorParts.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

#pragma mark - Look

static UIColor *RCInlineRowEditorAccent(UIView *view) {
    return view.tintColor ?: [UIColor systemBlueColor];
}

static CGFloat RCInlineRowEditorBaseSize(UIFontTextStyle style) {
    if ([style isEqualToString:UIFontTextStyleLargeTitle]) return 34;
    if ([style isEqualToString:UIFontTextStyleTitle1]) return 28;
    if ([style isEqualToString:UIFontTextStyleTitle2]) return 22;
    if ([style isEqualToString:UIFontTextStyleTitle3]) return 20;
    if ([style isEqualToString:UIFontTextStyleHeadline]) return 17;
    if ([style isEqualToString:UIFontTextStyleBody]) return 17;
    if ([style isEqualToString:UIFontTextStyleCallout]) return 16;
    if ([style isEqualToString:UIFontTextStyleSubheadline]) return 15;
    if ([style isEqualToString:UIFontTextStyleFootnote]) return 13;
    if ([style isEqualToString:UIFontTextStyleCaption1]) return 12;
    if ([style isEqualToString:UIFontTextStyleCaption2]) return 11;
    return 17;
}

static UIFont *RCInlineRowEditorFontSized(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

static UIFont *RCInlineRowEditorFont(UIFontTextStyle style, UIFontWeight weight) {
    return RCInlineRowEditorFontSized(RCInlineRowEditorBaseSize(style), style, weight);
}

static UIFont *RCInlineRowEditorDigitFontSized(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

static UIFont *RCInlineRowEditorMonoFontSized(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont monospacedSystemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

static UIImage *RCInlineRowEditorSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIImageConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    UIImage *image = name.length ? [UIImage systemImageNamed:name withConfiguration:configuration] : nil;
    return image ?: [UIImage systemImageNamed:@"square.dashed" withConfiguration:configuration];
}

static UILabel *RCInlineRowEditorLabel(NSString *text, UIFont *font, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static UILabel *RCInlineRowEditorNote(NSString *text) {
    UILabel *label = RCInlineRowEditorLabel(text, RCInlineRowEditorFont(UIFontTextStyleFootnote, UIFontWeightRegular), [UIColor secondaryLabelColor]);
    label.numberOfLines = 0;
    return label;
}

static UIView *RCInlineRowEditorWell(UIColor *fill, CGFloat radius) {
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = fill;
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}

// A short, firm tap when a value changes, and the softer one a row gives as it opens or closes
static void RCInlineRowEditorSelectTick(void) {
    UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
    [generator selectionChanged];
}

static void RCInlineRowEditorImpact(void) {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator prepare];
    [generator impactOccurred];
}

static NSString *RCInlineRowEditorUnitSuffix(RCInlineRowItem *item) {
    if (!item.unit.length) return @"";
    return item.unitNeedsSpace ? [NSString stringWithFormat:@" %@", item.unit] : item.unit;
}

#pragma mark - The step buttons and the readout between them

@interface RCInlineRowReadoutControl : UIControl
@end

@implementation RCInlineRowReadoutControl

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.55 : 1.0;
}

@end

@interface RCInlineRowStepperStrip : UIView
@property (nonatomic, strong, readonly) UILabel *readout;
@property (nonatomic, strong, readonly) UILabel *unitLabel;
@property (nonatomic, strong, readonly) UIButton *minusButton;
@property (nonatomic, strong, readonly) UIButton *plusButton;
@property (nonatomic, copy) void (^onChange)(void);
- (instancetype)initWithItem:(RCInlineRowItem *)item compact:(BOOL)compact;
- (void)refresh;
@end

@interface RCInlineRowStepperStrip () <UITextFieldDelegate>
@property (nonatomic, strong) RCInlineRowItem *item;
@property (nonatomic, assign) BOOL compact;
@property (nonatomic, strong) RCInlineRowReadoutControl *valueButton;
@property (nonatomic, strong) NSLayoutConstraint *valueRowCenterXConstraint;
@property (nonatomic, strong) UITextField *field;
- (void)stepBy:(double)delta;
- (void)beginTyping;
- (void)finishTyping;
@end

@implementation RCInlineRowStepperStrip

- (instancetype)initWithItem:(RCInlineRowItem *)item compact:(BOOL)compact {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _item = item;
        _compact = compact;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [UIColor secondarySystemFillColor];
        self.layer.cornerRadius = compact ? 12 : 16;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        CGFloat side = compact ? 38 : 46;
        CGFloat inset = compact ? 10 : 14;

        _minusButton = [self stepButtonNamed:@"minus" label:(compact ? @"Decrease" : @"Decrease by one step") side:side];
        _plusButton = [self stepButtonNamed:@"plus" label:(compact ? @"Increase" : @"Increase by one step") side:side];
        [_minusButton addTarget:self action:@selector(stepDown) forControlEvents:UIControlEventTouchUpInside];
        [_plusButton addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside];

        _readout = RCInlineRowEditorLabel(nil, RCInlineRowEditorDigitFontSized(compact ? 26 : 34, compact ? UIFontTextStyleTitle2 : UIFontTextStyleTitle1, UIFontWeightSemibold), [UIColor labelColor]);
        _readout.adjustsFontSizeToFitWidth = YES;
        _readout.minimumScaleFactor = 0.5;
        [_readout setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
        [_readout setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

        _unitLabel = RCInlineRowEditorLabel(item.unit, RCInlineRowEditorFont(UIFontTextStyleSubheadline, UIFontWeightRegular), [UIColor secondaryLabelColor]);

        UIStackView *valueRow = [[UIStackView alloc] initWithArrangedSubviews:@[_readout, _unitLabel]];
        valueRow.axis = UILayoutConstraintAxisHorizontal;
        valueRow.alignment = UIStackViewAlignmentLastBaseline;
        valueRow.spacing = 3;
        valueRow.userInteractionEnabled = NO;
        valueRow.translatesAutoresizingMaskIntoConstraints = NO;

        _valueButton = [[RCInlineRowReadoutControl alloc] init];
        _valueButton.translatesAutoresizingMaskIntoConstraints = NO;
        _valueButton.isAccessibilityElement = YES;
        _valueButton.accessibilityTraits = UIAccessibilityTraitButton;
        _valueButton.accessibilityHint = @"Double tap to type an exact value";
        [_valueButton addTarget:self action:@selector(beginTyping) forControlEvents:UIControlEventTouchUpInside];
        [_valueButton addSubview:valueRow];

        _valueRowCenterXConstraint = [valueRow.centerXAnchor constraintEqualToAnchor:_valueButton.centerXAnchor];
        _valueRowCenterXConstraint.priority = UILayoutPriorityDefaultHigh;

        _field = [[UITextField alloc] init];
        _field.font = RCInlineRowEditorDigitFontSized(compact ? 26 : 34, compact ? UIFontTextStyleTitle2 : UIFontTextStyleTitle1, UIFontWeightSemibold);
        _field.adjustsFontSizeToFitWidth = YES;
        _field.minimumFontSize = 14;
        _field.textColor = [UIColor labelColor];
        _field.tintColor = [UIColor systemBlueColor];
        _field.backgroundColor = [UIColor tertiarySystemFillColor];
        _field.layer.cornerRadius = compact ? 8 : 10;
        _field.layer.cornerCurve = kCACornerCurveContinuous;
        _field.clipsToBounds = YES;
        _field.textAlignment = NSTextAlignmentCenter;
        _field.keyboardType = item.allowsDecimals ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.spellCheckingType = UITextSpellCheckingTypeNo;
        _field.returnKeyType = UIReturnKeyDone;
        _field.delegate = self;
        _field.hidden = YES;
        _field.translatesAutoresizingMaskIntoConstraints = NO;
        _field.accessibilityLabel = item.caption.length ? [item.caption stringByAppendingString:@" value"] : @"Value";
        [_field addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];

        UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
        [toolbar sizeToFit];
        toolbar.items = @[
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finishTyping)],
        ];
        _field.inputAccessoryView = toolbar;

        [self addSubview:_minusButton];
        [self addSubview:_plusButton];
        [self addSubview:_valueButton];
        [self addSubview:_field];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:compact ? 56 : 92],
            [_minusButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:inset],
            [_minusButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_minusButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:inset],
            [_plusButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-inset],
            [_plusButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_plusButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:inset],
            [_valueButton.leadingAnchor constraintEqualToAnchor:_minusButton.trailingAnchor constant:6],
            [_valueButton.trailingAnchor constraintEqualToAnchor:_plusButton.leadingAnchor constant:-6],
            [_valueButton.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_valueButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            _valueRowCenterXConstraint,
            [valueRow.centerYAnchor constraintEqualToAnchor:_valueButton.centerYAnchor],
            [valueRow.topAnchor constraintGreaterThanOrEqualToAnchor:_valueButton.topAnchor constant:inset],
            [valueRow.bottomAnchor constraintLessThanOrEqualToAnchor:_valueButton.bottomAnchor constant:-inset],
            [valueRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:_valueButton.leadingAnchor constant:4],
            [valueRow.trailingAnchor constraintLessThanOrEqualToAnchor:_valueButton.trailingAnchor constant:-4],
            [_field.leadingAnchor constraintEqualToAnchor:_minusButton.trailingAnchor constant:10],
            [_field.trailingAnchor constraintEqualToAnchor:_plusButton.leadingAnchor constant:-10],
            [_field.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_field.heightAnchor constraintEqualToConstant:compact ? 38 : 48],
        ]];
        [self refresh];
    }
    return self;
}

- (UIButton *)stepButtonNamed:(NSString *)symbol label:(NSString *)label side:(CGFloat)side {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:RCInlineRowEditorSymbol(symbol, side >= 44 ? 18 : 15, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = side / 2;
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:side],
        [button.heightAnchor constraintEqualToConstant:side],
    ]];
    return button;
}

- (void)beginTyping {
    if (self.item.variableName.length) {
        self.field.text = @"";
        self.field.placeholder = [self.item editableNumberText];
    } else {
        self.field.text = [self.item numberText];
        self.field.placeholder = nil;
    }
    self.valueButton.hidden = YES;
    self.field.hidden = NO;
    [self.field becomeFirstResponder];
}

- (void)finishTyping {
    [self.field resignFirstResponder];
}

- (void)fieldChanged {
    [self.item applyEditableNumberText:self.field.text];
    RCInlineRowNotifyValueChanged(self.item);
    if (self.onChange) self.onChange();
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    // Clamp typed values into [min, max] when editing ends so out-of-range inputs snap cleanly
    // instead of being discarded on fold.
    if (!self.item.variableName.length) {
        double maxVal = MAX(self.item.minimumValue, self.item.maximumValue);
        self.item.numberValue = MAX(self.item.minimumValue, MIN(maxVal, self.item.numberValue));
    }
    self.field.hidden = YES;
    self.valueButton.hidden = NO;
    [self refresh];
    RCInlineRowNotifyValueChanged(self.item);
    if (self.onChange) self.onChange();
}

- (void)stepDown {
    [self stepBy:-self.item.step];
}

- (void)stepUp {
    [self stepBy:self.item.step];
}

- (void)stepBy:(double)delta {
    if (self.field.isFirstResponder) [self.field resignFirstResponder];
    double value = self.item.numberValue + delta;
    self.item.variableName = nil;
    self.item.numberValue = MAX(self.item.minimumValue, MIN(MAX(self.item.minimumValue, self.item.maximumValue), value));
    [self refresh];
    RCInlineRowEditorImpact();
    RCInlineRowNotifyValueChanged(self.item);
    if (self.onChange) self.onChange();
}

- (void)refresh {
    if (self.item.variableName.length) {
        self.readout.font = RCInlineRowEditorMonoFontSized(self.compact ? 20 : 22, UIFontTextStyleTitle3, UIFontWeightSemibold);
        self.readout.text = [NSString stringWithFormat:@"{%@}", self.item.variableName];
        self.unitLabel.hidden = YES;
        self.valueRowCenterXConstraint.constant = -7.0;
        self.minusButton.enabled = NO;
        self.plusButton.enabled = NO;
    } else {
        self.readout.font = RCInlineRowEditorDigitFontSized(self.compact ? 26 : 34, self.compact ? UIFontTextStyleTitle2 : UIFontTextStyleTitle1, UIFontWeightSemibold);
        self.readout.text = [self.item numberText];
        self.unitLabel.text = self.item.unit;
        self.unitLabel.hidden = self.item.unit.length == 0;
        self.valueRowCenterXConstraint.constant = 0.0;
        self.minusButton.enabled = self.item.numberValue > self.item.minimumValue;
        self.plusButton.enabled = self.item.numberValue < self.item.maximumValue;
    }
    self.valueButton.accessibilityLabel = [self.item displayValue];
    self.minusButton.alpha = self.minusButton.enabled ? 1.0 : 0.35;
    self.plusButton.alpha = self.plusButton.enabled ? 1.0 : 0.35;
}

@end

#pragma mark - The exact field

@interface RCInlineRowExactField : UIView
@property (nonatomic, strong, readonly) UITextField *field;
@property (nonatomic, copy) void (^onChange)(void);
@property (nonatomic, copy) void (^onCommit)(void);
- (instancetype)initWithItem:(RCInlineRowItem *)item compact:(BOOL)compact;
- (void)refresh;
@end

@interface RCInlineRowExactField () <UITextFieldDelegate>
@property (nonatomic, strong) RCInlineRowItem *item;
- (void)fieldChanged;
@end

@implementation RCInlineRowExactField

- (instancetype)initWithItem:(RCInlineRowItem *)item compact:(BOOL)compact {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _item = item;

        UILabel *label = RCInlineRowEditorLabel(@"Exact", RCInlineRowEditorFont(UIFontTextStyleSubheadline, UIFontWeightRegular), [UIColor secondaryLabelColor]);
        [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UIView *well = RCInlineRowEditorWell([UIColor secondarySystemFillColor], 8);

        _field = [[UITextField alloc] init];
        _field.font = RCInlineRowEditorDigitFontSized(15, UIFontTextStyleSubheadline, UIFontWeightRegular);
        _field.textColor = [UIColor labelColor];
        _field.tintColor = [UIColor systemBlueColor];
        _field.textAlignment = NSTextAlignmentRight;
        _field.keyboardType = item.allowsDecimals ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.spellCheckingType = UITextSpellCheckingTypeNo;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;
        _field.translatesAutoresizingMaskIntoConstraints = NO;
        _field.accessibilityLabel = item.caption.length ? [item.caption stringByAppendingString:@" exact value"] : @"Exact value";
        _field.delegate = self;
        [_field addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
        [_field addTarget:self action:@selector(fieldCommitted) forControlEvents:UIControlEventEditingDidEndOnExit];

        [well addSubview:_field];
        [self addSubview:label];
        [self addSubview:well];

        NSLayoutConstraint *wellWidth = [well.widthAnchor constraintEqualToConstant:116];
        wellWidth.priority = 999;
        NSLayoutConstraint *wellLeading = [well.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12];
        wellLeading.priority = 250;

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:36],
            [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [label.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:2],
            [well.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [well.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [well.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
            [well.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor],
            [well.heightAnchor constraintGreaterThanOrEqualToConstant:36],
            [well.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:12],
            [_field.leadingAnchor constraintEqualToAnchor:well.leadingAnchor constant:10],
            [_field.trailingAnchor constraintEqualToAnchor:well.trailingAnchor constant:-10],
            [_field.topAnchor constraintEqualToAnchor:well.topAnchor],
            [_field.bottomAnchor constraintEqualToAnchor:well.bottomAnchor],
        ]];
        if (compact) wellLeading.active = YES;
        else wellWidth.active = YES;
        [self refresh];
    }
    return self;
}

- (void)refresh {
    if (self.field.isFirstResponder) return;
    self.field.text = [self.item editableNumberText];
}

- (void)fieldChanged {
    [self.item applyEditableNumberText:self.field.text];
    RCInlineRowNotifyValueChanged(self.item);
    if (self.onChange) self.onChange();
}

- (void)fieldCommitted {
    if (self.onCommit) self.onCommit();
}

// Return, or the keyboard going away: the value is ready to keep
- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField.window && self.onCommit) self.onCommit();
}

@end

#pragma mark - A choice, short and long

@interface RCInlineRowChoiceChip : UIControl
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, assign, getter=isChosen) BOOL chosen;
- (instancetype)initWithTitle:(NSString *)title;
@end

@implementation RCInlineRowChoiceChip

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityLabel = title;
        self.layer.cornerRadius = 10;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1.5;

        _titleLabel = RCInlineRowEditorLabel(title, RCInlineRowEditorFont(UIFontTextStyleSubheadline, UIFontWeightSemibold), [UIColor labelColor]);
        _titleLabel.numberOfLines = 0;
        _titleLabel.textAlignment = NSTextAlignmentCenter;

        [self addSubview:_titleLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:40],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_titleLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:9],
            [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-9],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        [self applyLook];
    }
    return self;
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [self applyLook];
}

- (void)applyLook {
    UIColor *accent = RCInlineRowEditorAccent(self);
    self.backgroundColor = self.isChosen ? [accent colorWithAlphaComponent:0.16] : [UIColor secondarySystemFillColor];
    self.layer.borderColor = (self.isChosen ? accent : [UIColor clearColor]).CGColor;
    self.titleLabel.textColor = self.isChosen ? accent : [UIColor labelColor];
    self.accessibilityTraits = self.isChosen ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.borderColor = (self.isChosen ? RCInlineRowEditorAccent(self) : [UIColor clearColor]).CGColor;
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self applyLook];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}

@end

@interface RCInlineRowOptionRow : UIControl
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UIImageView *checkView;
@property (nonatomic, assign, getter=isChosen) BOOL chosen;
- (instancetype)initWithTitle:(NSString *)title;
@end

@implementation RCInlineRowOptionRow

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityLabel = title;

        _titleLabel = RCInlineRowEditorLabel(title, RCInlineRowEditorFont(UIFontTextStyleBody, UIFontWeightRegular), [UIColor labelColor]);
        _titleLabel.numberOfLines = 0;

        _checkView = [[UIImageView alloc] initWithImage:RCInlineRowEditorSymbol(@"checkmark", 15, UIImageSymbolWeightSemibold)];
        _checkView.contentMode = UIViewContentModeScaleAspectFit;
        _checkView.translatesAutoresizingMaskIntoConstraints = NO;
        _checkView.hidden = YES;

        [self addSubview:_titleLabel];
        [self addSubview:_checkView];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:52],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_titleLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:14],
            [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-14],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_checkView.leadingAnchor constant:-12],
            [_checkView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [_checkView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_checkView.widthAnchor constraintEqualToConstant:18],
            [_checkView.heightAnchor constraintEqualToConstant:18],
        ]];
        [self applyLook];
    }
    return self;
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [self applyLook];
}

- (void)applyLook {
    UIColor *accent = RCInlineRowEditorAccent(self);
    self.checkView.hidden = !self.isChosen;
    self.checkView.tintColor = accent;
    self.titleLabel.textColor = self.isChosen ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    self.backgroundColor = self.isChosen ? [accent colorWithAlphaComponent:0.10] : [UIColor clearColor];
    self.accessibilityTraits = self.isChosen ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self applyLook];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}

@end

#pragma mark - The editor

@interface RCInlineRowEditor () <UITextFieldDelegate>
@property (nonatomic, strong) RCInlineRowItem *item;
@property (nonatomic, assign) RCInlineRowEditorStyle style;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIButton *variableButton;
@property (nonatomic, strong) RCInlineRowStepperStrip *stepper;
@property (nonatomic, strong) RCInlineRowExactField *exactRow;
@property (nonatomic, strong) NSArray<RCInlineRowChoiceChip *> *choiceChips;
@property (nonatomic, strong) NSArray<RCInlineRowOptionRow *> *optionRows;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, copy) NSArray<NSString *> *runNames;
@property (nonatomic, copy) NSArray<NSString *> *savedNames;
- (void)collectVariableNames:(NSArray *)otherActions;
- (BOOL)isCompact;
- (UIView *)captionRow;
- (UIView *)choiceEditor;
- (UIView *)textEditor;
- (void)installVariableMenu;
- (void)insertVariableNamed:(NSString *)name;
- (void)loadSavedNames;
- (void)choiceTapped:(RCInlineRowChoiceChip *)chip;
- (void)optionTapped:(RCInlineRowOptionRow *)row;
- (void)textChanged;
- (void)reportChange;
- (void)reportCommit;
@end

@implementation RCInlineRowEditor

- (instancetype)initWithItem:(RCInlineRowItem *)item {
    return [self initWithItem:item style:RCInlineRowEditorStyleCompact otherActions:nil];
}

- (instancetype)initWithItem:(RCInlineRowItem *)item style:(RCInlineRowEditorStyle)style otherActions:(NSArray *)otherActions {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _item = item;
        _style = style;
        [self collectVariableNames:otherActions];
        self.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = [self isCompact] ? 10 : 12;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        __weak typeof(self) weakSelf = self;

        if (item.kind != RCInlineRowKindChoice) {
            [stack addArrangedSubview:[self captionRow]];
        } else {
            UILabel *caption = RCInlineRowEditorLabel(item.caption, RCInlineRowEditorFont(UIFontTextStyleSubheadline, UIFontWeightSemibold), [UIColor secondaryLabelColor]);
            caption.numberOfLines = 0;
            [stack addArrangedSubview:caption];
        }

        if (item.kind == RCInlineRowKindNumber) {
            self.stepper = [[RCInlineRowStepperStrip alloc] initWithItem:item compact:[self isCompact]];
            self.stepper.onChange = ^{ [weakSelf refresh]; [weakSelf reportChange]; };
            [stack addArrangedSubview:self.stepper];

            if (![self isCompact]) {
                self.exactRow = [[RCInlineRowExactField alloc] initWithItem:item compact:NO];
                self.exactRow.onChange = ^{ [weakSelf refresh]; [weakSelf reportChange]; };
                self.exactRow.onCommit = ^{ [weakSelf reportCommit]; };
                [stack addArrangedSubview:self.exactRow];

                NSString *step = [NSString stringWithFormat:@"%g", item.step];
                [stack addArrangedSubview:RCInlineRowEditorNote([NSString stringWithFormat:@"Steps by %@%@. Tap the number or type an exact value, or use + for a variable.", step, RCInlineRowEditorUnitSuffix(item)])];
            }
        } else if (item.kind == RCInlineRowKindChoice) {
            [stack addArrangedSubview:[self choiceEditor]];
            if (![self isCompact]) [stack addArrangedSubview:RCInlineRowEditorNote(@"Tap an option. The row shows the chosen one.")];
        } else {
            [stack addArrangedSubview:[self textEditor]];
            if (![self isCompact]) [stack addArrangedSubview:RCInlineRowEditorNote(@"One line. Return closes the keyboard.")];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillChange:)
                                                     name:UIKeyboardWillChangeFrameNotification
                                                   object:nil];
        [self loadSavedNames];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isCompact {
    return self.style == RCInlineRowEditorStyleCompact;
}

// The variables this trigger sets, split the way the number sheet splits them
- (void)collectVariableNames:(NSArray *)otherActions {
    NSMutableOrderedSet *run = [NSMutableOrderedSet orderedSet], *saved = [NSMutableOrderedSet orderedSet];
    for (id item in otherActions) {
        if (![item isKindOfClass:[NSDictionary class]] || ![[item[@"type"] description] isEqualToString:@"set_variable"]) continue;
        NSString *name = [item[@"name"] description];
        if (!RCSetVariableNameValid(name)) continue;
        if ([[item[@"scope"] description] isEqualToString:@"run"]) [run addObject:name];
        else [saved addObject:name];
    }
    self.runNames = [[run array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.savedNames = [[saved array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

// The caption on the left, the + menu for a variable on the right
- (UIView *)captionRow {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    self.captionLabel = RCInlineRowEditorLabel(self.item.caption, RCInlineRowEditorFont(UIFontTextStyleSubheadline, UIFontWeightSemibold), [UIColor secondaryLabelColor]);
    self.captionLabel.numberOfLines = 0;

    UIButton *insert = [UIButton buttonWithType:UIButtonTypeSystem];
    [insert setImage:RCInlineRowEditorSymbol(@"plus.circle", 18, UIImageSymbolWeightMedium) forState:UIControlStateNormal];
    insert.accessibilityLabel = @"Insert Variable";
    insert.showsMenuAsPrimaryAction = YES;
    insert.translatesAutoresizingMaskIntoConstraints = NO;
    self.variableButton = insert;
    [self installVariableMenu];

    [row addSubview:self.captionLabel];
    [row addSubview:insert];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:34],
        [self.captionLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [self.captionLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [self.captionLabel.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:2],
        [self.captionLabel.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-2],
        [self.captionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:insert.leadingAnchor constant:-8],
        [insert.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [insert.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [insert.widthAnchor constraintEqualToConstant:34],
        [insert.heightAnchor constraintEqualToConstant:34],
    ]];
    return row;
}

// The choices as chips when they are short and few, as a list when they are not
- (UIView *)choiceEditor {
    if (self.item.options.count <= 3) {
        UIStackView *chipRow = [[UIStackView alloc] init];
        chipRow.axis = UILayoutConstraintAxisHorizontal;
        chipRow.spacing = 8;
        chipRow.distribution = UIStackViewDistributionFillEqually;
        chipRow.translatesAutoresizingMaskIntoConstraints = NO;

        NSMutableArray *chips = [NSMutableArray array];
        for (NSUInteger i = 0; i < self.item.options.count; i++) {
            RCInlineRowChoiceChip *chip = [[RCInlineRowChoiceChip alloc] initWithTitle:self.item.options[i]];
            chip.tag = (NSInteger)i;
            chip.chosen = ((NSInteger)i == self.item.choiceIndex);
            [chip addTarget:self action:@selector(choiceTapped:) forControlEvents:UIControlEventTouchUpInside];
            [chipRow addArrangedSubview:chip];
            [chips addObject:chip];
        }
        self.choiceChips = chips;
        return chipRow;
    }

    UIView *list = RCInlineRowEditorWell([self isCompact] ? [UIColor secondarySystemFillColor] : [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12], 12);
    UIStackView *listStack = [[UIStackView alloc] init];
    listStack.axis = UILayoutConstraintAxisVertical;
    listStack.spacing = 0;
    listStack.translatesAutoresizingMaskIntoConstraints = NO;
    [list addSubview:listStack];
    [NSLayoutConstraint activateConstraints:@[
        [listStack.leadingAnchor constraintEqualToAnchor:list.leadingAnchor],
        [listStack.trailingAnchor constraintEqualToAnchor:list.trailingAnchor],
        [listStack.topAnchor constraintEqualToAnchor:list.topAnchor],
        [listStack.bottomAnchor constraintEqualToAnchor:list.bottomAnchor],
    ]];

    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.item.options.count; i++) {
        if (i > 0) {
            UIView *box = [[UIView alloc] init];
            box.translatesAutoresizingMaskIntoConstraints = NO;
            UIView *line = [[UIView alloc] init];
            line.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"separators" defaultVal:0.30];
            line.translatesAutoresizingMaskIntoConstraints = NO;
            [box addSubview:line];
            [NSLayoutConstraint activateConstraints:@[
                [box.heightAnchor constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale],
                [line.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:16],
                [line.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
                [line.topAnchor constraintEqualToAnchor:box.topAnchor],
                [line.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
            ]];
            [listStack addArrangedSubview:box];
        }
        RCInlineRowOptionRow *row = [[RCInlineRowOptionRow alloc] initWithTitle:self.item.options[i]];
        row.tag = (NSInteger)i;
        row.chosen = ((NSInteger)i == self.item.choiceIndex);
        [row addTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [listStack addArrangedSubview:row];
        [rows addObject:row];
    }
    self.optionRows = rows;
    return list;
}

- (UIView *)textEditor {
    UIView *well = RCInlineRowEditorWell([UIColor secondarySystemFillColor], 10);
    CGFloat height = [self isCompact] ? 46 : 52;
    CGFloat inset = [self isCompact] ? 12 : 14;

    UITextField *field = [[UITextField alloc] init];
    field.font = RCInlineRowEditorFont(UIFontTextStyleBody, UIFontWeightRegular);
    field.textColor = [UIColor labelColor];
    field.tintColor = [UIColor systemBlueColor];
    field.placeholder = self.item.placeholder;
    field.text = self.item.textValue;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.returnKeyType = UIReturnKeyDone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.accessibilityLabel = self.item.caption.length ? self.item.caption : self.item.name;
    field.delegate = self;
    [field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
    [field addTarget:self action:@selector(dismissKeyboard) forControlEvents:UIControlEventEditingDidEndOnExit];
    self.textField = field;

    [well addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [well.heightAnchor constraintGreaterThanOrEqualToConstant:height],
        [field.leadingAnchor constraintEqualToAnchor:well.leadingAnchor constant:inset],
        [field.trailingAnchor constraintEqualToAnchor:well.trailingAnchor constant:-inset],
        [field.topAnchor constraintEqualToAnchor:well.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:well.bottomAnchor],
    ]];
    return well;
}

- (void)choiceTapped:(RCInlineRowChoiceChip *)chip {
    if (chip.tag < 0 || chip.tag >= (NSInteger)self.item.options.count) return;
    self.item.choiceIndex = chip.tag;
    for (RCInlineRowChoiceChip *other in self.choiceChips) other.chosen = (other == chip);
    RCInlineRowEditorSelectTick();
    RCInlineRowNotifyValueChanged(self.item);
    [self reportChange];
}

- (void)optionTapped:(RCInlineRowOptionRow *)row {
    if (row.tag < 0 || row.tag >= (NSInteger)self.item.options.count) return;
    self.item.choiceIndex = row.tag;
    for (RCInlineRowOptionRow *other in self.optionRows) other.chosen = (other == row);
    RCInlineRowEditorSelectTick();
    RCInlineRowNotifyValueChanged(self.item);
    [self reportChange];
}

- (void)textChanged {
    self.item.textValue = self.textField.text ?: @"";
    RCInlineRowNotifyValueChanged(self.item);
    [self reportChange];
}

- (void)dismissKeyboard {
    [self.textField resignFirstResponder];
}

// Return, or the keyboard going away: the value is ready to keep
- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField.window) [self reportCommit];
}

- (void)reportChange {
    if (self.onChange) self.onChange();
}

- (void)reportCommit {
    if (self.onCommit) self.onCommit();
}

- (void)refresh {
    self.captionLabel.text = self.item.caption;
    [self.stepper refresh];
    [self.exactRow refresh];
    for (RCInlineRowChoiceChip *chip in self.choiceChips) {
        chip.chosen = (chip.tag == self.item.choiceIndex);
    }
    for (RCInlineRowOptionRow *row in self.optionRows) {
        row.chosen = (row.tag == self.item.choiceIndex);
    }
    if (self.textField && !self.textField.isFirstResponder) self.textField.text = self.item.textValue;
}

- (void)endEditing {
    [self endEditing:YES];
}

#pragma mark The variable menu

// The + menu is a fixed shell whose entries are built when the menu opens, not when it closes.
// The saved names arrive from the server a moment later, and handing an open button a new menu
// dismisses that menu (and the editor with it), so the button's menu is never replaced.
- (void)installVariableMenu {
    if (!self.variableButton) return;
    __weak typeof(self) weakSelf = self;
    void (^provide)(void (^)(NSArray<UIMenuElement *> *)) = ^(void (^completion)(NSArray<UIMenuElement *> *elements)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { completion(@[]); return; }
        BOOL round = strongSelf.item.kind == RCInlineRowKindNumber && strongSelf.item.allowsRound;
        UIMenu *menu = RCVariableInsertMenuWithRound(strongSelf.runNames, strongSelf.savedNames, round, ^(NSString *name) {
            [strongSelf insertVariableNamed:name];
        });
        completion(menu.children ?: @[]);
    };
    UIDeferredMenuElement *variables = nil;
    if (@available(iOS 15.0, *)) {
        variables = [UIDeferredMenuElement elementWithUncachedProvider:provide];
    } else {
        variables = [UIDeferredMenuElement elementWithProvider:provide];
    }
    self.variableButton.menu = [UIMenu menuWithTitle:@"" children:@[variables]];
}

// A picked variable takes the value's place. In a number field that is the whole number; in a
// text field the variable is the text.
- (void)insertVariableNamed:(NSString *)name {
    NSString *text = [NSString stringWithFormat:@"{%@}", name];
    if (self.item.kind == RCInlineRowKindText) {
        self.item.textValue = text;
        self.textField.text = text;
    } else {
        self.item.variableName = name;
        [self endEditing:YES];
        [self refresh];
    }
    RCInlineRowEditorImpact();
    RCInlineRowNotifyValueChanged(self.item);
    [self reportChange];
}

- (void)loadSavedNames {
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"var list" completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![parsed isKindOfClass:[NSDictionary class]] || ![parsed count]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:[parsed allKeys]];
            [all addObjectsFromArray:strongSelf.savedNames ?: @[]];
            [all minusSet:[NSSet setWithArray:strongSelf.runNames ?: @[]]];
            strongSelf.savedNames = [all.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        });
    }];
}

#pragma mark The keyboard

// A text field or the exact field near the bottom would sit under the keyboard. The editor finds
// the scroll view it lives in and brings the field into the part of it the keyboard leaves.
- (UIView *)firstResponderInView:(UIView *)view {
    if (view.isFirstResponder) return view;
    for (UIView *subview in view.subviews) {
        UIView *found = [self firstResponderInView:subview];
        if (found) return found;
    }
    return nil;
}

- (UIScrollView *)enclosingScrollView {
    for (UIView *view = self.superview; view; view = view.superview) {
        if ([view isKindOfClass:[UIScrollView class]]) return (UIScrollView *)view;
    }
    return nil;
}

- (void)keyboardWillChange:(NSNotification *)note {
    UIView *field = [self firstResponderInView:self];
    if (!field || !self.window) return;
    UIScrollView *scroll = [self enclosingScrollView];
    if (!scroll) return;

    CGRect keyboardOnScreen = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardInWindow = [self.window convertRect:keyboardOnScreen fromCoordinateSpace:self.window.screen.coordinateSpace];
    CGRect keyboardInScroll = [scroll convertRect:keyboardInWindow fromView:self.window];
    CGRect fieldInScroll = [field convertRect:field.bounds toView:scroll];

    CGFloat bottom = CGRectGetMinY(keyboardInScroll) - 12.0;
    CGFloat top = scroll.contentOffset.y + scroll.adjustedContentInset.top + 8.0;
    CGFloat delta = 0;
    if (CGRectGetMaxY(fieldInScroll) > bottom) delta = CGRectGetMaxY(fieldInScroll) - bottom;
    else if (CGRectGetMinY(fieldInScroll) < top) delta = CGRectGetMinY(fieldInScroll) - top;
    if (fabs(delta) < 1.0) return;

    CGPoint offset = scroll.contentOffset;
    offset.y += delta;
    CGFloat minimum = -scroll.adjustedContentInset.top;
    CGFloat maximum = MAX(minimum, scroll.contentSize.height - scroll.bounds.size.height + scroll.adjustedContentInset.bottom);
    offset.y = MAX(minimum, MIN(maximum, offset.y));

    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options = (UIViewAnimationOptions)([note.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16);
    [UIView animateWithDuration:duration delay:0 options:options animations:^{
        scroll.contentOffset = offset;
    } completion:nil];
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width {
    if (width <= 0) return 0;
    return ceil([self systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                    withHorizontalFittingPriority:UILayoutPriorityRequired
                          verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height);
}

@end
