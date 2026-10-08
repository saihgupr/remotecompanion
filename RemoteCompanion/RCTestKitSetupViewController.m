#import "RCTestKitSetupViewController.h"
#import "RCTestKitViewController.h"
#import "RCConfigManager.h"

static const NSInteger kRCMaxStepCount = 5;

@interface RCTestKitSetupViewController ()
@property (nonatomic, copy) NSString *suite;
@property (nonatomic, strong) NSArray<NSDictionary *> *allSteps;    // as the tweak lists them: id, prompt, group, optional, note, replayOnly, scripted
@property (nonatomic, strong) NSArray<NSString *> *groupNames;      // the steps shown, grouped
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *groups;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *counts; // only steps not done once
@property (nonatomic, assign) BOOL handsOff;                        // the tweak does what it can
@property (nonatomic, assign) BOOL includeByHand;                   // automatic Gestures & Sensors: the steps only a person can do too
@property (nonatomic, assign) NSUInteger hiddenCount;               // steps of the suite this setup leaves out
@end

@implementation RCTestKitSetupViewController

// Only counts other than 1 are kept, so steps added later start out once
- (NSString *)countsKey { return [@"RCTestKitStepCounts." stringByAppendingString:self.suite]; }
- (NSString *)modeKey { return [@"RCTestKitHandsOff." stringByAppendingString:self.suite]; }
- (NSString *)includeKey { return [@"RCTestKitIncludeByHand." stringByAppendingString:self.suite]; }

- (instancetype)initWithSuite:(NSString *)suite {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _suite = [suite copy];
    }
    return self;
}

// Gestures & Sensors and Stock vs Tweak can be done by the tweak or by hand
- (BOOL)hasMode {
    return [self.suite isEqualToString:@"guided"] || [self.suite isEqualToString:@"differential"];
}

// Automatic Gestures & Sensors: whether to include the steps only a person can do
- (BOOL)hasIncludeRow {
    return self.handsOff && [self.suite isEqualToString:@"guided"];
}

- (NSInteger)includeSection { return 1; }
- (NSInteger)totalsSection { return (self.hasMode ? 1 : 0) + (self.hasIncludeRow ? 1 : 0); }
- (NSInteger)firstStepSection { return self.totalsSection + 1; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [RCTestKitViewController displayNameForSuite:self.suite];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"settingsBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Start" style:UIBarButtonItemStyleDone target:self action:@selector(start)];
    self.navigationItem.rightBarButtonItem.enabled = NO;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *saved = [defaults dictionaryForKey:[self countsKey]];
    self.counts = [saved isKindOfClass:[NSDictionary class]] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    self.handsOff = [defaults objectForKey:[self modeKey]] ? [defaults boolForKey:[self modeKey]] : YES;
    self.includeByHand = [defaults objectForKey:[self includeKey]] ? [defaults boolForKey:[self includeKey]] : YES;
    self.allSteps = @[];
    self.groupNames = @[];
    self.groups = @[];

    [self loadSteps];
}

// The steps in the order the run does them; automatic Gestures & Sensors puts the ones you do first
- (void)loadSteps {
    NSString *request = [@"suite/steps name=" stringByAppendingString:self.suite];
    if (self.handsOff && [self.suite isEqualToString:@"guided"]) request = [request stringByAppendingString:@"&auto=1"];
    [RCTestKitViewController sendRequest:request completion:^(NSDictionary *json, NSError *error) {
        NSArray *steps = [json[@"steps"] isKindOfClass:[NSArray class]] ? json[@"steps"] : nil;
        if (!steps.count) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't Load Steps"
                                                                           message:json[@"error"] ?: error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        self.allSteps = steps;
        [self regroup];
        [self.tableView reloadData];
        [self updateStart];
    }];
}

