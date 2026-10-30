#import "RCRunningViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCTriggersViewController.h"
#import "RCActionsViewController.h"
#import "RCRunHistoryViewController.h"
#import <notify.h>

@interface RCRunningViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *runs;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) int notifyToken;
@property (nonatomic, copy) NSString *filterKey;
@property (nonatomic, strong) UIBarButtonItem *stopAllItem;
@property (nonatomic, assign) BOOL swiping; // a row's swipe actions are open: no redraw until it closes
@property (nonatomic, assign) BOOL redrawPending;
@property (nonatomic, strong) NSArray<NSDictionary *> *recentRuns; // the last runs that ended, from Run History
@end

// Sections: the runs going, then the last ones that ended
typedef NS_ENUM(NSInteger, RCRunningSection) {
    RCRunningSectionNow,
    RCRunningSectionRecent,
};
static const NSInteger kRCRecentRunsShown = 5;

@implementation RCRunningViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _runs = @[];
        _recentRuns = @[];
        _notifyToken = NOTIFY_TOKEN_INVALID;
        self.title = @"Running";
    }
    return self;
}

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [self init];
    if (self) {
        _filterKey = [triggerKey copy];
        self.title = [[RCConfigManager sharedManager] displayNameForTrigger:triggerKey];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.stopAllItem = [[UIBarButtonItem alloc] initWithTitle:@"Stop All" style:UIBarButtonItemStylePlain target:self action:@selector(stopAll)];
    self.stopAllItem.tintColor = [UIColor systemRedColor];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
    [self refreshRecent];
    __weak typeof(self) weakSelf = self;
    // Every second for the time and the step, and at once when a run starts or ends (when the
    // recent runs change too)
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
    int token;
    if (notify_register_dispatch("com.pizzaman.rc.runs_changed", &token, dispatch_get_main_queue(), ^(int t) { [weakSelf refresh]; [weakSelf refreshRecent]; }) == NOTIFY_STATUS_OK) {
        self.notifyToken = token;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    if (self.notifyToken != NOTIFY_TOKEN_INVALID) notify_cancel(self.notifyToken);
    self.notifyToken = NOTIFY_TOKEN_INVALID;
}

- (void)refresh {
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"running" completion:^(NSString *output, NSError *error) {
        NSArray *runs = nil;
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        if (data) runs = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.loaded = YES;
            NSArray *all = [runs isKindOfClass:[NSArray class]] ? runs : @[];
            if (strongSelf.filterKey) all = [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key == %@", strongSelf.filterKey]];
            strongSelf.runs = all;
            // Stop All only while there's something to stop (not a greyed button that can still be tapped)
            strongSelf.navigationItem.rightBarButtonItem = strongSelf.runs.count ? strongSelf.stopAllItem : nil;
            [strongSelf redraw];
        });
    }];
}

// The once-a-second redraw would close a swiped-open row (its Stop or Delete), so it waits
- (void)redraw {
    if (self.swiping) { self.redrawPending = YES; return; }
    self.redrawPending = NO;
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    self.swiping = YES;
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    self.swiping = NO;
    if (self.redrawPending) [self redraw];
}

// The last runs that ended (this trigger's, on its own page), newest first
- (void)refreshRecent {
    __weak typeof(self) weakSelf = self;
    NSString *command = self.filterKey ? [@"run history " stringByAppendingString:self.filterKey] : [NSString stringWithFormat:@"run history all %ld", (long)kRCRecentRunsShown];
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *runs = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSArray *recent = [runs isKindOfClass:[NSArray class]] ? runs : @[];
            if ((NSInteger)recent.count > kRCRecentRunsShown) recent = [recent subarrayWithRange:NSMakeRange(0, kRCRecentRunsShown)];
            strongSelf.recentRuns = recent;
            [strongSelf redraw];
        });
    }];
}

