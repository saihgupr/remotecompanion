#import "RCSettingsPageViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"
#import "RCBannersViewController.h"
#import "RCActionTile.h"
#import "RCSliderCell.h"
#import "RCLayoutPreview.h"
#import "RCCategoryBar.h"
#import "RCRunningViewController.h"
#import "RCTestKitViewController.h"

UIImage *RCSettingsIconWithGlyph(UIImage *glyph, UIColor *color) {
    const CGFloat side = 29.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:6.5] fill];
        if (!glyph) return;
        UIImage *white = [glyph imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize size = white.size;
        CGFloat scale = MIN(1.0, MIN(19.0 / MAX(size.width, 1), 19.0 / MAX(size.height, 1)));
        size = CGSizeMake(size.width * scale, size.height * scale);
        [white drawInRect:CGRectMake((side - size.width) / 2.0, (side - size.height) / 2.0, size.width, size.height)];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

CGFloat RCSettingsRowHeight(UITableView *tableView, UITableViewCell *cell) {
    const CGFloat minimum = 50;
    NSString *title = cell.textLabel.text;
    if (!title.length) return minimum;
    // An inset grouped row: the table's side margins, 16 inside the card on the left, the icon
    // and its gap, then the value and the accessory on the right
    CGFloat side = MAX(16, tableView.layoutMargins.left);
    CGFloat width = tableView.bounds.size.width - 2 * side;
    CGFloat used = 16 + (cell.imageView.image ? cell.imageView.image.size.width + 16 : 0);
    if (cell.accessoryView) used += cell.accessoryView.bounds.size.width + 16;
    else if (cell.accessoryType != UITableViewCellAccessoryNone) used += 34;
    else used += 16;
    NSString *detail = cell.detailTextLabel.text;
    if (detail.length) {
        UIFont *detailFont = cell.detailTextLabel.font ?: [UIFont systemFontOfSize:17];
        used += ceil([detail sizeWithAttributes:@{ NSFontAttributeName: detailFont }].width) + 8;
    }
    CGFloat available = MAX(60, width - used);
    UIFont *font = cell.textLabel.font ?: [UIFont systemFontOfSize:17];
    CGFloat height = ceil([title boundingRectWithSize:CGSizeMake(available, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                          attributes:@{ NSFontAttributeName: font } context:nil].size.height);
    return MAX(minimum, height + 26);
}

UIImage *RCSettingsIcon(NSString *symbol, UIColor *color) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    UIImage *glyph = [UIImage systemImageNamed:symbol withConfiguration:config] ?: [UIImage systemImageNamed:@"gearshape.fill" withConfiguration:config];
    return RCSettingsIconWithGlyph(glyph, color);
}
#import <notify.h>

// A table whose buttons feel a touch at once: a scroll view holds a touch back for a moment to see
// whether it's a scroll, which made the sliders' held buttons (Default / Undo, the lock) and − / +
// take noticeably longer than their 0.6 s, most of all on older phones. A scroll that starts on one
// still scrolls: the button's touch is cancelled.
@interface RCSettingsTableView : UITableView
@end

@implementation RCSettingsTableView
// (a slider being dragged keeps its touch, so a little up-and-down doesn't scroll the page instead)
- (BOOL)touchesShouldCancelInContentView:(UIView *)view { return ![view isKindOfClass:[UISlider class]]; }
@end

@interface RCSettingsPageViewController ()
@property (nonatomic) RCSettingsPage page;
@property (nonatomic, strong) UITableView *tableView;
// Layout: the screen being set up (its bar of chips sits above the settings and picks the preview's screen)
@property (nonatomic, copy) NSString *layoutScreen;
@property (nonatomic, strong) RCCategoryBar *layoutScreenBar;
@property (nonatomic, assign) BOOL layoutScreenBarShown;
@end

// Row IDs: a fixed name for each row, "layout:<option>" for the Layout rows of the screen being set
// up, "timing:<n>" for the Button Timing rows by position, and "swipe:<config key>" for the Swipe
// Triggers values
static NSString *const RCRowBanners = @"banners";
static NSString *const RCRowWakeScreen = @"wakeScreen";
static NSString *const RCRowNFCScanning = @"nfcScanning";
static NSString *const RCRowNFCExperimental = @"nfcExperimental";
static NSString *const RCRowNFCScreenOff = @"nfcScreenOff";
static NSString *const RCRowWrapLongNames = @"wrapLongNames";
static NSString *const RCRowLogging = @"logging";
static NSString *const RCRowLockScrolling = @"lockScrolling";
static NSString *const RCRowAdjustOnScreen = @"adjustOnScreen";
static NSString *const RCRowRootHelper = @"rootHelper";
static NSString *const RCRowDeveloperMode = @"developerMode";
static NSString *const RCRowUnlockOutOfPocket = @"unlockOutOfPocket";
static NSString *const RCRowSavedPasscode = @"savedPasscode";
static NSString *const RCRowRunning = @"running";
static NSString *const RCRowTestKit = @"testKit";

@implementation RCSettingsPageViewController

+ (NSString *)titleForPage:(RCSettingsPage)page {
    switch (page) {
        case RCSettingsPageLayout: return @"Layout";
        case RCSettingsPageBanners: return @"Banners";
        case RCSettingsPageButtons: return @"Buttons";
        case RCSettingsPageSwipeTriggers: return @"Swipe Triggers";
        case RCSettingsPageNFC: return @"NFC";
        case RCSettingsPageDiagnostics: return @"Diagnostics";
        case RCSettingsPageSecurity: return @"Security";
        default: return @"";
    }
}

+ (NSString *)symbolForPage:(RCSettingsPage)page {
    switch (page) {
        case RCSettingsPageLayout: return @"square.grid.2x2.fill";
        case RCSettingsPageBanners: return @"bell.badge.fill";
        case RCSettingsPageButtons: return @"power";
        case RCSettingsPageSwipeTriggers: return @"hand.point.up.left.fill";
        case RCSettingsPageNFC: return @"wave.3.right";
        case RCSettingsPageDiagnostics: return @"stethoscope";
        case RCSettingsPageSecurity: return @"lock.fill";
        default: return @"gearshape";
    }
}

+ (UIColor *)colorForPage:(RCSettingsPage)page {
    switch (page) {
        case RCSettingsPageLayout: return [UIColor systemBlueColor];
        case RCSettingsPageBanners: return [UIColor systemRedColor];
        case RCSettingsPageButtons: return [UIColor systemOrangeColor];
        case RCSettingsPageSwipeTriggers: return [UIColor systemPurpleColor];
        case RCSettingsPageNFC: return [UIColor systemGreenColor];
        case RCSettingsPageSecurity: return [UIColor systemIndigoColor];
        default: return [UIColor systemGrayColor];
    }
}

+ (UIViewController *)viewControllerForPage:(RCSettingsPage)page highlightRowID:(NSString *)rowID {
    if (page == RCSettingsPageBanners) return [[RCBannersViewController alloc] init];
    RCSettingsPageViewController *vc = [[RCSettingsPageViewController alloc] initWithPage:page];
    vc.highlightRowID = rowID;
    return vc;
}

- (instancetype)initWithPage:(RCSettingsPage)page {
    if ((self = [super init])) _page = page;
    return self;
}

#pragma mark - Sections and rows

// The page's sections: {title, rows, footer (optional)}
- (NSArray<NSDictionary *> *)sections {
    NSMutableArray *rows;
    switch (self.page) {
        case RCSettingsPageLayout:
            rows = [NSMutableArray array];
            for (NSArray *option in RCLayoutOptionRows([self currentLayoutScreen])) [rows addObject:[@"layout:" stringByAppendingString:option[1]]];
            return @[
                @{ @"title": @"Screen", @"rows": rows,
                   @"footer": @"Each screen is set up on its own. Compact shows a grid of tiles instead of a list; hiding the tile names makes the icons larger." },
                @{ @"title": @"Names", @"rows": @[RCRowWrapLongNames] },
            ];
        case RCSettingsPageBanners:
            // Only for search: the page opens as the Banners list, with Wake Screen above it
            return @[ @{ @"title": @"Banners", @"rows": @[RCRowWakeScreen],
                         @"footer": @"Actions that show a banner when a trigger runs them. A banner that comes while the screen is off waits until it turns on, unless Wake Screen is on." } ];
        case RCSettingsPageButtons:
            rows = [NSMutableArray array];
            for (NSUInteger i = 0; i < [self timingRows].count; i++) [rows addObject:[NSString stringWithFormat:@"timing:%lu", (unsigned long)i]];
            return @[ @{ @"title": @"Timing", @"rows": rows,
                         @"footer": @"How long a press waits for the next one before it counts. A shorter time responds sooner and needs quicker presses." } ];
        case RCSettingsPageSwipeTriggers: {
            NSMutableArray *zones = [NSMutableArray array], *distances = [NSMutableArray array];
            for (NSDictionary *row in [self swipeRows]) {
                NSString *rowID = [@"swipe:" stringByAppendingString:row[@"key"]];
                [([row[@"key"] hasSuffix:@"Distance"] ? distances : zones) addObject:rowID];
            }
            return @[
                @{ @"title": @"On Screen", @"rows": @[RCRowAdjustOnScreen],
                   @"footer": @"Shows every zone and distance at its real size over any app, with a handle to drag for each." },
                @{ @"title": @"Zones", @"rows": zones,
                   @"footer": @"Where a status bar, edge or bottom swipe has to start. Smaller zones leave more room for the Home swipe and other gestures." },
                @{ @"title": @"Distances", @"rows": distances,
                   @"footer": @"How far a swipe goes before its trigger runs. Longer distances leave more room for other gestures." },
                @{ @"title": @"While Swiping", @"rows": @[RCRowLockScrolling] },
            ];
        }
        case RCSettingsPageNFC: {
            NSString *footer = @"NFC scanning options.";
            if (![RCConfigManager nfcBackgroundReadingSupported]) footer = @"Experimental NFC requires iPhone XS or later.";
            else if ([RCConfigManager sharedManager].nfcBackgroundReading) {
                footer = @"Enabling Experimental NFC gives control of the NFC sensor back to iOS. This is so that express cards, tags, and passes still work as intended. iOS has an internal NFC cooldown of about 3 seconds. For cards and keys to work while the phone is locked, keep NFC With Screen Off set to Off.";
            }
            return @[ @{ @"title": @"NFC", @"rows": @[RCRowNFCScanning, RCRowNFCExperimental, RCRowNFCScreenOff], @"footer": footer } ];
        }
        case RCSettingsPageDiagnostics:
            return @[
                @{ @"title": @"Logging", @"rows": @[RCRowLogging],
                   @"footer": @"Minimal records triggers, their actions and conditions, and errors. Full records every step, for tracking down a problem." },
                @{ @"title": @"Developer", @"rows": @[RCRowDeveloperMode],
                   @"footer": @"Unlocks developer actions in the action picker, such as annotating a screenshot and sending it to your editor." },
                @{ @"title": @"This Device", @"rows": @[RCRowRunning, RCRowTestKit],
                   @"footer": @"Activity shows the triggers running now, with Stop, and the runs before them, action by action. Test Kit runs tests on this device and shares their results." },
            ];
        case RCSettingsPageSecurity:
            return @[
                @{ @"title": @"Unlocking", @"rows": @[RCRowSavedPasscode, RCRowUnlockOutOfPocket],
                   @"footer": @"Unlock Device and Lock Toggle enter the saved passcode. It is kept in the Keychain on this iPhone only. Only Unlock Out of Pocket skips unlocking while the proximity sensor is covered, such as in a pocket." },
                @{ @"title": @"Root Helper", @"rows": @[RCRowRootHelper],
                   @"footer": @"Lets scripts, terminals and other tools call the root helper directly. Any app on this device can then get root, so leave it off unless you need it." },
            ];
        default:
            return @[];
    }
}

- (NSString *)rowIDAtIndexPath:(NSIndexPath *)indexPath {
    return [self sections][indexPath.section][@"rows"][indexPath.row];
}

- (NSInteger)indexFromRowID:(NSString *)rowID prefix:(NSString *)prefix {
    return [[rowID substringFromIndex:prefix.length] integerValue];
}

- (NSDictionary *)swipeRowForRowID:(NSString *)rowID {
    NSString *key = [rowID substringFromIndex:@"swipe:".length];
    for (NSDictionary *row in [self swipeRows]) if ([row[@"key"] isEqualToString:key]) return row;
    return nil;
}

- (NSString *)titleForRowID:(NSString *)rowID {
    if ([rowID hasPrefix:@"layout:"]) {
        NSString *option = [rowID substringFromIndex:@"layout:".length];
        for (NSArray *row in RCLayoutOptionRows([self currentLayoutScreen])) if ([row[1] isEqualToString:option]) return row[0];
        return @"";
    }
    if ([rowID hasPrefix:@"timing:"]) return [self timingRows][[self indexFromRowID:rowID prefix:@"timing:"]][@"title"];
    if ([rowID hasPrefix:@"swipe:"]) return [self swipeRowForRowID:rowID][@"title"];
    NSDictionary *titles = @{ RCRowBanners: @"Banners", RCRowWakeScreen: @"Wake Screen", RCRowNFCScanning: @"NFC Scanning",
                              RCRowNFCExperimental: @"Experimental NFC", RCRowNFCScreenOff: @"NFC With Screen Off",
                              RCRowWrapLongNames: @"Wrap Long Names", RCRowLogging: @"Logging",
                              RCRowLockScrolling: @"Lock Scrolling During Gestures", RCRowAdjustOnScreen: @"Adjust on Screen",
                              RCRowRootHelper: @"Allow Direct Root Helper Calls", RCRowDeveloperMode: @"Developer Mode",
                              RCRowUnlockOutOfPocket: @"Only Unlock Out of Pocket", RCRowSavedPasscode: @"Saved Passcode",
                              RCRowRunning: @"Activity", RCRowTestKit: @"Test Kit" };
    return titles[rowID] ?: rowID;
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)searchEntries {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSDictionary *section in [self sections]) {
        for (NSString *rowID in section[@"rows"]) [entries addObject:@{ @"title": [self titleForRowID:rowID], @"rowID": rowID }];
    }
    return entries;
}

