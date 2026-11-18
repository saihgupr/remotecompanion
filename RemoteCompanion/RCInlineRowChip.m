#import "RCInlineRowChip.h"

static UIColor *RCInlineRowChipAccent(UIView *view) {
    return view.tintColor ?: [UIColor systemBlueColor];
}

static UIImage *RCInlineRowChipSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIImageConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    UIImage *image = name.length ? [UIImage systemImageNamed:name withConfiguration:configuration] : nil;
    return image ?: [UIImage systemImageNamed:@"square.dashed" withConfiguration:configuration];
}

static UIFont *RCInlineRowChipDigitFont(void) {
    UIFont *base = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:base];
}

@interface RCInlineRowChip ()
@property (nonatomic, strong) NSLayoutConstraint *labelToCaret;
@property (nonatomic, strong) NSLayoutConstraint *labelToEdge;
@property (nonatomic, strong) NSLayoutConstraint *caretToEdge;
@property (nonatomic, strong) NSLayoutConstraint *caretWidth;
@property (nonatomic, strong) NSLayoutConstraint *caretHeight;
@end

@implementation RCInlineRowChip

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = NO;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.backgroundColor = [UIColor secondarySystemFillColor];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = RCInlineRowChipDigitFont();
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

        _caretView = [[UIImageView alloc] initWithImage:RCInlineRowChipSymbol(@"chevron.up.chevron.down", 9, UIImageSymbolWeightSemibold)];
        _caretView.contentMode = UIViewContentModeScaleAspectFit;
        _caretView.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_titleLabel];
        [self addSubview:_caretView];

        self.labelToCaret = [_titleLabel.trailingAnchor constraintEqualToAnchor:_caretView.leadingAnchor constant:-5];
        self.labelToEdge = [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10];
        self.caretToEdge = [_caretView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10];
        self.caretWidth = [_caretView.widthAnchor constraintEqualToConstant:9];
        self.caretHeight = [_caretView.heightAnchor constraintEqualToConstant:9];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:11],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:6],
            [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-6],
            [_caretView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            self.caretWidth,
            self.caretHeight,
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:30],
        ]];
        [self applyLook];
        self.showsCaret = YES;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2;
}

- (void)setShowsCaret:(BOOL)showsCaret {
    _showsCaret = showsCaret;
    self.caretView.hidden = !showsCaret;
    self.labelToCaret.active = showsCaret;
    self.caretToEdge.active = showsCaret;
    self.caretWidth.active = showsCaret;
    self.caretHeight.active = showsCaret;
    self.labelToEdge.active = !showsCaret;
    [self invalidateIntrinsicContentSize];
}

- (void)setValueText:(NSString *)text {
    self.titleLabel.text = text;
    self.accessibilityValue = text;
}

- (void)setAccented:(BOOL)accented {
    _accented = accented;
    [self applyLook];
}

- (void)applyLook {
    UIColor *accent = RCInlineRowChipAccent(self);
    self.backgroundColor = self.isAccented ? [accent colorWithAlphaComponent:0.16] : [UIColor secondarySystemFillColor];
    self.titleLabel.textColor = self.isAccented ? accent : [UIColor labelColor];
    self.caretView.tintColor = self.isAccented ? [accent colorWithAlphaComponent:0.85] : [UIColor tertiaryLabelColor];
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self applyLook];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.55 : 1.0;
}

@end
