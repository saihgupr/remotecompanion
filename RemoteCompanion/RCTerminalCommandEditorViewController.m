#import "RCTerminalCommandEditorViewController.h"
#import "RCConfigManager.h"
#import "RCVariableEditorParts.h"
#import "RCServerClient.h"

@interface RCTerminalCommandEditorViewController () <UITextViewDelegate>

@property (nonatomic, copy) NSString *command;
@property (nonatomic, assign) BOOL isRoot;
@property (nonatomic, strong) UITextView *commandView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic, strong) UIBarButtonItem *insertItem;
@property (nonatomic, strong) NSArray<NSString *> *runNames;
@property (nonatomic, strong) NSArray<NSString *> *triggerSavedNames;
@property (nonatomic, strong) NSArray<NSString *> *savedNames;

@end

@implementation RCTerminalCommandEditorViewController

- (instancetype)initWithCommand:(NSString *)command isRoot:(BOOL)isRoot {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _command = [command copy] ?: @"";
        _isRoot = isRoot;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.command.length > 0 ? @"Edit Terminal Command" : @"New Terminal Command";
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

    [self gatherNames];
    [self loadSavedNames];
    [self updateSaveButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTweaks];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.commandView becomeFirstResponder];
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

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Privileges" : @"Command";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Turn on to run the command as root. Off runs it as the mobile user.";
    }
    return @"Runs on this device, exactly as typed. Multiple lines are allowed.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 ? 170 : 50;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    if (indexPath.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"Execute as Root";

        UISwitch *rootSwitch = [[UISwitch alloc] init];
        rootSwitch.on = self.isRoot;
        [rootSwitch addTarget:self action:@selector(rootSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = rootSwitch;
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (!self.commandView) {
            self.commandView = [[UITextView alloc] init];
            self.commandView.delegate = self;
            self.commandView.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
            self.commandView.backgroundColor = [UIColor clearColor];
            self.commandView.textColor = [UIColor labelColor];
            self.commandView.keyboardType = UIKeyboardTypeASCIICapable;
            self.commandView.autocapitalizationType = UITextAutocapitalizationTypeNone;
            self.commandView.autocorrectionType = UITextAutocorrectionTypeNo;
            self.commandView.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4);
            self.commandView.translatesAutoresizingMaskIntoConstraints = NO;
            self.commandView.text = self.command;
            self.commandView.inputAccessoryView = [self keyboardToolbar];

            self.placeholderLabel = [[UILabel alloc] init];
            self.placeholderLabel.text = @"e.g. uptime";
            self.placeholderLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
            self.placeholderLabel.textColor = [UIColor tertiaryLabelColor];
            self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
            self.placeholderLabel.hidden = self.command.length > 0;
        }
        [cell.contentView addSubview:self.commandView];
        [cell.contentView addSubview:self.placeholderLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.commandView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
            [self.commandView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [self.commandView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
            [self.commandView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
            [self.placeholderLabel.topAnchor constraintEqualToAnchor:self.commandView.topAnchor constant:12],
            [self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.commandView.leadingAnchor constant:9],
        ]];
    }

    return cell;
}

#pragma mark - Variables

- (UIToolbar *)keyboardToolbar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self.commandView action:@selector(resignFirstResponder)];
    if (self.variableActions) {
        self.insertItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle"] style:UIBarButtonItemStylePlain target:nil action:nil];
        self.insertItem.accessibilityLabel = @"Insert Variable";
        [self rebuildMenu];
        [toolbar setItems:@[self.insertItem, flexSpace, doneButton]];
    } else {
        [toolbar setItems:@[flexSpace, doneButton]];
    }
    return toolbar;
}

// The variables this trigger sets, by kind
- (void)gatherNames {
    NSMutableOrderedSet *run = [NSMutableOrderedSet orderedSet], *saved = [NSMutableOrderedSet orderedSet];
    for (id item in self.variableActions) {
        if (![item isKindOfClass:[NSDictionary class]] || ![[item[@"type"] description] isEqualToString:@"set_variable"]) continue;
        NSString *name = [item[@"name"] description];
        if (!RCSetVariableNameValid(name)) continue;
        if ([[item[@"scope"] description] isEqualToString:@"run"]) [run addObject:name];
        else [saved addObject:name];
    }
    self.runNames = [run.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.triggerSavedNames = saved.array;
    self.savedNames = [self mergedSaved:@[]];
}

- (NSArray<NSString *> *)mergedSaved:(NSArray<NSString *> *)phoneNames {
    NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:phoneNames];
    [all addObjectsFromArray:self.triggerSavedNames ?: @[]];
    [all minusSet:[NSSet setWithArray:self.runNames ?: @[]]];
    return [all.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

// Saved variables already on the phone, from other triggers
- (void)loadSavedNames {
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"var list" completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![parsed isKindOfClass:[NSDictionary class]] || ![parsed count]) return;
        NSArray *phoneNames = [parsed allKeys];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.isViewLoaded) return;
            strongSelf.savedNames = [strongSelf mergedSaved:phoneNames];
            [strongSelf rebuildMenu];
        });
    }];
}

// A picked variable goes in at the cursor, as {name}
- (void)rebuildMenu {
    __weak typeof(self) weakSelf = self;
    self.insertItem.menu = RCVariableInsertMenu(self.runNames, self.savedNames, ^(NSString *name) {
        UITextView *textView = weakSelf.commandView;
        UITextRange *range = textView.selectedTextRange ?: [textView textRangeFromPosition:textView.endOfDocument toPosition:textView.endOfDocument];
        [textView replaceRange:range withText:[NSString stringWithFormat:@"{%@}", name]];
    });
}

#pragma mark - Editing

- (void)rootSwitchChanged:(UISwitch *)sender {
    self.isRoot = sender.isOn;
}

- (void)textViewDidChange:(UITextView *)textView {
    self.placeholderLabel.hidden = textView.text.length > 0;
    [self updateSaveButton];
}

- (void)updateSaveButton {
    NSString *trimmed = [self.commandView.text ?: self.command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.saveButton.enabled = (trimmed.length > 0);
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
    NSString *command = [self.commandView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (command.length == 0) return;
    if (self.onSave) self.onSave(command, self.isRoot);

    BOOL isRootOfPresentedNav = (self.navigationController.viewControllers.firstObject == self)
        && self.navigationController.presentingViewController != nil;
    if (isRootOfPresentedNav) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end
