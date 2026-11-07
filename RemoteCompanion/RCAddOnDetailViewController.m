#import "RCAddOnDetailViewController.h"
#import "RCAddOnCatalog.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import <notify.h>

@interface RCAddOnDetailViewController ()
@property (nonatomic, copy) NSString *addOnId;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSDictionary *addOn;
@property (nonatomic, assign) BOOL on;
@property (nonatomic, assign) BOOL switching;    // waiting for the tweak to turn it on or off
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;   // { title, footer, rows: [{ kind, ... }] }
@property (nonatomic, assign) int changeToken;
@property (nonatomic, copy) NSDictionary *settingValues;   // setting id -> value, from "addons settings <id>"
@end

static BOOL rcao_is_text(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value length];
}

@implementation RCAddOnDetailViewController

- (instancetype)initWithAddOnId:(NSString *)identifier {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _addOnId = [identifier copy];
        _changeToken = NOTIFY_TOKEN_INVALID;
    }
    return self;
}

- (void)dealloc {
    if (_changeToken != NOTIFY_TOKEN_INVALID) notify_cancel(_changeToken);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 10;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;
    self.tableView.backgroundColor = settingsBG;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    int token = NOTIFY_TOKEN_INVALID;
    __weak typeof(self) weakSelf = self;
    if (notify_register_dispatch([RCAddOnCatalog changedNotification], &token, dispatch_get_main_queue(), ^(int t) {
        [weakSelf readCatalog];
    }) == NOTIFY_STATUS_OK) self.changeToken = token;
    [self readCatalog];
}

#pragma mark - Contents

- (void)readCatalog {
    NSDictionary *addOn = [RCAddOnCatalog addOnWithId:self.addOnId];
    if (!addOn) {
        // Uninstalled (or its file broke) while this page was open
        if (self.addOn) [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    self.addOn = addOn;
    self.on = [RCAddOnCatalog isAddOnEnabled:self.addOnId];
    self.title = addOn[@"name"];

    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:@{ @"footer": @"When off, it adds nothing and its events stop.", @"rows": @[ @{ @"kind": @"enabled" } ] }];

    NSMutableArray *settingRows = [NSMutableArray array];
    for (NSDictionary *setting in [addOn[@"settings"] isKindOfClass:[NSArray class]] ? addOn[@"settings"] : @[]) {
        if ([setting isKindOfClass:[NSDictionary class]]) [settingRows addObject:@{ @"kind": @"setting", @"item": setting }];
    }
    if (settingRows.count) {
        [sections addObject:@{ @"title": @"Settings", @"rows": settingRows }];
        [self readSettings];
    }

    NSArray *actions = [addOn[@"actions"] isKindOfClass:[NSArray class]] ? addOn[@"actions"] : @[];
    NSMutableArray *actionRows = [NSMutableArray array], *bannerRows = [NSMutableArray array];
    for (NSDictionary *action in actions) {
        if (![action isKindOfClass:[NSDictionary class]]) continue;
        [actionRows addObject:@{ @"kind": @"action", @"item": action }];
        if ([action[@"banner"] isKindOfClass:[NSDictionary class]]) [bannerRows addObject:@{ @"kind": @"banner", @"item": action }];
    }
    if (actionRows.count) [sections addObject:@{ @"title": @"Actions", @"rows": actionRows }];

    NSMutableArray *triggerRows = [NSMutableArray array];
    for (NSDictionary *event in [addOn[@"events"] isKindOfClass:[NSArray class]] ? addOn[@"events"] : @[]) {
        if ([event isKindOfClass:[NSDictionary class]] && [event[@"trigger"] isKindOfClass:[NSDictionary class]]) {
            [triggerRows addObject:@{ @"kind": @"trigger", @"item": event[@"trigger"], @"event": event }];
        }
    }
    if (triggerRows.count) [sections addObject:@{ @"title": @"Triggers", @"rows": triggerRows }];

    NSMutableArray *conditionRows = [NSMutableArray array];
    for (NSDictionary *condition in [addOn[@"conditions"] isKindOfClass:[NSArray class]] ? addOn[@"conditions"] : @[]) {
        if ([condition isKindOfClass:[NSDictionary class]]) [conditionRows addObject:@{ @"kind": @"condition", @"item": condition }];
    }
    if (conditionRows.count) [sections addObject:@{ @"title": @"Conditions", @"rows": conditionRows }];

    if (bannerRows.count) [sections addObject:@{ @"title": @"Banners", @"footer": @"A banner shows after its action runs.", @"rows": bannerRows }];

    NSMutableArray *infoRows = [NSMutableArray array];
    [infoRows addObject:@{ @"kind": @"info", @"title": @"Command", @"value": addOn[@"id"] ?: @"" }];
    if ([addOn[@"_file"] isKindOfClass:[NSString class]]) [infoRows addObject:@{ @"kind": @"info", @"title": @"File", @"value": addOn[@"_file"] }];
    if ([addOn[@"_folder"] isKindOfClass:[NSString class]]) [infoRows addObject:@{ @"kind": @"info", @"title": @"Folder", @"value": addOn[@"_folder"] }];
    [sections addObject:@{ @"title": @"About", @"rows": infoRows }];

    self.sections = sections;
    [self.tableView reloadData];
}

#pragma mark - Settings

// The current values, from the tweak (it reads and writes the preferences, as the add-on's steps do)
- (void)readSettings {
    NSString *command = [NSString stringWithFormat:@"addons settings %@", self.addOnId];
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *values = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([values isKindOfClass:[NSDictionary class]]) self.settingValues = values;
            [self.tableView reloadData];
        });
    }];
}

