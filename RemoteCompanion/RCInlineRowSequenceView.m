#import "RCInlineRowSequenceView.h"

#import "RCInlineRowChip.h"
#import "RCInlineRowEditor.h"
#import "RCConfigManager.h"

#import <QuartzCore/QuartzCore.h>

#pragma mark - Look

static UIColor *RCInlineRowSequenceBlockColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12];
}

static UIColor *RCInlineRowSequenceBorderColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"borders" defaultVal:0.14];
}

static UIColor *RCInlineRowSequenceSeparatorColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"separators" defaultVal:0.30];
}

static UIColor *RCInlineRowSequenceAccent(UIView *view) {
    return view.tintColor ?: [UIColor systemBlueColor];
}

static CGFloat RCInlineRowSequenceBaseSize(UIFontTextStyle style) {
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

static UIFont *RCInlineRowSequenceFontSized(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

static UIFont *RCInlineRowSequenceFont(UIFontTextStyle style, UIFontWeight weight) {
    return RCInlineRowSequenceFontSized(RCInlineRowSequenceBaseSize(style), style, weight);
}

static UIImage *RCInlineRowSequenceSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIImageConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    UIImage *image = name.length ? [UIImage systemImageNamed:name withConfiguration:configuration] : nil;
    return image ?: [UIImage systemImageNamed:@"square.dashed" withConfiguration:configuration];
}

static UILabel *RCInlineRowSequenceLabel(NSString *text, UIFont *font, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static UILabel *RCInlineRowSequenceEyebrow(NSString *text, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.attributedText = [[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName: RCInlineRowSequenceFont(UIFontTextStyleCaption2, UIFontWeightSemibold),
        NSForegroundColorAttributeName: color,
        NSKernAttributeName: @1.2,
    }];
    label.numberOfLines = 1;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static UIView *RCInlineRowSequenceHairline(void) {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = RCInlineRowSequenceSeparatorColor();
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    return line;
}

static UIImage *RCInlineRowSequenceGrabberImage(void) {
    return [UIImage systemImageNamed:@"line.3.horizontal"] ?: [UIImage systemImageNamed:@"line.horizontal.3"];
}

static void RCInlineRowSequenceTick(void) {
    UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
    [generator selectionChanged];
}

static void RCInlineRowSequenceImpact(void) {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator prepare];
    [generator impactOccurred];
}

#pragma mark - Icon tile

@interface RCInlineRowIconTile : UIView
@property (nonatomic, strong, readonly) UIImageView *imageView;
- (void)setSymbolName:(NSString *)name;
@end

@implementation RCInlineRowIconTile

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [UIColor tertiarySystemFillColor];
        self.layer.cornerRadius = 10;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _imageView = [[UIImageView alloc] init];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.tintColor = [UIColor secondaryLabelColor];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_imageView];
        [NSLayoutConstraint activateConstraints:@[
            [_imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_imageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_imageView.widthAnchor constraintEqualToConstant:20],
            [_imageView.heightAnchor constraintEqualToConstant:20],
            [self.widthAnchor constraintGreaterThanOrEqualToConstant:40],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:40],
        ]];
    }
    return self;
}

- (void)setSymbolName:(NSString *)name {
    self.imageView.image = RCInlineRowSequenceSymbol(name, 17, UIImageSymbolWeightSemibold);
}

- (void)setTintColor:(UIColor *)tintColor {
    [super setTintColor:tintColor];
    self.imageView.tintColor = tintColor;
}

@end

#pragma mark - The row

@interface RCInlineRowItemView : UIControl
@property (nonatomic, strong, readonly) RCInlineRowItem *item;
@property (nonatomic, strong, readonly) RCInlineRowIconTile *iconTile;
@property (nonatomic, strong, readonly) UILabel *nameLabel;
@property (nonatomic, strong, readonly) UILabel *detailLabel;
@property (nonatomic, strong, readonly) RCInlineRowChip *chip;
@property (nonatomic, strong, readonly) UIImageView *grabber;
@property (nonatomic, assign) BOOL showsGrabber;
@property (nonatomic, copy) void (^onActivate)(void);
- (instancetype)initWithItem:(RCInlineRowItem *)item;
- (void)refresh;
- (void)setAccentLook:(BOOL)accented;
@end

@interface RCInlineRowItemView ()
@property (nonatomic, strong) NSLayoutConstraint *chipToGrabber;
@property (nonatomic, strong) NSLayoutConstraint *chipToEdge;
@property (nonatomic, strong) NSLayoutConstraint *chipMaxWidth;
@end

@implementation RCInlineRowItemView

