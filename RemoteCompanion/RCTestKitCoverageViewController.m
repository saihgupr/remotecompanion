#import "RCTestKitCoverageViewController.h"
#import "RCTestKitViewController.h"
#import "RCTriggersViewController.h"
#import "RCActionPickerViewController.h"
#import "RCActionsViewController.h"
#import "RCConfigManager.h"

@interface RCActionsViewController (RCCoverage)
- (NSArray<NSDictionary *> *)ifConditionDefinitions;
@end

typedef NS_ENUM(NSInteger, RCCoverageKind) { RCCoverageTriggers, RCCoverageActions, RCCoverageConditions };

@interface RCTestKitCoverageViewController ()
@property (nonatomic, strong) NSDictionary *coverage;   // from the tweak
@property (nonatomic, copy) NSString *errorText;
@property (nonatomic) RCCoverageKind kind;
@property (nonatomic) BOOL onlyUntested;
@property (nonatomic, strong) UISegmentedControl *kindControl;
// For the kind shown: sections {title, rows: [{title, detail, tested}]}, and the counts
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic) NSUInteger testedCount, totalCount;
// The app's own lists (read once)
@property (nonatomic, copy) NSArray<NSDictionary *> *triggerCatalog;
@property (nonatomic, copy) NSArray<NSArray<NSDictionary *> *> *actionSections;
@property (nonatomic, copy) NSArray<NSString *> *actionTitles;
@property (nonatomic, copy) NSArray<NSDictionary *> *conditionDefinitions;
@end

@implementation RCTestKitCoverageViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Coverage";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"settingsBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    self.kindControl = [[UISegmentedControl alloc] initWithItems:@[@"Triggers", @"Actions", @"Conditions"]];
    self.kindControl.selectedSegmentIndex = 0;
    [self.kindControl addTarget:self action:@selector(kindChanged) forControlEvents:UIControlEventValueChanged];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 52)];
    self.kindControl.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.kindControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.kindControl.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [self.kindControl.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [self.kindControl.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];
    self.tableView.tableHeaderView = header;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Not Tested" style:UIBarButtonItemStylePlain target:self action:@selector(toggleFilter)];

    self.triggerCatalog = [RCTriggersViewController newTriggerCatalog];
    RCActionPickerViewController *picker = [[RCActionPickerViewController alloc] init];
    self.actionSections = [picker catalogSections];
    self.actionTitles = [picker catalogSectionTitles];
    RCActionsViewController *editor = [[RCActionsViewController alloc] initWithTriggerKey:@"__testkit_coverage__"];
    self.conditionDefinitions = [editor respondsToSelector:@selector(ifConditionDefinitions)] ? [editor ifConditionDefinitions] : @[];

    [self rebuild];
    __weak typeof(self) weakSelf = self;
    [RCTestKitViewController sendRequest:@"coverage" completion:^(NSDictionary *json, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.coverage = json;
            weakSelf.errorText = json ? nil : (error.localizedDescription ?: @"The tweak didn't answer");
            [weakSelf rebuild];
        });
    }];
}

- (void)kindChanged {
    self.kind = self.kindControl.selectedSegmentIndex;
    [self rebuild];
}

// Every row, or only the ones no suite tests
- (void)toggleFilter {
    self.onlyUntested = !self.onlyUntested;
    self.navigationItem.rightBarButtonItem.title = self.onlyUntested ? @"All" : @"Not Tested";
    [self rebuild];
}

// The suites that test it, as the Test Kit screen names them
- (NSString *)suitesText:(NSArray *)suites {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *suite in suites) {
        NSString *base = [suite componentsSeparatedByString:@" "].firstObject;
        NSString *name = [RCTestKitViewController displayNameForSuite:base] ?: suite;
        if ([suite containsString:@"disruptive"]) name = [name stringByAppendingString:@" (disruptive)"];
        if (![names containsObject:name]) [names addObject:name];
    }
    return [names componentsJoinedByString:@", "];
}

