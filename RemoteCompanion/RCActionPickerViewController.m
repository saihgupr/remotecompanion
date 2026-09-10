#import "RCActionPickerViewController.h"
#import "RCServerClient.h"
#import "RCConfigManager.h"
#import "RCHAEntityPickerViewController.h"
#import "RCKMMacroPickerViewController.h"

@interface RCActionPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredActions;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIAlertController *activeAlert;
@property (nonatomic, assign) BOOL isWaitingForTapRecord;
@end

@implementation RCActionPickerViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
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
    
    // Reduce gap above first section (below search bar)
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, CGFLOAT_MIN)];
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 15;
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
    
    _sectionTitles = @[@"Media", @"Device Controls", @"Connectivity", @"System", @"Integrations", @"Scripting & Logic"];
    
    _sections = @[
        // Media
        ({
            NSMutableArray *media = [NSMutableArray arrayWithArray:@[
                @{ @"name": @"Play", @"command": @"play", @"icon": @"play.fill" },
                @{ @"name": @"Pause", @"command": @"pause", @"icon": @"pause.fill" },
                @{ @"name": @"Play/Pause", @"command": @"playpause", @"icon": @"playpause.fill" },
                @{ @"name": @"Next Track", @"command": @"next", @"icon": @"forward.fill" },
                @{ @"name": @"Previous Track", @"command": @"prev", @"icon": @"backward.fill" },
                @{ @"name": @"Volume Up", @"command": @"volume up", @"icon": @"speaker.wave.3.fill" },
                @{ @"name": @"Volume Down", @"command": @"volume down", @"icon": @"speaker.wave.1.fill" },
                @{ @"name": @"Set Volume...", @"command": @"__SET_VOLUME__", @"icon": @"speaker.wave.3.fill" },
                @{ @"name": @"Set Brightness...", @"command": @"__SET_BRIGHTNESS__", @"icon": @"sun.max.fill" },
                @{ @"name": @"Mute", @"command": @"mute toggle", @"icon": @"speaker.slash.fill" },
                @{ @"name": @"ANC On", @"command": @"anc on", @"icon": @"ear.badge.checkmark" },
                @{ @"name": @"ANC Off", @"command": @"anc off", @"icon": @"ear" },
                @{ @"name": @"Transparency Mode", @"command": @"anc transparency", @"icon": @"waveform.circle.fill" },
                @{ @"name": @"Open Camera...", @"command": @"__CAMERA_PICKER__", @"icon": @"camera.fill" },
                @{ @"name": @"Open Video Camera...", @"command": @"__CAMERA_VIDEO_PICKER__", @"icon": @"video.fill" },
                @{ @"name": @"Camera Shutter / Snap", @"command": @"camera shutter", @"icon": @"camera.circle.fill" },
                @{ @"name": @"Camera Record Toggle", @"command": @"camera record", @"icon": @"record.circle.fill" }
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
        // Device Controls
        @[
            @{ @"name": @"Appearance", @"command": @"appearance toggle", @"icon": @"moon.fill" },
            @{ @"name": @"Flashlight", @"command": @"flashlight toggle", @"icon": @"flashlight.on.fill" },
            @{ @"name": @"Rotation Lock", @"command": @"rotate toggle", @"icon": @"lock.rotation" }
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
            @{ @"name": @"Haptic Feedback", @"command": @"haptic", @"icon": @"hand.tap.fill" },
            @{ @"name": @"Screenshot", @"command": @"screenshot", @"icon": @"camera.fill" },
            @{ @"name": @"Screen Recording", @"command": @"screenrecord toggle", @"icon": @"record.circle.fill" },
            @{ @"name": @"Open App...", @"command": @"__OPEN_APP__", @"icon": @"square.grid.2x2.fill" },
            @{ @"name": @"Kill App...", @"command": @"__KILL_APP__", @"icon": @"xmark.square.fill" },
            @{ @"name": @"Lock Device", @"command": @"lock", @"icon": @"lock.fill" },
            @{ @"name": @"Unlock Device", @"command": @"unlock", @"icon": @"lock.open.fill" },
            @{ @"name": @"Do Not Disturb", @"command": @"dnd toggle", @"icon": @"moon.fill" },
            @{ @"name": @"Activate Siri", @"command": @"siri", @"icon": @"mic.circle.fill" },
            @{ @"name": @"Home Button", @"command": @"home", @"icon": @"house.fill" },
            @{ @"name": @"App Switcher", @"command": @"switcher", @"icon": @"square.stack.3d.up.fill" },
            @{ @"name": @"Previous App", @"command": @"previous app", @"icon": @"arrow.uturn.backward" },
            @{ @"name": @"Control Center", @"command": @"open control center", @"icon": @"gear" },
            @{ @"name": @"Respring Device", @"command": @"respring", @"icon": @"memories" },
            @{ @"name": @"Safe Mode", @"command": @"safemode", @"icon": @"shield.slash.fill" },
            @{ @"name": @"Soft Reboot (ldrestart)", @"command": @"ldrestart", @"icon": @"arrow.clockwise" },
            @{ @"name": @"Userspace Reboot", @"command": @"userspace-reboot", @"icon": @"arrow.clockwise.circle" },
            @{ @"name": @"Refresh Icon Cache (uicache)", @"command": @"uicache", @"icon": @"square.grid.2x2" },
            @{ @"name": @"Silent Vibration", @"command": @"vibration silent-toggle", @"icon": @"bell.slash" },
            @{ @"name": @"Ring Vibration", @"command": @"vibration ring-toggle", @"icon": @"bell" },
            @{ @"name": @"Low Power Mode", @"command": @"low power toggle", @"icon": @"battery.25" }
        ],
        // Integrations
        ({
            NSMutableArray *integrations = [NSMutableArray array];
            if (cm.haEnabled) {
                [integrations addObject:@{ @"name": @"Home Assistant: Control Entity...", @"command": @"__HA_PICKER__", @"icon": @"house.fill" }];
            }
            if (cm.kmEnabled) {
                [integrations addObject:@{ @"name": @"Keyboard Maestro: Trigger Macro...", @"command": @"__KM_TRIGGER__", @"icon": @"command" }];
            }
            if (cm.mqttEnabled) {
                [integrations addObject:@{ @"name": @"MQTT: Publish Topic...", @"command": @"__MQTT_PUBLISH__", @"icon": @"antenna.radiowaves.left.and.right" }];
            }
            [integrations addObject:@{ @"name": @"Shortcuts: Run Shortcut...", @"command": @"__SHORTCUT_PICKER__", @"icon": @"command" }];
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
                @"/var/mobile/Library/Preferences/com.spark.sneakycam.plist",
                @"/var/mobile/Library/Preferences/com.spark.SneakyCam.plist",
                @"/var/jb/var/mobile/Library/Preferences/com.spark.sneakycam.plist"
            ];
            BOOL sneakyInstalled = NO;
            NSFileManager *fm = [NSFileManager defaultManager];
            for (NSString *p in sneakyPaths) {
                if ([fm fileExistsAtPath:p]) { sneakyInstalled = YES; break; }
            }
            if (sneakyInstalled) {
                [integrations addObject:@{ @"name": @"SneakyCam: Take Photo", @"command": @"sneakycam photo", @"icon": @"camera.aperture" }];
                [integrations addObject:@{ @"name": @"SneakyCam: Toggle Video", @"command": @"sneakycam video", @"icon": @"video.fill" }];
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
                @"/var/jb/usr/lib/TweakInject/Snapper3.dylib",
                @"/var/jb/usr/lib/TweakInject/snapper3.dylib",
                @"/var/jb/usr/lib/TweakInject/Snapper2.dylib",
                @"/var/jb/usr/lib/TweakInject/snapper2.dylib",
                @"/var/mobile/Library/Preferences/com.jontelang.snapper3preferences.plist",
                @"/var/jb/var/mobile/Library/Preferences/com.jontelang.snapper3preferences.plist",
                @"/var/mobile/Library/Preferences/com.jontelang.snapper2.plist",
                @"/var/jb/var/mobile/Library/Preferences/com.jontelang.snapper2.plist",
                @"/Library/PreferenceBundles/Snapper3Preferences.bundle",
                @"/var/jb/Library/PreferenceBundles/Snapper3Preferences.bundle"
            ];
            BOOL snapperInstalled = NO;
            for (NSString *p in snapperPaths) {
                if ([fm fileExistsAtPath:p]) { snapperInstalled = YES; break; }
            }
            if (snapperInstalled) {
                [integrations addObject:@{ @"name": @"Snapper: Open Area", @"command": @"snapper open", @"icon": @"crop" }];
                [integrations addObject:@{ @"name": @"Snapper: Freeze Screen", @"command": @"snapper freeze", @"icon": @"snowflake" }];
                [integrations addObject:@{ @"name": @"Snapper: Instant Snap", @"command": @"snapper instant", @"icon": @"bolt.fill" }];
                [integrations addObject:@{ @"name": @"Snapper: Close All", @"command": @"snapper close", @"icon": @"xmark.circle" }];
            }
            [integrations addObject:@{ @"name": @"AudioMix: Toggle", @"command": @"audiomix toggle", @"icon": @"music.note" }];
            integrations;
        }),
        // Scripting & Logic
        @[
            @{ @"name": @"Custom Lua Script", @"command": @"__LUA_SCRIPT__", @"icon": @"scroll.fill" },
            @{ @"name": @"If Condition...", @"command": @"__IF_CONDITION__", @"icon": @"arrow.triangle.branch" },
            @{ @"name": @"Delay", @"command": @"__DELAY__", @"icon": @"timer" },
            @{ @"name": @"Terminal Command", @"command": @"__CUSTOM__", @"icon": @"terminal.fill" },
            @{ @"name": @"Toast...", @"command": @"__TOAST__", @"icon": @"text.bubble.fill" }
        ]
    ];
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

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        return 1;
    }
    return _sections.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = nil;
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        title = @"SEARCH RESULTS";
    } else {
        title = _sectionTitles[section];
    }
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, tableView.bounds.size.width - 40, 20)];
    label.text = [title uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40.0f;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        return self.filteredActions.count;
    }
    return _sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell" forIndexPath:indexPath];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    
    NSDictionary *action;
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        action = self.filteredActions[indexPath.row];
    } else {
        action = _sections[indexPath.section][indexPath.row];
    }
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
        [cmd isEqualToString:@"__SET_BRIGHTNESS__"] || 
        [cmd isEqualToString:@"__BT_CONNECT__"] || 
        [cmd isEqualToString:@"__BT_DISCONNECT__"] || 
        [cmd isEqualToString:@"__AIRPLAY_CONNECT__"] || 
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
    
    NSDictionary *action;
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        action = self.filteredActions[indexPath.row];
    } else {
        action = _sections[indexPath.section][indexPath.row];
    }
    NSString *command = action[@"command"];
    

    if ([command isEqualToString:@"__SET_VOLUME__"] || [command isEqualToString:@"__SET_BRIGHTNESS__"] || [command isEqualToString:@"__SET_FLASHLIGHT__"]) {
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
    NSString *title = [commandPlaceholder isEqualToString:@"__SET_VOLUME__"] ? @"Set Volume" : ([commandPlaceholder isEqualToString:@"__SET_BRIGHTNESS__"] ? @"Set Brightness" : @"Set Flashlight");
    NSString *prefix = [commandPlaceholder isEqualToString:@"__SET_VOLUME__"] ? @"set-vol" : ([commandPlaceholder isEqualToString:@"__SET_BRIGHTNESS__"] ? @"brightness" : @"flashlight");

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
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Scanning for devices..." 
                                                                     message:@"Please wait" 
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    
    [[RCServerClient sharedClient] executeCommand:@"airplay list" completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error) {
                UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Error" 
                                                                                message:error.localizedDescription 
                                                                         preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:errAlert animated:YES completion:nil];
                return;
            }
            
            // Parse output
            // Output format expected: "UID - Name" per line, or "No AirPlay devices found."
            NSArray *lines = [output componentsSeparatedByString:@"\n"];
            NSMutableArray *devices = [NSMutableArray array];
            
            for (NSString *line in lines) {
                NSString *clean = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (clean.length == 0) continue;
                if ([clean isEqualToString:@"No AirPlay devices found."]) continue;
                if ([clean hasPrefix:@"Error:"]) continue;
                
                // Format from Tweak.x: "  Name [UID]" or "* Name [UID]"
                if (clean.length < 5) continue;
                
                // Strip leading status char if present (* or space)
                NSString *workingLine = clean;
                if ([workingLine hasPrefix:@"* "] || [workingLine hasPrefix:@"  "]) {
                    workingLine = [workingLine substringFromIndex:2];
                }
                
                NSRange openBracket = [workingLine rangeOfString:@" [" options:NSBackwardsSearch];
                NSRange closeBracket = [workingLine rangeOfString:@"]" options:NSBackwardsSearch];
                
                if (openBracket.location != NSNotFound && closeBracket.location != NSNotFound && closeBracket.location > openBracket.location) {
                    NSString *name = [[workingLine substringToIndex:openBracket.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSString *uid = [[workingLine substringWithRange:NSMakeRange(openBracket.location + 2, closeBracket.location - openBracket.location - 2)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    [devices addObject:@{ @"uid": uid, @"name": name }];
                }
            }
            
            if (devices.count == 0) {
                UIAlertController *empty = [UIAlertController alertControllerWithTitle:@"No Devices Found" 
                                                                               message:@"Ensure AirPlay devices are reachable." 
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [empty addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:empty animated:YES completion:nil];
                return;
            }
            
            // Show selection
            UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Select AirPlay Device" 
                                                                            message:nil 
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];
            
            for (NSDictionary *device in devices) {
                [picker addAction:[UIAlertAction actionWithTitle:device[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    NSString *finalCommand = [NSString stringWithFormat:@"airplay connect %@ # %@", device[@"uid"], device[@"name"]];
                    
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
                }]];
            }
            
            [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            
            // iPad support
            picker.popoverPresentationController.sourceView = self.view;
            picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
            
            [self presentViewController:picker animated:YES completion:nil];
        }];
    }];
}



