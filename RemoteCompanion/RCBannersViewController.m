#import "RCBannersViewController.h"
#import "RCActionPickerViewController.h"
#import "RCConfigManager.h"
#import "RCActionTile.h"
#import "RCAddOnCatalog.h"

// Lists the action picker's catalog; tapping an action adds/removes it from the
// config's "bannerActions". Each entry tells the tweak how to recognise the action:
//   id      - the catalog command (what this screen keys on)
//   title   - banner title (the action's name)
//   icon    - SF Symbol for the banner
//   toggle  - YES for toggles, which show their new state instead of just the name
//   match   - command patterns: ending in " ", ":" or "-" = prefix, otherwise exact
//   exclude - other catalog actions' longer patterns within this one's prefixes
//             (Open Camera "camera " must not catch Camera Shutter "camera shutter")
//
// Actions that show a banner of their own (Camera, Home Assistant, ...) are listed too,
// ticked unless switched off: their banners stay their own, and switching one off adds
// it to the config's "bannerOptOut", which the tweak checks before showing it.
@interface RCBannersViewController () <UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;      // the catalog, by category
// What the table shows: the checked actions first ("Enabled"), then the rest by category. Ticking
// or unticking an action moves it between "Enabled" and its category.
@property (nonatomic, strong) NSArray<NSString *> *displayTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *displaySections;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIds;
@property (nonatomic, strong) NSMutableSet<NSString *> *optedOutIds;
@end

// Catalog commands of the actions that show a banner of their own (the ids the tweak checks)
static NSSet<NSString *> *RCOwnBannerIds(void) {
    static NSSet *ids;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ids = [NSSet setWithArray:@[@"__CAMERA_PICKER__", @"__CAMERA_VIDEO_PICKER__", @"camera record",
                                    @"__HA_PICKER__", @"__KM_TRIGGER__", @"__MQTT_PUBLISH__", @"audiomix toggle",
                                    @"sneakycam photo", @"sneakycam video",
                                    @"queue album", @"queue artist", @"shuffle all songs", @"delete current song"]];
    });
    return ids;
}

// Actions whose banner is their own: the built-in ones, and add-on actions with a banner
static BOOL RCHasOwnBanner(NSString *command) {
    if ([RCOwnBannerIds() containsObject:command]) return YES;
    for (NSDictionary *item in [RCAddOnCatalog bannerItems]) if ([item[@"id"] isEqualToString:command]) return YES;
    return NO;
}

// The picker's catalog, minus entries that don't run an action of their own
static NSArray<NSArray<NSDictionary *> *> *RCBannerCatalog(NSArray<NSString *> **titlesOut) {
    NSSet *skip = [NSSet setWithArray:@[@"__IF_CONDITION__", @"__REPEAT__", @"__REPEAT_WHILE__", @"__EXIT_REPEAT__", @"__WAIT_UNTIL__", @"__SET_VARIABLE__", @"__DELAY__", @"__STOP_TRIGGER__", @"__TOAST__"]];
    RCActionPickerViewController *picker = [[RCActionPickerViewController alloc] init];
    NSArray *catalog = [picker catalogSections];
    NSArray *titles = [picker catalogSectionTitles];
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *sectionTitles = [NSMutableArray array];
    for (NSUInteger i = 0; i < catalog.count; i++) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *item in catalog[i]) {
            // An add-on's row is replaced by its actions, below
            if (![skip containsObject:item[@"command"]] && ![item[@"command"] hasPrefix:@"__ADDON__"]) [items addObject:item];
        }
        if (items.count) {
            [sections addObject:items];
            [sectionTitles addObject:i < titles.count ? titles[i] : @""];
        }
    }
    for (NSDictionary *addOn in [RCAddOnCatalog pickerSections]) {
        [sections addObject:addOn[@"actions"]];
        [sectionTitles addObject:addOn[@"title"]];
    }
    if (titlesOut) *titlesOut = sectionTitles;
    return sections;
}

@implementation RCBannersViewController