#pragma mark - View

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [RCSettingsPageViewController titleForPage:self.page];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.tableView = [[RCSettingsTableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delaysContentTouches = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 50;
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 0;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTweaksChanged:) name:@"RCConfigTweaksChangedNotification" object:nil];
    // Adjust on Screen saves from SpringBoard: the Swipe Triggers rows follow
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(configChanged:) name:RCConfigChangedNotification object:nil];
    if (self.page == RCSettingsPageLayout) {
        // A small copy of the screen being set up, above the settings
        CGFloat width = self.view.bounds.size.width;
        RCLayoutPreview *preview = [[RCLayoutPreview alloc] initWithWidth:width];
        [preview showScreen:[self currentLayoutScreen]];
        self.tableView.tableHeaderView = preview;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutSettingChanged:) name:RCLayoutChangedNotification object:nil];
    }
    [self applyTweaks];
}

// The preview follows the page's width (rotation, split screen)
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    if (![header isKindOfClass:[RCLayoutPreview class]]) return;
    CGFloat width = self.tableView.bounds.size.width;
    if (fabs(header.frame.size.width - width) < 0.5) return;
    header.frame = CGRectMake(0, 0, width, [RCLayoutPreview heightForWidth:width]);
    self.tableView.tableHeaderView = header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    if (self.page == RCSettingsPageSecurity) {
        // Whether a passcode is saved: the tweak's Keychain item, asked each time the page shows
        [RCConfigManager checkUnlockPasscodeSaved:^(BOOL saved) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self.tableView reloadData]; });
        }];
    }
}