- (instancetype)initWithItem:(RCInlineRowItem *)item {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _item = item;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;

        _iconTile = [[RCInlineRowIconTile alloc] initWithFrame:CGRectZero];
        [_iconTile setSymbolName:item.symbolName];

        _nameLabel = RCInlineRowSequenceLabel(item.name, RCInlineRowSequenceFont(UIFontTextStyleBody, UIFontWeightMedium), [UIColor labelColor]);
        _nameLabel.numberOfLines = 0;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        _detailLabel = RCInlineRowSequenceLabel(item.detail, RCInlineRowSequenceFont(UIFontTextStyleSubheadline, UIFontWeightRegular), [UIColor secondaryLabelColor]);
        _detailLabel.numberOfLines = 0;
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _detailLabel.hidden = item.detail.length == 0;

        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _detailLabel]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 1;
        textStack.translatesAutoresizingMaskIntoConstraints = NO;
        [textStack setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        _chip = [[RCInlineRowChip alloc] initWithFrame:CGRectZero];
        [_chip setValueText:item.displayValue];

        _grabber = [[UIImageView alloc] initWithImage:RCInlineRowSequenceGrabberImage()];
        _grabber.tintColor = [UIColor tertiaryLabelColor];
        _grabber.contentMode = UIViewContentModeScaleAspectFit;
        _grabber.translatesAutoresizingMaskIntoConstraints = NO;
        _grabber.accessibilityElementsHidden = YES;

        [self addSubview:_iconTile];
        [self addSubview:textStack];
        [self addSubview:_chip];
        [self addSubview:_grabber];

        self.chipToGrabber = [_chip.trailingAnchor constraintEqualToAnchor:_grabber.leadingAnchor constant:-10];
        self.chipToEdge = [_chip.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12];
        self.chipMaxWidth = [_chip.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.46];

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:64],
            [_iconTile.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_iconTile.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconTile.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:12],
            [_iconTile.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-12],
            [_iconTile.widthAnchor constraintEqualToConstant:40],
            [_iconTile.heightAnchor constraintEqualToConstant:40],
            [textStack.leadingAnchor constraintEqualToAnchor:_iconTile.trailingAnchor constant:12],
            [textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [textStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:10],
            [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-10],
            [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_chip.leadingAnchor constant:-10],
            [_chip.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_chip.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:10],
            [_chip.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-10],
            self.chipMaxWidth,
            [_grabber.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_grabber.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_grabber.widthAnchor constraintEqualToConstant:18],
            [_grabber.heightAnchor constraintEqualToConstant:18],
        ]];
        [self.chipToGrabber setActive:YES];

        [_chip addTarget:self action:@selector(activate) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(activate) forControlEvents:UIControlEventTouchUpInside];
        [self refresh];
    }
    return self;
}

- (void)setShowsGrabber:(BOOL)showsGrabber {
    _showsGrabber = showsGrabber;
    self.grabber.hidden = !showsGrabber;
    self.chipToEdge.active = !showsGrabber;
    self.chipToGrabber.active = showsGrabber;
}

- (void)activate {
    if (self.onActivate) self.onActivate();
}

- (void)refresh {
    self.nameLabel.text = self.item.name;
    self.detailLabel.text = self.item.detail;
    self.detailLabel.hidden = self.item.detail.length == 0;
    [self.iconTile setSymbolName:self.item.symbolName];
    [self.chip setValueText:self.item.displayValue];
    self.accessibilityLabel = self.item.name;
    self.accessibilityValue = self.item.displayValue;
    self.accessibilityHint = @"Opens the value editor";
}

- (void)setAccentLook:(BOOL)accented {
    UIColor *accent = RCInlineRowSequenceAccent(self);
    self.iconTile.tintColor = accented ? accent : [UIColor secondaryLabelColor];
    [self.chip setAccented:accented];
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self.chip setAccented:self.chip.isAccented];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.72 : 1.0;
}

@end

#pragma mark - A row as a card

@interface RCInlineRowCardView ()
@property (nonatomic, strong) RCInlineRowItemView *row;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIView *editorContainer;
@property (nonatomic, strong) RCInlineRowEditor *editor;
- (void)buildEditorIfNeeded;
- (void)applyLook;
- (void)applyBorder;
@end

@implementation RCInlineRowCardView

