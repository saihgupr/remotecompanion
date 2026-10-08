#import "RCConditionPickerViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

// Day of the Week: stored as a list of day codes ("MON,WED,FRI"), Monday first
static NSArray<NSString *> *RCDayCodes(void) { return @[@"MON", @"TUE", @"WED", @"THU", @"FRI", @"SAT", @"SUN"]; }
static NSArray<NSString *> *RCDayNames(void) { return @[@"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday", @"Sunday"]; }

@interface RCConditionPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *expandedKey;          // the condition showing its options
@property (nonatomic, copy) NSString *existingKey;          // the block being edited
@property (nonatomic, copy) NSString *existingValue;
@property (nonatomic, copy) NSString *existingTitle;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *tickedDays;
@property (nonatomic, strong) NSArray<NSString *> *bluetoothDevices; // nil until loaded
@property (nonatomic, assign) BOOL loadingBluetooth;
@property (nonatomic, strong) NSArray<NSString *> *focusModes; // nil until loaded
@property (nonatomic, assign) BOOL loadingFocus;
@end

@implementation RCConditionPickerViewController

- (instancetype)initWithConditions:(NSArray<NSDictionary *> *)conditions title:(NSString *)title existing:(NSDictionary *)existing {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = title;
        _existingKey = [existing[@"conditionKey"] isKindOfClass:[NSString class]] ? existing[@"conditionKey"] : nil;
        _existingValue = [existing[@"expectedValue"] isKindOfClass:[NSString class]] ? [existing[@"expectedValue"] uppercaseString] : nil;
        _existingTitle = [existing[@"expectedTitle"] isKindOfClass:[NSString class]] ? existing[@"expectedTitle"] : _existingValue;
        _expandedKey = _existingKey;
        _tickedDays = [NSMutableOrderedSet orderedSet];
        if ([_existingKey isEqualToString:@"day_of_week"]) [self tickDaysFromValue:_existingValue];

        // Conditions defined without an icon / section (e.g. Auto-Lock, from its own PR)
        NSDictionary *fallback = @{ @"autolock": @{ @"icon": @"timer", @"section": @"Device" } };
        // Group by each definition's "section", in this order; anything else goes last
        NSMutableArray *titles = [@[@"Time", @"Device", @"Power", @"Sound", @"Connectivity"] mutableCopy];
        NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
        for (NSDictionary *definition in conditions) {
            NSMutableDictionary *condition = [definition mutableCopy];
            NSDictionary *f = fallback[definition[@"key"]];
            if (!condition[@"icon"] && f[@"icon"]) condition[@"icon"] = f[@"icon"];
            if (!condition[@"section"] && f[@"section"]) condition[@"section"] = f[@"section"];
            NSString *section = condition[@"section"] ?: @"Other";
            if (![titles containsObject:section]) [titles addObject:section];
            if (!groups[section]) groups[section] = [NSMutableArray array];
            [groups[section] addObject:condition];
        }
        NSMutableArray *sectionTitles = [NSMutableArray array];
        NSMutableArray *sections = [NSMutableArray array];
        for (NSString *section in titles) {
            if (groups[section].count) {
                [sectionTitles addObject:section];
                [sections addObject:groups[section]];
            }
        }
        _sectionTitles = sectionTitles;
        _sections = sections;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = 52;

    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Conditions";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([self.expandedKey isEqualToString:@"bt_device"]) [self loadBluetoothDevices];
    if ([self.expandedKey isEqualToString:@"focus"]) [self loadFocusModes];
    // Editing: bring the expanded condition into view
    NSIndexPath *path = [self indexPathOfConditionKey:self.expandedKey];
    if (path) [self.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
}

#pragma mark - Days

- (void)tickDaysFromValue:(NSString *)value {
    [self.tickedDays removeAllObjects];
    if ([value isEqualToString:@"WEEKDAYS"]) value = @"MON,TUE,WED,THU,FRI";
    else if ([value isEqualToString:@"WEEKENDS"]) value = @"SAT,SUN";
    for (NSString *code in RCDayCodes()) {
        if ([[value componentsSeparatedByString:@","] containsObject:code]) [self.tickedDays addObject:code];
    }
}

// The ticked days as a value + the label iOS would give them
- (NSDictionary *)daysValue {
    NSMutableArray *codes = [NSMutableArray array];
    NSMutableArray *shortNames = [NSMutableArray array];
    for (NSUInteger i = 0; i < 7; i++) {
        if ([self.tickedDays containsObject:RCDayCodes()[i]]) {
            [codes addObject:RCDayCodes()[i]];
            [shortNames addObject:[RCDayNames()[i] substringToIndex:3]];
        }
    }
    NSString *joined = [codes componentsJoinedByString:@","];
    NSString *title = [shortNames componentsJoinedByString:@", "];
    if (codes.count == 7) title = @"Every Day";
    else if ([joined isEqualToString:@"MON,TUE,WED,THU,FRI"]) title = @"Weekdays";
    else if ([joined isEqualToString:@"SAT,SUN"]) title = @"Weekends";
    return @{ @"value": joined, @"title": title };
}

#pragma mark - Rows

- (BOOL)isSearching {
    return self.searchController.isActive && self.searchController.searchBar.text.length > 0;
}

- (NSArray<NSDictionary *> *)conditionsInSection:(NSInteger)section {
    return [self isSearching] ? self.filtered : self.sections[section];
}

// What a condition expands to: its values, the days, or one row that opens its prompt
- (NSArray<NSDictionary *> *)optionRowsForCondition:(NSDictionary *)condition {
    NSString *key = condition[@"key"];
    NSMutableArray *rows = [NSMutableArray array];
    if ([key isEqualToString:@"day_of_week"]) {
        for (NSUInteger i = 0; i < 7; i++) {
            [rows addObject:@{ @"kind": @"day", @"code": RCDayCodes()[i], @"title": RCDayNames()[i] }];
        }
        [rows addObject:@{ @"kind": @"done", @"title": @"Done" }];
    } else if ([condition[@"input"] isEqualToString:@"threshold"]) {
        [rows addObject:@{ @"kind": @"threshold", @"direction": @"Above", @"title": @"Above…" }];
        [rows addObject:@{ @"kind": @"threshold", @"direction": @"Below", @"title": @"Below…" }];
    } else if ([key isEqualToString:@"bt_device"]) {
        // The paired devices (from the tweak), then a row to type any other name
        if (!self.bluetoothDevices) {
            [rows addObject:@{ @"kind": @"loading", @"title": @"Loading devices…" }];
        } else {
            for (NSString *name in self.bluetoothDevices) {
                [rows addObject:@{ @"kind": @"value", @"value": @{ @"value": name, @"title": name } }];
            }
        }
        [rows addObject:@{ @"kind": @"input", @"title": @"Other Name…" }];
    } else if ([key isEqualToString:@"focus"]) {
        // None on, any, then the Focus modes (from the tweak) by name
        [rows addObject:@{ @"kind": @"value", @"value": @{ @"value": @"OFF", @"title": @"Off" } }];
        [rows addObject:@{ @"kind": @"value", @"value": @{ @"value": @"ON", @"title": @"Any Focus" } }];
        if (!self.focusModes) {
            [rows addObject:@{ @"kind": @"loading", @"title": @"Loading Focus modes…" }];
        } else {
            for (NSString *name in self.focusModes) {
                [rows addObject:@{ @"kind": @"value", @"value": @{ @"value": name, @"title": name } }];
            }
        }
    } else if ([condition[@"values"] isKindOfClass:[NSArray class]] && [condition[@"values"] count]) {
        for (NSDictionary *value in condition[@"values"]) {
            [rows addObject:@{ @"kind": @"value", @"value": value }];
        }
    } else {
        NSString *prompt = @"Set…";
        if ([key isEqualToString:@"time_between"]) prompt = @"Set Time Range…";
        else if ([key isEqualToString:@"front_app"]) prompt = @"Choose App…";
        else if ([condition[@"input"] isEqualToString:@"text"]) prompt = @"Enter Name…";
        else if ([condition[@"input"] isEqualToString:@"threshold"]) prompt = @"Set Level…";
        [rows addObject:@{ @"kind": @"input", @"title": prompt }];
    }
    return rows;
}

// Every row of a section: each condition, followed by its options when expanded
- (NSArray<NSDictionary *> *)rowsInSection:(NSInteger)section {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *condition in [self conditionsInSection:section]) {
        [rows addObject:@{ @"kind": @"condition", @"condition": condition }];
        if ([condition[@"key"] isEqualToString:self.expandedKey]) {
            for (NSDictionary *option in [self optionRowsForCondition:condition]) {
                NSMutableDictionary *row = [option mutableCopy];
                row[@"condition"] = condition;
                [rows addObject:row];
            }
        }
    }
    return rows;
}

