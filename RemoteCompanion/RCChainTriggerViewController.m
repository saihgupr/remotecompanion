#import "RCChainTriggerViewController.h"
#import <objc/message.h>
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCTriggersViewController.h"
#import "RCActionTile.h"
#import "RCCategoryBar.h"
#import "RCTriggerIcons.h"

typedef NS_ENUM(NSInteger, RCChainSection) { RCChainSectionName, RCChainSectionSteps, RCChainSectionExisting, RCChainSectionWithin, RCChainSectionCount };

static const double kRCChainWithinDefault = 2.0;
static const double kRCChainWithinMin = 0.5;
static const double kRCChainWithinMax = 10.0;

#pragma mark - Step picker

// The triggers that can be steps, grouped as on the Triggers screen, as a list or tiles with
// category chips and a search (Settings > Layout > Chain Trigger)
@interface RCChainStepPickerViewController : UICollectionViewController <UICollectionViewDelegateFlowLayout, UISearchResultsUpdating>
// Edit Steps: the chain's steps first, in their own section, as the same rows or tiles (tap one to
// take it out, touch and hold to move it); then the triggers, each tap adding one as the next step (a
// trigger can be more than one step, its numbers shown on it). Done hands the whole list back.
@property (nonatomic, copy) void (^onDone)(NSArray<NSString *> *steps);
@property (nonatomic, copy) NSArray<NSString *> *initialSteps;
@property (nonatomic, strong) NSMutableArray<NSString *> *picked;
@property (nonatomic, assign) BOOL movingStep;
@property (nonatomic, strong) NSArray<NSString *> *groupTitles;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *groups;
@property (nonatomic, strong) RCCategoryBar *categoryBar;
@property (nonatomic, copy) NSString *selectedGroup; // a chip's group, nil for All
@property (nonatomic, strong) NSArray<NSString *> *shownTitles;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *shownGroups;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *query; // normalized, empty for none
@end

@implementation RCChainStepPickerViewController