- (instancetype)init {
    return [super initWithCollectionViewLayout:RCActionGridLayout()];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Banners";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"settingsBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.view.backgroundColor = bg;
    self.collectionView.backgroundColor = bg;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[RCActionTileCell class] forCellWithReuseIdentifier:@"Tile"];
    [self.collectionView registerClass:[RCActionRowCell class] forCellWithReuseIdentifier:@"Row"];
    // List or Compact (Settings), followed while open
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutChanged:) name:RCLayoutChangedNotification object:nil];
    [self.collectionView registerClass:[RCActionGridHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"Header"];
    [self.collectionView registerClass:[RCActionGridHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:@"Footer"];

    NSArray *titles = nil;
    self.sections = RCBannerCatalog(&titles);
    self.sectionTitles = titles;

    self.selectedIds = [NSMutableSet set];
    for (NSDictionary *entry in cm.bannerActions) {
        if ([entry[@"id"] isKindOfClass:[NSString class]]) [self.selectedIds addObject:entry[@"id"]];
    }
    // ANC Off and Transparency Mode were their own entries before Noise Control took all three modes
    if ([self.selectedIds containsObject:@"anc off"] || [self.selectedIds containsObject:@"anc transparency"]) [self.selectedIds addObject:@"anc on"];
    self.optedOutIds = [NSMutableSet setWithArray:cm.bannerOptOut];
    [self buildDisplaySections];
}

// The checked actions in one section at the top, and each category without them (empty ones left out)
- (void)buildDisplaySections {
    NSMutableArray *enabled = [NSMutableArray array], *titles = [NSMutableArray array], *sections = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.sections.count; i++) {
        NSMutableArray *rest = [NSMutableArray array];
        for (NSDictionary *item in self.sections[i]) {
            if ([self isChecked:item[@"command"]]) [enabled addObject:item];
            else [rest addObject:item];
        }
        if (rest.count) {
            [titles addObject:i < self.sectionTitles.count ? self.sectionTitles[i] : @""];
            [sections addObject:rest];
        }
    }
    if (enabled.count) {
        [titles insertObject:@"Enabled" atIndex:0];
        [sections insertObject:enabled atIndex:0];
    }
    self.displayTitles = titles;
    self.displaySections = sections;
}

+ (NSUInteger)checkedCount {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSSet *selected = [NSSet setWithArray:[cm.bannerActions valueForKey:@"id"]];
    NSSet *optedOut = [NSSet setWithArray:cm.bannerOptOut];
    NSUInteger count = 0;
    for (NSArray *section in RCBannerCatalog(NULL)) {
        for (NSDictionary *item in section) {
            NSString *command = item[@"command"];
            BOOL own = RCHasOwnBanner(command);
            if (own ? ![optedOut containsObject:command] : [selected containsObject:command]) count++;
        }
    }
    return count;
}

- (BOOL)isChecked:(NSString *)command {
    if (RCHasOwnBanner(command)) return ![self.optedOutIds containsObject:command];
    return [self.selectedIds containsObject:command];
}

#pragma mark - Matching

// Placeholder commands open a picker; these are the commands they produce.
- (NSArray<NSString *> *)patternsForCommand:(NSString *)command isToggle:(BOOL *)isToggle {
    static NSDictionary *placeholders;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        placeholders = @{
            @"__SET_VOLUME__": @[@"set-vol "],
            @"__SET_RINGER_VOLUME__": @[@"ringer volume "],
            @"__SET_BRIGHTNESS__": @[@"brightness "],
            @"__CAMERA_PICKER__": @[@"camera ", @"open camera ", @"camera", @"open camera"],
            @"__CAMERA_VIDEO_PICKER__": @[@"camera video ", @"open camera video ", @"camera video", @"open camera video", @"camera 2x"],
            @"__BT_CONNECT__": @[@"bt connect ", @"bluetooth connect "],
            @"__BT_DISCONNECT__": @[@"bt disconnect ", @"bluetooth disconnect "],
            @"__AIRPLAY_CONNECT__": @[@"airplay connect "],
            @"__FOCUS__": @[@"focus on ", @"focus toggle ", @"focus off"],
            @"__OPEN_APP__": @[@"uiopen "],
            @"__KILL_APP__": @[@"kill "],
            @"__HA_PICKER__": @[@"ha "],
            @"__KM_TRIGGER__": @[@"km "],
            @"__MQTT_PUBLISH__": @[@"mqtt "],
            @"__SHORTCUT_PICKER__": @[@"shortcut:"],
            @"__LUA_SCRIPT__": @[@"lua ", @"lua_eval "],
            @"__SSH_COMMAND__": @[@"ssh-run "],
            @"__CUSTOM__": @[@"exec ", @"root ", @"sudo "]
        };
    });
    if (isToggle) *isToggle = NO;
    if (placeholders[command]) return placeholders[command];

    NSDictionary *info = [[RCConfigManager sharedManager] toggleInfoForCommand:command];
    if ([info[@"prefixes"] isKindOfClass:[NSArray class]] && [info[@"prefixes"] count]) {
        if (isToggle) *isToggle = YES;
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *p in info[@"prefixes"]) [out addObject:[p lowercaseString]];
        return out;
    }
    return @[[command lowercaseString]];
}

