#import "RCNumberSettingViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCVariableEditorParts.h"

@interface RCNumberSettingViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *initialValue;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *variableButton;
@property (nonatomic, strong) UILabel *readout;
@property (nonatomic, strong) UILabel *unit;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UISegmentedControl *choiceControl;
@property (nonatomic, strong) RCSetVariableFooter *footer;
@property (nonatomic, strong) NSArray<NSString *> *runNames;
@property (nonatomic, strong) NSArray<NSString *> *savedNames;
@property (nonatomic, strong) NSArray<NSString *> *triggerSavedNames;
@end

@implementation RCNumberSettingViewController

- (instancetype)initWithTitle:(NSString *)title label:(NSString *)label value:(NSString *)value otherActions:(NSArray *)otherActions {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = title;
        _label = [label copy];
        _initialValue = [value copy];
        _minimum = 0;
        _maximum = 1000000;
        _allowsRound = YES;
        NSMutableOrderedSet *run = [NSMutableOrderedSet orderedSet], *saved = [NSMutableOrderedSet orderedSet];
        for (id item in otherActions) {
            if (![item isKindOfClass:[NSDictionary class]] || ![[item[@"type"] description] isEqualToString:@"set_variable"]) continue;
            NSString *name = [item[@"name"] description];
            if (!RCSetVariableNameValid(name)) continue;
            if ([[item[@"scope"] description] isEqualToString:@"run"]) [run addObject:name];
            else [saved addObject:name];
        }
        _runNames = [run.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        _triggerSavedNames = saved.array;
        _savedNames = [self mergedSaved:@[]];
    }
    return self;
}

- (NSArray<NSString *> *)mergedSaved:(NSArray<NSString *> *)phoneNames {
    NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:phoneNames];
    [all addObjectsFromArray:self.triggerSavedNames ?: @[]];
    [all minusSet:[NSSet setWithArray:self.runNames ?: @[]]];
    return [all.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    if (self.stepperStyle) self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 30;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithTitle:self.saveTitle ?: @"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem = save;

    if (self.choices.count) {
        self.choiceControl = [[UISegmentedControl alloc] initWithItems:self.choices];
        self.choiceControl.selectedSegmentIndex = MAX(0, MIN((NSInteger)self.choices.count - 1, self.selectedChoice));
        self.choiceControl.translatesAutoresizingMaskIntoConstraints = NO;
    }

    self.field = [[UITextField alloc] init];
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.field.spellCheckingType = UITextSpellCheckingTypeNo;
    self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.field.keyboardType = self.allowsDecimals ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
    self.field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.field.placeholder = self.placeholder;
    self.field.text = self.initialValue;
    self.field.delegate = self;
    self.field.translatesAutoresizingMaskIntoConstraints = NO;
    [self.field addTarget:self action:@selector(updateState) forControlEvents:UIControlEventEditingChanged];
    UIButton *insert = [UIButton buttonWithType:UIButtonTypeSystem];
    [insert setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
    insert.accessibilityLabel = @"Insert Variable";
    insert.showsMenuAsPrimaryAction = YES;
    self.variableButton = insert;
    if (self.stepperStyle) {
        self.variableButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.readout = [[UILabel alloc] init];
        self.readout.textColor = [UIColor labelColor];
        self.readout.adjustsFontSizeToFitWidth = YES;
        self.readout.minimumScaleFactor = 0.5;
        self.unit = [[UILabel alloc] init];
        self.unit.text = @"s";
        self.unit.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        self.unit.textColor = [UIColor secondaryLabelColor];
        self.minusButton = [self stepButtonNamed:@"minus" label:@"Decrease by one second"];
        self.plusButton = [self stepButtonNamed:@"plus" label:@"Increase by one second"];
        [self.minusButton addTarget:self action:@selector(stepDown) forControlEvents:UIControlEventTouchUpInside];
        [self.plusButton addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside];
    } else {
        insert.frame = CGRectMake(0, 0, 36, 36);
        self.field.rightView = insert;
        self.field.rightViewMode = UITextFieldViewModeAlways;
    }

    self.footer = [[RCSetVariableFooter alloc] initWithReuseIdentifier:nil];
    [self rebuildMenu];
    [self updateState];
    [self loadSavedNames];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.stepperStyle && !self.field.text.length) [self.field becomeFirstResponder];
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
            [strongSelf rebuildMenu];
        });
    }];
}

