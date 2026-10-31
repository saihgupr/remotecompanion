#import "RCToastEditorViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCVariableEditorParts.h"
#import "RCSymbolPickerViewController.h"

@interface RCToastEditorViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *original;
@property (nonatomic, strong) UITextField *titleField;
@property (nonatomic, strong) UITextField *subtitleField;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong) NSArray<NSString *> *runNames;
@property (nonatomic, strong) NSArray<NSString *> *savedNames;
@property (nonatomic, strong) NSArray<NSString *> *triggerSavedNames;
@end

@implementation RCToastEditorViewController

// "toast "A" "B" "c"" or "toast A": its title, subtitle and icon
static NSArray<NSString *> *RCToastParts(NSString *command) {
    NSMutableArray *parts = [NSMutableArray arrayWithObjects:@"", @"", @"", nil];
    if (![command.lowercaseString hasPrefix:@"toast "]) return parts;
    NSString *args = [[command substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (![args hasPrefix:@"\""]) {
        parts[0] = args;
        return parts;
    }
    NSScanner *scanner = [NSScanner scannerWithString:args];
    scanner.charactersToBeSkipped = nil;
    for (NSUInteger i = 0; i < 3; i++) {
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
        if (![scanner scanString:@"\"" intoString:NULL]) break;
        NSString *text = @"";
        [scanner scanUpToString:@"\"" intoString:&text];
        parts[i] = text ?: @"";
        if (![scanner scanString:@"\"" intoString:NULL]) break;
    }
    return parts;
}

- (instancetype)initWithCommand:(NSString *)command otherActions:(NSArray *)otherActions {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _original = [command copy];
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
        self.title = @"Toast";
    }
    return self;
}

- (NSArray<NSString *> *)mergedSaved:(NSArray<NSString *> *)phoneNames {
    NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:phoneNames];
    [all addObjectsFromArray:self.triggerSavedNames ?: @[]];
    [all minusSet:[NSSet setWithArray:self.runNames ?: @[]]];
    return [all.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (UITextField *)makeFieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text insertButton:(BOOL)insertButton {
    UITextField *field = [[UITextField alloc] init];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.placeholder = placeholder;
    field.text = text;
    field.delegate = self;
    field.returnKeyType = UIReturnKeyNext;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field addTarget:self action:@selector(updateState) forControlEvents:UIControlEventEditingChanged];
    if (insertButton) {
        UIButton *insert = [UIButton buttonWithType:UIButtonTypeSystem];
        [insert setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
        insert.frame = CGRectMake(0, 0, 36, 36);
        insert.showsMenuAsPrimaryAction = YES;
        insert.accessibilityLabel = @"Insert Variable";
        field.rightView = insert;
        field.rightViewMode = UITextFieldViewModeAlways;
    } else {
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }
    return field;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.original ? @"Save" : @"Add" style:UIBarButtonItemStyleDone target:self action:@selector(save)];

    NSArray<NSString *> *parts = RCToastParts(self.original);
    self.titleField = [self makeFieldWithPlaceholder:@"Required" text:parts[0] insertButton:YES];
    self.titleField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    self.subtitleField = [self makeFieldWithPlaceholder:@"Optional" text:parts[1] insertButton:YES];
    self.subtitleField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    self.iconName = parts[2];
    self.subtitleField.returnKeyType = UIReturnKeyDone;

    [self rebuildMenus];
    [self updateState];
    [self loadSavedNames];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.original) [self.titleField becomeFirstResponder];
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
            [strongSelf rebuildMenus];
        });
    }];
}

// The + menus: the variable goes in at the cursor
- (void)rebuildMenus {
    for (UITextField *field in @[self.titleField, self.subtitleField]) {
        __weak UITextField *weakField = field;
        __weak typeof(self) weakSelf = self;
        ((UIButton *)field.rightView).menu = RCVariableInsertMenu(self.runNames, self.savedNames, ^(NSString *name) {
            UITextField *f = weakField;
            if (!f) return;
            NSString *token = [NSString stringWithFormat:@"{%@}", name];
            UITextRange *range = f.selectedTextRange ?: [f textRangeFromPosition:f.endOfDocument toPosition:f.endOfDocument];
            [f replaceRange:range withText:token];
            [weakSelf updateState];
        });
    }
}

- (NSString *)trimmed:(NSString *)text {
    return [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)updateState {
    self.navigationItem.rightBarButtonItem.enabled = [self trimmed:self.titleField.text].length > 0;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.titleField) [self.subtitleField becomeFirstResponder];
    else [textField resignFirstResponder];
    return NO;
}

- (void)cancel {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    // A quote would end the field early
    NSString *(^clean)(UITextField *) = ^NSString *(UITextField *field) {
        return [[self trimmed:field.text] stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    };
    NSString *title = clean(self.titleField), *subtitle = clean(self.subtitleField);
    NSString *icon = [[self trimmed:self.iconName] stringByReplacingOccurrencesOfString:@"\"" withString:@""];
    if (!title.length) return;
    NSString *command;
    if (icon.length) command = [NSString stringWithFormat:@"toast \"%@\" \"%@\" \"%@\"", title, subtitle, icon];
    else if (subtitle.length) command = [NSString stringWithFormat:@"toast \"%@\" \"%@\"", title, subtitle];
    else command = [NSString stringWithFormat:@"toast \"%@\"", title];
    void (^onSave)(NSString *) = self.onSave;
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:^{
        if (onSave) onSave(command);
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Shows a short message at the top of the screen. Use + to insert a variable's value.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if (indexPath.row == 2) {
        // The icon as it will look, and its name; tapping opens the picker
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
        cell.textLabel.text = @"Icon";
        BOOL has = self.iconName.length && [UIImage systemImageNamed:self.iconName];
        cell.detailTextLabel.text = self.iconName.length ? self.iconName : @"None";
        UIImageView *preview = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:has ? self.iconName : @"text.bubble"]];
        preview.tintColor = has ? [UIColor systemBlueColor] : [UIColor tertiaryLabelColor];
        preview.contentMode = UIViewContentModeScaleAspectFit;
        preview.frame = CGRectMake(0, 0, 26, 26);
        UIStackView *accessory = [[UIStackView alloc] initWithArrangedSubviews:@[preview, [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]]]];
        ((UIImageView *)accessory.arrangedSubviews[1]).tintColor = [UIColor tertiaryLabelColor];
        ((UIImageView *)accessory.arrangedSubviews[1]).preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        accessory.spacing = 10;
        accessory.alignment = UIStackViewAlignmentCenter;
        accessory.frame = CGRectMake(0, 0, 50, 30);
        cell.accessoryView = accessory;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UITextField *field = indexPath.row == 0 ? self.titleField : self.subtitleField;
    [field removeFromSuperview];
    UILabel *label = [[UILabel alloc] init];
    label.text = indexPath.row == 0 ? @"Title" : @"Subtitle";
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [cell.contentView addSubview:label];
    [cell.contentView addSubview:field];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [label.widthAnchor constraintGreaterThanOrEqualToConstant:90],
        [field.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
        [field.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row != 2) return;
    [self.view endEditing:YES];
    RCSymbolPickerViewController *picker = [[RCSymbolPickerViewController alloc] initWithSelectedSymbol:self.iconName allowsNone:YES];
    __weak typeof(self) weakSelf = self;
    picker.onPick = ^(NSString *name) {
        weakSelf.iconName = name;
        [weakSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

@end
