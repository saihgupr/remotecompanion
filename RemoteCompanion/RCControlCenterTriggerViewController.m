#import "RCControlCenterTriggerViewController.h"
#import "RCSymbolPickerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"

const NSInteger RCControlCenterButtonSlots = 4;
NSString *const RCControlCenterButtonKeyPrefix = @"trigger_cc_button_";
static NSString *const kRCDefaultButtonIcon = @"bolt.fill";

@interface RCControlCenterTriggerViewController ()
@property (nonatomic, copy) NSString *triggerKey; // nil when adding
@property (nonatomic, assign) NSInteger slot;
@property (nonatomic, copy) NSString *buttonName;
@property (nonatomic, copy) NSString *iconName;
@end

@implementation RCControlCenterTriggerViewController

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _triggerKey = [triggerKey copy];
        _iconName = kRCDefaultButtonIcon;
        _buttonName = @"";
        if (triggerKey) {
            NSDictionary *data = [[RCConfigManager sharedManager] triggerDataForKey:triggerKey];
            if ([data[@"icon"] length]) _iconName = data[@"icon"];
            _buttonName = data[@"name"] ?: @"";
            _slot = [[triggerKey substringFromIndex:MIN(triggerKey.length, RCControlCenterButtonKeyPrefix.length)] integerValue];
        } else {
            _slot = [self firstFreeSlot];
        }
    }
    return self;
}

- (instancetype)init {
    return [self initWithTriggerKey:nil];
}

#pragma mark - Slots

- (NSString *)keyForSlot:(NSInteger)slot {
    return [NSString stringWithFormat:@"%@%ld", RCControlCenterButtonKeyPrefix, (long)slot];
}

- (BOOL)slotIsFree:(NSInteger)slot {
    return [self keyForSlot:slot].length && ![[RCConfigManager sharedManager] triggerDataForKey:[self keyForSlot:slot]];
}

// 0 when all are taken
- (NSInteger)firstFreeSlot {
    for (NSInteger slot = 1; slot <= RCControlCenterButtonSlots; slot++) {
        if ([self slotIsFree:slot]) return slot;
    }
    return 0;
}

#pragma mark - View

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Control Center Button";
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
    return section == 0 ? @"Button" : @"Control Center";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Tapping the button in Control Center runs this trigger's actions.";
    if (![RCConfigManager controlCenterSupportInstalled]) return @"CCSupport isn't installed, and it's what puts the button in Control Center. Install it from Havoc or your package manager, then add the button in Settings > Control Center.";
    return @"Add the button in Settings > Control Center, under the name RemoteCompanion Button, with the number above.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (indexPath.section == 1) {
        cell.textLabel.text = @"Button Number";
        cell.detailTextLabel.text = self.slot ? [NSString stringWithFormat:@"%ld", (long)self.slot] : @"None free";
        // A trigger keeps its number; a new one picks from those left
        cell.accessoryType = self.triggerKey ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = self.triggerKey ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (indexPath.row == 0) {
        cell.textLabel.text = @"Name";
        cell.detailTextLabel.text = self.buttonName.length ? self.buttonName : @"Button";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    cell.textLabel.text = @"Icon";
    cell.imageView.image = [UIImage systemImageNamed:self.iconName] ?: [UIImage systemImageNamed:kRCDefaultButtonIcon];
    cell.imageView.tintColor = [UIColor systemBlueColor];
    cell.detailTextLabel.text = self.iconName;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (!self.triggerKey) [self chooseSlot];
    } else if (indexPath.row == 0) {
        [self editName];
    } else {
        [self chooseIcon];
    }
}

- (void)editName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Name" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = self.buttonName;
        field.placeholder = @"Button";
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.buttonName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseIcon {
    RCSymbolPickerViewController *picker = [[RCSymbolPickerViewController alloc] initWithSelectedSymbol:self.iconName allowsNone:NO];
    __weak typeof(self) weakSelf = self;
    picker.onPick = ^(NSString *name) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.iconName = name.length ? name : kRCDefaultButtonIcon;
        [strongSelf.tableView reloadData];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)chooseSlot {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Button Number" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger slot = 1; slot <= RCControlCenterButtonSlots; slot++) {
        if (![self slotIsFree:slot]) continue;
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%ld", (long)slot] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.slot = slot;
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Save

- (void)save {
    RCConfigManager *config = [RCConfigManager sharedManager];
    if (!self.slot) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Buttons Left"
                                                                       message:[NSString stringWithFormat:@"All %ld Control Center buttons are in use. Delete one to add another.", (long)RCControlCenterButtonSlots]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSString *key = self.triggerKey ?: [self keyForSlot:self.slot];
    NSString *name = self.buttonName.length ? self.buttonName : [NSString stringWithFormat:@"Control Center Button %ld", (long)self.slot];

    if (self.triggerKey) {
        NSMutableDictionary *data = [[config triggerDataForKey:key] mutableCopy] ?: [NSMutableDictionary dictionary];
        data[@"name"] = name;
        data[@"icon"] = self.iconName;
        if (!data[@"actions"]) data[@"actions"] = @[];
        if (!data[@"enabled"]) data[@"enabled"] = @YES;
        [config updateTrigger:key withData:data];
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    [config updateTrigger:key withData:@{ @"name": name, @"icon": self.iconName, @"enabled": @YES, @"actions": @[] }];
    RCActionsViewController *vc = [[RCActionsViewController alloc] initWithTriggerKey:key];
    NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
    [vcs removeLastObject];
    [vcs addObject:vc];
    [self.navigationController setViewControllers:vcs animated:YES];
}

@end
