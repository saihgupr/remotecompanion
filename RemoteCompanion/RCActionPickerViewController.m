#import "RCActionPickerViewController.h"
#import "RCAddOnCatalog.h"
#import "RCAddOnActionsViewController.h"
#import "RCServerClient.h"
#import "RCDevicePickerViewController.h"
#import "RCFocusPickerViewController.h"
#import "RCGesturesViewController.h"
#import "RCPlayGestureViewController.h"
#import "RCConfigManager.h"
#import "RCHAEntityPickerViewController.h"
#import "RCKMMacroPickerViewController.h"
#import "RCCategoryBar.h"
#import "RCSSHActionEditorViewController.h"
#import "RCActionTile.h"

@interface RCActionPickerViewController () <UISearchResultsUpdating, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredActions;
@property (nonatomic, strong) NSDictionary *selectedActionOverride; // an add-on action picked in its own list
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIAlertController *activeAlert;
@property (nonatomic, assign) BOOL isWaitingForTapRecord;
// Category bar: -1 = All, otherwise an index into sections / sectionTitles
@property (nonatomic, assign) NSInteger selectedCategory;
@property (nonatomic, strong) RCCategoryBar *categoryBar;
@end

@implementation RCActionPickerViewController

// One pick per opening: a second tap while the list is closing (easy on a slower iPhone) would
// otherwise add the action twice, or ask for its details twice. A pick that keeps the list open
// (its screen opens on top, and Cancel there comes back here) doesn't use it up.
- (void)setOnActionSelected:(void (^)(NSString *))onActionSelected {
    if (!onActionSelected) { _onActionSelected = nil; return; }
    __block BOOL picked = NO;
    __weak typeof(self) weakSelf = self;
    void (^once)(NSString *) = ^(NSString *action) {
        if (picked) return;
        BOOL (^staysOpen)(NSString *) = weakSelf.staysOpenFor;
        if (!staysOpen || !staysOpen(action)) picked = YES;
        onActionSelected(action);
    };
    _onActionSelected = [once copy];
}

