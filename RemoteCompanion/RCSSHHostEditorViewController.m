#import "RCSSHHostEditorViewController.h"
#import "RCSSHSettingsViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

@interface RCSSHHostEditorViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSDictionary *existingHost;
@property (nonatomic, assign) BOOL isEditingHost;
@property (nonatomic, assign) BOOL useKeyAuth;

// One field per row, created once so values and first responder state survive reloads
@property (nonatomic, strong) UIButton *revealButton;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *portField;
@property (nonatomic, strong) UITextField *userField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UITextField *keyPathField;
@property (nonatomic, strong) UISegmentedControl *authSegment;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic, strong) UIActivityIndicatorView *testSpinner;
@end

@implementation RCSSHHostEditorViewController

- (instancetype)initWithHost:(NSDictionary *)host {
    self = [super init];
    if (self) {
        _existingHost = [host copy];
        _isEditingHost = (host != nil);
        _useKeyAuth = [[host objectForKey:@"authType"] isEqualToString:@"key"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.isEditingHost ? @"Edit SSH Host" : @"New SSH Host";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelTapped)];
    self.saveButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = self.saveButton;

    [self buildFields];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 50;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
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

- (void)buildFields {
    self.nameField = [self fieldWithPlaceholder:@"MacBook Pro"];
    self.nameField.text = self.existingHost[@"name"] ?: @"";
    self.nameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.nameField.returnKeyType = UIReturnKeyNext;

    self.hostField = [self fieldWithPlaceholder:@"192.168.1.50"];
    self.hostField.text = self.existingHost[@"host"] ?: @"";
    self.hostField.keyboardType = UIKeyboardTypeURL;
    self.hostField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.hostField.returnKeyType = UIReturnKeyNext;

    self.portField = [self fieldWithPlaceholder:@"22"];
    self.portField.text = self.existingHost
        ? [NSString stringWithFormat:@"%@", self.existingHost[@"port"] ?: @22]
        : @"22";
    self.portField.keyboardType = UIKeyboardTypeNumberPad;
    self.portField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.portField.inputAccessoryView = [self doneToolbar];

    self.userField = [self fieldWithPlaceholder:@"mobile"];
    self.userField.text = self.existingHost[@"user"] ?: @"";
    self.userField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.userField.returnKeyType = UIReturnKeyDone;

    // The saved password is never loaded into the field.
    BOOL hasSavedPassword = self.isEditingHost
        && [self.existingHost[@"authType"] isEqualToString:@"password"]
        && [self.existingHost[@"password"] length] > 0;
    self.passwordField = [self fieldWithPlaceholder:(hasSavedPassword ? @"Leave blank to keep" : @"Optional")];
    self.passwordField.text = @"";
    self.passwordField.secureTextEntry = YES;
    self.passwordField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.passwordField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.passwordField.returnKeyType = UIReturnKeyDone;

    self.revealButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.revealButton setImage:[UIImage systemImageNamed:@"eye.slash"] forState:UIControlStateNormal];
    self.revealButton.tintColor = [UIColor secondaryLabelColor];
    // Leave a gap between the text/placeholder and the eye so they never touch.
    self.revealButton.frame = CGRectMake(12, 0, 34, 24);
    [self.revealButton addTarget:self action:@selector(revealTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIView *revealWrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 46, 24)];
    [revealWrapper addSubview:self.revealButton];
    self.passwordField.rightView = revealWrapper;
    self.passwordField.rightViewMode = UITextFieldViewModeAlways;

    self.keyPathField = [self fieldWithPlaceholder:@"~/.ssh/id_rsa"];
    self.keyPathField.text = self.existingHost[@"keyPath"] ?: @"";
    self.keyPathField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.keyPathField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.keyPathField.keyboardType = UIKeyboardTypeURL;
    self.keyPathField.returnKeyType = UIReturnKeyDone;

    self.authSegment = [[UISegmentedControl alloc] initWithItems:@[@"Password", @"Private Key"]];
    self.authSegment.selectedSegmentIndex = self.useKeyAuth ? 1 : 0;
    [self.authSegment addTarget:self action:@selector(authSegmentChanged:) forControlEvents:UIControlEventValueChanged];
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.font = [UIFont systemFontOfSize:16];
    field.textColor = [UIColor labelColor];
    field.tintColor = [UIColor labelColor];
    field.textAlignment = NSTextAlignmentRight;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.delegate = self;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    return field;
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

#pragma mark - Actions

- (void)cancelTapped {
    if (self.navigationController.viewControllers.firstObject == self
        && self.navigationController.presentingViewController != nil) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)authSegmentChanged:(UISegmentedControl *)sender {
    [self.view endEditing:YES];
    self.useKeyAuth = (sender.selectedSegmentIndex == 1);
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)revealTapped:(UIButton *)sender {
    self.passwordField.secureTextEntry = !self.passwordField.secureTextEntry;
    UIImage *image = [UIImage systemImageNamed:self.passwordField.secureTextEntry ? @"eye.slash" : @"eye"];
    [self.revealButton setImage:image forState:UIControlStateNormal];
    // Windows redraw the text only after a text change, so nudge it without touching the value.
    NSString *value = self.passwordField.text;
    self.passwordField.text = @"";
    self.passwordField.text = value;
}

- (void)saveTapped {
    [self.view endEditing:YES];
    NSDictionary *hostDict = [self hostDictionaryFromFields];
    if (!hostDict) return;
    BOOL needsPass = ![hostDict[@"authType"] isEqualToString:@"key"] && [hostDict[@"password"] length] > 0;
    if (![RCSSHSettingsViewController ensureSSHInstalledInViewController:self requireSSHPass:needsPass]) {
        return;
    }
    [[RCConfigManager sharedManager] addOrUpdateSSHHost:hostDict];
    [self.navigationController popViewControllerAnimated:YES];
}

// The host as it would be saved, or nil after telling the user what's missing. The Test button
// saves through the same path, since the tweak's ssh-test reads the saved host by id.
- (NSDictionary *)hostDictionaryFromFields {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *host = [self.hostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *portStr = [self.portField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *user = [self.userField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *passwordInput = self.passwordField.text ?: @"";
    NSString *keyInput = [self.keyPathField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (host.length == 0) {
        [self showErrorWithTitle:@"Host Required" message:@"Enter a hostname or IP address."];
        return nil;
    }
    if ([host hasPrefix:@"-"] || [host rangeOfString:@" "].location != NSNotFound) {
        [self showErrorWithTitle:@"Invalid Host" message:@"Hostname may not start with - or contain spaces."];
        return nil;
    }
    if ([user hasPrefix:@"-"] || [user rangeOfString:@" "].location != NSNotFound) {
        [self showErrorWithTitle:@"Invalid Username" message:@"Username may not start with - or contain spaces."];
        return nil;
    }
    if (self.useKeyAuth && keyInput.length == 0) {
        [self showErrorWithTitle:@"Key Path Required" message:@"Enter the path to the private key, e.g. ~/.ssh/id_rsa."];
        return nil;
    }

    NSInteger port = [portStr integerValue];
    if (port <= 0 || port > 65535) port = 22;
    if (name.length == 0) name = host;
    if (user.length == 0) user = @"mobile";

    NSString *authType;
    NSString *password = @"";
    NSString *keyPath = @"";
    if (self.useKeyAuth) {
        authType = @"key";
        keyPath = keyInput;
    } else if (passwordInput.length > 0) {
        authType = @"password";
        password = passwordInput;
    } else if (self.isEditingHost && [self.existingHost[@"authType"] isEqualToString:@"password"]) {
        authType = @"password";
        password = self.existingHost[@"password"] ?: @"";
    } else {
        authType = @"password";
    }

    NSString *hostId = self.isEditingHost ? self.existingHost[@"id"] : [[NSUUID UUID] UUIDString];
    return @{
        @"id": hostId,
        @"name": name,
        @"host": host,
        @"port": @(port),
        @"user": user,
        @"authType": authType,
        @"password": password,
        @"keyPath": keyPath
    };
}

- (void)testTapped {
    [self.view endEditing:YES];
    NSDictionary *hostDict = [self hostDictionaryFromFields];
    if (!hostDict) return;
    BOOL needsPass = ![hostDict[@"authType"] isEqualToString:@"key"] && [hostDict[@"password"] length] > 0;
    if (![RCSSHSettingsViewController ensureSSHInstalledInViewController:self requireSSHPass:needsPass]) {
        return;
    }
    // The test runs on the phone, which reads the saved host by id
    [[RCConfigManager sharedManager] addOrUpdateSSHHost:hostDict];
    self.existingHost = hostDict;
    self.isEditingHost = YES;
    [self setTesting:YES];

    __weak typeof(self) weakSelf = self;
    NSString *command = [NSString stringWithFormat:@"ssh-test %@", hostDict[@"id"]];
    [[RCServerClient sharedClient] executeCommand:command timeout:15.0 completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self setTesting:NO];
        if (error) {
            [self showErrorWithTitle:@"Connection Failed" message:error.localizedDescription];
            return;
        }
        NSString *text = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([text.lowercaseString hasPrefix:@"error"]) {
            NSString *detail = text;
            if (detail.length > 6) detail = [[detail substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [self showErrorWithTitle:@"Connection Failed" message:(detail.length ? detail : @"The connection test failed.")];
        } else if ([text.lowercaseString containsString:@"connected"]) {
            [self showErrorWithTitle:@"Connection OK" message:text];
        } else {
            [self showErrorWithTitle:@"Connection Failed" message:(text.length ? text : @"No response from ssh.")];
        }
    }];
}

- (void)setTesting:(BOOL)testing {
    if (testing) {
        self.saveButton.enabled = NO;
        if (!self.testSpinner) {
            self.testSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        }
        [self.testSpinner startAnimating];
    } else {
        [self.testSpinner stopAnimating];
        self.testSpinner = nil;
        self.saveButton.enabled = YES;
    }
    if (self.isViewLoaded) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                      withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)showErrorWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIToolbar *)doneToolbar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
    toolbar.items = @[flex, done];
    return toolbar;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 4; // Name, Host, Port, Username
    if (section == 1) return 2; // Auth picker + one credential field
    return 1; // Test Connection
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Server";
    if (section == 1) return @"Authentication";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 1) return nil;
    if (self.useKeyAuth) {
        return @"The key file must already exist on this iPhone. A path starting with ~ expands to the home directory.";
    }
    BOOL hasSavedPassword = self.isEditingHost
        && [self.existingHost[@"authType"] isEqualToString:@"password"]
        && [self.existingHost[@"password"] length] > 0;
    if (hasSavedPassword) {
        return @"The saved password is never shown. Leave the field blank to keep it, or type a new one to replace it.";
    }
    return @"Saved passwords are never shown once stored. Leave empty for key-agent logins.";
}

// The Test button sits in its own card below Authentication, like a Settings action row
- (UITableViewCell *)testConnectionCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    if (self.testSpinner) {
        cell.textLabel.text = @"Testing…";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = self.testSpinner;
    } else {
        cell.textLabel.text = @"Test Connection";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2 && !self.testSpinner) [self testTapped];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) return [self testConnectionCell];

    if (indexPath.section == 0) {
        NSArray *labels = @[@"Name", @"Host", @"Port", @"Username"];
        NSArray *fields = @[self.nameField, self.hostField, self.portField, self.userField];
        return [self cellWithLabel:labels[indexPath.row] control:fields[indexPath.row]];
    }

    if (indexPath.row == 0) {
        return [self cellWithLabel:nil control:self.authSegment];
    }
    if (self.useKeyAuth) {
        return [self cellWithLabel:@"Key Path" control:self.keyPathField];
    }
    return [self cellWithLabel:@"Password" control:self.passwordField];
}

// A Settings row: label on the left, control filling the rest of the width. A fixed label
// column keeps the control from collapsing against UITableViewCell's own text label.
- (UITableViewCell *)cellWithLabel:(NSString *)labelText control:(UIView *)control {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    [control removeFromSuperview];
    [cell.contentView addSubview:control];

    NSLayoutConstraint *leadingConstraint;
    if (labelText.length > 0) {
        UILabel *label = [[UILabel alloc] init];
        label.text = labelText;
        label.font = [UIFont systemFontOfSize:16];
        label.textColor = [UIColor labelColor];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [cell.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
        ]];
        leadingConstraint = [control.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:12];
    } else {
        leadingConstraint = [control.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16];
    }

    [NSLayoutConstraint activateConstraints:@[
        leadingConstraint,
        [control.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [control.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [control.heightAnchor constraintEqualToConstant:34]
    ]];

    return cell;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.nameField) {
        [self.hostField becomeFirstResponder];
    } else if (textField == self.hostField) {
        [self.portField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return YES;
}

@end
