#import "RCVariableConditionViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCVariableEditorParts.h"

typedef NS_ENUM(NSInteger, RCVariableConditionSection) {
    RCVariableConditionSectionCompare = 0,
    RCVariableConditionSectionVariable,
    RCVariableConditionSectionValue,
    RCVariableConditionSectionCount
};

// The comparisons: code, tile title, phrase title, icon, whether it takes a value, and what it checks
static NSArray<NSDictionary *> *RCVariableComparisons(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @{ @"op": @"is", @"title": @"Is", @"phrase": @"Is", @"icon": @"equal", @"value": @YES,
               @"message": @"True when the variable equals this text or number. Letter case doesn't matter." },
            @{ @"op": @"is_not", @"title": @"Is Not", @"phrase": @"Is Not", @"icon": @"notequal", @"fallbackIcon": @"xmark", @"value": @YES,
               @"message": @"True when the variable doesn't equal this text or number. Letter case doesn't matter." },
            @{ @"op": @"contains", @"title": @"Contains", @"phrase": @"Contains", @"icon": @"text.magnifyingglass", @"fallbackIcon": @"magnifyingglass", @"value": @YES,
               @"message": @"True when this text appears anywhere in the variable. Letter case doesn't matter." },
            @{ @"op": @"above", @"title": @"Above", @"phrase": @"Is Above", @"icon": @"greaterthan", @"value": @YES, @"number": @YES,
               @"message": @"True when the variable is a number greater than this one." },
            @{ @"op": @"below", @"title": @"Below", @"phrase": @"Is Below", @"icon": @"lessthan", @"value": @YES, @"number": @YES,
               @"message": @"True when the variable is a number less than this one." },
            @{ @"op": @"not_empty", @"title": @"Has Value", @"phrase": @"Has Any Value", @"icon": @"checkmark.circle",
               @"message": @"True when the variable has any value." },
            @{ @"op": @"empty", @"title": @"No Value", @"phrase": @"Has No Value", @"icon": @"circle.dashed", @"fallbackIcon": @"circle",
               @"message": @"True when the variable has no value or was never set." },
        ];
    });
    return list;
}

@interface RCVariableConditionViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSDictionary *original;
@property (nonatomic, copy) NSString *comparison;
@property (nonatomic, strong) NSArray<RCSetVariableTile *> *tiles;
@property (nonatomic, strong) UIView *grid;
@property (nonatomic, strong) UIButton *variableButton;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *valueField;
@property (nonatomic, strong) RCSetVariableFooter *compareFooter;
@property (nonatomic, strong) RCSetVariableFooter *variableFooter;
@property (nonatomic, strong) NSArray<NSString *> *runNames;
@property (nonatomic, strong) NSArray<NSString *> *savedNames;
@property (nonatomic, strong) NSArray<NSString *> *triggerSavedNames;
@property (nonatomic, copy) NSString *pickedName;
@property (nonatomic, assign) BOOL typingNewName;
@end

@implementation RCVariableConditionViewController

+ (NSString *)titleForComparison:(NSString *)comparison {
    for (NSDictionary *c in RCVariableComparisons()) if ([c[@"op"] isEqualToString:comparison]) return c[@"phrase"];
    return @"Is";
}

- (instancetype)initWithCondition:(NSDictionary *)condition otherActions:(NSArray *)otherActions {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _original = condition;
        NSString *comparison = [[condition[@"comparison"] description] lowercaseString] ?: @"is";
        _comparison = @"is";
        for (NSDictionary *c in RCVariableComparisons()) if ([c[@"op"] isEqualToString:comparison]) _comparison = comparison;

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

        NSString *name = [condition[@"variable"] description];
        if (RCSetVariableNameValid(name)) _pickedName = name;
        // Nothing to pick from yet: start with the name field
        _typingNewName = !_pickedName && !_runNames.count && !_savedNames.count;
        self.title = @"Variable";
    }
    return self;
}

- (NSArray<NSString *> *)mergedSaved:(NSArray<NSString *> *)phoneNames {
    NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:phoneNames];
    [all addObjectsFromArray:self.triggerSavedNames ?: @[]];
    [all minusSet:[NSSet setWithArray:self.runNames ?: @[]]];
    return [all.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSDictionary *)currentComparison {
    for (NSDictionary *c in RCVariableComparisons()) if ([c[@"op"] isEqualToString:self.comparison]) return c;
    return RCVariableComparisons().firstObject;
}

- (BOOL)needsValue {
    return [[self currentComparison][@"value"] boolValue];
}

- (UITextField *)makeField {
    UITextField *field = [[UITextField alloc] init];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field addTarget:self action:@selector(updateState) forControlEvents:UIControlEventEditingChanged];
    return field;
}

