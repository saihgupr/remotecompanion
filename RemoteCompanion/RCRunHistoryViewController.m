#import "RCRunHistoryViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

// One row of a run's details: an action as it was for that run, what happened there, and how deep
// in the If and Repeat blocks it sits
@interface RCRunStep : NSObject
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) NSInteger depth;
@property (nonatomic, assign) BOOL marker;  // Else, End If, End Repeat: dimmed
@property (nonatomic, assign) BOOL stoppedHere;
@end

@implementation RCRunStep
@end

// One run's details
@interface RCRunDetailViewController : UITableViewController
@property (nonatomic, copy) NSArray<RCRunStep *> *steps;
@property (nonatomic, copy) NSString *footer;
@end

@implementation RCRunDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.steps.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (!self.steps.count) {
        cell.textLabel.text = @"No actions recorded";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        return cell;
    }
    RCRunStep *step = self.steps[indexPath.row];
    cell.indentationWidth = 18;
    cell.indentationLevel = step.depth;
    cell.imageView.image = [UIImage systemImageNamed:step.icon];
    cell.imageView.tintColor = step.stoppedHere ? [UIColor systemOrangeColor] : step.marker ? [UIColor tertiaryLabelColor] : [UIColor systemGrayColor];
    cell.textLabel.text = step.name;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.textColor = step.marker ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    cell.detailTextLabel.text = step.detail.length ? step.detail : nil;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = step.stoppedHere ? [UIColor systemOrangeColor] : [UIColor secondaryLabelColor];
    return cell;
}

@end

@interface RCRunHistoryViewController ()
@property (nonatomic, copy) NSString *triggerKey; // nil: every trigger
@property (nonatomic, strong) NSArray<NSDictionary *> *runs;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation RCRunHistoryViewController

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _triggerKey = [triggerKey copy];
        _runs = @[];
        self.title = @"Run History";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self updateMenu];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

// Keep (how many runs each trigger keeps) and Clear
- (void)updateMenu {
    __weak typeof(self) weakSelf = self;
    NSInteger keep = [RCConfigManager sharedManager].runHistoryCount;
    NSMutableArray *choices = [NSMutableArray array];
    for (NSNumber *count in @[@0, @5, @10, @25, @50]) {
        NSString *title = count.integerValue ? [NSString stringWithFormat:@"%@ Runs", count] : @"Off";
        UIAction *choice = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *a) {
            [RCConfigManager sharedManager].runHistoryCount = count.integerValue;
            [weakSelf updateMenu];
            [weakSelf.tableView reloadData];
        }];
        choice.state = keep == count.integerValue ? UIMenuElementStateOn : UIMenuElementStateOff;
        [choices addObject:choice];
    }
    UIMenu *keepMenu = [UIMenu menuWithTitle:@"Keep" image:[UIImage systemImageNamed:@"clock.arrow.circlepath"] identifier:nil options:0 children:choices];
    UIAction *clear = [UIAction actionWithTitle:@"Clear History" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused UIAction *a) {
        NSString *command = weakSelf.triggerKey ? [@"clear run history " stringByAppendingString:weakSelf.triggerKey] : @"clear run history";
        [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reload]; });
        }];
    }];
    clear.attributes = UIMenuElementAttributesDestructive;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[UIMenu menuWithTitle:@"" children:@[keepMenu, clear]]];
}

- (void)reload {
    __weak typeof(self) weakSelf = self;
    NSString *command = self.triggerKey ? [@"run history " stringByAppendingString:self.triggerKey] : @"run history all";
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *runs = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.loaded = YES;
            strongSelf.runs = [runs isKindOfClass:[NSArray class]] ? runs : @[];
            [strongSelf.refreshControl endRefreshing];
            [strongSelf.tableView reloadData];
        });
    }];
}

#pragma mark - Describing a run

+ (NSString *)durationText:(double)seconds {
    if (seconds < 10) return [NSString stringWithFormat:@"%.1f s", seconds];
    NSInteger s = (NSInteger)round(seconds);
    if (s < 60) return [NSString stringWithFormat:@"%ld s", (long)s];
    if (s < 3600) return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
    return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(s / 3600), (long)(s / 60 % 60), (long)(s % 60)];
}

+ (NSString *)whenText:(double)started {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:started];
    NSString *time = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    if ([[NSCalendar currentCalendar] isDateInToday:date]) return [NSString stringWithFormat:@"Today %@", time];
    if ([[NSCalendar currentCalendar] isDateInYesterday:date]) return [NSString stringWithFormat:@"Yesterday %@", time];
    return [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
}

+ (NSString *)typeOfItem:(id)item {
    if ([item isKindOfClass:[NSDictionary class]]) return [[item[@"type"] description] lowercaseString];
    if ([item isKindOfClass:[NSString class]]) return [(NSString *)item lowercaseString];
    return nil;
}

