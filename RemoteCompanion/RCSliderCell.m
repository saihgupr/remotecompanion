#import "RCSliderCell.h"
#import "RCConfigManager.h"

@interface RCSliderCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *valueButton;
// Back to the default when the value is another; after that, Undo puts the value from before back
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) NSNumber *undoValue;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UIButton *lockButton;
// Default / Undo and the lock are held, not tapped: a ring around the button fills, and it acts once full
@property (nonatomic, strong) CAShapeLayer *lockRing;
@property (nonatomic, strong) CAShapeLayer *resetRing;
@property (nonatomic, strong) NSTimer *holdTimer;
@property (nonatomic, strong) UIView *defaultTick;
@property (nonatomic, strong) NSLayoutConstraint *tickCenter;
@property (nonatomic, strong) NSTimer *repeatTimer;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *format;
@property (nonatomic) double value, min, max, step, defaultValue;
@end

@implementation RCSliderCell

+ (CGFloat)rowHeight { return 92; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:17];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.adjustsFontSizeToFitWidth = YES; // a long name beside a long value
    _titleLabel.minimumScaleFactor = 0.85;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];

    _valueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _valueButton.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular];
    [_valueButton setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    _valueButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    _valueButton.translatesAutoresizingMaskIntoConstraints = NO;
    _valueButton.accessibilityHint = @"Type a value";
    [_valueButton addTarget:self action:@selector(valueTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_valueButton];

    // A round button like − and +, before them: dimmed at the default with nothing to undo
    _resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _resetButton.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"selectionHighlight" defaultVal:0.2];
    _resetButton.layer.cornerRadius = 16;
    _resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_resetButton addTarget:self action:@selector(holdPressed:) forControlEvents:UIControlEventTouchDown];
    [_resetButton addTarget:self action:@selector(holdReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    _resetButton.accessibilityHint = @"Double-tap and hold";
    _resetRing = [self ringOn:_resetButton];
    [self.contentView addSubview:_resetButton];

    _slider = [[UISlider alloc] init];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.minimumTrackTintColor = [UIColor systemBlueColor];
    [_slider addTarget:self action:@selector(sliderMoved) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(sliderReleased) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.contentView addSubview:_slider];

    // The default's place on the track, a small mark under it
    _defaultTick = [[UIView alloc] init];
    _defaultTick.backgroundColor = [UIColor tertiaryLabelColor];
    _defaultTick.layer.cornerRadius = 1;
    _defaultTick.translatesAutoresizingMaskIntoConstraints = NO;
    _defaultTick.userInteractionEnabled = NO;
    [self.contentView insertSubview:_defaultTick belowSubview:_slider];

    _minusButton = [self stepButton:@"minus"];
    _plusButton = [self stepButton:@"plus"];

    // After +: locks the value (the slider, −, + and Default stop changing it)
    _lockButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _lockButton.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"selectionHighlight" defaultVal:0.2];
    _lockButton.layer.cornerRadius = 16;
    _lockButton.translatesAutoresizingMaskIntoConstraints = NO;
    _lockButton.hidden = YES;
    // Held, not tapped: a ring around it fills, and the lock changes once it's full
    [_lockButton addTarget:self action:@selector(holdPressed:) forControlEvents:UIControlEventTouchDown];
    [_lockButton addTarget:self action:@selector(holdReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    _lockButton.accessibilityHint = @"Double-tap and hold";
    [self.contentView addSubview:_lockButton];
    _lockRing = [self ringOn:_lockButton];

    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
    _tickCenter = [_defaultTick.centerXAnchor constraintEqualToAnchor:_slider.leadingAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        [_valueButton.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_valueButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_valueButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8],
        [_resetButton.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor constant:-6],
        [_resetButton.centerYAnchor constraintEqualToAnchor:_slider.centerYAnchor],
        [_resetButton.widthAnchor constraintEqualToConstant:32],
        [_resetButton.heightAnchor constraintEqualToConstant:32],
        [_valueButton.heightAnchor constraintGreaterThanOrEqualToConstant:32],
        [_minusButton.leadingAnchor constraintEqualToAnchor:_resetButton.trailingAnchor constant:8],
        [_minusButton.centerYAnchor constraintEqualToAnchor:_slider.centerYAnchor],
        [_lockButton.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor constant:6],
        [_lockButton.centerYAnchor constraintEqualToAnchor:_slider.centerYAnchor],
        [_lockButton.widthAnchor constraintEqualToConstant:32],
        [_lockButton.heightAnchor constraintEqualToConstant:32],
        [_plusButton.trailingAnchor constraintEqualToAnchor:_lockButton.leadingAnchor constant:-8],
        [_plusButton.centerYAnchor constraintEqualToAnchor:_slider.centerYAnchor],
        [_slider.leadingAnchor constraintEqualToAnchor:_minusButton.trailingAnchor constant:6],
        [_slider.trailingAnchor constraintEqualToAnchor:_plusButton.leadingAnchor constant:-6],
        [_slider.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:12],
        [_defaultTick.widthAnchor constraintEqualToConstant:2],
        [_defaultTick.heightAnchor constraintEqualToConstant:8],
        [_defaultTick.topAnchor constraintEqualToAnchor:_slider.centerYAnchor constant:6],
        _tickCenter,
    ]];
    return self;
}

- (UIButton *)stepButton:(NSString *)symbol {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]];
    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"selectionHighlight" defaultVal:0.2];
    button.layer.cornerRadius = 16;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = [symbol isEqualToString:@"plus"] ? @"More" : @"Less";
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:32],
        [button.heightAnchor constraintEqualToConstant:32],
    ]];
    [button addTarget:self action:@selector(stepDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.contentView addSubview:button];
    return button;
}

