#import "RCRCClientEditorViewController.h"
#import "RCConfigManager.h"

@interface RCRCClientEditorViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSDictionary *existingClient;
@property (nonatomic, assign) BOOL isEditingClient;

// One field per row, created once so values and first responder state survive reloads
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *addressField;
@property (nonatomic, strong) UITextField *portField;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UIButton *revealButton;
@property (nonatomic, strong) UIActivityIndicatorView *testSpinner;
@end

@implementation RCRCClientEditorViewController

- (instancetype)initWithClient:(NSDictionary *)client {
    self = [super init];
    if (self) {
        _existingClient = [client copy];
        _isEditingClient = (client != nil);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.isEditingClient ? @"Edit RC Client" : @"New RC Client";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(saveTapped)];

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
    self.nameField = [self fieldWithPlaceholder:@"iPad"];
    self.nameField.text = self.existingClient[@"name"] ?: @"";
    self.nameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.nameField.returnKeyType = UIReturnKeyNext;

    self.addressField = [self fieldWithPlaceholder:@"192.168.1.42"];
    self.addressField.text = self.existingClient[@"host"] ?: @"";
    self.addressField.keyboardType = UIKeyboardTypeURL;
    self.addressField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.addressField.returnKeyType = UIReturnKeyNext;

    self.portField = [self fieldWithPlaceholder:@"8080"];
    self.portField.text = self.existingClient
        ? [NSString stringWithFormat:@"%@", self.existingClient[@"port"] ?: @8080]
        : @"8080";
    self.portField.keyboardType = UIKeyboardTypeNumberPad;
    self.portField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.portField.inputAccessoryView = [self doneToolbar];

    // The saved token is never loaded into the field.
    BOOL hasSavedToken = self.isEditingClient && [self.existingClient[@"token"] length] > 0;
    self.tokenField = [self fieldWithPlaceholder:(hasSavedToken ? @"Leave blank to keep" : @"Optional")];
    self.tokenField.text = @"";
    self.tokenField.secureTextEntry = YES;
    self.tokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tokenField.returnKeyType = UIReturnKeyDone;

    self.revealButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.revealButton setImage:[UIImage systemImageNamed:@"eye.slash"] forState:UIControlStateNormal];
    self.revealButton.tintColor = [UIColor secondaryLabelColor];
    self.revealButton.frame = CGRectMake(12, 0, 34, 24);
    [self.revealButton addTarget:self action:@selector(revealTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIView *revealWrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 46, 24)];
    [revealWrapper addSubview:self.revealButton];
    self.tokenField.rightView = revealWrapper;
    self.tokenField.rightViewMode = UITextFieldViewModeAlways;
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

- (void)revealTapped:(UIButton *)sender {
    self.tokenField.secureTextEntry = !self.tokenField.secureTextEntry;
    UIImage *image = [UIImage systemImageNamed:self.tokenField.secureTextEntry ? @"eye.slash" : @"eye"];
    [self.revealButton setImage:image forState:UIControlStateNormal];
    NSString *value = self.tokenField.text;
    self.tokenField.text = @"";
    self.tokenField.text = value;
}

