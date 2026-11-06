#import "RCExcludedAppsViewController.h"
#import "RCConfigManager+AppExclusions.h"
#import "RCAppPickerViewController.h"

// Private API Declarations (same as the app picker)
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end

@interface RCExcludedAppsViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *sections;
@property (nonatomic, copy) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *appNames; // lowercase bundle id -> display name
@end

@implementation RCExcludedAppsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Excluded Apps";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] ? UITableViewAutomaticDimension : 64.0;
    self.tableView.estimatedRowHeight = 90;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.tableView.backgroundColor = [cm tweakColorForKey:@"settingsBackground"
                                             defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    // Setup Search
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Triggers";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wrapLongNamesSettingChanged:) name:@"RCWrapLongNamesSettingChanged" object:nil];

    [self loadAppNames];
}

// Bundle id -> display name, so excluded apps show by name instead of by id.
// Loaded once; ids without a match (uninstalled apps) fall back to the id.
- (void)loadAppNames {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        NSArray<LSApplicationProxy *> *apps = [[workspaceClass defaultWorkspace] allInstalledApplications];
        NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
        for (LSApplicationProxy *app in apps) {
            if (app.applicationIdentifier.length && app.localizedName.length) {
                names[app.applicationIdentifier.lowercaseString] = app.localizedName;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.appNames = names;
            [self.tableView reloadData];
        });
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSections];
}

- (void)wrapLongNamesSettingChanged:(NSNotification *)note {
    self.tableView.rowHeight = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] ? UITableViewAutomaticDimension : 64.0;
    [self.tableView reloadData];
}

