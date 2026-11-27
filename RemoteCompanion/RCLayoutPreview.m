#import "RCLayoutPreview.h"
#import "RCActionTile.h"
#import "RCCategoryBar.h"
#import "RCTriggersGrid.h"
#import "RCTriggerIcons.h"
#import "RCTriggersViewController.h"
#import "RCConfigManager.h"
#import "RCSymbolPickerViewController.h"

// The screens the preview can show, in the control's order (its keys are RCLayout's)
static NSArray<NSArray<NSString *> *> *RCPreviewScreens(void) {
    return RCLayoutScreens();
}

static const CGFloat RCPreviewScreenHeight = 250; // the small screen's height, in the page's points

// Sample triggers for Triggers: {key, actions}; the first two are favorites
static NSArray<NSDictionary *> *RCPreviewTriggers(void) {
    return @[
        @{ @"key": @"volume_up_hold", @"actions": @"Flashlight" },
        @{ @"key": @"power_double_tap", @"actions": @"Camera > Wait 1 s > Camera Shutter > Show Banner" },
        @{ @"key": @"volume_down_hold", @"actions": @"Play/Pause" },
        @{ @"key": @"volume_both_press", @"actions": @"Do Not Disturb" },
        @{ @"key": @"trigger_statusbar_left_tap", @"actions": @"Control Center" },
        @{ @"key": @"trigger_statusbar_center_hold", @"actions": @"Screenshot" },
        @{ @"key": @"trigger_statusbar_swipe_right", @"actions": @"Next Track" },
    ];
}

// The Triggers sections the samples fall in: {title, indexes into RCPreviewTriggers}
static NSArray<NSDictionary *> *RCPreviewTriggerSections(void) {
    return @[ @{ @"title": @"Favorites", @"items": @[@0, @1] },
              @{ @"title": @"Volume Buttons", @"items": @[@2, @3] },
              @{ @"title": @"Status Bar", @"items": @[@4, @5, @6] } ];
}

// Samples for the other screens: {title, items: [{name, icon}]}
static NSArray<NSDictionary *> *RCPreviewCatalog(NSString *screen) {
    if ([screen isEqualToString:RCLayoutChainSteps]) {
        return @[ @{ @"title": @"Volume Buttons", @"items": @[
                        @{ @"name": @"Volume Up Hold", @"icon": @"speaker.wave.3.fill" }, @{ @"name": @"Volume Down Hold", @"icon": @"speaker.wave.1.fill" },
                        @{ @"name": @"Volume Up + Down", @"icon": @"plusminus" } ] },
                  @{ @"title": @"Status Bar", @"items": @[
                        @{ @"name": @"Status Bar Double Tap", @"icon": @"hand.tap" }, @{ @"name": @"Status Bar Swipe Left", @"icon": @"arrow.left" },
                        @{ @"name": @"Status Bar Swipe Right", @"icon": @"arrow.right" }, @{ @"name": @"Status Bar Center Hold", @"icon": @"hand.point.up.left" } ] } ];
    }
    if ([screen isEqualToString:RCLayoutNewTrigger]) {
        return @[ @{ @"title": @"Buttons", @"items": @[
                        @{ @"name": @"Volume Buttons", @"icon": @"speaker.wave.2.fill" }, @{ @"name": @"Power Button", @"icon": @"power" },
                        @{ @"name": @"Ringer Switch", @"icon": @"bell.fill" } ] },
                  @{ @"title": @"Screen", @"items": @[
                        @{ @"name": @"Status Bar", @"icon": @"menubar.rectangle" }, @{ @"name": @"Edge Gestures", @"icon": @"arrow.left.and.right" },
                        @{ @"name": @"Bottom Bar", @"icon": @"house.fill" }, @{ @"name": @"Shake", @"icon": @"waveform.path.ecg" } ] } ];
    }
    return @[ @{ @"title": @"Media", @"items": @[
                    @{ @"name": @"Play/Pause", @"icon": @"playpause.fill" }, @{ @"name": @"Next Track", @"icon": @"forward.fill" },
                    @{ @"name": @"Previous Track", @"icon": @"backward.fill" } ] },
              @{ @"title": @"Device Controls", @"items": @[
                    @{ @"name": @"Flashlight", @"icon": @"flashlight.on.fill" }, @{ @"name": @"Do Not Disturb", @"icon": @"moon.fill" },
                    @{ @"name": @"Low Power Mode", @"icon": @"battery.25" }, @{ @"name": @"Screenshot", @"icon": @"camera.viewfinder" } ] } ];
}

