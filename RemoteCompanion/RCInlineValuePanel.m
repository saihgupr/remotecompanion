#import "RCInlineValuePanel.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCVariableEditorParts.h"

@interface RCInlineValuePanel () <UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *caption;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic, copy) NSString *prefix;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *variableButton;
@property (nonatomic, strong) UILabel *readout;
@property (nonatomic, strong) UILabel *unitLabel;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UIStackView *valueRow;
@property (nonatomic, strong) NSLayoutConstraint *fieldWidthConstraint;
@property (nonatomic, assign) BOOL typingValue;
@property (nonatomic, copy) NSArray<NSString *> *runNames;
@property (nonatomic, copy) NSArray<NSString *> *savedNames;
- (void)installVariableMenu;
- (void)insertVariableNamed:(NSString *)name;
@end

// The type sizes start from the shipping styles and scale with Dynamic Type, like the sheets do
static UIFont *RCInlineValueFont(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
}

static UIFont *RCInlineMonoFont(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont monospacedSystemFontOfSize:size weight:weight]];
}

// The panel's own spacing: one inset shared by the caption and the stepper card, and a card whose
// height is the step buttons plus the same air above and below them
static CGFloat const RCInlineStepperCardHeight = 58.0;
static CGFloat const RCInlineStepperInset = 10.0;
static CGFloat const RCInlineStepperButtonSide = 38.0;

@implementation RCInlineValuePanel

- (instancetype)initWithCaption:(NSString *)caption unit:(NSString *)unit prefix:(NSString *)prefix value:(NSString *)value otherActions:(NSArray *)otherActions {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _caption = [caption copy];
        _unit = [unit copy];
        _prefix = [prefix copy];
        _minimum = 0;
        _maximum = 100;
        _step = 1;
        _allowsRound = YES;
        [self collectVariableNames:otherActions];
        self.translatesAutoresizingMaskIntoConstraints = NO;

        // The panel watches every touch inside it, including the ones on its own step buttons and
        // field, so a tap there can never reach the row and fold it. The touches are never
        // cancelled, so the buttons and the field still get theirs.
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelTap:)];
        tap.cancelsTouchesInView = NO;
        tap.delaysTouchesBegan = NO;
        tap.delaysTouchesEnded = NO;
        tap.delegate = self;
        [self addGestureRecognizer:tap];

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 10;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        [stack addArrangedSubview:[self captionRow]];
        [stack addArrangedSubview:[self stepperCard]];

        self.field.text = value;
        [self updateState];
        [self loadSavedNames];
    }
    return self;
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
    UILabel *label = [[UILabel alloc] init];
    label.text = self.caption;
    label.font = RCInlineValueFont(15, UIFontTextStyleSubheadline, UIFontWeightSemibold);
    label.textColor = [UIColor secondaryLabelColor];
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *insert = [UIButton buttonWithType:UIButtonTypeSystem];
    [insert setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
    insert.accessibilityLabel = @"Insert Variable";
    insert.showsMenuAsPrimaryAction = YES;
    insert.translatesAutoresizingMaskIntoConstraints = NO;
    self.variableButton = insert;
    [self installVariableMenu];

    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    [row addSubview:insert];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:34],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:insert.leadingAnchor constant:-8],
        [insert.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [insert.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [insert.widthAnchor constraintEqualToConstant:34],
        [insert.heightAnchor constraintEqualToConstant:34],
    ]];
    return row;
}

