#import "RCActionPickerViewController.h"
#import "RCServerClient.h"
#import "RCDevicePickerViewController.h"
#import "RCFocusPickerViewController.h"
#import "RCConfigManager.h"
#import "RCHAEntityPickerViewController.h"
#import "RCKMMacroPickerViewController.h"
#import "RCCategoryBar.h"

@interface RCActionPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredActions;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIAlertController *activeAlert;
@property (nonatomic, assign) BOOL isWaitingForTapRecord;
// Category bar: -1 = All, otherwise an index into sections / sectionTitles
@property (nonatomic, assign) NSInteger selectedCategory;
@property (nonatomic, strong) RCCategoryBar *categoryBar;
@end

@implementation RCActionPickerViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) _selectedCategory = -1;
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // Elegant grey tint
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    
    self.title = @"Select Action";
    
    // Category bar floating below the search bar
    [self rebuildSections];
    self.categoryBar = [self makeCategoryBar];
    [self.categoryBar attachToTableView:self.tableView];
    if (@available(iOS 15.0, *)) {
        // Spacing above headers is built into the header views instead (see
        // heightForHeaderInSection:), so the first one can sit close to the category bar
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    // Use proper Cancel button style
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self
        action:@selector(cancel)];
    
    // Setup Search
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Actions";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    
    [self rebuildSections];
    
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ActionCell"];
    self.tableView.rowHeight = 60; // Increased touch target
    
    [self applyTweaks];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuildSections];
    [self.tableView reloadData];
}

