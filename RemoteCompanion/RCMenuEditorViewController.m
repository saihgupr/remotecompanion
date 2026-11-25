#import "RCMenuEditorViewController.h"
#import "RCConfigManager.h"

typedef NS_ENUM(NSInteger, RCMenuEditorSection) {
    RCMenuEditorSectionTitle,
    RCMenuEditorSectionOptions,
    RCMenuEditorSectionTime,
    RCMenuEditorSectionTimeout,
    RCMenuEditorSectionCount,
};

// The time limits offered, in seconds (0: none, until a pick)
static NSArray<NSNumber *> *RCMenuTimeLimits(void) { return @[@0, @5, @10, @15, @30, @60]; }

static NSString *RCItemType(id item) {
    return [item isKindOfClass:[NSDictionary class]] ? [[((NSDictionary *)item)[@"type"] description] lowercaseString] : nil;
}

@interface RCMenuEditorViewController () <UITextFieldDelegate>
@property (nonatomic) BOOL isNew;
@property (nonatomic, strong) NSMutableDictionary *menu;
@property (nonatomic, copy) NSArray *preamble;   // rows between the menu and its first option, kept as they are
// Each option: { @"option": its row (name, icon), @"actions": the rows under it }
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *options;
@property (nonatomic, strong) NSMutableDictionary *timeoutOption; // the option a timeout picks (nil: Cancel)
@property (nonatomic, strong) UITextField *titleField;
@end

@implementation RCMenuEditorViewController

