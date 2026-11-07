#import "RCIntegrationsViewController.h"
#import "RCHASettingsViewController.h"
#import "RCKMSettingsViewController.h"
#import "RCMQTTSettingsViewController.h"
#import "RCAddOnsViewController.h"
#import "RCAddOnDetailViewController.h"
#import "RCAddOnCatalog.h"
#import <notify.h>
#import "RCSSHSettingsViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"

// Two sections: the integrations RemoteCompanion has itself, then the add-ons other apps and
// tweaks install (ADDONS.md), one row each, with rows for any not installed or with a problem
typedef NS_ENUM(NSInteger, RCIntegrationsSection) {
    RCIntegrationsSectionNative = 0,
    RCIntegrationsSectionAddOns,
};

@interface RCIntegrationsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *addOnRows;   // { kind: addon|absent|problems|none, ... }
@property (nonatomic, assign) int changeToken;
@end

@implementation RCIntegrationsViewController

- (instancetype)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
    if ((self = [super initWithNibName:nibName bundle:bundle])) _changeToken = NOTIFY_TOKEN_INVALID;
    return self;
}

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
    // The add-ons section follows the tweak's catalog as add-ons are installed, changed or removed
    int token = NOTIFY_TOKEN_INVALID;
    __weak typeof(self) weakSelf = self;
    if (notify_register_dispatch([RCAddOnCatalog changedNotification], &token, dispatch_get_main_queue(), ^(int t) {
        [weakSelf reloadAddOns];
    }) == NOTIFY_STATUS_OK) self.changeToken = token;
    [self applyTweaks];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadAddOns];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_changeToken != NOTIFY_TOKEN_INVALID) notify_cancel(_changeToken);
}

// What the add-on section shows: each add-on (on or off) by name, then rows for those not
// installed and the files with problems
- (void)reloadAddOns {
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *addOns = [NSMutableArray array];
    for (NSDictionary *addOn in [RCAddOnCatalog addOns]) [addOns addObject:@{ @"kind": @"addon", @"addOn": addOn, @"on": @YES }];
    for (NSDictionary *addOn in [RCAddOnCatalog disabledAddOns]) [addOns addObject:@{ @"kind": @"addon", @"addOn": addOn, @"on": @NO }];
    [addOns sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"addOn"][@"name"] localizedCaseInsensitiveCompare:b[@"addOn"][@"name"]];
    }];
    [rows addObjectsFromArray:addOns];
    NSUInteger absent = [RCAddOnCatalog absentAddOnNames].count;
    NSUInteger problems = [RCAddOnCatalog problems].count + ([RCAddOnCatalog catalogAvailable] && ![RCAddOnCatalog commandsScriptLoaded] ? 1 : 0);
    if (absent) [rows addObject:@{ @"kind": @"absent", @"count": @(absent) }];
    if (problems) [rows addObject:@{ @"kind": @"problems", @"count": @(problems) }];
    if (!rows.count) [rows addObject:@{ @"kind": @"none" }];
    self.addOnRows = rows;
    [self.tableView reloadData];
}

// "3 actions · 2 triggers · 1 condition"
+ (NSString *)contentsOfAddOn:(NSDictionary *)addOn {
    NSUInteger actions = [addOn[@"actions"] isKindOfClass:[NSArray class]] ? [addOn[@"actions"] count] : 0;
    NSUInteger triggers = 0, conditions = [addOn[@"conditions"] isKindOfClass:[NSArray class]] ? [addOn[@"conditions"] count] : 0;
    for (NSDictionary *event in [addOn[@"events"] isKindOfClass:[NSArray class]] ? addOn[@"events"] : @[]) if ([event isKindOfClass:[NSDictionary class]] && event[@"trigger"]) triggers++;
    NSMutableArray *parts = [NSMutableArray array];
    void (^add)(NSUInteger, NSString *) = ^(NSUInteger n, NSString *word) {
        if (n) [parts addObject:[NSString stringWithFormat:@"%lu %@%@", (unsigned long)n, word, n == 1 ? @"" : @"s"]];
    };
    add(actions, @"action");
    add(triggers, @"trigger");
    add(conditions, @"condition");
    return [parts componentsJoinedByString:@" · "];
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
    // No add-ons section until the tweak has written its catalog
    return [RCAddOnCatalog catalogAvailable] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == RCIntegrationsSectionNative ? 4 : (NSInteger)self.addOnRows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == RCIntegrationsSectionAddOns ? @"Add-ons" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCIntegrationsSectionNative) return @"Configure external service integrations to trigger actions and control third-party automations.";
    return @"Added by other apps and tweaks.";
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

    if (indexPath.section == RCIntegrationsSectionAddOns) {
        NSDictionary *row = self.addOnRows[indexPath.row];
        NSString *kind = row[@"kind"];
        if ([kind isEqualToString:@"addon"]) {
            NSDictionary *addOn = row[@"addOn"];
            BOOL on = [row[@"on"] boolValue];
            cell.textLabel.text = addOn[@"name"];
            cell.detailTextLabel.text = on ? [RCIntegrationsViewController contentsOfAddOn:addOn] : @"Off";
            cell.imageView.image = [RCAddOnCatalog iconImageForAddOn:addOn] ?: [UIImage systemImageNamed:[RCAddOnCatalog iconForAddOn:addOn]];
            cell.imageView.tintColor = on ? [UIColor systemOrangeColor] : [UIColor secondaryLabelColor];
            cell.imageView.alpha = on ? 1.0 : 0.5;
        } else if ([kind isEqualToString:@"absent"]) {
            cell.textLabel.text = @"Not Installed";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ add-on%@ for apps or tweaks that aren't installed", row[@"count"], [row[@"count"] integerValue] == 1 ? @"" : @"s"];
            cell.imageView.image = [UIImage systemImageNamed:[RCAddOnCatalog defaultSymbol]];
            cell.imageView.tintColor = [UIColor secondaryLabelColor];
        } else if ([kind isEqualToString:@"problems"]) {
            cell.textLabel.text = @"Problems";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ file%@ not loaded", row[@"count"], [row[@"count"] integerValue] == 1 ? @"" : @"s"];
            cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
            cell.imageView.tintColor = [UIColor systemOrangeColor];
        } else {
            cell.textLabel.text = @"None";
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        return cell;
    }
    
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
    if (indexPath.section == RCIntegrationsSectionAddOns) {
        NSDictionary *row = self.addOnRows[indexPath.row];
        NSString *kind = row[@"kind"];
        UIViewController *next = nil;
        if ([kind isEqualToString:@"addon"]) next = [[RCAddOnDetailViewController alloc] initWithAddOnId:row[@"addOn"][@"id"]];
        else if ([kind isEqualToString:@"absent"]) next = [[RCAddOnsViewController alloc] initShowing:RCAddOnsListNotInstalled];
        else if ([kind isEqualToString:@"problems"]) next = [[RCAddOnsViewController alloc] initShowing:RCAddOnsListProblems];
        if (next) [self.navigationController pushViewController:next animated:YES];
        return;
    }
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