// What happened at one action, from the run's trace: "True", "4 rounds", "Met after 3.5 s", "Set to “5”"...
+ (NSString *)traceText:(NSDictionary *)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) return @"";
    NSMutableArray *parts = [NSMutableArray array];
    NSInteger yes = [entry[@"true"] integerValue], no = [entry[@"false"] integerValue];
    if (yes + no == 1) [parts addObject:yes ? @"True" : @"False"];
    else if (yes + no > 1) [parts addObject:[NSString stringWithFormat:@"True %ld×, False %ld×", (long)yes, (long)no]];
    if (entry[@"rounds"]) {
        NSInteger rounds = [entry[@"rounds"] integerValue];
        [parts addObject:rounds == 0 ? @"Didn't run" : [NSString stringWithFormat:@"%ld round%@", (long)rounds, rounds == 1 ? @"" : @"s"]];
    }
    if ([entry[@"cap"] boolValue]) [parts addObject:@"Stopped at the 1,000-round limit"];
    if (entry[@"exit"]) [parts addObject:[entry[@"exit"] integerValue] == 1 ? @"Left the loop" : [NSString stringWithFormat:@"Left the loop %@×", entry[@"exit"]]];
    if (entry[@"problem"]) [parts addObject:[NSString stringWithFormat:@"Not changed: %@", entry[@"problem"]]];
    if (entry[@"value"]) {
        NSInteger sets = [entry[@"sets"] integerValue];
        NSString *value = [entry[@"value"] description];
        NSString *shown = value.length ? [NSString stringWithFormat:@"“%@”", value] : @"no text";
        [parts addObject:sets > 1 ? [NSString stringWithFormat:@"Set %ld×, last to %@", (long)sets, shown] : [NSString stringWithFormat:@"Set to %@", shown]];
    }
    if (entry[@"met"]) [parts addObject:[NSString stringWithFormat:@"%@ after %@", [entry[@"met"] boolValue] ? @"Met" : @"Time limit reached", [self durationText:[entry[@"seconds"] doubleValue]]]];
    return [parts componentsJoinedByString:@" · "];
}

// The run's actions as they were for that run, each with what happened there. A record from before
// runs kept their actions has only the traced rows, named from the trigger's actions now.
+ (NSArray<RCRunStep *> *)stepsForRun:(NSDictionary *)run {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSDictionary *trace = [run[@"trace"] isKindOfClass:[NSDictionary class]] ? run[@"trace"] : @{};
    NSArray *saved = [run[@"actions"] isKindOfClass:[NSArray class]] ? run[@"actions"] : nil;
    NSInteger stoppedAt = run[@"index"] && [run[@"outcome"] isEqual:@"stopped"] ? [run[@"index"] integerValue] : -1;
    NSMutableArray *steps = [NSMutableArray array];

    if (saved) {
        NSInteger depth = 0;
        for (NSInteger i = 0; i < (NSInteger)saved.count; i++) {
            id item = saved[i];
            NSString *type = [self typeOfItem:item] ?: @"";
            BOOL end = [@[@"end_if", @"end", @"end_repeat"] containsObject:type];
            BOOL middle = [@[@"else", @"else_if"] containsObject:type];
            if (end) depth = MAX(0, depth - 1);
            RCRunStep *step = [RCRunStep new];
            step.depth = middle ? MAX(0, depth - 1) : depth;
            step.marker = end || [type isEqualToString:@"else"];
            step.name = [cm nameForCommand:item truncate:YES] ?: @"";
            NSString *icon = [cm iconForCommand:item];
            step.icon = !icon.length || [icon hasPrefix:@"USER_APP:"] ? @"app" : icon;
            step.detail = [self traceText:trace[[NSString stringWithFormat:@"%ld", (long)i]]];
            if (i == stoppedAt) {
                step.stoppedHere = YES;
                step.detail = step.detail.length ? [step.detail stringByAppendingString:@" · Stopped here"] : @"Stopped here";
            }
            [steps addObject:step];
            if ([@[@"if", @"repeat", @"repeat_while"] containsObject:type]) depth++;
        }
        return steps;
    }

    NSString *key = [run[@"key"] isKindOfClass:[NSString class]] ? run[@"key"] : nil;
    NSArray *actions = key ? [cm actionsForTrigger:key] : @[];
    NSArray *indexes = [trace.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [@(a.integerValue) compare:@(b.integerValue)]; }];
    for (NSString *index in indexes) {
        NSInteger i = index.integerValue;
        id action = i < (NSInteger)actions.count ? actions[i] : nil;
        RCRunStep *step = [RCRunStep new];
        step.name = action ? [cm nameForCommand:action truncate:YES] : [NSString stringWithFormat:@"Action %ld", (long)i + 1];
        NSString *icon = action ? [cm iconForCommand:action] : nil;
        step.icon = !icon.length || [icon hasPrefix:@"USER_APP:"] ? @"circle" : icon;
        step.detail = [self traceText:trace[index]];
        [steps addObject:step];
    }
    return steps;
}