- (void)setSetting:(NSDictionary *)setting to:(NSString *)text {
    NSString *command = [NSString stringWithFormat:@"addons set %@ %@ %@", self.addOnId, setting[@"id"], text ?: @""];
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || ![output isKindOfClass:[NSString class]] || [output hasPrefix:@"Error"]) {
                NSString *message = error.localizedDescription ?: [output hasPrefix:@"Error: "] ? [output substringFromIndex:7] : output ?: @"RemoteCompanion didn't answer.";
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't Change" message:message preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
            [self readSettings];
        });
    }];
}

// A number as written ("80", "0.5"), with its unit
- (NSString *)textForNumber:(id)value setting:(NSDictionary *)setting {
    NSString *number = [value isKindOfClass:[NSNumber class]] ? [NSNumberFormatter localizedStringFromNumber:value numberStyle:NSNumberFormatterDecimalStyle] : [value description];
    return rcao_is_text(setting[@"unit"]) ? [NSString stringWithFormat:@"%@ %@", number, setting[@"unit"]] : number;
}

// What a setting row shows under its title: its value (not for a switch), then its note
- (NSString *)detailForSetting:(NSDictionary *)setting {
    id value = self.settingValues[setting[@"id"]];
    NSString *shown = nil;
    NSString *type = setting[@"type"];
    if (!value) shown = [type isEqualToString:@"switch"] ? nil : @"…";
    else if ([type isEqualToString:@"number"]) shown = [self textForNumber:value setting:setting];
    else if ([type isEqualToString:@"choice"]) {
        for (NSDictionary *choice in setting[@"choices"]) if ([[choice[@"value"] description] isEqualToString:[value description]]) shown = choice[@"label"];
        shown = shown ?: [value description];
    } else if ([type isEqualToString:@"text"]) shown = [value description].length ? [value description] : @"None";
    NSString *note = rcao_is_text(setting[@"note"]) ? setting[@"note"] : nil;
    if (shown && note) return [NSString stringWithFormat:@"%@\n%@", shown, note];
    return shown ?: note;
}

- (void)settingSwitched:(UISwitch *)toggle {
    NSDictionary *setting = [self settingForControl:toggle];
    [self setSetting:setting to:toggle.isOn ? @"on" : @"off"];
}

