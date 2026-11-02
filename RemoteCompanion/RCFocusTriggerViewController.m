#import "RCFocusTriggerViewController.h"
#import "RCFocusPickerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"

static NSString *const kRCFocusOnKey = @"trigger_device_focus_on";
static NSString *const kRCFocusOffKey = @"trigger_device_focus_off";

@interface RCFocusTriggerViewController ()
@property (nonatomic, copy) NSString *triggerKey;
@property (nonatomic, assign) BOOL turnsOff;
@property (nonatomic, copy) NSString *focusName; // empty: any Focus
@end

@implementation RCFocusTriggerViewController

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _triggerKey = [triggerKey copy];
        _focusName = @"";
        if ([triggerKey hasPrefix:kRCFocusOffKey]) {
            _turnsOff = YES;
            if (triggerKey.length > kRCFocusOffKey.length + 1) _focusName = [triggerKey substringFromIndex:kRCFocusOffKey.length + 1];
        } else if ([triggerKey hasPrefix:kRCFocusOnKey]) {
            if (triggerKey.length > kRCFocusOnKey.length + 1) _focusName = [triggerKey substringFromIndex:kRCFocusOnKey.length + 1];
        }
    }
    return self;
}

- (instancetype)init {
    return [self initWithTriggerKey:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Focus";
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
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Trigger Event" : @"Focus";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 1 || self.focusName.length) return nil;
    return self.turnsOff ? @"Runs when no Focus is left on." : @"Runs when any Focus turns on, including a switch from another.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (indexPath.section == 0) {
        BOOL off = indexPath.row == 1;
        cell.textLabel.text = off ? @"Turns Off" : @"Turns On";
        cell.imageView.image = [UIImage systemImageNamed:off ? @"moon" : @"moon.fill"];
        cell.imageView.tintColor = [UIColor systemIndigoColor];
        cell.accessoryType = off == self.turnsOff ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }
    cell.textLabel.text = @"Focus";
    cell.detailTextLabel.text = self.focusName.length ? self.focusName : @"Any";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        self.turnsOff = indexPath.row == 1;
        [UIView performWithoutAnimation:^{
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationNone];
        }];
        return;
    }
    RCFocusPickerViewController *picker = [[RCFocusPickerViewController alloc] initWithTitle:@"Focus"
                                                                                  fixedRows:@[ @{ @"name": @"Any", @"value": @"", @"icon": @"moon.circle" } ]];
    picker.currentValue = self.focusName;
    __weak typeof(self) weakSelf = self;
    picker.onSelected = ^(NSDictionary *row) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.focusName = row[@"value"] ?: @"";
        [strongSelf.tableView reloadData];
        [strongSelf.navigationController popToViewController:strongSelf animated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

#pragma mark - Save

- (NSString *)keyForChoice {
    NSString *base = self.turnsOff ? kRCFocusOffKey : kRCFocusOnKey;
    return self.focusName.length ? [NSString stringWithFormat:@"%@_%@", base, self.focusName] : base;
}

- (NSString *)nameForChoice {
    return [NSString stringWithFormat:@"%@: %@", self.turnsOff ? @"Focus Off" : @"Focus On", self.focusName.length ? self.focusName : @"Any"];
}

- (void)save {
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSString *key = [self keyForChoice];
    NSString *name = [self nameForChoice];

    if (![key isEqualToString:self.triggerKey] && [config triggerDataForKey:key]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Trigger Exists"
                                                                       message:[NSString stringWithFormat:@"“%@” is already set up.", name]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    if (self.triggerKey) {
        NSMutableDictionary *data = [[config triggerDataForKey:self.triggerKey] mutableCopy] ?: [NSMutableDictionary dictionary];
        data[@"name"] = name;
        if (!data[@"actions"]) data[@"actions"] = @[];
        if (!data[@"enabled"]) data[@"enabled"] = @YES;
        [config updateTrigger:key withData:data];
        if (![key isEqualToString:self.triggerKey]) {
            [config removeTrigger:self.triggerKey];
            // The actions screen below moves to the new key
            NSArray *vcs = self.navigationController.viewControllers;
            NSUInteger index = [vcs indexOfObject:self];
            if (index != NSNotFound && index > 0 && [vcs[index - 1] isKindOfClass:[RCActionsViewController class]]) {
                RCActionsViewController *actionsVC = vcs[index - 1];
                [actionsVC setValue:key forKey:@"triggerKey"];
                actionsVC.title = name;
            }
        }
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    [config updateTrigger:key withData:@{ @"name": name, @"enabled": @YES, @"actions": @[] }];
    RCActionsViewController *vc = [[RCActionsViewController alloc] initWithTriggerKey:key];
    NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
    [vcs removeLastObject];
    [vcs addObject:vc];
    [self.navigationController setViewControllers:vcs animated:YES];
}

@end