- (void)rebuildSections {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    
    _sectionTitles = @[@"Media", @"Sound", @"Capture", @"Apps & Navigation", @"Device Controls", @"Connectivity", @"System", @"Integrations", @"Scripting & Logic"];
    
    _sections = @[
        // Media
        ({
            NSMutableArray *media = [NSMutableArray arrayWithArray:@[
                @{ @"name": @"Play", @"command": @"play", @"icon": @"play.fill" },
                @{ @"name": @"Pause", @"command": @"pause", @"icon": @"pause.fill" },
                @{ @"name": @"Play/Pause", @"command": @"playpause", @"icon": @"playpause.fill" },
                @{ @"name": @"Next Track", @"command": @"next", @"icon": @"forward.fill" },
                @{ @"name": @"Previous Track", @"command": @"prev", @"icon": @"backward.fill" }
            ]];
            NSArray *audioStreamPaths = @[
                @"/Applications/AudioReceiver.app",
                @"/Applications/AudioStream.app",
                @"/var/jb/Applications/AudioReceiver.app",
                @"/var/jb/Applications/AudioStream.app"
            ];
            BOOL audioStreamInstalled = NO;
            NSFileManager *fm = [NSFileManager defaultManager];
            for (NSString *p in audioStreamPaths) {
                if ([fm fileExistsAtPath:p]) { audioStreamInstalled = YES; break; }
            }
            if (!audioStreamInstalled) {
                Class proxyClass = NSClassFromString(@"LSApplicationProxy");
                if (proxyClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:@"com.saihgupr.audiostream"];
                    if (proxy) {
                        NSString *name = [proxy performSelector:@selector(localizedName)];
                        if (name.length > 0) audioStreamInstalled = YES;
                    }
#pragma clang diagnostic pop
                }
            }
            if (audioStreamInstalled) {
                [media addObject:@{ @"name": @"Queue Current Album", @"command": @"queue album", @"icon": @"music.note.list" }];
                [media addObject:@{ @"name": @"Queue Artist", @"command": @"queue artist", @"icon": @"music.mic" }];
                [media addObject:@{ @"name": @"Shuffle All Songs", @"command": @"shuffle all songs", @"icon": @"shuffle" }];
                [media addObject:@{ @"name": @"Delete Currently Playing Song", @"command": @"delete current song", @"icon": @"trash" }];
            }
            media;
        }),
        // Sound
        @[
            @{ @"name": @"Volume Up", @"command": @"volume up", @"icon": @"speaker.wave.3.fill" },
            @{ @"name": @"Volume Down", @"command": @"volume down", @"icon": @"speaker.wave.1.fill" },
            @{ @"name": @"Set Volume...", @"command": @"__SET_VOLUME__", @"icon": @"slider.horizontal.3" },
            @{ @"name": @"Set Ringer Volume...", @"command": @"__SET_RINGER_VOLUME__", @"icon": @"bell.fill" },
            @{ @"name": @"Mute", @"command": @"mute toggle", @"icon": @"speaker.slash.fill" },
            @{ @"name": @"Noise Control", @"command": @"anc on", @"icon": @"ear" },
            @{ @"name": @"Silent Mode", @"command": @"ringer toggle", @"icon": @"bell.slash.fill" },
            @{ @"name": @"Silent Vibration", @"command": @"vibration silent-toggle", @"icon": @"bell.slash" },
            @{ @"name": @"Ring Vibration", @"command": @"vibration ring-toggle", @"icon": @"bell" }
        ],
        // Capture
        @[
            @{ @"name": @"Screenshot", @"command": @"screenshot", @"icon": @"camera.viewfinder" },
            @{ @"name": @"Screen Recording", @"command": @"screenrecord toggle", @"icon": @"record.circle.fill" },
            @{ @"name": @"Open Camera...", @"command": @"__CAMERA_PICKER__", @"icon": @"camera.fill" },
            @{ @"name": @"Open Video Camera...", @"command": @"__CAMERA_VIDEO_PICKER__", @"icon": @"video.fill" },
            @{ @"name": @"Camera Shutter / Snap", @"command": @"camera shutter", @"icon": @"camera.circle.fill" },
            @{ @"name": @"Camera Record Toggle", @"command": @"camera record", @"icon": @"video.circle.fill" }
        ],
        // Apps & Navigation
        @[
            @{ @"name": @"Open App...", @"command": @"__OPEN_APP__", @"icon": @"square.grid.2x2.fill" },
            @{ @"name": @"Kill App...", @"command": @"__KILL_APP__", @"icon": @"xmark.square.fill" },
            @{ @"name": @"Home Button", @"command": @"home", @"icon": @"house.fill" },
            @{ @"name": @"App Switcher", @"command": @"switcher", @"icon": @"square.stack.3d.up.fill" },
            @{ @"name": @"Previous App", @"command": @"previous app", @"icon": @"arrow.uturn.backward" },
            @{ @"name": @"Control Center", @"command": @"open control center", @"icon": @"switch.2" },
            @{ @"name": @"Activate Siri", @"command": @"siri", @"icon": @"mic.circle.fill" }
        ],
        // Device Controls
        @[
            @{ @"name": @"Appearance", @"command": @"appearance toggle", @"icon": @"circle.lefthalf.fill" },
            @{ @"name": @"Set Brightness...", @"command": @"__SET_BRIGHTNESS__", @"icon": @"sun.max.fill" },
            @{ @"name": @"Flashlight", @"command": @"flashlight toggle", @"icon": @"flashlight.on.fill" },
            @{ @"name": @"Rotation Lock", @"command": @"rotate toggle", @"icon": @"lock.rotation" },
            @{ @"name": @"Lock Device", @"command": @"lock", @"icon": @"lock.fill" },
            @{ @"name": @"Unlock Device", @"command": @"unlock", @"icon": @"lock.open.fill" },
            @{ @"name": @"Do Not Disturb", @"command": @"dnd toggle", @"icon": @"moon.circle.fill" },
            @{ @"name": @"Set Focus...", @"command": @"__FOCUS__", @"icon": @"moon.circle" },
            @{ @"name": @"Low Power Mode", @"command": @"low power toggle", @"icon": @"battery.25" },
            @{ @"name": @"Auto-Lock", @"command": @"autolock toggle", @"icon": @"timer" }
        ],
        // Connectivity
        @[
            @{ @"name": @"Wi-Fi", @"command": @"wifi toggle", @"icon": @"wifi" },
            @{ @"name": @"Cellular Data", @"command": @"cellular toggle", @"icon": @"antenna.radiowaves.left.and.right" },
            @{ @"name": @"Bluetooth", @"command": @"bluetooth toggle", @"icon": @"bolt.horizontal.fill" },
            @{ @"name": @"Location Services", @"command": @"location toggle", @"icon": @"location.fill" },
            @{ @"name": @"Airplane Mode", @"command": @"airplane toggle", @"icon": @"airplane" },
            @{ @"name": @"Connect Bluetooth...", @"command": @"__BT_CONNECT__", @"icon": @"link" },
            @{ @"name": @"Disconnect Bluetooth...", @"command": @"__BT_DISCONNECT__", @"icon": @"xmark.circle" },
            @{ @"name": @"Connect AirPlay...", @"command": @"__AIRPLAY_CONNECT__", @"icon": @"airplayaudio" },
            @{ @"name": @"Disconnect AirPlay", @"command": @"airplay disconnect", @"icon": @"airplayaudio.badge.exclamationmark" }
        ],
        // System
        @[
            @{ @"name": @"Respring Device", @"command": @"respring", @"icon": @"memories" },
            @{ @"name": @"Safe Mode", @"command": @"safemode", @"icon": @"shield.slash.fill" },
            @{ @"name": @"Soft Reboot (ldrestart)", @"command": @"ldrestart", @"icon": @"arrow.clockwise" },
            @{ @"name": @"Userspace Reboot", @"command": @"userspace-reboot", @"icon": @"arrow.clockwise.circle" },
            @{ @"name": @"Refresh Icon Cache (uicache)", @"command": @"uicache", @"icon": @"square.grid.2x2" }
        ],
        // Integrations
        ({
            NSMutableArray *integrations = [NSMutableArray array];
            if (cm.haEnabled) {
                [integrations addObject:@{ @"name": @"Home Assistant: Control Entity...", @"command": @"__HA_PICKER__", @"icon": @"lightbulb.fill" }];
            }
            if (cm.kmEnabled) {
                [integrations addObject:@{ @"name": @"Keyboard Maestro: Trigger Macro...", @"command": @"__KM_TRIGGER__", @"icon": @"command" }];
            }
            if (cm.mqttEnabled) {
                [integrations addObject:@{ @"name": @"MQTT: Publish Topic...", @"command": @"__MQTT_PUBLISH__", @"icon": @"dot.radiowaves.left.and.right" }];
            }
            [integrations addObject:@{ @"name": @"Shortcuts: Run Shortcut...", @"command": @"__SHORTCUT_PICKER__", @"icon": @"wand.and.stars" }];
            NSArray *sneakyPaths = @[
                @"/Library/MobileSubstrate/DynamicLibraries/SneakyCam.dylib",
                @"/Library/MobileSubstrate/DynamicLibraries/sneakycam.dylib",
                @"/Library/MobileSubstrate/DynamicLibraries/SneakyCam.plist",
                @"/Library/MobileSubstrate/DynamicLibraries/sneakycam.plist",
                @"/usr/lib/TweakInject/SneakyCam.dylib",
                @"/usr/lib/TweakInject/sneakycam.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/SneakyCam.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/sneakycam.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/SneakyCam.plist",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/sneakycam.plist",
                @"/var/jb/usr/lib/TweakInject/SneakyCam.dylib",
                @"/var/jb/usr/lib/TweakInject/sneakycam.dylib",
                @"/Library/PreferenceBundles/SneakyCamPrefs.bundle",
                @"/var/jb/Library/PreferenceBundles/SneakyCamPrefs.bundle"
            ];
            BOOL sneakyInstalled = NO;
            NSFileManager *fm = [NSFileManager defaultManager];
            for (NSString *p in sneakyPaths) {
                if ([fm fileExistsAtPath:p]) { sneakyInstalled = YES; break; }
            }
            if (sneakyInstalled) {
                [integrations addObject:@{ @"name": @"SneakyCam: Take Photo", @"command": @"sneakycam photo", @"icon": @"camera.aperture" }];
                [integrations addObject:@{ @"name": @"SneakyCam: Toggle Video", @"command": @"sneakycam video", @"icon": @"eye.slash.fill" }];
            }
            NSArray *snapperPaths = @[
                @"/Library/MobileSubstrate/DynamicLibraries/Snapper3.dylib",
                @"/Library/MobileSubstrate/DynamicLibraries/snapper3.dylib",
                @"/Library/MobileSubstrate/DynamicLibraries/Snapper2.dylib",
                @"/Library/MobileSubstrate/DynamicLibraries/snapper2.dylib",
                @"/Library/MobileSubstrate/DynamicLibraries/Snapper3.plist",
                @"/Library/MobileSubstrate/DynamicLibraries/snapper3.plist",
                @"/Library/MobileSubstrate/DynamicLibraries/Snapper2.plist",
                @"/Library/MobileSubstrate/DynamicLibraries/snapper2.plist",
                @"/usr/lib/TweakInject/Snapper3.dylib",
                @"/usr/lib/TweakInject/snapper3.dylib",
                @"/usr/lib/TweakInject/Snapper2.dylib",
                @"/usr/lib/TweakInject/snapper2.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/Snapper3.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/snapper3.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/Snapper2.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/snapper2.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/Snapper3.plist",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/snapper3.plist",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/Snapper2.plist",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/snapper2.plist",
                @"/var/jb/usr/lib/TweakInject/Snapper3.dylib",
                @"/var/jb/usr/lib/TweakInject/snapper3.dylib",
                @"/var/jb/usr/lib/TweakInject/Snapper2.dylib",
                @"/var/jb/usr/lib/TweakInject/snapper2.dylib",
                @"/Library/PreferenceBundles/Snapper3Preferences.bundle",
                @"/var/jb/Library/PreferenceBundles/Snapper3Preferences.bundle",
                @"/Library/ControlCenter/Bundles/Snapper3CCSupportNormal.bundle",
                @"/var/jb/Library/ControlCenter/Bundles/Snapper3CCSupportNormal.bundle"
            ];
            BOOL snapperInstalled = NO;
            for (NSString *p in snapperPaths) {
                if ([fm fileExistsAtPath:p]) { snapperInstalled = YES; break; }
            }
            if (snapperInstalled) {
                [integrations addObject:@{ @"name": @"Snapper: Open Area", @"command": @"snapper open", @"icon": @"crop" }];
                [integrations addObject:@{ @"name": @"Snapper: Freeze Screen", @"command": @"snapper freeze", @"icon": @"snowflake" }];
                [integrations addObject:@{ @"name": @"Snapper: Instant Snap", @"command": @"snapper instant", @"icon": @"bolt.fill" }];
                [integrations addObject:@{ @"name": @"Snapper: Close All", @"command": @"snapper close", @"icon": @"xmark.rectangle.fill" }];
            }
            [integrations addObject:@{ @"name": @"AudioMix: Toggle", @"command": @"audiomix toggle", @"icon": @"music.note" }];
            integrations;
        }),
        // Scripting & Logic
        @[
            @{ @"name": @"Custom Lua Script", @"command": @"__LUA_SCRIPT__", @"icon": @"scroll.fill" },
            @{ @"name": @"If Condition...", @"command": @"__IF_CONDITION__", @"icon": @"arrow.triangle.branch" },
            @{ @"name": @"Delay", @"command": @"__DELAY__", @"icon": @"hourglass" },
            @{ @"name": @"Terminal Command", @"command": @"__CUSTOM__", @"icon": @"terminal.fill" },
            @{ @"name": @"Toast...", @"command": @"__TOAST__", @"icon": @"text.bubble.fill" },
            @{ @"name": @"Haptic Feedback", @"command": @"haptic", @"icon": @"hand.tap.fill" }
        ]
    ];

    // The vibration settings as this iOS version's Settings shows them: iOS 17's one Haptics
    // menu in place of the two switches, or the switches by their name for this version
    NSMutableArray *sections = [NSMutableArray array];
    for (NSArray *section in _sections) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *item in section) {
            NSString *command = item[@"command"];
            // Focus modes came with iOS 15
            if ([command isEqualToString:@"__FOCUS__"] && ![RCConfigManager supportsFocus]) continue;
            BOOL silent = [command isEqualToString:@"vibration silent-toggle"], ring = [command isEqualToString:@"vibration ring-toggle"];
            if (!silent && !ring) { [items addObject:item]; continue; }
            if ([RCConfigManager usesHapticsMenu]) {
                if (silent) [items addObject:@{ @"name": @"Haptics", @"command": @"haptics always", @"icon": @"iphone.radiowaves.left.and.right" }];
                continue;
            }
            NSMutableDictionary *renamed = [item mutableCopy];
            renamed[@"name"] = [RCConfigManager vibrationNameForSilentMode:silent];
            [items addObject:renamed];
        }
        [sections addObject:items];
    }
    _sections = sections;
}