#pragma mark - Triggers in Compact: the real grid with the samples

@interface RCPreviewGridSource : NSObject <RCTriggersGridSource>
@end

@implementation RCPreviewGridSource
- (BOOL)oneSection { return RCLayoutSectionsHidden(RCLayoutTriggers); }
- (NSInteger)gridSectionCount { return [self oneSection] ? 1 : RCPreviewTriggerSections().count; }
- (NSString *)gridTitleForSection:(NSInteger)section { return [self oneSection] ? @"" : RCPreviewTriggerSections()[section][@"title"]; }
- (NSArray<NSString *> *)gridKeysInSection:(NSInteger)section {
    NSMutableArray *keys = [NSMutableArray array];
    NSArray *sections = [self oneSection] ? RCPreviewTriggerSections() : @[RCPreviewTriggerSections()[section]];
    for (NSDictionary *s in sections) for (NSNumber *i in s[@"items"]) [keys addObject:RCPreviewTriggers()[i.integerValue][@"key"]];
    return keys;
}
- (BOOL)gridSectionIsFavorites:(NSInteger)section { return ![self oneSection] && section == 0; }
- (NSString *)gridNameForTrigger:(NSString *)key { return [[RCConfigManager sharedManager] defaultNameForTrigger:key] ?: key; }
- (NSString *)gridDetailForTrigger:(NSString *)key { return nil; }
- (NSString *)gridIconForTrigger:(NSString *)key { return [RCTriggersViewController iconNameForTrigger:key]; }
- (UIImage *)gridImageForTrigger:(NSString *)key { return [RCTriggersViewController iconImageForTrigger:key size:RCLayoutNamesHidden(RCLayoutTriggers) ? 52 : 26]; }
- (NSInteger)gridActionCountForTrigger:(NSString *)key { return 1; }
- (NSString *)gridOffIntegrationForTrigger:(NSString *)key { return nil; }
- (BOOL)gridTriggerIsFavorite:(NSString *)key { return NO; }
- (BOOL)gridCanDeleteTrigger:(NSString *)key { return NO; }
- (void)gridOpenTrigger:(NSString *)key {}
- (void)gridRunTrigger:(NSString *)key fromView:(UIView *)view {}
- (void)gridToggleFavorite:(NSString *)key {}
- (void)gridDeleteTrigger:(NSString *)key fromView:(UIView *)view {}
- (void)gridMoveFavoriteFrom:(NSInteger)from to:(NSInteger)to {}
- (void)gridDidScroll:(UIScrollView *)scrollView {}
@end

#pragma mark - The other screens: the real tiles and rows with the samples

@interface RCPreviewCatalogSource : NSObject <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSString *screen;
@end

