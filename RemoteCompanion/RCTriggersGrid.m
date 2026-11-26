#import "RCTriggersGrid.h"
#import "RCActionTile.h"
#import "RCConfigManager.h"
#import "RCTriggerIcons.h"

// A trigger in Compact: a wide card, its icon beside its name (up to three lines), or at 3 per row
// a tile, its icon above its name. Dimmed when it has no actions yet, or when its integration is
// switched off. In Edit, a star (favorite) and a minus (delete): on the card's right, or at the
// tile's top right.
@class RCIconMarquee;

@interface RCTriggerCardCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIStackView *editButtons;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, copy) void (^onFavorite)(void);
@property (nonatomic, copy) void (^onDelete)(void);
@property (nonatomic, assign) BOOL dimmed;
@property (nonatomic, copy) NSString *dimmedReason; // "No actions", "MQTT off", or nil
// The name runs to the card's edge, or (in Edit) to the star and minus
@property (nonatomic, strong) UILabel *detailLabel;   // its default name, under a name of the user's own
@property (nonatomic, strong) UIStackView *textStack;
@property (nonatomic, strong) NSLayoutConstraint *nameToEdge;
@property (nonatomic, strong) NSLayoutConstraint *nameToButtons;
// Beside (2 per row), stacked (3 per row) or mini (4 per row)
@property (nonatomic, assign) NSInteger perRow;
@property (nonatomic, assign) BOOL editShown;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *besideConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *stackedConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *miniConstraints;
// Compact Titles: Hide - the icon alone, centred and half the tile's width; the name is for VoiceOver
@property (nonatomic, assign) BOOL iconOnly;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *iconOnlyConstraints;
@property (nonatomic, strong) NSLayoutConstraint *iconWidth;
@property (nonatomic, strong) NSLayoutConstraint *iconHeight;
// A Chained Trigger's steps, scrolling across the tile in place of the icon
@property (nonatomic, strong) RCIconMarquee *marquee;
@end

// A row of icons that scrolls slowly and without end when it's wider than its place, its ends
// fading out (as a long song title does in Music); a still row, centered, when it fits or with
// Reduce Motion. A Chained Trigger's steps in Compact. Template icons take the view's tint.
@interface RCIconMarquee : UIView
- (void)setIcons:(NSArray<UIImage *> *)icons letter:(UIImage *)letter;
@end

@interface RCIconMarquee ()
@property (nonatomic, copy) NSArray<UIImage *> *icons;
@property (nonatomic, strong) UIView *strip;
@property (nonatomic, strong) UIImageView *letterView;
@property (nonatomic, strong) CAGradientLayer *fade;
@property (nonatomic, assign) CGSize builtFor;
@property (nonatomic, assign) CGFloat cycle; // one pass and its gap; 0 when it stands still
- (void)step:(CFTimeInterval)now;
@end

// One display link moves every scrolling strip on screen. Each is placed from the clock on every
// frame, so nothing can stop it: a Core Animation loop was dropped when the screen was covered and
// shown again, and stood still until the app came back from the background.
static NSHashTable<RCIconMarquee *> *RCMarqueesRunning;
static CADisplayLink *RCMarqueeLink;

@interface RCMarqueeTicker : NSObject
@end
@implementation RCMarqueeTicker
- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = CACurrentMediaTime();
    for (RCIconMarquee *marquee in RCMarqueesRunning.allObjects) [marquee step:now];
}
@end

static void RCMarqueeSetRunning(RCIconMarquee *marquee, BOOL running) {
    if (!RCMarqueesRunning) RCMarqueesRunning = [NSHashTable weakObjectsHashTable];
    if (running) [RCMarqueesRunning addObject:marquee]; else [RCMarqueesRunning removeObject:marquee];
    BOOL any = RCMarqueesRunning.allObjects.count > 0;
    if (any && !RCMarqueeLink) {
        static RCMarqueeTicker *ticker;
        if (!ticker) ticker = [[RCMarqueeTicker alloc] init];
        RCMarqueeLink = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
        if (@available(iOS 15.0, *)) RCMarqueeLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
        else RCMarqueeLink.preferredFramesPerSecond = 60;
        [RCMarqueeLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes]; // also while the list scrolls
    } else if (!any && RCMarqueeLink) {
        [RCMarqueeLink invalidate];
        RCMarqueeLink = nil;
    }
}