- (void)rebuild {
    NSDictionary *tested = nil;
    NSMutableArray *sections = [NSMutableArray array];
    NSUInteger testedCount = 0, total = 0;
    NSMutableDictionary<NSString *, NSMutableArray *> *bySection = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    void (^addRow)(NSString *, NSString *, NSArray *) = ^(NSString *section, NSString *title, NSArray *suites) {
        BOOL isTested = suites.count > 0;
        if (!bySection[section]) { bySection[section] = [NSMutableArray array]; [order addObject:section]; }
        [bySection[section] addObject:@{ @"title": title ?: @"", @"tested": @(isTested), @"detail": isTested ? [self suitesText:suites] : @"Not tested" }];
    };

    if (self.kind == RCCoverageTriggers) {
        tested = self.coverage[@"triggers"];
        for (NSDictionary *item in self.triggerCatalog) {
            NSString *key = item[@"key"], *kindPrefix = item[@"kind"];
            NSMutableOrderedSet *suites = [NSMutableOrderedSet orderedSet];
            if (key) [suites addObjectsFromArray:tested[key] ?: @[]];
            else if (kindPrefix) {
                for (NSString *testedKey in tested) if ([testedKey hasPrefix:kindPrefix]) [suites addObjectsFromArray:tested[testedKey]];
            } else continue; // an add-on's own list
            addRow(item[@"section"] ?: @"Other", kindPrefix ? [item[@"title"] stringByAppendingString:@" (created)"] : item[@"title"], suites.array);
        }
    } else if (self.kind == RCCoverageActions) {
        tested = self.coverage[@"actions"];
        [self.actionSections enumerateObjectsUsingBlock:^(NSArray<NSDictionary *> *items, NSUInteger i, BOOL *stop) {
            NSString *section = i < self.actionTitles.count ? self.actionTitles[i] : @"Actions";
            for (NSDictionary *item in items) {
                NSString *command = item[@"command"];
                if (![command isKindOfClass:[NSString class]]) continue;
                NSMutableOrderedSet *suites = [NSMutableOrderedSet orderedSet];
                for (NSString *testedCommand in tested) {
                    // the picker's command, or a fuller one it starts ("flashlight" for "flashlight on")
                    if ([testedCommand isEqualToString:command] || [testedCommand hasPrefix:[command stringByAppendingString:@" "]]) [suites addObjectsFromArray:tested[testedCommand]];
                }
                addRow(section, item[@"name"], suites.array);
            }
        }];
    } else {
        tested = self.coverage[@"conditions"];
        for (NSDictionary *definition in self.conditionDefinitions) {
            NSString *key = definition[@"key"];
            if (![key isKindOfClass:[NSString class]]) continue;
            addRow(definition[@"section"] ?: @"Conditions", definition[@"title"] ?: key, tested[key] ?: @[]);
        }
    }

    for (NSString *section in order) {
        NSArray *rows = bySection[section];
        for (NSDictionary *row in rows) { total++; if ([row[@"tested"] boolValue]) testedCount++; }
        // Not tested first: they're what this page is for
        NSArray *sorted = [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [@([a[@"tested"] boolValue]) compare:@([b[@"tested"] boolValue])];
        }];
        if (self.onlyUntested) sorted = [sorted filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"tested == NO"]];
        if (sorted.count) [sections addObject:@{ @"title": section, @"rows": sorted }];
    }
    self.sections = sections;
    self.testedCount = testedCount;
    self.totalCount = total;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count + 1; // the summary first
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : [self.sections[section - 1][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? nil : self.sections[section - 1][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 0) return nil;
    if (self.errorText) return self.errorText;
    if (!self.coverage) return @"Asking the tweak what its suites test…";
    NSString *what = @[@"triggers in the New Trigger menu", @"actions in the action picker", @"If conditions"][self.kind];
    return [NSString stringWithFormat:@"Each of the %@, and the suites that test it on this phone. Some need a person or a device the suites can't stand in for (the Apple Watch, CarPlay).", what];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:indexPath.section == 0 ? UITableViewCellStyleValue1 : UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.textLabel.numberOfLines = 0;
    if (indexPath.section == 0) {
        cell.textLabel.text = @"Tested";
        cell.detailTextLabel.text = self.coverage ? [NSString stringWithFormat:@"%lu of %lu", (unsigned long)self.testedCount, (unsigned long)self.totalCount] : @"…";
        return cell;
    }
    NSDictionary *row = self.sections[indexPath.section - 1][@"rows"][indexPath.row];
    BOOL isTested = [row[@"tested"] boolValue];
    cell.textLabel.text = row[@"title"];
    cell.detailTextLabel.text = row[@"detail"];
    cell.imageView.image = [UIImage systemImageNamed:isTested ? @"checkmark.circle.fill" : @"circle.dashed"] ?: [UIImage systemImageNamed:isTested ? @"checkmark.circle.fill" : @"circle"];
    cell.imageView.tintColor = isTested ? [UIColor systemGreenColor] : [UIColor tertiaryLabelColor];
    return cell;
}

@end