// The big readout between the round step buttons. Tapping the number swaps it for the field in the
// same place, with the unit still beside it when the two fit.
- (UIView *)stepperCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemFillColor];
    card.layer.cornerRadius = 12;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    self.minusButton = [self stepButtonNamed:@"minus" label:@"Decrease"];
    self.plusButton = [self stepButtonNamed:@"plus" label:@"Increase"];
    [self.minusButton addTarget:self action:@selector(stepDown) forControlEvents:UIControlEventTouchUpInside];
    [self.plusButton addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside];

    self.readout = [[UILabel alloc] init];
    self.readout.textColor = [UIColor labelColor];
    self.readout.adjustsFontSizeToFitWidth = YES;
    self.readout.minimumScaleFactor = 0.5;
    self.readout.lineBreakMode = NSLineBreakByClipping;
    self.unitLabel = [[UILabel alloc] init];
    self.unitLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.unitLabel.textColor = [UIColor secondaryLabelColor];
    self.unitLabel.text = self.unit;

    UITextField *field = [[UITextField alloc] init];
    field.font = RCInlineMonoFont(26, UIFontTextStyleTitle2, UIFontWeightSemibold);
    field.textColor = [UIColor labelColor];
    field.tintColor = [UIColor systemBlueColor];
    field.textAlignment = NSTextAlignmentCenter;
    field.keyboardType = self.allowsDecimals ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
    field.returnKeyType = UIReturnKeyDone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.delegate = self;
    field.hidden = YES;
    field.accessibilityLabel = self.caption.length ? [self.caption stringByAppendingString:@" value"] : @"Value";
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [field setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [field addTarget:self action:@selector(updateState) forControlEvents:UIControlEventEditingChanged];
    self.field = field;
    self.fieldWidthConstraint = [field.widthAnchor constraintEqualToConstant:80];

    UIStackView *valueRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.readout, field, self.unitLabel]];
    valueRow.axis = UILayoutConstraintAxisHorizontal;
    valueRow.alignment = UIStackViewAlignmentLastBaseline;
    valueRow.spacing = 3;
    valueRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.valueRow = valueRow;

    [card addSubview:self.minusButton];
    [card addSubview:self.plusButton];
    [card addSubview:valueRow];
    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:RCInlineStepperCardHeight],
        // The same air and the same button size on both sides, so the two arrows mirror each other
        [self.minusButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:RCInlineStepperInset],
        [self.minusButton.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [self.minusButton.topAnchor constraintGreaterThanOrEqualToAnchor:card.topAnchor constant:RCInlineStepperInset],
        [self.plusButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-RCInlineStepperInset],
        [self.plusButton.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [self.plusButton.topAnchor constraintGreaterThanOrEqualToAnchor:card.topAnchor constant:RCInlineStepperInset],
        [valueRow.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [valueRow.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [valueRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.minusButton.trailingAnchor constant:10],
        [valueRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.plusButton.leadingAnchor constant:-10],
        [valueRow.topAnchor constraintGreaterThanOrEqualToAnchor:card.topAnchor constant:8],
        [valueRow.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-8],
    ]];
    return card;
}

// The number swaps into the field in the same place: the readout's own font, centred, keyboard up
// with the caret at the end. A variable like {count} opens the same way.
- (void)beginEditingValue {
    if (self.typingValue || !self.field) return;
    self.typingValue = YES;
    self.field.font = self.readout.font;
    self.field.hidden = NO;
    self.readout.hidden = YES;
    self.fieldWidthConstraint.active = YES;
    [self updateEditingWidth];
    [self.field becomeFirstResponder];
}

// Return or a tap elsewhere puts the readout back, showing what was just typed
- (void)endEditingValue {
    if (!self.typingValue) return;
    self.typingValue = NO;
    self.fieldWidthConstraint.active = NO;
    self.field.hidden = YES;
    self.readout.hidden = NO;
    [self updateState];
}

// The field is only as wide as the text in it, so the number stays centred where the readout was.
// The unit keeps its place beside it while both fit between the step buttons.
- (void)updateEditingWidth {
    if (!self.typingValue) return;
    CGFloat available = self.bounds.size.width - 2.0 * (RCInlineStepperInset + RCInlineStepperButtonSide + 10.0);
    if (available < 44.0) available = 120.0;
    UIFont *unitFont = self.unitLabel.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    CGFloat unitWidth = self.unit.length ? ceil([self.unit sizeWithAttributes:@{NSFontAttributeName: unitFont}].width) : 0;
    CGFloat gap = unitWidth > 0 ? self.valueRow.spacing : 0;
    CGFloat textWidth = ceil([(self.field.text ?: @"") sizeWithAttributes:@{NSFontAttributeName: self.field.font}].width) + 12.0;
    BOOL showUnit = unitWidth > 0 && textWidth + gap + unitWidth <= available;
    self.unitLabel.hidden = !showUnit;
    CGFloat room = available - (showUnit ? gap + unitWidth : 0);
    self.fieldWidthConstraint.constant = MAX(44.0, MIN(textWidth, room));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.typingValue) [self updateEditingWidth];
}

