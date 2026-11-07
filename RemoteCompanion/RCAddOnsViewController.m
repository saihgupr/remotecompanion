#import "RCAddOnsViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCAddOnCatalog.h"
#import "RCAddOnDetailViewController.h"
#import <notify.h>

@interface RCAddOnsViewController ()
@property (nonatomic, assign) RCAddOnsList list;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSString *> *items;
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;   // RCAddOnsListAll: { kind: addon|absent|problems, ... }
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
    self.title = self.list == RCAddOnsListAll ? @"Add-ons" : self.list == RCAddOnsListProblems ? @"Problems" : @"Not Installed";
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
    if (self.list == RCAddOnsListAll) {
        // Each add-on (on or off) by name, then rows for those not installed and the files with problems
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *addOn in [RCAddOnCatalog addOns]) [rows addObject:@{ @"kind": @"addon", @"addOn": addOn, @"on": @YES }];
        for (NSDictionary *addOn in [RCAddOnCatalog disabledAddOns]) [rows addObject:@{ @"kind": @"addon", @"addOn": addOn, @"on": @NO }];
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"addOn"][@"name"] localizedCaseInsensitiveCompare:b[@"addOn"][@"name"]];
        }];
        NSUInteger absent = [RCAddOnCatalog absentAddOnNames].count;
        NSUInteger problems = [RCAddOnCatalog problems].count + ([RCAddOnCatalog catalogAvailable] && ![RCAddOnCatalog commandsScriptLoaded] ? 1 : 0);
        if (absent) [rows addObject:@{ @"kind": @"absent", @"count": @(absent) }];
        if (problems) [rows addObject:@{ @"kind": @"problems", @"count": @(problems) }];
        self.rows = rows;
    } else if (self.list == RCAddOnsListNotInstalled) {
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
    return MAX(1, (NSInteger)(self.list == RCAddOnsListAll ? self.rows.count : self.items.count));
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.list == RCAddOnsListAll) return @"Added by other apps and tweaks.";
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
    if (self.list == RCAddOnsListAll && self.rows.count) {
        NSDictionary *row = self.rows[indexPath.row];
        NSString *kind = row[@"kind"];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        UIView *selBg = [[UIView alloc] init];
        selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
        cell.selectedBackgroundView = selBg;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if ([kind isEqualToString:@"addon"]) {
            NSDictionary *addOn = row[@"addOn"];
            BOOL on = [row[@"on"] boolValue];
            cell.textLabel.text = addOn[@"name"];
            cell.detailTextLabel.text = on ? [RCAddOnCatalog contentsOfAddOn:addOn] : @"Off";
            cell.imageView.image = [RCAddOnCatalog iconImageForAddOn:addOn] ?: [UIImage systemImageNamed:[RCAddOnCatalog iconForAddOn:addOn]];
            cell.imageView.tintColor = on ? [UIColor systemOrangeColor] : [UIColor secondaryLabelColor];
            cell.imageView.alpha = on ? 1.0 : 0.5;
        } else if ([kind isEqualToString:@"absent"]) {
            cell.textLabel.text = @"Not Installed";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ add-on%@ for apps or tweaks that aren't installed", row[@"count"], [row[@"count"] integerValue] == 1 ? @"" : @"s"];
            cell.imageView.image = [UIImage systemImageNamed:[RCAddOnCatalog defaultSymbol]];
            cell.imageView.tintColor = [UIColor secondaryLabelColor];
        } else {
            cell.textLabel.text = @"Problems";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ file%@ not loaded", row[@"count"], [row[@"count"] integerValue] == 1 ? @"" : @"s"];
            cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
            cell.imageView.tintColor = [UIColor systemOrangeColor];
        }
        return cell;
    }
    if (!(self.list == RCAddOnsListAll ? self.rows.count : self.items.count)) {
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.list != RCAddOnsListAll || indexPath.row >= (NSInteger)self.rows.count) return;
    NSDictionary *row = self.rows[indexPath.row];
    NSString *kind = row[@"kind"];
    UIViewController *next = nil;
    if ([kind isEqualToString:@"addon"]) next = [[RCAddOnDetailViewController alloc] initWithAddOnId:row[@"addOn"][@"id"]];
    else if ([kind isEqualToString:@"absent"]) next = [[RCAddOnsViewController alloc] initShowing:RCAddOnsListNotInstalled];
    else if ([kind isEqualToString:@"problems"]) next = [[RCAddOnsViewController alloc] initShowing:RCAddOnsListProblems];
    if (next) [self.navigationController pushViewController:next animated:YES];
}

@end