- (NSArray<NSArray<NSDictionary *> *> *)catalogSections {
    [self rebuildSections];
    return _sections;
}

- (NSArray<NSString *> *)catalogSectionTitles {
    [self rebuildSections];
    return _sectionTitles;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *pickerBG = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = pickerBG;
    self.tableView.backgroundColor = pickerBG;
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    [self.tableView reloadData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self applyTweaks];
        }
    }
}

#pragma mark - Category bar

// All + one chip per catalog section. Tapping one shows only that section;
// search then filters within it.
- (RCCategoryBar *)makeCategoryBar {
    RCCategoryBar *bar = [[RCCategoryBar alloc] initWithWidth:self.view.bounds.size.width];
    [bar setChipTitles:self.sectionTitles];
    bar.selectedIndex = self.selectedCategory;
    __weak typeof(self) weakSelf = self;
    bar.onSelect = ^(NSInteger index) {
        weakSelf.selectedCategory = index;
        [weakSelf updateSearchResultsForSearchController:weakSelf.searchController];
    };
    return bar;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.categoryBar scrollViewDidScroll:scrollView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.categoryBar layoutInScrollView:self.tableView];
}

#pragma mark - Display model

- (BOOL)isSearching {
    return self.searchController.isActive && self.searchController.searchBar.text.length > 0;
}

