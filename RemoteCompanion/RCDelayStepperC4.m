#import "RCDelayPrototypeKit.h"
#import "RCDelayStepperVariations.h"

#import <math.h>

// C4. A horizontal wheel of half-second detents. Drag the strip to move the
// selection, let go to snap, trim with minus and plus, tap the centre to type.

static const double RCDelayWheelUpperBound = 86400;
static const CGFloat RCDelayWheelStep = 0.5;

static NSArray<NSNumber *> *RCDelayWheelValues(void) {
    static NSArray<NSNumber *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSNumber *> *list = [NSMutableArray array];
        for (double value = RCDelayWheelStep; value <= 30.0001; value += RCDelayWheelStep) {
            [list addObject:@(value)];
        }
        [list addObjectsFromArray:@[@35, @40, @45, @50, @60]];
        values = list.copy;
    });
    return values;
}

static UIColor *RCDelayWheelMix(UIColor *from, UIColor *to, CGFloat amount, UITraitCollection *traits) {
    UIColor *start = [from resolvedColorWithTraitCollection:traits];
    UIColor *end = [to resolvedColorWithTraitCollection:traits];
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 1, r2 = 0, g2 = 0, b2 = 0, a2 = 1;
    if (![start getRed:&r1 green:&g1 blue:&b1 alpha:&a1]) return amount < 0.5 ? from : to;
    if (![end getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) return amount < 0.5 ? from : to;
    return [UIColor colorWithRed:r1 + (r2 - r1) * amount
                           green:g1 + (g2 - g1) * amount
                            blue:b1 + (b2 - b1) * amount
                           alpha:a1 + (a2 - a1) * amount];
}

@interface RCDelayStepperWheelPanel : RCDelayVariantView <UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIView *slotView;
@property (nonatomic, strong) UIScrollView *wheel;
@property (nonatomic, strong) UIStackView *strip;
@property (nonatomic, strong) NSArray<UILabel *> *items;
@property (nonatomic, strong) NSArray<NSNumber *> *detents;
@property (nonatomic, strong) UILabel *variableLabel;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, assign) CGFloat itemWidth;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) BOOL snapping;
@property (nonatomic, assign) BOOL editingExact;

@end