// A search result: scroll to its row and flash it
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSString *rowID = self.highlightRowID;
    if (!rowID) return;
    self.highlightRowID = nil;
    NSArray *sections = [self sections];
    for (NSUInteger s = 0; s < sections.count; s++) {
        NSUInteger r = [sections[s][@"rows"] indexOfObject:rowID];
        if (r == NSNotFound) continue;
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:r inSection:s];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        });
        return;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleTweaksChanged:(NSNotification *)note {
    [self applyTweaks];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;
    self.tableView.backgroundColor = settingsBG;
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    [self.tableView reloadData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) [self applyTweaks];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[self sections].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.page == RCSettingsPageLayout && section == 0) return [self layoutScreenHeaderWithWidth:tableView.bounds.size.width];
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, tableView.bounds.size.width - 40, 20)];
    label.text = [[self sections][section][@"title"] uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (self.page == RCSettingsPageLayout && section == 0) return 8.0f + [RCCategoryBar barHeight];
    return 40.0f;
}

#pragma mark - Layout: the screen being set up

// The screens' keys, in the control's order
static NSArray<NSString *> *RCLayoutScreenKeys(void) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSArray *screen in RCLayoutScreens()) [keys addObject:screen[1]];
    return keys;
}

- (NSString *)currentLayoutScreen {
    if (!self.layoutScreen) {
        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"RCLayoutPageScreen"];
        self.layoutScreen = [RCLayoutScreenKeys() containsObject:saved] ? saved : RCLayoutTriggers;
    }
    return self.layoutScreen;
}