+ (NSString *)summaryForRun:(NSDictionary *)run {
    NSString *outcome = [run[@"outcome"] isEqual:@"stopped"] ? @"Stopped" : @"Finished";
    if ([run[@"test"] boolValue]) outcome = [@"Test · " stringByAppendingString:outcome];
    NSMutableArray *bits = [NSMutableArray arrayWithObject:outcome];
    NSDictionary *trace = [run[@"trace"] isKindOfClass:[NSDictionary class]] ? run[@"trace"] : @{};
    NSArray *indexes = [trace.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [@(a.integerValue) compare:@(b.integerValue)]; }];
    for (NSString *index in indexes) {
        NSString *text = [self traceText:trace[index]];
        if (text.length) [bits addObject:text];
    }
    return [bits componentsJoinedByString:@" · "];
}

+ (UIViewController *)detailForRun:(NSDictionary *)run {
    RCRunDetailViewController *detail = [[RCRunDetailViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    NSString *key = [run[@"key"] isKindOfClass:[NSString class]] ? run[@"key"] : nil;
    detail.title = key ? [[RCConfigManager sharedManager] displayNameForTrigger:key] : [self whenText:[run[@"started"] doubleValue]];
    detail.steps = [self stepsForRun:run];
    NSMutableString *footer = [NSMutableString stringWithFormat:@"%@ %@, after %@.", [run[@"outcome"] isEqual:@"stopped"] ? @"Stopped" : @"Finished",
                               [self whenText:[run[@"started"] doubleValue]], [self durationText:[run[@"seconds"] doubleValue]]];
    if ([run[@"test"] boolValue]) [footer appendString:@" A test run from the actions page."];
    if (![run[@"actions"] isKindOfClass:[NSArray class]]) [footer appendString:@" Recorded before runs kept their actions, so only conditions and loops are shown."];
    detail.footer = footer;
    return detail;
}

+ (void)deleteRun:(NSDictionary *)run completion:(void (^)(void))done {
    NSString *key = [run[@"key"] isKindOfClass:[NSString class]] ? run[@"key"] : nil;
    if (!key.length) { if (done) done(); return; }
    NSString *command = [NSString stringWithFormat:@"delete run history %.6f %@", [run[@"started"] doubleValue], key];
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(); });
    }];
}

#pragma mark - Rows

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.runs.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSInteger keep = [RCConfigManager sharedManager].runHistoryCount;
    if (keep == 0) return @"Run History is off. Turn it on with Keep in the ••• menu.";
    return [NSString stringWithFormat:@"The last %ld runs of %@ are kept. Tap a run to see its actions as they ran.", (long)keep, self.triggerKey ? @"this trigger" : @"each trigger"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    if (!self.runs.count) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = self.loaded ? @"No runs yet" : @"Loading…";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        return cell;
    }
    NSDictionary *run = self.runs[indexPath.row];
    BOOL stopped = [run[@"outcome"] isEqual:@"stopped"];
    NSString *when = [NSString stringWithFormat:@"%@ · %@", [[self class] whenText:[run[@"started"] doubleValue]], [[self class] durationText:[run[@"seconds"] doubleValue]]];
    NSString *summary = [[self class] summaryForRun:run];
    cell.imageView.image = [UIImage systemImageNamed:stopped ? @"stop.circle" : @"checkmark.circle"];
    cell.imageView.tintColor = stopped ? [UIColor systemOrangeColor] : [UIColor systemGreenColor];
    if (self.triggerKey) {
        cell.textLabel.text = when;
        cell.textLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = summary;
    } else {
        // Every trigger's runs: the trigger's name first
        NSString *key = [run[@"key"] isKindOfClass:[NSString class]] ? run[@"key"] : @"";
        cell.textLabel.text = [cm displayNameForTrigger:key];
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", when, summary];
        cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    }
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.runs.count > 0;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.runs.count || indexPath.row >= (NSInteger)self.runs.count) return [UISwipeActionsConfiguration configurationWithActions:@[]];
    NSMutableDictionary *run = [self.runs[indexPath.row] mutableCopy];
    if (!run[@"key"] && self.triggerKey) run[@"key"] = self.triggerKey;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { done(NO); return; }
        // Off the list at once; the history catches up
        NSMutableArray *runs = [strongSelf.runs mutableCopy];
        [runs removeObjectAtIndex:indexPath.row];
        strongSelf.runs = runs;
        if (runs.count) [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        else [tableView reloadData];
        done(YES);
        [RCRunHistoryViewController deleteRun:run completion:nil];
    }];
    delete.image = [UIImage systemImageNamed:@"trash.fill"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.runs.count) return;
    NSDictionary *run = self.runs[indexPath.row];
    UIViewController *detail = [[self class] detailForRun:run];
    if (self.triggerKey) detail.title = [[self class] whenText:[run[@"started"] doubleValue]];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