- (instancetype)init {
    self = [super initWithCollectionViewLayout:RCActionGridLayout()];
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
    
    // The cells and titles first: attaching the category bar lays the grid out, and on iOS 14 that
    // asks for cells straight away
    [self.collectionView registerClass:[RCActionTileCell class] forCellWithReuseIdentifier:@"ActionTile"];
    [self.collectionView registerClass:[RCActionRowCell class] forCellWithReuseIdentifier:@"ActionRow"];
    [self.collectionView registerClass:[RCActionGridHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"Header"];

    // Category bar floating below the search bar
    [self rebuildSections];
    self.categoryBar = [self makeCategoryBar];
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.categoryBar attachToScrollView:self.collectionView];
    
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
    
    // List or Compact (Settings), followed while open
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutChanged:) name:RCLayoutChangedNotification object:nil];
    
    [self applyTweaks];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuildSections];
    [self.collectionView reloadData];
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
            @{ @"name": @"App Quick Action", @"command": @"__APP_QUICK_SHORTCUT__", @"icon": @"bolt.fill" },
            @{ @"name": @"Kill App...", @"command": @"__KILL_APP__", @"icon": @"xmark.square.fill" },
            @{ @"name": @"Kill Current App", @"command": @"kill current", @"icon": @"xmark.square.fill" },
            @{ @"name": @"Home Button", @"command": @"home", @"icon": @"house.fill" },
            @{ @"name": @"App Switcher", @"command": @"switcher", @"icon": @"square.stack.3d.up.fill" },
            @{ @"name": @"Previous App", @"command": @"previous app", @"icon": @"arrow.uturn.backward" },
            @{ @"name": @"Control Center", @"command": @"open control center", @"icon": @"switch.2" },
            @{ @"name": @"Activate Siri", @"command": @"siri", @"icon": @"mic.circle.fill" },
            @{ @"name": @"Play Gesture...", @"command": @"__PLAY_GESTURE__", @"icon": @"hand.draw.fill" },
            @{ @"name": @"Record Gesture", @"command": @"__RECORD_GESTURE__", @"icon": @"record.circle" },
            @{ @"name": @"Accessibility Shortcut", @"command": @"accessibility shortcut", @"icon": ([UIImage systemImageNamed:@"accessibility"] ? @"accessibility" : @"figure.stand") }
        ],
        // Device Controls
        @[
            @{ @"name": @"Appearance", @"command": @"appearance toggle", @"icon": @"circle.lefthalf.fill" },
            @{ @"name": @"Set Brightness...", @"command": @"__SET_BRIGHTNESS__", @"icon": @"sun.max.fill" },
            @{ @"name": @"Flashlight", @"command": @"flashlight toggle", @"icon": @"flashlight.on.fill" },
            @{ @"name": @"Rotation Lock", @"command": @"rotate toggle", @"icon": @"lock.rotation" },
            @{ @"name": @"Lock Device", @"command": @"lock", @"icon": @"lock.fill" },
            @{ @"name": @"Unlock Device...", @"command": @"__UNLOCK_DEVICE__", @"icon": @"lock.open.fill" },
            @{ @"name": @"Lock Toggle...", @"command": @"__LOCK_TOGGLE__", @"icon": @"lock.circle" },
            @{ @"name": @"Do Not Disturb", @"command": @"dnd toggle", @"icon": @"moon.circle.fill" },
            @{ @"name": @"Set Focus...", @"command": @"__FOCUS__", @"icon": @"moon.circle" },
            @{ @"name": @"Low Power Mode", @"command": @"low power toggle", @"icon": @"battery.25" },
            @{ @"name": @"Auto-Lock (Display Sleep)", @"command": @"autolock toggle", @"icon": @"timer", @"keywords": @"display sleep timeout time off screen autolock" },
            @{ @"name": @"NFC Scanner", @"command": @"nfc scanner toggle", @"icon": @"wave.3.right" },
            @{ @"name": @"Button Triggers", @"command": @"button triggers pause 15", @"icon": @"pause.circle" }
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
            [integrations addObject:@{ @"name": @"SSH: Run Remote Command...", @"command": @"__SSH_COMMAND__", @"icon": @"terminal.fill" }];
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
            NSArray *audioHandoffPaths = @[
                @"/Library/MobileSubstrate/DynamicLibraries/AudioHandoff.dylib",
                @"/Library/MobileSubstrate/DynamicLibraries/AudioHandoff.plist",
                @"/usr/lib/TweakInject/AudioHandoff.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/AudioHandoff.dylib",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries/AudioHandoff.plist",
                @"/var/jb/usr/lib/TweakInject/AudioHandoff.dylib"
            ];
            BOOL audioHandoffInstalled = NO;
            for (NSString *p in audioHandoffPaths) {
                if ([fm fileExistsAtPath:p]) { audioHandoffInstalled = YES; break; }
            }
            if (audioHandoffInstalled) {
                [integrations addObject:@{ @"name": @"AudioHandoff: Automatic Switching", @"command": @"audiohandoff enabled toggle", @"icon": @"headphones" }];
            }
            [integrations addObject:@{ @"name": @"AudioMix: Toggle", @"command": @"audiomix toggle", @"icon": @"music.note" }];
            integrations;
        }),
        // Scripting & Logic
        @[
            @{ @"name": @"Custom Lua Script", @"command": @"__LUA_SCRIPT__", @"icon": @"scroll.fill" },
            @{ @"name": @"If Condition...", @"command": @"__IF_CONDITION__", @"icon": @"arrow.triangle.branch" },
            @{ @"name": @"Repeat...", @"command": @"__REPEAT__", @"icon": @"repeat" },
            @{ @"name": @"Repeat While...", @"command": @"__REPEAT_WHILE__", @"icon": @"repeat" },
            @{ @"name": @"Exit Repeat", @"command": @"__EXIT_REPEAT__", @"icon": @"arrow.right.to.line" },
            @{ @"name": @"Wait Until...", @"command": @"__WAIT_UNTIL__", @"icon": @"hourglass" },
            @{ @"name": @"Set Variable...", @"command": @"__SET_VARIABLE__", @"icon": @"x.squareroot" },
            @{ @"name": @"Delay", @"command": @"__DELAY__", @"icon": @"hourglass" },
            @{ @"name": @"Stop Trigger...", @"command": @"__STOP_TRIGGER__", @"icon": @"stop.circle" },
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
    // Add-ons (add-ons, ADDONS.md): one category, a row for each add-on that opens its actions
    NSMutableArray *titles = [_sectionTitles mutableCopy];
    NSArray *addOns = [RCAddOnCatalog addOnRows];
    if (addOns.count) {
        NSUInteger at = [titles indexOfObject:@"Integrations"];
        at = at == NSNotFound ? titles.count : at + 1;
        [titles insertObject:@"Add-ons" atIndex:at];
        [sections insertObject:addOns atIndex:at];
    }
    _sectionTitles = titles;
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
    self.collectionView.backgroundColor = pickerBG;
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    [self.collectionView reloadData];
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
    [self.categoryBar layoutInScrollView:self.collectionView];
}