// Stop on a row: just that run (a trigger set to Run Alongside can have several)
- (void)stopRun:(NSDictionary *)run {
    NSString *runID = [run[@"id"] isKindOfClass:[NSString class]] ? run[@"id"] : nil;
    if (!runID.length) return;
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:[@"stop run " stringByAppendingString:runID] completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
    }];
}

// Stop All: every run of each trigger
- (void)stopTrigger:(NSString *)key {
    if (!key.length) return;
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:[@"stop trigger " stringByAppendingString:key] completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
    }];
}

- (void)stopAll {
    NSMutableSet *keys = [NSMutableSet set];
    for (NSDictionary *run in self.runs) if ([run[@"key"] isKindOfClass:[NSString class]]) [keys addObject:run[@"key"]];
    for (NSString *key in keys) [self stopTrigger:key];
}

#pragma mark - Rows

- (NSString *)elapsedText:(double)seconds {
    NSInteger s = (NSInteger)seconds;
    if (s < 60) return [NSString stringWithFormat:@"%ld s", (long)s];
    if (s < 3600) return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
    return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(s / 3600), (long)(s / 60 % 60), (long)(s % 60)];
}

// The step it's on, as the action editor names it, and the round of the loop it's in
- (NSString *)stepTextForRun:(NSDictionary *)run {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    id step = run[@"step"];
    NSString *text = step ? [cm nameForCommand:step truncate:YES] : @"Starting";
    NSDictionary *loop = [run[@"loop"] isKindOfClass:[NSDictionary class]] ? run[@"loop"] : nil;
    if (loop) {
        NSDictionary *repeat = loop[@"repeat"];
        NSInteger round = [loop[@"round"] integerValue];
        NSInteger count = [repeat isKindOfClass:[NSDictionary class]] ? [repeat[@"count"] integerValue] : 0;
        NSString *roundText = count > 0 ? [NSString stringWithFormat:@"Round %ld of %ld", (long)round, (long)count] : [NSString stringWithFormat:@"Round %ld", (long)round];
        // On the Repeat row itself: its name and round; inside it: the step, then the round
        BOOL onRepeat = [step isKindOfClass:[NSDictionary class]] && [step isEqual:repeat];
        text = onRepeat ? [NSString stringWithFormat:@"%@ · %@", [cm nameForCommand:repeat truncate:YES], roundText]
                        : [NSString stringWithFormat:@"%@ · %@", text, roundText];
    }
    return text;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

// Recent: the last runs, then Run History (all of them)
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RCRunningSectionRecent) return self.recentRuns.count + 1;
    return MAX(self.runs.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == RCRunningSectionRecent ? @"Recent" : @"Now";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCRunningSectionRecent) return nil;
    return @"Stop ends that run of the trigger, even during a wait or a loop; Stop All ends every run. Tap a run to follow it, with the action it's on highlighted.";
}

