#import "RCDelayStepperVariations.h"

#import <math.h>

// ---------------------------------------------------------------------------
// TEMPORARY DESIGN PROTOTYPE - C3, drag the number
//
// Nothing here is referenced by the shipping Delay flow.
// ---------------------------------------------------------------------------

@interface RCDelayStepperScrubPanel : RCDelayVariantView <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *hero;
@property (nonatomic, strong) UIView *valueCard;
@property (nonatomic, strong) UIStackView *valueRow;
@property (nonatomic, strong) UILabel *readout;
@property (nonatomic, strong) UILabel *unit;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UIPanGestureRecognizer *scrubGesture;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (nonatomic, strong) UISelectionFeedbackGenerator *tick;
@property (nonatomic, assign) double panStartValue;
@property (nonatomic, assign) long panStep;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, copy) NSString *valueBeforeEditing;
@end

@implementation RCDelayStepperScrubPanel

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
        title.translatesAutoresizingMaskIntoConstraints = NO;
        UIButton *variable = [self makeVariableButton];
        variable.translatesAutoresizingMaskIntoConstraints = NO;
        UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, variable]];
        header.axis = UILayoutConstraintAxisHorizontal;
        header.alignment = UIStackViewAlignmentCenter;
        header.spacing = 8;
        [NSLayoutConstraint activateConstraints:@[
            [variable.widthAnchor constraintEqualToConstant:34],
            [variable.heightAnchor constraintEqualToConstant:34],
        ]];

        self.hero = [[UIView alloc] init];
        self.hero.backgroundColor = RCDelayBlockColor();
        self.hero.layer.cornerRadius = 16;
        self.hero.layer.borderWidth = 1;
        self.hero.translatesAutoresizingMaskIntoConstraints = NO;

        self.minusButton = [self stepButtonNamed:@"minus" label:@"Decrease by half a second"];
        self.plusButton = [self stepButtonNamed:@"plus" label:@"Increase by half a second"];
        [self.minusButton addTarget:self action:@selector(stepDown) forControlEvents:UIControlEventTouchUpInside];
        [self.plusButton addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside];

        self.valueCard = [[UIView alloc] init];
        self.valueCard.backgroundColor = RCDelayPageColor();
        self.valueCard.layer.cornerRadius = 12;
        self.valueCard.layer.borderWidth = 1;
        self.valueCard.translatesAutoresizingMaskIntoConstraints = NO;

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
        [self.unit setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        self.unit.translatesAutoresizingMaskIntoConstraints = NO;

        self.valueRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.readout, self.unit]];
        self.valueRow.axis = UILayoutConstraintAxisHorizontal;
        self.valueRow.alignment = UIStackViewAlignmentLastBaseline;
        self.valueRow.spacing = 3;
        self.valueRow.translatesAutoresizingMaskIntoConstraints = NO;

        self.field = [self makeNumberField];
        self.field.textAlignment = NSTextAlignmentCenter;
        self.field.hidden = YES;
        [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
        [self.field addTarget:self action:@selector(editingEnded) forControlEvents:UIControlEventEditingDidEnd];

        self.tick = [[UISelectionFeedbackGenerator alloc] init];

        self.scrubGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrubbed:)];
        self.scrubGesture.delegate = self;
        [self.valueCard addGestureRecognizer:self.scrubGesture];

        self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        self.tapGesture.delegate = self;
        [self.tapGesture requireGestureRecognizerToFail:self.scrubGesture];
        [self.valueCard addGestureRecognizer:self.tapGesture];

        [self.valueCard addSubview:self.valueRow];
        [self.valueCard addSubview:self.field];
        [self.hero addSubview:self.minusButton];
        [self.hero addSubview:self.plusButton];
        [self.hero addSubview:self.valueCard];
        [NSLayoutConstraint activateConstraints:@[
            [self.minusButton.leadingAnchor constraintEqualToAnchor:self.hero.leadingAnchor constant:12],
            [self.minusButton.centerYAnchor constraintEqualToAnchor:self.hero.centerYAnchor],
            [self.plusButton.trailingAnchor constraintEqualToAnchor:self.hero.trailingAnchor constant:-12],
            [self.plusButton.centerYAnchor constraintEqualToAnchor:self.hero.centerYAnchor],
            [self.valueCard.leadingAnchor constraintEqualToAnchor:self.minusButton.trailingAnchor constant:10],
            [self.valueCard.trailingAnchor constraintEqualToAnchor:self.plusButton.leadingAnchor constant:-10],
            [self.valueCard.topAnchor constraintEqualToAnchor:self.hero.topAnchor constant:10],
            [self.valueCard.bottomAnchor constraintEqualToAnchor:self.hero.bottomAnchor constant:-10],
            [self.valueRow.centerXAnchor constraintEqualToAnchor:self.valueCard.centerXAnchor],
            [self.valueRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.valueCard.leadingAnchor constant:14],
            [self.valueRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.valueCard.trailingAnchor constant:-14],
            [self.valueRow.topAnchor constraintEqualToAnchor:self.valueCard.topAnchor constant:12],
            [self.valueRow.bottomAnchor constraintEqualToAnchor:self.valueCard.bottomAnchor constant:-12],
            [self.field.leadingAnchor constraintEqualToAnchor:self.valueCard.leadingAnchor constant:14],
            [self.field.trailingAnchor constraintEqualToAnchor:self.valueCard.trailingAnchor constant:-14],
            [self.field.topAnchor constraintEqualToAnchor:self.valueCard.topAnchor],
            [self.field.bottomAnchor constraintEqualToAnchor:self.valueCard.bottomAnchor],
        ]];

        [stack addArrangedSubview:header];
        [stack addArrangedSubview:self.hero];
        [stack addArrangedSubview:RCDelayNoteLabel(@"Drag the number, or nudge it with minus and plus.")];

        [self valueTextDidChange];
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.userInteractionEnabled) return;
    UIView *view = self.superview;
    while (view && ![view isKindOfClass:[UIScrollView class]]) view = view.superview;
    [((UIScrollView *)view).panGestureRecognizer requireGestureRecognizerToFail:self.scrubGesture];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIColor *border = [RCDelayBorderColor() resolvedColorWithTraitCollection:self.traitCollection];
    self.hero.layer.borderColor = border.CGColor;
    self.valueCard.layer.borderColor = border.CGColor;
}