- (instancetype)init {
    return [super initWithCollectionViewLayout:RCActionGridLayout()];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (NSString *)groupForKey:(NSString *)key {
    NSArray *rules = @[ @[@"volume_", @"Volume Buttons"], @[@"power_", @"Power Button"], @[@"trigger_statusbar_", @"Status Bar"],
                        @[@"trigger_edge_", @"Edge Gestures"], @[@"trigger_bottombar_", @"Bottom Bar Gestures"],
                        @[@"trigger_bottom_", @"Bottom Bar Gestures"], @[@"trigger_home_", @"Home Button"], @[@"touchid_", @"Home Button"],
                        @[@"trigger_ringer_", @"Ringer Switch"], @[@"trigger_two_finger_", @"Multi-Finger Gestures"],
                        @[@"trigger_island_", @"Dynamic Island"], @[@"trigger_watch_", @"Apple Watch"],
                        @[@"nfc_", @"NFC Tags"], @[@"trigger_cc_button_", @"Control Center Buttons"] ];
    for (NSArray *rule in rules) if ([key hasPrefix:rule[0]]) return rule[1];
    return @"Motion Gestures"; // Shake
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Edit Steps";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.picked = [self.initialSteps mutableCopy] ?: [NSMutableArray array];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finish)];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(moveStep:)];
    hold.minimumPressDuration = 0.3;
    [self.collectionView addGestureRecognizer:hold];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.collectionView.backgroundColor = bg;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[RCActionTileCell class] forCellWithReuseIdentifier:@"Tile"];
    [self.collectionView registerClass:[RCActionRowCell class] forCellWithReuseIdentifier:@"Row"];
    [self.collectionView registerClass:[RCActionGridHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"Header"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutChanged:) name:RCLayoutChangedNotification object:nil];

    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    NSMutableArray<NSString *> *candidates = [[RCConfigManager builtInTriggerKeys] mutableCopy];
    // The Dynamic Island's triggers, on a phone with one (looked up by name: not every build has them)
    SEL islandKeys = NSSelectorFromString(@"dynamicIslandTriggerKeys"), hasIsland = NSSelectorFromString(@"hasDynamicIsland");
    if ([RCConfigManager respondsToSelector:islandKeys] && [RCConfigManager respondsToSelector:hasIsland] &&
        ((BOOL (*)(id, SEL))objc_msgSend)([RCConfigManager class], hasIsland)) {
        NSArray *island = ((id (*)(id, SEL))objc_msgSend)([RCConfigManager class], islandKeys);
        if ([island isKindOfClass:[NSArray class]]) [candidates addObjectsFromArray:island];
    }
    BOOL home = [RCConfigManager hasHomeButton];
    for (NSString *key in candidates) {
        if ([keys containsObject:key] || ![RCConfigManager canBeChainStep:key]) continue;
        BOOL homeKey = [key hasPrefix:@"trigger_home_"] || [key hasPrefix:@"touchid_"];
        if (homeKey && !home) continue; // the Home button's triggers only with one
        [keys addObject:key];
    }
    for (NSString *key in [[cm allConfiguredTriggerKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if (([key hasPrefix:@"nfc_"] || [key hasPrefix:@"trigger_cc_button_"]) && ![keys containsObject:key]) [keys addObject:key];
    }
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *byGroup = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *group = [RCChainStepPickerViewController groupForKey:key];
        if (!byGroup[group]) { byGroup[group] = [NSMutableArray array]; [titles addObject:group]; }
        [byGroup[group] addObject:key];
    }
    self.groupTitles = titles;
    NSMutableArray *groups = [NSMutableArray array];
    for (NSString *title in titles) [groups addObject:byGroup[title]];
    self.groups = groups;

    // Category chips over the list: a chip shows just its group
    self.categoryBar = [[RCCategoryBar alloc] initWithWidth:self.view.bounds.size.width screen:RCLayoutChainSteps];
    NSMutableArray *chipIcons = [NSMutableArray array];
    for (NSString *title in titles) [chipIcons addObject:RCTriggerCategoryIcon(title) ?: (id)[NSNull null]];
    [self.categoryBar setChipTitles:titles icons:chipIcons];
    self.categoryBar.selectedIndex = -1;
    self.categoryBar.backgroundColor = bg;
    __weak typeof(self) weakSelf = self;
    self.categoryBar.onSelect = ^(NSInteger index) {
        weakSelf.selectedGroup = (index >= 0 && index < (NSInteger)titles.count) ? titles[index] : nil;
        [weakSelf rebuild];
        [weakSelf.collectionView reloadData];
    };
    [self.categoryBar attachToScrollView:self.collectionView];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Triggers";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self rebuild];
}

// Letters and numbers only, lowercased, so "2 finger" finds "Two-Finger" spelled either way
+ (NSString *)normalizedText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) return @"";
    NSString *folded = [[text stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch locale:nil] lowercaseString];
    NSMutableString *letters = [NSMutableString stringWithCapacity:folded.length];
    NSCharacterSet *lettersAndNumbers = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < folded.length; i++) {
        unichar character = [folded characterAtIndex:i];
        if ([lettersAndNumbers characterIsMember:character]) [letters appendFormat:@"%C", character];
    }
    return letters;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [RCChainStepPickerViewController normalizedText:searchController.searchBar.text];
    if ([query isEqualToString:self.query ?: @""]) return;
    self.query = query;
    [self rebuild];
    [self.collectionView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.categoryBar layoutInScrollView:self.collectionView];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.categoryBar scrollViewDidScroll:scrollView];
}

- (BOOL)compact { return RCLayoutIsCompact(RCLayoutChainSteps); }