- (UITableViewCell *)recentCellForRow:(NSInteger)row {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (row >= (NSInteger)self.recentRuns.count) {
        cell.textLabel.text = @"Run History";
        cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
        cell.imageView.tintColor = [UIColor systemGrayColor];
        return cell;
    }
    NSDictionary *run = self.recentRuns[row];
    BOOL stopped = [run[@"outcome"] isEqual:@"stopped"];
    NSString *key = [run[@"key"] isKindOfClass:[NSString class]] ? run[@"key"] : self.filterKey;
    NSString *when = [NSString stringWithFormat:@"%@ · %@", [RCRunHistoryViewController whenText:[run[@"started"] doubleValue]], [RCRunHistoryViewController durationText:[run[@"seconds"] doubleValue]]];
    cell.imageView.image = [UIImage systemImageNamed:stopped ? @"stop.circle" : @"checkmark.circle"];
    cell.imageView.tintColor = stopped ? [UIColor systemOrangeColor] : [UIColor systemGreenColor];
    cell.textLabel.text = self.filterKey ? when : [cm displayNameForTrigger:key ?: @""];
    cell.textLabel.font = self.filterKey ? [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium] : [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    NSString *summary = [RCRunHistoryViewController summaryForRun:run];
    cell.detailTextLabel.text = self.filterKey ? summary : [NSString stringWithFormat:@"%@ · %@", when, summary];
    cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 2;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == RCRunningSectionRecent) return [self recentCellForRow:indexPath.row];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;

    if (self.runs.count == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = !self.loaded ? @"Loading…" : self.filterKey ? @"Not running" : @"No triggers are running";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        return cell;
    }

    NSDictionary *run = self.runs[indexPath.row];
    NSString *key = [run[@"key"] isKindOfClass:[NSString class]] ? run[@"key"] : @"";
    cell.textLabel.text = [cm displayNameForTrigger:key];
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.imageView.image = [UIImage systemImageNamed:[RCTriggersViewController iconNameForTrigger:key]];
    cell.imageView.tintColor = [UIColor systemGrayColor];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@ · %@", [run[@"test"] boolValue] ? @"Test · " : @"", [self elapsedText:[run[@"seconds"] doubleValue]], [self stepTextForRun:run]];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.detailTextLabel.numberOfLines = 2;

    UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
    [stop setImage:[UIImage systemImageNamed:@"stop.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24]] forState:UIControlStateNormal];
    stop.tintColor = [UIColor systemRedColor];
    stop.frame = CGRectMake(0, 0, 36, 36);
    stop.accessibilityLabel = @"Stop";
    [stop addAction:[UIAction actionWithHandler:^(__unused UIAction *action) { [self stopRun:run]; }] forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = stop;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == RCRunningSectionRecent || self.runs.count > 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == RCRunningSectionRecent) {
        UIViewController *next = indexPath.row < (NSInteger)self.recentRuns.count
            ? [RCRunHistoryViewController detailForRun:self.recentRuns[indexPath.row]]
            : [[RCRunHistoryViewController alloc] initWithTriggerKey:self.filterKey];
        [self.navigationController pushViewController:next animated:YES];
        return;
    }
    if (self.runs.count == 0) return;
    // The run's debugger view: the action it's on highlighted, as it goes
    NSString *key = self.runs[indexPath.row][@"key"];
    NSString *runID = self.runs[indexPath.row][@"id"];
    if (![key isKindOfClass:[NSString class]] || ![runID isKindOfClass:[NSString class]]) return;
    RCActionsViewController *editor = [[RCActionsViewController alloc] initWithTriggerKey:key followingRun:runID];
    [self.navigationController pushViewController:editor animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == RCRunningSectionRecent) {
        // A recent run: Delete takes it out of Run History
        if (indexPath.row >= (NSInteger)self.recentRuns.count) return [UISwipeActionsConfiguration configurationWithActions:@[]];
        NSMutableDictionary *recent = [self.recentRuns[indexPath.row] mutableCopy];
        if (!recent[@"key"] && self.filterKey) recent[@"key"] = self.filterKey;
        __weak typeof(self) weakSelf = self;
        UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            // Off the list at once; the history catches up
            if (strongSelf && indexPath.row < (NSInteger)strongSelf.recentRuns.count) {
                NSMutableArray *recentRuns = [strongSelf.recentRuns mutableCopy];
                [recentRuns removeObjectAtIndex:indexPath.row];
                strongSelf.recentRuns = recentRuns;
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
            done(YES);
            [RCRunHistoryViewController deleteRun:recent completion:^{ [weakSelf refreshRecent]; }];
        }];
        delete.image = [UIImage systemImageNamed:@"trash.fill"];
        return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
    }
    if (self.runs.count == 0) return [UISwipeActionsConfiguration configurationWithActions:@[]];
    NSDictionary *run = self.runs[indexPath.row];
    UIContextualAction *stop = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Stop" handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        [self stopRun:run];
        done(YES);
    }];
    stop.image = [UIImage systemImageNamed:@"stop.fill"];
    return [UISwipeActionsConfiguration configurationWithActions:@[stop]];
}

@end
