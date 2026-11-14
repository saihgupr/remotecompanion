#import "RCAddOnListViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

static BOOL rcal_is_text(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value length];
}

static void rcal_style_table(UIViewController *vc, UITableView *tableView) {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    vc.view.backgroundColor = settingsBG;
    tableView.backgroundColor = settingsBG;
    tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 52;
    if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 10;
    [vc.view addSubview:tableView];
    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor]
    ]];
}

static UITableViewCell *rcal_cell(UITableViewCellStyle style) {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    if (style == UITableViewCellStyleSubtitle) {
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        cell.detailTextLabel.numberOfLines = 0;
    }
    return cell;
}

static void rcal_alert(UIViewController *vc, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

@implementation RCAddOnSettingText

+ (NSString *)textForNumber:(id)value control:(NSDictionary *)control {
    NSString *number = [value description];
    if ([value isKindOfClass:[NSNumber class]]) {
        NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
        f.numberStyle = NSNumberFormatterDecimalStyle;
        f.maximumFractionDigits = 6;
        number = [f stringFromNumber:value] ?: number;
    }
    return rcal_is_text(control[@"unit"]) ? [NSString stringWithFormat:@"%@ %@", number, control[@"unit"]] : number;
}

+ (NSString *)textForValue:(id)value control:(NSDictionary *)control {
    NSString *type = control[@"type"];
    if (!value) return @"";
    if ([type isEqualToString:@"switch"]) return [value boolValue] ? @"On" : @"Off";
    if ([type isEqualToString:@"number"]) return [self textForNumber:value control:control];
    if ([type isEqualToString:@"choice"]) {
        for (NSDictionary *choice in control[@"choices"]) if ([[choice[@"value"] description] isEqualToString:[value description]]) return choice[@"label"];
    }
    return [value description];
}

+ (NSString *)summaryForItems:(NSArray *)items setting:(NSDictionary *)setting {
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) return @"None";
    NSDictionary *first = [setting[@"fields"] firstObject];
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSString *text = [item isKindOfClass:[NSDictionary class]] ? [self textForValue:item[first[@"id"]] control:first] : @"";
        [names addObject:text.length ? text : @"—"];
    }
    return [names componentsJoinedByString:@", "];
}

+ (NSArray<NSString *> *)suggestionsForControl:(NSDictionary *)control {
    if (![control[@"type"] isEqualToString:@"text"]) return @[];
    NSMutableArray *all = [NSMutableArray array];
    if (rcal_is_text(control[@"suggestionsFile"])) {
        NSData *data = [NSData dataWithContentsOfFile:control[@"suggestionsFile"]];
        id list = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([list isKindOfClass:[NSArray class]]) [all addObjectsFromArray:list];
    }
    if ([control[@"suggestions"] isKindOfClass:[NSArray class]]) [all addObjectsFromArray:control[@"suggestions"]];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id name in all) {
        if (!rcal_is_text(name)) continue;
        NSString *key = [name lowercaseString];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [out addObject:name];
    }
    return out;
}

+ (NSString *)numberForTyped:(NSString *)typed {
    NSString *text = [[typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] stringByReplacingOccurrencesOfString:@"," withString:@"."];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double number = 0;
    if (!text.length || ![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number)) return nil;
    return [NSString stringWithFormat:@"%.10g", number];
}

@end

#pragma mark - Suggestions

@interface RCAddOnSuggestionsViewController ()
@property (nonatomic, copy) NSArray<NSString *> *suggestions, *shown;
@property (nonatomic, copy) NSString *current, *typed;
@property (nonatomic, copy) void (^completion)(NSString *text);
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *search;
@end

@implementation RCAddOnSuggestionsViewController

- (instancetype)initWithTitle:(NSString *)title suggestions:(NSArray<NSString *> *)suggestions current:(NSString *)current completion:(void (^)(NSString *))completion {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = title;
        _suggestions = [suggestions copy];
        _shown = [suggestions copy];
        _current = [current copy];
        _typed = @"";
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    rcal_style_table(self, self.tableView);
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Search or Type a Name";
    self.search.searchBar.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    self.typed = [controller.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"";
    if (!self.typed.length) self.shown = self.suggestions;
    else {
        NSString *t = self.typed;
        self.shown = [self.suggestions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *s, id b) {
            return [s rangeOfString:t options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
        }]];
    }
    [self.tableView reloadData];
}