// Four tiles a row; a short last row keeps the same tile width
- (UIView *)makeGridWithTiles:(NSMutableArray *)tiles {
    UIStackView *grid = [[UIStackView alloc] init];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 8;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *list = RCVariableComparisons();
    NSUInteger columns = 4;
    for (NSUInteger start = 0; start < list.count; start += columns) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.distribution = UIStackViewDistributionFillEqually;
        row.spacing = 8;
        for (NSUInteger i = start; i < start + columns; i++) {
            if (i >= list.count) { [row addArrangedSubview:[[UIView alloc] init]]; continue; }
            RCSetVariableTile *tile = [[RCSetVariableTile alloc] initWithKind:list[i] compact:YES];
            [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:tile];
            [tiles addObject:tile];
        }
        [grid addArrangedSubview:row];
    }
    return grid;
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
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 30;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];

    self.nameField = [self makeField];
    self.nameField.placeholder = @"count";
    self.nameField.font = [UIFont monospacedSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightRegular];
    self.valueField = [self makeField];
    self.valueField.text = [self.original[@"expectedValue"] description];
    UIButton *insert = [UIButton buttonWithType:UIButtonTypeSystem];
    [insert setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
    insert.frame = CGRectMake(0, 0, 36, 36);
    insert.showsMenuAsPrimaryAction = YES;
    insert.accessibilityLabel = @"Insert Variable";
    self.valueField.rightView = insert;
    self.valueField.rightViewMode = UITextFieldViewModeAlways;

    self.variableButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.variableButton.titleLabel.font = [UIFont monospacedSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightRegular];
    // Left-aligned like the text fields, the arrow after the name with a gap
    self.variableButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.variableButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.variableButton.imageEdgeInsets = UIEdgeInsetsMake(0, 10, 0, -10);
    self.variableButton.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 10);
    [self.variableButton setImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"] forState:UIControlStateNormal];
    self.variableButton.showsMenuAsPrimaryAction = YES;
    self.variableButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.compareFooter = [[RCSetVariableFooter alloc] initWithReuseIdentifier:nil];
    self.variableFooter = [[RCSetVariableFooter alloc] initWithReuseIdentifier:nil];

    NSMutableArray *tiles = [NSMutableArray array];
    self.grid = [self makeGridWithTiles:tiles];
    self.tiles = tiles;

    [self applyComparison];
    [self rebuildMenus];
    [self updateState];
    [self loadSavedNames];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.original && self.typingNewName) [self.nameField becomeFirstResponder];
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

#pragma mark - State

- (void)rebuildMenus {
    __weak typeof(self) weakSelf = self;
    UIAction *(^pick)(NSString *) = ^UIAction *(NSString *name) {
        UIAction *action = [UIAction actionWithTitle:name image:nil identifier:nil handler:^(__unused UIAction *a) {
            [weakSelf pickVariable:name];
        }];
        if (!weakSelf.typingNewName && [weakSelf.pickedName isEqualToString:name]) action.state = UIMenuElementStateOn;
        return action;
    };
    NSMutableArray *runNames = [self.runNames mutableCopy], *savedNames = [self.savedNames mutableCopy];
    if (self.pickedName && ![runNames containsObject:self.pickedName] && ![savedNames containsObject:self.pickedName]) {
        [savedNames addObject:self.pickedName];
    }
    NSMutableArray *runItems = [NSMutableArray array], *savedItems = [NSMutableArray array];
    for (NSString *name in runNames) [runItems addObject:pick(name)];
    for (NSString *name in savedNames) [savedItems addObject:pick(name)];
    NSMutableArray *children = [NSMutableArray array];
    if (runItems.count) [children addObject:[UIMenu menuWithTitle:@"This Run" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:runItems]];
    if (savedItems.count) [children addObject:[UIMenu menuWithTitle:@"Saved" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:savedItems]];
    UIAction *other = [UIAction actionWithTitle:@"Other Name" image:[UIImage systemImageNamed:@"plus"] identifier:nil handler:^(__unused UIAction *a) {
        [weakSelf startTypingName];
    }];
    if (self.typingNewName) other.state = UIMenuElementStateOn;
    [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[other]]];
    self.variableButton.menu = [UIMenu menuWithTitle:@"" children:children];
    NSString *title = self.typingNewName ? @"Other Name" : (self.pickedName ?: @"Choose");
    [self.variableButton setTitle:title forState:UIControlStateNormal];

    __weak UITextField *weakField = self.valueField;
    ((UIButton *)self.valueField.rightView).menu = RCVariableInsertMenu(self.runNames, self.savedNames, ^(NSString *name) {
        [weakSelf insertVariable:name intoField:weakField];
    });
}

- (void)pickVariable:(NSString *)name {
    BOOL wasTyping = self.typingNewName;
    self.pickedName = name;
    self.typingNewName = NO;
    [self rebuildMenus];
    if (wasTyping) [self reloadSection:RCVariableConditionSectionVariable];
    [self updateState];
}

- (void)startTypingName {
    if (self.typingNewName) return;
    self.typingNewName = YES;
    self.nameField.text = nil;
    [self rebuildMenus];
    [self reloadSection:RCVariableConditionSectionVariable];
    [self updateState];
    [self.nameField becomeFirstResponder];
}

