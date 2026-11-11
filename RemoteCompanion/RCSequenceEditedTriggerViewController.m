#import "RCSequenceEditedTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"

static NSString *const kSequenceEditedTriggerKey = @"trigger_sequence_edited";

@interface RCSequenceEditedTriggerViewController ()
@property (nonatomic, copy) NSString *triggerKey;
@property (nonatomic, assign) NSTimeInterval debounce; // seconds; 0 is off
@end

@implementation RCSequenceEditedTriggerViewController

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _triggerKey = [triggerKey copy];
        _debounce = 0;
        if (triggerKey) {
            id stored = [[RCConfigManager sharedManager] triggerDataForKey:triggerKey][@"debounce"];
            if ([stored isKindOfClass:[NSNumber class]]) _debounce = [stored doubleValue];
        }
    }
    return self;
}

- (instancetype)init {
    return [self initWithTriggerKey:nil];
}

- (NSArray<NSNumber *> *)debounceValues {
    return @[ @0, @5, @10, @15, @30, @60, @120, @300 ];
}

- (NSString *)labelForDebounce:(NSTimeInterval)seconds {
    if (seconds <= 0) return @"Off";
    if (seconds < 60) return [NSString stringWithFormat:@"%g Seconds", seconds];
    return [NSString stringWithFormat:@"%g Minute%@", seconds / 60, seconds >= 120 ? @"s" : @""];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Action Sequence Edited";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.triggerKey ? @"Save" : @"Add"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(save)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTweaks) name:@"RCConfigTweaksChangedNotification" object:nil];
    [self applyTweaks];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    [self.tableView reloadData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) [self applyTweaks];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.debounceValues.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Debounce";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Runs when you add, remove, reorder or change an action in any trigger's sequence. A debounce waits until the edits stop, so a run of changes runs the sequence once. Changes to this trigger's own actions are ignored.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSTimeInterval value = [self.debounceValues[indexPath.row] doubleValue];
    cell.textLabel.text = [self labelForDebounce:value];
    cell.imageView.image = [UIImage systemImageNamed:value > 0 ? @"timer" : @"bolt.fill"];
    cell.imageView.tintColor = value > 0 ? [UIColor systemOrangeColor] : [UIColor systemGrayColor];
    cell.accessoryType = fabs(value - self.debounce) < 0.5 ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    self.debounce = [self.debounceValues[indexPath.row] doubleValue];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self.tableView reloadData];
}

#pragma mark - Save

- (void)save {
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSMutableDictionary *data = [[config triggerDataForKey:self.triggerKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    data[@"name"] = [config defaultNameForTrigger:kSequenceEditedTriggerKey];
    data[@"added"] = @YES;
    if (!data[@"actions"]) data[@"actions"] = @[];
    if (self.debounce > 0) data[@"debounce"] = @(self.debounce);
    else [data removeObjectForKey:@"debounce"];

    if (self.triggerKey) {
        [config updateTrigger:kSequenceEditedTriggerKey withData:data];
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    if (!data[@"enabled"]) data[@"enabled"] = @NO;
    [config updateTrigger:kSequenceEditedTriggerKey withData:data];
    RCActionsViewController *vc = [[RCActionsViewController alloc] initWithTriggerKey:kSequenceEditedTriggerKey];
    NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
    [vcs removeLastObject];
    [vcs addObject:vc];
    [self.navigationController setViewControllers:vcs animated:YES];
}

@end
