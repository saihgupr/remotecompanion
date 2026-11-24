#import "RCDelayPrototypeKit.h"
#import "RCDelayStepperVariations.h"

// C6. One split pill: minus at the edge, the value in the middle, plus at the
// other edge. Tapping the value types an exact time.

@interface RCDelayStepperPillPanel : RCDelayVariantView <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *readout;
@property (nonatomic, strong) UILabel *unit;
@property (nonatomic, strong) UIStackView *valueStack;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@end

@implementation RCDelayStepperPillPanel

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

        UIView *pill = [[UIView alloc] init];
        pill.backgroundColor = RCDelayBlockColor();
        pill.layer.cornerRadius = 28;
        pill.translatesAutoresizingMaskIntoConstraints = NO;

        self.minusButton = [self edgeButtonNamed:@"minus" label:@"Decrease by half a second"];
        self.plusButton = [self edgeButtonNamed:@"plus" label:@"Increase by half a second"];
        [self.minusButton addTarget:self action:@selector(stepDown) forControlEvents:UIControlEventTouchUpInside];
        [self.plusButton addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside];

        self.readout = [[UILabel alloc] init];
        self.readout.font = RCDelayDigitFontOfSize(30, UIFontTextStyleTitle1, UIFontWeightSemibold);
        self.readout.textColor = [UIColor labelColor];
        self.readout.textAlignment = NSTextAlignmentCenter;
        self.readout.adjustsFontSizeToFitWidth = YES;
        self.readout.minimumScaleFactor = 0.5;
        self.readout.text = self.valueText;
        self.readout.userInteractionEnabled = NO;
        self.readout.translatesAutoresizingMaskIntoConstraints = NO;

        self.unit = [[UILabel alloc] init];
        self.unit.text = @"s";
        self.unit.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightRegular);
        self.unit.textColor = [UIColor secondaryLabelColor];
        self.unit.userInteractionEnabled = NO;
        self.unit.translatesAutoresizingMaskIntoConstraints = NO;

        self.valueStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.readout, self.unit]];
        self.valueStack.axis = UILayoutConstraintAxisHorizontal;
        self.valueStack.alignment = UIStackViewAlignmentLastBaseline;
        self.valueStack.spacing = 3;
        self.valueStack.userInteractionEnabled = YES;
        self.valueStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.valueStack addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(beginTyping)]];

        self.field = [self makeNumberField];
        self.field.textAlignment = NSTextAlignmentCenter;
        self.field.font = RCDelayDigitFontOfSize(26, UIFontTextStyleTitle2, UIFontWeightSemibold);
        self.field.delegate = self;
        self.field.hidden = YES;
        [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];

        [pill addSubview:self.minusButton];
        [pill addSubview:self.plusButton];
        [pill addSubview:self.valueStack];
        [pill addSubview:self.field];
        [NSLayoutConstraint activateConstraints:@[
            [pill.heightAnchor constraintEqualToConstant:64],
            [self.minusButton.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:8],
            [self.minusButton.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
            [self.plusButton.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-8],
            [self.plusButton.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
            [self.valueStack.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],
            [self.valueStack.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
            [self.valueStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.minusButton.trailingAnchor constant:8],
            [self.valueStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.plusButton.leadingAnchor constant:-8],
            [self.field.leadingAnchor constraintEqualToAnchor:self.minusButton.trailingAnchor constant:8],
            [self.field.trailingAnchor constraintEqualToAnchor:self.plusButton.leadingAnchor constant:-8],
            [self.field.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
            [self.field.heightAnchor constraintEqualToConstant:44],
        ]];

        [stack addArrangedSubview:header];
        [stack addArrangedSubview:pill];
        [stack addArrangedSubview:RCDelayNoteLabel(@"One row. Tap the number to type an exact time.")];

        [self valueTextDidChange];
    }
    return self;
}

- (UIButton *)edgeButtonNamed:(NSString *)symbol label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18
                                                                                               weight:UIImageSymbolWeightSemibold]]
            forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = 24;
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:48],
        [button.heightAnchor constraintEqualToConstant:48],
    ]];
    return button;
}

- (void)beginTyping {
    double value = 0;
    if (!RCDelayNumberFromText(self.valueText, &value)) return;
    self.field.text = self.valueText;
    self.valueStack.hidden = YES;
    self.field.hidden = NO;
    [self.field becomeFirstResponder];
}

- (void)textChanged {
    self.valueText = self.field.text ?: @"";
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.field.hidden = YES;
    self.valueStack.hidden = NO;
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
    if (![self.field.text isEqualToString:self.valueText] && self.field.hidden) {
        self.field.text = self.valueText;
    }

    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    if (numeric) {
        self.readout.font = RCDelayDigitFontOfSize(30, UIFontTextStyleTitle1, UIFontWeightSemibold);
        self.readout.text = RCDelayFormat(value, 2);
        self.unit.hidden = NO;
        self.minusButton.enabled = value > 0;
        self.plusButton.enabled = value < 86400;
    } else {
        self.readout.font = RCDelayMonoFont(20, UIFontTextStyleTitle3, UIFontWeightSemibold);
        self.readout.text = self.valueText;
        self.unit.hidden = YES;
        self.minusButton.enabled = NO;
        self.plusButton.enabled = NO;
    }
    self.minusButton.alpha = self.minusButton.enabled ? 1.0 : 0.35;
    self.plusButton.alpha = self.plusButton.enabled ? 1.0 : 0.35;
}

@end

RCDelayVariantView *RCDelayMakeStepperPill(void) {
    return [[RCDelayStepperPillPanel alloc] initWithFrame:CGRectZero];
}
