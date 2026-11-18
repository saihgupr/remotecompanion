#import "RCDelayStepperVariations.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

static const NSTimeInterval RCDelayHoldDelay = 0.5;
static const NSTimeInterval RCDelayHoldRepeat = 0.18;
static const NSTimeInterval RCDelayHoldAccelerate = 1.5;

@interface RCDelayStepperHoldPanel : RCDelayVariantView <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *readout;
@property (nonatomic, strong) UILabel *unit;
@property (nonatomic, strong) UIStackView *valueRow;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIView *fieldWell;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) NSTimer *repeatDelayTimer;
@property (nonatomic, strong) NSTimer *repeatTimer;
@property (nonatomic, assign) double repeatDirection;
@property (nonatomic, assign) NSTimeInterval holdBeganAt;
@property (nonatomic, copy) NSString *valueBeforeEditing;
@end

@implementation RCDelayStepperHoldPanel

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

        UILabel *title = [[UILabel alloc] init];
        title.text = @"Seconds";
        title.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
        title.textColor = [UIColor secondaryLabelColor];
        [title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        UIButton *variable = [self makeVariableButton];
        variable.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, variable]];
        header.axis = UILayoutConstraintAxisHorizontal;
        header.alignment = UIStackViewAlignmentCenter;
        header.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [header.heightAnchor constraintGreaterThanOrEqualToConstant:34],
            [variable.widthAnchor constraintEqualToConstant:34],
            [variable.heightAnchor constraintEqualToConstant:34],
        ]];

        UIView *hero = [[UIView alloc] init];
        hero.backgroundColor = RCDelayBlockColor();
        hero.layer.cornerRadius = 16;
        hero.translatesAutoresizingMaskIntoConstraints = NO;

        self.minusButton = [self holdButtonNamed:@"minus" label:@"Decrease, hold to repeat"];
        self.plusButton = [self holdButtonNamed:@"plus" label:@"Increase, hold to repeat"];
        [self.minusButton addTarget:self action:@selector(holdMinus) forControlEvents:UIControlEventTouchDown];
        [self.plusButton addTarget:self action:@selector(holdPlus) forControlEvents:UIControlEventTouchDown];
        for (UIButton *button in @[self.minusButton, self.plusButton]) {
            [button addTarget:self action:@selector(stopHold) forControlEvents:UIControlEventTouchUpInside];
            [button addTarget:self action:@selector(stopHold) forControlEvents:UIControlEventTouchUpOutside];
            [button addTarget:self action:@selector(stopHold) forControlEvents:UIControlEventTouchCancel];
            [button addTarget:self action:@selector(stopHold) forControlEvents:UIControlEventTouchDragExit];
        }

        self.readout = [[UILabel alloc] init];
        self.readout.font = RCDelayDigitFontOfSize(36, UIFontTextStyleTitle1, UIFontWeightSemibold);
        self.readout.textColor = [UIColor labelColor];
        self.readout.adjustsFontSizeToFitWidth = YES;
        self.readout.minimumScaleFactor = 0.4;
        self.readout.text = self.valueText;
        self.readout.userInteractionEnabled = YES;
        self.readout.accessibilityLabel = @"Delay length";
        [self.readout setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
        [self.readout setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [self.readout addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(readoutTapped)]];

        self.unit = [[UILabel alloc] init];
        self.unit.text = @"s";
        self.unit.font = RCDelayFont(UIFontTextStyleSubheadline, UIFontWeightRegular);
        self.unit.textColor = [UIColor secondaryLabelColor];

        UIStackView *valueRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.readout, self.unit]];
        valueRow.axis = UILayoutConstraintAxisHorizontal;
        valueRow.alignment = UIStackViewAlignmentLastBaseline;
        valueRow.spacing = 3;
        valueRow.translatesAutoresizingMaskIntoConstraints = NO;
        self.valueRow = valueRow;

        self.fieldWell = [[UIView alloc] init];
        self.fieldWell.backgroundColor = [UIColor tertiarySystemFillColor];
        self.fieldWell.layer.cornerRadius = 10;
        self.fieldWell.hidden = YES;
        self.fieldWell.translatesAutoresizingMaskIntoConstraints = NO;

        self.field = [self makeNumberField];
        self.field.textAlignment = NSTextAlignmentCenter;
        self.field.delegate = self;
        [self.field addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
        [self.fieldWell addSubview:self.field];

        [hero addSubview:self.minusButton];
        [hero addSubview:self.plusButton];
        [hero addSubview:valueRow];
        [hero addSubview:self.fieldWell];
        [NSLayoutConstraint activateConstraints:@[
            [self.minusButton.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:10],
            [self.minusButton.topAnchor constraintEqualToAnchor:hero.topAnchor constant:10],
            [self.minusButton.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-10],
            [self.minusButton.widthAnchor constraintEqualToConstant:58],
            [self.plusButton.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-10],
            [self.plusButton.topAnchor constraintEqualToAnchor:hero.topAnchor constant:10],
            [self.plusButton.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-10],
            [self.plusButton.widthAnchor constraintEqualToConstant:58],
            [valueRow.centerXAnchor constraintEqualToAnchor:hero.centerXAnchor],
            [valueRow.topAnchor constraintEqualToAnchor:hero.topAnchor constant:18],
            [valueRow.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-18],
            [valueRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.minusButton.trailingAnchor constant:12],
            [valueRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.plusButton.leadingAnchor constant:-12],
            [self.fieldWell.leadingAnchor constraintEqualToAnchor:self.minusButton.trailingAnchor constant:12],
            [self.fieldWell.trailingAnchor constraintEqualToAnchor:self.plusButton.leadingAnchor constant:-12],
            [self.fieldWell.centerYAnchor constraintEqualToAnchor:hero.centerYAnchor],
            [self.fieldWell.heightAnchor constraintGreaterThanOrEqualToConstant:44],
            [self.field.leadingAnchor constraintEqualToAnchor:self.fieldWell.leadingAnchor constant:10],
            [self.field.trailingAnchor constraintEqualToAnchor:self.fieldWell.trailingAnchor constant:-10],
            [self.field.topAnchor constraintEqualToAnchor:self.fieldWell.topAnchor constant:6],
            [self.field.bottomAnchor constraintEqualToAnchor:self.fieldWell.bottomAnchor constant:-6],
        ]];

        [stack addArrangedSubview:header];
        [stack addArrangedSubview:hero];
        [stack addArrangedSubview:RCDelayNoteLabel(@"Hold minus or plus to move faster.")];

        [self valueTextDidChange];
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self stopHold];
}

