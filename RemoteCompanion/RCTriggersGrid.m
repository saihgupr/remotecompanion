#import "RCTriggersGrid.h"
#import "RCActionTile.h"
#import "RCConfigManager.h"

// A trigger in Compact: a wide card, its icon beside its name (up to three lines). Dimmed when it
// has no actions yet. In Edit, a star (favorite) and a minus (delete) on its right.
@interface RCTriggerCardCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIStackView *editButtons;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, copy) void (^onFavorite)(void);
@property (nonatomic, copy) void (^onDelete)(void);
@property (nonatomic, assign) BOOL dimmed;
// The name runs to the card's edge, or (in Edit) to the star and minus
@property (nonatomic, strong) NSLayoutConstraint *nameToEdge;
@property (nonatomic, strong) NSLayoutConstraint *nameToButtons;
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

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _nameLabel.numberOfLines = 3;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.85;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_nameLabel];

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

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:34],
            [_iconView.heightAnchor constraintEqualToConstant:30],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:8],

            [_nameLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_nameLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:6],
            [_editButtons.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],
            [_editButtons.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
        // Hidden buttons still hold their place, so the name's end is switched with them
        _nameToEdge = [_nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10];
        _nameToButtons = [_nameLabel.trailingAnchor constraintEqualToAnchor:_editButtons.leadingAnchor constant:-2];
        _nameToEdge.active = YES;
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

- (void)setName:(NSString *)name image:(UIImage *)image {
    self.nameLabel.text = name;
    self.iconView.image = image ?: [UIImage systemImageNamed:@"hand.tap"];
    self.accessibilityLabel = name;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
}

- (void)setDimmed:(BOOL)dimmed {
    _dimmed = dimmed;
    [self applyLook];
}

- (void)applyLook {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.contentView.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    self.iconView.tintColor = self.dimmed ? [UIColor tertiaryLabelColor] : [UIColor labelColor];
    self.iconView.alpha = self.dimmed ? 0.6 : 1; // an app's own icon isn't tinted
    self.nameLabel.textColor = self.dimmed ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    self.accessibilityValue = self.dimmed ? @"No actions" : nil;
}

- (void)showEditFavorite:(BOOL)favorite deletable:(BOOL)deletable onFavorite:(void (^)(void))onFavorite onDelete:(void (^)(void))onDelete {
    [self.favoriteButton setImage:[UIImage systemImageNamed:favorite ? @"star.fill" : @"star"] forState:UIControlStateNormal];
    self.favoriteButton.tintColor = favorite ? [UIColor colorWithRed:242/255.0 green:195/255.0 blue:80/255.0 alpha:1.0] : [UIColor secondaryLabelColor];
    self.favoriteButton.accessibilityLabel = favorite ? @"Unfavorite" : @"Favorite";
    self.deleteButton.hidden = !deletable;
    self.editButtons.hidden = NO;
    self.nameToEdge.active = NO;
    self.nameToButtons.active = YES;
    self.onFavorite = onFavorite;
    self.onDelete = onDelete;
}

- (void)hideEdit {
    self.editButtons.hidden = YES;
    self.nameToButtons.active = NO;
    self.nameToEdge.active = YES;
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
    if (!self.deleteButton.hidden) [actions addObject:[[UIAccessibilityCustomAction alloc] initWithName:@"Delete" target:self selector:@selector(deleteTapped)]];
    return actions;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.contentView.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
        self.contentView.alpha = highlighted ? 0.75 : 1;
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.contentView.transform = CGAffineTransformIdentity;
    self.contentView.alpha = 1;
    [self hideEdit];
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
    NSString *key = [self keyAtIndexPath:indexPath];
    id<RCTriggersGridSource> source = self.source;
    [cell setName:[source gridNameForTrigger:key] image:[source gridImageForTrigger:key]];
    cell.dimmed = [source gridActionCountForTrigger:key] == 0;
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
    [header setTitle:[self.source gridTitleForSection:indexPath.section]];
    if ([self.source gridSectionIsFavorites:indexPath.section]) {
        header.label.textColor = [UIColor colorWithRed:242/255.0 green:195/255.0 blue:80/255.0 alpha:1.0];
    }
    return header;
}

#pragma mark - Layout

// Wide cards: two columns on a phone, more on a wider screen
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat usable = MAX(0, collectionView.bounds.size.width - 32);
    NSInteger columns = MAX(2, (NSInteger)floor((usable + 8) / (170 + 8)));
    return CGSizeMake(floor((usable - 8 * (columns - 1)) / columns), 64);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section {
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
