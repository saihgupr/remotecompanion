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
        _nameLabel.numberOfLines = 2;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.85;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_nameLabel];

        // The corner mark: a chevron (opens more) or a checkmark (checked)
        _badgeView = [[UIImageView alloc] init];
        _badgeView.contentMode = UIViewContentModeScaleAspectFit;
        _badgeView.translatesAutoresizingMaskIntoConstraints = NO;
        _badgeView.hidden = YES;
        [self.contentView addSubview:_badgeView];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
            [_iconView.widthAnchor constraintEqualToConstant:30],
            [_iconView.heightAnchor constraintEqualToConstant:28],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:5],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-5],
            [_nameLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:6],
            [_nameLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-6],
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

- (void)setOpensMore:(BOOL)opensMore {
    _opensMore = opensMore;
    [self applyLook];
}

- (void)setChecked:(BOOL)checked {
    _checked = checked;
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
    self.contentView.backgroundColor = self.checked ? [[UIColor systemBlueColor] colorWithAlphaComponent:0.22] : tile;
    self.contentView.layer.borderWidth = self.checked ? 1.5 : 0;
    self.iconView.tintColor = self.checked ? [UIColor systemBlueColor] : self.dimmed ? [UIColor tertiaryLabelColor] : [UIColor labelColor];
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
@end

@implementation RCActionGridHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _label = [[UILabel alloc] init];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.textColor = [UIColor secondaryLabelColor];
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:RCGridSide + 4],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-(RCGridSide + 4)],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
        ]];
    }
    return self;
}

- (void)setTitle:(NSString *)title {
    self.label.textColor = [UIColor secondaryLabelColor]; // a reused title may have been Favorites' yellow
    self.label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.label.numberOfLines = 1;
    self.label.text = title.uppercaseString;
    self.accessibilityTraits = UIAccessibilityTraitHeader;
}

- (void)setNote:(NSString *)note {
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

CGSize RCActionRowSize(CGFloat listWidth, CGFloat height) {
    return CGSizeMake(MAX(0, listWidth - 2 * RCGridSide), height);
}

#pragma mark - Layout setting

NSString *const RCLayoutTriggers = @"triggers";
NSString *const RCLayoutActionPicker = @"actionPicker";
NSString *const RCLayoutBanners = @"banners";
NSString *const RCLayoutChangedNotification = @"RCLayoutChangedNotification";

static NSString *RCLayoutDefaultsKey(NSString *screen) {
    return [@"RCCompactLayout." stringByAppendingString:screen ?: @""];
}

BOOL RCLayoutIsCompact(NSString *screen) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:RCLayoutDefaultsKey(screen)];
}

void RCLayoutSetCompact(NSString *screen, BOOL compact) {
    [[NSUserDefaults standardUserDefaults] setBool:compact forKey:RCLayoutDefaultsKey(screen)];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCLayoutChangedNotification object:screen];
}

NSArray<NSArray<NSString *> *> *RCLayoutScreens(void) {
    return @[@[@"Triggers", RCLayoutTriggers], @[@"Select Action", RCLayoutActionPicker], @[@"Banners", RCLayoutBanners]];
}

// The segmented control's target: it carries its screen's key
@interface RCLayoutSegmentTarget : NSObject
@property (nonatomic, copy) NSString *screen;
- (void)changed:(UISegmentedControl *)control;
@end

@implementation RCLayoutSegmentTarget
- (void)changed:(UISegmentedControl *)control {
    RCLayoutSetCompact(self.screen, control.selectedSegmentIndex == 1);
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
@end

UITableViewCell *RCLayoutSettingCell(NSString *title, NSString *screen) {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = title;
    cell.textLabel.textColor = [UIColor labelColor];
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[@"List", @"Compact"]];
    control.selectedSegmentIndex = RCLayoutIsCompact(screen) ? 1 : 0;
    control.accessibilityLabel = [title stringByAppendingString:@" Layout"];
    RCLayoutSegmentTarget *target = [[RCLayoutSegmentTarget alloc] init];
    target.screen = screen;
    [control addTarget:target action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    // The control doesn't keep its target: the cell does
    static char RCLayoutTargetKey;
    objc_setAssociatedObject(control, &RCLayoutTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control sizeToFit];
    cell.accessoryView = control;
    return cell;
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
