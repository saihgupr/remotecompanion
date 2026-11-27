#import "RCDevAnnotateEditorViewController.h"
#import "RCSetupShortcuts.h"
#import "RCDevAnnotateAction.h"
#import "RCConfigManager.h"

@interface RCDevAnnotateEditorViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *hostId;
@property (nonatomic, copy) NSString *editorId;
@property (nonatomic, copy) NSString *projectDir;
@property (nonatomic, assign) BOOL autoSend;
@property (nonatomic, assign) BOOL pauseMusic;
@property (nonatomic, assign) BOOL editingExisting;

@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic, strong) UITextField *projectDirField;
@property (nonatomic, strong) UISwitch *autoSendSwitch;
@property (nonatomic, strong) UISwitch *pauseMusicSwitch;
@end

typedef NS_ENUM(NSInteger, RCDevAnnotateSection) {
    RCDevAnnotateSectionComputer,
    RCDevAnnotateSectionEditor,
    RCDevAnnotateSectionDelivery,
    RCDevAnnotateSectionCount
};

@implementation RCDevAnnotateEditorViewController

- (instancetype)initWithActionString:(nullable NSString *)actionString {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        NSDictionary *comp = [RCDevAnnotateAction componentsFromActionString:actionString];
        _editingExisting = (comp != nil);
        _hostId = [comp[@"hostId"] copy] ?: @"";
        NSString *parsedEditor = [comp[@"editor"] copy] ?: @"";
        if (![RCDevAnnotateAction presetForId:parsedEditor]) {
            parsedEditor = [RCDevAnnotateAction presets].firstObject[@"id"] ?: @"opencode";
        }
        _editorId = parsedEditor;
        _projectDir = [comp[@"projectDir"] copy] ?: @"";
        _autoSend = comp[@"autoSend"] ? [comp[@"autoSend"] boolValue] : YES;
        _pauseMusic = comp[@"pauseMusic"] ? [comp[@"pauseMusic"] boolValue] : NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.editingExisting ? @"Edit Annotate & Send" : @"Annotate & Send to Editor";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelTapped)];
    self.saveButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = self.saveButton;

    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
    }

    NSArray<NSDictionary *> *hosts = [RCConfigManager sharedManager].sshHosts;
    if (self.hostId.length == 0 && hosts.count == 1) {
        self.hostId = hosts.firstObject[@"id"];
    }

    [self buildControls];
    [self updateSaveButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTweaks];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;
    self.tableView.backgroundColor = settingsBG;
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (void)buildControls {
    self.projectDirField = [self textFieldWithPlaceholder:@"Optional (last viewed)"];
    self.projectDirField.text = self.projectDir;
    self.projectDirField.keyboardType = UIKeyboardTypeURL;

    self.autoSendSwitch = [[UISwitch alloc] init];
    self.autoSendSwitch.on = self.autoSend;
    [self.autoSendSwitch addTarget:self action:@selector(autoSendChanged:) forControlEvents:UIControlEventValueChanged];

    self.pauseMusicSwitch = [[UISwitch alloc] init];
    self.pauseMusicSwitch.on = self.pauseMusic;
    [self.pauseMusicSwitch addTarget:self action:@selector(pauseMusicChanged:) forControlEvents:UIControlEventValueChanged];
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.font = [UIFont systemFontOfSize:16];
    field.textColor = [UIColor labelColor];
    field.tintColor = [UIColor labelColor];
    field.textAlignment = NSTextAlignmentRight;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyDone;
    field.delegate = self;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [field addTarget:self action:@selector(fieldEditingChanged:) forControlEvents:UIControlEventEditingChanged];
    return field;
}

#pragma mark - Helpers

- (NSDictionary *)selectedPreset {
    return [RCDevAnnotateAction presetForId:self.editorId];
}

- (BOOL)showsProjectFolderRow {
    return [[self selectedPreset][@"supportsProjectDir"] boolValue];
}

