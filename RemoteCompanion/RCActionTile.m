#import "RCActionTile.h"
#import "RCConfigManager.h"
#import <objc/runtime.h>

static const CGFloat RCGridSide = 16;    // space at the grid's left and right
static const CGFloat RCGridSpacing = 8;  // space between tiles
static const CGFloat RCTileMinWidth = 80;

@interface RCActionTileCell ()
@property (nonatomic, strong, readwrite) UIImageView *iconView;
@property (nonatomic, strong, readwrite) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *badgeView;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, copy) void (^onFavorite)(void);
@property (nonatomic, copy) void (^onDelete)(void);
@property (nonatomic, assign) BOOL editing;
// The icon above the name, or (icon only) centred in the tile at half its width
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *namedConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *iconOnlyConstraints;
@end

@implementation RCActionTileCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.layer.cornerRadius = 14;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.layer.borderColor = [UIColor systemBlueColor].CGColor;

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_iconView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        // Three lines, shrinking a little, so long names such as "Ringer Unmuted (Silent Mode Off)"
        // fit a four-column grid instead of ending in "..."
        _nameLabel.numberOfLines = 3;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.8;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_nameLabel];

        // The corner mark: a chevron (opens more) or a checkmark (checked)
        _badgeView = [[UIImageView alloc] init];
        _badgeView.contentMode = UIViewContentModeScaleAspectFit;
        _badgeView.translatesAutoresizingMaskIntoConstraints = NO;
        _badgeView.hidden = YES;
        [self.contentView addSubview:_badgeView];

        _namedConstraints = @[
            [_iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_iconView.widthAnchor constraintEqualToConstant:30],
            [_iconView.heightAnchor constraintEqualToConstant:28],
        ];
        _iconOnlyConstraints = @[
            [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor multiplier:0.5],
            [_iconView.heightAnchor constraintEqualToAnchor:_iconView.widthAnchor],
        ];
        [NSLayoutConstraint activateConstraints:_namedConstraints];
        [NSLayoutConstraint activateConstraints:@[
            [_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:5],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-5],
            [_nameLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:4],
            [_nameLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [_badgeView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:7],
            [_badgeView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-7],
            [_badgeView.widthAnchor constraintEqualToConstant:14],
            [_badgeView.heightAnchor constraintEqualToConstant:14],
        ]];
        [self applyLook];
    }
    return self;
}

- (void)setName:(NSString *)name icon:(NSString *)icon {
    [self setName:name icon:icon image:nil];
}

- (void)setName:(NSString *)name icon:(NSString *)icon image:(UIImage *)custom {
    // "Set Volume..." reads "Set Volume" on a tile: the chevron says there's more
    NSString *shown = name ?: @"";
    for (NSString *dots in @[@"...", @"…"]) {
        if ([shown hasSuffix:dots]) shown = [shown substringToIndex:shown.length - dots.length];
    }
    self.nameLabel.text = shown;
    self.accessibilityLabel = shown;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    UIImage *image = custom ?: (icon.length ? [UIImage systemImageNamed:icon] : nil);
    self.iconView.image = image ?: [UIImage systemImageNamed:@"square.dashed"];
}

- (void)setIconOnly:(BOOL)iconOnly {
    if (iconOnly == _iconOnly) return;
    _iconOnly = iconOnly;
    [NSLayoutConstraint deactivateConstraints:iconOnly ? self.namedConstraints : self.iconOnlyConstraints];
    [NSLayoutConstraint activateConstraints:iconOnly ? self.iconOnlyConstraints : self.namedConstraints];
    self.nameLabel.hidden = iconOnly;
    // A symbol drawn for the larger size, so it stays sharp
    self.iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:iconOnly ? 40 : 22 weight:UIImageSymbolWeightRegular];
}

- (void)setOpensMore:(BOOL)opensMore {
    _opensMore = opensMore;
    [self applyLook];
}

- (void)setChecked:(BOOL)checked {
    _checked = checked;
    [self applyLook];
}

- (void)setPlainChecked:(BOOL)plainChecked {
    _plainChecked = plainChecked;
    [self applyLook];
}

- (void)setDimmed:(BOOL)dimmed {
    _dimmed = dimmed;
    [self applyLook];
}

