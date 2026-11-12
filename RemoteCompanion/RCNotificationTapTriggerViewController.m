#import "RCNotificationTapTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCTriggerIcons.h"

@interface RCNotificationTapTriggerViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;
@property (nonatomic, copy) NSString *tapTriggerKey; // relinking this trigger, or nil for a new one
@end

@implementation RCNotificationTapTriggerViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (instancetype)initWithTapTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) _tapTriggerKey = [triggerKey copy];
    return self;
}

- (BOOL)relinkingButton {
    return [self.tapTriggerKey hasPrefix:@"notifbtn_"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = !self.tapTriggerKey ? @"Notification" : ([self relinkingButton] ? @"Button" : @"Notification");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSArray *all = [[RCConfigManager sharedManager] notificationActionEntries];
    if (self.tapTriggerKey) {
        NSString *kind = [self relinkingButton] ? @"button" : @"tap";
        all = [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind == %@", kind]];
    }
    self.entries = all;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.entries.count == 0) return [self relinkingButton] ? @"No notification buttons yet." : @"No Notification actions yet. Add one to a trigger first.";
    if (self.tapTriggerKey) return [self relinkingButton] ? @"The button that runs this trigger." : @"The notification whose tap runs this trigger.";
    return @"Its actions run when the notification is tapped, or its button pressed, with RC closed.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RCNotificationTapCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RCNotificationTapCell"];
    NSDictionary *entry = self.entries[indexPath.row];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    BOOL isButton = [entry[@"kind"] isEqualToString:@"button"];
    NSString *name = [entry[@"title"] length] ? entry[@"title"] : @"Notification";
    cell.textLabel.text = isButton ? [NSString stringWithFormat:@"%@ › %@", name, entry[@"buttonTitle"]] : [@"Tap: " stringByAppendingString:name];
    NSString *detail = [@"In " stringByAppendingString:[cm displayNameForTrigger:entry[@"trigger"]]];
    NSString *key = entry[@"key"];
    BOOL linkedHere = key && [key isEqualToString:self.tapTriggerKey];
    if (!linkedHere && key && [cm triggerDataForKey:key]) {
        detail = [detail stringByAppendingString:self.tapTriggerKey ? @" · Has a trigger" : @" · Added"];
    }
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    // The trigger list's icons: a finger pressing a bell for a tap, a bell for a button
    cell.imageView.image = isButton ? [UIImage systemImageNamed:@"bell.fill"] : RCTriggerIconImage(@"notiftap_", 22);
    cell.imageView.tintColor = [UIColor secondaryLabelColor];
    cell.accessoryType = self.tapTriggerKey ? (linkedHere ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone) : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *entry = self.entries[indexPath.row];
    if (self.tapTriggerKey) {
        [self linkEntry:entry];
        return;
    }
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSString *key = [cm triggerKeyForNotificationEntry:entry];
    if (!key) return;
    NSMutableDictionary *data = [[cm triggerDataForKey:key] mutableCopy];
    if (!data) data = [@{ @"actions": @[] } mutableCopy];
    data[@"enabled"] = @YES;
    [cm updateTrigger:key withData:data];
    // The trigger's actions take this screen's place, so Back goes to the Triggers list
    RCActionsViewController *actions = [[RCActionsViewController alloc] initWithTriggerKey:key];
    NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
    [vcs removeLastObject];
    [vcs addObject:actions];
    [self.navigationController setViewControllers:vcs animated:YES];
}

// Relinking: the chosen notification (or button) runs this trigger from now on. One that has a
// trigger of its own asks first, as that trigger stops running.
- (void)linkEntry:(NSDictionary *)entry {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSString *current = entry[@"key"];
    if ([current isEqualToString:self.tapTriggerKey]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    __weak typeof(self) weakSelf = self;
    void (^link)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [cm linkNotificationEntry:entry toTriggerKey:strongSelf.tapTriggerKey];
        if (strongSelf.onLinked) strongSelf.onLinked();
        [strongSelf.navigationController popViewControllerAnimated:YES];
    };
    if (!current || ![cm triggerDataForKey:current]) {
        link();
        return;
    }
    BOOL isButton = [self relinkingButton];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isButton ? @"Move Button" : @"Move Notification"
                                                                   message:[NSString stringWithFormat:@"%@ runs “%@” now. It will run this trigger instead.", isButton ? @"That button" : @"Tapping it", [cm displayNameForTrigger:current]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Move" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { link(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