// What's shown: one chip's group, everything in groups, or (Compact, Section Headings: Hide) one
// grid; with a search, only the triggers whose name or group has it
- (void)rebuild {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSArray<NSString *> *> *groups = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.groupTitles.count; i++) {
        NSString *title = self.groupTitles[i];
        if (self.selectedGroup && ![title isEqualToString:self.selectedGroup]) continue;
        NSArray<NSString *> *keys = self.groups[i];
        if (self.query.length) {
            NSMutableArray *matches = [NSMutableArray array];
            for (NSString *key in keys) {
                NSString *text = [NSString stringWithFormat:@"%@ %@", [[RCConfigManager sharedManager] displayNameForTrigger:key], title];
                if ([[RCChainStepPickerViewController normalizedText:text] containsString:self.query]) [matches addObject:key];
            }
            keys = matches;
        }
        if (!keys.count) continue;
        [titles addObject:title];
        [groups addObject:keys];
    }
    if ([self compact] && RCLayoutSectionsHidden(RCLayoutChainSteps) && !self.selectedGroup) {
        NSMutableArray *all = [NSMutableArray array];
        for (NSArray *group in groups) [all addObjectsFromArray:group];
        self.shownTitles = all.count ? @[@""] : @[];
        self.shownGroups = all.count ? @[all] : @[];
    } else {
        self.shownTitles = titles;
        self.shownGroups = groups;
    }
}

- (void)layoutChanged:(NSNotification *)note {
    if (![note.object isEqual:RCLayoutChainSteps]) return;
    [self rebuild];
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
}

#pragma mark Sections: the steps, then the triggers

static const NSInteger kStepsSection = 0;

- (BOOL)stepsEmpty { return self.picked.count == 0; }

// The trigger an item stands for (a step, or one to add); nil for the empty steps' hint
- (NSString *)keyAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kStepsSection) return [self stepsEmpty] ? nil : self.picked[indexPath.item];
    return self.shownGroups[indexPath.section - 1][indexPath.item];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView { return 1 + self.shownGroups.count; }

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (section == kStepsSection) return [self stepsEmpty] ? 1 : self.picked.count; // or the hint
    return self.shownGroups[section - 1].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *key = [self keyAtIndexPath:indexPath];
    BOOL isStep = indexPath.section == kStepsSection;
    if (!key) {
        // No steps yet: a row saying where they come from
        RCActionRowCell *hint = [collectionView dequeueReusableCellWithReuseIdentifier:@"Row" forIndexPath:indexPath];
        [hint setName:@"Tap triggers below to add steps, in order." icon:nil image:nil];
        [hint setFirst:YES last:YES];
        [self showBadge:nil remove:NO on:hint];
        hint.alpha = 0.6;
        hint.accessibilityValue = nil;
        return hint;
    }
    NSString *name = [[RCConfigManager sharedManager] displayNameForTrigger:key];
    NSInteger count = [self collectionView:collectionView numberOfItemsInSection:indexPath.section];
    UICollectionViewCell *cell;
    if (![self compact]) {
        RCActionRowCell *row = [collectionView dequeueReusableCellWithReuseIdentifier:@"Row" forIndexPath:indexPath];
        [row setName:name icon:nil image:[RCTriggersViewController iconImageForTrigger:key size:22]];
        [row setFirst:indexPath.item == 0 last:indexPath.item == count - 1];
        cell = row;
    } else {
        RCActionTileCell *tile = [collectionView dequeueReusableCellWithReuseIdentifier:@"Tile" forIndexPath:indexPath];
        tile.iconOnly = RCLayoutNamesHidden(RCLayoutChainSteps);
        [tile setName:name icon:nil image:[RCTriggersViewController iconImageForTrigger:key size:tile.iconOnly ? 52 : 26]];
        cell = tile;
    }
    cell.alpha = 1;
    if (isStep) {
        // Its place in the chain, and a minus: a tap takes it out
        [self showBadge:[NSString stringWithFormat:@"%ld", (long)indexPath.item + 1] remove:YES on:cell];
        cell.accessibilityValue = [NSString stringWithFormat:@"Step %ld", (long)indexPath.item + 1];
        cell.accessibilityHint = @"Removes this step. Touch and hold to move it.";
    } else {
        NSMutableArray<NSString *> *numbers = [NSMutableArray array];
        for (NSUInteger i = 0; i < self.picked.count; i++) {
            if ([self.picked[i] isEqualToString:key]) [numbers addObject:[NSString stringWithFormat:@"%lu", (unsigned long)i + 1]];
        }
        NSArray *shown = numbers.count > 3 ? [[numbers subarrayWithRange:NSMakeRange(0, 3)] arrayByAddingObject:@"…"] : numbers;
        [self showBadge:numbers.count ? [shown componentsJoinedByString:@", "] : nil remove:NO on:cell];
        cell.accessibilityValue = numbers.count ? [NSString stringWithFormat:@"Step %@", [numbers componentsJoinedByString:@", "]] : nil;
        cell.accessibilityHint = @"Adds it as the next step";
    }
    return cell;
}