- (void)setCount:(NSInteger)count {
    _count = count;
    if (count > 0 && !self.countLabel) {
        UILabel *label = [[UILabel alloc] init];
        label.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.backgroundColor = [UIColor systemBlueColor];
        label.layer.cornerRadius = 9;
        label.layer.masksToBounds = YES;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [label.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6],
            [label.heightAnchor constraintEqualToConstant:18],
            [label.widthAnchor constraintGreaterThanOrEqualToConstant:18],
        ]];
        self.countLabel = label;
    }
    // " 12 " keeps a wider number off the edges of its capsule
    self.countLabel.text = count > 9 ? [NSString stringWithFormat:@" %ld ", (long)count] : [NSString stringWithFormat:@"%ld", (long)count];
    [self applyLook];
}

#pragma mark Edit mode (Triggers)

- (UIButton *)makeBadgeButton:(NSString *)symbol action:(SEL)action label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    [button setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular] forImageInState:UIControlStateNormal];
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:button];
    return button;
}

- (void)showEditBadgesFavorite:(BOOL)favorite deletable:(BOOL)deletable onFavorite:(void (^)(void))onFavorite onDelete:(void (^)(void))onDelete {
    if (!self.favoriteButton) {
        self.favoriteButton = [self makeBadgeButton:@"star" action:@selector(favoriteTapped) label:@"Favorite"];
        self.deleteButton = [self makeBadgeButton:@"minus.circle.fill" action:@selector(deleteTapped) label:@"Delete"];
        self.deleteButton.tintColor = [UIColor systemRedColor];
        [NSLayoutConstraint activateConstraints:@[
            [self.favoriteButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.favoriteButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.favoriteButton.widthAnchor constraintEqualToConstant:36],
            [self.favoriteButton.heightAnchor constraintEqualToConstant:36],
            [self.deleteButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.deleteButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.deleteButton.widthAnchor constraintEqualToConstant:36],
            [self.deleteButton.heightAnchor constraintEqualToConstant:36],
        ]];
    }
    [self.favoriteButton setImage:[UIImage systemImageNamed:favorite ? @"star.fill" : @"star"] forState:UIControlStateNormal];
    self.favoriteButton.tintColor = favorite ? [UIColor colorWithRed:242/255.0 green:195/255.0 blue:80/255.0 alpha:1.0] : [UIColor secondaryLabelColor];
    self.favoriteButton.accessibilityLabel = favorite ? @"Unfavorite" : @"Favorite";
    self.favoriteButton.hidden = NO;
    self.deleteButton.hidden = !deletable;
    self.onFavorite = onFavorite;
    self.onDelete = onDelete;
    self.editing = YES;
    [self applyLook];
}

- (void)hideEditBadges {
    self.favoriteButton.hidden = YES;
    self.deleteButton.hidden = YES;
    self.onFavorite = nil;
    self.onDelete = nil;
    self.editing = NO;
    [self applyLook];
}

- (void)favoriteTapped {
    if (self.onFavorite) self.onFavorite();
}

- (void)deleteTapped {
    if (self.onDelete) self.onDelete();
}

// The tile's own buttons get their taps, not the tile
- (NSArray *)accessibilityCustomActions {
    if (!self.editing) return nil;
    NSMutableArray *actions = [NSMutableArray array];
    if (!self.favoriteButton.hidden) [actions addObject:[[UIAccessibilityCustomAction alloc] initWithName:self.favoriteButton.accessibilityLabel target:self selector:@selector(favoriteTapped)]];
    if (!self.deleteButton.hidden) [actions addObject:[[UIAccessibilityCustomAction alloc] initWithName:@"Delete" target:self selector:@selector(deleteTapped)]];
    return actions;
}

