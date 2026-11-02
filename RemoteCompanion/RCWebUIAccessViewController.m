#import "RCWebUIAccessViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

typedef NS_ENUM(NSInteger, RCWebUIAccessSection) {
    RCWebUIAccessSectionChoice,
    RCWebUIAccessSectionNetworks,
    RCWebUIAccessSectionApiToken,
};

@interface RCWebUIAccessViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *currentWiFi; // the Wi-Fi network this iPhone is on, if any
@property (nonatomic, strong) UITextField *tokenTextField;
@property (nonatomic, assign) BOOL isTokenVisible;
@property (nonatomic, strong) UIButton *visibilityButton;
@end

@implementation RCWebUIAccessViewController

+ (NSArray<NSArray<NSString *> *> *)choices {
    return @[@[@"any", @"Any Network", @"globe"],
             @[@"networks", @"Trusted Networks", @"wifi"],
             @[@"local", @"This iPhone Only", @"iphone"]];
}

+ (NSString *)titleForAccess:(NSString *)access {
    for (NSArray *choice in [self choices]) if ([choice[0] isEqualToString:access]) return choice[1];
    return @"Any Network";
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) self.title = @"Access";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Asked of the tweak: SpringBoard knows the network name without a location permission
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"webui wifi" completion:^(NSString *output, NSError *error) {
        NSString *name = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.currentWiFi = name.length && ![name hasPrefix:@"Error"] ? name : nil;
            [weakSelf.tableView reloadData];
        });
    }];
}

- (BOOL)showsNetworks {
    return [[RCConfigManager sharedManager].webUIAccess isEqualToString:@"networks"];
}

- (BOOL)canAddCurrentWiFi {
    return self.currentWiFi.length && ![[RCConfigManager sharedManager].webUINetworks containsObject:self.currentWiFi];
}

#pragma mark - Editing the list

- (void)addNetwork:(NSString *)name {
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if (!name.length || [cm.webUINetworks containsObject:name]) return;
    cm.webUINetworks = [cm.webUINetworks arrayByAddingObject:name];
    [self.tableView reloadData];
}

- (void)promptForNetwork {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Network" message:@"Enter the Wi-Fi network name exactly as it appears in Settings." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Network Name";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [weakSelf addNetwork:alert.textFields.firstObject.text];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveTokenField];
    if (self.tokenTextField.isFirstResponder) {
        [self.tokenTextField resignFirstResponder];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self saveTokenField];
    if (self.tokenTextField.isFirstResponder) {
        [self.tokenTextField resignFirstResponder];
    }
}

- (void)saveTokenField {
    NSString *current = self.tokenTextField.text ?: @"";
    if (![[RCConfigManager sharedManager].webUIApiToken isEqualToString:current]) {
        [RCConfigManager sharedManager].webUIApiToken = current;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.tokenTextField) [self saveTokenField];
    [textField resignFirstResponder];
    return YES;
}

- (void)toggleTokenVisibility {
    self.isTokenVisible = !self.isTokenVisible;
    self.tokenTextField.secureTextEntry = !self.isTokenVisible;
    [self.visibilityButton setImage:[UIImage systemImageNamed:self.isTokenVisible ? @"eye.slash" : @"eye"] forState:UIControlStateNormal];
}

