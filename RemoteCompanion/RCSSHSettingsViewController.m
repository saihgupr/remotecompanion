#import "RCSSHSettingsViewController.h"
#import "RCSSHHostEditorViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"

@interface RCSSHSettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation RCSSHSettingsViewController

+ (BOOL)hasExecutableNamed:(NSString *)name {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *prefixes = @[
        @"/var/jb/usr/local/bin",
        @"/var/jb/usr/bin",
        @"/var/jb/bin",
        @"/usr/local/bin",
        @"/usr/bin",
        @"/bin"
    ];
    for (NSString *prefix in prefixes) {
        if ([fm isExecutableFileAtPath:[prefix stringByAppendingPathComponent:name]]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isSSHInstalled {
    return [self hasExecutableNamed:@"ssh"];
}

+ (BOOL)isSSHPassInstalled {
    return [self hasExecutableNamed:@"sshpass"];
}

+ (void)presentMissingPackageAlertInViewController:(UIViewController *)viewController
                                             title:(NSString *)title
                                           message:(NSString *)message
                                       packageName:(NSString *)packageName {
    if (!viewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIApplication *app = [UIApplication sharedApplication];
    NSURL *sileoURL = [NSURL URLWithString:[NSString stringWithFormat:@"sileo://package/%@", packageName]];
    NSURL *zebraURL = [NSURL URLWithString:[NSString stringWithFormat:@"zbra://packages/%@", packageName]];
    if (sileoURL && [app canOpenURL:sileoURL]) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Open in Sileo" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [app openURL:sileoURL options:@{} completionHandler:nil];
        }]];
    } else if (zebraURL && [app canOpenURL:zebraURL]) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Open in Zebra" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [app openURL:zebraURL options:@{} completionHandler:nil];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [viewController presentViewController:alert animated:YES completion:nil];
}

+ (BOOL)ensureSSHInstalledInViewController:(UIViewController *)viewController requireSSHPass:(BOOL)requireSSHPass {
    if (![self isSSHInstalled]) {
        [self presentMissingPackageAlertInViewController:viewController
                                                   title:@"OpenSSH Required"
                                                 message:@"SSH features require the openssh-client package. Install openssh-client from Sileo or Zebra to use SSH."
                                             packageName:@"openssh-client"];
        return NO;
    }
    if (requireSSHPass && ![self isSSHPassInstalled]) {
        [self presentMissingPackageAlertInViewController:viewController
                                                   title:@"sshpass Required"
                                                 message:@"Password-based SSH authentication requires the sshpass package. Install sshpass from Sileo or Zebra, or switch to Key authentication."
                                             packageName:@"sshpass"];
        return NO;
    }
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"SSH Hosts";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] 
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd 
        target:self 
        action:@selector(addNewHost)];

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

- (void)addNewHost {
    if (![RCSSHSettingsViewController ensureSSHInstalledInViewController:self requireSSHPass:NO]) {
        return;
    }
    [self presentHostEditorForHost:nil];
}

- (void)presentHostEditorForHost:(NSDictionary *)existingHost {
    RCSSHHostEditorViewController *editor = [[RCSSHHostEditorViewController alloc] initWithHost:existingHost];
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *hosts = [RCConfigManager sharedManager].sshHosts;
    return hosts.count > 0 ? hosts.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Configured Hosts";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"SSH hosts configured here can be targeted from triggers to run remote commands over SSH via OpenSSH or sshpass.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSArray *hosts = cm.sshHosts;
    
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
    
    if (hosts.count == 0) {
        cell.textLabel.text = @"No SSH Hosts Configured";
        cell.detailTextLabel.text = @"Tap + in the top right to add a host";
        cell.imageView.image = [UIImage systemImageNamed:@"terminal"];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    
    NSDictionary *host = hosts[indexPath.row];
    cell.textLabel.text = host[@"name"] ?: host[@"host"];
    
    NSString *authDesc = [host[@"authType"] isEqualToString:@"key"] ? @"Key" : @"Password";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@@%@:%@ (%@)", host[@"user"] ?: @"", host[@"host"] ?: @"", host[@"port"] ?: @22, authDesc];
    cell.imageView.image = [UIImage systemImageNamed:@"terminal.fill"];
    cell.imageView.tintColor = [UIColor systemOrangeColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *hosts = [RCConfigManager sharedManager].sshHosts;
    if (hosts.count == 0) {
        [self addNewHost];
        return;
    }
    NSDictionary *host = hosts[indexPath.row];
    [self presentHostEditorForHost:host];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [RCConfigManager sharedManager].sshHosts.count > 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSArray *hosts = [RCConfigManager sharedManager].sshHosts;
        if (indexPath.row < hosts.count) {
            NSDictionary *host = hosts[indexPath.row];
            [[RCConfigManager sharedManager] deleteSSHHostWithId:host[@"id"]];
            [tableView reloadData];
        }
    }
}

@end