- (void)applyLook {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *tile = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    BOOL tint = self.checked && !self.plainChecked;
    self.contentView.backgroundColor = tint ? [[UIColor systemBlueColor] colorWithAlphaComponent:0.22] : tile;
    self.contentView.layer.borderWidth = tint ? 1.5 : 0;
    self.iconView.tintColor = tint ? [UIColor systemBlueColor] : self.dimmed ? [UIColor tertiaryLabelColor] : [UIColor labelColor];
    self.iconView.alpha = self.dimmed && !self.checked ? 0.6 : 1; // an app's own icon isn't tinted
    self.nameLabel.textColor = self.dimmed && !self.checked ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    self.countLabel.hidden = self.count <= 0 || self.editing;
    self.accessibilityValue = self.count > 0 ? [NSString stringWithFormat:@"%ld action%@", (long)self.count, self.count == 1 ? @"" : @"s"] : nil;
    if (self.editing) {
        self.badgeView.hidden = YES; // the edit buttons take the corners
    } else if (self.checked) {
        self.badgeView.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
        self.badgeView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightRegular];
        self.badgeView.tintColor = [UIColor systemBlueColor];
        self.badgeView.hidden = NO;
    } else if (self.opensMore) {
        self.badgeView.image = [UIImage systemImageNamed:@"chevron.right"];
        self.badgeView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightSemibold];
        self.badgeView.tintColor = [UIColor tertiaryLabelColor];
        self.badgeView.hidden = NO;
    } else {
        self.badgeView.hidden = YES;
    }
    if (self.checked) self.accessibilityValue = @"Checked";
    self.accessibilityHint = self.opensMore && !self.checked ? @"Asks for more" : nil;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.contentView.transform = highlighted ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity;
        self.contentView.alpha = highlighted ? 0.75 : 1;
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _opensMore = NO;
    _checked = NO;
    _plainChecked = NO;
    _dimmed = NO;
    _count = 0;
    self.countLabel.hidden = YES;
    self.favoriteButton.hidden = YES;
    self.deleteButton.hidden = YES;
    self.onFavorite = nil;
    self.onDelete = nil;
    self.editing = NO;
    self.contentView.transform = CGAffineTransformIdentity;
    self.contentView.alpha = 1;
    [self applyLook];
}

@end

@interface RCActionGridHeader ()
@property (nonatomic, strong, readwrite) UILabel *label;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) NSLayoutConstraint *labelLeading;
@end

@implementation RCActionGridHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _label = [[UILabel alloc] init];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.textColor = [UIColor secondaryLabelColor];
        [self addSubview:_label];
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.hidden = YES;
        [self addSubview:_iconView];
        _labelLeading = [_label.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:RCGridSide + 4];
        [NSLayoutConstraint activateConstraints:@[
            _labelLeading,
            [_iconView.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:RCGridSide + 4],
            [_iconView.centerYAnchor constraintEqualToAnchor:_label.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:18],
            [_iconView.heightAnchor constraintEqualToConstant:16],
            [_label.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-(RCGridSide + 4)],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
        ]];
    }
    return self;
}

- (void)setTitle:(NSString *)title icon:(UIImage *)icon {
    [self setTitle:title];
    self.iconView.image = icon;
    self.iconView.hidden = icon == nil;
    self.labelLeading.constant = RCGridSide + 4 + (icon ? 24 : 0);
}

- (void)setTitle:(NSString *)title {
    self.label.textColor = [UIColor secondaryLabelColor]; // a reused title may have been Favorites' yellow
    self.tintColor = [UIColor secondaryLabelColor];       // the icon's, set like the text's
    self.iconView.hidden = YES;
    self.labelLeading.constant = RCGridSide + 4;
    self.label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.label.numberOfLines = 1;
    self.label.text = title.uppercaseString;
    self.accessibilityTraits = UIAccessibilityTraitHeader;
}

- (void)setNote:(NSString *)note {
    self.iconView.hidden = YES;
    self.labelLeading.constant = RCGridSide + 4;
    self.label.textColor = [UIColor secondaryLabelColor];
    self.label.font = [UIFont systemFontOfSize:13];
    self.label.numberOfLines = 0;
    self.label.text = note;
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
}

@end

UICollectionViewFlowLayout *RCActionGridLayout(void) {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = RCGridSpacing;
    layout.minimumLineSpacing = RCGridSpacing;
    layout.sectionInset = UIEdgeInsetsMake(0, RCGridSide, 18, RCGridSide);
    layout.sectionInsetReference = UICollectionViewFlowLayoutSectionInsetFromSafeArea; // clear of the Dynamic Island in landscape
    return layout;
}

CGSize RCActionTileSize(CGFloat gridWidth) {
    CGFloat usable = MAX(0, gridWidth - 2 * RCGridSide);
    NSInteger columns = MAX(3, (NSInteger)floor((usable + RCGridSpacing) / (RCTileMinWidth + RCGridSpacing)));
    CGFloat width = floor((usable - RCGridSpacing * (columns - 1)) / columns);
    return CGSizeMake(width, 90);
}

