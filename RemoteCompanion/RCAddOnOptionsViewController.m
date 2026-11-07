#import "RCAddOnOptionsViewController.h"
#import "RCConfigManager.h"
#import "RCAddOnCatalog.h"
#import "RCAddOnExpandCell.h"

@interface RCAddOnOptionsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) NSDictionary *action;
@property (nonatomic, copy) NSString *base;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *chosen;   // option id -> word ("" = Keep Current)
@property (nonatomic, copy) NSString *inputText;
@property (nonatomic, copy) NSString *expandedId;                                    // the option whose choices are showing
@end

@implementation RCAddOnOptionsViewController

- (instancetype)initWithAction:(NSDictionary *)action base:(NSString *)base current:(NSArray<NSString *> *)current editing:(BOOL)editing {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _action = action;
        _base = [base copy];
        _chosen = [NSMutableDictionary dictionary];
        NSDictionary *split = [RCAddOnCatalog splitWords:current action:action];
        for (NSDictionary *option in action[@"options"] ?: @[]) {
            NSDictionary *choice = split[@"choices"][option[@"id"]];
            _chosen[option[@"id"]] = choice ? choice[@"word"] : @"";
        }
        _inputText = split[@"input"] ?: @"";
        self.title = action[@"name"];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:editing ? @"Save" : @"Add" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = RCAddOnHeaderHeight;
    self.tableView.estimatedRowHeight = 0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (NSArray<NSDictionary *> *)options {
    return [self.action[@"options"] isKindOfClass:[NSArray class]] ? self.action[@"options"] : @[];
}

// skipWhen { "<option id>": "<word>" } names another option's choice that leaves this one out
- (BOOL)isVisible:(NSDictionary *)option {
    NSDictionary *skipWhen = option[@"skipWhen"];
    if ([skipWhen isKindOfClass:[NSDictionary class]]) {
        for (NSString *other in skipWhen) if ([self.chosen[other] isEqualToString:[skipWhen[other] description]]) return NO;
    }
    return YES;
}

- (NSDictionary *)inputSpec {
    return [self.action[@"input"] isKindOfClass:[NSDictionary class]] ? self.action[@"input"] : nil;
}

- (BOOL)isInputSection:(NSInteger)section {
    return [self inputSpec] && section == ([self options].count ? 1 : 0);
}

- (NSArray<NSDictionary *> *)choicesFor:(NSDictionary *)option {
    NSMutableArray *choices = [NSMutableArray arrayWithObject:@{ @"label": @"Keep Current", @"word": @"" }];
    [choices addObjectsFromArray:option[@"choices"]];
    return choices;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return ([self options].count ? 1 : 0) + ([self inputSpec] ? 1 : 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self isInputSection:section] ? 1 : (NSInteger)[self options].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return ![self isInputSection:section] ? @"Options left on Keep Current stay as they are." : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isInputSection:indexPath.section]) return RCAddOnHeaderHeight;
    // Exact heights, so the row and the box inside it always agree: the header and, open, each choice.
    // An option another one rules out takes no room.
    NSDictionary *option = [self options][indexPath.row];
    if (![self isVisible:option]) return 0;
    BOOL expanded = [self.expandedId isEqualToString:option[@"id"]];
    return RCAddOnHeaderHeight + (expanded ? [self choicesFor:option].count * RCAddOnChoiceHeight : 0);
}

- (void)configureCell:(RCAddOnExpandCell *)cell forOption:(NSDictionary *)option {
    NSString *word = self.chosen[option[@"id"]] ?: @"";
    NSDictionary *choice = [RCAddOnCatalog choiceForOption:option inWords:word.length ? @[word] : @[]];
    cell.titleLabel.text = option[@"title"] ?: option[@"id"];
    cell.valueLabel.text = choice ? (choice[@"label"] ?: choice[@"word"]) : @"Keep Current";
    [cell setChoices:[self choicesFor:option] selectedWord:word];
    [cell setExpanded:[self.expandedId isEqualToString:option[@"id"]]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if ([self isInputSection:indexPath.section]) {
        NSDictionary *input = [self inputSpec];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = input[@"title"] ?: @"Value";
        cell.textLabel.textColor = [UIColor labelColor];
        UITextField *field = [[UITextField alloc] init];
        field.placeholder = input[@"placeholder"];
        field.text = self.inputText;
        field.textAlignment = NSTextAlignmentRight;
        field.keyboardType = [input[@"number"] boolValue] ? UIKeyboardTypeDecimalPad : UIKeyboardTypeDefault;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.returnKeyType = UIReturnKeyDone;
        field.delegate = self;
        [field addTarget:self action:@selector(inputChanged:) forControlEvents:UIControlEventEditingChanged];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:field];
        [NSLayoutConstraint activateConstraints:@[
            [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [field.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [field.widthAnchor constraintEqualToAnchor:cell.contentView.widthAnchor multiplier:0.5],
        ]];
        return cell;
    }
    NSDictionary *option = [self options][indexPath.row];
    RCAddOnExpandCell *cell = [[RCAddOnExpandCell alloc] init];
    __weak typeof(self) weakSelf = self;
    cell.onToggle = ^{ [weakSelf toggleOption:option]; };
    cell.onChoose = ^(NSString *word) { [weakSelf choose:word forOption:option]; };
    [self configureCell:cell forOption:option];
    return cell;
}

- (void)refreshVisibleCells {
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
        if ([self isInputSection:path.section]) continue;
        RCAddOnExpandCell *cell = (RCAddOnExpandCell *)[self.tableView cellForRowAtIndexPath:path];
        if ([cell isKindOfClass:[RCAddOnExpandCell class]]) [self configureCell:cell forOption:[self options][path.row]];
    }
}

// The table animates the rows' new heights; the choices and arrows change inside that animation
- (void)animateChanges {
    [self.view endEditing:YES];
    [self.tableView performBatchUpdates:^{
        [self refreshVisibleCells];
    } completion:nil];
}

- (void)toggleOption:(NSDictionary *)option {
    self.expandedId = [self.expandedId isEqualToString:option[@"id"]] ? nil : option[@"id"];
    [self animateChanges];
}

- (void)choose:(NSString *)word forOption:(NSDictionary *)option {
    self.chosen[option[@"id"]] = word;
    self.expandedId = nil;
    [self animateChanges];
}

#pragma mark - Field

- (void)inputChanged:(UITextField *)field {
    self.inputText = field.text ?: @"";
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return YES;
}

#pragma mark - Done

- (void)done {
    [self.view endEditing:YES];
    NSMutableArray *words = [NSMutableArray arrayWithObject:self.base];
    for (NSDictionary *option in [self options]) {
        if (![self isVisible:option]) continue;
        NSString *word = self.chosen[option[@"id"]];
        if (word.length) [words addObject:word];
    }
    NSString *text = [RCAddOnCatalog wordsForInput:self.inputText action:self.action];
    if ([self inputSpec] && text) [words addObject:text];
    NSString *command = [words componentsJoinedByString:@" "];
    if (self.popsWhenDone) [self.navigationController popViewControllerAnimated:YES];
    if (self.onDone) self.onDone(command);
}

@end
