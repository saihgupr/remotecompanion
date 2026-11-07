#import "RCIntegrationsViewController.h"
#import "RCHASettingsViewController.h"
#import "RCKMSettingsViewController.h"
#import "RCMQTTSettingsViewController.h"
#import "RCSSHSettingsViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"

@interface RCIntegrationsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation RCIntegrationsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Integrations";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 60;
    
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
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Configure external service integrations to trigger actions and control third-party automations.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;

    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.masksToBounds = YES;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    if (indexPath.row == 0) {
        cell.textLabel.text = @"Home Assistant";
        cell.detailTextLabel.text = cm.haEnabled ? (cm.haUrl.length ? cm.haUrl : @"Enabled (URL not configured)") : @"Disabled";
        cell.imageView.image = [UIImage systemImageNamed:@"house.fill"];
        cell.imageView.tintColor = cm.haEnabled ? [UIColor systemBlueColor] : [UIColor secondaryLabelColor];
    } else if (indexPath.row == 1) {
        cell.textLabel.text = @"Keyboard Maestro";
        cell.detailTextLabel.text = cm.kmEnabled ? (cm.kmUrl.length ? cm.kmUrl : @"Enabled (Default URL)") : @"Disabled";
        cell.imageView.image = [UIImage systemImageNamed:@"keyboard.fill"];
        cell.imageView.tintColor = cm.kmEnabled ? [UIColor systemPurpleColor] : [UIColor secondaryLabelColor];
    } else if (indexPath.row == 2) {
        cell.textLabel.text = @"MQTT";
        NSString *hostStr = cm.mqttHost.length ? [NSString stringWithFormat:@"%@:%ld", cm.mqttHost, (long)(cm.mqttPort > 0 ? cm.mqttPort : 1883)] : @"Enabled";
        cell.detailTextLabel.text = cm.mqttEnabled ? hostStr : @"Disabled";
        cell.imageView.image = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
        cell.imageView.tintColor = cm.mqttEnabled ? [UIColor systemTealColor] : [UIColor secondaryLabelColor];
    } else if (indexPath.row == 3) {
        cell.textLabel.text = @"SSH Hosts";
        NSUInteger count = cm.sshHosts.count;
        cell.detailTextLabel.text = count > 0 ? [NSString stringWithFormat:@"%lu Host%@", (unsigned long)count, count == 1 ? @"" : @"s"] : @"None Configured";
        cell.imageView.image = [UIImage systemImageNamed:@"terminal.fill"];
        cell.imageView.tintColor = count > 0 ? [UIColor systemOrangeColor] : [UIColor secondaryLabelColor];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 0) {
        RCHASettingsViewController *haVC = [[RCHASettingsViewController alloc] init];
        [self.navigationController pushViewController:haVC animated:YES];
    } else if (indexPath.row == 1) {
        RCKMSettingsViewController *kmVC = [[RCKMSettingsViewController alloc] init];
        [self.navigationController pushViewController:kmVC animated:YES];
    } else if (indexPath.row == 2) {
        RCMQTTSettingsViewController *mqttVC = [[RCMQTTSettingsViewController alloc] init];
        [self.navigationController pushViewController:mqttVC animated:YES];
    } else if (indexPath.row == 3) {
        RCSSHSettingsViewController *sshVC = [[RCSSHSettingsViewController alloc] init];
        [self.navigationController pushViewController:sshVC animated:YES];
    }
}

@end