CGFloat RCActionGridNoteHeight(NSString *note, CGFloat gridWidth) {
    if (!note.length) return 0;
    CGFloat width = MAX(0, gridWidth - 2 * (RCGridSide + 4));
    CGRect r = [note boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13] } context:nil];
    return ceil(r.size.height) + 14;
}

#pragma mark - List rows

@interface RCActionRowCell ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *accessoryImage;
@property (nonatomic, strong) UIView *separator;
@end

@implementation RCActionRowCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.clipsToBounds = YES;

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
        _iconView.tintColor = [UIColor secondaryLabelColor];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_iconView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:17];
        _nameLabel.textColor = [UIColor labelColor];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_nameLabel];

        _accessoryImage = [[UIImageView alloc] init];
        _accessoryImage.contentMode = UIViewContentModeCenter;
        _accessoryImage.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_accessoryImage];

        _separator = [[UIView alloc] init];
        _separator.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_separator];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:28],
            [_iconView.heightAnchor constraintEqualToConstant:28],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:14],
            [_nameLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_accessoryImage.leadingAnchor constant:-8],
            [_accessoryImage.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_accessoryImage.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_accessoryImage.widthAnchor constraintEqualToConstant:20],
            [_separator.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_separator.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_separator.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        ]];
        [self applyLook];
    }
    return self;
}

- (void)setName:(NSString *)name icon:(NSString *)icon image:(UIImage *)custom {
    self.nameLabel.text = name;
    self.accessibilityLabel = name;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    UIImage *image = custom ?: (icon.length ? [UIImage systemImageNamed:icon] : nil);
    self.iconView.image = image ?: [UIImage systemImageNamed:@"square.dashed"];
}

- (void)setOpensMore:(BOOL)opensMore {
    _opensMore = opensMore;
    [self applyLook];
}

- (void)setChecked:(BOOL)checked {
    _checked = checked;
    [self applyLook];
}

- (void)setFirst:(BOOL)first last:(BOOL)last {
    CACornerMask corners = 0;
    if (first) corners |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    if (last) corners |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    self.contentView.layer.maskedCorners = corners;
    self.contentView.layer.cornerRadius = corners ? 10 : 0;
    self.separator.hidden = last;
}

