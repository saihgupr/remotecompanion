#import "RCTimerEditorViewController.h"
#import "RCTimerCommand.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCVariableEditorParts.h"

@interface RCTimerEditorViewController () <UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate>

@property (nonatomic, assign) RCTimerActionType selectedAction;
@property (nonatomic, assign) NSInteger selectedHours;
@property (nonatomic, assign) NSInteger selectedMinutes;
@property (nonatomic, assign) NSInteger selectedSeconds;

@property (nonatomic, strong) UISegmentedControl *actionSegment;
@property (nonatomic, strong) UITableViewCell *actionCell;
@property (nonatomic, strong) UITableViewCell *presetsCell;
@property (nonatomic, strong) UITableViewCell *pickerCell;
@property (nonatomic, strong) UITableViewCell *durationFieldCell;
@property (nonatomic, strong) UITableViewCell *labelFieldCell;

@property (nonatomic, strong) UIPickerView *durationPicker;
@property (nonatomic, strong) UITextField *durationField;
@property (nonatomic, strong) UITextField *labelField;
@property (nonatomic, strong) NSArray<UIButton *> *presetButtons;
@property (nonatomic, strong) UIBarButtonItem *saveItem;

@property (nonatomic, copy) NSString *initialDurationExpr;
@property (nonatomic, copy) NSString *initialLabel;
@property (nonatomic, strong) NSArray<NSString *> *runNames;
@property (nonatomic, strong) NSArray<NSString *> *triggerSavedNames;
@property (nonatomic, strong) NSArray<NSString *> *savedNames;
@property (nonatomic, assign) BOOL syncGuard;

@end

@implementation RCTimerEditorViewController

static NSArray<NSNumber *> *RCTimerPresetSeconds(void) {
    return @[@60, @300, @600, @900, @1200, @1800, @2700, @3600];
}

