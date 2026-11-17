#import "RCDelayPrototypeGalleryViewController.h"
#import "RCConfigManager.h"
#import "RCVariableEditorParts.h"
#import "RCDelayPrototypeKit.h"
#import "RCDelayStepperVariations.h"

#import <math.h>

// ---------------------------------------------------------------------------
// TEMPORARY DESIGN PROTOTYPE
//
// Six takes on the Delay panel, then six variations on the Stepper (C1-C6).
// width; tapping a card opens that panel alone, fully interactive, in the same
// half-height sheet the real Delay editor uses.
//
// Nothing in this file is referenced by the shipping Delay flow. The only
// existing file touched is RCAdvancedSettingsViewController, for the entry row.
// ---------------------------------------------------------------------------


#pragma mark - A. The shipping inset row

@interface RCDelayBaselinePanel : RCDelayVariantView
@property (nonatomic, strong) UITextField *field;
@end

@implementation RCDelayBaselinePanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 8;
        stack.layoutMarginsRelativeArrangement = YES;
        stack.layoutMargins = UIEdgeInsetsMake(18, 16, 16, 16);
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        UIView *row = [[UIView alloc] init];
        row.backgroundColor = RCDelayBlockColor();
        row.layer.cornerRadius = 12;
        row.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *label = [[UILabel alloc] init];
        label.text = @"Seconds";
        label.font = RCDelayFont(UIFontTextStyleBody, UIFontWeightRegular);
        label.textColor = [UIColor labelColor];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        self.field = [self makeNumberField];
        self.field.rightView = [self makeVariableButton];
        self.field.rightViewMode = UITextFieldViewModeAlways;
        [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];

        [row addSubview:label];
        [row addSubview:self.field];
        [NSLayoutConstraint activateConstraints:@[
            [row.heightAnchor constraintGreaterThanOrEqualToConstant:52],
            [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
            [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [label.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:6],
            [label.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-6],
            [self.field.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:12],
            [self.field.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8],
            [self.field.topAnchor constraintEqualToAnchor:row.topAnchor],
            [self.field.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        ]];

        [stack addArrangedSubview:row];
        [stack addArrangedSubview:RCDelayNoteLabel(@"How long to wait before the next action, up to a day.")];
        self.field.text = self.valueText;
    }
    return self;
}

- (void)textChanged {
    self.valueText = self.field.text ?: @"";
}

- (void)valueTextDidChange {
    if (![self.field.text isEqualToString:self.valueText]) self.field.text = self.valueText;
}

@end

#pragma mark - Preset chip

@interface RCDelayChipButton : UIButton
@property (nonatomic, assign, getter=isChosen) BOOL chosen;
@end

@implementation RCDelayChipButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.titleLabel.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.8;
        self.layer.masksToBounds = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self applyLook];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + 22, MAX(34, size.height + 12));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetMidY(self.bounds);
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [self applyLook];
}

- (void)applyLook {
    UIColor *accent = RCDelayAccent(self);
    self.backgroundColor = self.isChosen ? [accent colorWithAlphaComponent:0.18] : [UIColor tertiarySystemFillColor];
    [self setTitleColor:(self.isChosen ? accent : [UIColor labelColor]) forState:UIControlStateNormal];
    self.layer.borderWidth = self.isChosen ? 1.5 : 0;
    self.layer.borderColor = accent.CGColor;
    if (self.isChosen) self.accessibilityTraits |= UIAccessibilityTraitSelected;
    else self.accessibilityTraits &= ~UIAccessibilityTraitSelected;
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

#pragma mark - B. Field plus preset chips

@interface RCDelayPresetsPanel : RCDelayVariantView
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) NSArray<NSNumber *> *presets;
@property (nonatomic, strong) NSMutableArray<RCDelayChipButton *> *chips;
@end