- (void)applyLook {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.contentView.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    self.separator.backgroundColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    if (self.checked) {
        self.accessoryImage.image = [UIImage systemImageNamed:@"checkmark"];
        self.accessoryImage.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
        self.accessoryImage.tintColor = [UIColor systemBlueColor];
    } else if (self.opensMore) {
        self.accessoryImage.image = [UIImage systemImageNamed:@"chevron.right"];
        self.accessoryImage.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        self.accessoryImage.tintColor = [UIColor tertiaryLabelColor];
    } else {
        self.accessoryImage.image = nil;
    }
    self.accessibilityValue = self.checked ? @"Checked" : nil;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.contentView.backgroundColor = highlighted ? [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15] : [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _opensMore = NO;
    _checked = NO;
    [self applyLook];
}

@end

CGFloat RCGridWidth(UIScrollView *view) {
    return MAX(0, view.bounds.size.width - view.safeAreaInsets.left - view.safeAreaInsets.right);
}

CGSize RCActionRowSize(CGFloat listWidth, CGFloat height) {
    return CGSizeMake(MAX(0, listWidth - 2 * RCGridSide), height);
}

#pragma mark - Layout settings (per screen)

NSString *const RCLayoutTriggers = @"triggers";
NSString *const RCLayoutActionPicker = @"actionPicker";
NSString *const RCLayoutBanners = @"banners";
NSString *const RCLayoutNewTrigger = @"newTrigger";
NSString *const RCLayoutIcons = @"icons";
NSString *const RCLayoutOptionCompact = @"compact";
NSString *const RCLayoutOptionPerRow = @"perRow";
NSString *const RCLayoutOptionSections = @"sections";
NSString *const RCLayoutOptionNames = @"names";
NSString *const RCLayoutOptionBarLines = @"barLines";
NSString *const RCLayoutOptionKey = @"option";
NSString *const RCLayoutChangedNotification = @"RCLayoutChangedNotification";

NSArray<NSArray<NSString *> *> *RCLayoutScreens(void) {
    return @[@[@"Triggers", RCLayoutTriggers], @[@"New Trigger", RCLayoutNewTrigger],
             @[@"Select Action", RCLayoutActionPicker], @[@"Banners", RCLayoutBanners], @[@"Icons", RCLayoutIcons]];
}

static BOOL RCLayoutIsTriggers(NSString *screen) { return !screen || [screen isEqualToString:RCLayoutTriggers]; }

static void RCLayoutPostChange(NSString *screen, NSString *option) {
    [[NSNotificationCenter defaultCenter] postNotificationName:RCLayoutChangedNotification object:screen ?: RCLayoutTriggers
                                                      userInfo:@{ RCLayoutOptionKey: option }];
}

// Where each is kept. Triggers keeps the keys its settings always had (before they were per screen),
// so nothing changes for it; the other screens' start out as they looked before.
static NSString *RCLayoutKey(NSString *screen, NSString *option) {
    BOOL triggers = RCLayoutIsTriggers(screen);
    if ([option isEqualToString:RCLayoutOptionCompact]) return [@"RCCompactLayout." stringByAppendingString:screen ?: RCLayoutTriggers];
    if ([option isEqualToString:RCLayoutOptionPerRow]) return triggers ? @"RCTriggerColumns" : [@"RCPerRow." stringByAppendingString:screen];
    if ([option isEqualToString:RCLayoutOptionSections]) return triggers ? @"RCCompactLayout.triggerSectionsHidden" : [@"RCSectionsHidden." stringByAppendingString:screen];
    if ([option isEqualToString:RCLayoutOptionNames]) return triggers ? @"RCCompactLayout.triggerTitlesHidden" : [@"RCNamesHidden." stringByAppendingString:screen];
    return triggers ? @"RCCategoryBarLines" : [@"RCCategoryBarLines." stringByAppendingString:screen];
}

BOOL RCLayoutIsCompact(NSString *screen) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:RCLayoutKey(screen, RCLayoutOptionCompact)];
}

void RCLayoutSetCompact(NSString *screen, BOOL compact) {
    [[NSUserDefaults standardUserDefaults] setBool:compact forKey:RCLayoutKey(screen, RCLayoutOptionCompact)];
    RCLayoutPostChange(screen, RCLayoutOptionCompact);
}

NSArray<NSNumber *> *RCLayoutPerRowChoices(NSString *screen) {
    if ([screen isEqualToString:RCLayoutIcons]) return @[@4, @5, @6];
    return RCLayoutIsTriggers(screen) ? @[@2, @3, @4] : @[@3, @4, @5];
}

NSInteger RCLayoutPerRow(NSString *screen) {
    NSArray<NSNumber *> *choices = RCLayoutPerRowChoices(screen);
    NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey:RCLayoutKey(screen, RCLayoutOptionPerRow)];
    if ([choices containsObject:@(count)]) return count;
    if (RCLayoutIsTriggers(screen)) return [[NSUserDefaults standardUserDefaults] boolForKey:@"RCCompactLayout.triggerColumns"] ? 3 : 2; // the earlier 2 / 3 switch
    if ([screen isEqualToString:RCLayoutIcons]) return 6; // icons alone fit six across
    return 4; // what the tile screens showed on a phone before
}

void RCLayoutSetPerRow(NSString *screen, NSInteger count) {
    NSArray<NSNumber *> *choices = RCLayoutPerRowChoices(screen);
    count = MAX(choices.firstObject.integerValue, MIN(choices.lastObject.integerValue, count));
    [[NSUserDefaults standardUserDefaults] setInteger:count forKey:RCLayoutKey(screen, RCLayoutOptionPerRow)];
    RCLayoutPostChange(screen, RCLayoutOptionPerRow);
}

BOOL RCLayoutSectionsHidden(NSString *screen) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:RCLayoutKey(screen, RCLayoutOptionSections)];
}

void RCLayoutSetSectionsHidden(NSString *screen, BOOL hidden) {
    [[NSUserDefaults standardUserDefaults] setBool:hidden forKey:RCLayoutKey(screen, RCLayoutOptionSections)];
    RCLayoutPostChange(screen, RCLayoutOptionSections);
}