// The screens, as a row of chips just above that screen's settings: it scrolls sideways when
// there are more than fit, so more screens can be added
- (UIView *)layoutScreenHeaderWithWidth:(CGFloat)width {
    RCCategoryBar *bar = self.layoutScreenBar;
    if (!bar) {
        bar = [[RCCategoryBar alloc] initWithWidth:width];
        bar.picker = YES;
        bar.accessibilityLabel = @"Screen";
        NSMutableArray *titles = [NSMutableArray array];
        for (NSArray *screen in RCLayoutScreens()) [titles addObject:screen[0]];
        [bar setChipTitles:titles];
        __weak typeof(self) weakSelf = self;
        bar.onSelect = ^(NSInteger index) { [weakSelf layoutScreenPicked:index]; };
        self.layoutScreenBar = bar;
    }
    bar.selectedIndex = (NSInteger)[RCLayoutScreenKeys() indexOfObject:[self currentLayoutScreen]];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 8.0 + [RCCategoryBar barHeight])];
    bar.frame = CGRectMake(0, 4, width, [RCCategoryBar barHeight]);
    [header addSubview:bar];
    // The screen set up last time, in view
    if (!self.layoutScreenBarShown) {
        self.layoutScreenBarShown = YES;
        NSInteger index = bar.selectedIndex;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *chip = nil;
            for (UIView *view in bar.subviews) if ([view isKindOfClass:[UIButton class]] && view.tag == index) chip = view;
            if (chip) [bar scrollRectToVisible:CGRectInset(chip.frame, -24, 0) animated:NO];
        });
    }
    return header;
}

- (void)layoutScreenPicked:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)RCLayoutScreens().count) return;
    self.layoutScreen = RCLayoutScreens()[index][1];
    [[NSUserDefaults standardUserDefaults] setObject:self.layoutScreen forKey:@"RCLayoutPageScreen"];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    RCLayoutPreview *preview = (RCLayoutPreview *)self.tableView.tableHeaderView;
    if ([preview isKindOfClass:[RCLayoutPreview class]]) [preview showScreen:self.layoutScreen];
    // The rows swap in place: animated, the table slid them and resized their text
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView layoutIfNeeded];
    }];
}

// List / Compact adds or takes away the Compact settings under it
- (void)layoutSettingChanged:(NSNotification *)note {
    if (self.page != RCSettingsPageLayout || ![note.object isEqual:[self currentLayoutScreen]]) return;
    if (![note.userInfo[RCLayoutOptionKey] isEqual:RCLayoutOptionCompact]) return;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [self sections][section][@"footer"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[self sections][section][@"rows"] count];
}

