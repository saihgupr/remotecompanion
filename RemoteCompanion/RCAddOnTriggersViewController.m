#import "RCAddOnTriggersViewController.h"
#import "RCAddOnExpandCell.h"
#import "RCActionsViewController.h"
#import "RCConfigManager.h"
#import "RCAddOnCatalog.h"

@interface RCAddOnTriggersViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *triggers;
@property (nonatomic, copy) NSString *expandedKey;
@end

@implementation RCAddOnTriggersViewController

- (instancetype)initWithAddOn:(NSString *)identifier title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = title;
        for (NSDictionary *group in [RCAddOnCatalog addOnTriggerGroups]) {
            if ([group[@"id"] isEqualToString:identifier]) _triggers = group[@"triggers"];
        }
        if (!_triggers) _triggers = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = RCAddOnHeaderHeight;
    self.tableView.estimatedRowHeight = 0;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];   // marks what was added while the action list was open
}

- (NSSet<NSString *> *)configuredKeys {
    return [NSSet setWithArray:[[RCConfigManager sharedManager] allConfiguredTriggerKeys]];
}

// The choices of a trigger with states: Any State first, then each state (word = the trigger's key)
- (NSArray<NSDictionary *> *)choicesFor:(NSDictionary *)trigger {
    NSMutableArray *choices = [NSMutableArray arrayWithObject:@{ @"label": @"Any State", @"word": trigger[@"key"], @"name": trigger[@"name"] }];
    for (NSDictionary *state in trigger[@"states"]) [choices addObject:@{ @"label": state[@"label"], @"word": state[@"key"], @"name": state[@"name"] }];
    return choices;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.triggers.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *trigger = self.triggers[indexPath.row];
    BOOL expanded = [self.expandedKey isEqualToString:trigger[@"key"]];
    return RCAddOnHeaderHeight + (expanded ? [self choicesFor:trigger].count * RCAddOnChoiceHeight : 0);
}

- (void)configureCell:(RCAddOnExpandCell *)cell forTrigger:(NSDictionary *)trigger {
    NSSet *configured = [self configuredKeys];
    NSArray *choices = [self choicesFor:trigger];
    NSMutableSet *added = [NSMutableSet set];
    for (NSDictionary *choice in choices) if ([configured containsObject:choice[@"word"]]) [added addObject:choice[@"word"]];
    BOOL hasStates = [trigger[@"states"] count] > 0;
    cell.titleLabel.text = trigger[@"title"];
    cell.valueLabel.text = added.count ? @"Added" : @"";
    [cell setChoices:hasStates ? choices : @[] checkedWords:added];
    [cell setExpanded:hasStates && [self.expandedKey isEqualToString:trigger[@"key"]]];
    cell.chevron.hidden = !hasStates;   // a trigger with no states opens at a tap
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *trigger = self.triggers[indexPath.row];
    RCAddOnExpandCell *cell = [[RCAddOnExpandCell alloc] init];
    __weak typeof(self) weakSelf = self;
    cell.onToggle = ^{ [weakSelf toggle:trigger]; };
    cell.onChoose = ^(NSString *key) { [weakSelf openTrigger:key name:[weakSelf nameForKey:key in:trigger]]; };
    [self configureCell:cell forTrigger:trigger];
    return cell;
}

- (NSString *)nameForKey:(NSString *)key in:(NSDictionary *)trigger {
    for (NSDictionary *choice in [self choicesFor:trigger]) if ([choice[@"word"] isEqualToString:key]) return choice[@"name"];
    return trigger[@"name"];
}

- (void)toggle:(NSDictionary *)trigger {
    if (![trigger[@"states"] count]) {
        [self openTrigger:trigger[@"key"] name:trigger[@"name"]];
        return;
    }
    self.expandedKey = [self.expandedKey isEqualToString:trigger[@"key"]] ? nil : trigger[@"key"];
    [self.tableView performBatchUpdates:^{
        for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
            RCAddOnExpandCell *cell = (RCAddOnExpandCell *)[self.tableView cellForRowAtIndexPath:path];
            if ([cell isKindOfClass:[RCAddOnExpandCell class]]) [self configureCell:cell forTrigger:self.triggers[path.row]];
        }
    } completion:nil];
}

// Adds the trigger if it isn't there yet and opens its action list on top of this screen
- (void)openTrigger:(NSString *)key name:(NSString *)name {
    if (![[self configuredKeys] containsObject:key]) {
        [[RCConfigManager sharedManager] updateTrigger:key withData:@{ @"name": name, @"enabled": @YES, @"actions": @[] }];
    }
    self.expandedKey = nil;
    [self.navigationController pushViewController:[[RCActionsViewController alloc] initWithTriggerKey:key] animated:YES];
}

@end
