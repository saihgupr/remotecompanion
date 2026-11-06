#import "RCExcludedAppsViewController.h"
#import "RCConfigManager+AppExclusions.h"
#import "RCAppPickerViewController.h"

@interface RCExcludedAppsViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<NSString *> *triggerKeys;
@property (nonatomic, copy) NSArray<NSString *> *filteredTriggerKeys;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation RCExcludedAppsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Excluded Apps";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] ? UITableViewAutomaticDimension : 64.0;
    self.tableView.estimatedRowHeight = 90;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.tableView.backgroundColor = [cm tweakColorForKey:@"settingsBackground"
                                             defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    // Setup Search
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Triggers";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wrapLongNamesSettingChanged:) name:@"RCWrapLongNamesSettingChanged" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.triggerKeys = [[RCConfigManager sharedManager] assignedAppExclusionTriggerKeys];
    self.filteredTriggerKeys = [self keysMatchingText:self.searchController.searchBar.text];
    [self.tableView reloadData];
}

- (void)wrapLongNamesSettingChanged:(NSNotification *)note {
    self.tableView.rowHeight = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] ? UITableViewAutomaticDimension : 64.0;
    [self.tableView reloadData];
}

- (NSArray<NSString *> *)keysMatchingText:(NSString *)text {
    if (!text.length) return self.triggerKeys;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    return [self.triggerKeys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:
        ^BOOL(NSString *key, NSDictionary<NSString *, id> *bindings) {
            NSString *name = [cm displayNameForTrigger:key] ?: key;
            return [name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound;
        }]];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Triggers";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredTriggerKeys.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSString *key = self.filteredTriggerKeys[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    BOOL wrapLongNames = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.text = [cm displayNameForTrigger:key];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.numberOfLines = wrapLongNames ? 0 : 1;
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (id action in [cm actionsForTrigger:key]) {
        [labels addObject:[cm nameForCommand:action truncate:YES] ?: @"Action"];
    }
    NSUInteger count = [cm excludedAppsForTrigger:key].count;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@%lu excluded app%@",
        [labels componentsJoinedByString:@" · "], [cm isTriggerEnabled:key] ? @"" : @"Disabled · ",
        (unsigned long)count, count == 1 ? @"" : @"s"];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = wrapLongNames ? 0 : 1;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *key = self.filteredTriggerKeys[indexPath.row];
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

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.filteredTriggerKeys = [self keysMatchingText:searchController.searchBar.text];
    [self.tableView reloadData];
}

@end