- (UISwitch *)switchOn:(BOOL)on action:(SEL)action {
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = on;
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return toggle;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSString *rowID = [self rowIDAtIndexPath:indexPath];
    if ([rowID hasPrefix:@"layout:"]) {
        return RCLayoutOptionCell([self titleForRowID:rowID], [self currentLayoutScreen], [rowID substringFromIndex:@"layout:".length]);
    }
    if ([rowID hasPrefix:@"timing:"] || [rowID hasPrefix:@"swipe:"]) return [self sliderCellForRowID:rowID];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.masksToBounds = YES;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.textLabel.text = [self titleForRowID:rowID];
    cell.textLabel.numberOfLines = 0; // a long name wraps (RCSettingsRowHeight)
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    UISwitch *toggle = nil;
    if ([rowID isEqualToString:RCRowWakeScreen]) {
        toggle = [self switchOn:cm.toastsWakeScreen action:@selector(toastsWakeScreenChanged:)];
    } else if ([rowID isEqualToString:RCRowBanners]) {
        NSUInteger count = [RCBannersViewController checkedCount];
        cell.detailTextLabel.text = count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : @"Off";
    } else if ([rowID isEqualToString:RCRowNFCScanning]) {
        toggle = [self switchOn:cm.nfcEnabled action:@selector(nfcToggleChanged:)];
    } else if ([rowID isEqualToString:RCRowNFCExperimental]) {
        toggle = [self switchOn:cm.nfcBackgroundReading action:@selector(experimentalNFCChanged:)];
        toggle.enabled = [RCConfigManager nfcBackgroundReadingSupported] && cm.nfcEnabled;
    } else if ([rowID isEqualToString:RCRowNFCScreenOff]) {
        cell.detailTextLabel.text = [self nfcWindowTitleForSeconds:cm.nfcScreenOffSeconds];
    } else if ([rowID isEqualToString:RCRowWrapLongNames]) {
        toggle = [self switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] action:@selector(wrapLongNamesToggleChanged:)];
    } else if ([rowID isEqualToString:RCRowLogging]) {
        cell.detailTextLabel.text = [cm.logLevel capitalizedString];
    } else if ([rowID isEqualToString:RCRowLockScrolling]) {
        toggle = [self switchOn:cm.freezeListsDuringGestures action:@selector(freezeListsToggleChanged:)];
    } else if ([rowID isEqualToString:RCRowUnlockOutOfPocket]) {
        toggle = [self switchOn:cm.onlyUnlockOutOfPocket action:@selector(onlyUnlockOutOfPocketChanged:)];
    } else if ([rowID isEqualToString:RCRowRunning]) {
        cell.imageView.image = RCSettingsIcon(@"list.bullet.rectangle", [UIColor systemGreenColor]);
    } else if ([rowID isEqualToString:RCRowTestKit]) {
        cell.imageView.image = RCSettingsIcon([UIImage systemImageNamed:@"checklist"] ? @"checklist" : @"checkmark.seal.fill", [UIColor systemTealColor]);
    } else if ([rowID isEqualToString:RCRowSavedPasscode]) {
        cell.detailTextLabel.text = [RCConfigManager unlockPasscodeSaved] ? @"Saved" : @"None";
    } else if ([rowID isEqualToString:RCRowRootHelper]) {
        toggle = [self switchOn:cm.allowDirectRootHelper action:@selector(directRootToggleChanged:)];
    } else if ([rowID isEqualToString:RCRowDeveloperMode]) {
        toggle = [self switchOn:cm.developerMode action:@selector(developerModeToggleChanged:)];
    } else if ([rowID hasPrefix:@"timing:"]) {
        double (^get)(void) = [self timingRows][[self indexFromRowID:rowID prefix:@"timing:"]][@"get"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f s", get()];
    } else if ([rowID hasPrefix:@"swipe:"]) {
        NSDictionary *row = [self swipeRowForRowID:rowID];
        cell.detailTextLabel.text = [NSString stringWithFormat:row[@"format"] ?: @"%.0f pt", [cm swipeSettingForKey:row[@"key"] defaultValue:[row[@"default"] doubleValue]]];
    }
    if (toggle) {
        cell.accessoryView = toggle;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *rowID = [self rowIDAtIndexPath:indexPath];
    if ([rowID hasPrefix:@"timing:"] || [rowID hasPrefix:@"swipe:"]) return [RCSliderCell rowHeight];
    return RCSettingsRowHeight(tableView, [self tableView:tableView cellForRowAtIndexPath:indexPath]);
}

// A Button Timing or Swipe Triggers row: a slider, in 0.01 s or 1 pt / 1% steps, within the range
// the tweak accepts
- (UITableViewCell *)sliderCellForRowID:(NSString *)rowID {
    RCSliderCell *cell = [[RCSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [self configureSliderCell:cell rowID:rowID];
    return cell;
}

// Also used to bring a showing slider up to date, without replacing it (a − or + held down keeps
// repeating)
- (void)configureSliderCell:(RCSliderCell *)cell rowID:(NSString *)rowID {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.layer.masksToBounds = YES;
    cell.presenter = self;
    if ([rowID hasPrefix:@"timing:"]) {
        NSDictionary *row = [self timingRows][[self indexFromRowID:rowID prefix:@"timing:"]];
        double (^get)(void) = row[@"get"];
        void (^set)(double) = row[@"set"];
        [cell setTitle:row[@"title"] value:get() min:[row[@"min"] doubleValue] max:[row[@"max"] doubleValue]
                  step:0.01 defaultValue:[row[@"default"] doubleValue] format:@"%.2f s"];
        cell.message = row[@"message"];
        cell.lockKey = row[@"key"];
        cell.onChange = ^(double value) { set(value); };
    } else {
        NSDictionary *row = [self swipeRowForRowID:rowID];
        NSString *key = row[@"key"];
        double defaultValue = [row[@"default"] doubleValue];
        [cell setTitle:row[@"title"] value:[cm swipeSettingForKey:key defaultValue:defaultValue]
                   min:[row[@"min"] doubleValue] max:[row[@"max"] doubleValue] step:1 defaultValue:defaultValue format:row[@"format"] ?: @"%.0f pt"];
        cell.message = row[@"message"];
        cell.lockKey = key;
        cell.onChange = ^(double value) { [cm setSwipeSetting:value forKey:key defaultValue:defaultValue]; };
    }
}

// Every save posts this (a slider's too), and so does Adjust on Screen saving from SpringBoard:
// sliders are updated in place, the other rows reloaded
- (void)configChanged:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    NSMutableArray *reload = [NSMutableArray array];
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        NSString *rowID = [self rowIDAtIndexPath:indexPath];
        if ([cell isKindOfClass:[RCSliderCell class]]) [self configureSliderCell:(RCSliderCell *)cell rowID:rowID];
        else [reload addObject:indexPath];
    }
    if (reload.count) [self.tableView reloadRowsAtIndexPaths:reload withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *rowID = [self rowIDAtIndexPath:indexPath];
    UIView *source = [tableView cellForRowAtIndexPath:indexPath];

    if ([rowID isEqualToString:RCRowBanners]) {
        [self.navigationController pushViewController:[[RCBannersViewController alloc] init] animated:YES];
    } else if ([rowID isEqualToString:RCRowSavedPasscode]) {
        [self chooseSavedPasscode];
    } else if ([rowID isEqualToString:RCRowRunning]) {
        [self.navigationController pushViewController:[[RCRunningViewController alloc] init] animated:YES];
    } else if ([rowID isEqualToString:RCRowTestKit]) {
        [self.navigationController pushViewController:[[RCTestKitViewController alloc] init] animated:YES];
    } else if ([rowID isEqualToString:RCRowNFCScreenOff]) {
        [self chooseNFCWindowFromView:source];
    } else if ([rowID isEqualToString:RCRowLogging]) {
        [self chooseLogLevelFromView:source];
    } else if ([rowID isEqualToString:RCRowAdjustOnScreen]) {
        // SpringBoard draws it over every app (RCSwipeZones.m in the tweak)
        notify_post("com.pizzaman.rc.swipe_zones.show");
    }
}

#pragma mark - Button Timing

// The Button Timing rows, in order: the click and sequence windows, then the hold times. Home
// Clicks only on a phone with a Home button.
- (NSArray<NSDictionary *> *)timingRows {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@{ @"title": @"Volume Sequence", @"key": @"volumeSequenceWindow",
        @"message": @"How soon after a volume press the other volume button completes an Up then Down or Down then Up sequence.", @"default": @0.38, @"min": @0.15, @"max": @0.80,
        @"get": ^double{ return cm.volumeSequenceWindow; }, @"set": ^(double v) { cm.volumeSequenceWindow = v; } }];
    [rows addObject:@{ @"title": @"Power Clicks", @"key": @"powerClickWindow",
        @"message": @"How long a Power press waits for the next click before the clicks count as a double, triple or quadruple click.", @"default": @0.40, @"min": @0.10, @"max": @0.80,
        @"get": ^double{ return cm.powerClickWindow; }, @"set": ^(double v) { cm.powerClickWindow = v; } }];
    // A phone with a Home button has no safe area at the bottom of the screen
    // (not self.view.window unless the page is showing: search lists the rows without loading the page)
    UIWindow *window = (self.isViewLoaded ? self.view.window : nil) ?: [UIApplication sharedApplication].windows.firstObject;
    if (window && window.safeAreaInsets.bottom <= 0) {
        [rows addObject:@{ @"title": @"Home Clicks", @"key": @"homeClickWindow",
            @"message": @"How long a Home press waits for the next click before the clicks count as a double, triple or quadruple click.", @"default": @0.35, @"min": @0.25, @"max": @0.80,
            @"get": ^double{ return cm.homeClickWindow; }, @"set": ^(double v) { cm.homeClickWindow = v; } }];
    }
    [rows addObject:@{ @"title": @"Volume Hold", @"key": @"volumeHoldTime",
        @"message": @"How long a Volume Up or Down press is held before it counts as a hold rather than a tap. Taps wait this long when a hold trigger is set.", @"default": @0.35, @"min": @0.20, @"max": @0.80,
        @"get": ^double{ return cm.volumeHoldTime; }, @"set": ^(double v) { cm.volumeHoldTime = v; } }];
    [rows addObject:@{ @"title": @"Power Hold", @"key": @"powerHoldTime",
        @"message": @"How long a Power press is held before it counts as a long press.", @"default": @0.50, @"min": @0.30, @"max": @0.75,
        @"get": ^double{ return cm.powerHoldTime; }, @"set": ^(double v) { cm.powerHoldTime = v; } }];
    return rows;
}

// The Swipe Triggers rows: each a config key, its default (the size the tweak always used) and
// the values to pick from, in points unless the row has its own format (the zone shares, in percent)
- (NSArray<NSDictionary *> *)swipeRows {
    return @[
        @{ @"title": @"Edge Strip", @"key": @"swipeEdgeStrip", @"min": @10, @"max": @60, @"default": @25,
           @"message": @"How close to the left or right side an edge swipe has to start.", },
        @{ @"title": @"Edge Swipe", @"key": @"swipeEdgeDistance", @"min": @10, @"max": @250, @"default": @30,
           @"message": @"How far an edge swipe slides up or down before its trigger runs.", },
        @{ @"title": @"Status Bar Swipe", @"key": @"swipeStatusBarDistance", @"min": @10, @"max": @250, @"default": @50,
           @"message": @"How far a swipe left or right along the status bar goes before its trigger runs.", },
        @{ @"title": @"Top Swipe Down", @"key": @"swipeTopDownDistance", @"min": @10, @"max": @250, @"default": @45,
           @"message": @"How far a swipe down from the top goes before its trigger runs.", },
        @{ @"title": @"Bottom Bar Swipe", @"key": @"swipeBottomBarDistance", @"min": @10, @"max": @250, @"default": @60,
           @"message": @"How far a swipe left or right along the bottom of the screen goes before its trigger runs.", },
        @{ @"title": @"Bottom Swipe Up", @"key": @"swipeBottomUpDistance", @"min": @10, @"max": @250, @"default": @45,
           @"message": @"How far a swipe up from the bottom goes before its trigger runs.", },
        @{ @"title": @"Status Bar Height", @"key": @"swipeStatusBarHeight", @"min": @10, @"max": @100, @"default": @25,
           @"message": @"How close to the top a status bar tap, hold or swipe has to start. Phones with the Dynamic Island have a taller status bar, where 40 or more suits.", },
        @{ @"title": @"Status Bar Left Zone", @"key": @"swipeStatusBarLeftZone", @"min": @5, @"max": @60, @"default": @33, @"format": @"%.0f%%",
           @"message": @"How much of the status bar, from the left, counts as its left zone. The center zone has what the left and right zones leave.", },
        @{ @"title": @"Status Bar Right Zone", @"key": @"swipeStatusBarRightZone", @"min": @5, @"max": @60, @"default": @33, @"format": @"%.0f%%",
           @"message": @"How much of the status bar, from the right, counts as its right zone. The center zone has what the left and right zones leave.", },
        @{ @"title": @"Bottom Zone Height", @"key": @"swipeBottomZoneHeight", @"min": @10, @"max": @100, @"default": @25,
           @"message": @"How close to the bottom a bottom bar swipe or a bottom swipe up has to start.", },
        @{ @"title": @"Bottom Left Zone", @"key": @"swipeBottomLeftZone", @"min": @5, @"max": @60, @"default": @33, @"format": @"%.0f%%",
           @"message": @"How much of the bottom edge, from the left, starts a Bottom Swipe Up (Left). The center zone has what the left and right zones leave.", },
        @{ @"title": @"Bottom Right Zone", @"key": @"swipeBottomRightZone", @"min": @5, @"max": @60, @"default": @33, @"format": @"%.0f%%",
           @"message": @"How much of the bottom edge, from the right, starts a Bottom Swipe Up (Right). The center zone has what the left and right zones leave.", },
    ];
}

#pragma mark - Actions

- (void)nfcToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].nfcEnabled = sender.on;
    [self.tableView reloadData];
}