- (UIButton *)stepButtonNamed:(NSString *)symbol label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                               weight:UIImageSymbolWeightSemibold]]
            forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = 18;
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:36],
        [button.heightAnchor constraintEqualToConstant:36],
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
    [self applyValue:value + delta];
}

- (void)applyValue:(double)value {
    value = MAX(0, MIN(86400, round(value * 2) / 2));
    self.valueText = RCDelayFormat(value, 1);
}

- (void)scrubbed:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        double value = 0;
        if (!RCDelayNumberFromText(self.valueText, &value)) return;
        self.panStartValue = value;
        self.panStep = lround(value * 2);
        self.dragging = YES;
        [self.tick prepare];
        return;
    }
    if (pan.state == UIGestureRecognizerStateChanged) {
        if (!self.isDragging) return;
        double value = self.panStartValue - [pan translationInView:self].y / 48.0;
        value = MAX(0, MIN(86400, round(value * 2) / 2));
        long step = lround(value * 2);
        if (step != self.panStep) {
            self.panStep = step;
            [self.tick selectionChanged];
            [self.tick prepare];
        }
        self.valueText = RCDelayFormat(value, 1);
        return;
    }
    self.dragging = NO;
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (!self.field.hidden) {
        [self.field resignFirstResponder];
        return;
    }
    self.valueBeforeEditing = self.valueText;
    self.field.text = self.valueText;
    self.field.hidden = NO;
    self.valueRow.hidden = YES;
    [self.field becomeFirstResponder];
    [self.field selectAll:nil];
}

- (void)insertVariableNamed:(NSString *)name {
    if (!self.field.hidden) [self.field resignFirstResponder];
    [super insertVariableNamed:name];
}

- (void)editingEnded {
    self.field.hidden = YES;
    self.valueRow.hidden = NO;

    double value = 0;
    if (RCDelayNumberFromText(self.valueText, &value)) {
        self.valueText = RCDelayFormat(MAX(0, MIN(86400, value)), 1);
    } else {
        self.valueText = self.valueBeforeEditing ?: @"0";
    }
}

- (void)setDragging:(BOOL)dragging {
    if (_dragging == dragging) return;
    _dragging = dragging;
    [UIView animateWithDuration:0.18
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.valueCard.backgroundColor = dragging ? RCDelaySeparatorColor() : RCDelayPageColor();
        self.valueCard.transform = dragging ? CGAffineTransformMakeScale(1.02, 1.02) : CGAffineTransformIdentity;
    } completion:nil];
}

- (void)valueTextDidChange {
    if (self.field.isHidden) self.field.text = self.valueText;

    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    if (numeric) {
        value = MAX(0, MIN(86400, value));
        self.readout.font = RCDelayDigitFontOfSize(36, UIFontTextStyleTitle1, UIFontWeightSemibold);
        self.readout.text = RCDelayFormat(value, 1);
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

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.scrubGesture) return YES;
    if (!self.field.isHidden) return NO;
    double value = 0;
    return RCDelayNumberFromText(self.valueText, &value);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer != self.tapGesture) return YES;
    return ![touch.view isDescendantOfView:self.field];
}

@end

RCDelayVariantView *RCDelayMakeStepperScrub(void) {
    return [[RCDelayStepperScrubPanel alloc] initWithFrame:CGRectZero];
}