@implementation RCDelayPresetsPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.presets = @[@0.5, @1, @2, @5, @10];
        self.chips = [NSMutableArray array];

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 10;
        stack.layoutMarginsRelativeArrangement = YES;
        stack.layoutMargins = UIEdgeInsetsMake(18, 16, 16, 16);
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        UIView *row = [[UIView alloc] init];
        row.backgroundColor = RCDelayBlockColor();
        row.layer.cornerRadius = 12;
        row.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *label = [[UILabel alloc] init];
        label.text = @"Seconds";
        label.font = RCDelayFont(UIFontTextStyleBody, UIFontWeightRegular);
        label.textColor = [UIColor labelColor];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        self.field = [self makeNumberField];
        self.field.rightView = [self makeVariableButton];
        self.field.rightViewMode = UITextFieldViewModeAlways;
        [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];

        [row addSubview:label];
        [row addSubview:self.field];
        [NSLayoutConstraint activateConstraints:@[
            [row.heightAnchor constraintGreaterThanOrEqualToConstant:52],
            [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
            [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [label.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:6],
            [label.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-6],
            [self.field.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:12],
            [self.field.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8],
            [self.field.topAnchor constraintEqualToAnchor:row.topAnchor],
            [self.field.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        ]];

        UIStackView *chipRow = [[UIStackView alloc] init];
        chipRow.axis = UILayoutConstraintAxisHorizontal;
        chipRow.spacing = 8;
        chipRow.distribution = UIStackViewDistributionFillEqually;
        chipRow.translatesAutoresizingMaskIntoConstraints = NO;
        [chipRow.heightAnchor constraintEqualToConstant:36].active = YES;

        for (NSUInteger i = 0; i < self.presets.count; i++) {
            double preset = self.presets[i].doubleValue;
            RCDelayChipButton *chip = [[RCDelayChipButton alloc] initWithFrame:CGRectZero];
            [chip setTitle:[NSString stringWithFormat:@"%@ s", RCDelayFormat(preset, 1)] forState:UIControlStateNormal];
            chip.tag = (NSInteger)i;
            chip.accessibilityLabel = [NSString stringWithFormat:@"%@ seconds", RCDelayFormat(preset, 1)];
            [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
            [chipRow addArrangedSubview:chip];
            [self.chips addObject:chip];
        }

        [stack addArrangedSubview:row];
        [stack addArrangedSubview:chipRow];
        [stack addArrangedSubview:RCDelayNoteLabel(@"Tap a preset, or type an exact time.")];

        self.field.text = self.valueText;
        [self refreshChips];
    }
    return self;
}

- (void)textChanged {
    self.valueText = self.field.text ?: @"";
}

- (void)chipTapped:(RCDelayChipButton *)chip {
    double preset = self.presets[chip.tag].doubleValue;
    self.valueText = RCDelayFormat(preset, 1);
}

- (void)valueTextDidChange {
    if (![self.field.text isEqualToString:self.valueText]) self.field.text = self.valueText;
    [self refreshChips];
}

- (void)refreshChips {
    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    for (NSUInteger i = 0; i < self.chips.count; i++) {
        double preset = self.presets[i].doubleValue;
        self.chips[i].chosen = numeric && fabs(value - preset) < 0.0001;
    }
}

@end

#pragma mark - C. Big readout with step buttons

@interface RCDelayStepperPanel : RCDelayVariantView
@property (nonatomic, strong) UILabel *readout;
@property (nonatomic, strong) UILabel *unit;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@end

@implementation RCDelayStepperPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 12;
        stack.layoutMarginsRelativeArrangement = YES;
        stack.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        UIView *header = [[UIView alloc] init];
        UILabel *title = [[UILabel alloc] init];
        title.text = @"Seconds";
        title.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
        title.textColor = [UIColor secondaryLabelColor];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        UIButton *variable = [self makeVariableButton];
        variable.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:title];
        [header addSubview:variable];
        [NSLayoutConstraint activateConstraints:@[
            [header.heightAnchor constraintEqualToConstant:34],
            [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
            [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [variable.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
            [variable.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [variable.widthAnchor constraintEqualToConstant:34],
            [variable.heightAnchor constraintEqualToConstant:34],
        ]];

        UIView *hero = [[UIView alloc] init];
        hero.backgroundColor = RCDelayBlockColor();
        hero.layer.cornerRadius = 16;
        hero.translatesAutoresizingMaskIntoConstraints = NO;

        self.minusButton = [self stepButtonNamed:@"minus" label:@"Decrease by half a second"];
        self.plusButton = [self stepButtonNamed:@"plus" label:@"Increase by half a second"];
        [self.minusButton addTarget:self action:@selector(stepDown) forControlEvents:UIControlEventTouchUpInside];
        [self.plusButton addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside];

        self.readout = [[UILabel alloc] init];
        self.readout.font = RCDelayDigitFontOfSize(36, UIFontTextStyleTitle1, UIFontWeightSemibold);
        self.readout.textColor = [UIColor labelColor];
        self.readout.adjustsFontSizeToFitWidth = YES;
        self.readout.minimumScaleFactor = 0.5;
        self.readout.text = self.valueText;
        self.readout.translatesAutoresizingMaskIntoConstraints = NO;
        [self.readout setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
        [self.readout setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

        self.unit = [[UILabel alloc] init];
        self.unit.text = @"s";
        self.unit.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightRegular);
        self.unit.textColor = [UIColor secondaryLabelColor];
        self.unit.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *valueRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.readout, self.unit]];
        valueRow.axis = UILayoutConstraintAxisHorizontal;
        valueRow.alignment = UIStackViewAlignmentLastBaseline;
        valueRow.spacing = 3;
        valueRow.translatesAutoresizingMaskIntoConstraints = NO;

        [hero addSubview:self.minusButton];
        [hero addSubview:self.plusButton];
        [hero addSubview:valueRow];
        [NSLayoutConstraint activateConstraints:@[
            [self.minusButton.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:14],
            [self.minusButton.centerYAnchor constraintEqualToAnchor:hero.centerYAnchor],
            [self.minusButton.topAnchor constraintEqualToAnchor:hero.topAnchor constant:20],
            [self.minusButton.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-20],
            [self.plusButton.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-14],
            [self.plusButton.centerYAnchor constraintEqualToAnchor:hero.centerYAnchor],
            [valueRow.centerXAnchor constraintEqualToAnchor:hero.centerXAnchor],
            [valueRow.centerYAnchor constraintEqualToAnchor:hero.centerYAnchor],
            [valueRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.minusButton.trailingAnchor constant:12],
            [valueRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.plusButton.leadingAnchor constant:-12],
        ]];

        UIView *exact = [[UIView alloc] init];
        exact.backgroundColor = RCDelayBlockColor();
        exact.layer.cornerRadius = 12;
        exact.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *exactLabel = [[UILabel alloc] init];
        exactLabel.text = @"Exact";
        exactLabel.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightRegular);
        exactLabel.textColor = [UIColor secondaryLabelColor];
        exactLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *well = [[UIView alloc] init];
        well.backgroundColor = [UIColor tertiarySystemFillColor];
        well.layer.cornerRadius = 9;
        well.translatesAutoresizingMaskIntoConstraints = NO;

        self.field = [self makeNumberField];
        [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
        [well addSubview:self.field];
        [exact addSubview:exactLabel];
        [exact addSubview:well];
        [NSLayoutConstraint activateConstraints:@[
            [exact.heightAnchor constraintEqualToConstant:48],
            [exactLabel.leadingAnchor constraintEqualToAnchor:exact.leadingAnchor constant:14],
            [exactLabel.centerYAnchor constraintEqualToAnchor:exact.centerYAnchor],
            [well.trailingAnchor constraintEqualToAnchor:exact.trailingAnchor constant:-6],
            [well.centerYAnchor constraintEqualToAnchor:exact.centerYAnchor],
            [well.widthAnchor constraintEqualToConstant:116],
            [well.heightAnchor constraintEqualToConstant:36],
            [self.field.leadingAnchor constraintEqualToAnchor:well.leadingAnchor constant:10],
            [self.field.trailingAnchor constraintEqualToAnchor:well.trailingAnchor constant:-10],
            [self.field.topAnchor constraintEqualToAnchor:well.topAnchor],
            [self.field.bottomAnchor constraintEqualToAnchor:well.bottomAnchor],
        ]];

        [stack addArrangedSubview:header];
        [stack addArrangedSubview:hero];
        [stack addArrangedSubview:exact];
        [stack addArrangedSubview:RCDelayNoteLabel(@"Steps by half a second. Type a value for anything exact.")];

        self.field.text = self.valueText;
        [self valueTextDidChange];
    }
    return self;
}

- (UIButton *)stepButtonNamed:(NSString *)symbol label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18
                                                                                               weight:UIImageSymbolWeightSemibold]]
            forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = 23;
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:46],
        [button.heightAnchor constraintEqualToConstant:46],
    ]];
    return button;
}

- (void)textChanged {
    self.valueText = self.field.text ?: @"";
}

- (void)stepDown {
    [self stepBy:-0.5];
}

- (void)stepUp {
    [self stepBy:0.5];
}

- (void)stepBy:(double)delta {
    double value = 0;
    if (!RCDelayNumberFromText(self.valueText, &value)) return;
    value = MAX(0, MIN(86400, round((value + delta) * 2) / 2));
    self.valueText = RCDelayFormat(value, 2);
}

