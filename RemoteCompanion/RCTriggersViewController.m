#import "RCTriggersViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCNewTriggerViewController.h"
#import "RCSettingsViewController.h"
#import "RCFocusTriggerViewController.h"
#import "RCAddOnCatalog.h"
#import "RCAddOnTriggersViewController.h"
#import "RCNFCTriggerViewController.h"
#import <notify.h>
#import "RCWiFiTriggerViewController.h"
#import "RCBluetoothTriggerViewController.h"
#import "RCAudioOutputTriggerViewController.h"
#import "RCBatteryTriggerViewController.h"
#import "RCWrapSizing.h"
#import "RCAppPickerViewController.h"
#import "RCNotificationTriggerViewController.h"
#import "RCScheduledTriggerViewController.h"
#import "RCMQTTTriggerViewController.h"
#import "RCCategoryBar.h"
#import "RCActionTile.h"
#import "RCTriggersGrid.h"
#import "RCTriggerIcons.h"
#import "RCServerClient.h"

#define kSimulateNotificationPrefix "com.pizzaman.rc.simulate."

// Grows to show the whole title and subtitle, never below the usual row height
@interface RCTriggerCell : UITableViewCell
@end

@implementation RCTriggerCell
- (CGSize)systemLayoutSizeFittingSize:(CGSize)targetSize withHorizontalFittingPriority:(UILayoutPriority)horizontalFittingPriority verticalFittingPriority:(UILayoutPriority)verticalFittingPriority {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"]) return CGSizeMake(targetSize.width, 64.0);
    return CGSizeMake(targetSize.width, RCWrappedCellHeight(self, targetSize.width, 64.0));
}
@end

@interface RCTriggersViewController () <RCTriggersGridSource>
// Compact: the grid, its pull-to-refresh, and the bar buttons without Edit
@property (nonatomic, strong) RCTriggersGrid *grid;
@property (nonatomic, strong) UIRefreshControl *gridRefresh;
@property (nonatomic, assign) BOOL pausedByAction; // Resume shows at the top left
@property (nonatomic, strong) UIBarButtonItem *resumeItem;
@property (nonatomic, assign) UITableViewStyle tableStyle;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *sections;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
// Category bar: the section shown on its own, or nil for all. Kept by title because
// sections come and go (Favorites, NFC, Wi-Fi, ... only appear when they have triggers).
@property (nonatomic, strong) RCCategoryBar *categoryBar;
@property (nonatomic, copy) NSString *selectedCategoryTitle;
// The width the visible cells' card backgrounds were drawn for
@property (nonatomic, assign) CGFloat cardStyleWidth;
@end

@implementation RCTriggersViewController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    self = [super initWithNibName:nil bundle:nil];
    if (self) _tableStyle = style;
    return self;
}

// The table (List) fills the view; the grid (Compact) is added beside it in viewDidLoad
- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.tableView = [[UITableView alloc] initWithFrame:view.bounds style:self.tableStyle];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:self.tableView];
    self.view = view;
}

// Helper to get short friendly names for command strings
- (NSString *)nameForCommand:(NSString *)cmd truncate:(BOOL)shouldTruncate {
    return [[RCConfigManager sharedManager] nameForCommand:cmd truncate:shouldTruncate];
}

+ (NSString *)iconNameForTrigger:(NSString *)triggerKey {
    if ([triggerKey containsString:@"two_finger"]) return @"hand.draw";
    if ([triggerKey isEqualToString:@"volume_up_then_down"] || [triggerKey isEqualToString:@"volume_down_then_up"]) return @"arrow.up.and.down.circle.fill";
    if ([triggerKey hasPrefix:@"trigger_bottom_swipe_up"]) return @"chevron.compact.up";
    if ([triggerKey hasPrefix:@"trigger_bottombar"]) return @"square.stack.3d.up.fill";
    if ([triggerKey containsString:@"volume"]) return @"speaker.wave.2.fill";
    if ([triggerKey containsString:@"power"]) return @"power";
    if ([triggerKey containsString:@"statusbar"]) return @"hand.draw"; // Status bar / screen gestures
    if ([triggerKey containsString:@"home"]) return @"circle.circle"; // Home button
    if ([triggerKey containsString:@"ringer"]) return @"bell.fill";
    if ([triggerKey hasPrefix:@"trigger_watch_ping"]) {
        if (@available(iOS 14.0, *)) return @"applewatch.radiowaves.left.and.right";
        return @"bell.fill";
    }
    if ([triggerKey containsString:@"edge"]) {
        if (@available(iOS 14.2, *)) return @"iphone.homebutton.radiowaves.left.and.right";
        return @"hand.draw";
    }
    if ([triggerKey containsString:@"touchid"]) return @"touchid";
    if ([triggerKey hasPrefix:@"nfc_"]) return @"wave.3.right.circle.fill";
    if ([triggerKey hasPrefix:@"wifi_"]) return @"wifi";
    if ([triggerKey hasPrefix:@"trigger_device_focus_on"]) return @"moon.fill";
    if ([triggerKey hasPrefix:@"trigger_device_focus_off"]) return @"moon";
    if ([triggerKey hasPrefix:@"bt_"]) return @"bolt.horizontal.fill";
    if ([triggerKey hasPrefix:@"output_"]) return @"airplayaudio";
    if ([triggerKey hasPrefix:@"trigger_device_battery_above_"]) return @"battery.100";
    if ([triggerKey hasPrefix:@"trigger_device_battery_below_"]) return @"battery.25";
    if ([RCAddOnCatalog isAddOnTriggerKey:triggerKey]) return [RCAddOnCatalog iconForTriggerKey:triggerKey] ?: @"puzzlepiece.extension";
    if ([triggerKey hasPrefix:@"app_launch_"]) return @"app.badge";
    if ([triggerKey hasPrefix:@"app_exit_"]) return @"rectangle.portrait.and.arrow.right";
    if ([triggerKey hasPrefix:@"notif_"] || [triggerKey hasPrefix:@"notify_"]) return @"bell.badge.fill";
    if ([triggerKey hasPrefix:@"sched_"]) return @"clock.fill";
    if ([triggerKey hasPrefix:@"mqtt_"] || [triggerKey hasPrefix:@"mqtt_sub_"]) return @"antenna.radiowaves.left.and.right";
    if ([triggerKey isEqualToString:@"shake"]) return @"waveform.path.ecg";
    if ([triggerKey isEqualToString:@"trigger_power_connect"]) return @"bolt.fill";
    if ([triggerKey isEqualToString:@"trigger_power_disconnect"]) return @"bolt.slash.fill";
    if ([triggerKey isEqualToString:@"trigger_device_findmy_sound"]) return @"location.circle.fill";
    if ([triggerKey isEqualToString:@"trigger_carplay_connect"]) return @"car.fill";
    if ([triggerKey isEqualToString:@"trigger_carplay_disconnect"]) return @"car";
    if ([triggerKey isEqualToString:@"trigger_device_rotated_landscape"]) return @"iphone.landscape";
    if ([triggerKey isEqualToString:@"trigger_device_rotated_portrait"]) return @"iphone";
    if ([triggerKey isEqualToString:@"trigger_device_lock"]) return @"lock.fill";
    if ([triggerKey isEqualToString:@"trigger_device_unlock"]) return @"lock.open.fill";
    if ([triggerKey isEqualToString:@"trigger_media_play"]) return @"play.fill";
    if ([triggerKey isEqualToString:@"trigger_media_pause"]) return @"pause.fill";
    if ([triggerKey isEqualToString:@"trigger_media_track_change"]) return @"forward.fill";
    if ([triggerKey isEqualToString:@"trigger_device_call_incoming"]) return @"phone.arrow.down.left";
    if ([triggerKey isEqualToString:@"trigger_device_call_start"]) return @"phone.fill";
    if ([triggerKey isEqualToString:@"trigger_device_call_end"]) return @"phone.down.fill";
    return @"hand.tap"; // Default
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.title = @"RemoteCompanion";
    
    // Use default appearance for translucent blur
    // We do NOT set standardAppearance/scrollEdgeAppearance to opaque here anymore
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    UIBarButtonItem *settingsItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"gear"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(openSettings)];

    UIBarButtonItem *addItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"plus"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(addNewItem)];

    self.navigationItem.rightBarButtonItems = @[settingsItem, addItem];
    
    // Long names (a device or app name, a chain of actions) wrap, and the row grows with them
    self.tableView.rowHeight = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] ? UITableViewAutomaticDimension : 64.0;
    self.tableView.estimatedRowHeight = 64;
    if (@available(iOS 15.0, *)) {
        // Spacing above headers is built into the header views instead (see
        // heightForHeaderInSection:), so the first one can sit close to the category bar
        self.tableView.sectionHeaderTopPadding = 0;
    }
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0); // Reset inset since we have large titles handling spacing better now
    
    self.categoryBar = [[RCCategoryBar alloc] initWithWidth:self.view.bounds.size.width];
    __weak typeof(self) weakSelf = self;
    self.categoryBar.onSelect = ^(NSInteger index) {
        weakSelf.selectedCategoryTitle = (index >= 0 && index < (NSInteger)weakSelf.sectionTitles.count) ? weakSelf.sectionTitles[index] : nil;
        [weakSelf.tableView reloadData];
        [weakSelf.grid reload];
    };
    [self.categoryBar attachToTableView:self.tableView];

    // Pull-to-refresh
    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [UIColor systemGrayColor];
    [self.refreshControl addTarget:self action:@selector(handleRefresh) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    // Edit button will be shown/hidden based on favorites

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
        initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self.tableView addGestureRecognizer:longPress];
    
    self.navigationController.toolbarHidden = YES;
    
    // Listen for config changes
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleConfigChanged:) 
                                                 name:RCConfigChangedNotification 
                                               object:nil];
                                               
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleTweaksChanged:) 
                                                 name:@"RCConfigTweaksChangedNotification" 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wrapLongNamesSettingChanged:) name:@"RCWrapLongNamesSettingChanged" object:nil];
                                               
    [self setupFooterView];
    [self setupGrid];
    [self applyTweaks];
}