- (void)experimentalNFCChanged:(UISwitch *)sender {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    cm.nfcBackgroundReading = sender.on;
    // Explained the first time it's turned on, and whenever turning it on sets NFC With Screen
    // Off to Off
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL changedScreenOff = sender.on && cm.nfcScreenOffSeconds > 0;
    BOOL firstTime = sender.on && ![defaults boolForKey:@"RCExperimentalNFCExplained"];
    if (changedScreenOff) cm.nfcScreenOffSeconds = 0;
    if (sender.on) [defaults setBool:YES forKey:@"RCExperimentalNFCExplained"];
    if (changedScreenOff || firstTime) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Experimental NFC"
            message:@"Enabling Experimental NFC gives control of the NFC sensor back to iOS. This is so that express cards, tags, and passes still work as intended. iOS has an internal NFC cooldown of about 3 seconds. For cards and keys to work while the phone is locked, keep NFC With Screen Off set to Off."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    [self.tableView reloadData];
}

- (void)wrapLongNamesToggleChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"RCWrapLongNamesEnabled"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RCWrapLongNamesSettingChanged" object:nil];
}

- (void)freezeListsToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].freezeListsDuringGestures = sender.on;
}

- (void)onlyUnlockOutOfPocketChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].onlyUnlockOutOfPocket = sender.on;
}

