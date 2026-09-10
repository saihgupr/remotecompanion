#import "RCTriggersViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCSettingsViewController.h"
#import "RCNFCTriggerViewController.h"
#import <notify.h>
#import "RCWiFiTriggerViewController.h"
#import "RCBluetoothTriggerViewController.h"
#import "RCAppPickerViewController.h"
#import "RCNotificationTriggerViewController.h"
#import "RCScheduledTriggerViewController.h"
#import "RCMQTTTriggerViewController.h"

#define kSimulateNotificationPrefix "com.pizzaman.rc.simulate."

@interface RCTriggersViewController ()
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *sections;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@end

@implementation RCTriggersViewController

// Helper to get short friendly names for command strings
- (NSString *)nameForCommand:(NSString *)cmd truncate:(BOOL)shouldTruncate {
    return [[RCConfigManager sharedManager] nameForCommand:cmd truncate:shouldTruncate];
}

- (NSString *)iconNameForTrigger:(NSString *)triggerKey {
    if ([triggerKey isEqualToString:@"volume_up_then_down"] || [triggerKey isEqualToString:@"volume_down_then_up"]) return @"arrow.up.and.down.circle.fill";
    if ([triggerKey containsString:@"volume"]) return @"speaker.wave.2.fill";
    if ([triggerKey containsString:@"power"]) return @"power";
    if ([triggerKey containsString:@"statusbar"]) return @"hand.draw"; // Status bar / screen gestures
    if ([triggerKey containsString:@"home"]) return @"circle.circle"; // Home button
    if ([triggerKey containsString:@"ringer"]) return @"bell.fill";
    if ([triggerKey containsString:@"edge"]) {
        if (@available(iOS 14.2, *)) return @"iphone.homebutton.radiowaves.left.and.right";
        return @"hand.draw";
    }
    if ([triggerKey containsString:@"touchid"]) return @"touchid";
    if ([triggerKey hasPrefix:@"nfc_"]) return @"wave.3.right.circle.fill";
    if ([triggerKey hasPrefix:@"wifi_"]) return @"wifi";
    if ([triggerKey hasPrefix:@"bt_"]) return @"bolt.horizontal.fill";
    if ([triggerKey hasPrefix:@"app_launch_"]) return @"app.badge";
    if ([triggerKey hasPrefix:@"notif_"] || [triggerKey hasPrefix:@"notify_"]) return @"bell.badge.fill";
    if ([triggerKey hasPrefix:@"sched_"]) return @"clock.fill";
    if ([triggerKey hasPrefix:@"mqtt_"] || [triggerKey hasPrefix:@"mqtt_sub_"]) return @"antenna.radiowaves.left.and.right";
    if ([triggerKey isEqualToString:@"shake"]) return @"waveform.path.ecg";
    if ([triggerKey isEqualToString:@"trigger_power_connect"]) return @"bolt.fill";
    if ([triggerKey isEqualToString:@"trigger_power_disconnect"]) return @"bolt.slash.fill";
    if ([triggerKey isEqualToString:@"trigger_device_lock"]) return @"lock.fill";
    if ([triggerKey isEqualToString:@"trigger_device_unlock"]) return @"lock.open.fill";
    if ([triggerKey isEqualToString:@"trigger_media_play"]) return @"play.fill";
    if ([triggerKey isEqualToString:@"trigger_media_pause"]) return @"pause.fill";
    if ([triggerKey isEqualToString:@"trigger_media_track_change"]) return @"forward.fill";
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
    
    self.tableView.rowHeight = 64;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 15; // increased padding
    }
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0); // Reset inset since we have large titles handling spacing better now
    
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 0.1)];
    self.tableView.tableHeaderView.clipsToBounds = YES;

    // Pull-to-refresh
    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [UIColor systemGrayColor];
    [self.refreshControl addTarget:self action:@selector(handleRefresh) forControlEvents:UIControlEventValueChanged];

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
                                               
    [self setupFooterView];
    [self applyTweaks];
}

- (void)handleTweaksChanged:(NSNotification *)note {
    [self applyTweaks];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.view.backgroundColor = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
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
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadTableData];
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
    NSArray *allFavorites = [config orderedFavorites];

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
    addSection(@[@"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right", @"trigger_statusbar_double_tap"], @"Screen Gestures", NO);
    addSection(@[@"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down"], @"Edge Gestures", NO);
    addSection(@[@"trigger_bottombar_swipe_left", @"trigger_bottombar_swipe_right"], @"Bottom Bar Gestures", NO);
    addSection(@[@"trigger_home_double_click", @"trigger_home_triple_click", @"trigger_home_quadruple_click", @"touchid_tap", @"touchid_hold"], @"Home Button", NO);
    addSection(@[@"trigger_ringer_mute", @"trigger_ringer_unmute", @"trigger_ringer_toggle"], @"Ringer Switch", NO);
    // Device State Section (Only show if configured, hide if empty)
    NSMutableArray *deviceStateKeys = [NSMutableArray array];
    NSArray *configuredKeys = [[RCConfigManager sharedManager] allConfiguredTriggerKeys];
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
    if ([configuredKeys containsObject:@"trigger_media_play"]) {
        [deviceStateKeys addObject:@"trigger_media_play"];
    }
    if ([configuredKeys containsObject:@"trigger_media_pause"]) {
        [deviceStateKeys addObject:@"trigger_media_pause"];
    }
    if ([configuredKeys containsObject:@"trigger_media_track_change"]) {
        [deviceStateKeys addObject:@"trigger_media_track_change"];
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

    self.navigationItem.leftBarButtonItem = nil;

    [self.tableView reloadData];
}


- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
}

- (void)openSettings {
    RCSettingsViewController *settingsVC = [[RCSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)addNewItem {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Trigger"
        message:@"Select a trigger type to expand your RemoteCompanion setup."
        preferredStyle:UIAlertControllerStyleActionSheet];
        
    [alert addAction:[UIAlertAction actionWithTitle:@"NFC Tag" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self startNFCScan];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"WiFi Network" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        RCWiFiTriggerViewController *vc = [[RCWiFiTriggerViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Bluetooth Device" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        RCBluetoothTriggerViewController *vc = [[RCBluetoothTriggerViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"App Launch" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        RCAppPickerViewController *vc = [[RCAppPickerViewController alloc] init];
        vc.suppressAutoPop = YES; // We handle navigation ourselves
        vc.onAppSelected = ^(NSString *appName, NSString *bundleId) {
            NSString *triggerKey = [NSString stringWithFormat:@"app_launch_%@", bundleId];
            NSString *friendlyName = [NSString stringWithFormat:@"Launch %@", appName];
            
            NSDictionary *triggerData = @{
                @"name": friendlyName,
                @"enabled": @YES,
                @"actions": @[]
            };
            
            [[RCConfigManager sharedManager] updateTrigger:triggerKey withData:triggerData];
            
            // Push actionsVC, then let the app picker pop (leaving [TriggersVC, ActionsVC])
            RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
            NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
            [vcs removeLastObject]; // Remove the app picker
            [vcs addObject:actionsVC];
            [self.navigationController setViewControllers:vcs animated:YES];
        };
        [self.navigationController pushViewController:vc animated:YES];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Notification" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        RCNotificationTriggerViewController *vc = [[RCNotificationTriggerViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Scheduled Trigger" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        RCScheduledTriggerViewController *vc = [[RCScheduledTriggerViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"MQTT Topic" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        RCMQTTTriggerViewController *vc = [[RCMQTTTriggerViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"System Event" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *systemAlert = [UIAlertController alertControllerWithTitle:@"System Event" message:@"Select a system event to trigger actions." preferredStyle:UIAlertControllerStyleAlert];
        
        [systemAlert addAction:[UIAlertAction actionWithTitle:@"Device Locked" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *key = @"trigger_device_lock";
            if (![[[RCConfigManager sharedManager] allConfiguredTriggerKeys] containsObject:key]) {
                [[RCConfigManager sharedManager] updateTrigger:key withData:@{@"name": @"Device Locked", @"enabled": @YES, @"actions": @[]}];
            }
            RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:key];
            [self.navigationController pushViewController:actionsVC animated:YES];
        }]];
        
        [systemAlert addAction:[UIAlertAction actionWithTitle:@"Device Unlocked" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *key = @"trigger_device_unlock";
            if (![[[RCConfigManager sharedManager] allConfiguredTriggerKeys] containsObject:key]) {
                [[RCConfigManager sharedManager] updateTrigger:key withData:@{@"name": @"Device Unlocked", @"enabled": @YES, @"actions": @[]}];
            }
            RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:key];
            [self.navigationController pushViewController:actionsVC animated:YES];
        }]];
        
        [systemAlert addAction:[UIAlertAction actionWithTitle:@"Power Connected" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *key = @"trigger_power_connect";
            if (![[[RCConfigManager sharedManager] allConfiguredTriggerKeys] containsObject:key]) {
                [[RCConfigManager sharedManager] updateTrigger:key withData:@{@"name": @"Power Connected", @"enabled": @YES, @"actions": @[]}];
            }
            RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:key];
            [self.navigationController pushViewController:actionsVC animated:YES];
        }]];
        
        [systemAlert addAction:[UIAlertAction actionWithTitle:@"Power Disconnected" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *key = @"trigger_power_disconnect";
            if (![[[RCConfigManager sharedManager] allConfiguredTriggerKeys] containsObject:key]) {
                [[RCConfigManager sharedManager] updateTrigger:key withData:@{@"name": @"Power Disconnected", @"enabled": @YES, @"actions": @[]}];
            }
            RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:key];
            [self.navigationController pushViewController:actionsVC animated:YES];
        }]];
        
        [systemAlert addAction:[UIAlertAction actionWithTitle:@"Media Playing" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *key = @"trigger_media_play";
            if (![[[RCConfigManager sharedManager] allConfiguredTriggerKeys] containsObject:key]) {
                [[RCConfigManager sharedManager] updateTrigger:key withData:@{@"name": @"Media Playing", @"enabled": @YES, @"actions": @[]}];
            }
            RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:key];
            [self.navigationController pushViewController:actionsVC animated:YES];
        }]];
        
        [systemAlert addAction:[UIAlertAction actionWithTitle:@"Media Paused" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *key = @"trigger_media_pause";
            if (![[[RCConfigManager sharedManager] allConfiguredTriggerKeys] containsObject:key]) {
                [[RCConfigManager sharedManager] updateTrigger:key withData:@{@"name": @"Media Paused", @"enabled": @YES, @"actions": @[]}];
            }
            RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:key];
            [self.navigationController pushViewController:actionsVC animated:YES];
        }]];
        
        [systemAlert addAction:[UIAlertAction actionWithTitle:@"Media Track Changed" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *key = @"trigger_media_track_change";
            if (![[[RCConfigManager sharedManager] allConfiguredTriggerKeys] containsObject:key]) {
                [[RCConfigManager sharedManager] updateTrigger:key withData:@{@"name": @"Media Track Changed", @"enabled": @YES, @"actions": @[]}];
            }
            RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:key];
            [self.navigationController pushViewController:actionsVC animated:YES];
        }]];
        
        [systemAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:systemAlert animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
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
    
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];
    
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
    
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    [cell setHighlighted:YES animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [cell setHighlighted:NO animated:YES];
    });
    
    NSString *notificationName = [NSString stringWithFormat:@"%s%@", kSimulateNotificationPrefix, triggerKey];
    
    // Slight delay to ensure haptic plays before the app is potentially obscured (e.g., by Control Center or another App)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        notify_post([notificationName UTF8String]);
    });
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _sections.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, tableView.bounds.size.width - 40, 20)];
    label.text = [_sectionTitles[section] uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];

    // Yellow text for Favorites section
    if ([_sectionTitles[section] isEqualToString:@"Favorites"]) {
        label.textColor = [UIColor colorWithRed:242/255.0 green:195/255.0 blue:80/255.0 alpha:1.0];
    } else {
        label.textColor = [UIColor secondaryLabelColor];
    }

    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40.0f;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TriggerCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"TriggerCell"];
    }
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    
    cell.textLabel.text = [config displayNameForTrigger:triggerKey];
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    cell.textLabel.textColor = [UIColor labelColor];
    
    // Add Icon with tint based on section or type?
    // Using dark gray tint for a "premium" but subtle look
    UIImage *icon = [UIImage systemImageNamed:[self iconNameForTrigger:triggerKey]];
    cell.imageView.image = icon;
    cell.imageView.tintColor = [UIColor systemGrayColor];

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
    
    [self applySectionCardStyleToCell:cell atIndexPath:indexPath];

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];
    
    RCActionsViewController *actionsVC = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
    [self.navigationController pushViewController:actionsVC animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];

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
    NSString *triggerKey = _sections[indexPath.section][indexPath.row];

    // Only allow delete for NFC, WiFi, BT, App, Notif, Sched, MQTT, Device State triggers
    if (![triggerKey hasPrefix:@"nfc_"] && ![triggerKey hasPrefix:@"wifi_"] && ![triggerKey hasPrefix:@"bt_"] && ![triggerKey hasPrefix:@"app_launch_"] && ![triggerKey hasPrefix:@"notif_"] && ![triggerKey hasPrefix:@"notify_"] && ![triggerKey hasPrefix:@"sched_"] && ![triggerKey hasPrefix:@"mqtt_"] && ![triggerKey hasPrefix:@"mqtt_sub_"] && ![triggerKey hasPrefix:@"trigger_device_"] && ![triggerKey hasPrefix:@"trigger_media_"]) {
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
    if (_sectionTitles.count > 0 && [_sectionTitles[indexPath.section] isEqualToString:@"Favorites"]) {
        return YES;
    }
    return NO;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (sourceIndexPath.section != proposedDestinationIndexPath.section) {
        NSInteger row = (proposedDestinationIndexPath.section < sourceIndexPath.section) ? 0 : [_sections[sourceIndexPath.section] count] - 1;
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

    NSMutableArray *sectionData = [_sections[sourceIndexPath.section] mutableCopy];
    [sectionData removeObjectAtIndex:sourceIndexPath.row];
    [sectionData insertObject:movedItem atIndex:destinationIndexPath.row];

    NSMutableArray *mutableSections = [_sections mutableCopy];
    mutableSections[sourceIndexPath.section] = sectionData;
    _sections = mutableSections;
}

@end
