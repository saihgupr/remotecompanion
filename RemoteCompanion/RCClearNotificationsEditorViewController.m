#import "RCClearNotificationsEditorViewController.h"
#import "RCClearNotificationsCommand.h"
#import "RCAppPickerViewController.h"
#import "RCConfigManager.h"

@interface UIImage (RCPrivateAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

// Clean multi-line text list editor (one phrase per line), e.g. for pasting CleanNotifications.txt
@interface RCClearTextListViewController : UIViewController
@property (nonatomic, copy) NSArray<NSString *> *initialLines;
@property (nonatomic, copy) void (^onDone)(NSArray<NSString *> *lines);
@property (nonatomic, strong) UITextView *textView;
@end

@implementation RCClearTextListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Filter List";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelTapped)];

    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(doneTapped)];
    UIBarButtonItem *pasteItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"doc.on.clipboard"]
        style:UIBarButtonItemStylePlain
        target:self action:@selector(pasteTapped)];
    pasteItem.accessibilityLabel = @"Paste from Clipboard";
    self.navigationItem.rightBarButtonItems = @[doneItem, pasteItem];

    UILabel *hint = [[UILabel alloc] init];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.text = @"One phrase per line. Blank lines are ignored.";
    hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    hint.textColor = [UIColor secondaryLabelColor];
    hint.numberOfLines = 0;

    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.textView.textColor = [UIColor labelColor];
    self.textView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.textView.layer.cornerRadius = 12;
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.spellCheckingType = UITextSpellCheckingTypeNo;
    self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.textView.text = self.initialLines.count > 0 ? [self.initialLines componentsJoinedByString:@"\n"] : @"";

    [self.view addSubview:hint];
    [self.view addSubview:self.textView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [hint.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [hint.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],

        [self.textView.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:8],
        [self.textView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.textView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.textView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.textView becomeFirstResponder];
}

- (void)pasteTapped {
    NSString *clip = [UIPasteboard generalPasteboard].string;
    if (clip.length == 0) return;
    NSString *existing = self.textView.text ?: @"";
    if (existing.length > 0 && ![existing hasSuffix:@"\n"]) {
        self.textView.text = [existing stringByAppendingFormat:@"\n%@", clip];
    } else {
        self.textView.text = [existing stringByAppendingString:clip];
    }
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doneTapped {
    NSString *raw = [self.textView.text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    raw = [raw stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray<NSString *> *parts = [raw componentsSeparatedByString:@"\n"];
    RCClearNotificationsCommand *parsed = [[RCClearNotificationsCommand alloc] initWithApps:nil texts:parts];
    if (self.onDone) self.onDone(parsed.texts);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface RCClearNotificationsEditorViewController ()
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedApps;
@property (nonatomic, strong) NSMutableArray<NSString *> *filterTexts;
@end

@implementation RCClearNotificationsEditorViewController

- (instancetype)initWithCommand:(NSString *)command {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        RCClearNotificationsCommand *parsed = [RCClearNotificationsCommand commandWithString:command];
        _selectedApps = parsed ? [parsed.apps mutableCopy] : [NSMutableArray array];
        _filterTexts = parsed ? [parsed.texts mutableCopy] : [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Clear Notifications";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(saveTapped)];

    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;
    self.tableView.backgroundColor = settingsBG;
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (void)closeEditor {
    if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)cancelTapped {
    [self closeEditor];
}

- (void)saveTapped {
    RCClearNotificationsCommand *cmd = [[RCClearNotificationsCommand alloc] initWithApps:self.selectedApps texts:self.filterTexts];
    if (self.onSave) self.onSave([cmd string]);
    [self closeEditor];
}

- (NSString *)displayNameForBundleId:(NSString *)bundleId {
    if ([bundleId.lowercaseString isEqualToString:kRCRemoteCompanionBundleId]) {
        return @"RemoteCompanion";
    }
    NSString *name = [[RCConfigManager sharedManager] nameForBundleId:bundleId];
    return name.length > 0 ? name : bundleId;
}

- (void)openAppPicker {
    RCAppPickerViewController *picker = [[RCAppPickerViewController alloc] init];
    picker.allowsMultipleApps = YES;
    picker.allowsEmptySelection = YES;
    picker.selectedBundleIds = [self.selectedApps copy];
    picker.suppressAutoPop = YES;
    __weak typeof(self) weakSelf = self;
    picker.onAppsSelected = ^(NSArray<NSString *> *names, NSArray<NSString *> *bundleIds) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.selectedApps setArray:bundleIds ?: @[]];
        [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
        [strongSelf.navigationController popViewControllerAnimated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)promptTextFilterAtIndex:(NSInteger)index {
    BOOL isNew = (index == NSNotFound || index < 0 || index >= (NSInteger)self.filterTexts.count);
    NSString *existing = isNew ? @"" : self.filterTexts[index];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isNew ? @"Add Text Filter" : @"Edit Text Filter"
                                                                   message:@"Matches title, subtitle, or message."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"e.g. Motion Detected";
        textField.text = existing;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocorrectionType = UITextAutocorrectionTypeDefault;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *save = [UIAlertAction actionWithTitle:isNew ? @"Add" : @"Save"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *raw = alert.textFields.firstObject.text ?: @"";
        NSString *clean = [raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        if ([clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) return;

        if (isNew) {
            if (![strongSelf.filterTexts containsObject:clean]) {
                [strongSelf.filterTexts addObject:clean];
            }
        } else {
            strongSelf.filterTexts[index] = clean;
        }
        [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
    [alert addAction:save];
    alert.preferredAction = save;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openBulkListEditor {
    RCClearTextListViewController *listVC = [[RCClearTextListViewController alloc] init];
    listVC.initialLines = [self.filterTexts copy];
    __weak typeof(self) weakSelf = self;
    listVC.onDone = ^(NSArray<NSString *> *lines) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.filterTexts setArray:lines ?: @[]];
        [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:listVC];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Apps" : @"Match Text";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Leave as Any App to match all notifications, or select specific apps including RemoteCompanion.";
    }
    return @"Clears notifications whose title, subtitle, or message contains any listed text (case-insensitive). Leave empty to clear all from the chosen apps.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.selectedApps.count == 0 ? 1 : (NSInteger)self.selectedApps.count + 1;
    }
    return (NSInteger)self.filterTexts.count + 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (self.selectedApps.count == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AnyAppCell"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"AnyAppCell"];
            cell.textLabel.text = @"Apps";
            cell.detailTextLabel.text = @"Any App";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.imageView.image = nil;
            return cell;
        }
        if (indexPath.row == (NSInteger)self.selectedApps.count) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ChooseAppsCell"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ChooseAppsCell"];
            cell.textLabel.text = @"Choose Apps...";
            cell.textLabel.textColor = tableView.tintColor ?: [UIColor systemBlueColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.imageView.image = nil;
            return cell;
        }
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppItemCell"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AppItemCell"];
        NSString *bundleId = self.selectedApps[indexPath.row];
        cell.textLabel.text = [self displayNameForBundleId:bundleId];
        cell.textLabel.textColor = [UIColor labelColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        UIImage *appIcon = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:0 scale:[UIScreen mainScreen].scale];
        cell.imageView.image = appIcon ?: [UIImage systemImageNamed:@"app.fill"];
        cell.imageView.tintColor = appIcon ? nil : [UIColor secondaryLabelColor];
        return cell;
    }

    if (indexPath.row < (NSInteger)self.filterTexts.count) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TextFilterCell"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TextFilterCell"];
        cell.textLabel.text = self.filterTexts[indexPath.row];
        cell.textLabel.textColor = [UIColor labelColor];
        cell.textLabel.numberOfLines = 0;
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    UITableViewCell *actionCell = [tableView dequeueReusableCellWithIdentifier:@"TextActionCell"];
    if (!actionCell) actionCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TextActionCell"];
    BOOL isAddRow = (indexPath.row == (NSInteger)self.filterTexts.count);
    actionCell.textLabel.text = isAddRow ? @"Add Text Filter..." : @"Paste / Edit List...";
    actionCell.textLabel.textColor = tableView.tintColor ?: [UIColor systemBlueColor];
    actionCell.imageView.image = [UIImage systemImageNamed:isAddRow ? @"plus.circle" : @"list.bullet"];
    actionCell.imageView.tintColor = actionCell.textLabel.textColor;
    actionCell.accessoryType = UITableViewCellAccessoryNone;
    return actionCell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return self.selectedApps.count > 0 && indexPath.row < (NSInteger)self.selectedApps.count;
    }
    return indexPath.row < (NSInteger)self.filterTexts.count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.section == 0 && indexPath.row < (NSInteger)self.selectedApps.count) {
        [self.selectedApps removeObjectAtIndex:indexPath.row];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
    } else if (indexPath.section == 1 && indexPath.row < (NSInteger)self.filterTexts.count) {
        [self.filterTexts removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        [self openAppPicker];
        return;
    }
    if (indexPath.row < (NSInteger)self.filterTexts.count) {
        [self promptTextFilterAtIndex:indexPath.row];
    } else if (indexPath.row == (NSInteger)self.filterTexts.count) {
        [self promptTextFilterAtIndex:NSNotFound];
    } else {
        [self openBulkListEditor];
    }
}

@end

