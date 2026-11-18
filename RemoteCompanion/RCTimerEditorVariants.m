#import "RCTimerEditorVariants.h"
#import "RCConfigManager.h"
#import "RCSectionCardView.h"

static const CGFloat RCTimerGutter = 16.0;

static NSString *const RCTimerDurationHelpText =
    @"Spin the wheels or type a duration (e.g. 20m, 1h30m, 45s, 20:00) or {variable}.";
static NSString *const RCTimerClockHelpText =
    @"Runs a real Apple Clock timer synced with Lock Screen and Apple Watch. Optional labels name individual timers on iOS 17+.";

NSString *RCTimerActionWord(RCTimerActionType action) {
    switch (action) {
        case RCTimerActionPause: return @"Pause";
        case RCTimerActionResume: return @"Resume";
        case RCTimerActionStop: return @"Stop";
        case RCTimerActionStatus: return @"Status";
        case RCTimerActionStart:
        default: return @"Start";
    }
}

NSString *RCTimerReadoutTextForExpression(NSString *expression) {
    if (![expression isKindOfClass:[NSString class]]) return @"--:--:--";
    NSString *trimmed = [expression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return @"--:--:--";
    if ([RCTimerCommand containsVariable:trimmed]) return trimmed;

    double seconds = [RCTimerCommand parseDurationSeconds:trimmed];
    if (seconds <= 0) return @"--:--:--";

    NSInteger total = (NSInteger)llround(seconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger secs = total % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
}

static NSInteger RCTimerIndexForAction(RCTimerActionType action) {
    switch (action) {
        case RCTimerActionPause: return 1;
        case RCTimerActionResume: return 2;
        case RCTimerActionStop: return 3;
        case RCTimerActionStart:
        case RCTimerActionStatus:
        default: return 0;
    }
}

static RCTimerActionType RCTimerActionForIndex(NSInteger index) {
    switch (index) {
        case 1: return RCTimerActionPause;
        case 2: return RCTimerActionResume;
        case 3: return RCTimerActionStop;
        default: return RCTimerActionStart;
    }
}

static void RCTimerPin(UIView *view, UIView *host, UIEdgeInsets insets) {
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:host.topAnchor constant:insets.top],
        [view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor constant:-insets.bottom],
        [view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:insets.left],
        [view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-insets.right]
    ]];
}

// The app's tiles shrink a little under a finger; chips and pills do the same.
@interface RCTimerPressButton : UIButton
@end

@implementation RCTimerPressButton

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.10 animations:^{
        self.alpha = highlighted ? 0.72 : 1.0;
        self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
    }];
}

@end

#pragma mark - Theme

@interface RCTimerEditorTheme ()
@property (nonatomic, strong, readwrite) UIColor *background;
@property (nonatomic, strong, readwrite) UIColor *panel;
@property (nonatomic, strong, readwrite) UIColor *panelBorder;
@property (nonatomic, strong, readwrite) UIColor *separator;
@property (nonatomic, strong, readwrite) UIColor *control;
@property (nonatomic, strong, readwrite) UIColor *controlBorder;
@property (nonatomic, strong, readwrite) UIColor *accent;
@property (nonatomic, strong, readwrite) UIColor *accentSoft;
@property (nonatomic, strong, readwrite) UIColor *accentBorder;
@property (nonatomic, strong, readwrite) UIColor *primaryText;
@property (nonatomic, strong, readwrite) UIColor *secondaryText;
@property (nonatomic, strong, readwrite) UIColor *tertiaryText;
@end

@implementation RCTimerEditorTheme

+ (instancetype)themeForCurrentConfig {
    RCConfigManager *config = [RCConfigManager sharedManager];
    CGFloat mainBG = [config tweakValueForKey:@"mainBackground" defaultVal:0.09];

    RCTimerEditorTheme *theme = [[RCTimerEditorTheme alloc] init];
    theme.background = [config tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    theme.panel = [config tweakColorForKey:@"blockBackground" defaultVal:0.12];
    theme.panelBorder = [config tweakColorForKey:@"borders" defaultVal:0.14];
    theme.separator = [config tweakColorForKey:@"separators" defaultVal:0.30];

    // Fields and pills sit a step above the card, like the check tint on the
    // action tiles. Both come from the separator color, so the tweaker still
    // has the last word.
    theme.control = [theme.separator colorWithAlphaComponent:0.30];
    theme.controlBorder = [theme.separator colorWithAlphaComponent:0.50];

    // The app's accent on the Actions, Symbols and Banners screens.
    theme.accent = [UIColor systemBlueColor];
    theme.accentSoft = [theme.accent colorWithAlphaComponent:0.16];
    theme.accentBorder = [theme.accent colorWithAlphaComponent:0.50];

    theme.primaryText = [UIColor labelColor];
    theme.secondaryText = [UIColor secondaryLabelColor];
    theme.tertiaryText = [UIColor tertiaryLabelColor];
    return theme;
}

- (UIFont *)textFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    UIFontMetrics *metrics = [UIFontMetrics metricsForTextStyle:UIFontTextStyleBody];
    return [metrics scaledFontForFont:base maximumPointSize:size * 1.30];
}