// More or fewer columns after a rotation
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self.collectionView.collectionViewLayout invalidateLayout];
}

- (BOOL)compact {
    return RCLayoutIsCompact(RCLayoutActionPicker);
}

- (void)layoutChanged:(NSNotification *)note {
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
}

// A tile isn't left looking picked after its popup is cancelled
- (void)deselectTiles {
    for (NSIndexPath *path in self.collectionView.indexPathsForSelectedItems) [self.collectionView deselectItemAtIndexPath:path animated:YES];
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

#pragma mark - Grid

// Actions that open another screen or ask for more: their tiles get a chevron
static BOOL RCPickerActionOpensMore(NSString *command) {
    static NSSet *more;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        more = [NSSet setWithArray:@[@"__SET_VOLUME__", @"__SET_RINGER_VOLUME__", @"__SET_BRIGHTNESS__", @"__SET_FLASHLIGHT__",
                                     @"__BT_CONNECT__", @"__BT_DISCONNECT__", @"__AIRPLAY_CONNECT__", @"__FOCUS__",
                                     @"__SHORTCUT_PICKER__", @"__OPEN_APP__", @"__KILL_APP__", @"__LUA_SCRIPT__", @"__TOAST__",
                                     @"__IF_CONDITION__", @"__REPEAT__", @"__REPEAT_WHILE__", @"__WAIT_UNTIL__", @"__DELAY__",
                                     @"__STOP_TRIGGER__", @"__CUSTOM__", @"__HA_PICKER__", @"__KM_TRIGGER__", @"__MQTT_PUBLISH__",
                                     @"__CAMERA_PICKER__", @"__CAMERA_VIDEO_PICKER__", @"__TAP__", @"__HOLD__", @"__SWIPE__",
                                     @"__UNLOCK_DEVICE__", @"__LOCK_TOGGLE__"]];
    });
    if (![command isKindOfClass:[NSString class]]) return NO;
    // Any other placeholder opens something too; a plain command is added as it is
    return [more containsObject:command] || ([command hasPrefix:@"__"] && [command hasSuffix:@"__"]);
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return [self displaySections].count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self displaySections][section].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (![self compact]) {
        // List: a row, in a rounded card per section
        RCActionRowCell *row = [collectionView dequeueReusableCellWithReuseIdentifier:@"ActionRow" forIndexPath:indexPath];
        NSDictionary *action = [self actionAtIndexPath:indexPath];
        NSString *icon = action[@"icon"];
        if (@available(iOS 15.0, *)) {} else if ([icon isEqualToString:@"ear.badge.checkmark"]) icon = @"ear";
        UIImage *custom = [action[@"image"] isKindOfClass:[UIImage class]] ? action[@"image"] : nil;
        [row setName:action[@"name"] icon:icon image:custom];
        row.opensMore = RCPickerActionOpensMore(action[@"command"]) || [RCAddOnCatalog commandAsksForDetails:action[@"command"]];
        NSInteger count = [collectionView numberOfItemsInSection:indexPath.section];
        [row setFirst:indexPath.item == 0 last:indexPath.item == count - 1];
        return row;
    }
    RCActionTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ActionTile" forIndexPath:indexPath];
    NSDictionary *action = [self actionAtIndexPath:indexPath];
    NSString *icon = action[@"icon"];
    if (@available(iOS 15.0, *)) {} else if ([icon isEqualToString:@"ear.badge.checkmark"]) icon = @"ear";
    UIImage *custom = [action[@"image"] isKindOfClass:[UIImage class]] ? action[@"image"] : nil;   // an add-on's own picture
    [cell setName:action[@"name"] icon:icon image:custom];
    cell.opensMore = RCPickerActionOpensMore(action[@"command"]) || [RCAddOnCatalog commandAsksForDetails:action[@"command"]];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    RCActionGridHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"Header" forIndexPath:indexPath];
    [header setTitle:[self displayTitleForSection:indexPath.section]];
    return header;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [self compact] ? RCActionTileSize(RCGridWidth(collectionView)) : RCActionRowSize(RCGridWidth(collectionView), 56);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return [self compact] ? ((UICollectionViewFlowLayout *)layout).minimumLineSpacing : 0; // a list's rows touch
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section {
    // The first title sits just below the category bar
    return CGSizeMake(collectionView.bounds.size.width, section == 0 ? 30 : 38);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self selectActionAtIndexPath:indexPath];
}