@implementation RCIconMarquee

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        _strip = [[UIView alloc] init];
        [self addSubview:_strip];
        _letterView = [[UIImageView alloc] init];
        _letterView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_letterView];
        _fade = [CAGradientLayer layer];
        _fade.startPoint = CGPointMake(0, 0.5);
        _fade.endPoint = CGPointMake(1, 0.5);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setIcons:(NSArray<UIImage *> *)icons letter:(UIImage *)letter {
    self.letterView.image = letter;
    self.letterView.hidden = !letter;
    if ([icons isEqualToArray:self.icons ?: @[]]) { [self updateRunning]; return; }
    self.icons = icons;
    [self rebuild];
}

- (void)rebuild {
    self.builtFor = CGSizeZero;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = self.bounds.size.height;
    self.letterView.frame = CGRectMake(self.bounds.size.width - height, 0, height, height);
    if (CGSizeEqualToSize(self.builtFor, self.bounds.size)) return;
    self.builtFor = self.bounds.size;
    for (UIView *view in self.strip.subviews) [view removeFromSuperview];
    self.cycle = 0;
    CGFloat width = self.bounds.size.width;
    if (!self.icons.count || height <= 0 || width <= 0) { [self updateRunning]; return; }
    CGFloat spacing = height * 0.12;
    CGFloat pitch = height + spacing;
    CGFloat run = self.icons.count * pitch - spacing; // one pass of the steps
    BOOL scrolls = run > width && !UIAccessibilityIsReduceMotionEnabled();
    // Scrolling: the steps twice, a wider space between the passes, so it runs on without a seam
    CGFloat cycle = run + height * 0.9;
    NSUInteger passes = scrolls ? 2 : 1;
    for (NSUInteger pass = 0; pass < passes; pass++) {
        for (NSUInteger i = 0; i < self.icons.count; i++) {
            UIImageView *view = [[UIImageView alloc] initWithImage:self.icons[i]];
            view.contentMode = UIViewContentModeScaleAspectFit;
            view.frame = CGRectMake(pass * cycle + i * pitch, 0, height, height);
            [self.strip addSubview:view];
        }
    }
    self.strip.frame = CGRectMake(scrolls ? 0 : MAX(0, (width - run) / 2), 0, passes * cycle, height);
    // The ends fade, where the steps come in and go out
    BOOL faded = run > width;
    self.layer.mask = faded ? self.fade : nil;
    if (faded) {
        self.fade.frame = self.bounds;
        CGFloat edge = MIN(0.18, 14.0 / width);
        id clear = (id)[UIColor clearColor].CGColor, solid = (id)[UIColor blackColor].CGColor;
        self.fade.colors = @[clear, solid, solid, clear];
        self.fade.locations = @[@0, @(edge), @(1 - edge), @1];
    }
    self.cycle = scrolls ? cycle : 0;
    [self updateRunning];
    [self step:CACurrentMediaTime()];
}

// Slow: about 14 points a second, all strips in step with each other
- (void)step:(CFTimeInterval)now {
    if (self.cycle <= 0) return;
    CGRect frame = self.strip.frame;
    frame.origin.x = -fmod(now * 14.0, self.cycle);
    self.strip.frame = frame;
}

// Moving only while it's on screen and has somewhere to go
- (void)updateRunning {
    RCMarqueeSetRunning(self, self.window && !self.hidden && self.cycle > 0);
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateRunning];
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self updateRunning];
}

@end