- (UIFont *)monospacedFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont *base = [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
    UIFontMetrics *metrics = [UIFontMetrics metricsForTextStyle:UIFontTextStyleBody];
    return [metrics scaledFontForFont:base maximumPointSize:size * 1.30];
}

@end

#pragma mark - Action selector

@interface RCTimerActionSelector : UIView
@property (nonatomic, strong) RCTimerEditorTheme *theme;
@property (nonatomic, assign) RCTimerActionType selectedAction;
@property (nonatomic, copy) void (^onChange)(RCTimerActionType action);
@property (nonatomic, strong) NSArray<UIButton *> *controls;
- (instancetype)initWithTheme:(RCTimerEditorTheme *)theme;
@end

@implementation RCTimerActionSelector

- (instancetype)initWithTheme:(RCTimerEditorTheme *)theme {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _theme = theme;
        _selectedAction = RCTimerActionStart;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self buildControls];
        [self applySelection];
    }
    return self;
}

- (void)buildControls {
    NSArray<NSString *> *titles = @[@"Start", @"Pause", @"Resume", @"Stop"];
    NSMutableArray<UIButton *> *controls = [NSMutableArray array];

    UIStackView *row = [[UIStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 6;
    [self addSubview:row];
    RCTimerPin(row, self, UIEdgeInsetsZero);

    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *button = [self baseButtonWithTitle:titles[i] index:i];
        button.layer.cornerRadius = 10;
        button.layer.borderWidth = 1;
        [row addArrangedSubview:button];
        [controls addObject:button];
    }
    [self.heightAnchor constraintEqualToConstant:36].active = YES;

    self.controls = controls;
}

- (UIButton *)baseButtonWithTitle:(NSString *)title index:(NSInteger)index {
    UIButton *button = [RCTimerPressButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = index;
    button.titleLabel.font = [self.theme textFontOfSize:13 weight:UIFontWeightSemibold];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.7;
    [button setTitle:title forState:UIControlStateNormal];
    button.accessibilityLabel = title;
    [button addTarget:self action:@selector(controlTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)controlTapped:(UIControl *)sender {
    RCTimerActionType action = RCTimerActionForIndex(sender.tag);
    if (action == self.selectedAction) return;
    self.selectedAction = action;
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    if (self.onChange) self.onChange(action);
}

- (void)setSelectedAction:(RCTimerActionType)selectedAction {
    _selectedAction = selectedAction;
    [self applySelection];
}

- (void)applySelection {
    for (UIButton *control in self.controls) {
        BOOL on = (control.tag == RCTimerIndexForAction(self.selectedAction));

        control.backgroundColor = on ? self.theme.accent : self.theme.control;
        control.layer.borderWidth = 1;
        control.layer.borderColor = (on ? self.theme.accent : self.theme.controlBorder).CGColor;
        [control setTitleColor:(on ? [UIColor whiteColor] : self.theme.primaryText) forState:UIControlStateNormal];
        control.accessibilityTraits = UIAccessibilityTraitButton | (on ? UIAccessibilityTraitSelected : 0);
    }
}

@end

#pragma mark - Editor form

@interface RCTimerEditorFormView ()
@property (nonatomic, strong, readwrite) RCTimerEditorTheme *theme;
@property (nonatomic, strong, readwrite) UIPickerView *picker;
@property (nonatomic, strong, readwrite) UITextField *durationField;
@property (nonatomic, strong, readwrite, nullable) UITextField *labelField;
@property (nonatomic, strong, readwrite) NSArray<UIButton *> *presetButtons;
@property (nonatomic, assign, readwrite) BOOL durationVisible;
@property (nonatomic, copy, readwrite) NSString *defaultReadoutCaption;

@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) RCTimerActionSelector *actionSelector;
@property (nonatomic, strong) UIView *durationBlock;
@property (nonatomic, strong) UILabel *readoutLabel;
@property (nonatomic, strong) UILabel *readoutCaptionLabel;
@property (nonatomic, strong) UIFont *readoutFont;
@property (nonatomic, strong) UIColor *readoutColor;
@property (nonatomic, strong) UILabel *noteFooterLabel;
@end

@implementation RCTimerEditorFormView

- (instancetype)initWithTheme:(RCTimerEditorTheme *)theme {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _theme = theme;
        _durationVisible = YES;
        _presetButtons = @[];
        _defaultReadoutCaption = @"";
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [UIColor clearColor];
        [self build];
    }
    return self;
}

- (void)build {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 16;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:RCTimerGutter],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-RCTimerGutter],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-26]
    ]];
    self.stack = stack;

    self.picker = [[UIPickerView alloc] init];
    self.picker.translatesAutoresizingMaskIntoConstraints = NO;
    self.picker.backgroundColor = [UIColor clearColor];

    [self makeFields];

    [self buildHero];

    [self applyReadoutCaption];
    [self applyReadoutText];
    [self updateNoteVisibility];
}