// The + menu: a picked variable takes the field's place, since it holds one number or one variable
- (void)rebuildMenu {
    __weak typeof(self) weakSelf = self;
    self.variableButton.menu = RCVariableInsertMenuWithRound(self.runNames, self.savedNames, self.allowsRound, ^(NSString *name) {
        weakSelf.field.text = [NSString stringWithFormat:@"{%@}", name];
        [weakSelf updateState];
    });
}

- (NSString *)formatted:(double)number {
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    f.maximumFractionDigits = 3;
    return [f stringFromNumber:@(number)];
}

// What to save: an NSNumber in range, a "{name}" string, or nil. *problem says why not.
- (id)valueWithProblem:(NSString **)problem {
    NSString *text = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return nil;
    if ([text hasPrefix:@"{"] && [text hasSuffix:@"}"] && text.length > 2) {
        NSString *name = [text substringWithRange:NSMakeRange(1, text.length - 2)];
        if (RCSetVariableNameValid(name)) return text;
        if ([name isEqualToString:@"round"]) {
            if (self.allowsRound) return text;
            if (problem) *problem = @"Repeat Round only has a value inside a Repeat.";
            return nil;
        }
        if (problem) *problem = @"Variable names use letters, digits and _ only.";
        return nil;
    }
    NSScanner *scanner = [NSScanner scannerWithString:[text stringByReplacingOccurrencesOfString:@"," withString:@"."]];
    double number = 0;
    BOOL ok = [scanner scanDouble:&number] && scanner.isAtEnd;
    if (ok && !self.allowsDecimals && floor(number) != number) ok = NO;
    if (!ok || number < self.minimum || number > self.maximum) {
        if (problem) *problem = [NSString stringWithFormat:@"Enter a %@ from %@ to %@, or choose a variable with +.",
                                 self.allowsDecimals ? @"number" : @"whole number", [self formatted:self.minimum], [self formatted:self.maximum]];
        return nil;
    }
    return self.allowsDecimals ? @(number) : @((NSInteger)number);
}

- (void)updateState {
    NSString *problem = nil;
    id value = [self valueWithProblem:&problem];
    NSString *text = problem ?: self.note;
    UIColor *color = problem ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];
    BOOL changed = ![self.footer.label.text isEqualToString:text];
    self.footer.label.text = text;
    self.footer.label.textColor = color;
    if (changed && self.tableView.window) {
        [UIView performWithoutAnimation:^{
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
        }];
    }
    self.navigationItem.rightBarButtonItem.enabled = value != nil;
    [self updateReadout];
}

// The hero readout: the field's number, or a variable's "{name}" in a smaller monospaced font
- (void)updateReadout {
    if (!self.stepperStyle) return;
    NSString *text = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSScanner *scanner = [NSScanner scannerWithString:[text stringByReplacingOccurrencesOfString:@"," withString:@"."]];
    double number = 0;
    BOOL numeric = [scanner scanDouble:&number] && scanner.isAtEnd;
    if (numeric) {
        self.readout.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle1] scaledFontForFont:[UIFont monospacedSystemFontOfSize:34 weight:UIFontWeightSemibold]];
        self.readout.text = [self formatted:number];
    } else {
        self.readout.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle3] scaledFontForFont:[UIFont monospacedSystemFontOfSize:20 weight:UIFontWeightSemibold]];
        self.readout.text = text;
    }
    self.unit.hidden = !numeric;
    self.minusButton.enabled = numeric && number > self.minimum;
    self.plusButton.enabled = numeric && number < self.maximum;
    self.minusButton.alpha = self.minusButton.enabled ? 1.0 : 0.35;
    self.plusButton.alpha = self.plusButton.enabled ? 1.0 : 0.35;
}

- (UIButton *)stepButtonNamed:(NSString *)symbol label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18
                                                                                               weight:UIImageSymbolWeightSemibold]]
            forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = 23;
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:46],
        [button.heightAnchor constraintEqualToConstant:46],
    ]];
    return button;
}

- (void)stepDown {
    [self stepBy:-1];
}

- (void)stepUp {
    [self stepBy:1];
}

- (void)stepBy:(double)delta {
    NSString *text = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSScanner *scanner = [NSScanner scannerWithString:[text stringByReplacingOccurrencesOfString:@"," withString:@"."]];
    double number = 0;
    if (![scanner scanDouble:&number] || !scanner.isAtEnd) return;
    number = MAX(self.minimum, MIN(self.maximum, number + delta));
    self.field.text = [NSString stringWithFormat:@"%.10g", number];
    [self updateState];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self save];
    return NO;
}