- (void)directRootToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].allowDirectRootHelper = sender.on;
}

- (void)developerModeToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].developerMode = sender.on;
}
// Save, change or forget the passcode Unlock Device and Lock Toggle enter
- (void)chooseSavedPasscode {
    [RCConfigManager checkUnlockPasscodeSaved:^(BOOL saved) { dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Saved Passcode"
            message:@"The device passcode that Unlock Device and Lock Toggle enter, kept in the Keychain on this iPhone only."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = saved ? @"New Passcode" : @"Passcode";
            field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            field.secureTextEntry = YES;
        }];
        __weak typeof(self) weakSelf = self;
        void (^done)(NSString *) = ^(NSString *error) { dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
            if (!error) return;
            UIAlertController *failed = [UIAlertController alertControllerWithTitle:@"Passcode Not Changed" message:error preferredStyle:UIAlertControllerStyleAlert];
            [failed addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf presentViewController:failed animated:YES completion:nil];
        }); };
        UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *pin = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!pin.length) { done(@"Enter the device passcode."); return; }
            [RCConfigManager saveUnlockPasscode:pin completion:done];
        }];
        [alert addAction:save];
        if (saved) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Forget Saved Passcode" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                [RCConfigManager forgetUnlockPasscode:done];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        alert.preferredAction = save;
        [self presentViewController:alert animated:YES completion:nil];
    }); }];
}

