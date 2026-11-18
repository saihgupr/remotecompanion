#import "RCControlCenterTriggerViewController.h"
#import "RCSymbolPickerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import <objc/message.h>

NSString *const RCControlCenterButtonKeyPrefix = @"trigger_cc_button_";
static NSString *const kRCDefaultButtonIcon = @"bolt.fill";

@interface RCControlCenterTriggerViewController ()
@property (nonatomic, copy) NSString *triggerKey; // nil when adding
@property (nonatomic, assign) NSInteger nextNumber;
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
            RCConfigManager *config = [RCConfigManager sharedManager];
            NSDictionary *data = [config triggerDataForKey:triggerKey];
            if ([data[@"icon"] length]) _iconName = data[@"icon"];
            _buttonName = [config customNameForTrigger:triggerKey] ?: @"";
        } else {
            _nextNumber = [self nextButtonNumber];
        }
    }
    return self;
}

- (instancetype)init {
    return [self initWithTriggerKey:nil];
}

#pragma mark - Button Keys

- (NSString *)keyForNumber:(NSInteger)number {
    return [NSString stringWithFormat:@"%@%ld", RCControlCenterButtonKeyPrefix, (long)number];
}

- (NSInteger)nextButtonNumber {
    NSInteger maxNum = 0;
    RCConfigManager *config = [RCConfigManager sharedManager];
    for (NSString *key in [config allConfiguredTriggerKeys]) {
        if (![key hasPrefix:RCControlCenterButtonKeyPrefix]) continue;
        NSInteger n = [[key substringFromIndex:RCControlCenterButtonKeyPrefix.length] integerValue];
        if (n > maxNum) maxNum = n;
    }
    NSInteger candidate = maxNum + 1;
    while ([config triggerDataForKey:[self keyForNumber:candidate]]) {
        candidate++;
    }
    return candidate;
}

- (NSString *)defaultPlaceholderName {
    if (self.triggerKey) {
        return [[RCConfigManager sharedManager] defaultNameForTrigger:self.triggerKey];
    }
    return [NSString stringWithFormat:@"Control Center Button %ld", (long)self.nextNumber];
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
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Button";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (![RCConfigManager controlCenterSupportInstalled]) {
        return @"CCSupport isn't installed, and it's what puts the button in Control Center. Install it from Havoc or your package manager, then add the button in Settings > Control Center.";
    }
    return @"Tapping the button in Control Center runs this trigger's actions. Once saved, add it under this name in Settings > Control Center.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (indexPath.row == 0) {
        cell.textLabel.text = @"Name";
        cell.detailTextLabel.text = self.buttonName.length ? self.buttonName : [self defaultPlaceholderName];
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
    if (indexPath.row == 0) {
        [self editName];
    } else {
        [self chooseIcon];
    }
}

- (void)editName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Name" message:nil preferredStyle:UIAlertControllerStyleAlert];
    NSString *placeholder = [self defaultPlaceholderName];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = self.buttonName;
        field.placeholder = placeholder;
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

#pragma mark - Save

- (void)save {
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSString *key = self.triggerKey ?: [self keyForNumber:[self nextButtonNumber]];
    NSString *trimmed = [self.buttonName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *defaultName = [NSString stringWithFormat:@"Control Center Button %@", [key substringFromIndex:RCControlCenterButtonKeyPrefix.length]];
    NSString *name = trimmed.length ? trimmed : defaultName;

    if (self.triggerKey) {
        NSMutableDictionary *data = [[config triggerDataForKey:key] mutableCopy] ?: [NSMutableDictionary dictionary];
        data[@"name"] = name;
        if (trimmed.length) {
            data[@"customName"] = trimmed;
        } else {
            [data removeObjectForKey:@"customName"];
        }
        data[@"icon"] = self.iconName;
        if (!data[@"actions"]) data[@"actions"] = @[];
        if (!data[@"enabled"]) data[@"enabled"] = @YES;
        [config updateTrigger:key withData:data];
        NSArray *vcs = self.navigationController.viewControllers;
        NSUInteger index = [vcs indexOfObject:self];
        if (index != NSNotFound && index > 0 && [vcs[index - 1] isKindOfClass:[RCActionsViewController class]]) {
            RCActionsViewController *actionsVC = vcs[index - 1];
            actionsVC.title = name;
            SEL wrapSel = NSSelectorFromString(@"updateWrappedTitle");
            if ([actionsVC respondsToSelector:wrapSel]) {
                ((void (*)(id, SEL))objc_msgSend)(actionsVC, wrapSel);
            }
        }
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    NSMutableDictionary *data = [@{
        @"name": name,
        @"icon": self.iconName,
        @"enabled": @YES,
        @"actions": @[]
    } mutableCopy];
    if (trimmed.length) data[@"customName"] = trimmed;
    [config updateTrigger:key withData:data];
    RCActionsViewController *vc = [[RCActionsViewController alloc] initWithTriggerKey:key];
    NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
    [vcs removeLastObject];
    [vcs addObject:vc];
    [self.navigationController setViewControllers:vcs animated:YES];
}

@end