- (void)copyTokenToClipboard {
    NSString *token = self.tokenTextField.text;
    if (token.length > 0) {
        [UIPasteboard generalPasteboard].string = token;
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Copied" message:@"API token copied to clipboard." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - Table

- (RCWebUIAccessSection)sectionTypeForSection:(NSInteger)section {
    if (section == 0) return RCWebUIAccessSectionChoice;
    if ([self showsNetworks]) {
        if (section == 1) return RCWebUIAccessSectionNetworks;
        return RCWebUIAccessSectionApiToken;
    }
    return RCWebUIAccessSectionApiToken;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self showsNetworks] ? 3 : 2;
}

// Section 1 (if networks enabled): trusted networks, then Add Current Network and Add Network
// API Token section: Row 0 = Token text field, Row 1 = Generate New Token
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    RCWebUIAccessSection sectionType = [self sectionTypeForSection:section];
    if (sectionType == RCWebUIAccessSectionChoice) return [[self class] choices].count;
    if (sectionType == RCWebUIAccessSectionNetworks) {
        return [RCConfigManager sharedManager].webUINetworks.count + ([self canAddCurrentWiFi] ? 1 : 0) + 1;
    }
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    RCWebUIAccessSection sectionType = [self sectionTypeForSection:section];
    if (sectionType == RCWebUIAccessSectionNetworks) return @"Trusted Networks";
    if (sectionType == RCWebUIAccessSectionApiToken) return @"API Token";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    RCWebUIAccessSection sectionType = [self sectionTypeForSection:section];
    if (sectionType == RCWebUIAccessSectionApiToken) {
        return @"Protects raw shell and root commands from unauthenticated local network callers.";
    }
    NSString *access = [RCConfigManager sharedManager].webUIAccess;
    if (sectionType == RCWebUIAccessSectionNetworks) {
        return @"Anyone can name a network the same as a trusted one, so add only private networks.";
    }
    if ([access isEqualToString:@"networks"]) return @"The Web UI can be reached only while this iPhone is on a trusted Wi-Fi network. This iPhone can always reach it.";
    if ([access isEqualToString:@"local"]) return @"The Web UI can be reached only from this iPhone, at localhost.";
    return @"The Web UI can be reached from any device on the same network as this iPhone.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    RCWebUIAccessSection sectionType = [self sectionTypeForSection:indexPath.section];

    if (sectionType == RCWebUIAccessSectionChoice) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
        UIView *selBg = [[UIView alloc] init];
        selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
        cell.selectedBackgroundView = selBg;
        cell.imageView.tintColor = [UIColor systemGrayColor];

        NSArray *choice = [[self class] choices][indexPath.row];
        cell.textLabel.text = choice[1];
        cell.imageView.image = [UIImage systemImageNamed:choice[2]];
        cell.accessoryType = [cm.webUIAccess isEqualToString:choice[0]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }

    if (sectionType == RCWebUIAccessSectionNetworks) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
        UIView *selBg = [[UIView alloc] init];
        selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
        cell.selectedBackgroundView = selBg;
        cell.imageView.tintColor = [UIColor systemGrayColor];

        NSArray *networks = cm.webUINetworks;
        if (indexPath.row < (NSInteger)networks.count) {
            NSString *name = networks[indexPath.row];
            cell.textLabel.text = name;
            cell.imageView.image = [UIImage systemImageNamed:@"wifi"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if ([name isEqualToString:self.currentWiFi]) {
                UILabel *connected = [[UILabel alloc] init];
                connected.text = @"Connected";
                connected.font = [UIFont systemFontOfSize:15];
                connected.textColor = [UIColor secondaryLabelColor];
                [connected sizeToFit];
                cell.accessoryView = connected;
            }
            return cell;
        }
        BOOL addCurrent = indexPath.row == (NSInteger)networks.count && [self canAddCurrentWiFi];
        cell.textLabel.text = addCurrent ? [NSString stringWithFormat:@"Add “%@”", self.currentWiFi] : @"Add Network…";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        return cell;
    }

    // RCWebUIAccessSectionApiToken
    if (indexPath.row == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ApiTokenFieldCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ApiTokenFieldCell"];
            cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UITextField *tf = [[UITextField alloc] init];
            tf.placeholder = @"API Token (optional)";
            tf.autocorrectionType = UITextAutocorrectionTypeNo;
            tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
            tf.delegate = self;
            tf.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
            tf.textColor = [UIColor labelColor];
            [tf addTarget:self action:@selector(saveTokenField) forControlEvents:UIControlEventEditingDidEnd];
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            self.tokenTextField = tf;
            [cell.contentView addSubview:tf];

            UIButton *eyeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            [eyeBtn addTarget:self action:@selector(toggleTokenVisibility) forControlEvents:UIControlEventTouchUpInside];
            eyeBtn.tintColor = [UIColor systemGrayColor];
            eyeBtn.translatesAutoresizingMaskIntoConstraints = NO;
            self.visibilityButton = eyeBtn;
            [cell.contentView addSubview:eyeBtn];

            UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            [copyBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
            copyBtn.tintColor = [UIColor systemGrayColor];
            [copyBtn addTarget:self action:@selector(copyTokenToClipboard) forControlEvents:UIControlEventTouchUpInside];
            copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:copyBtn];

            [NSLayoutConstraint activateConstraints:@[
                [copyBtn.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
                [copyBtn.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [copyBtn.widthAnchor constraintEqualToConstant:32],
                [copyBtn.heightAnchor constraintEqualToConstant:32],

                [eyeBtn.trailingAnchor constraintEqualToAnchor:copyBtn.leadingAnchor constant:-8],
                [eyeBtn.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [eyeBtn.widthAnchor constraintEqualToConstant:32],
                [eyeBtn.heightAnchor constraintEqualToConstant:32],

                [tf.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                [tf.trailingAnchor constraintEqualToAnchor:eyeBtn.leadingAnchor constant:-8],
                [tf.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [tf.heightAnchor constraintEqualToConstant:44],
            ]];
        }
        self.tokenTextField.text = cm.webUIApiToken;
        self.tokenTextField.secureTextEntry = !self.isTokenVisible;
        [self.visibilityButton setImage:[UIImage systemImageNamed:self.isTokenVisible ? @"eye.slash" : @"eye"] forState:UIControlStateNormal];
        return cell;
    } else {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
        UIView *selBg = [[UIView alloc] init];
        selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
        cell.selectedBackgroundView = selBg;

        cell.textLabel.text = @"Generate New Token";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.imageView.image = [UIImage systemImageNamed:@"key.fill"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    RCWebUIAccessSection sectionType = [self sectionTypeForSection:indexPath.section];
    if (sectionType == RCWebUIAccessSectionChoice) {
        NSString *access = [[self class] choices][indexPath.row][0];
        cm.webUIAccess = access;
        [tableView reloadData];
        return;
    }
    if (sectionType == RCWebUIAccessSectionNetworks) {
        NSArray *networks = cm.webUINetworks;
        if (indexPath.row < (NSInteger)networks.count) return;
        if (indexPath.row == (NSInteger)networks.count && [self canAddCurrentWiFi]) [self addNetwork:self.currentWiFi];
        else [self promptForNetwork];
        return;
    }
    if (sectionType == RCWebUIAccessSectionApiToken) {
        if (indexPath.row == 1) {
            NSString *newToken = [cm generateRandomApiToken];
            cm.webUIApiToken = newToken;
            self.tokenTextField.text = newToken;
            [UIPasteboard generalPasteboard].string = newToken;
            UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [gen impactOccurred];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Token Generated" message:@"A new API token has been generated and copied to your clipboard." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCWebUIAccessSection sectionType = [self sectionTypeForSection:indexPath.section];
    if (sectionType != RCWebUIAccessSectionNetworks) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    NSArray *networks = [RCConfigManager sharedManager].webUINetworks;
    if (indexPath.row >= (NSInteger)networks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    NSString *name = networks[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Remove" handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        RCConfigManager *config = [RCConfigManager sharedManager];
        NSMutableArray *list = [config.webUINetworks mutableCopy];
        [list removeObject:name];
        config.webUINetworks = list;
        [weakSelf.tableView reloadData];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

@end