// A blue capsule with the step numbers ("2", or "1, 3" for a trigger that's two steps) at a tile's
// top right or a row's end, and for a step a red minus at the tile's top left or before the capsule
- (void)showBadge:(NSString *)text remove:(BOOL)remove on:(UICollectionViewCell *)cell {
    static const NSInteger kNumberTag = 0x5743, kRemoveTag = 0x5744;
    UILabel *badge = [cell.contentView viewWithTag:kNumberTag];
    UIImageView *minus = [cell.contentView viewWithTag:kRemoveTag];
    BOOL compact = [self compact];
    CGRect bounds = cell.contentView.bounds;
    CGFloat side = 22;
    CGFloat badgeLeft = bounds.size.width - 14;
    if (text.length) {
        if (!badge) {
            badge = [[UILabel alloc] init];
            badge.tag = kNumberTag;
            badge.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
            badge.textColor = [UIColor whiteColor];
            badge.textAlignment = NSTextAlignmentCenter;
            badge.backgroundColor = [UIColor systemBlueColor];
            badge.clipsToBounds = YES;
            badge.adjustsFontSizeToFitWidth = YES;
            badge.minimumScaleFactor = 0.7;
            [cell.contentView addSubview:badge];
        }
        badge.text = text;
        CGFloat width = MIN(MAX(side, ceil([text sizeWithAttributes:@{ NSFontAttributeName: badge.font }].width) + 12), bounds.size.width - 12);
        badge.frame = compact ? CGRectMake(bounds.size.width - width - 6, 6, width, side)
                              : CGRectMake(bounds.size.width - width - 14, (bounds.size.height - side) / 2, width, side);
        badge.autoresizingMask = compact ? UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin
                                         : UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        badge.layer.cornerRadius = side / 2;
        badgeLeft = badge.frame.origin.x;
        [cell.contentView bringSubviewToFront:badge];
    }
    badge.hidden = !text.length;
    if (remove) {
        if (!minus) {
            minus = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"minus.circle.fill"]];
            minus.tag = kRemoveTag;
            minus.tintColor = [UIColor systemRedColor];
            minus.contentMode = UIViewContentModeScaleAspectFit;
            [cell.contentView addSubview:minus];
        }
        minus.frame = compact ? CGRectMake(6, 6, side, side) : CGRectMake(badgeLeft - side - 8, (bounds.size.height - side) / 2, side, side);
        minus.autoresizingMask = compact ? UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin
                                         : UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [cell.contentView bringSubviewToFront:minus];
    }
    minus.hidden = !remove;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    RCActionGridHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"Header" forIndexPath:indexPath];
    if (indexPath.section == kStepsSection) {
        [header setTitle:@"Steps" icon:[UIImage systemImageNamed:@"link"]];
        return header;
    }
    NSString *title = self.shownTitles[indexPath.section - 1];
    [header setTitle:title icon:title.length ? RCTriggerCategoryIcon(title) : nil];
    return header;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    BOOL hint = indexPath.section == kStepsSection && [self stepsEmpty];
    return ([self compact] && !hint) ? RCActionTileSizeForScreen(RCGridWidth(collectionView), RCLayoutChainSteps) : RCActionRowSize(RCGridWidth(collectionView), 48);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return [self compact] ? ((UICollectionViewFlowLayout *)layout).minimumLineSpacing : 0; // a list's rows touch
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section {
    if (section == kStepsSection) return CGSizeMake(collectionView.bounds.size.width, 30);
    if (![self.shownTitles[section - 1] length]) return CGSizeMake(collectionView.bounds.size.width, 8); // one grid, no heading
    return CGSizeMake(collectionView.bounds.size.width, 38);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    NSString *key = [self keyAtIndexPath:indexPath];
    if (!key) return;
    if (indexPath.section == kStepsSection) {
        [self.picked removeObjectAtIndex:indexPath.item]; // a step tapped: out
    } else {
        [self.picked addObject:key]; // a trigger tapped: the next step, even one that's a step already
    }
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [self stepsChanged];
}