- (void)toastsWakeScreenChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].toastsWakeScreen = sender.on;
}

- (void)chooseLogLevelFromView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Logging"
        message:@"Minimal records triggers, their actions and conditions, and errors. Full records every step, for tracking down a problem."
        preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *current = [RCConfigManager sharedManager].logLevel;
    for (NSString *level in @[@"off", @"minimal", @"full"]) {
        NSString *title = [level isEqualToString:current] ? [NSString stringWithFormat:@"%@ \u2713", [level capitalizedString]] : [level capitalizedString];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [RCConfigManager sharedManager].logLevel = level;
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

// How long the NFC scan keeps going after the screen turns off. A window longer than the default
// asks first: it costs battery and keeps the reader in use.
static const double kRCNFCDefaultWindow = 120.0;

- (NSString *)nfcWindowTitleForSeconds:(double)seconds {
    if (seconds <= 0) return @"Off";
    if (seconds < 60) return [NSString stringWithFormat:@"%.0f s", seconds];
    NSInteger minutes = (NSInteger)lround(seconds / 60.0);
    return minutes == 1 ? @"1 min" : [NSString stringWithFormat:@"%ld min", (long)minutes];
}

- (void)chooseNFCWindowFromView:(UIView *)sourceView {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"NFC With Screen Off"
        message:@"How long a tag can still be tapped after the screen turns off. Off reads tags only while the screen is on."
        preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *choices = @[@0, @30, @60, @120, @300, @600, @1800];
    NSArray<NSString *> *names = @[@"Off", @"30 Seconds", @"1 Minute", @"2 Minutes", @"5 Minutes", @"10 Minutes", @"30 Minutes"];
    for (NSUInteger i = 0; i < choices.count; i++) {
        double seconds = choices[i].doubleValue;
        BOOL isCurrent = fabs(seconds - cm.nfcScreenOffSeconds) < 1.0;
        NSString *title = [NSString stringWithFormat:@"%@%@%@", names[i], seconds == kRCNFCDefaultWindow ? @" (Default)" : @"", isCurrent ? @" \u2713" : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (seconds <= kRCNFCDefaultWindow) {
                cm.nfcScreenOffSeconds = seconds;
                [self.tableView reloadData];
                return;
            }
            UIAlertController *warning = [UIAlertController alertControllerWithTitle:@"Longer Scan Window"
                message:@"The NFC reader stays in use while the screen is off. That costs battery (about 3% an hour on an iPhone 8) and warms the phone, and the system may switch the reader off for a few minutes. A longer window only helps when tags are tapped long after the screen goes dark."
                preferredStyle:UIAlertControllerStyleAlert];
            [warning addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Use %@", names[i]] style:UIAlertActionStyleDefault handler:^(UIAlertAction *confirm) {
                cm.nfcScreenOffSeconds = seconds;
                [self.tableView reloadData];
            }]];
            [warning addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:warning animated:YES completion:nil];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