- (void)handleBluetoothConnect {
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Fetching paired devices..." 
                                                                     message:@"Please wait" 
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    
    [[RCServerClient sharedClient] executeCommand:@"bluetooth list" completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error || !output) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription ?: @"Failed to fetch devices" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            NSArray *lines = [output componentsSeparatedByString:@"\n"];
            NSMutableArray *devices = [NSMutableArray array];
            for (NSString *line in lines) {
                NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length > 0) {
                    [devices addObject:trimmed];
                }
            }
            
            if (devices.count == 0) {
                UIAlertController *empty = [UIAlertController alertControllerWithTitle:@"No Devices Found" 
                                                                               message:@"Ensure Bluetooth devices are paired." 
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [empty addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:empty animated:YES completion:nil];
                return;
            }
            
            UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Select Bluetooth Device" 
                                                                            message:nil 
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];
            
            for (NSString *deviceName in devices) {
                [picker addAction:[UIAlertAction actionWithTitle:deviceName style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    NSString *finalCommand = [NSString stringWithFormat:@"bt connect %@", deviceName];
                    
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
                }]];
            }
            
            [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            picker.popoverPresentationController.sourceView = self.view;
            picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
            [self presentViewController:picker animated:YES completion:nil];
        }];
    }];
}

- (void)handleBluetoothDisconnect {
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Fetching paired devices..." 
                                                                     message:@"Please wait" 
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    
    [[RCServerClient sharedClient] executeCommand:@"bluetooth list" completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error || !output) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription ?: @"Failed to fetch devices" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            NSArray *lines = [output componentsSeparatedByString:@"\n"];
            NSMutableArray *devices = [NSMutableArray array];
            for (NSString *line in lines) {
                NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length > 0) {
                    [devices addObject:trimmed];
                }
            }
            
            if (devices.count == 0) {
                UIAlertController *empty = [UIAlertController alertControllerWithTitle:@"No Devices Found" 
                                                                               message:@"Ensure Bluetooth devices are paired." 
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [empty addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:empty animated:YES completion:nil];
                return;
            }
            
            UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Select Bluetooth Device" 
                                                                            message:nil 
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];
            
            for (NSString *deviceName in devices) {
                [picker addAction:[UIAlertAction actionWithTitle:deviceName style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    NSString *finalCommand = [NSString stringWithFormat:@"bt disconnect %@", deviceName];
                    
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
                }]];
            }
            
            [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            picker.popoverPresentationController.sourceView = self.view;
            picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
            [self presentViewController:picker animated:YES completion:nil];
        }];
    }];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    if (text.length == 0) {
        self.filteredActions = @[];
    } else {
        NSMutableArray *allActions = [NSMutableArray array];
        for (NSArray *section in self.sections) {
            [allActions addObjectsFromArray:section];
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