// The steps section and every trigger's numbers follow the steps
- (void)stepsChanged {
    [UIView performWithoutAnimation:^{
        [self.collectionView reloadData];
        [self.collectionView layoutIfNeeded];
    }];
}

#pragma mark Moving a step

- (BOOL)collectionView:(UICollectionView *)collectionView canMoveItemAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == kStepsSection && ![self stepsEmpty];
}

// A step moves among the steps only
- (NSIndexPath *)collectionView:(UICollectionView *)collectionView targetIndexPathForMoveOfItemFromOriginalIndexPath:(NSIndexPath *)original atCurrentIndexPath:(NSIndexPath *)current toProposedIndexPath:(NSIndexPath *)proposed API_AVAILABLE(ios(15.0)) {
    return [self stepsTargetFor:proposed current:current];
}

- (NSIndexPath *)collectionView:(UICollectionView *)collectionView targetIndexPathForMoveFromItemAtIndexPath:(NSIndexPath *)current toProposedIndexPath:(NSIndexPath *)proposed {
    return [self stepsTargetFor:proposed current:current];
}

- (NSIndexPath *)stepsTargetFor:(NSIndexPath *)proposed current:(NSIndexPath *)current {
    if (proposed.section != kStepsSection) {
        NSInteger last = (NSInteger)self.picked.count - 1;
        return [NSIndexPath indexPathForItem:proposed.section > kStepsSection ? last : 0 inSection:kStepsSection];
    }
    return proposed;
}

- (void)collectionView:(UICollectionView *)collectionView moveItemAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    if (from.section != kStepsSection || to.section != kStepsSection) return;
    NSString *key = self.picked[from.item];
    [self.picked removeObjectAtIndex:from.item];
    [self.picked insertObject:key atIndex:MIN((NSUInteger)to.item, self.picked.count)];
    dispatch_async(dispatch_get_main_queue(), ^{ [self stepsChanged]; }); // the numbers
}

- (void)moveStep:(UILongPressGestureRecognizer *)hold {
    UICollectionView *collectionView = self.collectionView;
    CGPoint point = [hold locationInView:collectionView];
    switch (hold.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath *path = [collectionView indexPathForItemAtPoint:point];
            if (!path || ![self collectionView:collectionView canMoveItemAtIndexPath:path]) return; // only a step moves
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
            self.movingStep = [collectionView beginInteractiveMovementForItemAtIndexPath:path];
            break;
        }
        case UIGestureRecognizerStateChanged:
            if (self.movingStep) [collectionView updateInteractiveMovementTargetPosition:point];
            break;
        case UIGestureRecognizerStateEnded:
            if (self.movingStep) [collectionView endInteractiveMovement];
            self.movingStep = NO;
            break;
        default:
            if (self.movingStep) [collectionView cancelInteractiveMovement];
            self.movingStep = NO;
            break;
    }
}

