#import "RCTimerEditorViewController.h"
#import "RCTimerCommand.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCVariableEditorParts.h"
#import "RCTimerEditorVariants.h"

@interface RCTimerEditorViewController () <UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate>

@property (nonatomic, assign) RCTimerActionType selectedAction;
@property (nonatomic, assign) NSInteger selectedHours;
@property (nonatomic, assign) NSInteger selectedMinutes;
@property (nonatomic, assign) NSInteger selectedSeconds;

@property (nonatomic, strong) RCTimerEditorTheme *theme;
@property (nonatomic, strong) RCTimerEditorFormView *form;
@property (nonatomic, strong) UITableViewCell *formCell;
@property (nonatomic, strong) UIBarButtonItem *saveItem;

@property (nonatomic, copy) NSString *initialDurationExpr;
@property (nonatomic, copy) NSString *initialLabel;
@property (nonatomic, strong) NSArray<NSString *> *runNames;
@property (nonatomic, strong) NSArray<NSString *> *triggerSavedNames;
@property (nonatomic, strong) NSArray<NSString *> *savedNames;
@property (nonatomic, assign) BOOL syncGuard;

@end

@implementation RCTimerEditorViewController

static void RCTimerInsertVariableText(UITextField *field, NSString *name) {
    NSString *token = [NSString stringWithFormat:@"{%@}", name];
    UITextRange *range = field.selectedTextRange;
    if (range) {
        [field replaceRange:range withText:token];
    } else {
        field.text = [(field.text ?: @"") stringByAppendingString:token];
    }
}

- (instancetype)initWithCommand:(NSString *)command {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        RCTimerCommand *parsed = [RCTimerCommand commandWithString:command];
        if (parsed) {
            _selectedAction = (parsed.action == RCTimerActionStatus) ? RCTimerActionStart : parsed.action;
            _initialDurationExpr = parsed.durationExpression ?: @"15m";
            _initialLabel = parsed.label ?: @"";
        } else {
            _selectedAction = RCTimerActionStart;
            _initialDurationExpr = @"15m";
            _initialLabel = @"";
        }
        double secs = [RCTimerCommand parseDurationSeconds:_initialDurationExpr];
        if (secs > 0) {
            NSInteger total = (NSInteger)llround(secs);
            _selectedHours = MIN(23, total / 3600);
            _selectedMinutes = (total % 3600) / 60;
            _selectedSeconds = total % 60;
        } else {
            _selectedHours = 0;
            _selectedMinutes = 15;
            _selectedSeconds = 0;
        }
    }
    return self;
}

- (void)setVariableActions:(NSArray *)variableActions {
    _variableActions = [variableActions copy];
    NSMutableOrderedSet *run = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet *saved = [NSMutableOrderedSet orderedSet];
    for (id item in variableActions) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        if (![[item[@"type"] description] isEqualToString:@"set_variable"]) continue;
        NSString *name = [item[@"name"] description];
        if (!RCSetVariableNameValid(name)) continue;
        if ([[item[@"scope"] description] isEqualToString:@"run"]) [run addObject:name];
        else [saved addObject:name];
    }
    _runNames = [run.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    _triggerSavedNames = saved.array;
    _savedNames = [self mergedSaved:@[]];
    [self rebuildVariableMenus];
}

- (NSArray<NSString *> *)mergedSaved:(NSArray<NSString *> *)phoneNames {
    NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:phoneNames ?: @[]];
    [all addObjectsFromArray:self.triggerSavedNames ?: @[]];
    [all minusSet:[NSSet setWithArray:self.runNames ?: @[]]];
    return [all.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

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
            [strongSelf rebuildVariableMenus];
        });
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Timer";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelTapped)];
    self.saveItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = self.saveItem;

    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 620;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    // The form is the only content; it should sit tight against the top.
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }

    [self rebuildFormPreservingState:NO];
    [self loadSavedNames];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;
    self.tableView.backgroundColor = settingsBG;
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
}

#pragma mark - Form

- (void)rebuildFormPreservingState:(BOOL)preserve {
    NSString *durationText = self.initialDurationExpr ?: @"15m";
    NSString *labelText = self.initialLabel ?: @"";
    if (preserve && self.form) {
        durationText = self.form.durationField.text.length ? self.form.durationField.text : durationText;
        labelText = self.form.labelField.text ?: labelText;
    }

    [self.view endEditing:YES];
    self.theme = [RCTimerEditorTheme themeForCurrentConfig];

    [self.form removeFromSuperview];
    RCTimerEditorFormView *form = [[RCTimerEditorFormView alloc] initWithTheme:self.theme];
    self.form = form;

    __weak typeof(self) weakSelf = self;
    form.onActionChange = ^(RCTimerActionType action) {
        [weakSelf actionChosen:action];
    };

    form.durationField.text = durationText;
    form.durationField.delegate = self;
    [form.durationField addTarget:self action:@selector(durationFieldChanged) forControlEvents:UIControlEventEditingChanged];

    if (form.labelField) {
        form.labelField.text = labelText;
        form.labelField.delegate = self;
        form.labelField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }

    form.picker.dataSource = self;
    form.picker.delegate = self;

    [form setSelectedAction:self.selectedAction];
    [form setDurationVisible:(self.selectedAction == RCTimerActionStart) animated:NO];

    if (!self.formCell) {
        self.formCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        self.formCell.selectionStyle = UITableViewCellSelectionStyleNone;
        self.formCell.backgroundColor = [UIColor clearColor];
        self.formCell.contentView.backgroundColor = [UIColor clearColor];
    }
    for (UIView *view in self.formCell.contentView.subviews) {
        [view removeFromSuperview];
    }
    form.translatesAutoresizingMaskIntoConstraints = NO;
    [self.formCell.contentView addSubview:form];
    [NSLayoutConstraint activateConstraints:@[
        [form.leadingAnchor constraintEqualToAnchor:self.formCell.contentView.leadingAnchor],
        [form.trailingAnchor constraintEqualToAnchor:self.formCell.contentView.trailingAnchor],
        [form.topAnchor constraintEqualToAnchor:self.formCell.contentView.topAnchor],
        [form.bottomAnchor constraintEqualToAnchor:self.formCell.contentView.bottomAnchor]
    ]];

    [self syncWheelsToPickerAnimated:NO];
    [self rebuildVariableMenus];
    [self updateReadout];
    [self updateSaveState];

    self.tableView.backgroundColor = self.theme.background;
    [self.tableView reloadData];
}