// Same section order and key mapping as RCTriggersViewController, limited to
// triggers that have assigned actions. Sections with nothing to show are left out.
- (void)reloadSections {
    NSString *text = self.searchController.searchBar.text ?: @"";
    RCConfigManager *config = [RCConfigManager sharedManager];

    NSArray<NSString *> *assigned = [config assignedAppExclusionTriggerKeys];
    NSSet<NSString *> *assignedSet = [NSSet setWithArray:assigned];

    // Assigned triggers only, narrowed to the search text when one is active.
    NSArray* (^visibleKeys)(NSArray*) = ^NSArray*(NSArray *keys) {
        NSMutableArray<NSString *> *result = [NSMutableArray array];
        for (NSString *key in keys) {
            if (![assignedSet containsObject:key]) continue;
            if (text.length) {
                NSString *name = [config displayNameForTrigger:key] ?: key;
                if ([name rangeOfString:text options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
            }
            [result addObject:key];
        }
        return result;
    };

    NSMutableArray<NSArray<NSString *> *> *sections = [NSMutableArray array];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableSet<NSString *> *grouped = [NSMutableSet set];

    void (^addSection)(NSArray *, NSString *) = ^(NSArray *keys, NSString *title) {
        NSMutableArray<NSString *> *rows = [NSMutableArray array];
        for (NSString *key in visibleKeys(keys)) {
            if ([config isTriggerFavorite:key]) continue;
            [rows addObject:key];
        }
        if (rows.count == 0) return;
        [sections addObject:rows];
        [titles addObject:title];
        [grouped addObjectsFromArray:rows];
    };

    // Favorites come first, as on the Triggers screen, and are not repeated in
    // their own section below.
    NSArray<NSString *> *favorites = visibleKeys([config orderedFavorites]);
    if (favorites.count > 0) {
        [sections addObject:favorites];
        [titles addObject:@"Favorites"];
        [grouped addObjectsFromArray:favorites];
    }

    addSection(@[@"volume_up_hold", @"volume_down_hold", @"volume_both_press", @"volume_up_then_down", @"volume_down_then_up"], @"Volume Buttons");
    addSection(@[@"power_double_tap", @"power_triple_click", @"power_quadruple_click", @"power_volume_up", @"power_volume_down", @"power_long_press"], @"Power Button");
    addSection(@[@"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right", @"trigger_statusbar_double_tap"], @"Screen Gestures");
    addSection(@[@"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down"], @"Edge Gestures");
    addSection(@[@"trigger_bottombar_swipe_left", @"trigger_bottombar_swipe_right", @"trigger_bottom_swipe_up_left", @"trigger_bottom_swipe_up_center", @"trigger_bottom_swipe_up_right"], @"Bottom Bar Gestures");
    addSection(@[@"trigger_statusbar_two_finger_swipe_down", @"trigger_bottom_two_finger_swipe_up"], @"Multi-Finger Gestures");
    if ([RCConfigManager hasHomeButton]) {
        addSection(@[@"trigger_home_double_click", @"trigger_home_triple_click", @"trigger_home_quadruple_click", @"trigger_home_hold", @"trigger_home_power", @"touchid_tap", @"touchid_hold"], @"Home Button");
    }
    addSection(@[@"trigger_ringer_mute", @"trigger_ringer_unmute", @"trigger_ringer_toggle"], @"Ringer Switch");
    addSection(@[@"trigger_watch_ping", @"trigger_watch_ping_hold"], @"Apple Watch");

    // Device State, ordered as on the Triggers screen: Focus, Battery, then the
    // single-instance device triggers in their fixed order.
    NSMutableArray<NSString *> *deviceStateKeys = [NSMutableArray array];
    NSArray<NSString *> *configuredKeys = [config allConfiguredTriggerKeys];

    NSMutableArray<NSString *> *focusKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
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

    // Battery Level triggers, lowest level first
    NSMutableArray<NSString *> *batteryKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"trigger_device_battery_"]) [batteryKeys addObject:key];
    }
    [batteryKeys sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSString *(^level)(NSString *) = ^NSString *(NSString *key) {
            return key.length > 29 ? [key substringFromIndex:29] : @"";
        };
        NSComparisonResult byLevel = [@([level(a) integerValue]) compare:@([level(b) integerValue])];
        return byLevel != NSOrderedSame ? byLevel : [b compare:a]; // "below" before "above"
    }];
    [deviceStateKeys addObjectsFromArray:batteryKeys];

    for (NSString *key in @[@"trigger_device_lock", @"trigger_device_unlock", @"trigger_power_connect", @"trigger_power_disconnect", @"trigger_device_rotated_landscape", @"trigger_device_rotated_portrait", @"trigger_carplay_connect", @"trigger_carplay_disconnect", @"trigger_device_findmy_sound", @"trigger_media_play", @"trigger_media_pause", @"trigger_media_track_change", @"trigger_device_call_incoming", @"trigger_device_call_start", @"trigger_device_call_end"]) {
        if ([configuredKeys containsObject:key]) [deviceStateKeys addObject:key];
    }
    addSection(deviceStateKeys, @"Device State");

    addSection(@[@"shake"], @"Motion Gestures");

    addSection([config nfcTriggerKeys], @"NFC Tags");

    NSMutableArray<NSString *> *wifiKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"wifi_"]) [wifiKeys addObject:key];
    }
    addSection(wifiKeys, @"WiFi Network Triggers");

    NSMutableArray<NSString *> *btKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"bt_"]) [btKeys addObject:key];
    }
    addSection(btKeys, @"Bluetooth Device Triggers");

    NSMutableArray<NSString *> *outputKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"output_"]) [outputKeys addObject:key];
    }
    addSection(outputKeys, @"Audio Output Triggers");

    NSMutableArray<NSString *> *notifKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"notif_"] || [key hasPrefix:@"notify_"]) [notifKeys addObject:key];
    }
    addSection(notifKeys, @"Notification Triggers");

    NSMutableArray<NSString *> *appKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"app_launch_"]) [appKeys addObject:key];
    }
    addSection(appKeys, @"App Launch Triggers");

    NSMutableArray<NSString *> *appExitKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"app_exit_"]) [appExitKeys addObject:key];
    }
    addSection(appExitKeys, @"App Exit Triggers");

    NSMutableArray<NSString *> *schedKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"sched_"]) [schedKeys addObject:key];
    }
    addSection(schedKeys, @"Scheduled Triggers");

    NSMutableArray<NSString *> *mqttKeys = [NSMutableArray array];
    for (NSString *key in configuredKeys) {
        if ([key hasPrefix:@"mqtt_sub_"] || [key hasPrefix:@"mqtt_"]) [mqttKeys addObject:key];
    }
    addSection(mqttKeys, @"MQTT Subscription Triggers");

    // Assigned keys the Triggers screen has no section for (for example one left
    // behind by a newer or custom trigger) still need a row.
    NSMutableArray<NSString *> *otherKeys = [NSMutableArray array];
    for (NSString *key in visibleKeys(assigned)) {
        if (![grouped containsObject:key]) [otherKeys addObject:key];
    }
    [otherKeys sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [[config displayNameForTrigger:a] localizedCaseInsensitiveCompare:[config displayNameForTrigger:b]];
    }];
    if (otherKeys.count > 0) {
        [sections addObject:otherKeys];
        [titles addObject:@"Other Triggers"];
    }

    self.sections = sections;
    self.sectionTitles = titles;
    [self.tableView reloadData];
}