- (void)valueTextDidChange {
    if (![self.field.text isEqualToString:self.valueText]) self.field.text = self.valueText;

    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    if (numeric) {
        self.readout.font = RCDelayDigitFontOfSize(36, UIFontTextStyleTitle1, UIFontWeightSemibold);
        self.readout.text = RCDelayFormat(value, 2);
        self.unit.hidden = NO;
        self.minusButton.enabled = value > 0;
        self.plusButton.enabled = value < 86400;
    } else {
        self.readout.font = RCDelayMonoFont(22, UIFontTextStyleTitle3, UIFontWeightSemibold);
        self.readout.text = self.valueText;
        self.unit.hidden = YES;
        self.minusButton.enabled = NO;
        self.plusButton.enabled = NO;
    }
    self.minusButton.alpha = self.minusButton.enabled ? 1.0 : 0.35;
    self.plusButton.alpha = self.plusButton.enabled ? 1.0 : 0.35;
}

@end

#pragma mark - D. Snap ruler with a floating value bubble

@interface RCDelayRulerView : UIControl <UIGestureRecognizerDelegate>
@property (nonatomic, assign) double value;
@property (nonatomic, assign) double minimumValue;
@property (nonatomic, assign) double maximumValue;
@property (nonatomic, assign) BOOL showsVariable;
@property (nonatomic, copy) void (^onScrub)(double value);
@property (nonatomic, copy) void (^onTextChange)(NSString *text);
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UITextField *field;
@end

@implementation RCDelayRulerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _minimumValue = 0;
        _maximumValue = 10;
        _value = 2;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;

        self.bubble = [[UIView alloc] init];
        self.bubble.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.16];
        self.bubble.layer.borderWidth = 1;
        self.bubble.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.55].CGColor;
        self.bubble.userInteractionEnabled = YES;
        [self addSubview:self.bubble];

        self.field = [[UITextField alloc] init];
        self.field.font = RCDelayDigitFont(UIFontTextStyleBody, UIFontWeightSemibold);
        self.field.textColor = [UIColor labelColor];
        self.field.tintColor = [UIColor systemBlueColor];
        self.field.textAlignment = NSTextAlignmentCenter;
        self.field.keyboardType = UIKeyboardTypeDecimalPad;
        self.field.autocorrectionType = UITextAutocorrectionTypeNo;
        self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.field.spellCheckingType = UITextSpellCheckingTypeNo;
        self.field.text = RCDelayFormat(self.value, 1);
        [self.field addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
        [self.bubble addSubview:self.field];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrubbed:)];
        pan.delegate = self;
        [self addGestureRecognizer:pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];

        [self updateAccessibilityValue];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(132, MAX(96, CGRectGetWidth(self.bounds) * 0.36));
    CGFloat height = 36;
    CGFloat inset = width / 2 + 4;
    CGFloat x = [self xForValue:self.value inset:inset] - width / 2;
    self.bubble.frame = CGRectMake(round(x), 2, width, height);
    self.bubble.layer.cornerRadius = height / 2;
    self.field.frame = CGRectMake(12, 0, width - 24, height);
    [self setNeedsDisplay];
}

- (CGFloat)trackInset {
    return MAX(8, CGRectGetWidth(self.bubble.bounds) / 2 + 4);
}

- (CGFloat)xForValue:(double)value inset:(CGFloat)inset {
    CGFloat usable = MAX(1, CGRectGetWidth(self.bounds) - inset * 2);
    double span = self.maximumValue - self.minimumValue;
    double t = span > 0 ? (value - self.minimumValue) / span : 0;
    return inset + (CGFloat)MAX(0, MIN(1, t)) * usable;
}

- (CGFloat)xForValue:(double)value {
    return [self xForValue:value inset:[self trackInset]];
}

- (void)setValue:(double)value {
    _value = MAX(self.minimumValue, MIN(self.maximumValue, value));
    [self setNeedsLayout];
    [self setNeedsDisplay];
    [self updateAccessibilityValue];
}

- (void)setShowsVariable:(BOOL)showsVariable {
    _showsVariable = showsVariable;
    [self setNeedsDisplay];
    [self updateAccessibilityValue];
}

- (void)updateAccessibilityValue {
    self.accessibilityLabel = @"Delay length";
    self.accessibilityValue = self.showsVariable ? self.field.text : [NSString stringWithFormat:@"%@ seconds", RCDelayFormat(self.value, 1)];
}

- (void)drawRect:(CGRect)rect {
    CGFloat baseline = 66;
    CGFloat inset = [self trackInset];
    CGFloat minX = inset;
    CGFloat maxX = CGRectGetWidth(self.bounds) - inset;
    if (maxX <= minX) return;

    CGFloat dim = self.showsVariable ? 0.35 : 1.0;
    UIColor *lineColor = [RCDelaySeparatorColor() colorWithAlphaComponent:dim];
    UIColor *tickColor = [[UIColor secondaryLabelColor] colorWithAlphaComponent:dim];
    UIColor *accent = [RCDelayAccent(self) colorWithAlphaComponent:dim];

    [lineColor setFill];
    UIRectFill(CGRectMake(minX, baseline, maxX - minX, 1));

    UIFont *labelFont = RCDelayFont(UIFontTextStyleCaption2, UIFontWeightRegular);
    NSDictionary *labelAttributes = @{ NSFontAttributeName: labelFont, NSForegroundColorAttributeName: tickColor };

    for (double v = self.minimumValue; v <= self.maximumValue + 0.0001; v += 0.5) {
        CGFloat x = [self xForValue:v];
        BOOL major = fabs(v - round(v)) < 0.001;
        CGFloat height = major ? 10 : 6;
        UIBezierPath *tick = [UIBezierPath bezierPath];
        tick.lineWidth = major ? 1.2 : 1;
        [tick moveToPoint:CGPointMake(round(x) + 0.5, baseline)];
        [tick addLineToPoint:CGPointMake(round(x) + 0.5, baseline - height)];
        [tickColor setStroke];
        [tick stroke];

        if (major) {
            NSString *text = [NSString stringWithFormat:@"%.0f", v];
            CGSize size = [text sizeWithAttributes:labelAttributes];
            [text drawAtPoint:CGPointMake(x - size.width / 2, baseline + 6) withAttributes:labelAttributes];
        }
    }

    CGFloat needleX = round([self xForValue:self.value]) + 0.5;
    UIBezierPath *needle = [UIBezierPath bezierPath];
    needle.lineWidth = 2;
    [needle moveToPoint:CGPointMake(needleX, 42)];
    [needle addLineToPoint:CGPointMake(needleX, baseline)];
    [accent setStroke];
    [needle stroke];

    [accent setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(needleX - 4, 42, 8, 8)] fill];
}

- (void)fieldChanged {
    double value = 0;
    if (RCDelayNumberFromText(self.field.text, &value)) {
        _value = MAX(self.minimumValue, MIN(self.maximumValue, value));
        [self setNeedsLayout];
        [self setNeedsDisplay];
        [self updateAccessibilityValue];
    }
    if (self.onTextChange) self.onTextChange(self.field.text ?: @"");
}