// "Use '...'" only for typed text that isn't exactly one of the names
- (BOOL)offersTyped {
    if (!self.typed.length) return NO;
    for (NSString *s in self.suggestions) if ([s caseInsensitiveCompare:self.typed] == NSOrderedSame) return NO;
    return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? ([self offersTyped] ? 1 : 0) : (NSInteger)self.shown.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1 && !self.shown.count) return self.typed.length ? nil : @"Type a name in the search field.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = rcal_cell(UITableViewCellStyleDefault);
    if (indexPath.section == 0) {
        cell.textLabel.text = [NSString stringWithFormat:@"Use \u201C%@\u201D", self.typed];
        cell.textLabel.textColor = self.view.tintColor;
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor = [UIColor systemGreenColor];
        return cell;
    }
    NSString *name = self.shown[(NSUInteger)indexPath.row];
    cell.textLabel.text = name;
    cell.accessoryType = [name caseInsensitiveCompare:self.current ?: @""] == NSOrderedSame ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *text = indexPath.section == 0 ? self.typed : self.shown[(NSUInteger)indexPath.row];
    void (^completion)(NSString *) = self.completion;
    self.search.active = NO;
    [self.navigationController popViewControllerAnimated:YES];
    if (completion) completion(text);
}

@end

#pragma mark - Item editor

// One item: a control per field (text and numbers typed in place, a number also has a stepper).
// Save hands the values back; nothing is written until the list saves.
@interface RCAddOnItemViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, copy) NSDictionary *setting;
@property (nonatomic, strong) NSMutableDictionary *values;   // field id -> value (numbers as typed text while editing)
@property (nonatomic, assign) BOOL adding;
@property (nonatomic, copy) void (^completion)(NSDictionary *item);
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) BOOL pickedFirst;   // a new item opened its first field's list once
@end

@implementation RCAddOnItemViewController

static id rcal_default_for_field(NSDictionary *field) {
    NSString *type = field[@"type"];
    if (field[@"default"] && field[@"default"] != [NSNull null]) return field[@"default"];
    if ([type isEqualToString:@"switch"]) return @NO;
    if ([type isEqualToString:@"number"]) return field[@"min"] && [field[@"min"] doubleValue] > 0 ? field[@"min"] : @0;
    if ([type isEqualToString:@"choice"]) return [[field[@"choices"] firstObject] objectForKey:@"value"] ?: @"";
    return @"";
}

- (instancetype)initWithSetting:(NSDictionary *)setting item:(NSDictionary *)item completion:(void (^)(NSDictionary *))completion {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _setting = [setting copy];
        _adding = item == nil;
        _completion = [completion copy];
        _values = [NSMutableDictionary dictionary];
        for (NSDictionary *field in setting[@"fields"]) _values[field[@"id"]] = item[field[@"id"]] ?: rcal_default_for_field(field);
    }
    return self;
}