- (void)setTitle:(NSString *)title value:(double)value min:(double)min max:(double)max
            step:(double)step defaultValue:(double)defaultValue format:(NSString *)format {
    self.title = title;
    self.format = format ?: @"%.0f";
    self.min = min;
    self.max = MAX(max, min);
    self.step = step > 0 ? step : 1;
    self.defaultValue = defaultValue;
    self.titleLabel.text = title;
    self.slider.minimumValue = min;
    self.slider.maximumValue = self.max;
    self.accessibilityLabel = title;
    [self showValue:[self rounded:value]];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // The mark sits under where the thumb's center is at the default value. The slider has to have
    // its final width first (on the first pass it doesn't yet, which put the mark in the wrong place
    // until the slider was moved)
    [self.contentView layoutIfNeeded];
    CGRect track = [self.slider trackRectForBounds:self.slider.bounds];
    CGRect thumb = [self.slider thumbRectForBounds:self.slider.bounds trackRect:track value:self.defaultValue];
    CGFloat center = CGRectGetMidX(thumb);
    if (fabs(self.tickCenter.constant - center) > 0.5) self.tickCenter.constant = center;
    self.defaultTick.hidden = self.max <= self.min;
}

- (double)rounded:(double)value {
    double steps = round((value - self.min) / self.step);
    double result = self.min + steps * self.step;
    // two decimals is as fine as any setting goes; keeps 0.35 from becoming 0.35000000000000003
    result = round(result * 100.0) / 100.0;
    return MIN(MAX(result, self.min), self.max);
}

- (NSString *)textForValue:(double)value {
    return [NSString stringWithFormat:self.format, value];
}

