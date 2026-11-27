#import "RCTweaksViewController.h"
#import "RCConfigManager.h"
#import "RCSettingsPageViewController.h"

@interface RCTweaksViewController ()
@property (nonatomic, strong) UITableView *tableView;
@end

// Each switch reads as what it turns on, so on means the iOS behaviour is kept: the config keeps
// its "disable" settings, and the switch shows the opposite.
// Rows: {id, title, symbol, color, get, set}; sections: {title, symbol, rows, footer}
static NSArray<NSDictionary *> *RCTweaksSections(void) {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *orange = [UIColor systemOrangeColor];
    return @[
        @{ @"title": @"Power", @"symbol": @"bolt.fill",
           @"footer": @"Wake Screen on Power turns the screen on when power connects or disconnects. Charging Haptics plays the vibration and chime when power connects. Charging triggers run either way.",
           @"rows": @[
               @{ @"id": @"wakeOnPower", @"title": @"Wake Screen on Power", @"symbol": @"sun.max.fill", @"color": [UIColor systemYellowColor],
                  @"get": ^BOOL{ return !cm.disableWakeOnPower; }, @"set": ^(BOOL on) { cm.disableWakeOnPower = !on; } },
               @{ @"id": @"chargingHaptics", @"title": @"Charging Haptics", @"symbol": @"bolt.circle.fill", @"color": orange,
                  @"get": ^BOOL{ return !cm.disablePowerConnectedHaptics; }, @"set": ^(BOOL on) { cm.disablePowerConnectedHaptics = !on; } },
           ] },
        @{ @"title": @"Notifications", @"symbol": @"bell.fill",
           @"footer": @"Vibrate When Unlocked lets notifications vibrate while the phone is unlocked; banners, sounds, alarms, calls and critical alerts are the same either way. Send to Watch When Unlocked forwards notifications to Apple Watch even while the iPhone is unlocked, following each app's Watch settings.",
           @"rows": @[
               @{ @"id": @"vibrateUnlocked", @"title": @"Vibrate When Unlocked", @"symbol": @"iphone.radiowaves.left.and.right", @"color": [UIColor systemRedColor],
                  @"get": ^BOOL{ return !cm.disableUnlockedNotificationVibration; }, @"set": ^(BOOL on) { cm.disableUnlockedNotificationVibration = !on; } },
               @{ @"id": @"watchUnlocked", @"title": @"Send to Watch When Unlocked", @"symbol": @"applewatch", @"color": [UIColor systemGreenColor],
                  @"get": ^BOOL{ return cm.sendNotificationsToWatchWhenUnlocked; }, @"set": ^(BOOL on) { cm.sendNotificationsToWatchWhenUnlocked = on; } },
           ] },
    ];
}

@implementation RCTweaksViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"iOS Tweaks";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 50;

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }

    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleTweaksChanged:)
                                                 name:@"RCConfigTweaksChangedNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleConfigChanged:)
                                                 name:RCConfigChangedNotification
                                               object:nil];
    [self applyTweaks];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleTweaksChanged:(NSNotification *)note {
    [self applyTweaks];
}

- (void)handleConfigChanged:(NSNotification *)note {
    [self.tableView reloadData];
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
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self applyTweaks];
        }
    }
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)searchEntries {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSDictionary *section in RCTweaksSections()) {
        for (NSDictionary *row in section[@"rows"]) [entries addObject:@{ @"title": row[@"title"], @"rowID": row[@"id"] }];
    }
    return entries;
}

// A search result: scroll to its row and flash it
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSString *rowID = self.highlightRowID;
    if (!rowID) return;
    self.highlightRowID = nil;
    NSArray *sections = RCTweaksSections();
    for (NSUInteger s = 0; s < sections.count; s++) {
        NSUInteger r = [[sections[s][@"rows"] valueForKey:@"id"] indexOfObject:rowID];
        if (r == NSNotFound) continue;
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:r inSection:s];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        UIColor *background = cell.backgroundColor;
        cell.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
        [UIView animateWithDuration:0.6 delay:0.8 options:0 animations:^{ cell.backgroundColor = background; } completion:nil];
        return;
    }
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RCTweaksSections().count;
}

// The section's symbol before its name, as on Settings
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSDictionary *info = RCTweaksSections()[section];
    CGFloat height = [self tableView:tableView heightForHeaderInSection:section];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, height)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(42, height - 24, tableView.bounds.size.width - 62, 20)];
    label.text = [info[@"title"] uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [header addSubview:label];
    UIImage *image = [UIImage systemImageNamed:info[@"symbol"] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]];
    UIImageView *icon = [[UIImageView alloc] initWithImage:image];
    icon.tintColor = [UIColor secondaryLabelColor];
    icon.contentMode = UIViewContentModeCenter;
    icon.frame = CGRectMake(20, label.frame.origin.y, 16, 20);
    [header addSubview:icon];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 32.0 : 38.0;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return RCTweaksSections()[section][@"footer"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return RCSettingsRowHeight(tableView, [self tableView:tableView cellForRowAtIndexPath:indexPath]);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [RCTweaksSections()[section][@"rows"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSDictionary *row = RCTweaksSections()[indexPath.section][@"rows"][indexPath.row];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.masksToBounds = YES;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.numberOfLines = 0; // a long name wraps (RCSettingsRowHeight)
    cell.imageView.image = RCSettingsIcon(row[@"symbol"], row[@"color"]);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = ((BOOL (^)(void))row[@"get"])();
    toggle.tag = indexPath.section * 100 + indexPath.row;
    [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

#pragma mark - Actions

- (void)switchChanged:(UISwitch *)sender {
    NSDictionary *row = RCTweaksSections()[sender.tag / 100][@"rows"][sender.tag % 100];
    ((void (^)(BOOL))row[@"set"])(sender.on);
}

@end