- (NSArray<NSDictionary *> *)fields {
    return self.setting[@"fields"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.adding ? @"New Item" : @"Edit Item";
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    rcal_style_table(self, self.tableView);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithTitle:self.adding ? @"Add" : @"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem = save;
    [self updateSaveButton];
}

// The first field names the item, so a text first field can't be left empty
- (void)updateSaveButton {
    NSDictionary *first = self.fields.firstObject;
    BOOL named = ![first[@"type"] isEqualToString:@"text"] ||
        [[[self.values[first[@"id"]] description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] > 0;
    self.navigationItem.rightBarButtonItem.enabled = named;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // A new item starts with its first text field: its list to pick from, or typing
    if (!self.adding || self.pickedFirst) return;
    self.pickedFirst = YES;
    for (NSUInteger i = 0; i < self.fields.count; i++) {
        if (![self.fields[i][@"type"] isEqualToString:@"text"]) continue;
        if ([RCAddOnSettingText suggestionsForControl:self.fields[i]].count) {
            [self pickForField:self.fields[i] row:(NSInteger)i];
            return;
        }
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
        UITextField *field = [cell.accessoryView isKindOfClass:[UITextField class]] ? (UITextField *)cell.accessoryView : nil;
        [field becomeFirstResponder];
        return;
    }
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// A text field with suggestions: its list to pick from
- (void)pickForField:(NSDictionary *)field row:(NSInteger)row {
    [self.view endEditing:YES];
    __weak typeof(self) ws = self;
    RCAddOnSuggestionsViewController *pick = [[RCAddOnSuggestionsViewController alloc] initWithTitle:field[@"title"]
        suggestions:[RCAddOnSettingText suggestionsForControl:field] current:[self.values[field[@"id"]] description]
        completion:^(NSString *text) {
            ws.values[field[@"id"]] = text ?: @"";
            [ws updateSaveButton];
            [ws.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        }];
    [self.navigationController pushViewController:pick animated:YES];
}

- (void)save {
    [self.view endEditing:YES];
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    for (NSDictionary *field in self.fields) {
        id value = self.values[field[@"id"]];
        if ([field[@"type"] isEqualToString:@"number"]) {
            NSString *number = [RCAddOnSettingText numberForTyped:[value description]];
            if (!number) {
                rcal_alert(self, @"Couldn't Save", [NSString stringWithFormat:@"%@ isn't a number.", field[@"title"]]);
                return;
            }
            double x = number.doubleValue;
            if (field[@"min"] && x < [field[@"min"] doubleValue]) {
                rcal_alert(self, @"Couldn't Save", [NSString stringWithFormat:@"The lowest %@ is %@.", field[@"title"], [RCAddOnSettingText textForNumber:field[@"min"] control:field]]);
                return;
            }
            if (field[@"max"] && x > [field[@"max"] doubleValue]) {
                rcal_alert(self, @"Couldn't Save", [NSString stringWithFormat:@"The highest %@ is %@.", field[@"title"], [RCAddOnSettingText textForNumber:field[@"max"] control:field]]);
                return;
            }
            value = @(x);
        }
        if (value) item[field[@"id"]] = value;
    }
    void (^completion)(NSDictionary *) = self.completion;
    [self dismissViewControllerAnimated:YES completion:^{
        if (completion) completion(item);
    }];
}

#pragma mark Controls

- (NSDictionary *)fieldForControl:(UIView *)control {
    NSInteger i = control.tag;
    return i >= 0 && i < (NSInteger)self.fields.count ? self.fields[(NSUInteger)i] : nil;
}

- (void)textChanged:(UITextField *)textField {
    NSDictionary *field = [self fieldForControl:textField];
    if (field) self.values[field[@"id"]] = textField.text ?: @"";
    [self updateSaveButton];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)switched:(UISwitch *)toggle {
    NSDictionary *field = [self fieldForControl:toggle];
    if (field) self.values[field[@"id"]] = @(toggle.isOn);
}

// A number's controls are tagged 1000 + field index (text) and 2000 + field index (stepper), so
// viewWithTag: never finds their box (tag 0) instead
- (void)stepped:(UIStepper *)stepper {
    NSInteger i = stepper.tag - 2000;
    if (i < 0 || i >= (NSInteger)self.fields.count) return;
    NSDictionary *field = self.fields[(NSUInteger)i];
    self.values[field[@"id"]] = @(stepper.value);
    UITextField *text = [stepper.superview viewWithTag:i + 1000];
    text.text = [NSString stringWithFormat:@"%.10g", stepper.value];
}

- (void)numberTyped:(UITextField *)textField {
    NSInteger i = textField.tag - 1000;
    if (i < 0 || i >= (NSInteger)self.fields.count) return;
    NSDictionary *field = self.fields[(NSUInteger)i];
    self.values[field[@"id"]] = textField.text ?: @"";
    NSString *number = [RCAddOnSettingText numberForTyped:textField.text];
    UIStepper *stepper = [textField.superview viewWithTag:i + 2000];
    if (number && [stepper isKindOfClass:[UIStepper class]]) stepper.value = number.doubleValue;
}

// A number: the typed value (number pad), its unit, and a stepper
- (UIView *)numberControlForField:(NSDictionary *)field index:(NSInteger)i {
    UIStepper *stepper = [[UIStepper alloc] init];
    stepper.minimumValue = field[@"min"] ? [field[@"min"] doubleValue] : -1e9;
    stepper.maximumValue = field[@"max"] ? [field[@"max"] doubleValue] : 1e9;
    stepper.stepValue = field[@"step"] ? [field[@"step"] doubleValue] : 1;
    NSString *typed = [self.values[field[@"id"]] description];
    stepper.value = [RCAddOnSettingText numberForTyped:typed].doubleValue;
    stepper.tag = i + 2000;
    [stepper addTarget:self action:@selector(stepped:) forControlEvents:UIControlEventValueChanged];

    UITextField *text = [[UITextField alloc] init];
    id value = self.values[field[@"id"]];
    text.text = [value isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%.10g", [value doubleValue]] : [value description];
    text.keyboardType = UIKeyboardTypeDecimalPad;
    text.textAlignment = NSTextAlignmentRight;
    text.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightRegular];
    text.textColor = [UIColor labelColor];
    text.tag = i + 1000;
    [text addTarget:self action:@selector(numberTyped:) forControlEvents:UIControlEventEditingChanged];

    UILabel *unit = [[UILabel alloc] init];
    unit.text = rcal_is_text(field[@"unit"]) ? field[@"unit"] : @"";
    unit.font = [UIFont systemFontOfSize:15];
    unit.textColor = [UIColor secondaryLabelColor];
    [unit sizeToFit];

    CGSize stepSize = stepper.intrinsicContentSize;
    CGFloat textWidth = 72, gap = 6, unitWidth = unit.text.length ? unit.bounds.size.width + gap : 0;
    CGFloat height = MAX(stepSize.height, 32);
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, textWidth + gap + unitWidth + 10 + stepSize.width, height)];
    text.frame = CGRectMake(0, 0, textWidth, height);
    unit.frame = CGRectMake(textWidth + gap, 0, unitWidth, height);
    stepper.frame = CGRectMake(textWidth + gap + unitWidth + 10, (height - stepSize.height) / 2, stepSize.width, stepSize.height);
    [box addSubview:text];
    [box addSubview:unit];
    [box addSubview:stepper];
    return box;
}

- (void)chooseForField:(NSDictionary *)field fromCell:(UITableViewCell *)cell {
    [self.view endEditing:YES];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:field[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *choice in field[@"choices"]) {
        [sheet addAction:[UIAlertAction actionWithTitle:choice[@"label"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            self.values[field[@"id"]] = choice[@"value"];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell;
    sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.fields.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSMutableArray *notes = [NSMutableArray array];
    for (NSDictionary *field in self.fields) if (rcal_is_text(field[@"note"])) [notes addObject:field[@"note"]];
    if (!notes.count && rcal_is_text(self.setting[@"note"])) [notes addObject:self.setting[@"note"]];
    return notes.count ? [notes componentsJoinedByString:@"\n"] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *field = self.fields[(NSUInteger)indexPath.row];
    NSString *type = field[@"type"];
    UITableViewCell *cell = rcal_cell(UITableViewCellStyleValue1);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = field[@"title"];
    id value = self.values[field[@"id"]];
    if ([type isEqualToString:@"switch"]) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = [value boolValue];
        toggle.tag = indexPath.row;
        [toggle addTarget:self action:@selector(switched:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if ([type isEqualToString:@"number"]) {
        cell.accessoryView = [self numberControlForField:field index:indexPath.row];
    } else if ([type isEqualToString:@"choice"]) {
        cell.detailTextLabel.text = [RCAddOnSettingText textForValue:value control:field];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if ([RCAddOnSettingText suggestionsForControl:field].count) {
        NSString *now = [value description];
        cell.detailTextLabel.text = now.length ? now : @"None";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        UITextField *text = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, MIN(240, tableView.bounds.size.width * 0.55), 32)];
        text.text = [value description];
        text.placeholder = @"None";
        text.textAlignment = NSTextAlignmentRight;
        text.textColor = [UIColor labelColor];
        text.font = [UIFont systemFontOfSize:16];
        text.clearButtonMode = UITextFieldViewModeWhileEditing;
        text.returnKeyType = UIReturnKeyDone;
        text.delegate = self;
        text.tag = indexPath.row;
        [text addTarget:self action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
        cell.accessoryView = text;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *field = self.fields[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if ([field[@"type"] isEqualToString:@"choice"]) [self chooseForField:field fromCell:cell];
    else if ([field[@"type"] isEqualToString:@"text"] && [RCAddOnSettingText suggestionsForControl:field].count) [self pickForField:field row:indexPath.row];
    else if ([cell.accessoryView isKindOfClass:[UITextField class]]) [cell.accessoryView becomeFirstResponder];
    else [[cell.accessoryView viewWithTag:indexPath.row + 1000] becomeFirstResponder];
}

@end

#pragma mark - List

@interface RCAddOnListViewController ()
@property (nonatomic, copy) NSString *addOnId;
@property (nonatomic, copy) NSDictionary *setting;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation RCAddOnListViewController

- (instancetype)initWithAddOnId:(NSString *)addOnId setting:(NSDictionary *)setting items:(NSArray *)items {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _addOnId = [addOnId copy];
        _setting = [setting copy];
        _items = [NSMutableArray array];
        for (NSDictionary *item in [items isKindOfClass:[NSArray class]] ? items : @[]) if ([item isKindOfClass:[NSDictionary class]]) [_items addObject:item];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.setting[@"title"];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    rcal_style_table(self, self.tableView);
    [self updateEditButton];
    [self reload];
}

- (void)updateEditButton {
    // Edit (reorder) only with two or more items; a swipe to delete doesn't count as editing
    self.navigationItem.rightBarButtonItem = self.items.count > 1 || self.isEditing ? self.editButtonItem : nil;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
    [self updateEditButton];
}

// The saved items, from the tweak
- (void)reload {
    NSString *command = [NSString stringWithFormat:@"addons settings %@", self.addOnId];
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *values = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *items = [values isKindOfClass:[NSDictionary class]] ? values[self.setting[@"id"]] : nil;
            if ([items isKindOfClass:[NSArray class]] && !self.isEditing) {
                [self.items removeAllObjects];
                for (NSDictionary *item in items) if ([item isKindOfClass:[NSDictionary class]]) [self.items addObject:item];
                [self.tableView reloadData];
                [self updateEditButton];
            }
        });
    }];
}

- (void)saveItems {
    NSData *json = [NSJSONSerialization dataWithJSONObject:self.items options:0 error:nil];
    NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
    NSString *command = [NSString stringWithFormat:@"addons set %@ %@ %@", self.addOnId, self.setting[@"id"], text];
    [self updateEditButton];
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || ![output isKindOfClass:[NSString class]] || [output hasPrefix:@"Error"]) {
                NSString *message = error.localizedDescription ?: [output hasPrefix:@"Error: "] ? [output substringFromIndex:7] : output ?: @"RemoteCompanion didn't answer.";
                rcal_alert(self, @"Couldn't Change", message);
            }
            [self reload];
        });
    }];
}

- (void)editItemAtIndex:(NSInteger)index {
    NSDictionary *item = index >= 0 ? self.items[(NSUInteger)index] : nil;
    RCAddOnItemViewController *editor = [[RCAddOnItemViewController alloc] initWithSetting:self.setting item:item completion:^(NSDictionary *saved) {
        if (index >= 0 && index < (NSInteger)self.items.count) self.items[(NSUInteger)index] = saved;
        else [self.items addObject:saved];
        [self.tableView reloadData];
        [self saveItems];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    [self presentViewController:nav animated:YES completion:nil];
}

// An item's row: its first field, then the others
- (NSString *)titleForItem:(NSDictionary *)item {
    NSDictionary *first = [self.setting[@"fields"] firstObject];
    NSString *text = [RCAddOnSettingText textForValue:item[first[@"id"]] control:first];
    return text.length ? text : @"—";
}

- (NSString *)detailForItem:(NSDictionary *)item {
    NSArray *fields = self.setting[@"fields"];
    NSMutableArray *bits = [NSMutableArray array];
    for (NSUInteger i = 1; i < fields.count; i++) {
        NSString *text = [RCAddOnSettingText textForValue:item[fields[i][@"id"]] control:fields[i]];
        [bits addObject:[NSString stringWithFormat:@"%@: %@", fields[i][@"title"], text.length ? text : @"None"]];
    }
    return bits.count ? [bits componentsJoinedByString:@" · "] : nil;
}

#pragma mark Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)self.items.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0 && self.items.count == 0) return @"None";
    if (section == 1 && rcal_is_text(self.setting[@"note"])) return self.setting[@"note"];
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        UITableViewCell *cell = rcal_cell(UITableViewCellStyleDefault);
        cell.textLabel.text = @"Add";
        cell.textLabel.textColor = self.view.tintColor;
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor = [UIColor systemGreenColor];
        return cell;
    }
    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    UITableViewCell *cell = rcal_cell(UITableViewCellStyleSubtitle);
    cell.textLabel.text = [self titleForItem:item];
    cell.detailTextLabel.text = [self detailForItem:item];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self editItemAtIndex:indexPath.section == 0 ? indexPath.row : -1];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 && self.items.count > 1;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section == 0) return proposed;
    return [NSIndexPath indexPathForRow:(NSInteger)self.items.count - 1 inSection:0];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSDictionary *item = self.items[(NSUInteger)source.row];
    [self.items removeObjectAtIndex:(NSUInteger)source.row];
    [self.items insertObject:item atIndex:(NSUInteger)destination.row];
    [self saveItems];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete || indexPath.section != 0) return;
    [self.items removeObjectAtIndex:(NSUInteger)indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    if (self.items.count == 0) [tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    if (self.items.count < 2 && tableView.isEditing) [self setEditing:NO animated:YES];
    [self saveItems];
}

@end