- (BOOL)hasCategory {
    return self.selectedCategory >= 0 && self.selectedCategory < (NSInteger)_sections.count;
}

// What the table shows: search results, the selected category, or everything
- (NSArray<NSArray<NSDictionary *> *> *)displaySections {
    if ([self isSearching]) return @[self.filteredActions ?: @[]];
    if ([self hasCategory]) return @[_sections[self.selectedCategory]];
    return _sections;
}

- (NSString *)displayTitleForSection:(NSInteger)section {
    if ([self isSearching]) return [self hasCategory] ? [NSString stringWithFormat:@"%@ Results", _sectionTitles[self.selectedCategory]] : @"Search Results";
    if ([self hasCategory]) return _sectionTitles[self.selectedCategory];
    return _sectionTitles[section];
}

- (NSDictionary *)actionAtIndexPath:(NSIndexPath *)indexPath {
    return [self displaySections][indexPath.section][indexPath.row];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self displaySections].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self displayTitleForSection:section];
    CGFloat height = [self tableView:tableView heightForHeaderInSection:section];
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, height)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, height - 25, tableView.bounds.size.width - 40, 20)];
    label.text = [title uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
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
    return [self displaySections][section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell" forIndexPath:indexPath];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    
    NSDictionary *action = [self actionAtIndexPath:indexPath];
    cell.textLabel.text = action[@"name"];
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.masksToBounds = YES; // Ensure content doesn't overflow rounded corners if any
    
    cell.textLabel.textColor = [UIColor labelColor];
    
    if (action[@"icon"]) {
        NSString *iconName = action[@"icon"];
        if (@available(iOS 15.0, *)) {
            // Use modern icon
        } else {
            if ([iconName isEqualToString:@"ear.badge.checkmark"]) {
                iconName = @"ear";
            }
        }
        cell.imageView.image = [UIImage systemImageNamed:iconName];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
    }
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    
    // Add disclosure for items requiring input
    NSString *cmd = action[@"command"];
    if ([cmd isEqualToString:@"__SET_VOLUME__"] || 
        [cmd isEqualToString:@"__SET_RINGER_VOLUME__"] || 
        [cmd isEqualToString:@"__SET_BRIGHTNESS__"] || 
        [cmd isEqualToString:@"__BT_CONNECT__"] || 
        [cmd isEqualToString:@"__BT_DISCONNECT__"] || 
        [cmd isEqualToString:@"__AIRPLAY_CONNECT__"] || 
        [cmd isEqualToString:@"__FOCUS__"] || 
        [cmd isEqualToString:@"__SHORTCUT_PICKER__"] || 
        [cmd isEqualToString:@"__OPEN_APP__"] || 
        [cmd isEqualToString:@"__KILL_APP__"] || 
        [cmd isEqualToString:@"__LUA_SCRIPT__"] || 
        [cmd isEqualToString:@"__TOAST__"] || 
        [cmd isEqualToString:@"__IF_CONDITION__"] ||
        [cmd isEqualToString:@"__DELAY__"] ||
        [cmd isEqualToString:@"__CUSTOM__"] ||
        [cmd isEqualToString:@"__HA_PICKER__"] ||
        [cmd isEqualToString:@"__KM_TRIGGER__"] ||
        [cmd isEqualToString:@"__TAP__"] ||
        [cmd isEqualToString:@"__HOLD__"] ||
        [cmd isEqualToString:@"__SWIPE__"]) {
        
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *action = [self actionAtIndexPath:indexPath];
    NSString *command = action[@"command"];
    

    if ([command isEqualToString:@"__SET_VOLUME__"] || [command isEqualToString:@"__SET_RINGER_VOLUME__"] || [command isEqualToString:@"__SET_BRIGHTNESS__"] || [command isEqualToString:@"__SET_FLASHLIGHT__"]) {
        [self handleValueInputForCommand:command];
        return;
    }
    
    // Touch gesture handlers
    if ([command isEqualToString:@"__TAP__"]) {
        [self handleTouchCoordInputWithTitle:@"Tap" placeholder:@"x y  (e.g. 195 422)" build:^NSString *(NSString *v) {
            return [NSString stringWithFormat:@"tap %@", v];
        }];
        return;
    }
    
    if ([command isEqualToString:@"__HOLD__"]) {
        [self handleTouchCoordInputWithTitle:@"Hold" placeholder:@"x y ms  (e.g. 195 422 800)" build:^NSString *(NSString *v) {
            return [NSString stringWithFormat:@"hold %@", v];
        }];
        return;
    }
    
    if ([command isEqualToString:@"__SWIPE__"]) {
        [self handleTouchCoordInputWithTitle:@"Custom Swipe" placeholder:@"x1 y1 x2 y2  (e.g. 195 700 195 200)" build:^NSString *(NSString *v) {
            return [NSString stringWithFormat:@"swipe %@", v];
        }];
        return;
    }
    
    // Existing special handlers
    if ([command isEqualToString:@"__AIRPLAY_CONNECT__"]) {
        [self handleAirPlayConnect];
        return;
    }
    
    if ([command isEqualToString:@"__BT_CONNECT__"]) {
        [self handleBluetoothConnect];
        return;
    }

    if ([command isEqualToString:@"__FOCUS__"]) {
        [self handleFocus];
        return;
    }
    
    if ([command isEqualToString:@"__BT_DISCONNECT__"]) {
        [self handleBluetoothDisconnect];
        return;
    }

    if ([command isEqualToString:@"__HA_PICKER__"]) {
        [self handleHAPicker];
        return;
    }

    if ([command isEqualToString:@"__KM_TRIGGER__"]) {
        [self handleKMTrigger];
        return;
    }

    if ([command isEqualToString:@"__MQTT_PUBLISH__"]) {
        [self handleMQTTPublish];
        return;
    }

    if ([command isEqualToString:@"__CAMERA_PICKER__"]) {
        [self handleCameraPicker:NO];
        return;
    }

    if ([command isEqualToString:@"__CAMERA_VIDEO_PICKER__"]) {
        [self handleCameraPicker:YES];
        return;
    }

    if (self.onActionSelected) {
        self.onActionSelected(command);
    }
    
    if (self.searchController.isActive) {
        // Dismiss search first, then self (or just self which now dismisses search? No, we need self gone.)
        // Robust pattern: Dismiss search (no animation), then dismiss self.
        [self.searchController dismissViewControllerAnimated:NO completion:^{
            [self dismissViewControllerAnimated:YES completion:nil];
        }];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)handleCameraPicker:(BOOL)isVideo {
    NSDictionary *toggleInfo = [[RCConfigManager sharedManager] toggleInfoForCommand:isVideo ? @"camera video 2x" : @"camera photo"];
    if (!toggleInfo) return;
    
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:toggleInfo[@"name"]
                                                                   message:@"Select desired mode/lens"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSArray *suffixes = toggleInfo[@"suffixes"];
    NSArray *displaySuffixes = toggleInfo[@"displaySuffixes"];
    NSString *canonicalPrefix = toggleInfo[@"prefixes"][0];
    
    __weak typeof(self) weakSelf = self;
    for (NSUInteger idx = 0; idx < suffixes.count; idx++) {
        NSString *suffix = suffixes[idx];
        NSString *displaySuffix = displaySuffixes[idx];
        
        [sheet addAction:[UIAlertAction actionWithTitle:displaySuffix
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            NSString *chosenCmd = [NSString stringWithFormat:@"%@%@", canonicalPrefix, suffix];
            if (strongSelf.onActionSelected) {
                strongSelf.onActionSelected(chosenCmd);
            }
            if (strongSelf.searchController.isActive) {
                [strongSelf.searchController dismissViewControllerAnimated:NO completion:^{
                    [strongSelf dismissViewControllerAnimated:YES completion:nil];
                }];
            } else {
                [strongSelf dismissViewControllerAnimated:YES completion:nil];
            }
        }]];
    }
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)handleTouchCoordInputWithTitle:(NSString *)title
                           placeholder:(NSString *)placeholder
                                 build:(NSString *(^)(NSString *))build {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                    message:placeholder
                                                             preferredStyle:UIAlertControllerStyleAlert];
    self.activeAlert = alert;
    self.isWaitingForTapRecord = NO;
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        tf.placeholder = placeholder;
    }];
    
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        self.activeAlert = nil;
        self.isWaitingForTapRecord = NO;
        NSString *val = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!val.length) return;
        NSString *cmd = build(val);
        if (self.onActionSelected) self.onActionSelected(cmd);
        if (self.searchController.isActive) {
            [self.searchController dismissViewControllerAnimated:NO completion:^{
                [self dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        self.activeAlert = nil;
        self.isWaitingForTapRecord = NO;
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    }];
    
    UIAlertAction *record = [UIAlertAction actionWithTitle:@"Record Tap" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        self.isWaitingForTapRecord = YES;
        [[RCServerClient sharedClient] executeCommand:@"taprecord" completion:^(NSString * _Nullable output, NSError * _Nullable error) {}];
        
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wundeclared-selector"
        if ([[UIApplication sharedApplication] respondsToSelector:@selector(suspend)]) {
            [[UIApplication sharedApplication] performSelector:@selector(suspend)];
        }
        #pragma clang diagnostic pop
    }];
    
    [alert addAction:cancel];
    if ([title isEqualToString:@"Tap"] || [title isEqualToString:@"Hold"]) {
        [alert addAction:record];
    }
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)appDidBecomeActive {
    if (self.isWaitingForTapRecord && self.activeAlert) {
        [[RCServerClient sharedClient] executeCommand:@"taprecordstatus" completion:^(NSString * _Nullable output, NSError * _Nullable error) {
            if (output) {
                NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (json && [json[@"status"] isEqualToString:@"recorded"]) {
                    double x = [json[@"x"] doubleValue];
                    double y = [json[@"y"] doubleValue];
                    
                    NSString *val;
                    NSString *cmd;
                    if ([self.activeAlert.title isEqualToString:@"Hold"]) {
                        val = [NSString stringWithFormat:@"%.0f %.0f 800", x, y];
                        cmd = [NSString stringWithFormat:@"hold %@", val];
                    } else {
                        val = [NSString stringWithFormat:@"%.0f %.0f", x, y];
                        cmd = [NSString stringWithFormat:@"tap %@", val];
                    }
                    
                    if (self.onActionSelected) {
                        self.onActionSelected(cmd);
                    }
                    
                    UIAlertController *alertToDismiss = self.activeAlert;
                    self.activeAlert = nil;
                    self.isWaitingForTapRecord = NO;
                    
                    [alertToDismiss dismissViewControllerAnimated:YES completion:^{
                        if (self.searchController.isActive) {
                            [self.searchController dismissViewControllerAnimated:NO completion:^{
                                [self dismissViewControllerAnimated:YES completion:nil];
                            }];
                        } else {
                            [self dismissViewControllerAnimated:YES completion:nil];
                        }
                    }];
                }
            }
        }];
    }
}