#pragma mark Controls

- (void)makeFields {
    self.durationField = [self fieldWithPlaceholder:@"20m, 90s, or {var}" monoSize:15 height:40];
    if (@available(iOS 17.0, *)) {
        self.labelField = [self fieldWithPlaceholder:@"Optional (e.g. Nap)" monoSize:15 height:40];
        self.labelField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder monoSize:(CGFloat)size height:(CGFloat)height {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = [self.theme monospacedFontOfSize:size weight:UIFontWeightMedium];
    field.adjustsFontForContentSizeCategory = YES;
    field.textColor = self.theme.primaryText;
    field.tintColor = self.theme.accent;
    field.backgroundColor = self.theme.control;
    field.layer.cornerRadius = 9;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.layer.borderWidth = 1;
    field.layer.borderColor = self.theme.controlBorder.CGColor;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyDone;
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{
        NSFontAttributeName: field.font,
        NSForegroundColorAttributeName: self.theme.tertiaryText
    }];

    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 11, height)];
    field.leftView = leftPad;
    field.leftViewMode = UITextFieldViewModeAlways;

    // Same + symbol as the other editors' "insert a variable" control.
    UIButton *insert = [UIButton buttonWithType:UIButtonTypeCustom];
    insert.frame = CGRectMake(0, 0, 38, height);
    insert.showsMenuAsPrimaryAction = YES;
    insert.accessibilityLabel = @"Insert Variable";
    insert.tintColor = self.theme.accent;
    [insert setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
    field.rightView = insert;
    field.rightViewMode = UITextFieldViewModeAlways;

    [field.heightAnchor constraintEqualToConstant:height].active = YES;
    return field;
}

- (void)wireSelector:(RCTimerActionSelector *)selector {
    self.actionSelector = selector;
    __weak typeof(self) weakSelf = self;
    selector.onChange = ^(RCTimerActionType action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.onActionChange) strongSelf.onActionChange(action);
    };
    selector.selectedAction = self.selectedAction;
}

#pragma mark Small pieces

- (NSAttributedString *)trackedString:(NSString *)text
                                 font:(UIFont *)font
                                color:(UIColor *)color
                                 kern:(CGFloat)kern
                            uppercase:(BOOL)uppercase {
    NSString *shown = uppercase ? text.uppercaseString : text;
    return [[NSAttributedString alloc] initWithString:shown ?: @"" attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSKernAttributeName: @(kern)
    }];
}

- (UILabel *)captionLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [self.theme textFontOfSize:10.5 weight:UIFontWeightSemibold];
    label.adjustsFontForContentSizeCategory = YES;
    label.accessibilityTraits = UIAccessibilityTraitHeader;
    label.attributedText = [self trackedString:text
                                          font:label.font
                                         color:self.theme.secondaryText
                                          kern:1.0
                                     uppercase:YES];
    return label;
}

- (UILabel *)footerLabel:(NSString *)text small:(BOOL)small {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [self.theme textFontOfSize:(small ? 11.5 : 12.5) weight:UIFontWeightRegular];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = self.theme.secondaryText;
    label.numberOfLines = 0;
    label.text = text;
    return label;
}

- (UILabel *)unitLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [self.theme textFontOfSize:9 weight:UIFontWeightSemibold];
    label.attributedText = [self trackedString:text
                                          font:label.font
                                         color:self.theme.tertiaryText
                                          kern:1.2
                                     uppercase:YES];
    return label;
}