#pragma mark - Layout (List or Compact)

- (BOOL)compactLayout {
    return RCLayoutIsCompact(RCLayoutTriggers);
}

- (UIScrollView *)activeScrollView {
    return [self compactLayout] ? self.grid.collectionView : self.tableView;
}

- (void)setupGrid {
    self.grid = [[RCTriggersGrid alloc] initWithSource:self];
    UICollectionView *collection = self.grid.collectionView;
    collection.frame = self.view.bounds;
    collection.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:collection];
    self.gridRefresh = [[UIRefreshControl alloc] init];
    self.gridRefresh.tintColor = [UIColor systemGrayColor];
    [self.gridRefresh addTarget:self action:@selector(handleRefresh) forControlEvents:UIControlEventValueChanged];
    collection.refreshControl = self.gridRefresh;
    // The same footer (name and version) under the grid
    UIView *tableFooter = self.tableView.tableFooterView;
    [self setupFooterView];
    self.grid.footerView = self.tableView.tableFooterView;
    self.tableView.tableFooterView = tableFooter;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutSettingChanged:) name:RCLayoutChangedNotification object:nil];
    [self applyLayout];
}

// The top left: Edit in Compact, and Resume while button triggers are paused by the action
- (void)updateLeftItems {
    NSMutableArray *items = [NSMutableArray array];
    if ([self compactLayout] && self.grid) [items addObject:self.editButtonItem];
    if (self.pausedByAction) {
        if (!self.resumeItem) self.resumeItem = [[UIBarButtonItem alloc] initWithTitle:@"Resume" style:UIBarButtonItemStylePlain target:self action:@selector(resumeButtonTriggers)];
        [items addObject:self.resumeItem];
    }
    self.navigationItem.leftBarButtonItems = items;
}

// The grid's columns and margins follow a rotation (and the Dynamic Island in landscape)
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.grid.collectionView.collectionViewLayout invalidateLayout];
    } completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.grid reload];
        [self.categoryBar layoutInScrollView:[self activeScrollView]];
    }];
}

- (void)layoutSettingChanged:(NSNotification *)note {
    if ([note.object isEqual:RCLayoutTriggers]) [self applyLayout];
    else if ([note.object isEqual:RCLayoutTriggerColumns] || [note.object isEqual:RCLayoutTriggerSections]) {
        [self.grid.collectionView.collectionViewLayout invalidateLayout];
        [self.grid reload];
    }
}

// Shows the table or the grid, with the category bar on it; Edit comes with the grid
- (void)applyLayout {
    BOOL compact = [self compactLayout];
    // Edit ends on both: the setting has already changed, so setEditing: alone would end the wrong one
    if (self.editing) [super setEditing:NO animated:NO];
    self.grid.editing = NO;
    [self.tableView setEditing:NO animated:NO];
    UIScrollView *active = compact ? self.grid.collectionView : self.tableView;
    UIScrollView *other = compact ? (UIScrollView *)self.tableView : self.grid.collectionView;
    [self.categoryBar detachFromScrollView:other];
    if (self.categoryBar.superview != active) [self.categoryBar attachToScrollView:active];
    active.hidden = NO;
    other.hidden = YES;
    // The large title follows the first scroll view
    [self.view sendSubviewToBack:other];
    [self.view sendSubviewToBack:active];
    if (@available(iOS 15.0, *)) [self setContentScrollView:active forEdge:NSDirectionalRectEdgeAll];
    [self updateLeftItems];
    [self.tableView reloadData];
    [self.grid reload];
    [self.categoryBar layoutInScrollView:active];
}

- (void)handleTweaksChanged:(NSNotification *)note {
    [self applyTweaks];
}

- (void)wrapLongNamesSettingChanged:(NSNotification *)note {
    self.tableView.rowHeight = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] ? UITableViewAutomaticDimension : 64.0;
    [self.tableView reloadData];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.view.backgroundColor = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.grid.collectionView.backgroundColor = self.view.backgroundColor;
    [self.tableView reloadData];
    [self.grid reload];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self applyTweaks];
        }
    }
}

- (void)setupFooterView {
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    footerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // App Title Label
    UILabel *appTitleLabel = [[UILabel alloc] init];
    appTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    appTitleLabel.textAlignment = NSTextAlignmentCenter;
    appTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    appTitleLabel.textColor = [UIColor secondaryLabelColor]; // Match opacity of Volume Buttons header
    appTitleLabel.text = @"RemoteCompanion";
    
    // Version Label
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.font = [UIFont systemFontOfSize:13];
    versionLabel.textColor = [UIColor secondaryLabelColor];
    
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    versionLabel.text = [NSString stringWithFormat:@"v%@", version];
    
    [footerView addSubview:appTitleLabel];
    [footerView addSubview:versionLabel];
    
    // Add Tap Gesture to Footer Labels
    appTitleLabel.userInteractionEnabled = YES;
    versionLabel.userInteractionEnabled = YES;
    
    UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGitHub)];
    [appTitleLabel addGestureRecognizer:titleTap];
    
    UITapGestureRecognizer *versionTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGitHub)];
    [versionLabel addGestureRecognizer:versionTap];
    
    [NSLayoutConstraint activateConstraints:@[
        // Stack Title on top of Version
        [appTitleLabel.centerXAnchor constraintEqualToAnchor:footerView.centerXAnchor],
        [appTitleLabel.topAnchor constraintEqualToAnchor:footerView.topAnchor constant:10],
        [appTitleLabel.heightAnchor constraintEqualToConstant:20],
        
        [versionLabel.centerXAnchor constraintEqualToAnchor:footerView.centerXAnchor],
        [versionLabel.topAnchor constraintEqualToAnchor:appTitleLabel.bottomAnchor constant:0],
        [versionLabel.heightAnchor constraintEqualToConstant:16]
    ]];
    
    self.tableView.tableFooterView = footerView;
}
- (void)handleConfigChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Only reload if we're the visible VC; if we're buried in the stack
        // during an animated transition, skip — viewWillAppear will reload on return.
        if (self.isViewLoaded && self.view.window && self.navigationController.topViewController == self) {
            [self reloadTableData];
        }
    });
}

