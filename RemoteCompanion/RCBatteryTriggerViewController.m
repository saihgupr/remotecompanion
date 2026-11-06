#import "RCBatteryTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"

@interface RCBatteryTriggerViewController ()
@property (nonatomic, copy) NSString *triggerKey;
@property (nonatomic, assign) BOOL rises;
@property (nonatomic, assign) NSInteger level;
@property (nonatomic, strong) UILabel *levelLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIStepper *stepper;
@end

@implementation RCBatteryTriggerViewController

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _triggerKey = [triggerKey copy];
        _level = 20;
        if ([triggerKey hasPrefix:@"trigger_device_battery_below_"] || [triggerKey hasPrefix:@"trigger_device_battery_above_"]) {
            _rises = [triggerKey hasPrefix:@"trigger_device_battery_above_"];
            NSInteger level = [[triggerKey substringFromIndex:29] integerValue];
            if (level >= 1 && level <= 100) _level = level;
        }
    }
    return self;
}

- (instancetype)init {
    return [self initWithTriggerKey:nil];
}

+ (NSString *)nameForRises:(BOOL)rises level:(NSInteger)level {
    return [NSString stringWithFormat:rises ? @"Battery Rises to %ld%%" : @"Battery Drops to %ld%%", (long)level];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Battery Level";
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
    return section == 0 ? @"Trigger Event" : @"Level";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 1) return nil;
    return self.rises ? @"Runs once each time the battery charges to this level."
                      : @"Runs once each time the battery drains to this level.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Event"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Event"];
        BOOL rises = indexPath.row == 1;
        cell.textLabel.text = rises ? @"Rises To" : @"Drops To";
        cell.imageView.image = [UIImage systemImageNamed:rises ? @"battery.100" : @"battery.25"];
        cell.imageView.tintColor = rises ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
        cell.accessoryType = rises == self.rises ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UILabel *label = [UILabel new];
    label.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentRight;
    UISlider *slider = [UISlider new];
    slider.minimumValue = 1;
    slider.maximumValue = 100;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    UIStepper *stepper = [UIStepper new];
    stepper.minimumValue = 1;
    stepper.maximumValue = 100;
    [stepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
    self.levelLabel = label;
    self.slider = slider;
    self.stepper = stepper;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[slider, label, stepper]];
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:row];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:margins.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
        [label.widthAnchor constraintEqualToConstant:52],
    ]];
    [stepper setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self showLevel];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) return;
    self.rises = indexPath.row == 1;
    // Both sections: the footer follows the event
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

#pragma mark - Level

- (void)showLevel {
    self.levelLabel.text = [NSString stringWithFormat:@"%ld%%", (long)self.level];
    self.slider.value = self.level;
    self.stepper.value = self.level;
}

- (void)sliderChanged:(UISlider *)slider {
    NSInteger level = (NSInteger)lroundf(slider.value);
    if (level == self.level) return;
    self.level = level;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    self.levelLabel.text = [NSString stringWithFormat:@"%ld%%", (long)level];
    self.stepper.value = level;
}

- (void)stepperChanged:(UIStepper *)stepper {
    self.level = (NSInteger)stepper.value;
    [self showLevel];
}

#pragma mark - Save

- (void)save {
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSString *key = [NSString stringWithFormat:@"%@%ld", self.rises ? @"trigger_device_battery_above_" : @"trigger_device_battery_below_", (long)self.level];
    NSString *name = [RCBatteryTriggerViewController nameForRises:self.rises level:self.level];

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
        if (![key isEqualToString:self.triggerKey]) {
            if (!data[@"actions"]) data[@"actions"] = @[];
            if (!data[@"enabled"]) data[@"enabled"] = @YES;
            [config updateTrigger:key withData:data];
            [config removeTrigger:self.triggerKey];
        } else {
            [config updateTrigger:key withData:data];
        }
        // The actions screen below moves to the new key
        NSArray *vcs = self.navigationController.viewControllers;
        NSUInteger index = [vcs indexOfObject:self];
        if (index != NSNotFound && index > 0 && [vcs[index - 1] isKindOfClass:[RCActionsViewController class]]) {
            RCActionsViewController *actionsVC = vcs[index - 1];
            if ([actionsVC respondsToSelector:@selector(setTriggerKey:)]) {
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