@implementation RCTriggerCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.layer.cornerRadius = 14;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_iconView];
        _marquee = [[RCIconMarquee alloc] init];
        _marquee.hidden = YES;
        [self.contentView addSubview:_marquee];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _nameLabel.numberOfLines = 3;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.85;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _detailLabel = [[UILabel alloc] init];
        _detailLabel.font = [UIFont systemFontOfSize:11];
        _detailLabel.textColor = [UIColor secondaryLabelColor];
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _detailLabel.hidden = YES;
        _textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _detailLabel]];
        _textStack.axis = UILayoutConstraintAxisVertical;
        _textStack.spacing = 1;
        _textStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_textStack];

        _favoriteButton = [self badgeButton:@selector(favoriteTapped)];
        _deleteButton = [self badgeButton:@selector(deleteTapped)];
        [_deleteButton setImage:[UIImage systemImageNamed:@"minus.circle.fill"] forState:UIControlStateNormal];
        _deleteButton.tintColor = [UIColor systemRedColor];
        _deleteButton.accessibilityLabel = @"Delete";
        _editButtons = [[UIStackView alloc] initWithArrangedSubviews:@[_favoriteButton, _deleteButton]];
        _editButtons.spacing = 0;
        _editButtons.translatesAutoresizingMaskIntoConstraints = NO;
        _editButtons.hidden = YES;
        [self.contentView addSubview:_editButtons];

        UIView *content = self.contentView;
        _iconWidth = [_iconView.widthAnchor constraintEqualToConstant:34];
        _iconHeight = [_iconView.heightAnchor constraintEqualToConstant:30];
        [NSLayoutConstraint activateConstraints:@[_iconWidth, _iconHeight]];
        // Beside: the icon at the left, the name centred beside it, the edit buttons at the right
        _besideConstraints = @[
            [_iconView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
            [_iconView.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
            [_textStack.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:8],
            [_textStack.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
            [_textStack.topAnchor constraintGreaterThanOrEqualToAnchor:content.topAnchor constant:6],
            [_editButtons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-4],
            [_editButtons.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        ];
        // Stacked: the icon at the top left, the name under it across the tile, the edit buttons
        // at the top right
        _stackedConstraints = @[
            [_iconView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
            [_iconView.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
            [_textStack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
            [_textStack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
            [_textStack.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:4],
            [_textStack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-6],
            [_editButtons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-2],
            [_editButtons.topAnchor constraintEqualToAnchor:content.topAnchor constant:0],
        ];
        // Mini: the icon centred at the top, the name centred under it, the star and minus in the
        // top corners
        _miniConstraints = @[
            [_iconView.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
            [_iconView.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
            [_textStack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:4],
            [_textStack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-4],
            [_textStack.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:4],
            [_textStack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-5],
            [_editButtons.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [_editButtons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [_editButtons.topAnchor constraintEqualToAnchor:content.topAnchor constant:-4],
        ];
        // Icon only: the icon in the middle, half the tile's width, the star and minus in the top corners
        _iconOnlyConstraints = @[
            [_iconView.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToAnchor:content.widthAnchor multiplier:0.5],
            [_iconView.heightAnchor constraintEqualToAnchor:_iconView.widthAnchor],
            [_editButtons.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [_editButtons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [_editButtons.topAnchor constraintEqualToAnchor:content.topAnchor constant:-4],
        ];
        // Beside, hidden buttons still hold their place, so the name's end is switched with them
        _nameToEdge = [_textStack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10];
        _nameToButtons = [_textStack.trailingAnchor constraintEqualToAnchor:_editButtons.leadingAnchor constant:-2];
        [NSLayoutConstraint activateConstraints:_besideConstraints];
        _perRow = 2;
        [self updateNameEnd];
        [self applyLook];
    }
    return self;
}

- (UIButton *)badgeButton:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular] forImageInState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:34].active = YES;
    [button.heightAnchor constraintEqualToConstant:40].active = YES;
    return button;
}

- (NSArray<NSLayoutConstraint *> *)constraintsForPerRow:(NSInteger)perRow {
    return perRow >= 4 ? self.miniConstraints : perRow == 3 ? self.stackedConstraints : self.besideConstraints;
}

// The constraints in use: icon only, or the layout for this many per row
- (NSArray<NSLayoutConstraint *> *)activeLayoutConstraints {
    return self.iconOnly ? self.iconOnlyConstraints : [self constraintsForPerRow:self.perRow];
}

- (void)setIconOnly:(BOOL)iconOnly {
    if (iconOnly == _iconOnly) return;
    [NSLayoutConstraint deactivateConstraints:[self activeLayoutConstraints]];
    _iconOnly = iconOnly;
    [NSLayoutConstraint activateConstraints:[self activeLayoutConstraints]];
    // The fixed icon size is the per-row layouts'; icon only sizes it from the tile
    self.iconWidth.active = !iconOnly;
    self.iconHeight.active = !iconOnly;
    self.textStack.hidden = iconOnly;
    self.editButtons.distribution = (iconOnly || self.perRow >= 4) ? UIStackViewDistributionEqualSpacing : UIStackViewDistributionFill;
    [self updateNameEnd];
}

- (void)setPerRow:(NSInteger)perRow {
    perRow = MAX(2, MIN(4, perRow));
    if (perRow == _perRow) return;
    if (!self.iconOnly) [NSLayoutConstraint deactivateConstraints:[self constraintsForPerRow:_perRow]];
    _perRow = perRow;
    if (!self.iconOnly) [NSLayoutConstraint activateConstraints:[self constraintsForPerRow:perRow]];
    BOOL mini = perRow >= 4;
    self.nameLabel.font = [UIFont systemFontOfSize:perRow == 2 ? 14 : perRow == 3 ? 12.5 : 11 weight:UIFontWeightMedium];
    self.nameLabel.textAlignment = mini ? NSTextAlignmentCenter : NSTextAlignmentNatural;
    self.detailLabel.font = [UIFont systemFontOfSize:perRow == 2 ? 11 : 10];
    // The star and minus: side by side, or one in each top corner, smaller there (with the icon)
    // so they clear the icon between them
    self.editButtons.distribution = (mini || self.iconOnly) ? UIStackViewDistributionEqualSpacing : UIStackViewDistributionFill;
    // Beside: the full icon; stacked and mini tiles are shorter, so a smaller one
    self.iconWidth.constant = perRow == 2 ? 34 : perRow == 3 ? 30 : 28;
    self.iconHeight.constant = perRow == 2 ? 30 : 26;
    UIImageSymbolConfiguration *buttonSize = [UIImageSymbolConfiguration configurationWithPointSize:mini ? 17 : 20 weight:UIImageSymbolWeightRegular];
    [self.favoriteButton setPreferredSymbolConfiguration:buttonSize forImageInState:UIControlStateNormal];
    [self.deleteButton setPreferredSymbolConfiguration:buttonSize forImageInState:UIControlStateNormal];
    [self updateNameEnd];
    [self showDetail];
}

// Beside: the name runs to the card's edge, or (in Edit) to the star and minus
- (void)updateNameEnd {
    BOOL beside = self.perRow == 2 && !self.iconOnly;
    BOOL toButtons = beside && self.editShown;
    BOOL toEdge = beside && !self.editShown;
    self.nameToButtons.active = toButtons;
    self.nameToEdge.active = toEdge;
}

// The default name under a name of the user's own, except on the smallest tiles
- (void)showDetail {
    BOOL shown = self.detailLabel.text.length > 0 && self.perRow < 4;
    self.detailLabel.hidden = !shown;
    self.nameLabel.numberOfLines = shown ? 2 : 3;
}

// detail: its default name when it has one of the user's own (shown under it), else nil
- (void)setName:(NSString *)name detail:(NSString *)detail image:(UIImage *)image {
    self.nameLabel.text = name;
    self.detailLabel.text = detail;
    [self showDetail];
    self.iconView.image = image ?: [UIImage systemImageNamed:@"hand.tap"];
    self.accessibilityLabel = detail.length ? [NSString stringWithFormat:@"%@, %@", name, detail] : name;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
}

- (void)setDimmed:(BOOL)dimmed {
    _dimmed = dimmed;
    [self applyLook];
}

// Dimmed, with the reason shown to VoiceOver ("No actions", "MQTT off"); nil is the normal look
- (void)setDimmedReason:(NSString *)reason {
    _dimmedReason = [reason copy];
    self.dimmed = reason.length > 0;
}

- (void)applyLook {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.contentView.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    self.iconView.tintColor = self.dimmed ? [UIColor tertiaryLabelColor] : [UIColor labelColor];
    self.iconView.alpha = self.dimmed ? 0.6 : 1; // an app's own icon isn't tinted
    self.marquee.tintColor = self.iconView.tintColor;
    self.marquee.alpha = self.iconView.alpha;
    self.nameLabel.textColor = self.dimmed ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    self.accessibilityValue = self.dimmedReason;
}

- (void)showEditFavorite:(BOOL)favorite deletable:(BOOL)deletable onFavorite:(void (^)(void))onFavorite onDelete:(void (^)(void))onDelete {
    [self.favoriteButton setImage:[UIImage systemImageNamed:favorite ? @"star.fill" : @"star"] forState:UIControlStateNormal];
    self.favoriteButton.tintColor = favorite ? [UIColor colorWithRed:242/255.0 green:195/255.0 blue:80/255.0 alpha:1.0] : [UIColor secondaryLabelColor];
    self.favoriteButton.accessibilityLabel = favorite ? @"Unfavorite" : @"Favorite";
    // A trigger that can't be deleted keeps an empty place for the minus, so the star stays put
    self.deleteButton.alpha = deletable ? 1 : 0;
    self.deleteButton.userInteractionEnabled = deletable;
    self.deleteButton.accessibilityElementsHidden = !deletable;
    self.editButtons.hidden = NO;
    self.editShown = YES;
    [self updateNameEnd];
    self.onFavorite = onFavorite;
    self.onDelete = onDelete;
}

- (void)hideEdit {
    self.editButtons.hidden = YES;
    self.editShown = NO;
    [self updateNameEnd];
    self.onFavorite = nil;
    self.onDelete = nil;
}

- (void)favoriteTapped {
    if (self.onFavorite) self.onFavorite();
}

- (void)deleteTapped {
    if (self.onDelete) self.onDelete();
}

- (NSArray *)accessibilityCustomActions {
    if (self.editButtons.hidden) return nil;
    NSMutableArray *actions = [NSMutableArray arrayWithObject:[[UIAccessibilityCustomAction alloc] initWithName:self.favoriteButton.accessibilityLabel target:self selector:@selector(favoriteTapped)]];
    if (self.deleteButton.userInteractionEnabled) [actions addObject:[[UIAccessibilityCustomAction alloc] initWithName:@"Delete" target:self selector:@selector(deleteTapped)]];
    return actions;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.contentView.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
        self.contentView.alpha = highlighted ? 0.75 : 1;
    }];
}

// A Chained Trigger's steps across the tile, where the icon would be (nil: the icon); letter: its
// letter tag's badge, or nil
- (void)setSteps:(NSArray<UIImage *> *)steps letter:(UIImage *)letter {
    BOOL shown = steps.count > 0;
    self.marquee.hidden = !shown;
    self.iconView.hidden = shown; // still laid out: the strip takes its height and place
    if (shown) [self.marquee setIcons:steps letter:letter];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.marquee.hidden) return;
    CGRect icon = self.iconView.frame;
    BOOL beside = self.perRow == 2 && !self.iconOnly;
    // Beside the name, the strip keeps to the icon's place; above it (or alone), it's the tile's width
    self.marquee.frame = beside ? icon : CGRectMake(4, icon.origin.y, self.contentView.bounds.size.width - 8, icon.size.height);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self setSteps:nil letter:nil];
    self.contentView.transform = CGAffineTransformIdentity;
    self.contentView.alpha = 1;
    [self hideEdit];
    self.dimmedReason = nil;
    self.dimmed = NO;
}

@end

// Holds the screen's footer view under the last section
@interface RCTriggersGridFooter : UICollectionReusableView
- (void)showView:(UIView *)view;
@end

@implementation RCTriggersGridFooter
- (void)showView:(UIView *)view {
    for (UIView *sub in self.subviews) if (sub != view) [sub removeFromSuperview];
    if (!view) return;
    view.frame = self.bounds;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (view.superview != self) [self addSubview:view];
}
@end

@interface RCTriggersGrid ()
@property (nonatomic, strong, readwrite) UICollectionView *collectionView;
@property (nonatomic, assign) BOOL moving;
@end

@implementation RCTriggersGrid

- (instancetype)initWithSource:(id<RCTriggersGridSource>)source {
    self = [super init];
    if (self) {
        _source = source;
        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:RCActionGridLayout()];
        _collectionView.dataSource = self;
        _collectionView.delegate = self;
        _collectionView.alwaysBounceVertical = YES;
        [_collectionView registerClass:[RCTriggerCardCell class] forCellWithReuseIdentifier:@"Trigger"];
        [_collectionView registerClass:[RCActionGridHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"Header"];
        [_collectionView registerClass:[RCTriggersGridFooter class] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:@"Footer"];
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
        press.minimumPressDuration = 0.5;
        [_collectionView addGestureRecognizer:press];
    }
    return self;
}

- (void)reload {
    if (self.moving) return; // after the drag
    [self.collectionView reloadData];
}

- (void)setEditing:(BOOL)editing {
    _editing = editing;
    [self reload];
}

- (NSString *)keyAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *keys = [self.source gridKeysInSection:indexPath.section];
    return indexPath.item < (NSInteger)keys.count ? keys[indexPath.item] : nil;
}

#pragma mark - Data

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return [self.source gridSectionCount];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self.source gridKeysInSection:section].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RCTriggerCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Trigger" forIndexPath:indexPath];
    cell.perRow = RCLayoutPerRow(RCLayoutTriggers);
    cell.iconOnly = RCLayoutNamesHidden(RCLayoutTriggers);
    NSString *key = [self keyAtIndexPath:indexPath];
    id<RCTriggersGridSource> source = self.source;
    [cell setName:[source gridNameForTrigger:key] detail:[source gridDetailForTrigger:key] image:[source gridImageForTrigger:key]];
    if ([source respondsToSelector:@selector(gridStepImagesForTrigger:)]) {
        NSArray *steps = [source gridStepImagesForTrigger:key];
        [cell setSteps:steps letter:steps.count ? [source gridStepsLetterForTrigger:key] : nil];
    }
    cell.dimmedReason = [source gridOffIntegrationForTrigger:key] ?: ([source gridActionCountForTrigger:key] == 0 ? @"No actions" : nil);
    cell.accessibilityHint = self.editing ? nil : @"Long press to run it now";
    if (self.editing) {
        __weak typeof(self) weakSelf = self;
        __weak RCTriggerCardCell *weakCell = cell;
        [cell showEditFavorite:[source gridTriggerIsFavorite:key] deletable:[source gridCanDeleteTrigger:key]
                    onFavorite:^{ [weakSelf.source gridToggleFavorite:key]; }
                      onDelete:^{ [weakSelf.source gridDeleteTrigger:key fromView:weakCell]; }];
    } else {
        [cell hideEdit];
    }
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    if ([kind isEqualToString:UICollectionElementKindSectionFooter]) {
        RCTriggersGridFooter *footer = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"Footer" forIndexPath:indexPath];
        BOOL last = indexPath.section == [self.source gridSectionCount] - 1;
        [footer showView:last ? self.footerView : nil];
        return footer;
    }
    RCActionGridHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"Header" forIndexPath:indexPath];
    NSString *title = [self.source gridTitleForSection:indexPath.section];
    [header setTitle:title icon:RCTriggerCategoryIcon(title)];
    if ([self.source gridSectionIsFavorites:indexPath.section]) {
        header.label.textColor = [UIColor colorWithRed:242/255.0 green:195/255.0 blue:80/255.0 alpha:1.0];
        header.tintColor = header.label.textColor;
    }
    return header;
}

