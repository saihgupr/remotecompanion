#import "RCSSHHostEditorViewController.h"
#import "RCConfigManager.h"

@interface RCSSHHostEditorViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSDictionary *existingHost;
@property (nonatomic, assign) BOOL isEditingHost;
@property (nonatomic, assign) BOOL useKeyAuth;

// Form fields, kept alive so values survive scrolling
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *portField;
@property (nonatomic, strong) UITextField *userField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UITextField *keyPathField;
@property (nonatomic, strong) UISegmentedControl *authSegment;
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
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(saveTapped)];

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
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)authSegmentChanged:(UISegmentedControl *)sender {
    self.useKeyAuth = (sender.selectedSegmentIndex == 1);
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)eyeTapped:(UIButton *)sender {
    self.passwordField.secureTextEntry = !self.passwordField.secureTextEntry;
    NSString *current = self.passwordField.text;
    self.passwordField.text = @"";
    self.passwordField.text = current;
    UIImage *image = [UIImage systemImageNamed:self.passwordField.secureTextEntry ? @"eye.slash" : @"eye"];
    [sender setImage:image forState:UIControlStateNormal];
}

- (void)saveTapped {
    [self.view endEditing:YES];

    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *host = [self.hostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *portStr = [self.portField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *user = [self.userField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *passwordInput = self.passwordField.text ?: @"";
    NSString *keyInput = [self.keyPathField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (host.length == 0) {
        [self showErrorWithTitle:@"Host Required" message:@"Enter a hostname or IP address."];
        return;
    }
    if (self.useKeyAuth && keyInput.length == 0) {
        [self showErrorWithTitle:@"Key Path Required" message:@"Enter the path to the private key, e.g. ~/.ssh/id_rsa."];
        return;
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
        // Password left blank and this host already used password auth: keep the saved password.
        authType = @"password";
        password = self.existingHost[@"password"] ?: @"";
    } else {
        // New host with no password, or switched over from key auth: password auth with no
        // password yet (key agent / passwordless login). Nothing secret is stored.
        authType = @"password";
    }

    NSString *hostId = self.isEditingHost ? self.existingHost[@"id"] : [[NSUUID UUID] UUIDString];
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
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showErrorWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 4; // Name, Host, Port, Username
    return 2; // Auth method picker + credential field
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Server" : @"Authentication";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return nil;
    if (self.useKeyAuth) {
        return @"The key file must already exist on this iPhone. A path starting with ~ expands to the home directory.";
    }
    BOOL hasSavedPassword = self.isEditingHost
        && [self.existingHost[@"authType"] isEqualToString:@"password"]
        && [self.existingHost[@"password"] length] > 0;
    if (hasSavedPassword) {
        return @"The saved password is never shown. Leave the field blank to keep it, or type a new one to replace it. Empty means no password (key agent).";
    }
    return @"Saved passwords are never shown once stored. Leave empty for key-agent logins.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = [UIColor labelColor];

    if (indexPath.section == 0) {
        NSArray *labels = @[@"Name", @"Host", @"Port", @"Username"];
        NSArray *placeholders = @[@"MacBook Pro", @"192.168.1.50", @"22", @"mobile"];
        cell.textLabel.text = labels[indexPath.row];
        cell.textLabel.font = [UIFont systemFontOfSize:16];

        UITextField *field = [[UITextField alloc] init];
        field.delegate = self;
        field.textAlignment = NSTextAlignmentRight;
        field.placeholder = placeholders[indexPath.row];
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:field];
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:12],
            [field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [field.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [field.heightAnchor constraintEqualToConstant:34]
        ]];

        if (indexPath.row == 0) {
            field.autocapitalizationType = UITextAutocapitalizationTypeWords;
            field.returnKeyType = UIReturnKeyNext;
            field.text = self.nameField.text ?: self.existingHost[@"name"] ?: @"";
            self.nameField = field;
        } else if (indexPath.row == 1) {
            field.keyboardType = UIKeyboardTypeURL;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.returnKeyType = UIReturnKeyNext;
            field.text = self.hostField.text ?: self.existingHost[@"host"] ?: @"";
            self.hostField = field;
        } else if (indexPath.row == 2) {
            field.keyboardType = UIKeyboardTypeNumberPad;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            NSString *fallback = self.existingHost
                ? [NSString stringWithFormat:@"%@", self.existingHost[@"port"] ?: @22]
                : @"22";
            field.text = self.portField.text ?: fallback;
            field.inputAccessoryView = [self doneToolbar];
            self.portField = field;
        } else {
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.returnKeyType = UIReturnKeyDone;
            field.text = self.userField.text ?: self.existingHost[@"user"] ?: @"";
            self.userField = field;
        }
    } else {
        if (indexPath.row == 0) {
            if (!self.authSegment) {
                self.authSegment = [[UISegmentedControl alloc] initWithItems:@[@"Password", @"Private Key"]];
                [self.authSegment addTarget:self action:@selector(authSegmentChanged:) forControlEvents:UIControlEventValueChanged];
            }
            self.authSegment.selectedSegmentIndex = self.useKeyAuth ? 1 : 0;
            self.authSegment.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:self.authSegment];
            [NSLayoutConstraint activateConstraints:@[
                [self.authSegment.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                [self.authSegment.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [self.authSegment.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
            ]];
        } else if (!self.useKeyAuth) {
            cell.textLabel.text = @"Password";
            cell.textLabel.font = [UIFont systemFontOfSize:16];

            if (!self.passwordField) {
                self.passwordField = [[UITextField alloc] init];
                self.passwordField.delegate = self;
                self.passwordField.secureTextEntry = YES;
                self.passwordField.autocapitalizationType = UITextAutocapitalizationTypeNone;
                self.passwordField.autocorrectionType = UITextAutocorrectionTypeNo;
                self.passwordField.returnKeyType = UIReturnKeyDone;
            }
            BOOL hasSaved = self.isEditingHost
                && [self.existingHost[@"authType"] isEqualToString:@"password"]
                && [self.existingHost[@"password"] length] > 0;
            self.passwordField.placeholder = hasSaved ? @"Leave blank to keep" : @"Optional";
            self.passwordField.textAlignment = NSTextAlignmentRight;
            self.passwordField.clearButtonMode = UITextFieldViewModeWhileEditing;
            self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;

            UIButton *eye = [UIButton buttonWithType:UIButtonTypeCustom];
            UIImage *eyeImage = [UIImage systemImageNamed:self.passwordField.secureTextEntry ? @"eye.slash" : @"eye"];
            [eye setImage:eyeImage forState:UIControlStateNormal];
            eye.tintColor = [UIColor secondaryLabelColor];
            eye.frame = CGRectMake(0, 0, 32, 24);
            [eye addTarget:self action:@selector(eyeTapped:) forControlEvents:UIControlEventTouchUpInside];
            self.passwordField.rightView = eye;
            self.passwordField.rightViewMode = UITextFieldViewModeAlways;

            [cell.contentView addSubview:self.passwordField];
            [NSLayoutConstraint activateConstraints:@[
                [self.passwordField.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:12],
                [self.passwordField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [self.passwordField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [self.passwordField.heightAnchor constraintEqualToConstant:34]
            ]];
        } else {
            cell.textLabel.text = @"Key Path";
            cell.textLabel.font = [UIFont systemFontOfSize:16];

            if (!self.keyPathField) {
                self.keyPathField = [[UITextField alloc] init];
                self.keyPathField.delegate = self;
                self.keyPathField.autocapitalizationType = UITextAutocapitalizationTypeNone;
                self.keyPathField.autocorrectionType = UITextAutocorrectionTypeNo;
                self.keyPathField.keyboardType = UIKeyboardTypeURL;
                self.keyPathField.returnKeyType = UIReturnKeyDone;
                self.keyPathField.text = self.existingHost[@"keyPath"] ?: @"";
            }
            self.keyPathField.placeholder = @"~/.ssh/id_rsa";
            self.keyPathField.textAlignment = NSTextAlignmentRight;
            self.keyPathField.clearButtonMode = UITextFieldViewModeWhileEditing;
            self.keyPathField.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:self.keyPathField];
            [NSLayoutConstraint activateConstraints:@[
                [self.keyPathField.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:12],
                [self.keyPathField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [self.keyPathField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [self.keyPathField.heightAnchor constraintEqualToConstant:34]
            ]];
        }
    }

    return cell;
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

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.nameField) {
        [self.hostField becomeFirstResponder];
    } else if (textField == self.hostField) {
        [self.portField becomeFirstResponder];
    } else if (textField == self.userField || textField == self.passwordField || textField == self.keyPathField) {
        [textField resignFirstResponder];
    }
    return YES;
}

@end