- (void)updateSaveButton {
    BOOL hostValid = (self.hostId.length > 0 && [[RCConfigManager sharedManager] sshHostForId:self.hostId] != nil);
    self.saveButton.enabled = hostValid;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RCDevAnnotateSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RCDevAnnotateSectionEditor) {
        return [self showsProjectFolderRow] ? 2 : 1;
    }
    if (section == RCDevAnnotateSectionDelivery) {
        return 2;
    }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == RCDevAnnotateSectionComputer) return @"Computer";
    if (section == RCDevAnnotateSectionEditor) return @"Editor";
    return @"Delivery";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCDevAnnotateSectionComputer) {
        return @"Pick the Mac to send to, or add it as a server.";
    }
    if (section == RCDevAnnotateSectionEditor) {
        NSDictionary *preset = [self selectedPreset];
        return [preset[@"subtitle"] isKindOfClass:[NSString class]] ? preset[@"subtitle"] : nil;
    }
    return @"On sends the prompt immediately. Off pastes the image and text into the editor without submitting. Pause Music stops Music or Spotify while you annotate, then resumes it.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 50;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];

    if (indexPath.section == RCDevAnnotateSectionComputer) {
        UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleSubtitle cm:cm];
        NSDictionary *host = self.hostId.length > 0 ? [cm sshHostForId:self.hostId] : nil;
        if (host) {
            cell.textLabel.text = host[@"name"] ?: host[@"host"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@@%@:%@",
                host[@"user"] ?: @"", host[@"host"] ?: @"", host[@"port"] ?: @22];
        } else {
            cell.textLabel.text = @"Choose a Host";
            cell.detailTextLabel.text = @"Required";
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == RCDevAnnotateSectionEditor) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleValue1 cm:cm];
            NSDictionary *preset = [self selectedPreset];
            BOOL multiEditor = ([RCDevAnnotateAction presets].count > 1);
            cell.textLabel.text = @"Editor";
            cell.detailTextLabel.text = preset[@"name"] ?: self.editorId;
            cell.accessoryType = multiEditor ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
            if (!multiEditor) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            return cell;
        }
        return [self cellWithLabel:@"Project Folder" control:self.projectDirField cm:cm];
    }

    UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleDefault cm:cm];
    cell.accessoryView = indexPath.row == 0 ? self.autoSendSwitch : self.pauseMusicSwitch;
    cell.textLabel.text = indexPath.row == 0 ? @"Auto-Send" : @"Pause Music";
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)styledCellWithStyle:(UITableViewCellStyle)style cm:(RCConfigManager *)cm {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.textLabel.textColor = [UIColor labelColor];
    if (cell.detailTextLabel) {
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    return cell;
}

- (UITableViewCell *)cellWithLabel:(NSString *)labelText control:(UIView *)control cm:(RCConfigManager *)cm {
    UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleDefault cm:cm];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    [control removeFromSuperview];
    [cell.contentView addSubview:control];

    UILabel *label = [[UILabel alloc] init];
    label.text = labelText;
    label.font = [UIFont systemFontOfSize:16];
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [cell.contentView addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [control.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:12],
        [control.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [control.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [control.heightAnchor constraintEqualToConstant:34]
    ]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (indexPath.section == RCDevAnnotateSectionComputer) {
        [self chooseHostFromView:cell];
    } else if (indexPath.section == RCDevAnnotateSectionEditor && indexPath.row == 0 && [RCDevAnnotateAction presets].count > 1) {
        [self chooseEditorFromView:cell];
    }
}

#pragma mark - Pickers

- (void)chooseHostFromView:(UIView *)sourceView {
    NSArray<NSDictionary *> *hosts = [RCConfigManager sharedManager].sshHosts;
    if (hosts.count == 0) {
        RCPresentSetupNeeded(self, RCSetupKindSSHHost, @"No Servers", @"Annotate & Send sends to a Mac over SSH. Add it as a server to pick it.", ^(NSDictionary *host) {
            [self useNewHost:host];
        });
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Computer (SSH Host)"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *host in hosts) {
        NSString *name = host[@"name"] ?: host[@"host"];
        NSString *detail = [NSString stringWithFormat:@"%@@%@", host[@"user"] ?: @"", host[@"host"] ?: @""];
        NSString *title = [NSString stringWithFormat:@"%@ (%@)", name, detail];
        if ([host[@"id"] isEqualToString:self.hostId]) {
            title = [title stringByAppendingString:@" \u2713"];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.hostId = host[@"id"];
            [strongSelf updateSaveButton];
            [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCDevAnnotateSectionComputer]
                                withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [sheet addAction:RCSetupAddAction(self, RCSetupKindSSHHost, ^(NSDictionary *host) { [weakSelf useNewHost:host]; })];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

// A server just added here is the one picked
- (void)useNewHost:(NSDictionary *)host {
    if ([host[@"id"] length]) self.hostId = host[@"id"];
    [self updateSaveButton];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCDevAnnotateSectionComputer] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)chooseEditorFromView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Editor"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *preset in [RCDevAnnotateAction presets]) {
        NSString *pid = preset[@"id"];
        NSString *name = preset[@"name"];
        NSString *title = [pid isEqualToString:self.editorId] ? [name stringByAppendingString:@" \u2713"] : name;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.view endEditing:YES];
            strongSelf.editorId = pid;
            [strongSelf updateSaveButton];
            [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCDevAnnotateSectionEditor]
                                withRowAnimation:UITableViewRowAnimationAutomatic];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Control Events

- (void)fieldEditingChanged:(UITextField *)sender {
    if (sender == self.projectDirField) {
        self.projectDir = sender.text ?: @"";
    }
}

- (void)autoSendChanged:(UISwitch *)sender {
    self.autoSend = sender.on;
}

- (void)pauseMusicChanged:(UISwitch *)sender {
    self.pauseMusic = sender.on;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Actions

- (void)cancelTapped {
    BOOL isRootOfPresentedNav = (self.navigationController.viewControllers.firstObject == self)
        && self.navigationController.presentingViewController != nil;
    if (isRootOfPresentedNav) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)saveTapped {
    [self.view endEditing:YES];
    self.projectDir = self.projectDirField.text ?: self.projectDir ?: @"";
    self.autoSend = self.autoSendSwitch.on;
    self.pauseMusic = self.pauseMusicSwitch.on;

    if (self.hostId.length == 0) return;

    NSString *actionString = [RCDevAnnotateAction actionStringWithHostId:self.hostId
                                                                 editor:self.editorId
                                                               autoSend:self.autoSend
                                                             projectDir:self.projectDir
                                                             pauseMusic:self.pauseMusic];
    if (self.onSave) self.onSave(actionString);
}

@end