BOOL RCLayoutNamesHidden(NSString *screen) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:RCLayoutKey(screen, RCLayoutOptionNames)];
    if (!value) return [screen isEqualToString:RCLayoutIcons]; // Icons begins with the symbols alone
    return [value boolValue];
}

void RCLayoutSetNamesHidden(NSString *screen, BOOL hidden) {
    [[NSUserDefaults standardUserDefaults] setBool:hidden forKey:RCLayoutKey(screen, RCLayoutOptionNames)];
    RCLayoutPostChange(screen, RCLayoutOptionNames);
}

NSInteger RCLayoutBarLines(NSString *screen) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger count = [defaults integerForKey:RCLayoutKey(screen, RCLayoutOptionBarLines)];
    if (count >= 1 && count <= 3) return count;
    if ([screen isEqualToString:RCLayoutIcons]) return 2; // its nine categories on two lines
    if (!RCLayoutIsTriggers(screen)) return RCLayoutBarLines(RCLayoutTriggers); // the one setting all screens had
    return [defaults boolForKey:@"RCCompactLayout.categoryBarTwoLines"] ? 2 : 1; // the earlier 1 / 2 switch
}

void RCLayoutSetBarLines(NSString *screen, NSInteger lines) {
    [[NSUserDefaults standardUserDefaults] setInteger:MAX(1, MIN(3, lines)) forKey:RCLayoutKey(screen, RCLayoutOptionBarLines)];
    RCLayoutPostChange(screen, RCLayoutOptionBarLines);
}

NSArray<NSArray<NSString *> *> *RCLayoutOptionRows(NSString *screen) {
    if ([screen isEqualToString:RCLayoutIcons]) {
        // Always a grid in one piece: no List, no headings
        return @[@[@"Per Row", RCLayoutOptionPerRow], @[@"Tile Names", RCLayoutOptionNames], @[@"Category Bar Lines", RCLayoutOptionBarLines]];
    }
    NSMutableArray *rows = [NSMutableArray arrayWithObject:@[@"Layout", RCLayoutOptionCompact]];
    if (RCLayoutIsCompact(screen)) {
        [rows addObject:@[@"Per Row", RCLayoutOptionPerRow]];
        [rows addObject:@[@"Section Headings", RCLayoutOptionSections]];
        [rows addObject:@[@"Tile Names", RCLayoutOptionNames]];
    }
    [rows addObject:@[@"Category Bar Lines", RCLayoutOptionBarLines]];
    return rows;
}

// The segmented control's target: it carries its screen and option
@interface RCLayoutSegmentTarget : NSObject
@property (nonatomic, copy) NSString *screen;
@property (nonatomic, copy) NSString *option;
- (void)changed:(UISegmentedControl *)control;
@end