#pragma mark - Layout

// Wide cards (2 per row on a phone), tiles (3) or small tiles (4); more on a wider screen
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat usable = MAX(0, RCGridWidth(collectionView) - 32);
    NSInteger perRow = RCLayoutPerRow(RCLayoutTriggers);
    CGFloat minimum = perRow == 2 ? 170 : perRow == 3 ? 104 : 76;
    CGFloat height = perRow == 2 ? 64 : perRow == 3 ? 92 : 84;
    NSInteger columns = MAX(perRow, (NSInteger)floor((usable + 8) / (minimum + 8)));
    CGFloat width = floor((usable - 8 * (columns - 1)) / columns);
    // Compact Titles: Hide - square tiles around a larger icon
    if (RCLayoutNamesHidden(RCLayoutTriggers)) return CGSizeMake(width, width);
    return CGSizeMake(width, height);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section {
    if (![self.source gridTitleForSection:section].length) return CGSizeMake(collectionView.bounds.size.width, 8); // one grid, no titles
    // The first title sits just below the category bar
    return CGSizeMake(collectionView.bounds.size.width, section == 0 ? 30 : 38);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForFooterInSection:(NSInteger)section {
    BOOL last = section == [self.source gridSectionCount] - 1;
    return CGSizeMake(collectionView.bounds.size.width, last && self.footerView ? 60 : 0);
}

#pragma mark - Taps

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    return !self.editing; // in Edit, a tile's star and minus do the work
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    NSString *key = [self keyAtIndexPath:indexPath];
    if (key) [self.source gridOpenTrigger:key];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.source gridDidScroll:scrollView];
}