- (instancetype)initWithItem:(RCInlineRowItem *)item {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _item = item;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = RCInlineRowSequenceBlockColor();
        self.layer.cornerRadius = 12;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1;
        self.clipsToBounds = YES;

        _row = [[RCInlineRowItemView alloc] initWithItem:item];
        __weak typeof(self) weakSelf = self;
        _row.onActivate = ^{
            if (weakSelf.onActivate) weakSelf.onActivate();
        };

        _contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[_row]];
        _contentStack.axis = UILayoutConstraintAxisVertical;
        _contentStack.spacing = 0;
        _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_contentStack];
        [NSLayoutConstraint activateConstraints:@[
            [_contentStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_contentStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_contentStack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_contentStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        [self applyLook];
    }
    return self;
}

- (void)setShowsGrabber:(BOOL)showsGrabber {
    _showsGrabber = showsGrabber;
    self.row.showsGrabber = showsGrabber;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    [self applyLook];
}

- (void)setDimmed:(BOOL)dimmed {
    _dimmed = dimmed;
    [self applyLook];
}

- (void)setExpanded:(BOOL)expanded {
    [self setExpanded:expanded animated:NO];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    if (_expanded == expanded) return;
    _expanded = expanded;
    if (expanded) [self buildEditorIfNeeded];
    if (animated) RCInlineRowSequenceImpact();

    void (^changes)(void) = ^{
        self.editorContainer.hidden = !expanded;
        [self applyLook];
        [self layoutIfNeeded];
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
    } else {
        changes();
    }
}

- (void)buildEditorIfNeeded {
    if (self.editorContainer) return;

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.hidden = YES;

    UIView *line = RCInlineRowSequenceHairline();
    [container addSubview:line];

    RCInlineRowEditor *editor = [[RCInlineRowEditor alloc] initWithItem:self.item];
    __weak typeof(self) weakSelf = self;
    editor.onChange = ^{
        RCInlineRowCardView *strongSelf = weakSelf;
        [strongSelf refresh];
        RCInlineRowNotifyValueChanged(strongSelf.item);
    };
    self.editor = editor;

    [container addSubview:editor];
    [NSLayoutConstraint activateConstraints:@[
        [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [line.topAnchor constraintEqualToAnchor:container.topAnchor],
        [editor.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [editor.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [editor.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:12],
        [editor.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-14],
    ]];

    [self.contentStack addArrangedSubview:container];
    self.editorContainer = container;
}

- (void)refresh {
    [self.row refresh];
    [self.editor refresh];
}

- (void)applyLook {
    UIColor *accent = RCInlineRowSequenceAccent(self);
    BOOL on = self.selected || self.expanded;
    self.backgroundColor = on ? [accent colorWithAlphaComponent:0.10] : RCInlineRowSequenceBlockColor();
    self.alpha = self.dimmed ? 0.40 : 1.0;
    [self.row setAccentLook:on];
    [self applyBorder];
}

- (void)applyBorder {
    UIColor *accent = RCInlineRowSequenceAccent(self);
    BOOL on = self.selected || self.expanded;
    UIColor *border = on ? accent : RCInlineRowSequenceBorderColor();
    self.layer.borderWidth = on ? 1.5 : 1;
    self.layer.borderColor = [border resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyBorder];
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self applyLook];
}

@end

#pragma mark - A sequence of rows

@interface RCInlineRowSequenceView ()
@property (nonatomic, strong) NSArray<RCInlineRowItem *> *items;
@property (nonatomic, strong) NSArray<RCInlineRowCardView *> *cards;
@property (nonatomic, assign) RCInlineRowSequenceStyle style;
- (void)activateIndex:(NSInteger)index;
@end

@implementation RCInlineRowSequenceView

- (instancetype)initWithItems:(NSArray<RCInlineRowItem *> *)items style:(RCInlineRowSequenceStyle)style {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _items = items ?: @[];
        _style = style;
        _expandedIndex = NSNotFound;
        _selectedIndex = NSNotFound;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *header = RCInlineRowSequenceEyebrow(@"ACTION SEQUENCE", [UIColor secondaryLabelColor]);

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[header]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        NSMutableArray *cards = [NSMutableArray array];
        for (NSUInteger i = 0; i < self.items.count; i++) {
            RCInlineRowItem *item = self.items[i];
            RCInlineRowCardView *card = [[RCInlineRowCardView alloc] initWithItem:item];
            card.showsGrabber = YES;
            __weak typeof(self) weakSelf = self;
            card.onActivate = ^{ [weakSelf activateIndex:(NSInteger)i]; };
            [stack addArrangedSubview:card];
            [cards addObject:card];
        }
        _cards = cards;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(valueChanged:)
                                                     name:RCInlineRowValueChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)valueChanged:(NSNotification *)note {
    if (![self.items containsObject:note.object]) return;
    [self refresh];
}

- (void)activateIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.cards.count) return;
    RCInlineRowSequenceTick();

    if (self.style == RCInlineRowSequenceStyleInline) {
        [self setExpandedIndex:(self.expandedIndex == index ? NSNotFound : index) animated:YES];
    } else if (self.style == RCInlineRowSequenceStyleInspector) {
        self.selectedIndex = index;
    }
    if (self.onActivate) self.onActivate(index, self.items[index]);
}

- (void)setExpandedIndex:(NSInteger)index {
    [self setExpandedIndex:index animated:NO];
}

- (void)setExpandedIndex:(NSInteger)index animated:(BOOL)animated {
    _expandedIndex = index;
    if (animated) RCInlineRowSequenceImpact();
    void (^changes)(void) = ^{
        for (NSUInteger i = 0; i < self.cards.count; i++) {
            RCInlineRowCardView *card = self.cards[i];
            BOOL expanded = ((NSInteger)i == index);
            [card setExpanded:expanded animated:NO];
            card.dimmed = (index != NSNotFound && (NSInteger)i != index);
            if (self.style == RCInlineRowSequenceStyleInline) card.selected = expanded;
        }
        [self layoutIfNeeded];
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
    } else {
        changes();
    }
}

- (void)setSelectedIndex:(NSInteger)index {
    _selectedIndex = index;
    for (NSUInteger i = 0; i < self.cards.count; i++) {
        self.cards[i].selected = ((NSInteger)i == index);
    }
}

- (void)refresh {
    for (RCInlineRowCardView *card in self.cards) [card refresh];
}

@end