- (void)dealloc {
    [_repeatDelayTimer invalidate];
    [_repeatTimer invalidate];
}

- (UIButton *)holdButtonNamed:(NSString *)symbol label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22
                                                                                               weight:UIImageSymbolWeightSemibold]]
            forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = 13;
    button.accessibilityLabel = label;
    button.accessibilityHint = @"Touch and hold to repeat";
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (void)holdMinus {
    [self beginHoldInDirection:-1];
}

- (void)holdPlus {
    [self beginHoldInDirection:1];
}

- (void)beginHoldInDirection:(double)direction {
    [self stopHold];
    if (self.field.isFirstResponder) [self.field resignFirstResponder];

    self.repeatDirection = direction;
    self.holdBeganAt = CACurrentMediaTime();
    [self stepBy:direction * 0.5];
    if (direction < 0 ? !self.minusButton.enabled : !self.plusButton.enabled) return;

    NSTimer *timer = [NSTimer timerWithTimeInterval:RCDelayHoldDelay
                                             target:self
                                           selector:@selector(beginRepeatTicks)
                                           userInfo:nil
                                            repeats:NO];
    timer.tolerance = 0.02;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.repeatDelayTimer = timer;
}

- (void)beginRepeatTicks {
    self.repeatDelayTimer = nil;

    NSTimer *timer = [NSTimer timerWithTimeInterval:RCDelayHoldRepeat
                                             target:self
                                           selector:@selector(repeatTick)
                                           userInfo:nil
                                            repeats:YES];
    timer.tolerance = 0.02;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.repeatTimer = timer;
}