- (void)handleRefresh {
    [[RCConfigManager sharedManager] loadConfig];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCConfigChangedNotification object:nil];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.refreshControl endRefreshing];
        [self.gridRefresh endRefreshing];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadTableData];
    [self updatePauseState];
}

// Paused button triggers (the Button Triggers action, or another tweak): a line above the title,
// and Resume when it's the action's pause. The states are the tweak's (see RC_TriggersPaused).
- (void)updatePauseState {
    static int untilToken = -1, tweakToken = -1;
    static dispatch_once_t once;
    __weak typeof(self) weakSelf = self;
    dispatch_once(&once, ^{
        notify_register_check("com.pizzaman.rc.pause_buttons_until", &untilToken);
        notify_register_check("com.pizzaman.rc.pause_triggers", &tweakToken);
        int t1, t2;
        notify_register_dispatch("com.pizzaman.rc.pause_buttons_until", &t1, dispatch_get_main_queue(), ^(int t) { [weakSelf updatePauseState]; });
        notify_register_dispatch("com.pizzaman.rc.pause_triggers", &t2, dispatch_get_main_queue(), ^(int t) { [weakSelf updatePauseState]; });
    });
    uint64_t until = 0, byTweak = 0;
    if (untilToken != -1) notify_get_state(untilToken, &until);
    if (tweakToken != -1) notify_get_state(tweakToken, &byTweak);
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (until != UINT64_MAX && until <= (uint64_t)now) until = 0;

    NSString *prompt = nil;
    if (until == UINT64_MAX) {
        prompt = @"Button triggers paused";
    } else if (until) {
        NSString *time = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:until] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
        prompt = [NSString stringWithFormat:@"Button triggers paused until %@", time];
        // Clear the line when the pause runs out
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((until - now + 1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf updatePauseState]; });
    } else if (byTweak) {
        prompt = @"Button triggers paused by another tweak";
    }
    self.navigationItem.prompt = prompt;
    self.pausedByAction = until != 0;
    [self updateLeftItems];
}

- (void)resumeButtonTriggers {
    [[RCServerClient sharedClient] executeCommand:@"button triggers resume" completion:^(NSString *output, NSError *error) {}];
}