// The steps this setup does, in groups in the order their first step comes. Stock vs Tweak's
// timing sweep exists only when the tweak does the presses; automatic Gestures & Sensors
// lists the steps only a person can do apart, first, as they run.
- (void)regroup {
    BOOL apartByHand = self.hasIncludeRow;
    NSMutableArray *names = [NSMutableArray array], *byHand = [NSMutableArray array];
    NSMutableDictionary *byGroup = [NSMutableDictionary dictionary];
    self.hiddenCount = 0;
    for (NSDictionary *step in self.allSteps) {
        if ([step[@"replayOnly"] boolValue] && !self.handsOff) { self.hiddenCount++; continue; }
        if (apartByHand && ![step[@"scripted"] boolValue]) {
            if (self.includeByHand) [byHand addObject:step]; else self.hiddenCount++;
            continue;
        }
        NSString *group = step[@"group"] ?: @"Other";
        if (!byGroup[group]) { byGroup[group] = [NSMutableArray array]; [names addObject:group]; }
        [byGroup[group] addObject:step];
    }
    NSMutableArray *groups = [NSMutableArray array];
    for (NSString *name in names) [groups addObject:byGroup[name]];
    if (byHand.count) {
        [names insertObject:@"Manual Steps" atIndex:0];
        [groups insertObject:byHand atIndex:0];
    }
    self.groupNames = names;
    self.groups = groups;
}

- (void)includeChanged:(UISwitch *)toggle {
    self.includeByHand = toggle.on;
    [[NSUserDefaults standardUserDefaults] setBool:toggle.on forKey:[self includeKey]];
    [self regroup];
    [self.tableView reloadData];
    [self updateStart];
}

#pragma mark - Counts

- (NSArray<NSDictionary *> *)shownSteps {
    NSMutableArray *all = [NSMutableArray array];
    for (NSArray *group in self.groups) [all addObjectsFromArray:group];
    return all;
}

- (NSInteger)countFor:(NSString *)stepId {
    NSNumber *count = self.counts[stepId];
    return count ? MAX(0, MIN(kRCMaxStepCount, count.integerValue)) : 1;
}

- (void)setCount:(NSInteger)count for:(NSString *)stepId {
    if (count == 1) [self.counts removeObjectForKey:stepId];
    else self.counts[stepId] = @(count);
    [[NSUserDefaults standardUserDefaults] setObject:self.counts forKey:[self countsKey]];
}

// An icon that tells a step apart at a glance: its direction, button, count or sensor
static UIImage *RCStepIcon(NSString *stepId) {
    NSArray<NSArray<NSString *> *> *rules = @[
        // gestures and sensors
        @[@"ringer", @"bell.slash"], @[@"statusbar_double_tap", @"hand.tap"],
        @[@"left_hold", @"hand.point.up.left"], @[@"center_hold", @"hand.point.up.left"], @[@"right_hold", @"hand.point.up.left"],
        @[@"swipe_up", @"arrow.up"], @[@"swipe_down", @"arrow.down"], @[@"swipe_left", @"arrow.left"], @[@"swipe_right", @"arrow.right"],
        @[@"shake", @"iphone.radiowaves.left.and.right"], @[@"touchid", @"touchid"],
        @[@"device_unlock", @"lock.open"], @[@"device_lock", @"lock"],
        @[@"power_connect", @"bolt"], @[@"power_disconnect", @"bolt.slash"],
        // buttons: chords, sequences and holds, then click counts
        @[@"home_power", @"camera.viewfinder"], @[@"power_volume_up", @"plus.circle"], @[@"power_volume_down", @"minus.circle"],
        @[@"volume_both", @"plusminus"], @[@"up_then_down", @"arrow.up.arrow.down"], @[@"down_then_up", @"arrow.up.arrow.down|flipped"], @[@"hold", @"timer"], @[@"long_press", @"timer"],
        @[@"volume_up", @"speaker.wave.3"], @[@"volume_down", @"speaker.wave.1"],
        @[@"single", @"1.circle"], @[@"double", @"2.circle"], @[@"triple", @"3.circle"], @[@"quadruple", @"4.circle"],
        @[@"power", @"power"],
    ];
    for (NSArray<NSString *> *rule in rules) {
        if ([stepId rangeOfString:rule[0]].location == NSNotFound) continue;
        // "|flipped": mirrored, e.g. up-arrow-then-down-arrow becomes down then up
        NSArray *parts = [rule[1] componentsSeparatedByString:@"|"];
        UIImage *image = [UIImage systemImageNamed:parts[0]];
        if (image && parts.count > 1) image = [[image imageWithHorizontallyFlippedOrientation] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        if (image) return image;
        break;
    }
    return [UIImage systemImageNamed:@"circle"];
}

static NSString *RCCountText(NSInteger count) {
    if (count == 0) return @"Off";
    return count == 1 ? @"Once" : [NSString stringWithFormat:@"%ld times", (long)count];
}

// The totals row and Start reflect the counts; only that row is reloaded, never the steps
- (void)updateStart {
    NSInteger steps = 0, runs = 0;
    for (NSDictionary *step in [self shownSteps]) {
        NSInteger count = [self countFor:step[@"id"]];
        if (count) steps++;
        runs += count;
    }
    self.navigationItem.rightBarButtonItem.enabled = runs > 0;
    UITableViewCell *totals = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:self.totalsSection]];
    totals.textLabel.text = [self totalsTextSteps:steps runs:runs];
}