// A tap on the number opens the field; every other tap inside the panel is only absorbed, which
// keeps it from reaching the row and folding it
- (void)handlePanelTap:(UITapGestureRecognizer *)recognizer {
    if (self.typingValue || !self.readout) return;
    CGPoint point = [recognizer locationInView:self.readout];
    if (!CGRectContainsPoint(CGRectInset(self.readout.bounds, -10, -8), point)) return;
    UIView *hit = [self hitTest:[recognizer locationInView:self] withEvent:nil];
    for (UIView *view = hit; view && view != self; view = view.superview) {
        if ([view isKindOfClass:[UIControl class]]) return;
    }
    [self beginEditingValue];
}

// The absorber takes every touch in the panel, the step buttons and the field included, but it
// never cancels them (cancelsTouchesInView is NO): each control still fires, and because the
// absorber sees the tap the row's own tap doesn't, so stepping never folds the row.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}

- (UIButton *)stepButtonNamed:(NSString *)symbol label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                               weight:UIImageSymbolWeightSemibold]]
            forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = RCInlineStepperButtonSide / 2.0;
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:RCInlineStepperButtonSide],
        [button.heightAnchor constraintEqualToConstant:RCInlineStepperButtonSide],
    ]];
    return button;
}

- (void)setMinimum:(double)minimum {
    _minimum = minimum;
    [self updateState];
}

- (void)setMaximum:(double)maximum {
    _maximum = maximum;
    [self updateState];
}

- (void)setStep:(double)step {
    _step = step > 0 ? step : 1;
}

- (void)setAllowsDecimals:(BOOL)allowsDecimals {
    _allowsDecimals = allowsDecimals;
    self.field.keyboardType = allowsDecimals ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
    [self updateState];
}

- (void)setAllowsRound:(BOOL)allowsRound {
    _allowsRound = allowsRound;
}

