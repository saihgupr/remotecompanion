#import "RCAddOnsViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCAddOnCatalog.h"
#import <notify.h>

@interface RCAddOnsViewController ()
@property (nonatomic, assign) RCAddOnsList list;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSString *> *items;
@property (nonatomic, assign) int changeToken;
@end

@implementation RCAddOnsViewController

- (instancetype)initShowing:(RCAddOnsList)list {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _list = list;
        _changeToken = NOTIFY_TOKEN_INVALID;
    }
    return self;
}

- (void)dealloc {
    if (_changeToken != NOTIFY_TOKEN_INVALID) notify_cancel(_changeToken);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.list == RCAddOnsListProblems ? @"Problems" : @"Not Installed";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    if (self.list == RCAddOnsListProblems) {
        // Reads the folders again now (the tweak watches them anyway), e.g. after fixing a file
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Reload" style:UIBarButtonItemStylePlain target:self action:@selector(reload)];
    }

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 10;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;
    self.tableView.backgroundColor = settingsBG;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    int token = NOTIFY_TOKEN_INVALID;
    __weak typeof(self) weakSelf = self;
    if (notify_register_dispatch([RCAddOnCatalog changedNotification], &token, dispatch_get_main_queue(), ^(int t) {
        [weakSelf readCatalog];
    }) == NOTIFY_STATUS_OK) self.changeToken = token;
    [self readCatalog];
}

- (void)reload {
    [[RCServerClient sharedClient] executeCommand:@"addons reload" completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self readCatalog]; });
    }];
}

- (void)readCatalog {
    if (self.list == RCAddOnsListNotInstalled) {
        self.items = [RCAddOnCatalog absentAddOnNames];
    } else {
        NSMutableArray *problems = [[RCAddOnCatalog problems] mutableCopy];
        // Without the command script the app can't read add-on actions; say so here, where people look
        if ([RCAddOnCatalog catalogAvailable] && ![RCAddOnCatalog commandsScriptLoaded]) {
            [problems insertObject:@"rc_addon_commands.js: didn't load, so add-on actions show no names or options (reinstall RemoteCompanion)" atIndex:0];
        }
        self.items = problems;
    }
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(1, (NSInteger)self.items.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.list == RCAddOnsListNotInstalled ? @"These add-ons appear once their app or tweak is installed." : @"A file with a problem isn't loaded until it's fixed.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.numberOfLines = 0;
    if (!self.items.count) {
        cell.textLabel.text = @"None";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        return cell;
    }
    NSString *item = self.items[indexPath.row];
    if (self.list == RCAddOnsListNotInstalled) {
        cell.textLabel.text = item;
        cell.imageView.image = [UIImage systemImageNamed:[RCAddOnCatalog defaultSymbol]];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
    } else {
        // "file.json: reason"
        NSRange colon = [item rangeOfString:@": "];
        cell.textLabel.text = colon.location == NSNotFound ? item : [item substringToIndex:colon.location];
        cell.detailTextLabel.text = colon.location == NSNotFound ? nil : [item substringFromIndex:NSMaxRange(colon)];
        cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
        cell.imageView.tintColor = [UIColor systemOrangeColor];
    }
    return cell;
}

@end