- (void)saveTapped {
    [self.view endEditing:YES];

    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *address = [self.addressField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *portStr = [self.portField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *tokenInput = self.tokenField.text ?: @"";

    if ([address.lowercaseString hasPrefix:@"http://"]) {
        address = [address substringFromIndex:7];
    }
    while ([address hasSuffix:@"/"]) {
        address = [address substringToIndex:address.length - 1];
    }

    if (address.length == 0) {
        [self showErrorWithTitle:@"Address Required" message:@"Enter the IP address or hostname of the other device."];
        return;
    }
    if ([address hasPrefix:@"-"] || [address rangeOfString:@" "].location != NSNotFound) {
        [self showErrorWithTitle:@"Invalid Address" message:@"The address may not start with - or contain spaces."];
        return;
    }

    NSInteger port = [portStr integerValue];
    if (port <= 0 || port > 65535) port = 8080;
    if (name.length == 0) name = address;

    NSString *token = @"";
    if (tokenInput.length > 0) {
        token = tokenInput;
    } else if (self.isEditingClient) {
        token = self.existingClient[@"token"] ?: @"";
    }

    NSString *clientId = self.isEditingClient ? self.existingClient[@"id"] : [[NSUUID UUID] UUIDString];
    NSDictionary *client = @{
        @"id": clientId,
        @"name": name,
        @"host": address,
        @"port": @(port),
        @"token": token
    };

    [[RCConfigManager sharedManager] addOrUpdateRCClient:client];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showErrorWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Test Connection

- (void)testConnectionTapped {
    [self.view endEditing:YES];

    NSString *address = [self.addressField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (address.length == 0) {
        [self showErrorWithTitle:@"Address Required" message:@"Enter the IP address or hostname first."];
        return;
    }
    if (![address.lowercaseString hasPrefix:@"http://"] && ![address.lowercaseString hasPrefix:@"https://"]) {
        address = [@"http://" stringByAppendingString:address];
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:address];
    if (!components || components.host.length == 0) {
        [self showErrorWithTitle:@"Invalid Address" message:@"That address could not be parsed."];
        return;
    }
    NSInteger port = [self.portField.text integerValue];
    if (components.port == nil && port > 0 && port <= 65535) {
        components.port = @(port);
    }
    components.path = @"/api/sysinfo";
    components.query = nil;

    NSURL *url = components.URL;
    if (!url) {
        [self showErrorWithTitle:@"Invalid Address" message:@"That address could not be parsed."];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                      timeoutInterval:5.0];
    request.HTTPMethod = @"GET";
    NSString *typedToken = [self.tokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *token = typedToken.length > 0 ? typedToken : (self.existingClient[@"token"] ?: @"");
    if (token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    self.testSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.testSpinner startAnimating];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
    cell.accessoryView = self.testSpinner;
    cell.textLabel.textColor = [UIColor secondaryLabelColor];
    self.tableView.userInteractionEnabled = NO;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 5.0;
    config.timeoutIntervalForResource = 5.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    __weak typeof(self) weakSelf = self;
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.testSpinner stopAnimating];
            strongSelf.testSpinner = nil;
            [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                               withRowAnimation:UITableViewRowAnimationNone];
            strongSelf.tableView.userInteractionEnabled = YES;

            if (error) {
                [strongSelf showErrorWithTitle:@"Connection Failed"
                                        message:error.localizedDescription ?: @"Could not reach that device."];
                return;
            }

            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            NSInteger status = http.statusCode;
            id json = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *device = nil;
            if ([json isKindOfClass:[NSDictionary class]]) {
                device = json[@"device_name"] ?: json[@"hostname"];
            }

            if (status >= 200 && status < 300) {
                NSString *message = device.length > 0
                    ? [NSString stringWithFormat:@"Connected to %@.", device]
                    : @"Connected to the RemoteCompanion Web UI.";
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Connection OK"
                                                                               message:message
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            } else {
                [strongSelf showErrorWithTitle:@"Web UI Replied"
                                        message:[NSString stringWithFormat:@"The device answered with HTTP %ld. Check that the Web UI is on and the port is right.", (long)status]];
            }
        });
    }] resume];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3; // Name, Address, Port
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Device";
    if (section == 1) return @"Authentication";
    return @"Check";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Turn on the Web UI on the other device (Settings > Web UI), then enter its IP address or hostname. The default port is 8080.";
    }
    if (section == 1) {
        BOOL hasSavedToken = self.isEditingClient && [self.existingClient[@"token"] length] > 0;
        if (hasSavedToken) {
            return @"The saved token is never shown. Leave the field blank to keep it, or type a new one to replace it.";
        }
        return @"Only needed when the other device's Web UI has an API token. Privileged commands (root, exec, ssh-run) are refused without it.";
    }
    return @"Asks the other device for its Web UI system info, without running any action.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        NSArray *labels = @[@"Name", @"Address", @"Port"];
        NSArray *fields = @[self.nameField, self.addressField, self.portField];
        return [self cellWithLabel:labels[indexPath.row] control:fields[indexPath.row]];
    }

    if (indexPath.section == 1) {
        return [self cellWithLabel:@"API Token" control:self.tokenField];
    }

    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.text = @"Test Connection";
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) {
        [self testConnectionTapped];
    }
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
        [self.addressField becomeFirstResponder];
    } else if (textField == self.addressField) {
        [self.portField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return YES;
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

@end