- (void)selectActionAtIndexPath:(NSIndexPath *)indexPath {
    [self.collectionView deselectItemAtIndexPath:indexPath animated:YES];
    
    NSDictionary *action = self.selectedActionOverride ?: [self actionAtIndexPath:indexPath];
    NSString *command = action[@"command"];
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed) return; // already picked, closing
    

    // An add-on opens a list of its actions; the one picked comes back through here
    if ([command hasPrefix:@"__ADDON__"]) {
        __weak typeof(self) weakSelf = self;
        RCAddOnActionsViewController *vc = [[RCAddOnActionsViewController alloc] initWithAddOn:[command substringFromIndex:9] title:action[@"name"]];
        __weak RCAddOnActionsViewController *weakList = vc;
        vc.onSelect = ^(NSDictionary *chosen) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSString *chosenCommand = chosen[@"command"];
            if ([RCAddOnCatalog commandAsksForDetails:chosenCommand] && weakList) {
                // The options open on top of this list, so Back returns to it
                [RCAddOnCatalog presentDetailsFrom:weakList command:chosenCommand current:nil completion:^(NSString *full) {
                    [strongSelf finishWithFocusCommand:full];
                }];
                return;
            }
            strongSelf.selectedActionOverride = chosen;
            [strongSelf selectActionAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
            strongSelf.selectedActionOverride = nil;
        };
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }


    if ([command isEqualToString:@"__UNLOCK_DEVICE__"]) {
        [self handleUnlockDevice];
        return;
    }

    if ([command isEqualToString:@"__LOCK_TOGGLE__"]) {
        [self handleLockToggle];
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
    
    if ([command isEqualToString:@"__PLAY_GESTURE__"]) {
        [self handlePlayGesture];
        return;
    }
    if ([command isEqualToString:@"__RECORD_GESTURE__"]) {
        [self finishWithFocusCommand:[RCGesturesViewController recordCommand]];
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

    if ([command isEqualToString:@"__SSH_COMMAND__"]) {
        [self handleSSHCommand];
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

    // An add-on action with options or input asks for them first
    if ([RCAddOnCatalog commandAsksForDetails:command]) {
        __weak typeof(self) weakSelf = self;
        [RCAddOnCatalog presentDetailsFrom:self command:command current:nil completion:^(NSString *chosen) {
            [weakSelf finishWithFocusCommand:chosen];
        }];
        return;
    }

    if (self.onActionSelected) {
        self.onActionSelected(command);
    }
    if (self.staysOpenFor && self.staysOpenFor(command)) return; // its screen opens on top of this one
    
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
        [self deselectTiles];
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
        [self deselectTiles];
    }];
    
    [alert addAction:cancelAction];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleUnlockDevice {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Unlock Device"
                                                                   message:@"Enter a passcode to unlock automatically, or choose 'Wake Screen Only' to present the passcode screen.\n\nNote: Configured passcodes are stored in plain text in trigger settings (rc_triggers.plist)."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Passcode (optional)";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        textField.secureTextEntry = YES;
    }];
    
    __weak typeof(self) weakSelf = self;
    
    UIAlertAction *saveWithPasscode = [UIAlertAction actionWithTitle:@"Set Passcode" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UITextField *tf = alert.textFields.firstObject;
        NSString *pin = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *finalCmd = pin.length > 0 ? [NSString stringWithFormat:@"unlock %@", pin] : @"unlock";
        if (strongSelf.onActionSelected) strongSelf.onActionSelected(finalCmd);
        if (strongSelf.searchController.isActive) {
            [strongSelf.searchController dismissViewControllerAnimated:NO completion:^{
                [strongSelf dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [strongSelf dismissViewControllerAnimated:YES completion:nil];
        }
    }];
    
    UIAlertAction *wakeOnly = [UIAlertAction actionWithTitle:@"Wake Screen Only" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.onActionSelected) strongSelf.onActionSelected(@"unlock");
        if (strongSelf.searchController.isActive) {
            [strongSelf.searchController dismissViewControllerAnimated:NO completion:^{
                [strongSelf dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [strongSelf dismissViewControllerAnimated:YES completion:nil];
        }
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [self deselectTiles];
    }];
    
    [alert addAction:wakeOnly];
    [alert addAction:saveWithPasscode];
    [alert addAction:cancel];
    alert.preferredAction = saveWithPasscode;
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleLockToggle {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Lock Toggle"
                                                                   message:@"Enter a passcode to unlock automatically when locked, or choose 'Toggle Without Passcode' to toggle without passcode entry.\n\nNote: Configured passcodes are stored in plain text in trigger settings (rc_triggers.plist)."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Passcode (optional)";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        textField.secureTextEntry = YES;
    }];
    
    __weak typeof(self) weakSelf = self;
    
    UIAlertAction *saveWithPasscode = [UIAlertAction actionWithTitle:@"Set Passcode" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UITextField *tf = alert.textFields.firstObject;
        NSString *pin = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *finalCmd = pin.length > 0 ? [NSString stringWithFormat:@"lock-toggle %@", pin] : @"lock-toggle";
        if (strongSelf.onActionSelected) strongSelf.onActionSelected(finalCmd);
        if (strongSelf.searchController.isActive) {
            [strongSelf.searchController dismissViewControllerAnimated:NO completion:^{
                [strongSelf dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [strongSelf dismissViewControllerAnimated:YES completion:nil];
        }
    }];
    
    UIAlertAction *noPasscode = [UIAlertAction actionWithTitle:@"Toggle Without Passcode" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.onActionSelected) strongSelf.onActionSelected(@"lock-toggle");
        if (strongSelf.searchController.isActive) {
            [strongSelf.searchController dismissViewControllerAnimated:NO completion:^{
                [strongSelf dismissViewControllerAnimated:YES completion:nil];
            }];
        } else {
            [strongSelf dismissViewControllerAnimated:YES completion:nil];
        }
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [self deselectTiles];
    }];
    
    [alert addAction:noPasscode];
    [alert addAction:saveWithPasscode];
    [alert addAction:cancel];
    alert.preferredAction = saveWithPasscode;
    
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

// A new Play Gesture action: its own page, which gesture and how fast
- (void)handlePlayGesture {
    RCPlayGestureViewController *page = [[RCPlayGestureViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    page.onSave = ^(NSString *command) {
        [weakSelf finishWithFocusCommand:command];
    };
    [self.navigationController pushViewController:page animated:YES];
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
        
        // Add-on actions are found directly, in place of their rows
        if (![self hasCategory] || [_sectionTitles[self.selectedCategory] isEqualToString:@"Add-ons"]) {
            [allActions addObjectsFromArray:[RCAddOnCatalog pickerActions]];
        }
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR command CONTAINS[cd] %@ OR (keywords != nil AND keywords CONTAINS[cd] %@)", text, text, text];
        self.filteredActions = [allActions filteredArrayUsingPredicate:pred];
    }
    [self.collectionView reloadData];
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

- (void)handleSSHCommand {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSArray<NSDictionary *> *hosts = cm.sshHosts;
    if (hosts.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No SSH Hosts Configured"
                                                                       message:@"You must add at least one SSH host before creating an SSH action.\nGo to Settings > Integrations > SSH Hosts."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    if (hosts.count == 1) {
        [self promptForSSHCommandWithHost:hosts.firstObject];
        return;
    }
    
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Select SSH Host"
                                                                   message:@"Choose a target host for this remote command"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *host in hosts) {
        NSString *title = host[@"name"] ?: host[@"host"];
        NSString *sub = [NSString stringWithFormat:@"%@@%@:%@", host[@"user"] ?: @"", host[@"host"] ?: @"", host[@"port"] ?: @22];
        NSString *display = [NSString stringWithFormat:@"%@ (%@)", title, sub];
        [sheet addAction:[UIAlertAction actionWithTitle:display style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [weakSelf promptForSSHCommandWithHost:host];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptForSSHCommandWithHost:(NSDictionary *)host {
    RCSSHActionEditorViewController *editor = [[RCSSHActionEditorViewController alloc]
        initWithHostId:host[@"id"] command:@""];
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(NSString *hostId, NSString *command) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *actionString = [NSString stringWithFormat:@"ssh-run %@ %@", hostId, command];
        if (strongSelf.onActionSelected) {
            strongSelf.onActionSelected(actionString);
        }
        // Dismiss the editor, then the picker itself so Save returns to the
        // main actions sequence like every other action editor.
        void (^dismissPickerToActions)(void) = ^{
            UINavigationController *pickerNav = strongSelf.navigationController;
            [pickerNav.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        };
        if (strongSelf.searchController.isActive) {
            [strongSelf.searchController dismissViewControllerAnimated:NO completion:^{
                [strongSelf dismissViewControllerAnimated:YES completion:^{
                    dismissPickerToActions();
                }];
            }];
        } else {
            [strongSelf dismissViewControllerAnimated:YES completion:^{
                dismissPickerToActions();
            }];
        }
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    [self presentViewController:nav animated:YES completion:nil];
}

@end