static NSString *RCTimerPresetTitle(NSInteger seconds) {
    return [RCTimerCommand compactTokenForSeconds:seconds];
}

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
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
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
    self.tableView.estimatedRowHeight = 52;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
    }

    [self buildCells];
    [self syncWheelsToPickerAnimated:NO];
    [self updatePresetHighlight];
    [self rebuildVariableMenus];
    [self updateSaveState];
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
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (UITableViewCell *)makeFormFieldCellWithTitle:(NSString *)title
                                    placeholder:(NSString *)placeholder
                                    initialText:(NSString *)initialText
                                      fieldOut:(UITextField **)fieldOut {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    label.textColor = [UIColor labelColor];
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    field.textColor = [UIColor labelColor];
    field.textAlignment = NSTextAlignmentRight;
    field.placeholder = placeholder;
    field.text = initialText;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyDone;
    field.delegate = self;

    UIButton *insertBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [insertBtn setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
    insertBtn.frame = CGRectMake(0, 0, 32, 32);
    insertBtn.showsMenuAsPrimaryAction = YES;
    insertBtn.accessibilityLabel = @"Insert Variable";
    field.rightView = insertBtn;
    field.rightViewMode = UITextFieldViewModeAlways;

    [cell.contentView addSubview:label];
    [cell.contentView addSubview:field];

    [NSLayoutConstraint activateConstraints:@[
        [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:48],
        [label.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [field.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        [field.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [field.topAnchor constraintGreaterThanOrEqualToAnchor:cell.contentView.topAnchor constant:8],
        [field.bottomAnchor constraintLessThanOrEqualToAnchor:cell.contentView.bottomAnchor constant:-8]
    ]];

    if (fieldOut) *fieldOut = field;
    return cell;
}

- (void)buildCells {
    // Action selector
    self.actionCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.actionCell.selectionStyle = UITableViewCellSelectionStyleNone;
    self.actionSegment = [[UISegmentedControl alloc] initWithItems:@[@"Start", @"Pause", @"Resume", @"Stop"]];
    self.actionSegment.translatesAutoresizingMaskIntoConstraints = NO;
    switch (self.selectedAction) {
        case RCTimerActionPause: self.actionSegment.selectedSegmentIndex = 1; break;
        case RCTimerActionResume: self.actionSegment.selectedSegmentIndex = 2; break;
        case RCTimerActionStop: self.actionSegment.selectedSegmentIndex = 3; break;
        default: self.actionSegment.selectedSegmentIndex = 0; break;
    }
    [self.actionSegment addTarget:self action:@selector(actionChanged:) forControlEvents:UIControlEventValueChanged];
    [self.actionCell.contentView addSubview:self.actionSegment];
    [NSLayoutConstraint activateConstraints:@[
        [self.actionSegment.leadingAnchor constraintEqualToAnchor:self.actionCell.contentView.layoutMarginsGuide.leadingAnchor],
        [self.actionSegment.trailingAnchor constraintEqualToAnchor:self.actionCell.contentView.layoutMarginsGuide.trailingAnchor],
        [self.actionSegment.topAnchor constraintEqualToAnchor:self.actionCell.contentView.topAnchor constant:8],
        [self.actionSegment.bottomAnchor constraintEqualToAnchor:self.actionCell.contentView.bottomAnchor constant:-8]
    ]];

    // Presets cell (2 balanced rows of 4 quick chips)
    self.presetsCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.presetsCell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSArray<NSNumber *> *presets = RCTimerPresetSeconds();
    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:presets.count];

    UIStackView *vStack = [[UIStackView alloc] init];
    vStack.translatesAutoresizingMaskIntoConstraints = NO;
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.spacing = 8;
    vStack.distribution = UIStackViewDistributionFillEqually;

    for (NSInteger rowIdx = 0; rowIdx < 2; rowIdx++) {
        UIStackView *hStack = [[UIStackView alloc] init];
        hStack.axis = UILayoutConstraintAxisHorizontal;
        hStack.spacing = 8;
        hStack.distribution = UIStackViewDistributionFillEqually;
        for (NSInteger colIdx = 0; colIdx < 4; colIdx++) {
            NSInteger idx = rowIdx * 4 + colIdx;
            NSInteger secs = presets[idx].integerValue;
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
            btn.tag = secs;
            btn.layer.cornerRadius = 8;
            btn.layer.masksToBounds = YES;
            btn.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
            [btn setTitle:RCTimerPresetTitle(secs) forState:UIControlStateNormal];
            [btn addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
            [btn.heightAnchor constraintEqualToConstant:34].active = YES;
            [hStack addArrangedSubview:btn];
            [buttons addObject:btn];
        }
        [vStack addArrangedSubview:hStack];
    }
    self.presetButtons = buttons;
    [self.presetsCell.contentView addSubview:vStack];
    [NSLayoutConstraint activateConstraints:@[
        [vStack.leadingAnchor constraintEqualToAnchor:self.presetsCell.contentView.layoutMarginsGuide.leadingAnchor],
        [vStack.trailingAnchor constraintEqualToAnchor:self.presetsCell.contentView.layoutMarginsGuide.trailingAnchor],
        [vStack.topAnchor constraintEqualToAnchor:self.presetsCell.contentView.topAnchor constant:10],
        [vStack.bottomAnchor constraintEqualToAnchor:self.presetsCell.contentView.bottomAnchor constant:-10]
    ]];

    // 3-column h/m/s wheel picker
    self.pickerCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.pickerCell.selectionStyle = UITableViewCellSelectionStyleNone;
    self.durationPicker = [[UIPickerView alloc] init];
    self.durationPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.durationPicker.dataSource = self;
    self.durationPicker.delegate = self;
    [self.pickerCell.contentView addSubview:self.durationPicker];
    [NSLayoutConstraint activateConstraints:@[
        [self.durationPicker.leadingAnchor constraintEqualToAnchor:self.pickerCell.contentView.leadingAnchor],
        [self.durationPicker.trailingAnchor constraintEqualToAnchor:self.pickerCell.contentView.trailingAnchor],
        [self.durationPicker.topAnchor constraintEqualToAnchor:self.pickerCell.contentView.topAnchor],
        [self.durationPicker.bottomAnchor constraintEqualToAnchor:self.pickerCell.contentView.bottomAnchor],
        [self.durationPicker.heightAnchor constraintEqualToConstant:162]
    ]];

    // Duration / variable text field
    UITextField *durField = nil;
    self.durationFieldCell = [self makeFormFieldCellWithTitle:@"Duration"
                                                  placeholder:@"20m, 90s, or {var}"
                                                  initialText:self.initialDurationExpr
                                                     fieldOut:&durField];
    self.durationField = durField;
    [self.durationField addTarget:self action:@selector(durationFieldChanged) forControlEvents:UIControlEventEditingChanged];

    // Label text field
    UITextField *lblField = nil;
    self.labelFieldCell = [self makeFormFieldCellWithTitle:@"Label"
                                               placeholder:@"Optional (e.g. Nap)"
                                               initialText:self.initialLabel
                                                  fieldOut:&lblField];
    self.labelField = lblField;
    self.labelField.autocapitalizationType = UITextAutocapitalizationTypeWords;
}

- (void)rebuildVariableMenus {
    if (!self.durationField || !self.labelField) return;
    __weak typeof(self) weakSelf = self;
    ((UIButton *)self.durationField.rightView).menu = RCVariableInsertMenu(self.runNames, self.savedNames, ^(NSString *name) {
        RCTimerInsertVariableText(weakSelf.durationField, name);
        [weakSelf durationFieldChanged];
    });
    ((UIButton *)self.labelField.rightView).menu = RCVariableInsertMenu(self.runNames, self.savedNames, ^(NSString *name) {
        RCTimerInsertVariableText(weakSelf.labelField, name);
    });
}

- (void)syncWheelsToPickerAnimated:(BOOL)animated {
    self.syncGuard = YES;
    [self.durationPicker selectRow:MAX(0, MIN(23, self.selectedHours)) inComponent:0 animated:animated];
    [self.durationPicker selectRow:MAX(0, MIN(59, self.selectedMinutes)) inComponent:1 animated:animated];
    [self.durationPicker selectRow:MAX(0, MIN(59, self.selectedSeconds)) inComponent:2 animated:animated];
    self.syncGuard = NO;
}

- (void)updatePresetHighlight {
    NSInteger currentSecs = -1;
    if (![RCTimerCommand containsVariable:self.durationField.text]) {
        double secs = [RCTimerCommand parseDurationSeconds:self.durationField.text];
        if (secs > 0 && fabs(secs - round(secs)) < 0.001) {
            currentSecs = (NSInteger)llround(secs);
        }
    }
    for (UIButton *btn in self.presetButtons) {
        BOOL active = (btn.tag == currentSecs);
        btn.backgroundColor = active ? [UIColor systemOrangeColor] : [UIColor tertiarySystemFillColor];
        [btn setTitleColor:(active ? [UIColor whiteColor] : [UIColor labelColor]) forState:UIControlStateNormal];
    }
}

- (void)updateSaveState {
    if (self.selectedAction != RCTimerActionStart) {
        self.saveItem.enabled = YES;
        return;
    }
    NSString *expr = self.durationField.text;
    BOOL hasVar = [RCTimerCommand containsVariable:expr];
    double secs = [RCTimerCommand parseDurationSeconds:expr];
    self.saveItem.enabled = (hasVar || secs > 0);
}

- (void)presetTapped:(UIButton *)sender {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    NSInteger total = sender.tag;
    self.selectedHours = MIN(23, total / 3600);
    self.selectedMinutes = (total % 3600) / 60;
    self.selectedSeconds = total % 60;
    [self syncWheelsToPickerAnimated:YES];
    self.durationField.text = [RCTimerCommand compactTokenForSeconds:total];
    [self updatePresetHighlight];
    [self updateSaveState];
}

- (void)durationFieldChanged {
    if (![RCTimerCommand containsVariable:self.durationField.text]) {
        double secs = [RCTimerCommand parseDurationSeconds:self.durationField.text];
        if (secs > 0) {
            NSInteger total = (NSInteger)llround(secs);
            self.selectedHours = MIN(23, total / 3600);
            self.selectedMinutes = (total % 3600) / 60;
            self.selectedSeconds = total % 60;
            [self syncWheelsToPickerAnimated:YES];
        }
    }
    [self updatePresetHighlight];
    [self updateSaveState];
}

- (void)actionChanged:(UISegmentedControl *)sender {
    [self.view endEditing:YES];
    BOOL wasStart = (self.selectedAction == RCTimerActionStart);
    switch (sender.selectedSegmentIndex) {
        case 1: self.selectedAction = RCTimerActionPause; break;
        case 2: self.selectedAction = RCTimerActionResume; break;
        case 3: self.selectedAction = RCTimerActionStop; break;
        default: self.selectedAction = RCTimerActionStart; break;
    }
    BOOL isStart = (self.selectedAction == RCTimerActionStart);
    [self updateSaveState];
    if (wasStart != isStart) {
        [self.tableView beginUpdates];
        if (isStart) {
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
        } else {
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
        }
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
    NSString *lbl = [self supportsTimerLabels] ? self.labelField.text : nil;
    RCTimerCommand *cmd = [[RCTimerCommand alloc] initWithAction:self.selectedAction
                                              durationExpression:(self.selectedAction == RCTimerActionStart ? self.durationField.text : nil)
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

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    NSString *unit = component == 0 ? @"hr" : (component == 1 ? @"min" : @"sec");
    return [NSString stringWithFormat:@"%ld %@", (long)row, unit];
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
    self.durationField.text = [RCTimerCommand compactTokenForSeconds:total];
    [self updatePresetHighlight];
    [self updateSaveState];
}

- (BOOL)supportsTimerLabels {
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (![self supportsTimerLabels]) {
        return self.selectedAction == RCTimerActionStart ? 2 : 1;
    }
    return self.selectedAction == RCTimerActionStart ? 3 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (self.selectedAction == RCTimerActionStart && section == 1) return 3;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Action";
    if (self.selectedAction == RCTimerActionStart && section == 1) return @"Duration";
    if ([self supportsTimerLabels]) return @"Options";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.selectedAction == RCTimerActionStart && section == 1) {
        return @"Tap a preset, spin the wheels, or type a duration (e.g. 20m, 1h30m, 45s, 20:00) or {variable}.";
    }
    if ([self supportsTimerLabels]) {
        BOOL isLabelSection = (self.selectedAction == RCTimerActionStart && section == 2) ||
                              (self.selectedAction != RCTimerActionStart && section == 1);
        if (isLabelSection) {
            return @"Runs a real Apple Clock timer synced with Lock Screen and Apple Watch. Optional labels name individual timers on iOS 17+.";
        }
    } else if (self.selectedAction != RCTimerActionStart && section == 0) {
        return @"Runs a real Apple Clock timer synced with Lock Screen and Apple Watch.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return self.actionCell;
    if (self.selectedAction == RCTimerActionStart && indexPath.section == 1) {
        if (indexPath.row == 0) return self.presetsCell;
        if (indexPath.row == 1) return self.pickerCell;
        return self.durationFieldCell;
    }
    return self.labelFieldCell;
}

@end

