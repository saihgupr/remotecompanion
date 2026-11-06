#import "RCTriggersGrid.h"
#import "RCActionTile.h"
#import "RCConfigManager.h"
#import "RCTriggerIcons.h"

// A trigger in Compact: a wide card, its icon beside its name (up to three lines), or at 3 per row
// a tile, its icon above its name. Dimmed when it has no actions yet. In Edit, a star (favorite)
// and a minus (delete): on the card's right, or at the tile's top right.
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
@property (nonatomic, strong) NSLayoutConstraint *iconWidth;
@property (nonatomic, strong) NSLayoutConstraint *iconHeight;
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

- (void)setPerRow:(NSInteger)perRow {
    perRow = MAX(2, MIN(4, perRow));
    if (perRow == _perRow) return;
    [NSLayoutConstraint deactivateConstraints:[self constraintsForPerRow:_perRow]];
    _perRow = perRow;
    [NSLayoutConstraint activateConstraints:[self constraintsForPerRow:perRow]];
    BOOL mini = perRow >= 4;
    self.nameLabel.font = [UIFont systemFontOfSize:perRow == 2 ? 14 : perRow == 3 ? 12.5 : 11 weight:UIFontWeightMedium];
    self.nameLabel.textAlignment = mini ? NSTextAlignmentCenter : NSTextAlignmentNatural;
    self.detailLabel.font = [UIFont systemFontOfSize:perRow == 2 ? 11 : 10];
    // The star and minus: side by side, or one in each top corner, smaller there (with the icon)
    // so they clear the icon between them
    self.editButtons.distribution = mini ? UIStackViewDistributionEqualSpacing : UIStackViewDistributionFill;
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
    BOOL beside = self.perRow == 2;
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
    cell.perRow = RCLayoutTriggerColumnCount();
    NSString *key = [self keyAtIndexPath:indexPath];
    id<RCTriggersGridSource> source = self.source;
    [cell setName:[source gridNameForTrigger:key] detail:[source gridDetailForTrigger:key] image:[source gridImageForTrigger:key]];
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
    NSInteger perRow = RCLayoutTriggerColumnCount();
    CGFloat minimum = perRow == 2 ? 170 : perRow == 3 ? 104 : 76;
    CGFloat height = perRow == 2 ? 64 : perRow == 3 ? 92 : 84;
    NSInteger columns = MAX(perRow, (NSInteger)floor((usable + 8) / (minimum + 8)));
    return CGSizeMake(floor((usable - 8 * (columns - 1)) / columns), height);
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