- (void)showValue:(double)value {
    _value = value;
    self.slider.value = value;
    BOOL isDefault = fabs(value - self.defaultValue) < self.step / 2.0;
    if (!isDefault) self.undoValue = nil;
    NSString *text = [self textForValue:value];
    [UIView performWithoutAnimation:^{
        [self.valueButton setTitle:isDefault ? [text stringByAppendingString:@" (Default)"] : text forState:UIControlStateNormal];
        [self.valueButton layoutIfNeeded];
    }];
    self.accessibilityValue = text;
    // Reset at any value but the default; Undo right after a reset, until the value changes again
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    [UIView performWithoutAnimation:^{
        if (self.undoValue) {
            [self.resetButton setImage:[UIImage systemImageNamed:@"arrow.uturn.backward" withConfiguration:config] forState:UIControlStateNormal];
            self.resetButton.tintColor = [UIColor systemBlueColor];
            self.resetButton.accessibilityLabel = [NSString stringWithFormat:@"Undo, back to %@", [self textForValue:self.undoValue.doubleValue]];
        } else {
            [self.resetButton setImage:[UIImage systemImageNamed:@"arrow.counterclockwise" withConfiguration:config] forState:UIControlStateNormal];
            self.resetButton.tintColor = [UIColor labelColor];
            self.resetButton.accessibilityLabel = [NSString stringWithFormat:@"Back to the default, %@", [self textForValue:self.defaultValue]];
        }
        [self.resetButton layoutIfNeeded];
    }];
    BOOL locked = [self locked];
    self.resetButton.enabled = !locked && (!isDefault || self.undoValue != nil);
    self.resetButton.alpha = self.resetButton.enabled ? 1.0 : 0.35;
    self.minusButton.enabled = !locked && value > self.min + self.step / 2.0;
    self.plusButton.enabled = !locked && value < self.max - self.step / 2.0;
    self.slider.enabled = !locked;
    self.lockButton.hidden = self.lockKey.length == 0;
    [UIView performWithoutAnimation:^{
        [self.lockButton setImage:[UIImage systemImageNamed:locked ? @"lock.fill" : @"lock.open" withConfiguration:config] forState:UIControlStateNormal];
        [self.lockButton layoutIfNeeded];
    }];
    self.lockButton.tintColor = locked ? [UIColor systemOrangeColor] : [UIColor secondaryLabelColor];
    self.lockButton.accessibilityLabel = locked ? @"Locked" : @"Lock";
    self.lockButton.accessibilityHint = locked ? @"Lets the value be changed again" : @"Keeps the value from being changed";
}

- (void)commit:(double)value {
    [self showValue:value];
    if (self.onChange) self.onChange(value);
}

#pragma mark - Slider

- (void)sliderMoved {
    double value = [self rounded:self.slider.value];
    if (fabs(value - _value) < self.step / 2.0) return;
    // a light tick at each step, and a firmer one on the default
    BOOL isDefault = fabs(value - self.defaultValue) < self.step / 2.0;
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    if (isDefault) [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self showValue:value];
    if (self.onSlide) self.onSlide(value);
}

- (void)sliderReleased {
    [self commit:[self rounded:self.slider.value]];
}

#pragma mark - − and +

- (void)stepDown:(UIButton *)sender {
    [self stepBy:(sender == self.plusButton ? 1 : -1)];
    [self.repeatTimer invalidate];
    __weak typeof(self) weakSelf = self;
    double direction = sender == self.plusButton ? 1 : -1;
    // held: repeats after a moment, then faster
    self.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.45 repeats:NO block:^(NSTimer *t) {
        weakSelf.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.08 repeats:YES block:^(NSTimer *timer) {
            [weakSelf stepBy:direction];
        }];
    }];
}

- (void)stepUp {
    [self.repeatTimer invalidate];
    self.repeatTimer = nil;
}

- (void)stepBy:(double)direction {
    double value = [self rounded:_value + direction * self.step];
    if (fabs(value - _value) < self.step / 2.0) { [self stepUp]; return; }
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [self commit:value];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self stepUp];
}

- (void)removeFromSuperview {
    [self stepUp];
    [super removeFromSuperview];
}

#pragma mark - Lock

// Kept in the config, so the Web UI and Adjust on Screen respect it too
- (BOOL)locked {
    return self.lockKey.length && [[RCConfigManager sharedManager] isSettingLocked:self.lockKey];
}

- (void)setLocked:(BOOL)locked {
    if (!self.lockKey.length) return;
    [self stepUp];
    [[RCConfigManager sharedManager] setSetting:self.lockKey locked:locked];
    [self showValue:_value];
}

- (void)setLockKey:(NSString *)lockKey {
    _lockKey = [lockKey copy];
    [self showValue:_value];
}

static const NSTimeInterval RCHoldTime = 0.6;

// The ring around a 32-point round button, empty to begin with
- (CAShapeLayer *)ringOn:(UIButton *)button {
    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.fillColor = [UIColor clearColor].CGColor;
    ring.lineWidth = 2.5;
    ring.lineCap = kCALineCapRound;
    ring.strokeEnd = 0;
    ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(16, 16) radius:17.5 startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES].CGPath;
    [button.layer addSublayer:ring];
    return ring;
}

- (CAShapeLayer *)ringForButton:(UIButton *)button {
    return button == self.lockButton ? self.lockRing : self.resetRing;
}