- (void)finish {
    NSArray *steps = [self.picked copy];
    void (^onDone)(NSArray<NSString *> *) = self.onDone;
    if (!onDone) return;
    if (!self.searchController.isActive) { onDone(steps); return; }
    // The search closes first: going back while it's open left its bar behind
    self.searchController.active = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ onDone(steps); });
}

@end

#pragma mark - The chain

@interface RCChainTriggerViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *triggerKey;
@property (nonatomic, strong) NSMutableArray<NSString *> *steps;
@property (nonatomic, assign) double within;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *alwaysRun; // per step: its own actions always run (else: if the chain doesn't complete)
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, copy) NSString *name;
@end

@implementation RCChainTriggerViewController

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _triggerKey = [triggerKey copy];
        NSDictionary *chain = [[RCConfigManager sharedManager] triggerDataForKey:triggerKey][@"chain"];
        NSArray *steps = [chain isKindOfClass:[NSDictionary class]] && [chain[@"steps"] isKindOfClass:[NSArray class]] ? chain[@"steps"] : @[];
        _steps = [steps mutableCopy];
        id within = [chain isKindOfClass:[NSDictionary class]] ? chain[@"within"] : nil;
        _within = [within respondsToSelector:@selector(doubleValue)] && [within doubleValue] > 0 ? [within doubleValue] : kRCChainWithinDefault;
        _name = triggerKey ? [[RCConfigManager sharedManager] customNameForTrigger:triggerKey] : nil;
        // stepActions: per step, "always" or "wait" (a single "always" was all the steps)
        id stepActions = [chain isKindOfClass:[NSDictionary class]] ? chain[@"stepActions"] : nil;
        _alwaysRun = [NSMutableArray array];
        for (NSUInteger i = 0; i < _steps.count; i++) {
            id value = [stepActions isKindOfClass:[NSArray class]] ? (i < [stepActions count] ? stepActions[i] : nil) : stepActions;
            [_alwaysRun addObject:@([[value description] isEqualToString:@"always"])];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.triggerKey ? @"Edit Chain" : @"New Chain";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.tableView.backgroundColor = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.triggerKey ? @"Save" : @"Add"
                                                                              style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.tableView.editing = YES; // the steps move and delete in place
    self.tableView.allowsSelectionDuringEditing = YES;
    [self updateSaveButton];
}

- (void)updateSaveButton {
    self.navigationItem.rightBarButtonItem.enabled = self.steps.count >= 2;
}

- (UITableViewCell *)styledCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.textColor = [UIColor labelColor];
    return cell;
}