@implementation RCPreviewCatalogSource
// Section Headings: Hide (Compact) puts the samples in one grid without a heading
- (BOOL)oneSection { return [self compact] && RCLayoutSectionsHidden(self.screen); }
- (NSArray *)sections {
    NSArray *sections = RCPreviewCatalog(self.screen);
    if (![self oneSection]) return sections;
    NSMutableArray *all = [NSMutableArray array];
    for (NSDictionary *section in sections) [all addObjectsFromArray:section[@"items"]];
    return @[ @{ @"title": @"", @"items": all } ];
}
- (BOOL)compact { return RCLayoutIsCompact(self.screen); }
- (BOOL)banners { return [self.screen isEqualToString:RCLayoutBanners]; }
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView { return [self sections].count; }
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [[self sections][section][@"items"] count];
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *items = [self sections][indexPath.section][@"items"];
    NSDictionary *item = items[indexPath.item];
    BOOL checked = [self banners] && indexPath.item % 2 == 0; // some banners ticked
    BOOL more = [self.screen isEqualToString:RCLayoutNewTrigger];
    if (![self compact]) {
        RCActionRowCell *row = [collectionView dequeueReusableCellWithReuseIdentifier:@"Row" forIndexPath:indexPath];
        [row setName:item[@"name"] icon:item[@"icon"] image:nil];
        row.checked = checked;
        row.opensMore = more;
        [row setFirst:indexPath.item == 0 last:indexPath.item == (NSInteger)items.count - 1];
        return row;
    }
    RCActionTileCell *tile = [collectionView dequeueReusableCellWithReuseIdentifier:@"Tile" forIndexPath:indexPath];
    tile.iconOnly = RCLayoutNamesHidden(self.screen);
    [tile setName:item[@"name"] icon:item[@"icon"]];
    tile.checked = checked;
    tile.plainChecked = [self banners];
    tile.opensMore = more;
    return tile;
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    RCActionGridHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"Header" forIndexPath:indexPath];
    NSString *title = [self sections][indexPath.section][@"title"];
    [header setTitle:title icon:title.length ? (RCActionCategoryIcon(title) ?: RCTriggerCategoryIcon(title)) : nil];
    return header;
}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [self compact] ? RCActionTileSizeForScreen(RCGridWidth(collectionView), self.screen) : RCActionRowSize(RCGridWidth(collectionView), 48);
}
- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return [self compact] ? ((UICollectionViewFlowLayout *)layout).minimumLineSpacing : 0;
}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section {
    if ([self oneSection]) return CGSizeMake(collectionView.bounds.size.width, 8);
    return CGSizeMake(collectionView.bounds.size.width, section == 0 ? 30 : 38);
}
@end

#pragma mark - Icons: the picker's own tiles with sample symbols

@interface RCPreviewIconSource : NSObject <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@end

@implementation RCPreviewIconSource
- (NSArray<NSString *> *)symbols {
    return @[@"bell.fill", @"checkmark.circle.fill", @"star.fill", @"heart.fill", @"bolt.fill", @"flame.fill",
             @"lightbulb.fill", @"lock.fill", @"house.fill", @"gearshape.fill", @"paperplane.fill", @"envelope.fill",
             @"play.fill", @"music.note", @"camera.fill", @"moon.fill", @"wifi", @"airplane"];
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return [self symbols].count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RCSymbolTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Icon" forIndexPath:indexPath];
    cell.iconOnly = RCLayoutNamesHidden(RCLayoutIcons);
    NSString *name = [self symbols][indexPath.item];
    cell.iconView.image = [UIImage systemImageNamed:name];
    cell.nameLabel.text = name;
    cell.chosen = indexPath.item == 0; // the current icon, as the picker marks it
    return cell;
}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return RCSymbolTileSize(collectionView.bounds.size.width);
}
@end

#pragma mark - Triggers in List: rows like the Triggers screen's

