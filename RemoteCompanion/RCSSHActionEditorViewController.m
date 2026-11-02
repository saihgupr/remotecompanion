#import "RCSSHActionEditorViewController.h"
#import "RCConfigManager.h"

@interface RCSSHActionEditorViewController () <UITextViewDelegate>
@property (nonatomic, copy) NSString *hostId;
@property (nonatomic, copy) NSString *command;
@property (nonatomic, strong) UITextView *commandView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@end

@implementation RCSSHActionEditorViewController

- (instancetype)initWithHostId:(NSString *)hostId command:(NSString *)command {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _hostId = [hostId copy];
        _command = [command copy] ?: @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.command.length > 0 ? @"Edit SSH Command" : @"New SSH Command";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelTapped)];
    self.saveButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = self.saveButton;

    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
    }

    // If there is only one host, use it; otherwise make the user pick on Save.
    NSArray<NSDictionary *> *hosts = [RCConfigManager sharedManager].sshHosts;
    if (self.hostId.length == 0 && hosts.count == 1) {
        self.hostId = hosts.firstObject[@"id"];
    }
    [self updateSaveButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
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
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Host" : @"Command";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Pick the server this command runs on. Manage servers in Settings > Integrations > SSH Hosts.";
    }
    return @"Runs on the remote machine, exactly as typed. Multiple lines are allowed.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 ? 170 : 50;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    if (indexPath.section == 0) {
        NSDictionary *host = [[RCConfigManager sharedManager] sshHostForId:self.hostId];
        if (host) {
            cell.textLabel.text = host[@"name"] ?: host[@"host"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@@%@:%@",
                host[@"user"] ?: @"", host[@"host"] ?: @"", host[@"port"] ?: @22];
        } else {
            cell.textLabel.text = @"Choose a Host";
            cell.detailTextLabel.text = @"Required";
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (!self.commandView) {
            self.commandView = [[UITextView alloc] init];
            self.commandView.delegate = self;
            self.commandView.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
            self.commandView.backgroundColor = [UIColor clearColor];
            self.commandView.textColor = [UIColor labelColor];
            self.commandView.keyboardType = UIKeyboardTypeASCIICapable;
            self.commandView.autocapitalizationType = UITextAutocapitalizationTypeNone;
            self.commandView.autocorrectionType = UITextAutocorrectionTypeNo;
            self.commandView.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4);
            self.commandView.translatesAutoresizingMaskIntoConstraints = NO;
            self.commandView.text = self.command;

            self.placeholderLabel = [[UILabel alloc] init];
            self.placeholderLabel.text = @"e.g. uptime";
            self.placeholderLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
            self.placeholderLabel.textColor = [UIColor tertiaryLabelColor];
            self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
            self.placeholderLabel.hidden = self.command.length > 0;
        }
        [cell.contentView addSubview:self.commandView];
        [cell.contentView addSubview:self.placeholderLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.commandView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
            [self.commandView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [self.commandView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
            [self.commandView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
            [self.placeholderLabel.topAnchor constraintEqualToAnchor:self.commandView.topAnchor constant:12],
            [self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.commandView.leadingAnchor constant:9],
        ]];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        [self chooseHostFromView:[tableView cellForRowAtIndexPath:indexPath]];
    }
}

#pragma mark - Host Picker

- (void)chooseHostFromView:(UIView *)sourceView {
    NSArray<NSDictionary *> *hosts = [RCConfigManager sharedManager].sshHosts;
    if (hosts.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No SSH Hosts"
            message:@"Add a server in Settings > Integrations > SSH Hosts first."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"SSH Host"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *host in hosts) {
        NSString *name = host[@"name"] ?: host[@"host"];
        NSString *detail = [NSString stringWithFormat:@"%@@%@", host[@"user"] ?: @"", host[@"host"] ?: @""];
        NSString *title = [NSString stringWithFormat:@"%@ (%@)", name, detail];
        if ([host[@"id"] isEqualToString:self.hostId]) {
            title = [title stringByAppendingString:@" \u2713"];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.hostId = host[@"id"];
            [self updateSaveButton];
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Editing

- (void)textViewDidChange:(UITextView *)textView {
    self.placeholderLabel.hidden = textView.text.length > 0;
    [self updateSaveButton];
}

- (void)updateSaveButton {
    NSString *trimmed = [self.commandView.text ?: self.command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.saveButton.enabled = (self.hostId.length > 0 && trimmed.length > 0);
}

#pragma mark - Actions

- (void)cancelTapped {
    BOOL isRootOfPresentedNav = (self.navigationController.viewControllers.firstObject == self)
        && self.navigationController.presentingViewController != nil;
    if (isRootOfPresentedNav) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)saveTapped {
    [self.view endEditing:YES];
    NSString *command = [self.commandView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (self.hostId.length == 0 || command.length == 0) return;
    if (self.onSave) self.onSave(self.hostId, command);
}

@end