@implementation RCDelayStepperWheelPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIFont *itemFont = RCDelayDigitFontOfSize(24, UIFontTextStyleTitle2, UIFontWeightSemibold);
        CGFloat digitWidth = [@"000" sizeWithAttributes:@{ NSFontAttributeName: itemFont }].width;
        self.itemWidth = MAX(58, ceil(digitWidth) + 28);
        CGFloat cardHeight = ceil(itemFont.lineHeight) + 56;

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

        self.card = [[UIView alloc] init];
        self.card.backgroundColor = RCDelayBlockColor();
        self.card.layer.cornerRadius = 16;
        self.card.layer.borderWidth = 1;
        self.card.layer.masksToBounds = YES;
        self.card.translatesAutoresizingMaskIntoConstraints = NO;

        self.slotView = [[UIView alloc] init];
        self.slotView.userInteractionEnabled = NO;
        self.slotView.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *leftSlot = [[UIView alloc] init];
        leftSlot.backgroundColor = RCDelaySeparatorColor();
        leftSlot.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *rightSlot = [[UIView alloc] init];
        rightSlot.backgroundColor = RCDelaySeparatorColor();
        rightSlot.translatesAutoresizingMaskIntoConstraints = NO;
        [self.slotView addSubview:leftSlot];
        [self.slotView addSubview:rightSlot];

        self.wheel = [[UIScrollView alloc] init];
        self.wheel.delegate = self;
        self.wheel.showsHorizontalScrollIndicator = NO;
        self.wheel.showsVerticalScrollIndicator = NO;
        self.wheel.decelerationRate = UIScrollViewDecelerationRateFast;
        self.wheel.alwaysBounceHorizontal = YES;
        self.wheel.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        self.wheel.translatesAutoresizingMaskIntoConstraints = NO;

        self.strip = [[UIStackView alloc] init];
        self.strip.axis = UILayoutConstraintAxisHorizontal;
        self.strip.spacing = 0;
        self.strip.translatesAutoresizingMaskIntoConstraints = NO;
        [self.wheel addSubview:self.strip];

        self.variableLabel = [[UILabel alloc] init];
        self.variableLabel.font = RCDelayMonoFont(20, UIFontTextStyleTitle2, UIFontWeightSemibold);
        self.variableLabel.textColor = [UIColor labelColor];
        self.variableLabel.textAlignment = NSTextAlignmentCenter;
        self.variableLabel.adjustsFontSizeToFitWidth = YES;
        self.variableLabel.minimumScaleFactor = 0.5;
        self.variableLabel.hidden = YES;
        self.variableLabel.translatesAutoresizingMaskIntoConstraints = NO;

        self.field = [self makeNumberField];
        self.field.font = RCDelayDigitFontOfSize(22, UIFontTextStyleTitle2, UIFontWeightSemibold);
        self.field.textAlignment = NSTextAlignmentCenter;
        self.field.backgroundColor = RCDelayPageColor();
        self.field.layer.cornerRadius = 10;
        self.field.layer.borderWidth = 1;
        self.field.hidden = YES;
        [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
        [self.field addTarget:self action:@selector(editingEnded) forControlEvents:UIControlEventEditingDidEnd];

        [self.card addSubview:self.slotView];
        [self.card addSubview:self.wheel];
        [self.card addSubview:self.variableLabel];
        [self.card addSubview:self.field];

        self.minusButton = [self stepButtonNamed:@"minus" label:@"Decrease by half a second"];
        self.plusButton = [self stepButtonNamed:@"plus" label:@"Increase by half a second"];
        [self.minusButton addTarget:self action:@selector(stepDown) forControlEvents:UIControlEventTouchUpInside];
        [self.plusButton addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside];

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.minusButton, self.card, self.plusButton]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentCenter;
        row.spacing = 10;
        row.translatesAutoresizingMaskIntoConstraints = NO;

        [NSLayoutConstraint activateConstraints:@[
            [self.card.heightAnchor constraintEqualToConstant:cardHeight],
            [self.slotView.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
            [self.slotView.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
            [self.slotView.topAnchor constraintEqualToAnchor:self.card.topAnchor],
            [self.slotView.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],
            [leftSlot.centerXAnchor constraintEqualToAnchor:self.slotView.centerXAnchor constant:-self.itemWidth / 2],
            [leftSlot.centerYAnchor constraintEqualToAnchor:self.slotView.centerYAnchor],
            [leftSlot.widthAnchor constraintEqualToConstant:1],
            [leftSlot.heightAnchor constraintEqualToAnchor:self.slotView.heightAnchor multiplier:0.56],
            [rightSlot.centerXAnchor constraintEqualToAnchor:self.slotView.centerXAnchor constant:self.itemWidth / 2],
            [rightSlot.centerYAnchor constraintEqualToAnchor:self.slotView.centerYAnchor],
            [rightSlot.widthAnchor constraintEqualToConstant:1],
            [rightSlot.heightAnchor constraintEqualToAnchor:self.slotView.heightAnchor multiplier:0.56],
            [self.wheel.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:4],
            [self.wheel.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-4],
            [self.wheel.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:12],
            [self.wheel.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-12],
            [self.strip.leadingAnchor constraintEqualToAnchor:self.wheel.contentLayoutGuide.leadingAnchor],
            [self.strip.trailingAnchor constraintEqualToAnchor:self.wheel.contentLayoutGuide.trailingAnchor],
            [self.strip.topAnchor constraintEqualToAnchor:self.wheel.contentLayoutGuide.topAnchor],
            [self.strip.bottomAnchor constraintEqualToAnchor:self.wheel.contentLayoutGuide.bottomAnchor],
            [self.strip.heightAnchor constraintEqualToAnchor:self.wheel.frameLayoutGuide.heightAnchor],
            [self.variableLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.card.leadingAnchor constant:16],
            [self.variableLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.card.trailingAnchor constant:-16],
            [self.variableLabel.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],
            [self.variableLabel.centerYAnchor constraintEqualToAnchor:self.card.centerYAnchor],
            [self.field.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:24],
            [self.field.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-24],
            [self.field.centerYAnchor constraintEqualToAnchor:self.card.centerYAnchor],
            [self.field.heightAnchor constraintEqualToConstant:MAX(40, ceil(self.field.font.lineHeight) + 14)],
        ]];

        UITapGestureRecognizer *cardTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
        cardTap.cancelsTouchesInView = NO;
        cardTap.delegate = self;
        [self.card addGestureRecognizer:cardTap];

        UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissTyping)];
        dismissTap.cancelsTouchesInView = NO;
        dismissTap.delegate = self;
        [self addGestureRecognizer:dismissTap];

        [stack addArrangedSubview:header];
        [stack addArrangedSubview:row];
        [stack addArrangedSubview:RCDelayNoteLabel(@"Snap to a value, then trim with minus and plus.")];

        [self applyColors];
        [self valueTextDidChange];
    }
    return self;
}

