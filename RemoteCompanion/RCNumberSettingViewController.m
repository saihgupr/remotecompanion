#import "RCNumberSettingViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCVariableEditorParts.h"

@interface RCNumberSettingViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *initialValue;
@property (nonatomic, strong) UITextField *field;
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
    insert.frame = CGRectMake(0, 0, 36, 36);
    insert.showsMenuAsPrimaryAction = YES;
    insert.accessibilityLabel = @"Insert Variable";
    self.field.rightView = insert;
    self.field.rightViewMode = UITextFieldViewModeAlways;

    self.footer = [[RCSetVariableFooter alloc] initWithReuseIdentifier:nil];
    [self rebuildMenu];
    [self updateState];
    [self loadSavedNames];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.field.text.length) [self.field becomeFirstResponder];
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
    ((UIButton *)self.field.rightView).menu = RCVariableInsertMenuWithRound(self.runNames, self.savedNames, self.allowsRound, ^(NSString *name) {
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
    return 1;
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

@end