- (NSIndexPath *)indexPathOfConditionKey:(NSString *)key {
    if (!key) return nil;
    for (NSInteger section = 0; section < [self numberOfSectionsInTableView:self.tableView]; section++) {
        NSArray *rows = [self rowsInSection:section];
        for (NSUInteger i = 0; i < rows.count; i++) {
            if ([rows[i][@"kind"] isEqualToString:@"condition"] && [rows[i][@"condition"][@"key"] isEqualToString:key]) {
                return [NSIndexPath indexPathForRow:i inSection:section];
            }
        }
    }
    return nil;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    NSMutableArray *matches = [NSMutableArray array];
    if (text.length) {
        for (NSArray *section in self.sections) {
            for (NSDictionary *condition in section) {
                if ([condition[@"title"] rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) [matches addObject:condition];
            }
        }
    }
    self.filtered = matches;
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self isSearching] ? 1 : self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self rowsInSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self isSearching] ? @"Search Results" : self.sectionTitles[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSDictionary *row = [self rowsInSection:indexPath.section][indexPath.row];
    NSDictionary *condition = row[@"condition"];
    NSString *kind = row[@"kind"];
    BOOL isExistingCondition = [condition[@"key"] isEqualToString:self.existingKey];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.textLabel.textColor = [UIColor labelColor];

    if ([kind isEqualToString:@"condition"]) {
        cell.textLabel.text = condition[@"title"];
        cell.imageView.image = [UIImage systemImageNamed:condition[@"icon"] ?: @"questionmark.circle"];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
        BOOL expanded = [condition[@"key"] isEqualToString:self.expandedKey];
        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:expanded ? @"chevron.up" : @"chevron.down"]];
        chevron.tintColor = [UIColor tertiaryLabelColor];
        cell.accessoryView = chevron;
        return cell;
    }

    // Options sit indented under their condition
    cell.indentationLevel = 1;
    cell.indentationWidth = 44;
    if ([kind isEqualToString:@"value"]) {
        cell.textLabel.text = row[@"value"][@"title"];
        BOOL current = isExistingCondition && [[row[@"value"][@"value"] uppercaseString] isEqualToString:self.existingValue];
        cell.accessoryType = current ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else if ([kind isEqualToString:@"day"]) {
        cell.textLabel.text = row[@"title"];
        cell.accessoryType = [self.tickedDays containsObject:row[@"code"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else if ([kind isEqualToString:@"done"]) {
        BOOL enabled = self.tickedDays.count > 0;
        cell.textLabel.text = enabled ? [NSString stringWithFormat:@"Done — %@", [self daysValue][@"title"]] : @"Tick at least one day";
        cell.textLabel.textColor = enabled ? [UIColor systemBlueColor] : [UIColor tertiaryLabelColor];
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    } else if ([kind isEqualToString:@"threshold"]) {
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textColor = [UIColor systemBlueColor];
        if (isExistingCondition && [self.existingValue hasPrefix:[row[@"direction"] uppercaseString]]) {
            cell.textLabel.text = [NSString stringWithFormat:@"%@ (now: %@)", row[@"title"], self.existingTitle];
        }
    } else if ([kind isEqualToString:@"loading"]) {
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textColor = [UIColor tertiaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([kind isEqualToString:@"input"]) {
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textColor = [UIColor systemBlueColor];
        if (isExistingCondition && self.existingTitle.length) {
            cell.textLabel.text = [NSString stringWithFormat:@"%@ (now: %@)", row[@"title"], self.existingTitle];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = [self rowsInSection:indexPath.section][indexPath.row];
    NSDictionary *condition = row[@"condition"];
    NSString *kind = row[@"kind"];

    if ([kind isEqualToString:@"condition"]) {
        // Expand this one (closing any other), or collapse it
        BOOL collapsing = [condition[@"key"] isEqualToString:self.expandedKey];
        if (!collapsing && [condition[@"key"] isEqualToString:@"day_of_week"] && ![self.existingKey isEqualToString:@"day_of_week"]) {
            [self.tickedDays removeAllObjects];
        }
        [self setExpandedKey:collapsing ? nil : condition[@"key"] animated:YES];
        if (!collapsing && [condition[@"key"] isEqualToString:@"bt_device"]) [self loadBluetoothDevices];
        if (!collapsing && [condition[@"key"] isEqualToString:@"focus"]) [self loadFocusModes];
        if (!collapsing) {
            NSIndexPath *path = [self indexPathOfConditionKey:condition[@"key"]];
            NSInteger options = [self optionRowsForCondition:condition].count;
            NSIndexPath *last = path ? [NSIndexPath indexPathForRow:path.row + options inSection:path.section] : nil;
            if (last) [tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionNone animated:YES];
        }
    } else if ([kind isEqualToString:@"value"]) {
        [self finishWithValue:row[@"value"] condition:condition];
    } else if ([kind isEqualToString:@"day"]) {
        NSString *code = row[@"code"];
        if ([self.tickedDays containsObject:code]) [self.tickedDays removeObject:code];
        else [self.tickedDays addObject:code];
        // Refresh this day and the Done row's label
        NSArray *rows = [self rowsInSection:indexPath.section];
        NSUInteger doneIndex = [rows indexOfObjectPassingTest:^BOOL(NSDictionary *r, NSUInteger idx, BOOL *stop) { return [r[@"kind"] isEqualToString:@"done"]; }];
        NSMutableArray *paths = [NSMutableArray arrayWithObject:indexPath];
        if (doneIndex != NSNotFound) [paths addObject:[NSIndexPath indexPathForRow:doneIndex inSection:indexPath.section]];
        [tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
    } else if ([kind isEqualToString:@"done"]) {
        if (self.tickedDays.count == 0) return;
        [self finishWithValue:[self daysValue] condition:condition];
    } else if ([kind isEqualToString:@"threshold"]) {
        [self promptThresholdForCondition:condition direction:row[@"direction"]];
    } else if ([kind isEqualToString:@"input"]) {
        void (^onInput)(NSDictionary *) = self.onInputRequested;
        if ([condition[@"key"] isEqualToString:@"front_app"]) {
            // The app list opens on top of this screen
            if (self.searchController.isActive) self.searchController.active = NO;
            if (onInput) onInput(condition);
        } else {
            // The other prompts are alerts on the editor, so show them once we're gone
            [self popThen:^{ if (onInput) onInput(condition); }];
        }
    }
}

// Switches which condition is open, inserting and deleting only the option rows so the
// rest of the list slides rather than reloading
- (void)setExpandedKey:(NSString *)key animated:(BOOL)animated {
    NSInteger sectionCount = [self numberOfSectionsInTableView:self.tableView];
    NSMutableArray *before = [NSMutableArray array];
    for (NSInteger section = 0; section < sectionCount; section++) [before addObject:[self rowsInSection:section]];
    NSString *previousKey = self.expandedKey;
    self.expandedKey = key;
    if (!animated) { [self.tableView reloadData]; return; }

    NSMutableArray *deletes = [NSMutableArray array];
    NSMutableArray *inserts = [NSMutableArray array];
    for (NSInteger section = 0; section < sectionCount; section++) {
        NSArray *old = before[section];
        NSArray *now = [self rowsInSection:section];
        for (NSUInteger i = 0; i < old.count; i++) {
            if (![old[i][@"kind"] isEqualToString:@"condition"]) [deletes addObject:[NSIndexPath indexPathForRow:i inSection:section]];
        }
        for (NSUInteger i = 0; i < now.count; i++) {
            if (![now[i][@"kind"] isEqualToString:@"condition"]) [inserts addObject:[NSIndexPath indexPathForRow:i inSection:section]];
        }
    }
    [self.tableView performBatchUpdates:^{
        [self.tableView deleteRowsAtIndexPaths:deletes withRowAnimation:UITableViewRowAnimationTop];
        [self.tableView insertRowsAtIndexPaths:inserts withRowAnimation:UITableViewRowAnimationTop];
    } completion:nil];

    // Flip the chevrons in place
    for (NSString *changed in @[previousKey ?: @"", key ?: @""]) {
        NSIndexPath *path = [self indexPathOfConditionKey:changed];
        UITableViewCell *cell = path ? [self.tableView cellForRowAtIndexPath:path] : nil;
        if ([cell.accessoryView isKindOfClass:[UIImageView class]]) {
            ((UIImageView *)cell.accessoryView).image = [UIImage systemImageNamed:[changed isEqualToString:self.expandedKey] ? @"chevron.up" : @"chevron.down"];
        }
    }
}

- (void)loadBluetoothDevices {
    if (self.bluetoothDevices || self.loadingBluetooth) return;
    self.loadingBluetooth = YES;
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"bluetooth list" completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            NSMutableArray *names = [NSMutableArray array];
            if (output && ![output hasPrefix:@"No paired"] && ![output containsString:@"Error:"]) {
                for (NSString *line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
                    NSString *name = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (name.length && ![names containsObject:name]) [names addObject:name];
                }
            }
            self.bluetoothDevices = names;
            self.loadingBluetooth = NO;
            if ([self.expandedKey isEqualToString:@"bt_device"]) [self.tableView reloadData];
        });
    }];
}

- (void)loadFocusModes {
    if (self.focusModes || self.loadingFocus) return;
    self.loadingFocus = YES;
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"focus list" completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            // One per line: the name, a tab, its SF Symbol
            NSMutableArray *names = [NSMutableArray array];
            for (NSString *line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                NSString *name = [parts.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (parts.count >= 2 && name.length && ![names containsObject:name]) [names addObject:name];
            }
            self.focusModes = names;
            self.loadingFocus = NO;
            if ([self.expandedKey isEqualToString:@"focus"]) [self.tableView reloadData];
        });
    }];
}

// Battery / Volume Level: just the number, for the direction picked in the list
- (void)promptThresholdForCondition:(NSDictionary *)condition direction:(NSString *)direction {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ %@", condition[@"title"], direction.lowercaseString]
                                                                   message:@"Percentage (0-100)"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = nil;
    if ([condition[@"key"] isEqualToString:self.existingKey] && [self.existingValue hasPrefix:direction.uppercaseString]) {
        current = [[self.existingValue substringFromIndex:direction.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"50";
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.text = current;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSInteger value = MAX(0, MIN(100, [alert.textFields[0].text integerValue]));
        [weakSelf finishWithValue:@{ @"value": [NSString stringWithFormat:@"%@ %ld", direction.uppercaseString, (long)value],
                                     @"title": [NSString stringWithFormat:@"%@ %ld%%", direction.lowercaseString, (long)value] }
                        condition:condition];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)finishWithValue:(NSDictionary *)value condition:(NSDictionary *)condition {
    void (^onValue)(NSDictionary *, NSDictionary *) = self.onValueSelected;
    [self popThen:^{ if (onValue) onValue(condition, value); }];
}

// Run the next step once we're off screen, so it presents from the If editor
- (void)popThen:(void (^)(void))next {
    if (self.searchController.isActive) self.searchController.active = NO;
    UINavigationController *nav = self.navigationController;
    [CATransaction begin];
    [CATransaction setCompletionBlock:next];
    [nav popViewControllerAnimated:YES];
    [CATransaction commit];
}

@end