- (UIButton *)stepButtonNamed:(NSString *)symbol label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                               weight:UIImageSymbolWeightSemibold]]
            forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = RCDelayBlockColor();
    button.layer.cornerRadius = 18;
    button.layer.borderWidth = 1;
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:36],
        [button.heightAnchor constraintEqualToConstant:36],
    ]];
    return button;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateWheelInset];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyColors];
    [self updateWheelStyles];
}

- (void)applyColors {
    UIColor *border = [RCDelayBorderColor() resolvedColorWithTraitCollection:self.traitCollection];
    self.card.layer.borderColor = border.CGColor;
    self.field.layer.borderColor = border.CGColor;
    self.minusButton.layer.borderColor = border.CGColor;
    self.plusButton.layer.borderColor = border.CGColor;
}

- (void)updateWheelInset {
    CGFloat width = CGRectGetWidth(self.wheel.bounds);
    if (width <= 0) return;
    CGFloat inset = MAX(0, (width - self.itemWidth) / 2);
    if (fabs(self.wheel.contentInset.left - inset) < 0.5) return;
    self.wheel.contentInset = UIEdgeInsetsMake(0, inset, 0, inset);
    [self.wheel setContentOffset:CGPointMake(self.selectedIndex * self.itemWidth - inset, 0) animated:NO];
    [self updateWheelStyles];
}

- (void)rebuildStripWithDetents:(NSArray<NSNumber *> *)detents {
    for (UIView *view in self.strip.arrangedSubviews) {
        [self.strip removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (NSNumber *detent in detents) {
        UILabel *label = [[UILabel alloc] init];
        label.text = RCDelayFormat(detent.doubleValue, 1);
        label.font = RCDelayDigitFontOfSize(24, UIFontTextStyleTitle2, UIFontWeightSemibold);
        label.textColor = [UIColor labelColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label.widthAnchor constraintEqualToConstant:self.itemWidth].active = YES;
        [labels addObject:label];
        [self.strip addArrangedSubview:label];
    }
    self.items = labels;
    self.detents = detents;
}

- (NSInteger)indexOfValue:(double)value inDetents:(NSArray<NSNumber *> *)detents {
    for (NSInteger index = 0; index < (NSInteger)detents.count; index++) {
        if (fabs(detents[index].doubleValue - value) < 0.0001) return index;
    }
    return NSNotFound;
}

- (void)showWheelValue:(double)value {
    double clamped = MAX(0, MIN(RCDelayWheelUpperBound, value));
    NSMutableArray<NSNumber *> *detents = [RCDelayWheelValues() mutableCopy];
    NSInteger index = [self indexOfValue:clamped inDetents:detents];
    if (index == NSNotFound) {
        NSInteger insert = 0;
        while (insert < (NSInteger)detents.count && detents[insert].doubleValue < clamped) insert++;
        [detents insertObject:@(clamped) atIndex:insert];
        index = insert;
    }

    BOOL changed = ![detents isEqualToArray:self.detents];
    if (changed) {
        [self rebuildStripWithDetents:detents];
        [self.wheel layoutIfNeeded];
    }
    self.selectedIndex = index;

    CGFloat target = index * self.itemWidth - self.wheel.contentInset.left;
    if (changed || fabs(self.wheel.contentOffset.x - target) > 0.5) {
        [self.wheel setContentOffset:CGPointMake(target, 0) animated:NO];
    }
    [self updateWheelStyles];
}

- (void)updateWheelStyles {
    if (!self.items.count || self.itemWidth <= 0) return;
    CGFloat position = (self.wheel.contentOffset.x + self.wheel.contentInset.left) / self.itemWidth;
    for (NSInteger index = 0; index < (NSInteger)self.items.count; index++) {
        UILabel *label = self.items[index];
        CGFloat distance = fabs((CGFloat)index - position);
        CGFloat amount = MIN(1.0, distance / 1.6);
        CGFloat scale = 1.26 - 0.50 * amount;
        label.transform = CGAffineTransformMakeScale(scale, scale);
        label.alpha = 1.0 - 0.50 * amount;
        label.textColor = RCDelayWheelMix([UIColor labelColor], [UIColor secondaryLabelColor],
                                          MIN(1.0, amount * 1.35), self.traitCollection);
    }
}

- (void)snapWheel {
    if (!self.detents.count || self.itemWidth <= 0) return;
    CGFloat inset = self.wheel.contentInset.left;
    CGFloat position = (self.wheel.contentOffset.x + inset) / self.itemWidth;
    NSInteger index = (NSInteger)lround(position);
    index = MAX(0, MIN((NSInteger)self.detents.count - 1, index));
    self.selectedIndex = index;

    CGFloat target = index * self.itemWidth - inset;
    if (fabs(self.wheel.contentOffset.x - target) < 0.5) {
        [self.wheel setContentOffset:CGPointMake(target, 0) animated:NO];
        [self commitSelectedValue];
    } else {
        self.snapping = YES;
        [self.wheel setContentOffset:CGPointMake(target, 0) animated:YES];
    }
}

- (void)commitSelectedValue {
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.detents.count) return;
    double value = self.detents[self.selectedIndex].doubleValue;
    NSString *text = RCDelayFormat(value, 1);
    if (![self.valueText isEqualToString:text]) self.valueText = text;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self updateWheelStyles];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.snapping = NO;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) [self snapWheel];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self snapWheel];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (!self.snapping) return;
    self.snapping = NO;
    [self commitSelectedValue];
}