- (void)settingStepped:(UIStepper *)stepper {
    NSDictionary *setting = [self settingForControl:stepper];
    NSMutableDictionary *values = [self.settingValues mutableCopy] ?: [NSMutableDictionary dictionary];
    values[setting[@"id"]] = @(stepper.value);   // shown at once; the tweak's answer follows
    self.settingValues = values;
    [self.tableView reloadData];
    [self setSetting:setting to:[NSString stringWithFormat:@"%g", stepper.value]];
}

- (NSDictionary *)settingForControl:(UIControl *)control {
    return self.sections[control.tag >> 16][@"rows"][control.tag & 0xFFFF][@"item"];
}

// Choice: a sheet of its choices. Text: a field.
- (void)editSetting:(NSDictionary *)setting fromCell:(UITableViewCell *)cell {
    NSString *type = setting[@"type"];
    if ([type isEqualToString:@"choice"]) {
        // The current choice is named in the message
        NSString *now = [self detailForSetting:setting];
        NSString *currentLabel = [now componentsSeparatedByString:@"\n"].firstObject;
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:setting[@"title"]
                                                                       message:self.settingValues ? [NSString stringWithFormat:@"Now: %@", currentLabel] : nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSDictionary *choice in setting[@"choices"]) {
            [sheet addAction:[UIAlertAction actionWithTitle:choice[@"label"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [self setSetting:setting to:[choice[@"value"] description]];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
        [self presentViewController:sheet animated:YES completion:nil];
    } else if ([type isEqualToString:@"text"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:setting[@"title"] message:rcao_is_text(setting[@"note"]) ? setting[@"note"] : nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            id current = self.settingValues[setting[@"id"]];
            field.text = current ? [current description] : @"";
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSString *text = [alert.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            [self setSetting:setting to:text];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if ([row[@"kind"] isEqualToString:@"setting"]) [self editSetting:row[@"item"] fromCell:[tableView cellForRowAtIndexPath:indexPath]];
}

- (NSString *)bannerIdForAction:(NSDictionary *)action {
    return [NSString stringWithFormat:@"%@ %@", self.addOnId, action[@"command"]];
}

// How many states a trigger offers on its own (the trigger's states, else its banner's)
- (NSUInteger)stateCountOfTrigger:(NSDictionary *)trigger event:(NSDictionary *)event {
    if ([trigger[@"states"] isKindOfClass:[NSDictionary class]]) return [trigger[@"states"] count];
    if ([trigger[@"states"] isEqual:@NO]) return 0;
    NSDictionary *banner = [event[@"banner"] isKindOfClass:[NSDictionary class]] ? event[@"banner"] : nil;
    return [banner[@"states"] isKindOfClass:[NSDictionary class]] ? [banner[@"states"] count] : 0;
}

#pragma mark - Switches

- (void)enabledChanged:(UISwitch *)toggle {
    BOOL want = toggle.isOn;
    self.switching = YES;
    toggle.enabled = NO;
    NSString *command = [NSString stringWithFormat:@"addons %@ %@", want ? @"enable" : @"disable", self.addOnId];
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.switching = NO;
            if (error || ![output isKindOfClass:[NSString class]] || [output hasPrefix:@"Error"]) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't Change"
                                                                               message:error.localizedDescription ?: output ?: @"RemoteCompanion didn't answer."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
            [self readCatalog];   // the catalog says whether it's on
        });
    }];
}

- (void)bannerChanged:(UISwitch *)toggle {
    NSArray *rows = self.sections[toggle.tag >> 16][@"rows"];
    NSDictionary *action = rows[toggle.tag & 0xFFFF][@"item"];
    NSString *bannerId = [self bannerIdForAction:action];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSMutableArray *optOut = [cm.bannerOptOut mutableCopy];
    [optOut removeObject:bannerId];
    if (!toggle.isOn) [optOut addObject:bannerId];
    cm.bannerOptOut = optOut;   // saves the config
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.sections[section][@"footer"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSString *kind = row[@"kind"];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:[kind isEqualToString:@"info"] ? UITableViewCellStyleValue1 : UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.numberOfLines = 0;
    NSDictionary *item = row[@"item"];

    if ([kind isEqualToString:@"enabled"]) {
        cell.textLabel.text = @"Enabled";
        cell.imageView.image = [RCAddOnCatalog iconImageForAddOn:self.addOn] ?: [UIImage systemImageNamed:[RCAddOnCatalog iconForAddOn:self.addOn]];
        cell.imageView.tintColor = self.on ? [UIColor systemOrangeColor] : [UIColor secondaryLabelColor];
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = self.on;
        toggle.enabled = !self.switching;
        [toggle addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if ([kind isEqualToString:@"action"]) {
        cell.textLabel.text = item[@"name"];
        BOOL details = [item[@"options"] count] > 0 || [item[@"input"] isKindOfClass:[NSDictionary class]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@%@", self.addOnId, item[@"command"], details ? @" …" : @""];
        cell.imageView.image = [RCAddOnCatalog imageForOwnIcon:item[@"icon"] inAddOn:self.addOn] ?: [UIImage systemImageNamed:[RCAddOnCatalog symbolForOwnIcon:item[@"icon"] inAddOn:self.addOn]];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
    } else if ([kind isEqualToString:@"trigger"]) {
        cell.textLabel.text = item[@"name"];
        NSUInteger states = [self stateCountOfTrigger:item event:row[@"event"]];
        cell.detailTextLabel.text = states ? [NSString stringWithFormat:@"%lu state%@", (unsigned long)states, states == 1 ? @"" : @"s"] : nil;
        cell.imageView.image = [RCAddOnCatalog imageForOwnIcon:item[@"icon"] inAddOn:self.addOn] ?: [UIImage systemImageNamed:[RCAddOnCatalog symbolForOwnIcon:item[@"icon"] inAddOn:self.addOn]];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
    } else if ([kind isEqualToString:@"condition"]) {
        cell.textLabel.text = item[@"name"];
        cell.detailTextLabel.text = [item[@"type"] isEqual:@"number"] ? @"Number" : @"Choice";
        cell.imageView.image = [RCAddOnCatalog imageForOwnIcon:item[@"icon"] inAddOn:self.addOn] ?: [UIImage systemImageNamed:[RCAddOnCatalog symbolForOwnIcon:item[@"icon"] inAddOn:self.addOn]];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
    } else if ([kind isEqualToString:@"banner"]) {
        cell.textLabel.text = item[@"name"];
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = ![cm.bannerOptOut containsObject:[self bannerIdForAction:item]];
        toggle.tag = (indexPath.section << 16) | indexPath.row;
        [toggle addTarget:self action:@selector(bannerChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if ([kind isEqualToString:@"setting"]) {
        NSString *type = item[@"type"];
        cell.textLabel.text = item[@"title"];
        cell.detailTextLabel.text = [self detailForSetting:item];
        NSInteger tag = (indexPath.section << 16) | indexPath.row;
        if ([type isEqualToString:@"switch"]) {
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = [self.settingValues[item[@"id"]] boolValue];
            toggle.enabled = self.settingValues != nil;
            toggle.tag = tag;
            [toggle addTarget:self action:@selector(settingSwitched:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        } else if ([type isEqualToString:@"number"]) {
            UIStepper *stepper = [[UIStepper alloc] init];
            stepper.minimumValue = item[@"min"] ? [item[@"min"] doubleValue] : -1e9;
            stepper.maximumValue = item[@"max"] ? [item[@"max"] doubleValue] : 1e9;
            stepper.stepValue = item[@"step"] ? [item[@"step"] doubleValue] : 1;
            stepper.value = [self.settingValues[item[@"id"]] doubleValue];
            stepper.enabled = self.settingValues != nil;
            stepper.tag = tag;
            [stepper addTarget:self action:@selector(settingStepped:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = stepper;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if ([kind isEqualToString:@"info"]) {
        cell.textLabel.text = row[@"title"];
        cell.detailTextLabel.text = row[@"value"];
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    }
    return cell;
}

@end