- (UIView *)panelWithContent:(UIView *)content insets:(UIEdgeInsets)insets {
    UIView *container = [[UIView alloc] init];
    RCSectionCardView *card = [[RCSectionCardView alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card configureWithFillColor:self.theme.panel
                     borderColor:self.theme.panelBorder
                     borderWidth:1
                    cornerRadius:12
                        position:RCSectionCardPositionSingle];
    [container addSubview:card];
    RCTimerPin(card, container, UIEdgeInsetsZero);

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:content];
    RCTimerPin(content, container, insets);
    return container;
}

- (UIView *)labeledFieldContent:(UITextField *)field caption:(NSString *)caption {
    UIView *content = [[UIView alloc] init];
    UILabel *label = [self captionLabel:caption];
    [content addSubview:label];
    [content addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
        [label.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [label.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [field.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:6],
        [field.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [field.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [field.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-10]
    ]];
    return content;
}

#pragma mark Wheels

- (UIView *)unitsRow {
    UIStackView *row = [[UIStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    for (NSString *title in @[@"Hours", @"Minutes", @"Seconds"]) {
        [row addArrangedSubview:[self unitLabel:title]];
    }
    return row;
}

- (UIView *)wheelPanelWithUnits:(BOOL)units pickerHeight:(CGFloat)pickerHeight {
    UIView *content = [[UIView alloc] init];
    NSLayoutYAxisAnchor *pickerTop = content.topAnchor;
    CGFloat pickerTopGap = 10;

    if (units) {
        UIView *row = [self unitsRow];
        [content addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
            [row.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:content.trailingAnchor]
        ]];
        pickerTop = row.bottomAnchor;
        pickerTopGap = 2;
    }

    [self.picker.heightAnchor constraintEqualToConstant:pickerHeight].active = YES;
    [content addSubview:self.picker];
    [NSLayoutConstraint activateConstraints:@[
        [self.picker.topAnchor constraintEqualToAnchor:pickerTop constant:pickerTopGap],
        [self.picker.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.picker.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.picker.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8]
    ]];
    return [self panelWithContent:content insets:UIEdgeInsetsZero];
}

- (UILabel *)makeReadoutLabelWithSize:(CGFloat)size
                                color:(UIColor *)color
                            alignment:(NSTextAlignment)alignment {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [self.theme monospacedFontOfSize:size weight:UIFontWeightSemibold];
    label.textColor = color;
    label.textAlignment = alignment;
    label.adjustsFontForContentSizeCategory = YES;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.5;
    label.numberOfLines = 1;
    self.readoutFont = label.font;
    self.readoutColor = color;
    return label;
}

#pragma mark Footer

- (void)addNoteFooterWithSmallText:(BOOL)small {
    UILabel *label = [self footerLabel:RCTimerClockHelpText small:small];
    self.noteFooterLabel = label;
    [self.stack addArrangedSubview:label];
}

- (void)updateNoteVisibility {
    // With no label field (before iOS 17) the sentence under the duration is
    // the only place the Clock behavior is explained. On iOS 17 it belongs
    // under the label, so it only shows while duration is visible.
    self.noteFooterLabel.hidden = !(self.labelField != nil || !self.durationVisible);
}

#pragma mark Hero layout

- (void)buildHero {
    self.defaultReadoutCaption = @"Timer length";
    self.stack.spacing = 16;

    UIView *hero = [[UIView alloc] init];

    UIView *accentBar = [[UIView alloc] init];
    accentBar.translatesAutoresizingMaskIntoConstraints = NO;
    accentBar.backgroundColor = self.theme.accent;
    accentBar.layer.cornerRadius = 1.5;
    accentBar.layer.cornerCurve = kCACornerCurveContinuous;

    self.readoutCaptionLabel = [self captionLabel:self.defaultReadoutCaption];
    self.readoutCaptionLabel.textAlignment = NSTextAlignmentCenter;
    self.readoutCaption = self.defaultReadoutCaption;

    self.readoutLabel = [self makeReadoutLabelWithSize:54 color:self.theme.primaryText alignment:NSTextAlignmentCenter];

    [hero addSubview:accentBar];
    [hero addSubview:self.readoutCaptionLabel];
    [hero addSubview:self.readoutLabel];

    [NSLayoutConstraint activateConstraints:@[
        [accentBar.topAnchor constraintEqualToAnchor:hero.topAnchor constant:2],
        [accentBar.centerXAnchor constraintEqualToAnchor:hero.centerXAnchor],
        [accentBar.widthAnchor constraintEqualToConstant:26],
        [accentBar.heightAnchor constraintEqualToConstant:3],
        [self.readoutCaptionLabel.topAnchor constraintEqualToAnchor:accentBar.bottomAnchor constant:9],
        [self.readoutCaptionLabel.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor],
        [self.readoutCaptionLabel.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor],
        [self.readoutLabel.topAnchor constraintEqualToAnchor:self.readoutCaptionLabel.bottomAnchor constant:2],
        [self.readoutLabel.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor],
        [self.readoutLabel.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor],
        [self.readoutLabel.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor]
    ]];

    [self.stack addArrangedSubview:hero];
    [self.stack setCustomSpacing:18 afterView:hero];

    RCTimerActionSelector *selector = [[RCTimerActionSelector alloc] initWithTheme:self.theme];
    [self wireSelector:selector];
    [self.stack addArrangedSubview:selector];
    [self.stack setCustomSpacing:18 afterView:selector];

    // The wheels flow straight into the expression panel: with no preset strip
    // between them the two panels read as one duration block.
    UIStackView *duration = [[UIStackView alloc] init];
    duration.axis = UILayoutConstraintAxisVertical;
    duration.spacing = 12;
    [duration addArrangedSubview:[self wheelPanelWithUnits:YES pickerHeight:180]];

    UIView *expression = [self panelWithContent:[self labeledFieldContent:self.durationField caption:@"Duration expression"]
                                         insets:UIEdgeInsetsZero];
    [duration addArrangedSubview:expression];
    [duration setCustomSpacing:10 afterView:expression];
    [duration addArrangedSubview:[self footerLabel:RCTimerDurationHelpText small:NO]];
    self.durationBlock = duration;
    [self.stack addArrangedSubview:duration];
    [self.stack setCustomSpacing:20 afterView:duration];

    if (self.labelField) {
        UILabel *optionsCaption = [self captionLabel:@"Options"];
        [self.stack addArrangedSubview:optionsCaption];
        [self.stack setCustomSpacing:8 afterView:optionsCaption];
        [self.stack addArrangedSubview:[self panelWithContent:[self labeledFieldContent:self.labelField caption:@"Label"]
                                                      insets:UIEdgeInsetsZero]];
    }

    [self addNoteFooterWithSmallText:NO];
}

#pragma mark - Public

- (void)setSelectedAction:(RCTimerActionType)selectedAction {
    _selectedAction = selectedAction;
    self.actionSelector.selectedAction = selectedAction;
}

- (void)setDurationVisible:(BOOL)visible animated:(BOOL)animated {
    (void)animated; // the table animates the height change
    _durationVisible = visible;
    self.durationBlock.hidden = !visible;
    [self updateNoteVisibility];
}

- (void)setReadoutCaption:(NSString *)readoutCaption {
    _readoutCaption = [readoutCaption copy];
    [self applyReadoutCaption];
}

- (void)applyReadoutCaption {
    if (!self.readoutCaptionLabel) return;
    NSString *caption = self.readoutCaption.length ? self.readoutCaption : self.defaultReadoutCaption;
    self.readoutCaptionLabel.attributedText = [self trackedString:caption
                                                             font:self.readoutCaptionLabel.font
                                                            color:self.theme.secondaryText
                                                             kern:1.0
                                                        uppercase:YES];
}

- (void)setReadoutText:(NSString *)readoutText {
    _readoutText = [readoutText copy];
    [self applyReadoutText];
}

- (void)applyReadoutText {
    if (!self.readoutLabel) return;
    NSString *text = self.readoutText.length ? self.readoutText : @"--:--:--";
    UIColor *dim = [self.readoutColor colorWithAlphaComponent:0.45];
    NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: self.readoutFont,
        NSForegroundColorAttributeName: self.readoutColor,
        NSKernAttributeName: @(1.2)
    }];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if ([substring isEqualToString:@":"]) {
            [string addAttribute:NSForegroundColorAttributeName value:dim range:substringRange];
        }
    }];
    self.readoutLabel.attributedText = string;
    NSString *caption = self.readoutCaption.length ? self.readoutCaption : self.defaultReadoutCaption;
    self.readoutLabel.accessibilityLabel = caption.length ? caption : @"Timer length";
    self.readoutLabel.accessibilityValue = text;
}

- (UILabel *)pickerRowLabelForRow:(NSInteger)row component:(NSInteger)component {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;

    NSString *unit = component == 0 ? @"hr" : (component == 1 ? @"min" : @"sec");
    NSString *number = [NSString stringWithFormat:@"%ld", (long)row];

    NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:number attributes:@{
        NSFontAttributeName: [self.theme monospacedFontOfSize:20 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: self.theme.primaryText,
        NSKernAttributeName: @(0.4)
    }];
    label.attributedText = string;
    label.accessibilityLabel = [NSString stringWithFormat:@"%ld %@", (long)row, unit];
    return label;
}

@end
