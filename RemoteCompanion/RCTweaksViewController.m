#import "RCTweaksViewController.h"
#import "RCConfigManager.h"

@interface RCTweaksViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *disableWakeOnPowerSwitch;
@property (nonatomic, strong) UISwitch *disablePowerConnectedHapticsSwitch;
@property (nonatomic, strong) UISwitch *disableUnlockedNotificationVibrationSwitch;
@end

typedef NS_ENUM(NSInteger, RCTweaksSection) {
    RCTweaksSectionPower,
    RCTweaksSectionNotifications,
    RCTweaksSectionCount,
};

@implementation RCTweaksViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Tweaks";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 50;

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
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

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RCTweaksSectionCount;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = @"";
    if (section == RCTweaksSectionPower) title = @"Power";
    else if (section == RCTweaksSectionNotifications) title = @"Notifications";

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

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCTweaksSectionPower) {
        return @"Disable Wake Screen On Power keeps the screen off when power connects or disconnects while the display is off or dimmed. Disable Power Connected Haptics stops the charging vibration and chime when power connects. Battery status and charging triggers still update normally.";
    } else if (section == RCTweaksSectionNotifications) {
        return @"Turns off notification vibration while the phone is unlocked. Banners and notification sounds still play normally, and alarms, timers, calls, and critical alerts still vibrate.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RCTweaksSectionPower) return 2;
    if (section == RCTweaksSectionNotifications) return 1;
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];

    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;

    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.masksToBounds = YES;
    cell.textLabel.textColor = [UIColor labelColor];

    if (indexPath.section == RCTweaksSectionPower && indexPath.row == 0) {
        cell.textLabel.text = @"Disable Wake Screen On Power";
        self.disableWakeOnPowerSwitch = [[UISwitch alloc] init];
        self.disableWakeOnPowerSwitch.on = cm.disableWakeOnPower;
        [self.disableWakeOnPowerSwitch addTarget:self action:@selector(disableWakeOnPowerChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.disableWakeOnPowerSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == RCTweaksSectionPower && indexPath.row == 1) {
        cell.textLabel.text = @"Disable Power Connected Haptics";
        self.disablePowerConnectedHapticsSwitch = [[UISwitch alloc] init];
        self.disablePowerConnectedHapticsSwitch.on = cm.disablePowerConnectedHaptics;
        [self.disablePowerConnectedHapticsSwitch addTarget:self action:@selector(disablePowerConnectedHapticsChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.disablePowerConnectedHapticsSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == RCTweaksSectionNotifications && indexPath.row == 0) {
        cell.textLabel.text = @"Disable Vibration When Unlocked";
        self.disableUnlockedNotificationVibrationSwitch = [[UISwitch alloc] init];
        self.disableUnlockedNotificationVibrationSwitch.on = cm.disableUnlockedNotificationVibration;
        [self.disableUnlockedNotificationVibrationSwitch addTarget:self action:@selector(disableUnlockedNotificationVibrationChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.disableUnlockedNotificationVibrationSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    return cell;
}

#pragma mark - Actions

- (void)disableWakeOnPowerChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].disableWakeOnPower = sender.on;
}

- (void)disablePowerConnectedHapticsChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].disablePowerConnectedHaptics = sender.on;
}

- (void)disableUnlockedNotificationVibrationChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].disableUnlockedNotificationVibration = sender.on;
}

@end