- (void)cancel {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    id value = [self valueWithProblem:NULL];
    if (!value) return;
    NSInteger choice = self.choiceControl ? self.choiceControl.selectedSegmentIndex : 0;
    void (^onSave)(id, NSInteger) = self.onSave;
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:^{
        if (onSave) onSave(value, choice);
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.choiceControl ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.stepperStyle && [self isFieldSection:section] ? 2 : 1;
}

- (BOOL)isFieldSection:(NSInteger)section {
    return section == (self.choiceControl ? 1 : 0);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return [self isFieldSection:section] ? self.footer : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return [self isFieldSection:section] ? UITableViewAutomaticDimension : 8;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    if (![self isFieldSection:indexPath.section]) {
        // The choice sits on the background, like the tiles in the variable editors
        cell.backgroundColor = [UIColor clearColor];
        [self.choiceControl removeFromSuperview];
        [cell.contentView addSubview:self.choiceControl];
        [NSLayoutConstraint activateConstraints:@[
            [self.choiceControl.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
            [self.choiceControl.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
            [self.choiceControl.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [self.choiceControl.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            [self.choiceControl.heightAnchor constraintEqualToConstant:36],
        ]];
        return cell;
    }
    if (self.stepperStyle && indexPath.row == 0) return [self stepperHeroCell];
    if (self.stepperStyle) return [self stepperExactCell];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    [self.field removeFromSuperview];
    UILabel *label = [[UILabel alloc] init];
    label.text = self.label;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [cell.contentView addSubview:label];
    [cell.contentView addSubview:self.field];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [label.widthAnchor constraintGreaterThanOrEqualToConstant:90],
        [self.field.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
        [self.field.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [self.field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [self.field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [self.field.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    return cell;
}

// Stepper style, row 0: the caption with the + menu, then the big readout between the step buttons
- (UITableViewCell *)stepperHeroCell {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    UILabel *caption = [[UILabel alloc] init];
    caption.text = self.label;
    caption.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]];
    caption.textColor = [UIColor secondaryLabelColor];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    [self.variableButton removeFromSuperview];
    [cell.contentView addSubview:self.variableButton];
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    card.layer.cornerRadius = 16;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *valueRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.readout, self.unit]];
    valueRow.axis = UILayoutConstraintAxisHorizontal;
    valueRow.alignment = UIStackViewAlignmentLastBaseline;
    valueRow.spacing = 3;
    valueRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.minusButton];
    [card addSubview:self.plusButton];
    [card addSubview:valueRow];
    [cell.contentView addSubview:caption];
    [cell.contentView addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [caption.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [caption.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
        [self.variableButton.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [self.variableButton.centerYAnchor constraintEqualToAnchor:caption.centerYAnchor],
        [self.variableButton.widthAnchor constraintEqualToConstant:34],
        [self.variableButton.heightAnchor constraintEqualToConstant:34],
        [card.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:6],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:74],
        [self.minusButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [self.minusButton.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [self.minusButton.topAnchor constraintGreaterThanOrEqualToAnchor:card.topAnchor constant:14],
        [self.plusButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.plusButton.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [valueRow.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [valueRow.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [valueRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.minusButton.trailingAnchor constant:12],
        [valueRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.plusButton.leadingAnchor constant:-12],
    ]];
    return cell;
}

// Stepper style, row 1: the Exact row, where the number field lives
- (UITableViewCell *)stepperExactCell {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    card.layer.cornerRadius = 12;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *exactLabel = [[UILabel alloc] init];
    exactLabel.text = @"Exact";
    exactLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    exactLabel.textColor = [UIColor secondaryLabelColor];
    exactLabel.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *well = [[UIView alloc] init];
    well.backgroundColor = [UIColor tertiarySystemFillColor];
    well.layer.cornerRadius = 9;
    well.translatesAutoresizingMaskIntoConstraints = NO;
    [self.field removeFromSuperview];
    [well addSubview:self.field];
    [card addSubview:exactLabel];
    [card addSubview:well];
    [cell.contentView addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
        [card.heightAnchor constraintEqualToConstant:48],
        [exactLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [exactLabel.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [well.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-6],
        [well.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [well.widthAnchor constraintEqualToConstant:116],
        [well.heightAnchor constraintEqualToConstant:36],
        [self.field.leadingAnchor constraintEqualToAnchor:well.leadingAnchor constant:10],
        [self.field.trailingAnchor constraintEqualToAnchor:well.trailingAnchor constant:-10],
        [self.field.topAnchor constraintEqualToAnchor:well.topAnchor],
        [self.field.bottomAnchor constraintEqualToAnchor:well.bottomAnchor],
    ]];
    return cell;
}

@end