// The + menu is a fixed shell whose entries are built when the menu opens, not when it closes.
// The saved names arrive from the server a moment later, and handing an open button a new menu
// dismisses that menu (and the editor with it), so the button's menu is never replaced.
- (void)installVariableMenu {
    if (!self.variableButton) return;
    __weak typeof(self) weakSelf = self;
    void (^provide)(void (^)(NSArray<UIMenuElement *> *)) = ^(void (^completion)(NSArray<UIMenuElement *> *elements)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { completion(@[]); return; }
        UIMenu *menu = RCVariableInsertMenuWithRound(strongSelf.runNames, strongSelf.savedNames, strongSelf.allowsRound, ^(NSString *name) {
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

// A picked variable takes the field's place. The row is left alone: the picker closes on its own
// and the field shows {name} in place.
- (void)insertVariableNamed:(NSString *)name {
    self.field.text = [NSString stringWithFormat:@"{%@}", name];
    [self updateState];
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

- (NSString *)trimmedText {
    return [(self.field.text ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (BOOL)scanNumber:(NSString *)text into:(double *)value {
    if (!text.length) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:[text stringByReplacingOccurrencesOfString:@"," withString:@"."]];
    double number = 0;
    if (![scanner scanDouble:&number] || !scanner.isAtEnd) return NO;
    if (value) *value = number;
    return YES;
}

- (NSString *)variableNameInText:(NSString *)text {
    if (![text hasPrefix:@"{"] || ![text hasSuffix:@"}"] || text.length <= 2) return nil;
    return [text substringWithRange:NSMakeRange(1, text.length - 2)];
}

// The number or the "{name}" text, or nil when it isn't one in range
- (id)valueFromText:(NSString *)text {
    NSString *name = [self variableNameInText:text];
    if (name) {
        if (RCSetVariableNameValid(name)) return text;
        if ([name isEqualToString:@"round"] && self.allowsRound) return text;
        return nil;
    }
    double number = 0;
    if (![self scanNumber:text into:&number]) return nil;
    if (!self.allowsDecimals && floor(number) != number) return nil;
    if (number < self.minimum || number > self.maximum) return nil;
    return @(number);
}

- (NSString *)currentCommand {
    NSString *text = [self trimmedText];
    id value = [self valueFromText:text];
    if (!value) return nil;
    if ([value isKindOfClass:[NSString class]]) return [self.prefix stringByAppendingString:value];
    double number = [value doubleValue];
    NSString *numberText = self.allowsDecimals ? [NSString stringWithFormat:@"%.10g", number]
                                               : [NSString stringWithFormat:@"%ld", (long)llround(number)];
    return [self.prefix stringByAppendingString:numberText];
}

- (NSString *)formatted:(double)number {
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    f.maximumFractionDigits = 3;
    return [f stringFromNumber:@(number)];
}

// The readout: the field's number in the big digits and the unit, or a variable (or a number out of
// range) in the smaller mono font, in red. While the field is up the readout is hidden, so only the
// step states and the editing width need keeping in step.
- (void)updateState {
    if (!self.readout) return;
    NSString *text = [self trimmedText];
    double number = 0;
    BOOL numeric = [self scanNumber:text into:&number];
    if (numeric) {
        if (!self.typingValue) {
            self.readout.font = RCInlineMonoFont(26, UIFontTextStyleTitle2, UIFontWeightSemibold);
            self.readout.text = [self formatted:number];
        }
        self.minusButton.enabled = number > self.minimum;
        self.plusButton.enabled = number < self.maximum;
    } else {
        if (!self.typingValue) {
            self.readout.font = RCInlineMonoFont(18, UIFontTextStyleTitle3, UIFontWeightSemibold);
            self.readout.text = text.length ? text : @"—";
        }
        self.minusButton.enabled = NO;
        self.plusButton.enabled = NO;
    }
    if (self.typingValue) {
        [self updateEditingWidth];
    } else {
        self.readout.textColor = (text.length && ![self valueFromText:text]) ? [UIColor systemRedColor] : [UIColor labelColor];
        self.unitLabel.hidden = !numeric;
        self.unitLabel.text = self.unit;
    }
    self.minusButton.alpha = self.minusButton.enabled ? 1.0 : 0.35;
    self.plusButton.alpha = self.plusButton.enabled ? 1.0 : 0.35;
}

- (void)stepDown {
    [self stepBy:-self.step];
}

- (void)stepUp {
    [self stepBy:self.step];
}

- (void)stepBy:(double)delta {
    double number = 0;
    if (![self scanNumber:[self trimmedText] into:&number]) return;
    number = MAX(self.minimum, MIN(self.maximum, number + delta));
    self.field.text = [NSString stringWithFormat:@"%.10g", number];
    [self updateState];
}

// The caret sits at the end, ready to continue the number (or the {variable})
- (void)textFieldDidBeginEditing:(UITextField *)textField {
    UITextPosition *end = textField.endOfDocument;
    textField.selectedTextRange = [textField textRangeFromPosition:end toPosition:end];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

// Return or ending the edit puts the readout back and hands the value over. A field torn off
// screen with the row is not a commit.
- (void)textFieldDidEndEditing:(UITextField *)textField {
    BOOL wasTyping = self.typingValue;
    BOOL stillOnScreen = textField.window != nil;
    [self endEditingValue];
    if (wasTyping && stillOnScreen && self.onCommit) self.onCommit();
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width {
    if (width <= 0) return 0;
    return ceil([self systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                    withHorizontalFittingPriority:UILayoutPriorityRequired
                          verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height);
}

@end