- (instancetype)initWithBlock:(NSArray *)block {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (!self) return nil;
    _options = [NSMutableArray array];
    _isNew = block.count < 2;
    if (_isNew) {
        _menu = [@{ @"type": @"menu", @"timeout": @10 } mutableCopy];
        for (NSString *name in @[@"Option 1", @"Option 2"]) {
            [_options addObject:[@{ @"option": [@{ @"type": @"menu_option", @"name": name } mutableCopy], @"actions": [NSMutableArray array] } mutableCopy]];
        }
        _preamble = @[];
        return self;
    }
    _menu = [block.firstObject mutableCopy];
    NSMutableArray *preamble = [NSMutableArray array];
    NSInteger depth = 0;
    // Everything but the first and last row; options at this menu's own depth start a new group
    for (NSUInteger i = 1; i + 1 < block.count; i++) {
        id item = block[i];
        NSString *type = RCItemType(item);
        if (depth == 0 && [type isEqualToString:@"menu_option"]) {
            [_options addObject:[@{ @"option": [item mutableCopy], @"actions": [NSMutableArray array] } mutableCopy]];
            continue;
        }
        if ([@[@"if", @"repeat", @"repeat_while", @"menu"] containsObject:type ?: @""]) depth++;
        else if ([@[@"end_if", @"end", @"end_repeat", @"end_menu"] containsObject:type ?: @""]) depth--;
        if (_options.count) [_options.lastObject[@"actions"] addObject:item];
        else [preamble addObject:item];
    }
    _preamble = preamble;
    id timeoutIndex = _menu[@"timeoutOption"];
    NSInteger index = [timeoutIndex respondsToSelector:@selector(integerValue)] ? [timeoutIndex integerValue] : -1;
    if (timeoutIndex && index >= 0 && index < (NSInteger)_options.count) _timeoutOption = _options[index];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Choose from Menu";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.isNew ? @"Add" : @"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    // Options can always be dragged by their handles
    [self.tableView setEditing:YES animated:NO];
    self.tableView.allowsSelectionDuringEditing = YES;

    self.titleField = [[UITextField alloc] init];
    self.titleField.placeholder = @"Title (optional)";
    self.titleField.text = [self.menu[@"title"] description];
    self.titleField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.titleField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.titleField.returnKeyType = UIReturnKeyDone;
    self.titleField.delegate = self;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (double)timeLimit {
    return self.menu[@"timeout"] ? [self.menu[@"timeout"] doubleValue] : 10;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    [self.view endEditing:YES];
    NSString *title = [self.titleField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (title.length) self.menu[@"title"] = title; else [self.menu removeObjectForKey:@"title"];
    NSUInteger timeoutIndex = self.timeoutOption ? [self.options indexOfObjectIdenticalTo:self.timeoutOption] : NSNotFound;
    if (timeoutIndex != NSNotFound && [self timeLimit] > 0) self.menu[@"timeoutOption"] = @(timeoutIndex);
    else [self.menu removeObjectForKey:@"timeoutOption"];
    NSMutableArray *block = [NSMutableArray arrayWithObject:[self.menu copy]];
    [block addObjectsFromArray:self.preamble];
    for (NSDictionary *option in self.options) {
        [block addObject:[option[@"option"] copy]];
        [block addObjectsFromArray:option[@"actions"]];
    }
    [block addObject:@{ @"type": @"end_menu" }];
    if (self.onSave) self.onSave(block);
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Options

- (NSString *)iconForOptionAt:(NSUInteger)i {
    NSString *icon = [self.options[i][@"option"][@"icon"] description];
    if (icon.length && [UIImage systemImageNamed:icon]) return icon;
    NSString *numbered = [NSString stringWithFormat:@"%lu.circle.fill", (unsigned long)i + 1];
    return i < 50 && [UIImage systemImageNamed:numbered] ? numbered : @"circle.fill";
}

- (void)addOption {
    NSString *name = [NSString stringWithFormat:@"Option %lu", (unsigned long)self.options.count + 1];
    [self.options addObject:[@{ @"option": [@{ @"type": @"menu_option", @"name": name } mutableCopy], @"actions": [NSMutableArray array] } mutableCopy]];
    [self.tableView reloadData];
    [self renameOptionAt:self.options.count - 1];
}

- (void)renameOptionAt:(NSUInteger)i {
    NSMutableDictionary *option = self.options[i][@"option"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Option Name" message:@"Shown on the menu. {menu} holds it after it's picked." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [option[@"name"] description];
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length) option[@"name"] = name;
        [self.tableView reloadData];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:save];
    alert.preferredAction = save;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseIconForOptionAt:(NSUInteger)i from:(UIView *)source {
    NSMutableDictionary *option = self.options[i][@"option"];
    NSArray<NSArray<NSString *> *> *icons = @[@[@"Number", @""], @[@"Light", @"lightbulb.fill"], @[@"Home", @"house.fill"], @[@"Music", @"music.note"],
                                              @[@"Phone", @"phone.fill"], @[@"Message", @"message.fill"], @[@"Car", @"car.fill"], @[@"Moon", @"moon.fill"],
                                              @[@"Power", @"power"], @[@"Star", @"star.fill"], @[@"Bolt", @"bolt.fill"], @[@"Lock", @"lock.fill"],
                                              @[@"Camera", @"camera.fill"], @[@"Heart", @"heart.fill"], @[@"Timer", @"timer"], @[@"Speaker", @"speaker.wave.2.fill"]];
    NSString *current = [option[@"icon"] description] ?: @"";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Icon" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSArray<NSString *> *icon in icons) {
        NSString *symbol = icon[1].length ? icon[1] : [self iconForOptionAt:i];
        if (icon[1].length && ![UIImage systemImageNamed:icon[1]]) continue;
        UIAlertAction *choice = [UIAlertAction actionWithTitle:[icon[0] stringByAppendingString:[icon[1] isEqualToString:current] ? @" ✓" : @""] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            if (icon[1].length) option[@"icon"] = icon[1]; else [option removeObjectForKey:@"icon"];
            [self.tableView reloadData];
        }];
        UIImage *image = [UIImage systemImageNamed:icon[1].length ? symbol : [NSString stringWithFormat:@"%lu.circle.fill", (unsigned long)i + 1]];
        if (image) [choice setValue:image forKey:@"image"];
        [sheet addAction:choice];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = source;
    sheet.popoverPresentationController.sourceRect = source.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)deleteOptionAt:(NSUInteger)i {
    NSUInteger count = [self.options[i][@"actions"] count];
    void (^remove)(void) = ^{
        if (self.timeoutOption == self.options[i]) self.timeoutOption = nil;
        [self.options removeObjectAtIndex:i];
        [self.tableView reloadData];
    };
    if (!count) { remove(); return; }
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Delete Option?"
        message:[NSString stringWithFormat:@"Its %lu action%@ are deleted too.", (unsigned long)count, count == 1 ? @"" : @"s"]
        preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { remove(); }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RCMenuEditorSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case RCMenuEditorSectionTitle: return 1;
        case RCMenuEditorSectionOptions: return self.options.count + 1; // + Add Option
        case RCMenuEditorSectionTime: return 1;
        case RCMenuEditorSectionTimeout: return [self timeLimit] > 0 ? self.options.count + 1 : 0;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case RCMenuEditorSectionTitle: return @"Title";
        case RCMenuEditorSectionOptions: return @"Options";
        case RCMenuEditorSectionTime: return @"Time Limit";
        case RCMenuEditorSectionTimeout: return [self timeLimit] > 0 ? @"When Time Runs Out" : nil;
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case RCMenuEditorSectionTitle: return @"Shown at the top of the menu.";
        case RCMenuEditorSectionOptions: return @"Tap an option to rename it or change its icon. Drag to reorder: its actions move with it. Add actions under an option in the trigger's list.";
        case RCMenuEditorSectionTime: return [self timeLimit] > 0 ? @"The menu closes after this long if nothing is picked." : @"The menu stays until an option or Cancel is tapped.";
        case RCMenuEditorSectionTimeout: return [self timeLimit] > 0 ? @"Cancel stops the trigger there; an option runs as if it had been picked." : nil;
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    if (indexPath.section == RCMenuEditorSectionTitle) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
        [self.titleField removeFromSuperview];
        [cell.contentView addSubview:self.titleField];
        UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [self.titleField.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [self.titleField.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [self.titleField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [self.titleField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            [self.titleField.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
        return cell;
    }
    if (indexPath.section == RCMenuEditorSectionOptions) {
        if (indexPath.row == (NSInteger)self.options.count) {
            cell.textLabel.text = @"Add Option";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
            cell.imageView.tintColor = [UIColor systemGreenColor];
            return cell;
        }
        NSDictionary *option = self.options[indexPath.row];
        cell.textLabel.text = [option[@"option"][@"name"] description].length ? [option[@"option"][@"name"] description] : @"Option";
        NSUInteger count = [option[@"actions"] count];
        cell.detailTextLabel.text = count ? [NSString stringWithFormat:@"%lu action%@", (unsigned long)count, count == 1 ? @"" : @"s"] : @"No actions";
        cell.imageView.image = [UIImage systemImageNamed:[self iconForOptionAt:indexPath.row]];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        cell.showsReorderControl = YES;
        return cell;
    }
    if (indexPath.section == RCMenuEditorSectionTime) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        NSMutableArray *titles = [NSMutableArray array];
        for (NSNumber *limit in RCMenuTimeLimits()) [titles addObject:limit.doubleValue > 0 ? [NSString stringWithFormat:@"%.0f s", limit.doubleValue] : @"Off"];
        UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:titles];
        NSUInteger at = [RCMenuTimeLimits() indexOfObjectPassingTest:^BOOL(NSNumber *n, NSUInteger i, BOOL *stop) { return fabs(n.doubleValue - [self timeLimit]) < 0.5; }];
        if (at == NSNotFound) {
            // A time typed elsewhere (the Web UI): its own segment
            [control insertSegmentWithTitle:[NSString stringWithFormat:@"%.0f s", [self timeLimit]] atIndex:control.numberOfSegments animated:NO];
            at = control.numberOfSegments - 1;
        }
        control.selectedSegmentIndex = at;
        [control addTarget:self action:@selector(timeChanged:) forControlEvents:UIControlEventValueChanged];
        control.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:control];
        UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [control.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [control.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [control.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:52],
        ]];
        return cell;
    }
    // When Time Runs Out: Cancel, or an option
    BOOL cancelRow = indexPath.row == 0;
    NSDictionary *option = cancelRow ? nil : self.options[indexPath.row - 1];
    cell.textLabel.text = cancelRow ? @"Cancel the Trigger" : [NSString stringWithFormat:@"Pick “%@”", [option[@"option"][@"name"] description] ?: @"Option"];
    BOOL ticked = cancelRow ? self.timeoutOption == nil : self.timeoutOption == option;
    cell.accessoryType = ticked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.imageView.image = [UIImage systemImageNamed:cancelRow ? @"xmark.circle" : [self iconForOptionAt:indexPath.row - 1]];
    cell.imageView.tintColor = cancelRow ? [UIColor secondaryLabelColor] : [UIColor systemBlueColor];
    return cell;
}

- (void)timeChanged:(UISegmentedControl *)control {
    NSArray *limits = RCMenuTimeLimits();
    if (control.selectedSegmentIndex < (NSInteger)limits.count) self.menu[@"timeout"] = limits[control.selectedSegmentIndex];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(RCMenuEditorSectionTime, 2)] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == RCMenuEditorSectionOptions) {
        if (indexPath.row == (NSInteger)self.options.count) { [self addOption]; return; }
        NSUInteger i = indexPath.row;
        UIView *source = [tableView cellForRowAtIndexPath:indexPath];
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[self.options[i][@"option"][@"name"] description] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self renameOptionAt:i]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Icon" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self chooseIconForOptionAt:i from:source]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Delete Option" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { [self deleteOptionAt:i]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = source;
        sheet.popoverPresentationController.sourceRect = source.bounds;
        [self presentViewController:sheet animated:YES completion:nil];
    } else if (indexPath.section == RCMenuEditorSectionTimeout) {
        self.timeoutOption = indexPath.row == 0 ? nil : self.options[indexPath.row - 1];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:RCMenuEditorSectionTimeout] withRowAnimation:UITableViewRowAnimationNone];
    }
}

// Editing is on for the drag handles; no delete circles (a swipe deletes)
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == RCMenuEditorSectionOptions && indexPath.row < (NSInteger)self.options.count && self.options.count > 1;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    if (to.section < RCMenuEditorSectionOptions) return [NSIndexPath indexPathForRow:0 inSection:RCMenuEditorSectionOptions];
    if (to.section > RCMenuEditorSectionOptions || to.row >= (NSInteger)self.options.count) return [NSIndexPath indexPathForRow:self.options.count - 1 inSection:RCMenuEditorSectionOptions];
    return to;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSMutableDictionary *option = self.options[from.row];
    [self.options removeObjectAtIndex:from.row];
    [self.options insertObject:option atIndex:to.row];
    dispatch_async(dispatch_get_main_queue(), ^{ [self.tableView reloadData]; }); // the numbered icons follow
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != RCMenuEditorSectionOptions || indexPath.row >= (NSInteger)self.options.count) return nil;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        [self deleteOptionAt:indexPath.row];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

@end