// Long press: run the trigger now; in Edit, drag a favorite to a new place
- (void)longPressed:(UILongPressGestureRecognizer *)press {
    CGPoint point = [press locationInView:self.collectionView];
    switch (press.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath *path = [self.collectionView indexPathForItemAtPoint:point];
            if (!path) return;
            if (self.editing) {
                if (![self.source gridSectionIsFavorites:path.section]) return;
                self.moving = [self.collectionView beginInteractiveMovementForItemAtIndexPath:path];
                if (self.moving) [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
            } else {
                NSString *key = [self keyAtIndexPath:path];
                if (key) [self.source gridRunTrigger:key fromView:[self.collectionView cellForItemAtIndexPath:path]];
            }
            break;
        }
        case UIGestureRecognizerStateChanged:
            if (self.moving) [self.collectionView updateInteractiveMovementTargetPosition:point];
            break;
        case UIGestureRecognizerStateEnded:
            if (self.moving) [self.collectionView endInteractiveMovement];
            self.moving = NO;
            break;
        default:
            if (self.moving) [self.collectionView cancelInteractiveMovement];
            self.moving = NO;
            break;
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView canMoveItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.editing && [self.source gridSectionIsFavorites:indexPath.section];
}

// A favorite stays among the favorites
- (NSIndexPath *)collectionView:(UICollectionView *)collectionView targetIndexPathForMoveFromItemAtIndexPath:(NSIndexPath *)original toProposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section == original.section) return proposed;
    NSInteger count = [collectionView numberOfItemsInSection:original.section];
    return [NSIndexPath indexPathForItem:(proposed.section < original.section ? 0 : count - 1) inSection:original.section];
}

- (void)collectionView:(UICollectionView *)collectionView moveItemAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    if (from.section != to.section || from.item == to.item) return;
    [self.source gridMoveFavoriteFrom:from.item to:to.item];
}

@end