- (NSString *)totalsTextSteps:(NSInteger)steps runs:(NSInteger)runs {
    if (runs == steps) return [NSString stringWithFormat:@"%ld of %lu Steps", (long)steps, (unsigned long)[self shownSteps].count];
    return [NSString stringWithFormat:@"%ld Steps, %ld Runs", (long)steps, (long)runs];
}

- (void)allOrNone:(UISegmentedControl *)control {
    NSInteger count = control.selectedSegmentIndex == 0 ? 1 : 0;
    for (NSDictionary *step in [self shownSteps]) [self setCount:count for:step[@"id"]];
    [self.tableView reloadData];
    [self updateStart];
}

- (void)stepperChanged:(UIStepper *)stepper {
    NSDictionary *step = [self stepForView:stepper];
    if (!step) return;
    [self setCount:(NSInteger)stepper.value for:step[@"id"]];
    [self showCount:(NSInteger)stepper.value forStep:step inCell:[self cellForView:stepper]];
    [self updateStart];
}

- (UITableViewCell *)cellForView:(UIView *)view {
    while (view && ![view isKindOfClass:[UITableViewCell class]]) view = view.superview;
    return (UITableViewCell *)view;
}

- (NSDictionary *)stepForView:(UIView *)view {
    NSIndexPath *path = [self.tableView indexPathForCell:[self cellForView:view]];
    if (!path || path.section < self.firstStepSection) return nil;
    return self.groups[path.section - self.firstStepSection][path.row];
}

- (void)showCount:(NSInteger)count forStep:(NSDictionary *)step inCell:(UITableViewCell *)cell {
    // The count, then what sets the step apart (two steps can share a prompt)
    NSString *text = RCCountText(count);
    if ([step[@"optional"] boolValue]) text = [text stringByAppendingString:@" - optional, skipped after 15 s"];
    if ([step[@"note"] length]) text = [text stringByAppendingFormat:@"\n%@", step[@"note"]];
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.text = text;
    cell.textLabel.textColor = count ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    [cell setNeedsLayout];
}

- (void)start {
    NSMutableArray *items = [NSMutableArray array];
    BOOL everyOnce = YES;
    for (NSDictionary *step in [self shownSteps]) {
        NSInteger count = [self countFor:step[@"id"]];
        if (count != 1) everyOnce = NO;
        if (count == 1) [items addObject:step[@"id"]];
        else if (count > 1) [items addObject:[NSString stringWithFormat:@"%@:%ld", step[@"id"], (long)count]];
    }
    // Every step once is the default; steps left out need the list
    NSString *options = everyOnce && !self.hiddenCount ? @"" : [@"&steps=" stringByAppendingString:[items componentsJoinedByString:@","]];
    if (self.hasMode && self.handsOff) {
        options = [([self.suite isEqualToString:@"guided"] ? @"&auto=1" : @"&replay=1") stringByAppendingString:options];
    }
    if (self.onStart) self.onStart(options);
}

#pragma mark - Mode

- (void)setMode:(BOOL)handsOff {
    if (handsOff == self.handsOff) return;
    self.handsOff = handsOff;
    [[NSUserDefaults standardUserDefaults] setBool:handsOff forKey:[self modeKey]];
    [self regroup];
    [self.tableView reloadData];
    [self updateStart];
    if ([self.suite isEqualToString:@"guided"]) [self loadSteps]; // another order
}

#pragma mark - Table

- (UITableViewCell *)styledCellWithStyle:(UITableViewCellStyle)style {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selection = [[UIView alloc] init];
    selection.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selection;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.firstStepSection + self.groups.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.hasMode && section == 0) return @"Testing Method";
    if (self.hasIncludeRow && section == self.includeSection) return nil;
    if (section == self.totalsSection) return @"Steps";
    return self.groupNames[section - self.firstStepSection];
}

