#import "RCActionTile.h"
#import "RCConfigManager.h"

static const CGFloat RCGridSide = 16;    // space at the grid's left and right
static const CGFloat RCGridSpacing = 8;  // space between tiles
static const CGFloat RCTileMinWidth = 80;

@interface RCActionTileCell ()
@property (nonatomic, strong, readwrite) UIImageView *iconView;
@property (nonatomic, strong, readwrite) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *badgeView;
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

- (void)applyLook {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *tile = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    self.contentView.backgroundColor = self.checked ? [[UIColor systemBlueColor] colorWithAlphaComponent:0.22] : tile;
    self.contentView.layer.borderWidth = self.checked ? 1.5 : 0;
    self.iconView.tintColor = self.checked ? [UIColor systemBlueColor] : [UIColor labelColor];
    self.nameLabel.textColor = [UIColor labelColor];
    if (self.checked) {
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
    self.accessibilityValue = self.checked ? @"Checked" : nil;
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
    self.label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.label.numberOfLines = 1;
    self.label.text = title.uppercaseString;
    self.accessibilityTraits = UIAccessibilityTraitHeader;
}

- (void)setNote:(NSString *)note {
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