- (void)handleValueInputForCommand:(NSString *)commandPlaceholder {
    NSDictionary *inputs = @{
        @"__SET_VOLUME__": @[@"Set Volume", @"set-vol"],
        @"__SET_RINGER_VOLUME__": @[@"Set Ringer Volume", @"ringer volume"],
        @"__SET_BRIGHTNESS__": @[@"Set Brightness", @"brightness"],
        @"__SET_FLASHLIGHT__": @[@"Set Flashlight", @"flashlight"],
    };
    NSString *title = inputs[commandPlaceholder][0] ?: @"Set Flashlight";
    NSString *prefix = inputs[commandPlaceholder][1] ?: @"flashlight";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title                                                                   message:@"Enter a value (0-100)" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.textAlignment = NSTextAlignmentCenter;
    }];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *value = textField.text;
        // Basic validation
        int val = [value intValue];
        if (val < 0) val = 0;
        if (val > 100) val = 100;
        
        NSString *finalCommand = [NSString stringWithFormat:@"%@ %d", prefix, val];
        
        if (self.onActionSelected) {
            self.onActionSelected(finalCommand);
        }
        if (self.searchController.isActive) {
            [self.searchController dismissViewControllerAnimated:NO completion:^{
                [self dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    }];
    
    [alert addAction:cancelAction];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleAirPlayConnect {
    [self pushDevicePickerWithKind:RCDevicePickerKindAirPlay title:@"Connect AirPlay" commandPrefix:@"airplay connect"];
}

- (void)handleBluetoothConnect {
    [self pushDevicePickerWithKind:RCDevicePickerKindBluetooth title:@"Connect Bluetooth" commandPrefix:@"bt connect"];
}

- (void)handleBluetoothDisconnect {
    [self pushDevicePickerWithKind:RCDevicePickerKindBluetooth title:@"Disconnect Bluetooth" commandPrefix:@"bt disconnect"];
}

// Lists the devices; choosing one adds "<prefix> <device>" and closes the picker
- (void)pushDevicePickerWithKind:(RCDevicePickerKind)kind title:(NSString *)title commandPrefix:(NSString *)prefix {
    RCDevicePickerViewController *picker = [[RCDevicePickerViewController alloc] initWithKind:kind title:title];
    __weak typeof(self) weakSelf = self;
    picker.onDeviceSelected = ^(NSDictionary *device) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.onActionSelected) {
            strongSelf.onActionSelected([NSString stringWithFormat:@"%@ %@", prefix, device[@"target"]]);
        }
        if (strongSelf.searchController.isActive) {
            [strongSelf.searchController dismissViewControllerAnimated:NO completion:^{
                [strongSelf dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [strongSelf dismissViewControllerAnimated:YES completion:nil];
        }
    };
    [self.navigationController pushViewController:picker animated:YES];
}

// Off adds "focus off"; a Focus is turned on or toggled (the picker asks which)
- (void)handleFocus {
    RCFocusPickerViewController *picker = [[RCFocusPickerViewController alloc] initWithTitle:@"Set Focus" fixedRows:@[ @{ @"name": @"Off", @"value": @"", @"icon": @"moon.zzz" } ]];
    picker.buildsCommand = YES;
    __weak typeof(self) weakSelf = self;
    picker.onSelected = ^(NSDictionary *row) {
        [weakSelf finishWithFocusCommand:row[@"command"]];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)finishWithFocusCommand:(NSString *)command {
    if (self.onActionSelected) self.onActionSelected(command);
    if (self.searchController.isActive) {
        [self.searchController dismissViewControllerAnimated:NO completion:^{
            [self dismissViewControllerAnimated:YES completion:nil];
        }];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    if (text.length == 0) {
        self.filteredActions = @[];
    } else {
        NSMutableArray *allActions = [NSMutableArray array];
        if ([self hasCategory]) {
            [allActions addObjectsFromArray:self.sections[self.selectedCategory]];
        } else {
            for (NSArray *section in self.sections) {
                [allActions addObjectsFromArray:section];
            }
        }
        
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR command CONTAINS[cd] %@", text, text];
        self.filteredActions = [allActions filteredArrayUsingPredicate:pred];
    }
    [self.tableView reloadData];
}

- (void)handleHAPicker {
    RCHAEntityPickerViewController *picker = [[RCHAEntityPickerViewController alloc] init];
    picker.onEntitySelected = ^(NSString *cmd) {
        if (self.onActionSelected) {
            self.onActionSelected(cmd);
        }
        if (self.searchController.isActive) {
            [self.searchController dismissViewControllerAnimated:NO completion:^{
                [self dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)handleKMTrigger {
    RCKMMacroPickerViewController *picker = [[RCKMMacroPickerViewController alloc] init];
    picker.onMacroSelected = ^(NSString *cmd) {
        if (self.onActionSelected) {
            self.onActionSelected(cmd);
        }
        if (self.searchController.isActive) {
            [self.searchController dismissViewControllerAnimated:NO completion:^{
                [self dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)handleMQTTPublish {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSString *defaultTopic = cm.mqttTopicPrefix.length ? [NSString stringWithFormat:@"%@/action", cm.mqttTopicPrefix] : @"remotecompanion/action";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MQTT: Publish Topic"
                                                                   message:@"Enter the MQTT topic and payload to publish:"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Topic (e.g. home/livingroom/light/set)";
        tf.text = defaultTopic;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Payload (e.g. ON, TOGGLE, 1, or JSON)";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *topic = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *payload = [alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (!topic.length) return;
        
        NSString *finalCmd;
        if (payload.length > 0) {
            finalCmd = [NSString stringWithFormat:@"mqtt publish %@ %@", topic, payload];
        } else {
            finalCmd = [NSString stringWithFormat:@"mqtt publish %@", topic];
        }
        
        if (self.onActionSelected) {
            self.onActionSelected(finalCmd);
        }
        if (self.searchController.isActive) {
            [self.searchController dismissViewControllerAnimated:NO completion:^{
                [self dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end