- (void)scrubbed:(UIPanGestureRecognizer *)pan {
    [self setValueFromPoint:[pan locationInView:self]];
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    [self setValueFromPoint:[tap locationInView:self]];
}

- (void)setValueFromPoint:(CGPoint)point {
    CGFloat inset = [self trackInset];
    CGFloat usable = MAX(1, CGRectGetWidth(self.bounds) - inset * 2);
    CGFloat t = MAX(0, MIN(1, (point.x - inset) / usable));
    double span = self.maximumValue - self.minimumValue;
    double value = self.minimumValue + t * span;
    value = round(value * 2) / 2;
    if (fabs(value - self.value) < 0.0001) return;
    self.value = value;
    [self updateAccessibilityValue];
    if (self.onScrub) self.onScrub(value);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isDescendantOfView:self.bubble];
}

- (void)accessibilityIncrement {
    self.value = MIN(self.maximumValue, self.value + 0.5);
    if (self.onScrub) self.onScrub(self.value);
}

- (void)accessibilityDecrement {
    self.value = MAX(self.minimumValue, self.value - 0.5);
    if (self.onScrub) self.onScrub(self.value);
}

@end

@interface RCDelayRulerPanel : RCDelayVariantView
@property (nonatomic, strong) RCDelayRulerView *ruler;
@end

@implementation RCDelayRulerPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 10;
        stack.layoutMarginsRelativeArrangement = YES;
        stack.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        UIView *header = [[UIView alloc] init];
        UILabel *title = [[UILabel alloc] init];
        title.text = @"Seconds";
        title.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
        title.textColor = [UIColor secondaryLabelColor];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        UIButton *variable = [self makeVariableButton];
        variable.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:title];
        [header addSubview:variable];
        [NSLayoutConstraint activateConstraints:@[
            [header.heightAnchor constraintEqualToConstant:34],
            [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
            [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [variable.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
            [variable.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [variable.widthAnchor constraintEqualToConstant:34],
            [variable.heightAnchor constraintEqualToConstant:34],
        ]];

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = RCDelayBlockColor();
        card.layer.cornerRadius = 16;
        card.translatesAutoresizingMaskIntoConstraints = NO;

        self.ruler = [[RCDelayRulerView alloc] initWithFrame:CGRectZero];
        __weak typeof(self) weakSelf = self;
        self.ruler.onScrub = ^(double value) {
            weakSelf.valueText = [NSString stringWithFormat:@"%.1f", value];
        };
        self.ruler.onTextChange = ^(NSString *text) {
            weakSelf.valueText = text;
        };
        [card addSubview:self.ruler];
        [NSLayoutConstraint activateConstraints:@[
            [self.ruler.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [self.ruler.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
            [self.ruler.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
            [self.ruler.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
            [self.ruler.heightAnchor constraintEqualToConstant:90],
        ]];

        [stack addArrangedSubview:header];
        [stack addArrangedSubview:card];
        [stack addArrangedSubview:RCDelayNoteLabel(@"Drag the ruler, or type a time. Each tick is half a second.")];

        self.valueText = @"2.0";
        self.ruler.field.text = self.valueText;
    }
    return self;
}

- (void)valueTextDidChange {
    if (![self.ruler.field.text isEqualToString:self.valueText]) self.ruler.field.text = self.valueText;
    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    self.ruler.showsVariable = [self.valueText hasPrefix:@"{"];
    if (numeric) self.ruler.value = value;
}

@end

#pragma mark - E. Duration tiles with a Custom row

@interface RCDelayDurationTile : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, assign, getter=isChosen) BOOL chosen;
- (void)setIconName:(NSString *)name valueText:(NSString *)text;
@end

@implementation RCDelayDurationTile

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 12;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:14
                                                                                                weight:UIImageSymbolWeightSemibold];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = RCDelayDigitFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
        _valueLabel.textAlignment = NSTextAlignmentCenter;
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        _valueLabel.minimumScaleFactor = 0.7;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_iconView];
        [self addSubview:_valueLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:68],
            [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
            [_iconView.widthAnchor constraintEqualToConstant:20],
            [_iconView.heightAnchor constraintEqualToConstant:18],
            [_valueLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3],
            [_valueLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:5],
        ]];
        [self applyLook];
    }
    return self;
}

- (void)setIconName:(NSString *)name valueText:(NSString *)text {
    self.iconView.image = [UIImage systemImageNamed:name
                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14
                                                                                                   weight:UIImageSymbolWeightSemibold]];
    self.valueLabel.text = text;
    self.accessibilityLabel = text;
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [self applyLook];
}

- (void)applyLook {
    UIColor *accent = RCDelayAccent(self);
    self.backgroundColor = self.isChosen ? [accent colorWithAlphaComponent:0.20] : RCDelayBlockColor();
    self.layer.borderWidth = self.isChosen ? 1.5 : 0;
    self.layer.borderColor = accent.CGColor;
    self.iconView.tintColor = self.isChosen ? accent : [UIColor secondaryLabelColor];
    self.valueLabel.textColor = self.isChosen ? accent : [UIColor labelColor];
    if (self.isChosen) self.accessibilityTraits |= UIAccessibilityTraitSelected;
    else self.accessibilityTraits &= ~UIAccessibilityTraitSelected;
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

@interface RCDelayTilesPanel : RCDelayVariantView
@property (nonatomic, strong) NSArray<NSNumber *> *presets;
@property (nonatomic, strong) NSArray<RCDelayDurationTile *> *presetTiles;
@property (nonatomic, strong) RCDelayDurationTile *customTile;
@property (nonatomic, strong) UIView *customRow;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, assign) BOOL customChosen;
@end