- (NSString *)triggerKeyAtIndexPath:(NSIndexPath *)indexPath {
    return self.sections[indexPath.section][indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sectionTitles[section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Rows with excluded apps need room for the second line even when
    // Wrap Long Names is off.
    NSString *key = [self triggerKeyAtIndexPath:indexPath];
    if ([[RCConfigManager sharedManager] excludedAppsForTrigger:key].count > 0) {
        return UITableViewAutomaticDimension;
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] ? UITableViewAutomaticDimension : 64.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSString *key = [self triggerKeyAtIndexPath:indexPath];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    BOOL wrapLongNames = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.text = [cm displayNameForTrigger:key];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.numberOfLines = wrapLongNames ? 0 : 1;
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (id action in [cm actionsForTrigger:key]) {
        [labels addObject:[cm nameForCommand:action truncate:YES] ?: @"Action"];
    }
    NSUInteger count = [cm excludedAppsForTrigger:key].count;
    NSString *actionsLine = [labels componentsJoinedByString:@" · "];
    if (![cm isTriggerEnabled:key]) actionsLine = [@"Disabled · " stringByAppendingString:actionsLine];
    NSMutableAttributedString *detail = [[NSMutableAttributedString alloc] initWithString:actionsLine
        attributes:@{NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}];
    if (count > 0) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *bundleID in [cm excludedAppsForTrigger:key]) {
            NSString *name = self.appNames[[bundleID lowercaseString]];
            [names addObject:name.length ? name : bundleID];
        }
        NSString *excludedLine = [NSString stringWithFormat:@"Excluded: %@ (%lu)",
            [names componentsJoinedByString:@", "], (unsigned long)count];
        NSMutableAttributedString *excluded = [[NSMutableAttributedString alloc] initWithString:excludedLine
            attributes:@{NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}];
        NSRange namesRange = [excludedLine rangeOfString:[names componentsJoinedByString:@", "]];
        if (namesRange.location != NSNotFound) {
            [excluded addAttribute:NSForegroundColorAttributeName value:[UIColor systemRedColor] range:namesRange];
        }
        // Always its own line: squeezed onto the actions line it truncates
        // before the names ever show when Wrap Long Names is off.
        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [detail appendAttributedString:excluded];
    }
    cell.detailTextLabel.attributedText = detail;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = (count > 0 || wrapLongNames) ? 0 : 1;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *key = [self triggerKeyAtIndexPath:indexPath];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    RCAppPickerViewController *picker = [[RCAppPickerViewController alloc] init];
    picker.allowsMultipleApps = YES;
    picker.allowsEmptySelection = YES;
    picker.selectedBundleIds = [cm excludedAppsForTrigger:key];
    picker.onAppsSelected = ^(NSArray<NSString *> *names, NSArray<NSString *> *bundleIDs) {
        [[RCConfigManager sharedManager] setExcludedApps:bundleIDs forTrigger:key];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reloadSections];
}

@end