static BOOL RCBannerIsPrefixPattern(NSString *p) {
    if (p.length == 0) return NO;
    unichar last = [p characterAtIndex:p.length - 1];
    return last == ' ' || last == ':' || last == '-';
}

- (NSDictionary *)entryForItem:(NSDictionary *)item {
    NSString *command = item[@"command"];
    BOOL isToggle = NO;
    NSArray *patterns = [self patternsForCommand:command isToggle:&isToggle];

    // Longer patterns of other catalog actions that fall within this one's prefixes
    NSMutableOrderedSet *exclude = [NSMutableOrderedSet orderedSet];
    for (NSArray *section in self.sections) {
        for (NSDictionary *other in section) {
            if ([other[@"command"] isEqualToString:command]) continue;
            for (NSString *otherPattern in [self patternsForCommand:other[@"command"] isToggle:NULL]) {
                for (NSString *mine in patterns) {
                    if (RCBannerIsPrefixPattern(mine) && otherPattern.length > mine.length && [otherPattern hasPrefix:mine] && ![patterns containsObject:otherPattern]) {
                        [exclude addObject:otherPattern];
                    }
                }
            }
        }
    }

    NSString *title = item[@"name"];
    for (NSString *ellipsis in @[@"...", @"…"]) {
        if ([title hasSuffix:ellipsis]) title = [title substringToIndex:title.length - ellipsis.length];
    }
    return @{
        @"id": command,
        @"title": title,
        @"icon": item[@"icon"] ?: @"",
        @"toggle": @(isToggle),
        @"match": patterns,
        @"exclude": exclude.array
    };
}

- (void)saveSelection {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSArray *section in self.sections) {
        for (NSDictionary *item in section) {
            if (RCHasOwnBanner(item[@"command"])) continue; // own banners: bannerOptOut instead
            if ([self.selectedIds containsObject:item[@"command"]]) [entries addObject:[self entryForItem:item]];
        }
    }
    [RCConfigManager sharedManager].bannerActions = entries;
    [RCConfigManager sharedManager].bannerOptOut = self.optedOutIds.allObjects;
}

#pragma mark - Grid

static NSString *const RCBannersNote = @"Checked actions show a banner whenever a trigger runs them. Toggles show their new state; other actions show their name.";

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.displaySections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.displaySections[section].count;
}

- (BOOL)compact {
    return RCLayoutIsCompact(RCLayoutBanners);
}

- (void)layoutChanged:(NSNotification *)note {
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.displaySections[indexPath.section][indexPath.item];
    if (![self compact]) {
        // List: a row with a checkmark, in a rounded card per section
        RCActionRowCell *row = [collectionView dequeueReusableCellWithReuseIdentifier:@"Row" forIndexPath:indexPath];
        UIImage *rowImage = [item[@"image"] isKindOfClass:[UIImage class]] ? item[@"image"] : nil;
        [row setName:item[@"name"] icon:item[@"icon"] image:rowImage];
        row.checked = [self isChecked:item[@"command"]];
        [row setFirst:indexPath.item == 0 last:indexPath.item == (NSInteger)self.displaySections[indexPath.section].count - 1];
        return row;
    }
    RCActionTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Tile" forIndexPath:indexPath];
    [cell setName:item[@"name"] icon:item[@"icon"]];
    cell.checked = [self isChecked:item[@"command"]];
    return cell;
}

