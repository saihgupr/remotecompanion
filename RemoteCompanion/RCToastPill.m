#import "RCToastPill.h"

// Shared pill metrics. These are the exact numbers the on-device toast has
// always used (native iOS 15 ringer HUD look); the editor preview used to
// keep its own copy, which is why the two could disagree.
static const CGFloat RCToastPillMinWidth = 140.0;
static const CGFloat RCToastPillHeightSingle = 40.0;
static const CGFloat RCToastPillHeightDouble = 50.0;
static const CGFloat RCToastPillLeftPadding = 16.0;
static const CGFloat RCToastPillIconSize = 20.0;
static const CGFloat RCToastPillIconGap = 10.0;
static const CGFloat RCToastPillTitleTop = 8.0;
static const CGFloat RCToastPillTitleHeight = 18.0;
static const CGFloat RCToastPillMessageTop = 26.0;
static const CGFloat RCToastPillMessageHeight = 16.0;

@implementation RCToastPillView {
    UIVisualEffectView *_blurView;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_subLabel;
    UIBlurEffectStyle _appliedStyle;
    BOOL _hasAppliedStyle;
}

+ (UIFont *)pillTitleFont {
    return [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
}

+ (UIFont *)pillMessageFont {
    return [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
}

+ (UIImage *)pillIconImageForName:(NSString *)iconName {
    if (!iconName || iconName.length == 0) return nil;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16.0
                                                                                         weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:iconName withConfiguration:config];
}

+ (BOOL)hasIconForName:(NSString *)iconName {
    if (!iconName || iconName.length == 0) return NO;
    if ([iconName isEqualToString:@"none"]) return NO;
    return [UIImage systemImageNamed:iconName] != nil;
}

+ (CGFloat)leftMarginForIconName:(NSString *)iconName {
    BOOL hasIcon = [self hasIconForName:iconName];
    return RCToastPillLeftPadding + (hasIcon ? RCToastPillIconSize + RCToastPillIconGap : 0.0);
}

+ (CGFloat)maxPillWidthForScreenWidth:(CGFloat)screenWidth {
    return screenWidth - 32.0;
}

+ (BOOL)hasMessage:(NSString *)message {
    return (message && message.length > 0);
}

+ (CGSize)sizeForTitle:(NSString *)title
               message:(NSString *)message
              iconName:(NSString *)iconName
          wrapsMessage:(BOOL)wrap
              maxWidth:(CGFloat)maxWidth {
    UIFont *titleFont = [self pillTitleFont];
    UIFont *subtitleFont = [self pillMessageFont];

    CGFloat maxTextWidth = 0;
    if (title && title.length > 0) {
        maxTextWidth = [title sizeWithAttributes:@{ NSFontAttributeName: titleFont }].width;
    }
    if ([self hasMessage:message]) {
        CGFloat w = [message sizeWithAttributes:@{ NSFontAttributeName: subtitleFont }].width;
        if (w > maxTextWidth) maxTextWidth = w;
    }

    CGFloat leftMargin = [self leftMarginForIconName:iconName];
    CGFloat pillWidth = maxTextWidth + 2 * leftMargin;
    pillWidth = MAX(RCToastPillMinWidth, MIN(pillWidth, maxWidth));

    BOOL hasSubtitle = [self hasMessage:message];
    CGFloat pillHeight = hasSubtitle ? RCToastPillHeightDouble : RCToastPillHeightSingle;
    if (wrap && hasSubtitle) {
        CGRect needed = [message boundingRectWithSize:CGSizeMake(pillWidth - 2 * leftMargin, CGFLOAT_MAX)
                                              options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                           attributes:@{ NSFontAttributeName: subtitleFont }
                                              context:nil];
        CGFloat subtitleHeight = MAX(RCToastPillMessageHeight, ceil(needed.size.height));
        pillHeight += subtitleHeight - RCToastPillMessageHeight;
    }
    return CGSizeMake(pillWidth, pillHeight);
}

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                     iconName:(NSString *)iconName {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _pillTitle = [title copy];
        _pillMessage = [message copy];
        _pillIconName = [iconName copy];
        _hasAppliedStyle = NO;

        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;

        _blurView = [[UIVisualEffectView alloc] init];
        _blurView.userInteractionEnabled = NO;
        _blurView.layer.masksToBounds = YES;
        [self addSubview:_blurView];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.userInteractionEnabled = NO;
        [self addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [[self class] pillTitleFont];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.userInteractionEnabled = NO;
        [self addSubview:_titleLabel];

        _subLabel = [[UILabel alloc] init];
        _subLabel.font = [[self class] pillMessageFont];
        _subLabel.textAlignment = NSTextAlignmentCenter;
        _subLabel.numberOfLines = 1;
        _subLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _subLabel.userInteractionEnabled = NO;
        [self addSubview:_subLabel];

        [self applyAppearanceIfNeeded:YES];
        [self refreshContent];
    }
    return self;
}

- (void)setPillTitle:(NSString *)pillTitle {
    if ((_pillTitle == pillTitle) || [_pillTitle isEqualToString:pillTitle]) return;
    _pillTitle = [pillTitle copy];
    [self refreshContent];
}

- (void)setPillMessage:(NSString *)pillMessage {
    if ((_pillMessage == pillMessage) || [_pillMessage isEqualToString:pillMessage]) return;
    _pillMessage = [pillMessage copy];
    [self refreshContent];
}

- (void)setPillIconName:(NSString *)pillIconName {
    if ((_pillIconName == pillIconName) || [_pillIconName isEqualToString:pillIconName]) return;
    _pillIconName = [pillIconName copy];
    [self refreshContent];
}

- (void)setShowsPlaceholderTitle:(BOOL)showsPlaceholderTitle {
    if (_showsPlaceholderTitle == showsPlaceholderTitle) return;
    _showsPlaceholderTitle = showsPlaceholderTitle;
    [self refreshContent];
}

- (void)setWrapsMessage:(BOOL)wrapsMessage {
    if (_wrapsMessage == wrapsMessage) return;
    _wrapsMessage = wrapsMessage;
    [self refreshContent];
}

- (BOOL)isDarkMode {
    if (@available(iOS 12.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) return NO;
    }
    return YES;
}

- (void)applyAppearanceIfNeeded:(BOOL)force {
    BOOL dark = [self isDarkMode];
    UIBlurEffectStyle style = dark ? UIBlurEffectStyleSystemMaterialDark : UIBlurEffectStyleSystemMaterialLight;
    if (!force && _hasAppliedStyle && style == _appliedStyle) return;
    _appliedStyle = style;
    _hasAppliedStyle = YES;
    _blurView.effect = [UIBlurEffect effectWithStyle:style];
    if (_pillTitle.length == 0 && _showsPlaceholderTitle) {
        _titleLabel.textColor = [UIColor tertiaryLabelColor];
    } else {
        _titleLabel.textColor = dark ? [UIColor whiteColor] : [UIColor colorWithWhite:0.0 alpha:0.8];
    }
    _subLabel.textColor = dark ? [UIColor colorWithWhite:1.0 alpha:0.6] : [UIColor colorWithWhite:0.0 alpha:0.48];
    _iconView.tintColor = dark ? [UIColor whiteColor] : [UIColor colorWithWhite:0.0 alpha:0.7];
}

- (void)refreshContent {
    BOOL hasIcon = [[self class] hasIconForName:_pillIconName];
    _iconView.hidden = !hasIcon;
    _iconView.image = hasIcon ? [[self class] pillIconImageForName:_pillIconName] : nil;

    BOOL hasSubtitle = [[self class] hasMessage:_pillMessage];
    _subLabel.hidden = !hasSubtitle;
    _subLabel.numberOfLines = (_wrapsMessage && hasSubtitle) ? 0 : 1;

    if (_pillTitle.length == 0 && _showsPlaceholderTitle) {
        _titleLabel.text = @"Title";
    } else {
        _titleLabel.text = _pillTitle ?: @"";
    }
    _subLabel.text = _pillMessage;
    [self applyAppearanceIfNeeded:NO];

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyAppearanceIfNeeded:NO];

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    _blurView.frame = self.bounds;
    _blurView.layer.cornerRadius = MIN(h, 50.0) / 2.0;

    BOOL hasIcon = [[self class] hasIconForName:_pillIconName];
    if (hasIcon) {
        _iconView.frame = CGRectMake(RCToastPillLeftPadding, (h - RCToastPillIconSize) / 2.0,
                                     RCToastPillIconSize, RCToastPillIconSize);
    }

    BOOL hasSubtitle = [[self class] hasMessage:_pillMessage];
    if (hasSubtitle) {
        _titleLabel.frame = CGRectMake(0, RCToastPillTitleTop, w, RCToastPillTitleHeight);
        if (_wrapsMessage) {
            CGFloat leftMargin = [[self class] leftMarginForIconName:_pillIconName];
            UIFont *subFont = [[self class] pillMessageFont];
            CGRect needed = [_pillMessage boundingRectWithSize:CGSizeMake(w - 2 * leftMargin, CGFLOAT_MAX)
                                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                   attributes:@{ NSFontAttributeName: subFont }
                                                      context:nil];
            CGFloat subtitleHeight = MAX(RCToastPillMessageHeight, ceil(needed.size.height));
            _subLabel.frame = CGRectMake(leftMargin, RCToastPillMessageTop, w - 2 * leftMargin, subtitleHeight);
        } else {
            _subLabel.frame = CGRectMake(0, RCToastPillMessageTop, w, RCToastPillMessageHeight);
        }
    } else {
        _titleLabel.frame = CGRectMake(0, 0, w, h);
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self applyAppearanceIfNeeded:YES];
        }
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self applyAppearanceIfNeeded:YES];
    [self setNeedsLayout];
}

@end