- (NSString *)withinText {
    return [NSString stringWithFormat:@"%g s", self.within];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return RCChainSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RCChainSectionSteps) return self.steps.count + 1; // and Add Step
    if (section == RCChainSectionExisting) return self.steps.count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == RCChainSectionName) return @"Name";
    if (section == RCChainSectionSteps) return @"Steps";
    if (section == RCChainSectionExisting) return self.steps.count ? @"Existing Triggers" : nil;
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCChainSectionName) return @"Leave empty to name it after its steps.";
    if (section == RCChainSectionSteps) return @"The steps have to happen in this order, at least two of them.";
    if (section == RCChainSectionExisting) {
        return self.steps.count ? @"Enabled runs a step's own actions as usual. Disabled runs them only if the chain doesn't complete." : nil;
    }
    return @"How long each step may take after the one before. Too slow, and the chain starts over.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self styledCell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == RCChainSectionName) {
        UITextField *field = self.nameField ?: [[UITextField alloc] init];
        self.nameField = field;
        field.text = self.name;
        field.placeholder = [self defaultName] ?: @"Chained Trigger";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.returnKeyType = UIReturnKeyDone;
        field.delegate = self;
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [field addTarget:self action:@selector(nameChanged:) forControlEvents:UIControlEventEditingChanged];
        [cell.contentView addSubview:field];
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            [field.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
        return cell;
    }
    if (indexPath.section == RCChainSectionSteps) {
        if (indexPath.row == (NSInteger)self.steps.count) {
            cell.textLabel.text = @"Edit Steps";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }
        NSString *key = self.steps[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%ld. %@", (long)indexPath.row + 1, [[RCConfigManager sharedManager] displayNameForTrigger:key]];
        cell.textLabel.numberOfLines = 0;
        cell.imageView.image = [RCTriggersViewController iconImageForTrigger:key size:22];
        cell.imageView.tintColor = [UIColor labelColor];
        return cell;
    }
    if (indexPath.section == RCChainSectionExisting) {
        // A step's own trigger: Enabled runs its actions as usual, Disabled only if the chain doesn't complete
        NSString *key = self.steps[indexPath.row];
        UITableViewCell *row = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        row.backgroundColor = cell.backgroundColor;
        row.selectionStyle = UITableViewCellSelectionStyleNone;
        row.textLabel.text = [[RCConfigManager sharedManager] displayNameForTrigger:key];
        row.textLabel.textColor = [UIColor labelColor];
        row.textLabel.numberOfLines = 0;
        BOOL enabled = [self.alwaysRun[indexPath.row] boolValue];
        row.detailTextLabel.text = enabled ? @"Existing Trigger: Enabled" : @"Existing Trigger: Disabled";
        row.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        row.imageView.image = [RCTriggersViewController iconImageForTrigger:key size:22];
        row.imageView.tintColor = [UIColor labelColor];
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = enabled;
        toggle.tag = indexPath.row;
        toggle.accessibilityLabel = row.textLabel.text;
        [toggle addTarget:self action:@selector(existingToggled:) forControlEvents:UIControlEventValueChanged];
        row.accessoryView = toggle;
        row.editingAccessoryView = toggle;
        return row;
    }
    cell.textLabel.text = @"Within";
    cell.detailTextLabel.text = [self withinText];
    UIStepper *stepper = [[UIStepper alloc] init];
    stepper.minimumValue = kRCChainWithinMin;
    stepper.maximumValue = kRCChainWithinMax;
    stepper.stepValue = 0.5;
    stepper.value = self.within;
    [stepper addTarget:self action:@selector(withinChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = stepper;
    return cell;
}

- (void)existingToggled:(UISwitch *)toggle {
    NSInteger index = toggle.tag;
    if (index >= (NSInteger)self.alwaysRun.count) return;
    self.alwaysRun[index] = @(toggle.on);
    UITableViewCell *row = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:RCChainSectionExisting]];
    row.detailTextLabel.text = toggle.on ? @"Existing Trigger: Enabled" : @"Existing Trigger: Disabled";
}

- (void)nameChanged:(UITextField *)field {
    self.name = field.text;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)withinChanged:(UIStepper *)stepper {
    self.within = stepper.value;
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:RCChainSectionWithin]];
    cell.detailTextLabel.text = [self withinText];
    [cell setNeedsLayout];
}

// Steps move and delete; the name, Add Step and Within don't
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == RCChainSectionSteps;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != RCChainSectionSteps) return UITableViewCellEditingStyleNone;
    return indexPath.row == (NSInteger)self.steps.count ? UITableViewCellEditingStyleNone : UITableViewCellEditingStyleDelete; // Edit Steps: a plain row
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == RCChainSectionSteps && indexPath.row < (NSInteger)self.steps.count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    [self.steps removeObjectAtIndex:indexPath.row];
    [self.alwaysRun removeObjectAtIndex:indexPath.row];
    [self refreshSteps];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == RCChainSectionSteps && indexPath.row < (NSInteger)self.steps.count;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    if (to.section != RCChainSectionSteps) return from;
    if (to.row >= (NSInteger)self.steps.count) return [NSIndexPath indexPathForRow:self.steps.count - 1 inSection:RCChainSectionSteps];
    return to;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSString *key = self.steps[from.row];
    NSNumber *always = self.alwaysRun[from.row];
    [self.steps removeObjectAtIndex:from.row];
    [self.steps insertObject:key atIndex:to.row];
    [self.alwaysRun removeObjectAtIndex:from.row];
    [self.alwaysRun insertObject:always atIndex:to.row];
    dispatch_async(dispatch_get_main_queue(), ^{ [self refreshSteps]; }); // the step numbers
}

