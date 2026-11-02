#import "RCSSHSettingsViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"

@interface RCSSHSettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation RCSSHSettingsViewController

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
    [self presentHostEditorForHost:nil];
}

- (void)presentHostEditorForHost:(NSDictionary *)existingHost {
    BOOL isEditing = (existingHost != nil);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isEditing ? @"Edit SSH Host" : @"Add SSH Host"
                                                                   message:@"Configure remote SSH server details"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Friendly Name (e.g. MacBook Pro)";
        textField.text = existingHost[@"name"] ?: @"";
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Host / IP (e.g. 192.168.1.50)";
        textField.text = existingHost[@"host"] ?: @"";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.keyboardType = UIKeyboardTypeURL;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Port (default: 22)";
        textField.text = existingHost ? [NSString stringWithFormat:@"%@", existingHost[@"port"] ?: @22] : @"22";
        textField.keyboardType = UIKeyboardTypeNumberPad;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Username (e.g. mobile)";
        textField.text = existingHost[@"user"] ?: @"";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        NSString *existingAuth = existingHost[@"password"];
        if (!existingAuth || existingAuth.length == 0) existingAuth = existingHost[@"keyPath"];
        textField.placeholder = @"Password or /path/to/private_key";
        textField.text = existingAuth ?: @"";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:isEditing ? @"Save" : @"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        NSArray<UITextField *> *fields = alert.textFields;
        NSString *name = [fields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *host = [fields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *portStr = [fields[2].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *user = [fields[3].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *authStr = [fields[4].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (host.length == 0) {
            UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Invalid Host"
                                                                              message:@"Hostname or IP address is required."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:errAlert animated:YES completion:nil];
            return;
        }
        
        NSInteger port = [portStr integerValue];
        if (port <= 0 || port > 65535) port = 22;
        if (name.length == 0) name = host;
        if (user.length == 0) user = @"mobile";
        
        NSString *authType = @"password";
        NSString *password = @"";
        NSString *keyPath = @"";
        
        if ([authStr hasPrefix:@"/"] || [authStr hasPrefix:@"~"]) {
            authType = @"key";
            keyPath = authStr;
        } else {
            authType = @"password";
            password = authStr;
        }
        
        NSString *hostId = isEditing ? existingHost[@"id"] : [[NSUUID UUID] UUIDString];
        NSDictionary *hostDict = @{
            @"id": hostId,
            @"name": name,
            @"host": host,
            @"port": @(port),
            @"user": user,
            @"authType": authType,
            @"password": password,
            @"keyPath": keyPath
        };
        
        [[RCConfigManager sharedManager] addOrUpdateSSHHost:hostDict];
        [strongSelf.tableView reloadData];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
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