- (void)reloadTableData {
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];

    RCConfigManager *config = [RCConfigManager sharedManager];

    // Helper to filter out favorited triggers
    NSArray* (^filterFavorites)(NSArray*) = ^NSArray*(NSArray *keys) {
        return [keys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
            return ![config isTriggerFavorite:key];
        }]];
    };

    // Get ordered favorites from config
    // A created trigger that was deleted before deleting took it out of Favorites isn't shown
    NSArray *allFavorites = [[config orderedFavorites] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
        return ![RCConfigManager canRenameTrigger:key] || [config triggerDataForKey:key] != nil;
    }]];

    // Add Favorites section at top if there are any
    if (allFavorites.count > 0) {
        [sections addObject:[allFavorites mutableCopy]];
        [titles addObject:@"Favorites"];
    }

    // Helper to add section
    void (^addSection)(NSArray *, NSString *, BOOL) = ^(NSArray *keys, NSString *title, BOOL hideIfEmpty) {
        NSArray *filtered = filterFavorites(keys);
        if (filtered.count > 0 || !hideIfEmpty) {
            [sections addObject:filtered];
            [titles addObject:title];
        }
    };

    // Standard Sections (Always show headers)
    addSection(@[@"volume_up_hold", @"volume_down_hold", @"volume_both_press", @"volume_up_then_down", @"volume_down_then_up"], @"Volume Buttons", NO);
    addSection(@[@"power_double_tap", @"power_triple_click", @"power_quadruple_click", @"power_volume_up", @"power_volume_down", @"power_long_press"], @"Power Button", NO);
    addSection(@[@"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right", @"trigger_statusbar_double_tap"], @"Status Bar", NO);
    addSection(@[@"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down"], @"Edge Gestures", NO);
    addSection(@[@"trigger_bottombar_swipe_left", @"trigger_bottombar_swipe_right", @"trigger_bottom_swipe_up_left", @"trigger_bottom_swipe_up_center", @"trigger_bottom_swipe_up_right"], @"Bottom Bar Gestures", NO);
    // Multi-Finger Gestures Section (Only show if configured, hide if empty)
    NSMutableArray *multiFingerKeys = [NSMutableArray array];
    for (NSString *key in @[@"trigger_statusbar_two_finger_swipe_down", @"trigger_bottom_two_finger_swipe_up"]) {
        NSDictionary *trig = [[RCConfigManager sharedManager] triggerDataForKey:key];
        if (trig && ([trig[@"enabled"] boolValue] || [trig[@"actions"] count] > 0)) {
            [multiFingerKeys addObject:key];
        }
    }
    addSection(multiFingerKeys, @"Multi-Finger Gestures", YES);
    if ([RCConfigManager hasHomeButton]) {
        addSection(@[@"trigger_home_double_click", @"trigger_home_triple_click", @"trigger_home_quadruple_click", @"trigger_home_hold", @"trigger_home_power", @"touchid_tap", @"touchid_hold"], @"Home Button", NO);
    }
    addSection(@[@"trigger_ringer_mute", @"trigger_ringer_unmute", @"trigger_ringer_toggle"], @"Ringer Switch", NO);
    // Apple Watch Section (Only show if configured, hide if empty)
    NSMutableArray *watchKeys = [NSMutableArray array];
    for (NSString *key in @[@"trigger_watch_ping", @"trigger_watch_ping_hold"]) {
        if ([[RCConfigManager sharedManager] actionsForTrigger:key].count > 0) {
            [watchKeys addObject:key];
        }
    }
    addSection(watchKeys, @"Apple Watch", YES);
    // Device State Section (Only show if configured, hide if empty)
    NSMutableArray *deviceStateKeys = [NSMutableArray array];
    // Focus triggers, by name, On before Off
    NSMutableArray *focusKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([key hasPrefix:@"trigger_device_focus_"]) [focusKeys addObject:key];
    }
    [focusKeys sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSString *(^focus)(NSString *) = ^NSString *(NSString *key) {
            NSRange r = [key rangeOfString:@"_" options:0 range:NSMakeRange(21, key.length - 21)];
            return r.location == NSNotFound ? @"" : [key substringFromIndex:r.location + 1];
        };
        NSComparisonResult byName = [focus(a) localizedCaseInsensitiveCompare:focus(b)];
        return byName != NSOrderedSame ? byName : [b compare:a]; // "on" before "off"
    }];
    [deviceStateKeys addObjectsFromArray:focusKeys];
    NSArray *configuredKeys = [[RCConfigManager sharedManager] allConfiguredTriggerKeys];
    // Battery Level triggers, lowest level first
    NSMutableArray *batteryKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"trigger_device_battery_"]) [batteryKeys addObject:key];
    }
    [batteryKeys sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult byLevel = [@([[a substringFromIndex:29] integerValue]) compare:@([[b substringFromIndex:29] integerValue])];
        return byLevel != NSOrderedSame ? byLevel : [b compare:a]; // "below" before "above"
    }];
    [deviceStateKeys addObjectsFromArray:batteryKeys];
    if ([configuredKeys containsObject:@"trigger_device_lock"]) {
        [deviceStateKeys addObject:@"trigger_device_lock"];
    }
    if ([configuredKeys containsObject:@"trigger_device_unlock"]) {
        [deviceStateKeys addObject:@"trigger_device_unlock"];
    }
    if ([configuredKeys containsObject:@"trigger_power_connect"]) {
        [deviceStateKeys addObject:@"trigger_power_connect"];
    }
    if ([configuredKeys containsObject:@"trigger_power_disconnect"]) {
        [deviceStateKeys addObject:@"trigger_power_disconnect"];
    }
    for (NSString *key in @[@"trigger_device_rotated_landscape", @"trigger_device_rotated_portrait"]) {
        if ([configuredKeys containsObject:key]) [deviceStateKeys addObject:key];
    }
    if ([configuredKeys containsObject:@"trigger_carplay_connect"]) {
        [deviceStateKeys addObject:@"trigger_carplay_connect"];
    }
    if ([configuredKeys containsObject:@"trigger_carplay_disconnect"]) {
        [deviceStateKeys addObject:@"trigger_carplay_disconnect"];
    }
    if ([configuredKeys containsObject:@"trigger_device_findmy_sound"]) {
        [deviceStateKeys addObject:@"trigger_device_findmy_sound"];
    }
    if ([configuredKeys containsObject:@"trigger_media_play"]) {
        [deviceStateKeys addObject:@"trigger_media_play"];
    }
    if ([configuredKeys containsObject:@"trigger_media_pause"]) {
        [deviceStateKeys addObject:@"trigger_media_pause"];
    }
    if ([configuredKeys containsObject:@"trigger_media_track_change"]) {
        [deviceStateKeys addObject:@"trigger_media_track_change"];
    }
    for (NSString *key in @[@"trigger_device_call_incoming", @"trigger_device_call_start", @"trigger_device_call_end"]) {
        if ([configuredKeys containsObject:key]) [deviceStateKeys addObject:key];
    }
    addSection(deviceStateKeys, @"Device State", YES);
    addSection(@[@"shake"], @"Motion Gestures", NO);

    // Dynamic Sections (Hide if empty/favorited)
    addSection([[RCConfigManager sharedManager] nfcTriggerKeys], @"NFC Tags", YES);

    // WiFi Section
    NSMutableArray *wifiKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([key hasPrefix:@"wifi_"]) [wifiKeys addObject:key];
    }
    addSection(wifiKeys, @"WiFi Network Triggers", YES);

    // Bluetooth Section
    NSMutableArray *btKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([key hasPrefix:@"bt_"]) [btKeys addObject:key];
    }
    addSection(btKeys, @"Bluetooth Device Triggers", YES);

    // Add-on triggers (ADDONS.md)
    NSMutableArray *addOnKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([RCAddOnCatalog isAddOnTriggerKey:key]) [addOnKeys addObject:key];
    }
    addSection(addOnKeys, @"Add-on Triggers", YES);

    NSMutableArray *outputKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([key hasPrefix:@"output_"]) [outputKeys addObject:key];
    }
    addSection(outputKeys, @"Audio Output Triggers", YES);

    // Notification Triggers Section
    NSMutableArray *notifKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([key hasPrefix:@"notif_"] || [key hasPrefix:@"notify_"]) [notifKeys addObject:key];
    }
    addSection(notifKeys, @"Notification Triggers", YES);

    // App Launch Section
    NSMutableArray *appKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([key hasPrefix:@"app_launch_"]) [appKeys addObject:key];
    }
    addSection(appKeys, @"App Launch Triggers", YES);

    NSMutableArray *appExitKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([key hasPrefix:@"app_exit_"]) [appExitKeys addObject:key];
    }
    addSection(appExitKeys, @"App Exit Triggers", YES);

    // Scheduled Triggers Section
    NSMutableArray *schedKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([key hasPrefix:@"sched_"]) [schedKeys addObject:key];
    }
    addSection(schedKeys, @"Scheduled Triggers", YES);

    // MQTT Subscription Triggers Section
    NSMutableArray *mqttKeys = [NSMutableArray array];
    for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) {
        if ([key hasPrefix:@"mqtt_sub_"] || [key hasPrefix:@"mqtt_"]) [mqttKeys addObject:key];
    }
    addSection(mqttKeys, @"MQTT Subscription Triggers", YES);

    self.sections = sections;
    self.sectionTitles = titles;

    // Chips follow the sections; a selected section that has gone away falls back to All
    NSMutableArray *chipTitles = [NSMutableArray array];
    for (NSString *title in titles) {
        [chipTitles addObject:[title hasSuffix:@" Triggers"] ? [title substringToIndex:title.length - 9] : title];
    }
    NSMutableArray *chipIcons = [NSMutableArray array];
    for (NSString *title in titles) [chipIcons addObject:RCTriggerCategoryIcon(title) ?: [NSNull null]];
    [self.categoryBar setChipTitles:chipTitles icons:chipIcons];
    NSUInteger selected = self.selectedCategoryTitle ? [titles indexOfObject:self.selectedCategoryTitle] : NSNotFound;
    if (selected == NSNotFound) self.selectedCategoryTitle = nil;
    self.categoryBar.selectedIndex = (selected == NSNotFound) ? -1 : (NSInteger)selected;

    [self updatePauseState]; // the left button is Resume while paused, otherwise none

    [self.tableView reloadData];
    [self.grid reload];
}


- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    if ([self compactLayout]) self.grid.editing = editing;
    else [self.tableView setEditing:editing animated:animated];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
}