- (void)stepDown {
    [self stepBy:-RCDelayWheelStep];
}

- (void)stepUp {
    [self stepBy:RCDelayWheelStep];
}

- (void)stepBy:(double)delta {
    if (self.editingExact) [self endEditing:YES];
    double value = 0;
    if (!RCDelayNumberFromText(self.valueText, &value)) return;
    value = MAX(0, MIN(RCDelayWheelUpperBound, round((value + delta) * 2) / 2));
    self.valueText = RCDelayFormat(value, 1);
}

- (void)cardTapped:(UITapGestureRecognizer *)tap {
    if (self.editingExact) return;
    if (self.wheel.isDragging || self.wheel.isDecelerating) return;
    if (!self.wheel.hidden) {
        CGPoint point = [tap locationInView:self.card];
        if (fabs(point.x - CGRectGetMidX(self.card.bounds)) > self.itemWidth * 0.7) return;
    }
    [self beginTyping];
}

- (void)beginTyping {
    self.editingExact = YES;
    self.snapping = NO;
    [self.wheel setContentOffset:self.wheel.contentOffset animated:NO];
    self.field.text = self.valueText;
    self.wheel.hidden = YES;
    self.slotView.hidden = YES;
    self.variableLabel.hidden = YES;
    self.field.hidden = NO;
    [self.field becomeFirstResponder];
}

- (void)textChanged {
    self.valueText = self.field.text ?: @"";
}

- (void)editingEnded {
    if (!self.editingExact) return;
    self.editingExact = NO;
    self.field.hidden = YES;

    double value = 0;
    if (RCDelayNumberFromText(self.valueText, &value) && (value < 0 || value > RCDelayWheelUpperBound)) {
        self.valueText = RCDelayFormat(MAX(0, MIN(RCDelayWheelUpperBound, value)), 1);
    } else {
        [self valueTextDidChange];
    }
}

- (void)dismissTyping {
    if (self.editingExact) [self endEditing:YES];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isDescendantOfView:self.field];
}

- (void)valueTextDidChange {
    if (self.field.hidden && ![self.field.text isEqualToString:self.valueText]) {
        self.field.text = self.valueText;
    }

    double value = 0;
    BOOL numeric = RCDelayNumberFromText(self.valueText, &value);
    if (numeric) {
        value = MAX(0, MIN(RCDelayWheelUpperBound, value));
        if (!self.editingExact) [self showWheelValue:value];
        self.wheel.hidden = self.editingExact;
        self.variableLabel.hidden = YES;
        self.minusButton.enabled = value > 0;
        self.plusButton.enabled = value < RCDelayWheelUpperBound;
    } else {
        self.wheel.hidden = YES;
        self.variableLabel.hidden = self.editingExact;
        self.variableLabel.text = self.valueText.length ? self.valueText : @"–";
        self.minusButton.enabled = NO;
        self.plusButton.enabled = NO;
    }
    self.slotView.hidden = self.wheel.hidden;
    self.minusButton.alpha = self.minusButton.enabled ? 1.0 : 0.35;
    self.plusButton.alpha = self.plusButton.enabled ? 1.0 : 0.35;
}

@end

RCDelayVariantView *RCDelayMakeStepperWheel(void) {
    return [[RCDelayStepperWheelPanel alloc] initWithFrame:CGRectZero];
}