- (void)holdPressed:(UIButton *)button {
    [self.holdTimer invalidate];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    CAShapeLayer *ring = [self ringForButton:button];
    UIColor *color = button == self.lockButton ? ([self locked] ? [UIColor secondaryLabelColor] : [UIColor systemOrangeColor])
                                               : (self.undoValue ? [UIColor systemBlueColor] : [UIColor labelColor]);
    ring.strokeColor = color.CGColor;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    ring.strokeEnd = 1;
    [CATransaction commit];
    CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    fill.fromValue = @0;
    fill.toValue = @1;
    fill.duration = RCHoldTime;
    [ring addAnimation:fill forKey:@"fill"];
    __weak typeof(self) weakSelf = self;
    self.holdTimer = [NSTimer scheduledTimerWithTimeInterval:RCHoldTime repeats:NO block:^(NSTimer *timer) {
        weakSelf.holdTimer = nil;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
        if (button == weakSelf.lockButton) [weakSelf setLocked:![weakSelf locked]];
        else [weakSelf resetHeld];
        [weakSelf clearRing:ring];
    }];
}

// Let go before the ring is full: nothing happens, and the ring empties. A quick tap still fills a
// quarter of it first, so it's plain the button wants holding.
- (void)holdReleased:(UIButton *)button {
    if (!self.holdTimer) return;
    [self.holdTimer invalidate];
    self.holdTimer = nil;
    CAShapeLayer *ring = [self ringForButton:button];
    CGFloat shown = [(CAShapeLayer *)ring.presentationLayer strokeEnd];
    if (shown >= 0.25) { [self clearRing:ring]; return; }
    [ring removeAnimationForKey:@"fill"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    ring.strokeEnd = 0;
    [CATransaction commit];
    CAKeyframeAnimation *nudge = [CAKeyframeAnimation animationWithKeyPath:@"strokeEnd"];
    nudge.values = @[@(shown), @0.25, @0.25, @0];
    nudge.keyTimes = @[@0, @0.3, @0.55, @1];
    nudge.duration = 0.6;
    [ring addAnimation:nudge forKey:@"empty"];
}

- (void)clearRing:(CAShapeLayer *)ring {
    CGFloat shown = [(CAShapeLayer *)ring.presentationLayer strokeEnd];
    [ring removeAnimationForKey:@"fill"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    ring.strokeEnd = 0;
    [CATransaction commit];
    CABasicAnimation *empty = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    empty.fromValue = @(shown);
    empty.toValue = @0;
    empty.duration = 0.15;
    [ring addAnimation:empty forKey:@"empty"];
}

#pragma mark - Default and Undo

// Held to the end of its ring: the default, or (right after that) the value from before
- (void)resetHeld {
    if (self.undoValue) {
        double previous = self.undoValue.doubleValue;
        self.undoValue = nil;
        [self commit:[self rounded:previous]];
        return;
    }
    double previous = _value;
    double fallback = [self rounded:self.defaultValue];
    self.undoValue = @(previous);
    [self commit:fallback];
}

#pragma mark - Typing

- (void)valueTapped {
    UIViewController *presenter = self.presenter;
    if (!presenter) return;
    NSString *range = [NSString stringWithFormat:@"%@ to %@. Default %@.", [self textForValue:self.min], [self textForValue:self.max], [self textForValue:self.defaultValue]];
    NSString *message = self.message.length ? [NSString stringWithFormat:@"%@\n\n%@", self.message, range] : range;
    __weak typeof(self) weakSelf = self;
    if ([self locked]) {
        // The same information; the value stays until it's unlocked
        message = [message stringByAppendingFormat:@"\n\nLocked at %@.", [self textForValue:self.value]];
        UIAlertController *info = [UIAlertController alertControllerWithTitle:self.title message:message preferredStyle:UIAlertControllerStyleAlert];
        [info addAction:[UIAlertAction actionWithTitle:@"Unlock" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [weakSelf setLocked:NO];
        }]];
        [info addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:info animated:YES completion:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title message:message preferredStyle:UIAlertControllerStyleAlert];
    BOOL decimals = self.step < 1;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = decimals ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:decimals ? @"%.2f" : @"%.0f", self.value];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    UIAlertAction *set = [UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = [alert.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"," withString:@"."];
        NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
        double typed = 0;
        if (![scanner scanDouble:&typed]) return;
        [weakSelf commit:[weakSelf rounded:typed]];
    }];
    [alert addAction:set];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset to Default" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf commit:[weakSelf rounded:weakSelf.defaultValue]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.preferredAction = set;
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end