// What the run will do, under the totals row
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.hasIncludeRow && section == self.includeSection) {
        return @"Steps the phone can't do by itself. They run first, so the phone can be left alone for the rest.";
    }
    if (section != self.totalsSection) return nil;
    NSString *swapped = @"Your triggers are swapped for test ones (their actions don't run) and put back after.";
    NSString *begin = @" To begin, go to the home screen and press Volume Up.";
    if ([self.suite isEqualToString:@"replay"]) {
        return [swapped stringByAppendingString:@" Leave the phone alone while it runs; repeats vary the timing slightly. Power presses are limited for safety, run last, and may lock the phone."];
    }
    if ([self.suite isEqualToString:@"guided"]) {
        NSString *text = [swapped stringByAppendingString:@" Button presses are tested in Button Triggers."];
        return self.handsOff ? [text stringByAppendingString:@" With a passcode set under Unlocking, the tweak also unlocks the phone."] : [text stringByAppendingString:begin];
    }
    NSString *text = @"Each press is done twice: with the tweak off, then on. iOS responds to every press as it would to a real one.";
    return self.handsOff ? [text stringByAppendingString:@" Each pass starts from the same state: the lock screen, and the home screen too when a passcode is set under Unlocking."]
                         : [text stringByAppendingFormat:@" Each pass starts unlocked on the home screen; with a passcode set under Unlocking, the tweak unlocks the phone itself.%@", begin];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.hasMode && section == 0) return 2;
    if (self.hasIncludeRow && section == self.includeSection) return 1;
    if (section == self.totalsSection) return 1;
    return self.groups[section - self.firstStepSection].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.hasMode && indexPath.section == 0) {
        UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleDefault];
        cell.textLabel.text = indexPath.row == 0 ? @"Automatic" : @"Manual";
        cell.imageView.image = [UIImage systemImageNamed:indexPath.row == 0 ? @"play.circle" : @"hand.point.up.left"];
        cell.imageView.tintColor = [UIColor systemTealColor];
        cell.accessoryType = (indexPath.row == 0) == self.handsOff ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }
    if (self.hasIncludeRow && indexPath.section == self.includeSection) {
        UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleDefault];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"Manual Steps";
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = self.includeByHand;
        [toggle addTarget:self action:@selector(includeChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }
    if (indexPath.section == self.totalsSection) {
        UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleDefault];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        NSInteger steps = 0, runs = 0;
        for (NSDictionary *step in [self shownSteps]) {
            NSInteger count = [self countFor:step[@"id"]];
            if (count) steps++;
            runs += count;
        }
        cell.textLabel.text = [self totalsTextSteps:steps runs:runs];
        UISegmentedControl *all = [[UISegmentedControl alloc] initWithItems:@[@"All", @"None"]];
        all.momentary = YES;
        [all addTarget:self action:@selector(allOrNone:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = all;
        return cell;
    }
    NSDictionary *step = self.groups[indexPath.section - self.firstStepSection][indexPath.row];
    NSInteger count = [self countFor:step[@"id"]];
    UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleSubtitle];
    cell.textLabel.text = step[@"name"] ?: step[@"prompt"];
    cell.imageView.image = RCStepIcon(step[@"id"]);
    cell.imageView.tintColor = [UIColor systemTealColor];
    [self showCount:count forStep:step inCell:cell];
    // Each row its own stepper: one view can't be the accessory of two cells
    UIStepper *stepper = [[UIStepper alloc] init];
    stepper.minimumValue = 0;
    stepper.maximumValue = kRCMaxStepCount;
    stepper.value = count;
    [stepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = stepper;
    return cell;
}

// Tapping a mode picks it; tapping a step turns it off, or on once
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.hasMode && indexPath.section == 0) {
        [self setMode:indexPath.row == 0];
        return;
    }
    if (indexPath.section < self.firstStepSection) return;
    NSDictionary *step = self.groups[indexPath.section - self.firstStepSection][indexPath.row];
    NSInteger count = [self countFor:step[@"id"]] ? 0 : 1;
    [self setCount:count for:step[@"id"]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    ((UIStepper *)cell.accessoryView).value = count;
    [self showCount:count forStep:step inCell:cell];
    [self updateStart];
}

@end