@implementation RCLayoutSegmentTarget
- (void)changed:(UISegmentedControl *)control {
    NSInteger i = control.selectedSegmentIndex;
    if ([self.option isEqualToString:RCLayoutOptionPerRow]) RCLayoutSetPerRow(self.screen, RCLayoutPerRowChoices(self.screen)[i].integerValue);
    else if ([self.option isEqualToString:RCLayoutOptionBarLines]) RCLayoutSetBarLines(self.screen, i + 1);
    else if ([self.option isEqualToString:RCLayoutOptionSections]) RCLayoutSetSectionsHidden(self.screen, i == 1);
    else if ([self.option isEqualToString:RCLayoutOptionNames]) RCLayoutSetNamesHidden(self.screen, i == 1);
    else RCLayoutSetCompact(self.screen, i == 1);
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
@end

UITableViewCell *RCLayoutOptionCell(NSString *title, NSString *screen, NSString *option) {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = title;
    cell.textLabel.textColor = [UIColor labelColor];
    BOOL perRow = [option isEqualToString:RCLayoutOptionPerRow];
    BOOL lines = [option isEqualToString:RCLayoutOptionBarLines];
    BOOL showHide = [option isEqualToString:RCLayoutOptionSections] || [option isEqualToString:RCLayoutOptionNames];
    NSMutableArray *items = [NSMutableArray array];
    if (perRow) for (NSNumber *n in RCLayoutPerRowChoices(screen)) [items addObject:n.stringValue];
    else if (lines) [items addObjectsFromArray:@[@"1", @"2", @"3"]];
    else if (showHide) [items addObjectsFromArray:@[@"Show", @"Hide"]];
    else [items addObjectsFromArray:@[@"List", @"Compact"]];
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:items];
    if (perRow) control.selectedSegmentIndex = [RCLayoutPerRowChoices(screen) indexOfObject:@(RCLayoutPerRow(screen))];
    else if (lines) control.selectedSegmentIndex = RCLayoutBarLines(screen) - 1;
    else if ([option isEqualToString:RCLayoutOptionSections]) control.selectedSegmentIndex = RCLayoutSectionsHidden(screen) ? 1 : 0;
    else if ([option isEqualToString:RCLayoutOptionNames]) control.selectedSegmentIndex = RCLayoutNamesHidden(screen) ? 1 : 0;
    else control.selectedSegmentIndex = RCLayoutIsCompact(screen) ? 1 : 0;
    control.accessibilityLabel = title;
    if (perRow || lines) {
        // Short choices: together as wide as List / Compact, so the controls line up
        for (NSInteger i = 0; i < 3; i++) [control setWidth:48 forSegmentAtIndex:i];
    }
    RCLayoutSegmentTarget *target = [[RCLayoutSegmentTarget alloc] init];
    target.screen = screen;
    target.option = option;
    [control addTarget:target action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    // The control doesn't keep its target: the cell does
    static char RCLayoutTargetKey;
    objc_setAssociatedObject(control, &RCLayoutTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control sizeToFit];
    cell.accessoryView = control;
    return cell;
}

CGSize RCActionTileSizeForScreen(CGFloat gridWidth, NSString *screen) {
    NSInteger perRow = RCLayoutPerRow(screen);
    CGFloat usable = MAX(0, gridWidth - 2 * RCGridSide);
    // The narrowest a tile gets at this many per row on a phone; a wider screen fits more
    CGFloat minimum = perRow <= 3 ? 104 : perRow == 4 ? RCTileMinWidth : 62;
    NSInteger columns = MAX(perRow, (NSInteger)floor((usable + RCGridSpacing) / (minimum + RCGridSpacing)));
    CGFloat width = floor((usable - RCGridSpacing * (columns - 1)) / columns);
    return CGSizeMake(width, RCLayoutNamesHidden(screen) ? width : 90);
}

#pragma mark - App icons

@interface UIImage (RCAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

UIImage *RCAppIconImage(NSString *bundleId, CGFloat side) {
    if (!bundleId.length) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    NSString *key = [NSString stringWithFormat:@"%@@%.0f", bundleId, side];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    if (![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return nil;
    // Only installed apps: the system hands back a generic icon for the rest
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (proxyClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleId];
        if (proxy && [proxy respondsToSelector:@selector(isInstalled)] && ![[proxy valueForKey:@"isInstalled"] boolValue]) return nil;
#pragma clang diagnostic pop
    }
    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:2 scale:UIScreen.mainScreen.scale];
    if (!icon) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *rounded = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        CGRect rect = CGRectMake(0, 0, side, side);
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:side * 0.225] addClip];
        [icon drawInRect:rect];
    }];
    rounded = [rounded imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [cache setObject:rounded forKey:key];
    return rounded;
}

UIImage *RCAppTriggerIconImage(NSString *bundleId, CGFloat side, BOOL exit) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    NSString *key = [NSString stringWithFormat:@"%@@%.0f%@", bundleId, side, exit ? @"x" : @"v"];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    UIImage *icon = RCAppIconImage(bundleId, side);
    if (!icon) return nil;
    CGFloat badge = round(side * 0.44);
    UIImage *mark = [[UIImage systemImageNamed:exit ? @"xmark.circle.fill" : @"checkmark.circle.fill"
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:badge weight:UIImageSymbolWeightBold]]
                     imageWithTintColor:exit ? [UIColor systemRedColor] : [UIColor systemGreenColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *result = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [icon drawInRect:CGRectMake(0, 0, side, side)];
        CGRect circle = CGRectMake(side - badge, 0, badge, badge);
        [[UIColor whiteColor] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:circle] fill];
        // The symbol a little inside the white circle, so a white ring shows around it
        CGFloat inset = MAX(1.0, badge * 0.1);
        [mark drawInRect:CGRectInset(circle, inset, inset)];
    }];
    result = [result imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [cache setObject:result forKey:key];
    return result;
}