@implementation RCDelayTilesPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.presets = @[@0.5, @1, @2, @5, @10];
        NSArray *icons = @[@"hare", @"bolt", @"timer", @"hourglass", @"moon.zzz"];

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 10;
        stack.layoutMarginsRelativeArrangement = YES;
        stack.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        UIView *header = [[UIView alloc] init];
        UILabel *title = [[UILabel alloc] init];
        title.text = @"Seconds";
        title.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
        title.textColor = [UIColor secondaryLabelColor];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        UIButton *variable = [self makeVariableButton];
        variable.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:title];
        [header addSubview:variable];
        [NSLayoutConstraint activateConstraints:@[
            [header.heightAnchor constraintEqualToConstant:34],
            [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
            [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [variable.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
            [variable.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [variable.widthAnchor constraintEqualToConstant:34],
            [variable.heightAnchor constraintEqualToConstant:34],
        ]];

        NSMutableArray *tiles = [NSMutableArray array];
        NSMutableArray *rows = [NSMutableArray array];
        for (NSInteger row = 0; row < 2; row++) {
            UIStackView *tileRow = [[UIStackView alloc] init];
            tileRow.axis = UILayoutConstraintAxisHorizontal;
            tileRow.spacing = 8;
            tileRow.distribution = UIStackViewDistributionFillEqually;
            tileRow.translatesAutoresizingMaskIntoConstraints = NO;
            [rows addObject:tileRow];
        }
        for (NSInteger i = 0; i < 6; i++) {
            RCDelayDurationTile *tile = [[RCDelayDurationTile alloc] initWithFrame:CGRectZero];
            tile.tag = i;
            [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
            if (i < (NSInteger)self.presets.count) {
                [tile setIconName:icons[i] valueText:[NSString stringWithFormat:@"%@ s", RCDelayFormat(self.presets[i].doubleValue, 1)]];
            } else {
                [tile setIconName:@"keyboard" valueText:@"Custom"];
                tile.accessibilityLabel = @"Custom duration";
            }
            [((UIStackView *)rows[i / 3]) addArrangedSubview:tile];
            [tiles addObject:tile];
        }
        self.presetTiles = @[tiles[0], tiles[1], tiles[2], tiles[3], tiles[4]];
        self.customTile = tiles[5];

        UIStackView *grid = [[UIStackView alloc] initWithArrangedSubviews:rows];
        grid.axis = UILayoutConstraintAxisVertical;
        grid.spacing = 8;

        self.customRow = [[UIView alloc] init];
        self.customRow.backgroundColor = RCDelayBlockColor();
        self.customRow.layer.cornerRadius = 12;
        self.customRow.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *customLabel = [[UILabel alloc] init];
        customLabel.text = @"Custom";
        customLabel.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightRegular);
        customLabel.textColor = [UIColor secondaryLabelColor];
        customLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.field = [self makeNumberField];
        [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
        [self.field addTarget:self action:@selector(fieldBeganEditing) forControlEvents:UIControlEventEditingDidBegin];
        [self.customRow addSubview:customLabel];
        [self.customRow addSubview:self.field];
        [NSLayoutConstraint activateConstraints:@[
            [self.customRow.heightAnchor constraintEqualToConstant:48],
            [customLabel.leadingAnchor constraintEqualToAnchor:self.customRow.leadingAnchor constant:14],
            [customLabel.centerYAnchor constraintEqualToAnchor:self.customRow.centerYAnchor],
            [self.field.leadingAnchor constraintGreaterThanOrEqualToAnchor:customLabel.trailingAnchor constant:12],
            [self.field.trailingAnchor constraintEqualToAnchor:self.customRow.trailingAnchor constant:-12],
            [self.field.topAnchor constraintEqualToAnchor:self.customRow.topAnchor],
            [self.field.bottomAnchor constraintEqualToAnchor:self.customRow.bottomAnchor],
        ]];
        self.customRow.hidden = YES;

        [stack addArrangedSubview:header];
        [stack addArrangedSubview:grid];
        [stack addArrangedSubview:self.customRow];
        [stack addArrangedSubview:RCDelayNoteLabel(@"Tap a length. Custom opens a field for anything else.")];

        self.field.text = self.valueText;
        [self updateSelection];
    }
    return self;
}

- (void)tileTapped:(RCDelayDurationTile *)tile {
    if (tile == self.customTile) {
        [self revealCustomRow:YES];
        self.customChosen = YES;
        [self updateSelection];
        [self.field becomeFirstResponder];
        return;
    }
    [self.field resignFirstResponder];
    self.customChosen = NO;
    [self revealCustomRow:NO];
    double preset = self.presets[tile.tag].doubleValue;
    self.valueText = RCDelayFormat(preset, 1);
}

- (void)fieldBeganEditing {
    [self revealCustomRow:YES];
    self.customChosen = YES;
    [self updateSelection];
}

- (void)textChanged {
    self.valueText = self.field.text ?: @"";
}

- (void)valueTextDidChange {
    if (![self.field.text isEqualToString:self.valueText]) self.field.text = self.valueText;
    if (self.field.isFirstResponder) {
        self.customChosen = YES;
    } else if ([self.valueText hasPrefix:@"{"]) {
        self.customChosen = YES;
    } else {
        double value = 0;
        BOOL matches = NO;
        if (RCDelayNumberFromText(self.valueText, &value)) {
            for (NSNumber *preset in self.presets) {
                if (fabs(preset.doubleValue - value) < 0.0001) { matches = YES; break; }
            }
        }
        if (matches) self.customChosen = NO;
    }
    if (self.customChosen) [self revealCustomRow:YES];
    [self updateSelection];
}

- (void)revealCustomRow:(BOOL)show {
    if (self.customRow.hidden == !show) return;
    [UIView animateWithDuration:0.2 animations:^{
        self.customRow.hidden = !show;
        [self layoutIfNeeded];
    }];
}

- (void)updateSelection {
    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    NSInteger chosen = -1;
    if (self.customChosen) {
        chosen = 5;
    } else if (numeric) {
        for (NSUInteger i = 0; i < self.presets.count; i++) {
            if (fabs(self.presets[i].doubleValue - value) < 0.0001) {
                chosen = (NSInteger)i;
                break;
            }
        }
    }
    for (NSUInteger i = 0; i < self.presetTiles.count; i++) {
        self.presetTiles[i].chosen = ((NSInteger)i == chosen);
    }
    self.customTile.chosen = (chosen == 5);
}

@end

#pragma mark - F. One compact line

@interface RCDelayInlinePanel : RCDelayVariantView
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UISegmentedControl *unitControl;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, assign) NSInteger unitIndex;
@end

@implementation RCDelayInlinePanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.unitIndex = 1;

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 10;
        stack.layoutMarginsRelativeArrangement = YES;
        stack.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        UIView *row = [[UIView alloc] init];
        row.backgroundColor = RCDelayBlockColor();
        row.layer.cornerRadius = 12;
        row.translatesAutoresizingMaskIntoConstraints = NO;

        self.field = [self makeNumberField];
        self.field.textAlignment = NSTextAlignmentLeft;
        UIButton *variable = [self makeVariableButton];
        variable.frame = CGRectMake(0, 0, 28, 34);
        self.field.rightView = variable;
        self.field.rightViewMode = UITextFieldViewModeAlways;
        [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];

        self.unitControl = [[UISegmentedControl alloc] initWithItems:@[@"ms", @"s", @"min"]];
        self.unitControl.selectedSegmentIndex = 1;
        self.unitControl.translatesAutoresizingMaskIntoConstraints = NO;
        [self.unitControl setTitleTextAttributes:@{
            NSFontAttributeName: RCDelayFont(UIFontTextStyleCaption1, UIFontWeightSemibold),
            NSForegroundColorAttributeName: [UIColor labelColor],
        } forState:UIControlStateNormal];
        [self.unitControl setTitleTextAttributes:@{
            NSFontAttributeName: RCDelayFont(UIFontTextStyleCaption1, UIFontWeightSemibold),
            NSForegroundColorAttributeName: [UIColor labelColor],
        } forState:UIControlStateSelected];
        [self.unitControl addTarget:self action:@selector(unitChanged) forControlEvents:UIControlEventValueChanged];

        self.slider = [[UISlider alloc] init];
        self.slider.minimumTrackTintColor = [UIColor systemBlueColor];
        self.slider.maximumTrackTintColor = RCDelaySeparatorColor();
        self.slider.translatesAutoresizingMaskIntoConstraints = NO;
        [self.slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];

        [row addSubview:self.field];
        [row addSubview:self.unitControl];
        [row addSubview:self.slider];
        [NSLayoutConstraint activateConstraints:@[
            [row.heightAnchor constraintEqualToConstant:54],
            [self.field.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:8],
            [self.field.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [self.field.widthAnchor constraintEqualToConstant:72],
            [self.field.heightAnchor constraintEqualToConstant:44],
            [self.unitControl.leadingAnchor constraintEqualToAnchor:self.field.trailingAnchor constant:6],
            [self.unitControl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [self.unitControl.widthAnchor constraintEqualToConstant:88],
            [self.unitControl.heightAnchor constraintEqualToConstant:32],
            [self.slider.leadingAnchor constraintEqualToAnchor:self.unitControl.trailingAnchor constant:6],
            [self.slider.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8],
            [self.slider.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];

        [stack addArrangedSubview:row];
        [stack addArrangedSubview:RCDelayNoteLabel(@"One line: type an exact time, drag for quick changes, or switch units.")];

        self.field.text = self.valueText;
        [self updateSliderRange];
        [self valueTextDidChange];
    }
    return self;
}

- (double)secondsPerUnit {
    if (self.unitIndex == 0) return 0.001;
    if (self.unitIndex == 2) return 60.0;
    return 1.0;
}

- (double)sliderMaximum {
    if (self.unitIndex == 0) return 10000.0;
    if (self.unitIndex == 2) return 10.0;
    return 30.0;
}

- (NSInteger)decimals {
    return self.unitIndex == 0 ? 0 : 2;
}

- (void)textChanged {
    self.valueText = self.field.text ?: @"";
}

- (void)sliderChanged {
    self.valueText = RCDelayFormat(self.slider.value, [self decimals]);
}

- (void)unitChanged {
    NSInteger newIndex = self.unitControl.selectedSegmentIndex;
    if (newIndex == self.unitIndex) return;

    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    double oldSecondsPerUnit = [self secondsPerUnit];
    self.unitIndex = newIndex;
    double newSecondsPerUnit = [self secondsPerUnit];

    [self updateSliderRange];
    if (numeric) {
        double seconds = value * oldSecondsPerUnit;
        self.valueText = RCDelayFormat(seconds / newSecondsPerUnit, [self decimals]);
    } else {
        [self valueTextDidChange];
    }
}

- (void)updateSliderRange {
    self.slider.minimumValue = 0;
    self.slider.maximumValue = [self sliderMaximum];
    double value = 0;
    if (RCDelayNumberFromText(self.valueText, &value)) self.slider.value = value;
}

- (void)valueTextDidChange {
    if (![self.field.text isEqualToString:self.valueText]) self.field.text = self.valueText;
    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    self.slider.enabled = numeric;
    self.slider.alpha = numeric ? 1.0 : 0.35;
    if (numeric) self.slider.value = value;
}

@end

#pragma mark - Full size panel

@interface RCDelayPrototypeDetailViewController : UIViewController
- (instancetype)initWithDescriptor:(NSDictionary *)descriptor;
@end

@interface RCDelayPrototypeDetailViewController ()
@property (nonatomic, copy) NSDictionary *descriptor;
@property (nonatomic, strong) RCDelayVariantView *variant;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@end

@implementation RCDelayPrototypeDetailViewController

- (instancetype)initWithDescriptor:(NSDictionary *)descriptor {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _descriptor = [descriptor copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Delay";
    self.navigationItem.prompt = [NSString stringWithFormat:@"Prototype %@: %@", self.descriptor[@"letter"], self.descriptor[@"name"]];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                         target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self action:@selector(save)];

    self.view.backgroundColor = RCDelayPageColor();

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
    ]];

    [self installVariant];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)installVariant {
    [self.variant removeFromSuperview];
    RCDelayVariantFactory make = self.descriptor[@"make"];
    RCDelayVariantView *variant = make ? make() : nil;
    if (!variant) return;
    self.variant = variant;
    variant.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:variant];

    NSLayoutConstraint *width = [variant.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor
                                                                    constant:-40];
    width.priority = 999;
    [NSLayoutConstraint activateConstraints:@[
        [variant.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:20],
        [variant.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [variant.widthAnchor constraintLessThanOrEqualToConstant:440],
        [variant.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [variant.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [variant.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-24],
        width,
    ]];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!self.isViewLoaded || !previousTraitCollection) return;
    if ([self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) return;
    NSString *value = self.variant.valueText;
    [self installVariant];
    self.variant.valueText = value;
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect keyboard = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:keyboard fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(local));
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.scrollView.contentInset = insets;
    if (@available(iOS 13.0, *)) self.scrollView.verticalScrollIndicatorInsets = insets;
}

- (void)cancel {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Contact sheet card

@interface RCDelayPrototypeCardView : UIControl
@property (nonatomic, copy) void (^onOpen)(void);
- (instancetype)initWithDescriptor:(NSDictionary *)descriptor;
@end

@interface RCDelayPrototypeCardView ()
@property (nonatomic, strong) UIView *stageView;
@end

@implementation RCDelayPrototypeCardView

- (instancetype)initWithDescriptor:(NSDictionary *)descriptor {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = RCDelayBlockColor();
        self.layer.cornerRadius = 18;
        self.layer.borderWidth = 1;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityLabel = [NSString stringWithFormat:@"Variant %@, %@. %@",
                                   descriptor[@"letter"], descriptor[@"name"], descriptor[@"summary"]];
        self.accessibilityHint = @"Opens this panel full size";

        UIView *badge = [[UIView alloc] init];
        badge.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.16];
        badge.layer.cornerRadius = 8;
        badge.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *letter = [[UILabel alloc] init];
        letter.text = descriptor[@"letter"];
        letter.font = RCDelayMonoFont(12, UIFontTextStyleCaption1, UIFontWeightSemibold);
        letter.textColor = [UIColor systemBlueColor];
        letter.textAlignment = NSTextAlignmentCenter;
        letter.adjustsFontSizeToFitWidth = YES;
        letter.minimumScaleFactor = 0.7;
        letter.translatesAutoresizingMaskIntoConstraints = NO;
        [badge addSubview:letter];
        [NSLayoutConstraint activateConstraints:@[
            [letter.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor],
            [letter.trailingAnchor constraintEqualToAnchor:badge.trailingAnchor],
            [letter.topAnchor constraintEqualToAnchor:badge.topAnchor],
            [letter.bottomAnchor constraintEqualToAnchor:badge.bottomAnchor],
        ]];

        UILabel *name = [[UILabel alloc] init];
        name.text = descriptor[@"name"];
        name.font = RCDelayFont(UIFontTextStyleHeadline, UIFontWeightSemibold);
        name.textColor = [UIColor labelColor];
        name.numberOfLines = 1;
        name.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *summary = [[UILabel alloc] init];
        summary.text = descriptor[@"summary"];
        summary.font = RCDelayFont(UIFontTextStyleFootnote, UIFontWeightRegular);
        summary.textColor = [UIColor secondaryLabelColor];
        summary.numberOfLines = 2;
        summary.translatesAutoresizingMaskIntoConstraints = NO;

        UIImageView *chevron = [[UIImageView alloc] init];
        chevron.image = [UIImage systemImageNamed:@"chevron.right"
                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11
                                                                                                weight:UIImageSymbolWeightSemibold]];
        chevron.tintColor = [UIColor tertiaryLabelColor];
        chevron.translatesAutoresizingMaskIntoConstraints = NO;

        self.stageView = [[UIView alloc] init];
        self.stageView.backgroundColor = RCDelayPageColor();
        self.stageView.layer.cornerRadius = 14;
        self.stageView.layer.borderWidth = 1;
        self.stageView.clipsToBounds = YES;
        self.stageView.translatesAutoresizingMaskIntoConstraints = NO;

        RCDelayVariantFactory make = descriptor[@"make"];
        RCDelayVariantView *variant = make ? make() : nil;
        variant.userInteractionEnabled = NO;
        variant.accessibilityElementsHidden = YES;
        [self.stageView addSubview:variant];

        [self addSubview:badge];
        [self addSubview:name];
        [self addSubview:summary];
        [self addSubview:chevron];
        [self addSubview:self.stageView];

        [NSLayoutConstraint activateConstraints:@[
            [badge.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [badge.centerYAnchor constraintEqualToAnchor:name.centerYAnchor],
            [badge.widthAnchor constraintEqualToConstant:26],
            [badge.heightAnchor constraintEqualToConstant:26],

            [name.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:10],
            [name.topAnchor constraintEqualToAnchor:self.topAnchor constant:11],
            [name.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-6],

            [chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [chevron.centerYAnchor constraintEqualToAnchor:name.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:12],
            [chevron.heightAnchor constraintEqualToConstant:16],

            [summary.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
            [summary.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [summary.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:3],

            [self.stageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [self.stageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [self.stageView.topAnchor constraintEqualToAnchor:summary.bottomAnchor constant:10],
            [self.stageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],

            [variant.leadingAnchor constraintEqualToAnchor:self.stageView.leadingAnchor],
            [variant.trailingAnchor constraintEqualToAnchor:self.stageView.trailingAnchor],
            [variant.topAnchor constraintEqualToAnchor:self.stageView.topAnchor],
            [variant.bottomAnchor constraintLessThanOrEqualToAnchor:self.stageView.bottomAnchor],
            [self.stageView.heightAnchor constraintGreaterThanOrEqualToAnchor:variant.heightAnchor],
        ]];

        [self addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
        [self applyBorderColors];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyBorderColors];
}

- (void)applyBorderColors {
    self.layer.borderColor = [RCDelayBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    self.stageView.layer.borderColor = [RCDelayBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)openTapped {
    if (self.onOpen) self.onOpen();
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.16
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.98, 0.98) : CGAffineTransformIdentity;
        self.alpha = highlighted ? 0.92 : 1.0;
    } completion:nil];
}

@end

@interface RCDelayPrototypeCardCell : UITableViewCell
@property (nonatomic, strong) UIStackView *rowStack;
@property (nonatomic, copy) void (^onOpenDescriptor)(NSDictionary *descriptor);
- (void)configureWithDescriptors:(NSArray<NSDictionary *> *)descriptors;
@end

@implementation RCDelayPrototypeCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _rowStack = [[UIStackView alloc] init];
        _rowStack.axis = UILayoutConstraintAxisHorizontal;
        _rowStack.spacing = 10;
        _rowStack.alignment = UIStackViewAlignmentFill;
        _rowStack.distribution = UIStackViewDistributionFillEqually;
        _rowStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_rowStack];
        [NSLayoutConstraint activateConstraints:@[
            [_rowStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_rowStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_rowStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:7],
            [_rowStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-7],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.rowStack.alpha = 1.0;
    self.rowStack.transform = CGAffineTransformIdentity;
}

- (void)configureWithDescriptors:(NSArray<NSDictionary *> *)descriptors {
    self.rowStack.alpha = 1.0;
    self.rowStack.transform = CGAffineTransformIdentity;
    for (UIView *view in self.rowStack.arrangedSubviews) {
        [self.rowStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSDictionary *descriptor in descriptors) {
        RCDelayPrototypeCardView *card = [[RCDelayPrototypeCardView alloc] initWithDescriptor:descriptor];
        __weak typeof(self) weakSelf = self;
        card.onOpen = ^{
            if (weakSelf.onOpenDescriptor) weakSelf.onOpenDescriptor(descriptor);
        };
        [self.rowStack addArrangedSubview:card];
    }
}

@end

#pragma mark - Gallery

@interface RCDelayPrototypeGalleryViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *variants;
@property (nonatomic, assign) NSInteger columnCount;
@property (nonatomic, assign) CGFloat headerWidth;
@property (nonatomic, copy) NSString *headerCategory;
@property (nonatomic, assign) BOOL hasAnimated;
@end

@implementation RCDelayPrototypeGalleryViewController

- (instancetype)init {
    return [self initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Delay Styles";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.variants = @[
        @{ @"letter": @"A", @"name": @"Current", @"summary": @"The shipping inset row.",
           @"make": ^RCDelayVariantView *(void){ return [[RCDelayBaselinePanel alloc] initWithFrame:CGRectZero]; } },
        @{ @"letter": @"B", @"name": @"Presets", @"summary": @"One-tap common lengths.",
           @"make": ^RCDelayVariantView *(void){ return [[RCDelayPresetsPanel alloc] initWithFrame:CGRectZero]; } },
        @{ @"letter": @"C", @"name": @"Stepper", @"summary": @"Half-second steps, big readout.",
           @"make": ^RCDelayVariantView *(void){ return [[RCDelayStepperPanel alloc] initWithFrame:CGRectZero]; } },
        @{ @"letter": @"D", @"name": @"Ruler", @"summary": @"Drag a snap ruler.",
           @"make": ^RCDelayVariantView *(void){ return [[RCDelayRulerPanel alloc] initWithFrame:CGRectZero]; } },
        @{ @"letter": @"E", @"name": @"Tiles", @"summary": @"Durations as tiles, plus Custom.",
           @"make": ^RCDelayVariantView *(void){ return [[RCDelayTilesPanel alloc] initWithFrame:CGRectZero]; } },
        @{ @"letter": @"F", @"name": @"Inline", @"summary": @"Value, units and slider in a line.",
           @"make": ^RCDelayVariantView *(void){ return [[RCDelayInlinePanel alloc] initWithFrame:CGRectZero]; } },

        // Variations on the Stepper (C), one file each
        @{ @"letter": @"C1", @"name": @"Stepper", @"summary": @"The one you picked: half-second steps.",
           @"make": ^RCDelayVariantView *(void){ return [[RCDelayStepperPanel alloc] initWithFrame:CGRectZero]; } },
        @{ @"letter": @"C2", @"name": @"Hold", @"summary": @"Minus and plus speed up while held.",
           @"make": ^RCDelayVariantView *(void){ return RCDelayMakeStepperHold(); } },
        @{ @"letter": @"C3", @"name": @"Scrub", @"summary": @"Drag the number to change it.",
           @"make": ^RCDelayVariantView *(void){ return RCDelayMakeStepperScrub(); } },
        @{ @"letter": @"C4", @"name": @"Wheel", @"summary": @"Snap through half-second detents.",
           @"make": ^RCDelayVariantView *(void){ return RCDelayMakeStepperWheel(); } },
        @{ @"letter": @"C5", @"name": @"Multiply", @"summary": @"x2 and /2 beside the steps.",
           @"make": ^RCDelayVariantView *(void){ return RCDelayMakeStepperMultiply(); } },
        @{ @"letter": @"C6", @"name": @"Pill", @"summary": @"One row: minus, value, plus.",
           @"make": ^RCDelayVariantView *(void){ return RCDelayMakeStepperPill(); } },
    ];

    self.tableView.backgroundColor = RCDelayPageColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 300;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    self.tableView.showsVerticalScrollIndicator = YES;
    [self.tableView registerClass:[RCDelayPrototypeCardCell class] forCellReuseIdentifier:@"card"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.tableView.backgroundColor = RCDelayPageColor();
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    NSInteger columns = [self columnCountForWidth:width];
    if (columns != self.columnCount) {
        self.columnCount = columns;
        [self.tableView reloadData];
    }
    NSString *category = self.traitCollection.preferredContentSizeCategory ?: @"";
    BOOL sameWidth = fabs(self.headerWidth - width) < 0.5;
    BOOL sameCategory = [self.headerCategory isEqualToString:category];
    if (sameWidth && sameCategory && self.tableView.tableHeaderView) return;
    self.headerWidth = width;
    self.headerCategory = category;
    self.tableView.tableHeaderView = [self makeHeaderViewWithWidth:width];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!self.isViewLoaded || !previousTraitCollection) return;
    if ([self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) return;
    self.tableView.tableHeaderView = nil;
    [self.tableView reloadData];
    [self.view setNeedsLayout];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.hasAnimated || UIAccessibilityIsReduceMotionEnabled()) return;
    self.hasAnimated = YES;
    NSArray<UITableViewCell *> *cells = self.tableView.visibleCells;
    for (NSUInteger i = 0; i < cells.count; i++) {
        UIStackView *stack = ((RCDelayPrototypeCardCell *)cells[i]).rowStack;
        stack.alpha = 0;
        stack.transform = CGAffineTransformMakeTranslation(0, 12);
        [UIView animateWithDuration:0.38
                              delay:0.04 * i
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            stack.alpha = 1;
            stack.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

#pragma mark - Rows

- (NSInteger)columnCountForWidth:(CGFloat)width {
    return width >= RCDelayColumnBreak ? 2 : 1;
}

- (NSArray<NSArray<NSDictionary *> *> *)rows {
    NSInteger columns = MAX(1, self.columnCount);
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.variants.count; i += columns) {
        NSRange range = NSMakeRange(i, MIN((NSUInteger)columns, self.variants.count - i));
        [rows addObject:[self.variants subarrayWithRange:range]];
    }
    return rows;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger columns = [self columnCountForWidth:CGRectGetWidth(tableView.bounds)];
    if (columns != self.columnCount) self.columnCount = columns;
    return (NSInteger)self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCDelayPrototypeCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"card" forIndexPath:indexPath];
    __weak typeof(self) weakSelf = self;
    cell.onOpenDescriptor = ^(NSDictionary *descriptor) {
        [weakSelf openDescriptor:descriptor];
    };
    [cell configureWithDescriptors:self.rows[indexPath.row]];
    return cell;
}

- (void)openDescriptor:(NSDictionary *)descriptor {
    RCDelayPrototypeDetailViewController *detail = [[RCDelayPrototypeDetailViewController alloc] initWithDescriptor:descriptor];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detail];
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent]];
        sheet.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Header

- (NSAttributedString *)eyebrowText:(NSString *)text color:(UIColor *)color kern:(CGFloat)kern {
    return [[NSAttributedString alloc] initWithString:text
                                           attributes:@{
        NSFontAttributeName: RCDelayFont(UIFontTextStyleCaption2, UIFontWeightSemibold),
        NSForegroundColorAttributeName: color,
        NSKernAttributeName: @(kern),
    }];
}

- (UIView *)makeHeaderViewWithWidth:(CGFloat)width {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 0)];

    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.attributedText = [self eyebrowText:@"PROTOTYPE" color:[UIColor secondaryLabelColor] kern:1.4];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *range = [[UILabel alloc] init];
    range.attributedText = [self eyebrowText:@"SIX + SIX" color:[UIColor tertiaryLabelColor] kern:1.0];
    range.textAlignment = NSTextAlignmentRight;
    range.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.text = @"Ways to set a delay";
    title.font = RCDelayFont(UIFontTextStyleTitle2, UIFontWeightSemibold);
    title.textColor = [UIColor labelColor];
    title.numberOfLines = 0;
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *body = [[UILabel alloc] init];
    body.text = @"The first six are different editors. The C cards are variations on the Stepper. Tap one to try it full size.";
    body.font = RCDelayFont(UIFontTextStyleFootnote, UIFontWeightRegular);
    body.textColor = [UIColor secondaryLabelColor];
    body.numberOfLines = 0;
    body.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:eyebrow];
    [header addSubview:range];
    [header addSubview:title];
    [header addSubview:body];
    [NSLayoutConstraint activateConstraints:@[
        [eyebrow.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [eyebrow.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],
        [range.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [range.centerYAnchor constraintEqualToAnchor:eyebrow.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [title.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:8],
        [body.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [body.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [body.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16],
    ]];

    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                         withHorizontalFittingPriority:UILayoutPriorityRequired
                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    header.frame = CGRectMake(0, 0, width, size.height);
    return header;
}

@end