- (void)openSettings {
    RCSettingsViewController *settingsVC = [[RCSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)openTriggerWithKey:(NSString *)triggerKey {
    if (!triggerKey.length) return;
    RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
    [self.navigationController pushViewController:actionsVC animated:YES];
}

- (void)addNewItem {
    __weak typeof(self) weakSelf = self;
    void (^push)(UIViewController *) = ^(UIViewController *vc) {
        [weakSelf.navigationController pushViewController:vc animated:YES];
    };

    // Opens a trigger's action list in place of the New Trigger menu, in a single transition (letting
    // the menu be removed after the push left the bar buttons half-faded)
    void (^replaceMenuWith)(UIViewController *) = ^(UIViewController *vc) {
        UINavigationController *nav = weakSelf.navigationController;
        NSMutableArray *vcs = [nav.viewControllers mutableCopy];
        if ([vcs.lastObject isKindOfClass:[RCNewTriggerViewController class]]) [vcs removeLastObject];
        [vcs addObject:vc];
        [nav setViewControllers:vcs animated:YES];
    };

    // System events can only be added once; one that exists just opens
    NSMutableArray *systemEvents = [NSMutableArray array];
    for (NSArray *event in @[@[@"trigger_statusbar_two_finger_swipe_down", @"2-Finger Top Slide Down", @"hand.draw", @"Gestures"],
                             @[@"trigger_bottom_two_finger_swipe_up", @"2-Finger Bottom Slide Up", @"hand.draw", @"Gestures"],
                             @[@"trigger_device_lock", @"Device Locked", @"lock.fill", @"Device"],
                             @[@"trigger_device_unlock", @"Device Unlocked", @"lock.open.fill", @"Device"],
                             @[@"trigger_power_connect", @"Power Connected", @"bolt.fill", @"Device"],
                             @[@"trigger_power_disconnect", @"Power Disconnected", @"bolt.slash.fill", @"Device"],
                             @[@"trigger_device_rotated_landscape", @"Rotated to Landscape", @"iphone.landscape", @"Device"],
                             @[@"trigger_device_rotated_portrait", @"Rotated to Portrait", @"iphone", @"Device"],
                             @[@"trigger_carplay_connect", @"CarPlay Connected", @"car.fill", @"Device"],
                             @[@"trigger_carplay_disconnect", @"CarPlay Disconnected", @"car", @"Device"],
                             @[@"trigger_device_findmy_sound", @"Find My Sound", @"location.circle.fill", @"Device"],
                             @[@"trigger_media_play", @"Media Playing", @"play.fill", @"Media"],
                             @[@"trigger_media_pause", @"Media Paused", @"pause.fill", @"Media"],
                             @[@"trigger_media_track_change", @"Media Track Changed", @"forward.fill", @"Media"],
                             @[@"trigger_device_call_incoming", @"Incoming Call", @"phone.arrow.down.left", @"Calls"],
                             @[@"trigger_device_call_start", @"Call Started", @"phone.fill", @"Calls"],
                             @[@"trigger_device_call_end", @"Call Ended", @"phone.down.fill", @"Calls"],
                             @[@"trigger_watch_ping", @"Ping iPhone", @"applewatch.radiowaves.left.and.right", @"Apple Watch"],
                             @[@"trigger_watch_ping_hold", @"Ping iPhone (Hold)", @"applewatch.radiowaves.left.and.right", @"Apple Watch"]]) {
        NSString *key = event[0], *title = event[1];
        NSMutableDictionary *item = [@{ @"title": title, @"icon": event[2], @"section": event[3], @"handler": ^{
            if (![[[RCConfigManager sharedManager] allConfiguredTriggerKeys] containsObject:key]) {
                [[RCConfigManager sharedManager] updateTrigger:key withData:@{@"name": title, @"enabled": @YES, @"actions": @[]}];
            } else {
                NSMutableDictionary *data = [[[RCConfigManager sharedManager] triggerDataForKey:key] mutableCopy] ?: [NSMutableDictionary dictionary];
                data[@"enabled"] = @YES;
                [[RCConfigManager sharedManager] updateTrigger:key withData:data];
            }
            replaceMenuWith([[RCActionsViewController alloc] initWithTriggerKey:key]);
        } } mutableCopy];
        NSDictionary *trig = [[RCConfigManager sharedManager] triggerDataForKey:key];
        if (trig && ([trig[@"enabled"] boolValue] || [trig[@"actions"] count] > 0)) {
            item[@"detail"] = @"Added";
        }
        [systemEvents addObject:item];
    }

    NSMutableArray *items = [@[
        @{ @"title": @"NFC Tag", @"icon": @"wave.3.right", @"section": @"Nearby", @"handler": ^{ push([[RCNFCTriggerViewController alloc] init]); } },
        @{ @"title": @"Wi-Fi Network", @"icon": @"wifi", @"section": @"Nearby", @"handler": ^{ push([[RCWiFiTriggerViewController alloc] init]); } },
        @{ @"title": @"Bluetooth Device", @"icon": @"dot.radiowaves.left.and.right", @"section": @"Nearby", @"handler": ^{ push([[RCBluetoothTriggerViewController alloc] init]); } },
        @{ @"title": @"Audio Output", @"icon": @"airplayaudio", @"section": @"Nearby", @"handler": ^{ push([[RCAudioOutputTriggerViewController alloc] init]); } },
        @{ @"title": @"App Launch", @"icon": @"square.grid.2x2", @"section": @"Apps", @"handler": ^{
            RCAppPickerViewController *vc = [[RCAppPickerViewController alloc] init];
            vc.allowsMultipleApps = YES;
            vc.suppressAutoPop = YES; // We handle navigation ourselves
            vc.onAppsSelected = ^(NSArray<NSString *> *names, NSArray<NSString *> *bundleIds) {
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                NSString *triggerKey = [[RCConfigManager sharedManager] saveAppTriggerWithPrefix:@"app_launch_" names:names bundleIds:bundleIds replacing:nil];

                // Push actionsVC, then let the app picker pop (leaving [TriggersVC, ActionsVC])
                RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
                NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
                [vcs removeLastObject]; // Remove the app picker
                [vcs addObject:actionsVC];
                [self.navigationController setViewControllers:vcs animated:YES];
            };
            push(vc);
        } },
        @{ @"title": @"App Exit", @"icon": @"square.grid.2x2", @"section": @"Apps", @"handler": ^{
            RCAppPickerViewController *vc = [[RCAppPickerViewController alloc] init];
            vc.allowsMultipleApps = YES;
            vc.suppressAutoPop = YES; // We handle navigation ourselves
            vc.onAppsSelected = ^(NSArray<NSString *> *names, NSArray<NSString *> *bundleIds) {
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                NSString *triggerKey = [[RCConfigManager sharedManager] saveAppTriggerWithPrefix:@"app_exit_" names:names bundleIds:bundleIds replacing:nil];

                // Push actionsVC, then let the app picker pop (leaving [TriggersVC, ActionsVC])
                RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
                NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
                [vcs removeLastObject]; // Remove the app picker
                [vcs addObject:actionsVC];
                [self.navigationController setViewControllers:vcs animated:YES];
            };
            push(vc);
        } },
        @{ @"title": @"Notification", @"icon": @"bell.badge", @"section": @"Apps", @"handler": ^{ push([[RCNotificationTriggerViewController alloc] init]); } },
        @{ @"title": @"Scheduled Trigger", @"icon": @"calendar.badge.clock", @"section": @"Time", @"handler": ^{ push([[RCScheduledTriggerViewController alloc] init]); } },
    ] mutableCopy];
    [items addObjectsFromArray:systemEvents];
    [items addObject:@{ @"title": @"Battery Level", @"icon": [UIImage systemImageNamed:@"battery.50"] ? @"battery.50" : @"battery.25", @"section": @"Device", @"handler": ^{ push([[RCBatteryTriggerViewController alloc] init]); } }];
    [items addObject:@{ @"title": @"MQTT Topic", @"icon": @"antenna.radiowaves.left.and.right", @"section": @"Integrations", @"handler": ^{ push([[RCMQTTTriggerViewController alloc] init]); } }];
    [items addObject:@{ @"title": @"Focus", @"icon": @"moon.fill", @"section": @"Device", @"handler": ^{ push([[RCFocusTriggerViewController alloc] init]); } }];
    // Add-ons: a row for each one that has triggers, opening its list (last, so they come after
    // the built-in sections)
    for (NSDictionary *group in [RCAddOnCatalog addOnTriggerGroups]) {
        NSString *prefix = [NSString stringWithFormat:@"addon_%@_", group[@"id"]];
        NSUInteger added = 0;
        for (NSString *key in [[RCConfigManager sharedManager] allConfiguredTriggerKeys]) if ([key hasPrefix:prefix]) added++;
        NSMutableDictionary *item = [@{ @"title": group[@"title"], @"icon": group[@"icon"], @"image": group[@"image"], @"section": @"Add-ons", @"handler": ^{
            push([[RCAddOnTriggersViewController alloc] initWithAddOn:group[@"id"] title:group[@"title"]]);
        } } mutableCopy];
        if (added) item[@"detail"] = [NSString stringWithFormat:@"%lu added", (unsigned long)added];
        [items addObject:item];
    }
    [self.navigationController pushViewController:[[RCNewTriggerViewController alloc] initWithItems:items] animated:YES];
}

- (void)startNFCScan {
    RCNFCTriggerViewController *vc = [[RCNFCTriggerViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/saihgupr/RemoteCompanion"] options:@{} completionHandler:nil];
}

- (UIBezierPath *)fillPathForRect:(CGRect)rect
                            first:(BOOL)isFirst
                             last:(BOOL)isLast
                           single:(BOOL)isSingle
                     cornerRadius:(CGFloat)cornerRadius {
    if (isSingle) {
        return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius];
    }
    if (isFirst) {
        return [UIBezierPath bezierPathWithRoundedRect:rect
                                     byRoundingCorners:(UIRectCornerTopLeft | UIRectCornerTopRight)
                                           cornerRadii:CGSizeMake(cornerRadius, cornerRadius)];
    }
    if (isLast) {
        return [UIBezierPath bezierPathWithRoundedRect:rect
                                     byRoundingCorners:(UIRectCornerBottomLeft | UIRectCornerBottomRight)
                                           cornerRadii:CGSizeMake(cornerRadius, cornerRadius)];
    }
    return [UIBezierPath bezierPathWithRect:rect];
}

- (void)applySectionCardStyleToCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *config = [RCConfigManager sharedManager];
    UIColor *fillColor = [config tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIColor *selectedFillColor = [config tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    UIColor *borderColor = [config tweakColorForKey:@"borders" defaultVal:0.14];
    
    NSInteger rowCount = [self.tableView numberOfRowsInSection:indexPath.section];
    if (rowCount < 1) {
        return;
    }
    
    BOOL isSingle = (rowCount == 1);
    BOOL isFirst = (indexPath.row == 0);
    BOOL isLast = (indexPath.row == rowCount - 1);
    
    CGFloat lineWidth = 1.0;
    CGFloat cornerRadius = 12.0;
    CGFloat horizontalInset = 0.0;
    CGRect fillRect = CGRectInset(cell.bounds, horizontalInset, 0.0);
    CGRect borderRect = CGRectInset(fillRect, lineWidth * 0.5, lineWidth * 0.5);
    if (CGRectGetWidth(fillRect) <= 0 || CGRectGetHeight(fillRect) <= 0) {
        return;
    }
    if (CGRectGetWidth(borderRect) <= 0 || CGRectGetHeight(borderRect) <= 0) {
        return;
    }
    
    UIBezierPath *fillPath = [self fillPathForRect:fillRect
                                             first:isFirst
                                              last:isLast
                                            single:isSingle
                                      cornerRadius:cornerRadius];
    
    UIBezierPath *borderPath = [self fillPathForRect:borderRect
                                             first:isFirst
                                              last:isLast
                                            single:isSingle
                                      cornerRadius:cornerRadius];
    
    UIView *normalBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
    normalBackgroundView.backgroundColor = [UIColor clearColor];
    
    CAShapeLayer *normalFillLayer = [CAShapeLayer layer];
    normalFillLayer.frame = normalBackgroundView.bounds;
    normalFillLayer.path = fillPath.CGPath;
    normalFillLayer.fillColor = fillColor.CGColor;
    [normalBackgroundView.layer addSublayer:normalFillLayer];
    
    CAShapeLayer *normalBorderLayer = [CAShapeLayer layer];
    normalBorderLayer.frame = normalBackgroundView.bounds;
    normalBorderLayer.path = borderPath.CGPath;
    normalBorderLayer.fillColor = [UIColor clearColor].CGColor;
    normalBorderLayer.strokeColor = borderColor.CGColor;
    normalBorderLayer.lineWidth = lineWidth;
    
    if (!isSingle) {
        CGRect maskRect = normalBorderLayer.bounds;
        if (isFirst) {
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else if (isLast) {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - (2.0 * lineWidth));
        }
        CAShapeLayer *maskLayer = [CAShapeLayer layer];
        maskLayer.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
        normalBorderLayer.mask = maskLayer;
    }
    [normalBackgroundView.layer addSublayer:normalBorderLayer];
    
    UIView *selectedBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
    selectedBackgroundView.backgroundColor = [UIColor clearColor];
    
    CAShapeLayer *selectedFillLayer = [CAShapeLayer layer];
    selectedFillLayer.frame = selectedBackgroundView.bounds;
    selectedFillLayer.path = fillPath.CGPath;
    selectedFillLayer.fillColor = selectedFillColor.CGColor;
    [selectedBackgroundView.layer addSublayer:selectedFillLayer];
    
    CAShapeLayer *selectedBorderLayer = [CAShapeLayer layer];
    selectedBorderLayer.frame = selectedBackgroundView.bounds;
    selectedBorderLayer.path = borderPath.CGPath;
    selectedBorderLayer.fillColor = [UIColor clearColor].CGColor;
    selectedBorderLayer.strokeColor = borderColor.CGColor;
    selectedBorderLayer.lineWidth = lineWidth;
    if (!isSingle) {
        CGRect maskRect = selectedBorderLayer.bounds;
        if (isFirst) {
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else if (isLast) {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - (2.0 * lineWidth));
        }
        CAShapeLayer *maskLayer = [CAShapeLayer layer];
        maskLayer.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
        selectedBorderLayer.mask = maskLayer;
    }
    [selectedBackgroundView.layer addSublayer:selectedBorderLayer];
    
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.backgroundView = normalBackgroundView;
    cell.selectedBackgroundView = selectedBackgroundView;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    
    if (!indexPath) return;
    
    NSString *triggerKey = [self triggerKeyAtIndexPath:indexPath];
    [self runTriggerNow:triggerKey view:[self.tableView cellForRowAtIndexPath:indexPath]];
}

// Long press: runs the trigger now (as if it had fired), showing it on its row or tile
- (void)runTriggerNow:(NSString *)triggerKey view:(UIView *)view {
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSArray *actions = [config actionsForTrigger:triggerKey];
    
    if (actions.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Actions"
            message:@"No actions configured for this trigger. Tap to add actions first."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    
    if ([view isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)view;
        [cell setHighlighted:YES animated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [cell setHighlighted:NO animated:YES];
        });
    } else {
        [UIView animateWithDuration:0.15 animations:^{ view.alpha = 0.5; } completion:^(BOOL done) {
            [UIView animateWithDuration:0.25 animations:^{ view.alpha = 1; }];
        }];
    }
    
    NSString *notificationName = [NSString stringWithFormat:@"%s%@", kSimulateNotificationPrefix, triggerKey];
    
    // Slight delay to ensure haptic plays before the app is potentially obscured (e.g., by Control Center or another App)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        notify_post([notificationName UTF8String]);
    });
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.categoryBar scrollViewDidScroll:scrollView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.categoryBar layoutInScrollView:[self activeScrollView]];

    // The card backgrounds are drawn for the cell's width when it's displayed: redraw the
    // visible ones when the width changes (rotation), or they keep the old width
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width != self.cardStyleWidth) {
        self.cardStyleWidth = width;
        for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            if (cell) [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
        }
    }
}