static UIView *RCPreviewTriggerList(CGFloat width) {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    BOOL wrap = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"];
    UIView *list = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 0)];
    CGFloat y = 0;
    for (NSDictionary *section in RCPreviewTriggerSections()) {
        NSString *title = section[@"title"];
        BOOL favorites = [title isEqualToString:@"Favorites"];
        UIColor *titleColor = favorites ? [UIColor colorWithRed:242/255.0 green:195/255.0 blue:80/255.0 alpha:1.0] : [UIColor secondaryLabelColor];
        y += y == 0 ? 8 : 18;
        UIImageView *icon = [[UIImageView alloc] initWithImage:RCTriggerCategoryIcon(title)];
        icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        icon.tintColor = titleColor;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.frame = CGRectMake(20, y + 1, 18, 18);
        [list addSubview:icon];
        UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(44, y, width - 64, 20)];
        header.text = title.uppercaseString;
        header.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        header.textColor = titleColor;
        [list addSubview:header];
        y += 26;

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
        card.layer.cornerRadius = 10;
        card.layer.masksToBounds = YES;
        [list addSubview:card];
        CGFloat cardY = 0, cardWidth = width - 32;
        NSArray *items = section[@"items"];
        for (NSUInteger i = 0; i < items.count; i++) {
            NSDictionary *trigger = RCPreviewTriggers()[[items[i] integerValue]];
            NSString *key = trigger[@"key"];
            CGFloat textWidth = cardWidth - 60 - 30;
            UILabel *name = [[UILabel alloc] init];
            name.text = [cm defaultNameForTrigger:key] ?: key;
            name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
            name.textColor = [UIColor labelColor];
            name.numberOfLines = wrap ? 0 : 1;
            UILabel *detail = [[UILabel alloc] init];
            detail.text = trigger[@"actions"];
            detail.font = [UIFont systemFontOfSize:12];
            detail.textColor = [UIColor secondaryLabelColor];
            detail.numberOfLines = wrap ? 0 : 1;
            CGFloat nameHeight = ceil([name sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
            CGFloat detailHeight = ceil([detail sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
            if (!wrap) { nameHeight = ceil(name.font.lineHeight); detailHeight = ceil(detail.font.lineHeight); }
            CGFloat rowHeight = MAX(64, nameHeight + detailHeight + 22);
            name.frame = CGRectMake(60, cardY + (rowHeight - nameHeight - detailHeight - 2) / 2, textWidth, nameHeight);
            detail.frame = CGRectMake(60, CGRectGetMaxY(name.frame) + 2, textWidth, detailHeight);
            UIImageView *image = [[UIImageView alloc] initWithImage:[RCTriggersViewController iconImageForTrigger:key size:22]];
            image.tintColor = [UIColor systemGrayColor];
            image.contentMode = UIViewContentModeCenter;
            image.frame = CGRectMake(14, cardY + (rowHeight - 32) / 2, 32, 32);
            UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
            chevron.tintColor = [UIColor tertiaryLabelColor];
            chevron.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
            [chevron sizeToFit];
            chevron.center = CGPointMake(cardWidth - 18, cardY + rowHeight / 2);
            for (UIView *v in @[image, name, detail, chevron]) [card addSubview:v];
            if (i + 1 < items.count) {
                UIView *line = [[UIView alloc] initWithFrame:CGRectMake(60, cardY + rowHeight - 0.5, cardWidth - 60, 0.5)];
                line.backgroundColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
                [card addSubview:line];
            }
            cardY += rowHeight;
        }
        card.frame = CGRectMake(16, y, cardWidth, cardY);
        y += cardY;
    }
    list.frame = CGRectMake(0, 0, width, y + 16);
    return list;
}

#pragma mark - The preview

@interface RCLayoutPreview ()
@property (nonatomic, strong) UIView *screenView;  // the small screen, clipped
@property (nonatomic, strong) UIView *canvas;      // a full-size screen inside it, scaled down
@property (nonatomic, strong) RCTriggersGrid *grid;
@property (nonatomic, strong) RCPreviewGridSource *gridSource;
@property (nonatomic, strong) RCPreviewCatalogSource *catalogSource;
@property (nonatomic, strong) RCPreviewIconSource *iconSource;
@property (nonatomic, copy) NSString *screen;
@end

@implementation RCLayoutPreview

// The width of the phone's screen, which the canvas is drawn at
static CGFloat RCPreviewCanvasWidth(void) {
    CGSize size = [UIScreen mainScreen].bounds.size;
    return MIN(size.width, size.height);
}

// The small screen keeps the phone's proportions across: as wide as the page allows, up to 60%
static CGFloat RCPreviewScale(CGFloat width) {
    return MIN(0.6, (width - 32) / RCPreviewCanvasWidth());
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    return 12 + RCPreviewScreenHeight + 4;
}

- (instancetype)initWithWidth:(CGFloat)width {
    self = [super initWithFrame:CGRectMake(0, 0, width, [RCLayoutPreview heightForWidth:width])];
    if (!self) return nil;
    _screen = RCLayoutTriggers;

    _screenView = [[UIView alloc] init];
    _screenView.layer.cornerRadius = 22;
    _screenView.layer.cornerCurve = kCACornerCurveContinuous;
    _screenView.layer.borderWidth = 1;
    _screenView.clipsToBounds = YES;
    _screenView.userInteractionEnabled = NO; // a picture, not a screen to use
    _screenView.isAccessibilityElement = YES;
    [self addSubview:_screenView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutChanged:) name:RCLayoutChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:@"RCWrapLongNamesSettingChanged" object:nil];
    [self rebuild];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat screenWidth = round(RCPreviewCanvasWidth() * RCPreviewScale(width));
    CGRect frame = CGRectMake(round((width - screenWidth) / 2), 12, screenWidth, RCPreviewScreenHeight);
    if (!CGRectEqualToRect(frame, self.screenView.frame)) {
        self.screenView.frame = frame;
        [self rebuild];
    }
}

- (void)showScreen:(NSString *)screen {
    if ([screen isEqualToString:self.screen]) return;
    self.screen = screen;
    [self crossfadeRebuild];
}

// The screen it shows follows each change to its settings
- (void)layoutChanged:(NSNotification *)note {
    if (![note.object isEqual:self.screen]) return;
    [self crossfadeRebuild];
}

// The new picture is built and laid out at once, with no animation (built inside one, its tiles,
// chips and text grew in from nothing and flew in from the corner); the old picture fades away
// over it
- (void)crossfadeRebuild {
    UIView *old = CGRectIsEmpty(self.screenView.bounds) ? nil : [self.screenView snapshotViewAfterScreenUpdates:NO];
    [UIView performWithoutAnimation:^{
        [self rebuild];
        [self.canvas layoutIfNeeded];
    }];
    if (!old) return;
    old.frame = self.screenView.bounds;
    [self.screenView addSubview:old];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        old.alpha = 0;
    } completion:^(__unused BOOL finished) {
        [old removeFromSuperview];
    }];
}

