#import "RCDelayPrototypeKit.h"
#import "RCDelayStepperVariations.h"

// C5. Multiply: the usual half-second steps beside x2 and /2, with a ms / s /
// min switch over the same stored seconds. The exact field always takes seconds.

static const double RCDelayMultiplyMaximum = 86400.0;
static const double RCDelayMultiplySmallestStep = 0.5;

@interface RCDelayStepperMultiplyPanel : RCDelayVariantView
@property (nonatomic, strong) UILabel *readout;
@property (nonatomic, strong) UILabel *unit;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UISegmentedControl *unitControl;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UIButton *doubleButton;
@property (nonatomic, strong) UIButton *halfButton;
@property (nonatomic, assign) NSInteger unitIndex;
@end

@implementation RCDelayStepperMultiplyPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.unitIndex = 1;

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
        NSLayoutConstraint *headerHeight = [header.heightAnchor constraintEqualToConstant:34];
        headerHeight.priority = 749;
        [NSLayoutConstraint activateConstraints:@[
            headerHeight,
            [header.heightAnchor constraintGreaterThanOrEqualToConstant:34],
            [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
            [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [title.topAnchor constraintGreaterThanOrEqualToAnchor:header.topAnchor],
            [title.bottomAnchor constraintLessThanOrEqualToAnchor:header.bottomAnchor],
            [variable.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
            [variable.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [variable.widthAnchor constraintEqualToConstant:34],
            [variable.heightAnchor constraintEqualToConstant:34],
        ]];

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = RCDelayBlockColor();
        card.layer.cornerRadius = 16;
        card.translatesAutoresizingMaskIntoConstraints = NO;

        self.unitControl = [[UISegmentedControl alloc] initWithItems:@[@"ms", @"s", @"min"]];
        self.unitControl.selectedSegmentIndex = self.unitIndex;
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

        self.minusButton = [self symbolButtonNamed:@"minus" label:@"Decrease by half a second"];
        self.plusButton = [self symbolButtonNamed:@"plus" label:@"Increase by half a second"];
        self.doubleButton = [self textButtonNamed:@"x2" label:@"Double"];
        self.halfButton = [self textButtonNamed:@"/2" label:@"Halve"];
        [self.minusButton addTarget:self action:@selector(stepDown) forControlEvents:UIControlEventTouchUpInside];
        [self.plusButton addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside];
        [self.doubleButton addTarget:self action:@selector(multiplyByTwo) forControlEvents:UIControlEventTouchUpInside];
        [self.halfButton addTarget:self action:@selector(divideByTwo) forControlEvents:UIControlEventTouchUpInside];

        UIStackView *actionRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.minusButton, self.plusButton, self.doubleButton, self.halfButton]];
        actionRow.axis = UILayoutConstraintAxisHorizontal;
        actionRow.distribution = UIStackViewDistributionFillEqually;
        actionRow.spacing = 8;
        actionRow.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *separator = [[UIView alloc] init];
        separator.backgroundColor = RCDelaySeparatorColor();
        separator.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *exact = [[UIView alloc] init];
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
        [self.field addTarget:self action:@selector(fieldCommitted) forControlEvents:UIControlEventEditingDidEnd];
        [well addSubview:self.field];
        [exact addSubview:exactLabel];
        [exact addSubview:well];

        NSLayoutConstraint *exactHeight = [exact.heightAnchor constraintEqualToConstant:48];
        exactHeight.priority = 749;
        NSLayoutConstraint *wellHeight = [well.heightAnchor constraintEqualToConstant:36];
        wellHeight.priority = 749;
        [NSLayoutConstraint activateConstraints:@[
            exactHeight,
            [exact.heightAnchor constraintGreaterThanOrEqualToConstant:48],
            [exactLabel.leadingAnchor constraintEqualToAnchor:exact.leadingAnchor],
            [exactLabel.centerYAnchor constraintEqualToAnchor:exact.centerYAnchor],
            [exactLabel.topAnchor constraintGreaterThanOrEqualToAnchor:exact.topAnchor],
            [exactLabel.bottomAnchor constraintLessThanOrEqualToAnchor:exact.bottomAnchor],
            [exactLabel.trailingAnchor constraintLessThanOrEqualToAnchor:well.leadingAnchor constant:-8],
            [well.trailingAnchor constraintEqualToAnchor:exact.trailingAnchor],
            [well.centerYAnchor constraintEqualToAnchor:exact.centerYAnchor],
            [well.widthAnchor constraintEqualToConstant:116],
            wellHeight,
            [well.heightAnchor constraintGreaterThanOrEqualToConstant:36],
            [well.topAnchor constraintGreaterThanOrEqualToAnchor:exact.topAnchor],
            [well.bottomAnchor constraintLessThanOrEqualToAnchor:exact.bottomAnchor],
            [self.field.leadingAnchor constraintEqualToAnchor:well.leadingAnchor constant:10],
            [self.field.trailingAnchor constraintEqualToAnchor:well.trailingAnchor constant:-10],
            [self.field.topAnchor constraintEqualToAnchor:well.topAnchor],
            [self.field.bottomAnchor constraintEqualToAnchor:well.bottomAnchor],
        ]];

        [card addSubview:self.unitControl];
        [card addSubview:valueRow];
        [card addSubview:actionRow];
        [card addSubview:separator];
        [card addSubview:exact];
        [NSLayoutConstraint activateConstraints:@[
            [self.unitControl.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
            [self.unitControl.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [self.unitControl.heightAnchor constraintGreaterThanOrEqualToConstant:30],
            [self.unitControl.widthAnchor constraintGreaterThanOrEqualToConstant:132],
            [self.unitControl.leadingAnchor constraintGreaterThanOrEqualToAnchor:card.leadingAnchor constant:14],
            [self.unitControl.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-14],
            [valueRow.topAnchor constraintEqualToAnchor:self.unitControl.bottomAnchor constant:10],
            [valueRow.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [valueRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:card.leadingAnchor constant:14],
            [valueRow.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-14],
            [actionRow.topAnchor constraintEqualToAnchor:valueRow.bottomAnchor constant:14],
            [actionRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [actionRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
            [actionRow.heightAnchor constraintGreaterThanOrEqualToConstant:44],
            [separator.topAnchor constraintEqualToAnchor:actionRow.bottomAnchor constant:12],
            [separator.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [separator.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
            [separator.heightAnchor constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale],
            [exact.topAnchor constraintEqualToAnchor:separator.bottomAnchor constant:6],
            [exact.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [exact.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
            [exact.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-6],
        ]];

        [stack addArrangedSubview:header];
        [stack addArrangedSubview:card];
        [stack addArrangedSubview:RCDelayNoteLabel(@"Step by half a second, double it, or halve it.")];

        self.field.text = self.valueText;
        [self valueTextDidChange];
    }
    return self;
}

- (UIButton *)symbolButtonNamed:(NSString *)symbol label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18
                                                                                               weight:UIImageSymbolWeightSemibold]]
            forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = 12;
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (UIButton *)textButtonNamed:(NSString *)title label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = RCDelayFont(UIFontTextStyleBody, UIFontWeightSemibold);
    [button setTitleColor:RCDelayAccent(self) forState:UIControlStateNormal];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = 12;
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (double)secondsPerUnit {
    if (self.unitIndex == 0) return 0.001;
    if (self.unitIndex == 2) return 60.0;
    return 1.0;
}

- (double)stepSeconds {
    return self.unitIndex == 2 ? 60.0 : 0.5;
}

- (NSInteger)decimals {
    if (self.unitIndex == 0) return 0;
    return self.unitIndex == 1 ? 3 : 2;
}

- (NSString *)unitName {
    return self.unitIndex == 0 ? @"ms" : (self.unitIndex == 2 ? @"min" : @"s");
}

- (void)unitChanged {
    self.unitIndex = MAX(0, MIN(2, self.unitControl.selectedSegmentIndex));
    [self valueTextDidChange];
}

- (void)textChanged {
    self.valueText = self.field.text ?: @"";
}

- (void)fieldCommitted {
    double value = 0;
    if (!RCDelayNumberFromText(self.valueText, &value)) return;
    self.valueText = RCDelayFormat(MAX(0, MIN(RCDelayMultiplyMaximum, value)), 3);
}

- (void)stepDown {
    [self stepBy:-[self stepSeconds]];
}

- (void)stepUp {
    [self stepBy:[self stepSeconds]];
}

- (void)stepBy:(double)delta {
    double value = 0;
    if (!RCDelayNumberFromText(self.valueText, &value)) return;
    value = MAX(0, MIN(RCDelayMultiplyMaximum, value + delta));
    self.valueText = RCDelayFormat(value, 3);
}

- (void)multiplyByTwo {
    double value = 0;
    if (!RCDelayNumberFromText(self.valueText, &value)) return;
    value = MIN(RCDelayMultiplyMaximum, value * 2);
    self.valueText = RCDelayFormat(value, 3);
}

- (void)divideByTwo {
    double value = 0;
    if (!RCDelayNumberFromText(self.valueText, &value)) return;
    value = MAX(RCDelayMultiplySmallestStep, value / 2);
    self.valueText = RCDelayFormat(value, 3);
}

- (void)refreshStepLabels {
    NSString *amount = self.unitIndex == 2 ? @"one minute" : @"half a second";
    self.minusButton.accessibilityLabel = [NSString stringWithFormat:@"Decrease by %@", amount];
    self.plusButton.accessibilityLabel = [NSString stringWithFormat:@"Increase by %@", amount];
}

- (void)valueTextDidChange {
    if (![self.field.text isEqualToString:self.valueText]) self.field.text = self.valueText;

    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    if (numeric) {
        double clamped = MAX(0, MIN(RCDelayMultiplyMaximum, value));
        self.readout.font = RCDelayDigitFontOfSize(36, UIFontTextStyleTitle1, UIFontWeightSemibold);
        self.readout.text = RCDelayFormat(clamped / [self secondsPerUnit], [self decimals]);
        self.unit.text = [self unitName];
        self.unit.hidden = NO;
        self.minusButton.enabled = clamped > 0;
        self.plusButton.enabled = clamped < RCDelayMultiplyMaximum;
        self.doubleButton.enabled = clamped > 0 && clamped < RCDelayMultiplyMaximum;
        self.halfButton.enabled = clamped > RCDelayMultiplySmallestStep;
        self.unitControl.enabled = YES;
    } else {
        self.readout.font = RCDelayMonoFont(22, UIFontTextStyleTitle3, UIFontWeightSemibold);
        self.readout.text = self.valueText;
        self.unit.hidden = YES;
        self.minusButton.enabled = NO;
        self.plusButton.enabled = NO;
        self.doubleButton.enabled = NO;
        self.halfButton.enabled = NO;
        self.unitControl.enabled = NO;
    }
    self.minusButton.alpha = self.minusButton.enabled ? 1.0 : 0.35;
    self.plusButton.alpha = self.plusButton.enabled ? 1.0 : 0.35;
    self.doubleButton.alpha = self.doubleButton.enabled ? 1.0 : 0.35;
    self.halfButton.alpha = self.halfButton.enabled ? 1.0 : 0.35;
    self.unitControl.alpha = self.unitControl.enabled ? 1.0 : 0.35;
    [self refreshStepLabels];
}

@end

RCDelayVariantView *RCDelayMakeStepperMultiply(void) {
    return [[RCDelayStepperMultiplyPanel alloc] initWithFrame:CGRectZero];
}