- (void)refreshSteps {
    NSMutableIndexSet *sections = [NSMutableIndexSet indexSetWithIndex:RCChainSectionSteps];
    [sections addIndex:RCChainSectionExisting];
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
    }];
    self.nameField.placeholder = [self defaultName] ?: @"Chained Trigger";
    [self updateSaveButton];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == RCChainSectionSteps && indexPath.row == (NSInteger)self.steps.count) [self addStep];
}

- (void)addStep {
    RCChainStepPickerViewController *picker = [[RCChainStepPickerViewController alloc] init];
    picker.initialSteps = self.steps;
    __weak typeof(self) weakSelf = self;
    picker.onDone = ^(NSArray<NSString *> *steps) {
        [weakSelf replaceStepsWith:steps];
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

// The steps from Edit Steps. Each keeps its Existing Trigger setting: a trigger's first time in the
// new list takes its first time's setting in the old one, its second its second, and so on.
- (void)replaceStepsWith:(NSArray<NSString *> *)steps {
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *settings = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < self.steps.count; i++) {
        if (!settings[self.steps[i]]) settings[self.steps[i]] = [NSMutableArray array];
        [settings[self.steps[i]] addObject:self.alwaysRun[i]];
    }
    NSMutableArray<NSNumber *> *alwaysRun = [NSMutableArray array];
    for (NSString *key in steps) {
        NSMutableArray<NSNumber *> *left = settings[key];
        [alwaysRun addObject:left.count ? left.firstObject : @NO];
        if (left.count) [left removeObjectAtIndex:0];
    }
    self.steps = [steps mutableCopy];
    self.alwaysRun = alwaysRun;
    [self refreshSteps];
}

#pragma mark Saving

// "Volume Up Hold, then Status Bar Double Tap"
- (NSString *)defaultName {
    if (!self.steps.count) return nil;
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *key in self.steps) [names addObject:[[RCConfigManager sharedManager] displayNameForTrigger:key]];
    return [names componentsJoinedByString:@", then "];
}

- (void)save {
    [self.view endEditing:YES];
    if (self.steps.count < 2) return;
    RCConfigManager *config = [RCConfigManager sharedManager];
    // The steps need nothing of their own: the tweak catches a chain's steps whether or not they
    // are in the Triggers list
    NSMutableDictionary *chain = [@{ @"steps": [self.steps copy], @"within": @(self.within) } mutableCopy];
    if ([self.alwaysRun containsObject:@YES]) {
        NSMutableArray *stepActions = [NSMutableArray array];
        for (NSNumber *always in self.alwaysRun) [stepActions addObject:always.boolValue ? @"always" : @"wait"];
        chain[@"stepActions"] = stepActions;
    }
    NSString *key = self.triggerKey;
    if (key) {
        NSMutableDictionary *data = [[config triggerDataForKey:key] mutableCopy] ?: [NSMutableDictionary dictionary];
        data[@"chain"] = chain;
        data[@"name"] = [self defaultName];
        [config updateTrigger:key withData:data];
        [config setCustomName:self.name forTrigger:key];
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    key = [NSString stringWithFormat:@"chain_%lld", (long long)([[NSDate date] timeIntervalSince1970] * 1000)];
    [config updateTrigger:key withData:@{ @"name": [self defaultName], @"enabled": @YES, @"actions": @[], @"chain": chain }];
    [config setCustomName:self.name forTrigger:key];
    // On to its actions, in place of this screen
    RCActionsViewController *actions = [[RCActionsViewController alloc] initWithTriggerKey:key];
    NSMutableArray *stack = [self.navigationController.viewControllers mutableCopy];
    [stack removeLastObject];
    [stack addObject:actions];
    [self.navigationController setViewControllers:stack animated:YES];
}

@end
