#import "RCExcludedAppsViewController.h"
#import "RCConfigManager+AppExclusions.h"
#import "RCAppPickerViewController.h"

@interface RCExcludedAppsViewController ()
@property (nonatomic, copy) NSArray<NSString *> *triggerKeys;
@end

@implementation RCExcludedAppsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Excluded Apps";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.tableView.backgroundColor = [cm tweakColorForKey:@"settingsBackground"
                                             defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.triggerKeys = [[RCConfigManager sharedManager] assignedAppExclusionTriggerKeys];
    [self.tableView reloadData];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Assigned Status Bar Behaviors";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.triggerKeys.count
        ? @"Choose apps separately for each behavior. Only that behavior is skipped while a selected app is in front. Other triggers and the existing command-line blacklist are unchanged."
        : @"No status bar behaviors assigned. Add an action to a status bar trigger first, then return here to choose its excluded apps.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.triggerKeys.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSString *key = self.triggerKeys[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.text = [cm displayNameForTrigger:key];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.numberOfLines = 0;
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (id action in [cm actionsForTrigger:key]) {
        [labels addObject:[cm nameForCommand:action truncate:YES] ?: @"Action"];
    }
    NSUInteger count = [cm excludedAppsForTrigger:key].count;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@%lu excluded app%@",
        [labels componentsJoinedByString:@" · "], [cm isTriggerEnabled:key] ? @"" : @"Disabled · ",
        (unsigned long)count, count == 1 ? @"" : @"s"];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *key = self.triggerKeys[indexPath.row];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    RCAppPickerViewController *picker = [[RCAppPickerViewController alloc] init];
    picker.allowsMultipleApps = YES;
    picker.allowsEmptySelection = YES;
    picker.selectedBundleIds = [cm excludedAppsForTrigger:key];
    picker.onAppsSelected = ^(NSArray<NSString *> *names, NSArray<NSString *> *bundleIDs) {
        [[RCConfigManager sharedManager] setExcludedApps:bundleIDs forTrigger:key];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

@end