#pragma mark - Display model

// The sections the table shows: all of them, or just the selected category
- (NSInteger)realSectionForDisplaySection:(NSInteger)section {
    if (!self.selectedCategoryTitle) return section;
    NSUInteger idx = [self.sectionTitles indexOfObject:self.selectedCategoryTitle];
    return idx == NSNotFound ? section : (NSInteger)idx;
}

- (NSInteger)displaySectionCount {
    return self.selectedCategoryTitle ? 1 : self.sections.count;
}

- (NSString *)triggerKeyAtIndexPath:(NSIndexPath *)indexPath {
    return self.sections[[self realSectionForDisplaySection:indexPath.section]][indexPath.row];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self displaySectionCount];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = _sectionTitles[[self realSectionForDisplaySection:section]];
    CGFloat height = [self tableView:tableView heightForHeaderInSection:section];
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, height)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, height - 25, tableView.bounds.size.width - 40, 20)];
    label.text = [title uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];

    // Yellow text for Favorites section
    if ([title isEqualToString:@"Favorites"]) {
        label.textColor = [UIColor colorWithRed:242/255.0 green:195/255.0 blue:80/255.0 alpha:1.0];
    } else {
        label.textColor = [UIColor secondaryLabelColor];
    }

    // The section's icon before its title, in the title's colour
    UIImage *icon = RCTriggerCategoryIcon(title);
    if (icon) {
        UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
        iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.tintColor = label.textColor;
        iconView.frame = CGRectMake(20, CGRectGetMinY(label.frame) + 1, 18, 18);
        [headerView addSubview:iconView];
        CGRect frame = label.frame;
        frame.origin.x += 24;
        frame.size.width -= 24;
        label.frame = frame;
    }

    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    // The first section sits just below the category bar. The others keep their old
    // spacing, including the 15pt sectionHeaderTopPadding they had on iOS 15+.
    if (section == 0) return 29.0f;
    CGFloat topPadding = 0;
    if (@available(iOS 15.0, *)) topPadding = 15;
    return 40.0f + topPadding;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[[self realSectionForDisplaySection:section]].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *triggerKey = [self triggerKeyAtIndexPath:indexPath];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TriggerCell"];
    if (!cell) {
        cell = [[RCTriggerCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"TriggerCell"];
    }

    BOOL wrapLongNames = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"];
    cell.textLabel.numberOfLines = wrapLongNames ? 0 : 1;
    cell.detailTextLabel.numberOfLines = wrapLongNames ? 0 : 1;
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    
    cell.textLabel.text = [config displayNameForTrigger:triggerKey];
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    cell.textLabel.textColor = [UIColor labelColor];
    
    // Add Icon with tint based on section or type?
    // Using dark gray tint for a "premium" but subtle look
    UIImage *custom = [RCAddOnCatalog isAddOnTriggerKey:triggerKey] ? [RCAddOnCatalog imageForTriggerKey:triggerKey] : nil;   // an add-on's image icon
    // The trigger's own picture: its app's icon, the phone drawing, or its symbol with a letter
    cell.imageView.image = custom ?: [self appIconForTrigger:triggerKey side:29] ?: RCTriggerIconImage(triggerKey, 22) ?: [self symbolIconForTrigger:triggerKey size:22];
    cell.imageView.tintColor = custom ? nil : [UIColor systemGrayColor];

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    // Action names joined by >
    NSArray *actions = [config actionsForTrigger:triggerKey];
    if (actions.count > 0) {
        if (actions.count == 1) {
            cell.detailTextLabel.text = [self nameForCommand:actions.firstObject truncate:NO];
        } else {
            NSMutableArray *shortNames = [NSMutableArray array];
            for (NSString *action in actions) {
                [shortNames addObject:[self nameForCommand:action truncate:YES]];
            }
            cell.detailTextLabel.text = [shortNames componentsJoinedByString:@" > "];
        }
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        // Use Monospace font for commands for better readability of code/IDs
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    } else {
        cell.detailTextLabel.text = @"Not configured";
        cell.detailTextLabel.textColor = [UIColor tertiaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13]; // Regular font for placeholder
    }
    
    // A name of the user's own: its default name leads the line under it
    if ([config customNameForTrigger:triggerKey]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [config defaultNameForTrigger:triggerKey], cell.detailTextLabel.text ?: @""];
    }

    [self applySectionCardStyleToCell:cell atIndexPath:indexPath];

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *triggerKey = [self triggerKeyAtIndexPath:indexPath];
    
    RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
    [self.navigationController pushViewController:actionsVC animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *triggerKey = [self triggerKeyAtIndexPath:indexPath];

    RCConfigManager *config = [RCConfigManager sharedManager];
    BOOL isFavorite = [config isTriggerFavorite:triggerKey];

    UIContextualAction *favoriteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
        title:isFavorite ? @"Unfavorite" : @"Favorite"
        handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [haptic impactOccurred];
            [config setTriggerFavorite:!isFavorite forTrigger:triggerKey];
            [self reloadTableData];
            completionHandler(YES);
        }];

    favoriteAction.backgroundColor = isFavorite ? [UIColor systemGrayColor] : [UIColor colorWithRed:242/255.0 green:195/255.0 blue:80/255.0 alpha:1.0];
    favoriteAction.image = [UIImage systemImageNamed:isFavorite ? @"star.slash.fill" : @"star.fill"];

    return [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *triggerKey = [self triggerKeyAtIndexPath:indexPath];

    // Only allow delete for NFC, WiFi, BT, App, Notif, Sched, MQTT, Device State, Multi-Finger triggers
    if (![self canDeleteTrigger:triggerKey]) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Delete"
        handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [[RCConfigManager sharedManager] removeTrigger:triggerKey];
            [self reloadTableData];
            completionHandler(YES);
        }];

    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_sectionTitles.count > 0 && [_sectionTitles[[self realSectionForDisplaySection:indexPath.section]] isEqualToString:@"Favorites"]) {
        return YES;
    }
    return NO;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (sourceIndexPath.section != proposedDestinationIndexPath.section) {
        NSInteger row = (proposedDestinationIndexPath.section < sourceIndexPath.section) ? 0 : [self.sections[[self realSectionForDisplaySection:sourceIndexPath.section]] count] - 1;
        return [NSIndexPath indexPathForRow:row inSection:sourceIndexPath.section];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray *favorites = [[RCConfigManager sharedManager] orderedFavorites].mutableCopy;
    NSString *movedItem = favorites[sourceIndexPath.row];
    [favorites removeObjectAtIndex:sourceIndexPath.row];
    [favorites insertObject:movedItem atIndex:destinationIndexPath.row];
    [[RCConfigManager sharedManager] setOrderedFavorites:favorites];

    NSInteger realSection = [self realSectionForDisplaySection:sourceIndexPath.section];
    NSMutableArray *sectionData = [_sections[realSection] mutableCopy];
    [sectionData removeObjectAtIndex:sourceIndexPath.row];
    [sectionData insertObject:movedItem atIndex:destinationIndexPath.row];

    NSMutableArray *mutableSections = [_sections mutableCopy];
    mutableSections[realSection] = sectionData;
    _sections = mutableSections;
}