- (NSString *)screenName {
    for (NSArray *screen in RCPreviewScreens()) if ([screen[1] isEqualToString:self.screen]) return screen[0];
    return @"";
}

- (void)rebuild {
    if (CGRectIsEmpty(self.screenView.bounds)) return;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *background = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.screenView.backgroundColor = background;
    self.screenView.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    [self.canvas removeFromSuperview];
    self.grid = nil;

    CGFloat scale = self.screenView.bounds.size.width / RCPreviewCanvasWidth();
    CGFloat width = RCPreviewCanvasWidth();
    CGFloat height = self.screenView.bounds.size.height / scale;
    UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    canvas.backgroundColor = background;

    // The screen's title, as its navigation bar shows it
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 14, width - 40, 40)];
    BOOL triggers = [self.screen isEqualToString:RCLayoutTriggers];
    BOOL icons = [self.screen isEqualToString:RCLayoutIcons];
    title.text = triggers ? @"RemoteCompanion" : icons ? @"Icon" : [self screenName];
    title.font = [UIFont systemFontOfSize:triggers ? 30 : 17 weight:UIFontWeightBold];
    title.textAlignment = triggers ? NSTextAlignmentLeft : NSTextAlignmentCenter;
    title.textColor = [UIColor labelColor];
    [canvas addSubview:title];
    CGFloat y = CGRectGetMaxY(title.frame) + 6;

    // Its category bar, with as many lines as Category Bar Lines
    RCCategoryBar *bar = [[RCCategoryBar alloc] initWithWidth:width screen:self.screen];
    NSArray *chipTitles = triggers ? @[@"Favorites", @"Volume Buttons", @"Power Button", @"Status Bar", @"Edge Gestures", @"Apple Watch", @"Device State"]
                                   : [self.screen isEqualToString:RCLayoutNewTrigger] ? @[@"Buttons", @"Screen", @"Device State", @"Apple Watch", @"Connections", @"Apps"]
                                   : [self.screen isEqualToString:RCLayoutChainSteps] ? @[@"Volume Buttons", @"Power Button", @"Status Bar", @"Edge Gestures", @"Bottom Bar Gestures", @"Motion Gestures"]
                                   : icons ? @[@"Common", @"Media", @"Devices", @"Connectivity", @"Home", @"Weather & Time", @"Life", @"Symbols"]
                                   : @[@"Media", @"Sound", @"Capture", @"Device Controls", @"Connectivity", @"System"];
    NSMutableArray *chipIcons = [NSMutableArray array];
    for (NSString *chip in chipTitles) {
        UIImage *icon = icons ? RCSymbolCategoryIcon(chip) : (RCTriggerCategoryIcon(chip) ?: RCActionCategoryIcon(chip));
        [chipIcons addObject:icon ?: (id)[NSNull null]];
    }
    [bar setChipTitles:chipTitles icons:chipIcons];
    bar.frame = CGRectMake(0, y, width, [bar height]);
    [canvas addSubview:bar];
    y += [bar height];

    CGRect content = CGRectMake(0, y, width, height - y);
    if (triggers && !RCLayoutIsCompact(RCLayoutTriggers)) {
        UIView *list = RCPreviewTriggerList(width);
        list.frame = CGRectMake(0, y, width, list.frame.size.height);
        [canvas addSubview:list];
    } else if (icons) {
        self.iconSource = [[RCPreviewIconSource alloc] init];
        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.minimumInteritemSpacing = 8;
        layout.minimumLineSpacing = 8;
        layout.sectionInset = UIEdgeInsetsMake(8, 16, 24, 16);
        UICollectionView *collection = [[UICollectionView alloc] initWithFrame:content collectionViewLayout:layout];
        collection.backgroundColor = background;
        [collection registerClass:[RCSymbolTileCell class] forCellWithReuseIdentifier:@"Icon"];
        collection.dataSource = self.iconSource;
        collection.delegate = self.iconSource;
        [canvas addSubview:collection];
        [collection reloadData];
    } else if (triggers) {
        self.gridSource = [[RCPreviewGridSource alloc] init];
        self.grid = [[RCTriggersGrid alloc] initWithSource:self.gridSource];
        self.grid.collectionView.frame = content;
        self.grid.collectionView.backgroundColor = background;
        [canvas addSubview:self.grid.collectionView];
        [self.grid reload];
    } else {
        self.catalogSource = [[RCPreviewCatalogSource alloc] init];
        self.catalogSource.screen = self.screen;
        UICollectionView *collection = [[UICollectionView alloc] initWithFrame:content collectionViewLayout:RCActionGridLayout()];
        collection.backgroundColor = background;
        [collection registerClass:[RCActionTileCell class] forCellWithReuseIdentifier:@"Tile"];
        [collection registerClass:[RCActionRowCell class] forCellWithReuseIdentifier:@"Row"];
        [collection registerClass:[RCActionGridHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"Header"];
        collection.dataSource = self.catalogSource;
        collection.delegate = self.catalogSource;
        [canvas addSubview:collection];
        [collection reloadData];
    }

    canvas.layer.anchorPoint = CGPointZero;
    canvas.layer.position = CGPointZero;
    canvas.transform = CGAffineTransformMakeScale(scale, scale);
    [self.screenView addSubview:canvas];
    self.canvas = canvas;

    // Read out as what it shows
    NSString *name = [self screenName];
    NSString *how = RCLayoutIsCompact(self.screen) || icons ? [NSString stringWithFormat:@"%@%ld per row", icons ? @"" : @"Compact, ", (long)RCLayoutPerRow(self.screen)] : @"List";
    self.screenView.accessibilityLabel = [NSString stringWithFormat:@"Preview of %@: %@", name, how];
}

@end