// A title over each section; the explanation under the first
- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    BOOL footer = [kind isEqualToString:UICollectionElementKindSectionFooter];
    RCActionGridHeader *view = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:footer ? @"Footer" : @"Header" forIndexPath:indexPath];
    if (footer) [view setNote:indexPath.section == 0 ? RCBannersNote : nil];
    else [view setTitle:self.displayTitles[indexPath.section]];
    return view;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [self compact] ? RCActionTileSize(RCGridWidth(collectionView)) : RCActionRowSize(RCGridWidth(collectionView), 48);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return [self compact] ? ((UICollectionViewFlowLayout *)layout).minimumLineSpacing : 0; // a list's rows touch
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section {
    return CGSizeMake(collectionView.bounds.size.width, section == 0 ? 34 : 38);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForFooterInSection:(NSInteger)section {
    CGFloat width = collectionView.bounds.size.width;
    return CGSizeMake(width, section == 0 ? RCActionGridNoteHeight(RCBannersNote, width) : 0);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)layout insetForSectionAtIndex:(NSInteger)section {
    UIEdgeInsets inset = layout.sectionInset;
    if (section == 0) inset.bottom = 4; // the note follows closely
    return inset;
}

// More or fewer columns after a rotation
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self.collectionView.collectionViewLayout invalidateLayout];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    NSString *command = self.displaySections[indexPath.section][indexPath.item][@"command"];
    NSMutableSet *set = RCHasOwnBanner(command) ? self.optedOutIds : self.selectedIds;
    NSArray *oldTitles = self.displayTitles;
    NSArray *oldSections = self.displaySections;
    if ([set containsObject:command]) [set removeObject:command];
    else [set addObject:command];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [self saveSelection];
    [self buildDisplaySections];
    [self animateFromTitles:oldTitles sections:oldSections];
}

// Moves the grid from the sections it shows to the current ones: the action that was ticked or
// unticked leaves one section and arrives in the other, and a section that has become empty (or
// has just got its first action, like "Enabled") goes or comes with it
- (void)animateFromTitles:(NSArray<NSString *> *)oldTitles sections:(NSArray<NSArray<NSDictionary *> *> *)oldSections {
    NSArray<NSString *> *newTitles = self.displayTitles;
    NSArray<NSArray<NSDictionary *> *> *newSections = self.displaySections;
    NSMutableIndexSet *deleteSections = [NSMutableIndexSet indexSet], *insertSections = [NSMutableIndexSet indexSet];
    NSMutableArray<NSIndexPath *> *deleteRows = [NSMutableArray array], *insertRows = [NSMutableArray array];

    for (NSUInteger i = 0; i < oldTitles.count; i++) {
        NSUInteger inNew = [newTitles indexOfObject:oldTitles[i]];
        if (inNew == NSNotFound) { [deleteSections addIndex:i]; continue; }
        NSSet *kept = [NSSet setWithArray:[newSections[inNew] valueForKey:@"command"]];
        for (NSUInteger row = 0; row < oldSections[i].count; row++) {
            if (![kept containsObject:oldSections[i][row][@"command"]]) [deleteRows addObject:[NSIndexPath indexPathForItem:(NSInteger)row inSection:(NSInteger)i]];
        }
    }
    for (NSUInteger i = 0; i < newTitles.count; i++) {
        NSUInteger inOld = [oldTitles indexOfObject:newTitles[i]];
        if (inOld == NSNotFound) { [insertSections addIndex:i]; continue; }
        NSSet *had = [NSSet setWithArray:[oldSections[inOld] valueForKey:@"command"]];
        for (NSUInteger row = 0; row < newSections[i].count; row++) {
            if (![had containsObject:newSections[i][row][@"command"]]) [insertRows addObject:[NSIndexPath indexPathForItem:(NSInteger)row inSection:(NSInteger)i]];
        }
    }
    [self.collectionView performBatchUpdates:^{
        [self.collectionView deleteSections:deleteSections];
        [self.collectionView insertSections:insertSections];
        [self.collectionView deleteItemsAtIndexPaths:deleteRows];
        [self.collectionView insertItemsAtIndexPaths:insertRows];
    } completion:^(BOOL finished) {
        // The first section carries the explanation, so its footer changes when the sections do
        [self.collectionView reloadData];
    }];
}

@end