#pragma mark - Deleting, app icons

// The triggers that can be deleted: the ones made for a tag, network, device, app, notification,
// schedule, topic or state (the button and gesture triggers are always there)
- (BOOL)canDeleteTrigger:(NSString *)triggerKey {
    return !(![triggerKey hasPrefix:@"nfc_"] && ![triggerKey hasPrefix:@"wifi_"] && ![triggerKey hasPrefix:@"bt_"] && ![triggerKey hasPrefix:@"app_launch_"] && ![triggerKey hasPrefix:@"app_exit_"] && ![triggerKey hasPrefix:@"output_"] && ![triggerKey hasPrefix:@"notif_"] && ![triggerKey hasPrefix:@"notify_"] && ![triggerKey hasPrefix:@"sched_"] && ![triggerKey hasPrefix:@"mqtt_"] && ![triggerKey hasPrefix:@"mqtt_sub_"] && ![triggerKey hasPrefix:@"trigger_device_"] && ![triggerKey hasPrefix:@"trigger_media_"] && ![triggerKey hasPrefix:@"trigger_power_"] && ![triggerKey hasPrefix:@"trigger_carplay_"] && ![triggerKey hasPrefix:@"trigger_watch_"] && ![triggerKey containsString:@"two_finger"] && ![RCAddOnCatalog isAddOnTriggerKey:triggerKey]);
}