- (void)reloadSection:(NSInteger)section {
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)applyComparison {
    NSDictionary *c = [self currentComparison];
    for (RCSetVariableTile *tile in self.tiles) tile.selected = [tile.op isEqualToString:self.comparison];
    self.compareFooter.label.text = c[@"message"];
    self.valueField.keyboardType = [c[@"number"] boolValue] ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeDefault;
    self.valueField.placeholder = [c[@"number"] boolValue] ? @"Number or {variable}" : @"Text, number or {variable}";
    [self.valueField reloadInputViews];
}

- (NSString *)trimmed:(NSString *)text {
    return [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)chosenName {
    if (!self.typingNewName) return self.pickedName;
    NSString *name = [self trimmed:self.nameField.text];
    return RCSetVariableNameValid(name) ? name : nil;
}

- (void)setFooter:(RCSetVariableFooter *)footer text:(NSString *)text color:(UIColor *)color {
    BOOL changed = ![footer.label.text isEqualToString:text];
    footer.label.text = text;
    footer.label.textColor = color;
    if (changed && self.tableView.window) {
        [UIView performWithoutAnimation:^{
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
        }];
    }
}

- (void)updateState {
    NSString *typed = [self trimmed:self.nameField.text];
    NSString *text = @"The variable to check.";
    UIColor *color = [UIColor secondaryLabelColor];
    if (self.typingNewName) {
        if (typed.length && !RCSetVariableNameValid(typed)) {
            text = [typed isEqualToString:@"round"] ? @"\"round\" is reserved." : @"Letters, digits and _ only, not starting with a digit.";
            color = [UIColor systemRedColor];
        } else {
            text = @"A variable this trigger doesn't set, such as one another trigger saves.";
        }
    }
    [self setFooter:self.variableFooter text:text color:color];
    BOOL valueOK = !self.needsValue || [self trimmed:self.valueField.text].length > 0;
    self.navigationItem.rightBarButtonItem.enabled = [self chosenName] != nil && valueOK;
}

#pragma mark - Actions

- (void)tileTapped:(RCSetVariableTile *)tile {
    if ([tile.op isEqualToString:self.comparison]) return;
    BOOL hadValue = self.needsValue;
    self.comparison = tile.op;
    [self applyComparison];
    if (hadValue != self.needsValue) {
        [self reloadSection:RCVariableConditionSectionValue];
    } else {
        [UIView performWithoutAnimation:^{
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
        }];
    }
    [self updateState];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}

// Text values get {name} at the cursor; Above and Below take one number, so it replaces the field
- (void)insertVariable:(NSString *)name intoField:(UITextField *)field {
    if (!field) return;
    NSString *token = [NSString stringWithFormat:@"{%@}", name];
    if ([[self currentComparison][@"number"] boolValue]) {
        field.text = token;
    } else if (field.isFirstResponder && field.selectedTextRange) {
        [field replaceRange:field.selectedTextRange withText:token];
    } else {
        field.text = [(field.text ?: @"") stringByAppendingString:token];
    }
    [self updateState];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.nameField && self.needsValue) [self.valueField becomeFirstResponder];
    else [textField resignFirstResponder];
    return NO;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    NSString *name = [self chosenName];
    if (!name) return;
    NSString *value = self.needsValue ? [self trimmed:self.valueField.text] : @"";
    NSString *comparison = self.comparison;
    void (^onSave)(NSString *, NSString *, NSString *) = self.onSave;
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:^{
        if (onSave) onSave(name, comparison, value);
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RCVariableConditionSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case RCVariableConditionSectionCompare: return 1;
        case RCVariableConditionSectionVariable: return self.typingNewName ? 2 : 1;
        default: return self.needsValue ? 1 : 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == RCVariableConditionSectionCompare ? @"Compare" : nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == RCVariableConditionSectionCompare) return self.compareFooter;
    if (section == RCVariableConditionSectionVariable) return self.variableFooter;
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == RCVariableConditionSectionValue) return CGFLOAT_MIN;
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == RCVariableConditionSectionValue && !self.needsValue) return CGFLOAT_MIN;
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)plainCell {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// A row with a label on the left and a control filling the rest (kept controls move between cells)
- (UITableViewCell *)cellWithLabel:(NSString *)labelText control:(UIView *)control {
    UITableViewCell *cell = [self plainCell];
    [control removeFromSuperview];
    UILabel *label = [[UILabel alloc] init];
    label.text = labelText;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [cell.contentView addSubview:label];
    [cell.contentView addSubview:control];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [label.widthAnchor constraintGreaterThanOrEqualToConstant:90],
        [control.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
        [control.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [control.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [control.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [control.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case RCVariableConditionSectionCompare: {
            UITableViewCell *cell = [self plainCell];
            cell.backgroundColor = [UIColor clearColor];
            [self.grid removeFromSuperview];
            [cell.contentView addSubview:self.grid];
            [NSLayoutConstraint activateConstraints:@[
                [self.grid.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                [self.grid.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                [self.grid.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
                [self.grid.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            ]];
            return cell;
        }
        case RCVariableConditionSectionVariable:
            if (indexPath.row == 0) return [self cellWithLabel:@"Variable" control:self.variableButton];
            return [self cellWithLabel:@"Name" control:self.nameField];
        default:
            return [self cellWithLabel:@"Value" control:self.valueField];
    }
}

@end
