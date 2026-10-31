#import "RCWebUIAccessViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

typedef NS_ENUM(NSInteger, RCWebUIAccessSection) {
    RCWebUIAccessSectionChoice,
    RCWebUIAccessSectionNetworks,
};

@interface RCWebUIAccessViewController ()
@property (nonatomic, copy) NSString *currentWiFi; // the Wi-Fi network this iPhone is on, if any
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

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self showsNetworks] ? 2 : 1;
}

// Section 1: the trusted networks, then Add Current Network (when not listed yet) and Add Network
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RCWebUIAccessSectionChoice) return [[self class] choices].count;
    return [RCConfigManager sharedManager].webUINetworks.count + ([self canAddCurrentWiFi] ? 1 : 0) + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == RCWebUIAccessSectionNetworks ? @"Trusted Networks" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *access = [RCConfigManager sharedManager].webUIAccess;
    if (section == RCWebUIAccessSectionNetworks) {
        return @"Anyone can name a network the same as a trusted one, so add only private networks.";
    }
    if ([access isEqualToString:@"networks"]) return @"The Web UI can be reached only while this iPhone is on a trusted Wi-Fi network. This iPhone can always reach it.";
    if ([access isEqualToString:@"local"]) return @"The Web UI can be reached only from this iPhone, at localhost.";
    return @"The Web UI can be reached from any device on the same network as this iPhone.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.imageView.tintColor = [UIColor systemGrayColor];

    if (indexPath.section == RCWebUIAccessSectionChoice) {
        NSArray *choice = [[self class] choices][indexPath.row];
        cell.textLabel.text = choice[1];
        cell.imageView.image = [UIImage systemImageNamed:choice[2]];
        cell.accessoryType = [cm.webUIAccess isEqualToString:choice[0]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }

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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if (indexPath.section == RCWebUIAccessSectionChoice) {
        NSString *access = [[self class] choices][indexPath.row][0];
        cm.webUIAccess = access;
        [tableView reloadData];
        return;
    }
    NSArray *networks = cm.webUINetworks;
    if (indexPath.row < (NSInteger)networks.count) return;
    if (indexPath.row == (NSInteger)networks.count && [self canAddCurrentWiFi]) [self addNetwork:self.currentWiFi];
    else [self promptForNetwork];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *networks = [RCConfigManager sharedManager].webUINetworks;
    if (indexPath.section != RCWebUIAccessSectionNetworks || indexPath.row >= (NSInteger)networks.count) {
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
