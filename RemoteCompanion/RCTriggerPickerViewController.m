#import "RCTriggerPickerViewController.h"
#import "RCTriggersViewController.h"
#import "RCConfigManager.h"

@interface RCTriggerPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *excludedKey;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *sections;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation RCTriggerPickerViewController

- (instancetype)initWithTitle:(NSString *)title excludingTrigger:(NSString *)excludedKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _excludedKey = [excludedKey copy];
        _sections = @[];
        _sectionTitles = @[];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    }

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [self rebuild];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Triggers

// The Triggers screen's section for a trigger
- (NSString *)sectionForTrigger:(NSString *)key {
    if ([key hasPrefix:@"volume_"]) return @"Volume Buttons";
    if ([key hasPrefix:@"power_"]) return @"Power Button";
    if ([key hasPrefix:@"trigger_statusbar_"]) return @"Screen Gestures";
    if ([key hasPrefix:@"trigger_edge_"]) return @"Edge Gestures";
    if ([key hasPrefix:@"trigger_bottombar_"] || [key hasPrefix:@"trigger_bottom_swipe_"]) return @"Bottom Bar Gestures";
    if ([key hasPrefix:@"trigger_home_"] || [key hasPrefix:@"touchid_"]) return @"Home Button";
    if ([key hasPrefix:@"trigger_ringer_"]) return @"Ringer Switch";
    if ([key hasPrefix:@"trigger_watch_"]) return @"Apple Watch";
    if ([key hasPrefix:@"trigger_device_"] || [key hasPrefix:@"trigger_power_"] || [key hasPrefix:@"trigger_carplay_"] || [key hasPrefix:@"trigger_media_"]) return @"Device State";
    if ([key isEqualToString:@"shake"]) return @"Motion Gestures";
    if ([key hasPrefix:@"nfc_"]) return @"NFC Tags";
    if ([key hasPrefix:@"wifi_"]) return @"WiFi Network Triggers";
    if ([key hasPrefix:@"bt_"]) return @"Bluetooth Device Triggers";
    if ([key hasPrefix:@"output_"]) return @"Audio Output Triggers";
    if ([key hasPrefix:@"app_launch_"] || [key hasPrefix:@"app_exit_"]) return @"App Triggers";
    if ([key hasPrefix:@"notif_"] || [key hasPrefix:@"notify_"]) return @"Notification Triggers";
    if ([key hasPrefix:@"sched_"]) return @"Scheduled Triggers";
    if ([key hasPrefix:@"mqtt_"]) return @"MQTT Triggers";
    return @"Other";
}

- (NSArray<NSString *> *)sectionOrder {
    return @[@"Volume Buttons", @"Power Button", @"Screen Gestures", @"Edge Gestures", @"Bottom Bar Gestures", @"Home Button",
             @"Ringer Switch", @"Apple Watch", @"Device State", @"Motion Gestures", @"NFC Tags", @"WiFi Network Triggers",
             @"Bluetooth Device Triggers", @"Audio Output Triggers", @"App Triggers", @"Notification Triggers",
             @"Scheduled Triggers", @"MQTT Triggers", @"Other"];
}

- (NSArray *)actionsForTrigger:(NSString *)key {
    id actions = [[RCConfigManager sharedManager] triggerDataForKey:key][@"actions"];
    return [actions isKindOfClass:[NSArray class]] ? actions : @[];
}

- (void)rebuild {
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSString *search = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableDictionary<NSString *, NSMutableArray *> *bySection = [NSMutableDictionary dictionary];
    for (NSString *key in [config allConfiguredTriggerKeys]) {
        if ([key isEqualToString:self.excludedKey]) continue;
        // Only triggers with actions can be stopped, plus the one the action names now
        if ([self actionsForTrigger:key].count == 0 && ![key isEqualToString:self.currentKey]) continue;
        NSString *name = [config displayNameForTrigger:key];
        if (search.length && [name rangeOfString:search options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        NSString *section = [self sectionForTrigger:key];
        if (!bySection[section]) bySection[section] = [NSMutableArray array];
        [bySection[section] addObject:key];
    }
    NSMutableArray *titles = [NSMutableArray array], *sections = [NSMutableArray array];
    for (NSString *title in [self sectionOrder]) {
        NSMutableArray *keys = bySection[title];
        if (!keys.count) continue;
        [keys sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [[config displayNameForTrigger:a] localizedCaseInsensitiveCompare:[config displayNameForTrigger:b]];
        }];
        [titles addObject:title];
        [sections addObject:keys];
    }
    self.sectionTitles = titles;
    self.sections = sections;
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self rebuild];
}

#pragma mark - Rows

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAX(self.sections.count, 1);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections.count ? self.sections[section].count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections.count ? self.sectionTitles[section] : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == MAX((NSInteger)self.sections.count, 1) - 1 ? self.footerText : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;

    if (!self.sections.count) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.text = self.searchController.searchBar.text.length ? @"No matching triggers" : @"No other triggers have actions";
        return cell;
    }

    NSString *key = self.sections[indexPath.section][indexPath.row];
    cell.textLabel.text = [cm displayNameForTrigger:key];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.imageView.image = [UIImage systemImageNamed:[RCTriggersViewController iconNameForTrigger:key]];
    cell.imageView.tintColor = [UIColor systemGrayColor];

    // Its actions, as on the Triggers screen
    NSArray *actions = [self actionsForTrigger:key];
    NSMutableArray *names = [NSMutableArray array];
    for (id action in actions) {
        NSString *name = [cm nameForCommand:action truncate:YES];
        if (name.length) [names addObject:name];
    }
    cell.detailTextLabel.text = names.count ? [names componentsJoinedByString:@" > "] : @"No actions";
    cell.detailTextLabel.textColor = names.count ? [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];

    cell.accessoryType = [key isEqualToString:self.currentKey] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.sections.count > 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.sections.count) return;
    if (self.onSelected) self.onSelected(self.sections[indexPath.section][indexPath.row]);
}

@end