// A created trigger's letter, telling NFC tags, networks and devices of one kind apart: the first
// of the user's name for it, else of its network, device or topic. None for an unnamed NFC tag or
// schedule (their default names don't say anything a letter could).
+ (NSString *)letterForTrigger:(NSString *)triggerKey {
    BOOL created = NO;
    for (NSString *prefix in @[@"nfc_", @"wifi_", @"bt_", @"output_", @"notif_", @"notify_", @"sched_", @"mqtt_"]) {
        if ([triggerKey hasPrefix:prefix]) { created = YES; break; }
    }
    if (!created) return nil;
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSString *source = [config customNameForTrigger:triggerKey];
    if (!source) {
        NSString *name = [config defaultNameForTrigger:triggerKey];
        if ([triggerKey hasPrefix:@"wifi_"] || [triggerKey hasPrefix:@"bt_"] || [triggerKey hasPrefix:@"output_"]) {
            // "Connected to Home WiFi", "Disconnected from AirPods Pro": what comes after
            for (NSString *joint in @[@" to ", @" from "]) {
                NSRange range = [name rangeOfString:joint];
                if (range.location != NSNotFound) { source = [name substringFromIndex:NSMaxRange(range)]; break; }
            }
        } else if ([triggerKey hasPrefix:@"mqtt_"] || [triggerKey hasPrefix:@"notif_"] || [triggerKey hasPrefix:@"notify_"]) {
            // "MQTT: home/door (OPEN)": the topic; a name given when it was made: that name
            NSRange colon = [name rangeOfString:@": "];
            source = colon.location != NSNotFound ? [name substringFromIndex:NSMaxRange(colon)] : name;
        }
    }
    for (NSUInteger i = 0; i < source.length; i++) {
        unichar c = [source characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) return [[source substringWithRange:NSMakeRange(i, 1)] uppercaseString];
    }
    return nil;
}

// A trigger's icon anywhere it's listed (Running, Stop Trigger): an add-on's picture, an app's
// icon, the phone drawing, or its symbol with a created trigger's letter
+ (UIImage *)iconImageForTrigger:(NSString *)triggerKey size:(CGFloat)size {
    UIImage *custom = nil;
    if (custom) return custom;
    for (NSString *prefix in @[@"app_launch_", @"app_exit_"]) {
        if ([triggerKey hasPrefix:prefix]) {
            UIImage *app = RCAppTriggerIconImage([triggerKey substringFromIndex:prefix.length], size + 7, [prefix isEqualToString:@"app_exit_"]);
            if (app) return app;
        }
    }
    return RCTriggerIconImage(triggerKey, size) ?: RCTriggerLetterImage([RCTriggersViewController iconNameForTrigger:triggerKey], [RCTriggersViewController letterForTrigger:triggerKey], size);
}

// A trigger's plain symbol, with its letter when it's a created one
- (UIImage *)symbolIconForTrigger:(NSString *)triggerKey size:(CGFloat)size {
    return RCTriggerLetterImage([RCTriggersViewController iconNameForTrigger:triggerKey], [RCTriggersViewController letterForTrigger:triggerKey], size);
}

// A trigger's own picture (an add-on's), or nil
- (UIImage *)customIconForTrigger:(NSString *)triggerKey {
    return nil;
}

// An App Launch or App Exit trigger's app icon (its first app's) with its launch or exit badge, or nil
- (UIImage *)appIconForTrigger:(NSString *)triggerKey side:(CGFloat)side {
    for (NSString *prefix in @[@"app_launch_", @"app_exit_"]) {
        if ([triggerKey hasPrefix:prefix]) return RCAppTriggerIconImage([triggerKey substringFromIndex:prefix.length], side, [prefix isEqualToString:@"app_exit_"]);
    }
    return nil;
}

#pragma mark - Compact grid

// Compact Sections: Hide (and no category picked) shows every trigger in one grid, without titles
- (BOOL)gridIsOneSection {
    return RCLayoutIsCompact(RCLayoutTriggerSections) && !self.selectedCategoryTitle;
}

- (NSInteger)gridSectionCount {
    if ([self gridIsOneSection]) return self.sections.count ? 1 : 0;
    return [self displaySectionCount];
}

- (NSString *)gridTitleForSection:(NSInteger)section {
    if ([self gridIsOneSection]) return @"";
    return self.sectionTitles[[self realSectionForDisplaySection:section]];
}

- (NSArray<NSString *> *)gridKeysInSection:(NSInteger)section {
    if ([self gridIsOneSection]) {
        NSMutableArray *all = [NSMutableArray array];
        for (NSArray *keys in self.sections) [all addObjectsFromArray:keys];
        return all;
    }
    NSInteger real = [self realSectionForDisplaySection:section];
    return real < (NSInteger)self.sections.count ? self.sections[real] : @[];
}

- (BOOL)gridSectionIsFavorites:(NSInteger)section {
    return [[self gridTitleForSection:section] isEqualToString:@"Favorites"];
}

- (NSString *)gridNameForTrigger:(NSString *)key {
    return [[RCConfigManager sharedManager] displayNameForTrigger:key];
}

- (NSString *)gridDetailForTrigger:(NSString *)key {
    RCConfigManager *config = [RCConfigManager sharedManager];
    return [config customNameForTrigger:key] ? [config defaultNameForTrigger:key] : nil;
}

- (NSString *)gridIconForTrigger:(NSString *)key {
    return [RCTriggersViewController iconNameForTrigger:key];
}

- (UIImage *)gridImageForTrigger:(NSString *)key {
    UIImage *custom = [self customIconForTrigger:key];
    if (custom) return custom;
    UIImage *addOnImage = [RCAddOnCatalog isAddOnTriggerKey:key] ? [RCAddOnCatalog imageForTriggerKey:key] : nil;
    return addOnImage ?: [self appIconForTrigger:key side:30] ?: RCTriggerIconImage(key, 26) ?: [self symbolIconForTrigger:key size:26];
}

- (NSInteger)gridActionCountForTrigger:(NSString *)key {
    return (NSInteger)[[RCConfigManager sharedManager] actionsForTrigger:key].count;
}

- (BOOL)gridTriggerIsFavorite:(NSString *)key {
    return [[RCConfigManager sharedManager] isTriggerFavorite:key];
}

- (BOOL)gridCanDeleteTrigger:(NSString *)key {
    return [self canDeleteTrigger:key];
}

- (void)gridOpenTrigger:(NSString *)key {
    RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:key];
    [self.navigationController pushViewController:actionsVC animated:YES];
}

- (void)gridRunTrigger:(NSString *)key fromView:(UIView *)view {
    [self runTriggerNow:key view:view];
}

- (void)gridToggleFavorite:(NSString *)key {
    RCConfigManager *config = [RCConfigManager sharedManager];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [config setTriggerFavorite:![config isTriggerFavorite:key] forTrigger:key];
    [self reloadTableData];
}

// Asks first: deleting a trigger takes its actions with it
- (void)gridDeleteTrigger:(NSString *)key fromView:(UIView *)view {
    NSString *name = [[RCConfigManager sharedManager] displayNameForTrigger:key];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete “%@”?", name]
                                                                   message:@"Its actions are deleted too."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete Trigger" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        [[RCConfigManager sharedManager] removeTrigger:key];
        [weakSelf reloadTableData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = view ?: self.view;
    alert.popoverPresentationController.sourceRect = view ? view.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)gridMoveFavoriteFrom:(NSInteger)from to:(NSInteger)to {
    // The favorites as shown (Favorites is the first section when there are any)
    NSUInteger section = [self.sectionTitles indexOfObject:@"Favorites"];
    if (section == NSNotFound) return;
    NSMutableArray *favorites = [self.sections[section] mutableCopy];
    if (from < 0 || from >= (NSInteger)favorites.count || to < 0 || to >= (NSInteger)favorites.count) return;
    NSString *moved = favorites[from];
    [favorites removeObjectAtIndex:from];
    [favorites insertObject:moved atIndex:to];
    [[RCConfigManager sharedManager] setOrderedFavorites:favorites];
    [self reloadTableData];
}

- (void)gridDidScroll:(UIScrollView *)scrollView {
    [self.categoryBar scrollViewDidScroll:scrollView];
}

@end