- (void)rebuildVariableMenus {
    if (!self.form) return;
    __weak typeof(self) weakSelf = self;

    UITextField *durationField = self.form.durationField;
    if ([durationField.rightView isKindOfClass:[UIButton class]]) {
        ((UIButton *)durationField.rightView).menu = RCVariableInsertMenu(self.runNames, self.savedNames, ^(NSString *name) {
            RCTimerInsertVariableText(weakSelf.form.durationField, name);
            [weakSelf durationFieldChanged];
        });
    }

    UITextField *labelField = self.form.labelField;
    if ([labelField.rightView isKindOfClass:[UIButton class]]) {
        ((UIButton *)labelField.rightView).menu = RCVariableInsertMenu(self.runNames, self.savedNames, ^(NSString *name) {
            RCTimerInsertVariableText(weakSelf.form.labelField, name);
        });
    }
}

- (void)syncWheelsToPickerAnimated:(BOOL)animated {
    self.syncGuard = YES;
    [self.form.picker selectRow:MAX(0, MIN(23, self.selectedHours)) inComponent:0 animated:animated];
    [self.form.picker selectRow:MAX(0, MIN(59, self.selectedMinutes)) inComponent:1 animated:animated];
    [self.form.picker selectRow:MAX(0, MIN(59, self.selectedSeconds)) inComponent:2 animated:animated];
    self.syncGuard = NO;
}

- (void)updateReadout {
    if (!self.form) return;
    if (self.selectedAction != RCTimerActionStart) {
        self.form.readoutCaption = @"Action";
        self.form.readoutText = [RCTimerActionWord(self.selectedAction) uppercaseString];
        return;
    }
    self.form.readoutCaption = self.form.defaultReadoutCaption;
    self.form.readoutText = RCTimerReadoutTextForExpression(self.form.durationField.text);
}

- (void)updateSaveState {
    if (self.selectedAction != RCTimerActionStart) {
        self.saveItem.enabled = YES;
        return;
    }
    NSString *expr = self.form.durationField.text;
    BOOL hasVar = [RCTimerCommand containsVariable:expr];
    double secs = [RCTimerCommand parseDurationSeconds:expr];
    self.saveItem.enabled = (hasVar || secs > 0);
}

- (void)durationFieldChanged {
    if (![RCTimerCommand containsVariable:self.form.durationField.text]) {
        double secs = [RCTimerCommand parseDurationSeconds:self.form.durationField.text];
        if (secs > 0) {
            NSInteger total = (NSInteger)llround(secs);
            self.selectedHours = MIN(23, total / 3600);
            self.selectedMinutes = (total % 3600) / 60;
            self.selectedSeconds = total % 60;
            [self syncWheelsToPickerAnimated:YES];
        }
    }
    [self updateReadout];
    [self updateSaveState];
}

- (void)actionChosen:(RCTimerActionType)action {
    [self.view endEditing:YES];
    if (action == self.selectedAction) return;

    BOOL wasStart = (self.selectedAction == RCTimerActionStart);
    self.selectedAction = action;
    BOOL isStart = (self.selectedAction == RCTimerActionStart);

    [self updateSaveState];
    [self updateReadout];

    if (wasStart != isStart) {
        [self.form setDurationVisible:isStart animated:YES];
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }
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
    [self.view endEditing:YES];
    NSString *lbl = [self supportsTimerLabels] ? self.form.labelField.text : nil;
    RCTimerCommand *cmd = [[RCTimerCommand alloc] initWithAction:self.selectedAction
                                              durationExpression:(self.selectedAction == RCTimerActionStart ? self.form.durationField.text : nil)
                                                           label:lbl];
    if (self.onSave) self.onSave([cmd string]);
    [self closeEditor];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - UIPickerViewDataSource / Delegate

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 3;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return component == 0 ? 24 : 60;
}

- (CGFloat)pickerView:(UIPickerView *)pickerView rowHeightForComponent:(NSInteger)component {
    return 32;
}

- (UIView *)pickerView:(UIPickerView *)pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view {
    return [self.form pickerRowLabelForRow:row component:component];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    if (self.syncGuard) return;
    self.selectedHours = [pickerView selectedRowInComponent:0];
    self.selectedMinutes = [pickerView selectedRowInComponent:1];
    self.selectedSeconds = [pickerView selectedRowInComponent:2];

    NSInteger total = self.selectedHours * 3600 + self.selectedMinutes * 60 + self.selectedSeconds;
    if (total <= 0) {
        total = 1;
        self.selectedSeconds = 1;
        [self syncWheelsToPickerAnimated:YES];
    }
    self.form.durationField.text = [RCTimerCommand compactTokenForSeconds:total];
    [self updateReadout];
    [self updateSaveState];
}

- (BOOL)supportsTimerLabels {
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.formCell;
}

@end