- (void)repeatTick {
    BOOL atLimit = self.repeatDirection < 0 ? !self.minusButton.enabled : !self.plusButton.enabled;
    if (atLimit) {
        [self stopHold];
        return;
    }
    NSTimeInterval held = CACurrentMediaTime() - self.holdBeganAt;
    double step = held >= RCDelayHoldAccelerate ? 1.0 : 0.5;
    [self stepBy:self.repeatDirection * step];
}

- (void)stopHold {
    [self.repeatDelayTimer invalidate];
    self.repeatDelayTimer = nil;
    [self.repeatTimer invalidate];
    self.repeatTimer = nil;
}

- (void)insertVariableNamed:(NSString *)name {
    if (self.field.isFirstResponder) [self.field resignFirstResponder];
    [super insertVariableNamed:name];
}

- (void)stepBy:(double)delta {
    double value = 0;
    if (!RCDelayNumberFromText(self.valueText, &value)) return;
    value = MAX(0, MIN(86400, round((value + delta) * 2) / 2));
    self.valueText = RCDelayFormat(value, 1);
}

- (void)readoutTapped {
    double value = 0;
    if (!RCDelayNumberFromText(self.valueText, &value)) return;

    self.valueBeforeEditing = self.valueText;
    self.field.text = RCDelayFormat(MAX(0, MIN(86400, value)), 1);
    self.valueRow.hidden = YES;
    self.fieldWell.hidden = NO;
    [self.field becomeFirstResponder];
}

- (void)fieldChanged {
    self.valueText = self.field.text ?: @"";
}

- (void)commitField {
    double value = 0;
    if (RCDelayNumberFromText(self.field.text, &value)) {
        self.valueText = RCDelayFormat(MAX(0, MIN(86400, value)), 1);
    } else {
        self.valueText = self.valueBeforeEditing ?: @"0";
    }
    self.field.text = self.valueText;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self commitField];
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [self commitField];
    self.fieldWell.hidden = YES;
    self.valueRow.hidden = NO;
}

- (void)valueTextDidChange {
    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);

    if (numeric) {
        value = MAX(0, MIN(86400, value));
        self.readout.font = RCDelayDigitFontOfSize(36, UIFontTextStyleTitle1, UIFontWeightSemibold);
        self.readout.text = RCDelayFormat(value, 1);
        self.readout.userInteractionEnabled = YES;
        self.readout.accessibilityValue = [NSString stringWithFormat:@"%@ seconds", RCDelayFormat(value, 1)];
        self.readout.accessibilityTraits = UIAccessibilityTraitButton;
        self.unit.hidden = NO;
        self.minusButton.enabled = value > 0;
        self.plusButton.enabled = value < 86400;
    } else {
        self.readout.font = RCDelayMonoFont(22, UIFontTextStyleTitle3, UIFontWeightSemibold);
        self.readout.text = self.valueText;
        self.readout.userInteractionEnabled = NO;
        self.readout.accessibilityValue = self.valueText;
        self.readout.accessibilityTraits = UIAccessibilityTraitStaticText;
        self.unit.hidden = YES;
        self.minusButton.enabled = NO;
        self.plusButton.enabled = NO;
    }

    self.minusButton.alpha = self.minusButton.enabled ? 1.0 : 0.35;
    self.plusButton.alpha = self.plusButton.enabled ? 1.0 : 0.35;

    if (!self.field.isFirstResponder) {
        self.field.text = numeric ? RCDelayFormat(value, 1) : self.valueText;
    }
}

@end

RCDelayVariantView *RCDelayMakeStepperHold(void) {
    return [[RCDelayStepperHoldPanel alloc] initWithFrame:CGRectZero];
}
