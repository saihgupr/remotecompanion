#import "RCNotificationEditorViewController.h"
#import "RCNotifyCommand.h"
#import "RCSymbolPickerViewController.h"
#import "RCAppPickerViewController.h"
#import "RCAppDelegate.h"
#import "RCVariableEditorParts.h"
#import "RCServerClient.h"
#import <objc/message.h>

@interface UIImage (RCNotificationEditor)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

static UIImage *RCNEAppIcon(NSString *bundleID) {
    if (![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return nil;
    return [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:UIScreen.mainScreen.scale];
}

// The notification's icon as iOS shows it (near enough): a symbol on a plain tile, or the app's icon
static UIImage *RCNEPicture(NSString *image, CGFloat side) {
    if ([image hasPrefix:@"app:"]) {
        UIImage *icon = RCNEAppIcon([image substringFromIndex:4]);
        if (!icon) return nil;
        return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:side * 0.225] addClip];
            [icon drawInRect:CGRectMake(0, 0, side, side)];
        }];
    }
    if (![image hasPrefix:@"sf:"]) return nil;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.42 weight:UIImageSymbolWeightSemibold];
    UIImage *symbol = [[UIImage systemImageNamed:[image substringFromIndex:3] withConfiguration:config] imageWithTintColor:[UIColor labelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (!symbol) return nil;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor secondarySystemFillColor] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:side * 0.225] fill];
        [symbol drawInRect:CGRectMake((side - symbol.size.width) / 2.0, (side - symbol.size.height) / 2.0, symbol.size.width, symbol.size.height)];
    }];
}

typedef NS_ENUM(NSInteger, RCNESection) { RCNESectionPreview, RCNESectionText, RCNESectionPicture, RCNESectionOptions, RCNESectionButtons, RCNESectionCount };

@interface RCNotificationEditorViewController () <UITextFieldDelegate>
@end

@implementation RCNotificationEditorViewController {
    RCNotifyCommand *_notify;
    BOOL _isNew;
    UITextField *_titleField, *_messageField;
    UITableViewCell *_titleCell, *_messageCell, *_previewCell;
    UILabel *_previewTitle, *_previewMessage;
    UIImageView *_previewIcon;
    UIImage *_rcIcon;
    NSArray<NSString *> *_runNames;          // This Run Only variables set by the trigger
    NSArray<NSString *> *_triggerSavedNames; // saved variables set by the trigger
    NSArray<NSString *> *_savedNames;        // those and the ones saved on the phone
    NSMutableArray<NSMutableDictionary *> *_buttons;
    UIBarButtonItem *_saveButton;
}

- (instancetype)initWithCommand:(NSString *)command {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _isNew = command.length == 0;
        _notify = [RCNotifyCommand commandWithString:command ?: @""];
        _buttons = [NSMutableArray array];
        for (NSDictionary *b in _notify.buttons) [_buttons addObject:[b mutableCopy]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _isNew ? @"New Notification" : @"Edit Notification";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)];
    _saveButton = [[UIBarButtonItem alloc] initWithTitle:(_isNew ? @"Add" : @"Save") style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem = _saveButton;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
    _titleCell = [self fieldCellWithLabel:@"Title" placeholder:@"Required" text:_notify.title field:&_titleField];
    _messageCell = [self fieldCellWithLabel:@"Message" placeholder:@"Optional" text:_notify.message field:&_messageField];
    _titleField.returnKeyType = UIReturnKeyNext;
    [self buildPreviewCell];
    [self refresh];
    [self collectVariableNames];
    [self rebuildVariableMenus];
    [self loadSavedVariableNames];
}

#pragma mark Variables

// The variables the trigger's Set Variable actions name, This Run Only apart from saved ones (as in
// the Toast editor)
- (void)collectVariableNames {
    NSMutableOrderedSet *run = [NSMutableOrderedSet orderedSet], *saved = [NSMutableOrderedSet orderedSet];
    for (id item in self.variableActions ?: @[]) {
        if (![item isKindOfClass:[NSDictionary class]] || ![[item[@"type"] description] isEqualToString:@"set_variable"]) continue;
        NSString *name = [item[@"name"] description];
        if (!RCSetVariableNameValid(name)) continue;
        if ([[item[@"scope"] description] isEqualToString:@"run"]) [run addObject:name];
        else [saved addObject:name];
    }
    _runNames = [run.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    _triggerSavedNames = saved.array;
    _savedNames = [self mergedSavedNames:@[]];
}

- (NSArray<NSString *> *)mergedSavedNames:(NSArray<NSString *> *)phoneNames {
    NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:phoneNames];
    [all addObjectsFromArray:_triggerSavedNames ?: @[]];
    [all minusSet:[NSSet setWithArray:_runNames ?: @[]]];
    return [all.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

// The ones saved on the phone, from other triggers too
- (void)loadSavedVariableNames {
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"var list" completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![parsed isKindOfClass:[NSDictionary class]] || ![parsed count]) return;
        NSArray *phoneNames = [parsed allKeys];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.isViewLoaded) return;
            strongSelf->_savedNames = [strongSelf mergedSavedNames:phoneNames];
            [strongSelf rebuildVariableMenus];
        });
    }];
}

- (void)rebuildVariableMenus {
    for (UITextField *field in @[_titleField ?: [UITextField new], _messageField ?: [UITextField new]]) {
        if (![field.rightView isKindOfClass:[UIButton class]]) continue;
        __weak UITextField *weakField = field;
        __weak typeof(self) weakSelf = self;
        ((UIButton *)field.rightView).menu = RCVariableInsertMenu(_runNames, _savedNames, ^(NSString *name) {
            UITextField *f = weakField;
            if (!f) return;
            UITextRange *range = f.selectedTextRange ?: [f textRangeFromPosition:f.endOfDocument toPosition:f.endOfDocument];
            [f replaceRange:range withText:[NSString stringWithFormat:@"{%@}", name]];
            [weakSelf refresh];
        });
    }
}

#pragma mark Cells

- (UITableViewCell *)fieldCellWithLabel:(NSString *)labelText placeholder:(NSString *)placeholder text:(NSString *)text field:(UITextField * __strong *)out {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *label = [[UILabel alloc] init];
    label.text = labelText;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:label];
    UITextField *field = [[UITextField alloc] init];
    field.text = text;
    field.placeholder = placeholder;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    field.returnKeyType = UIReturnKeyDone;
    field.delegate = self;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field addTarget:self action:@selector(refresh) forControlEvents:UIControlEventEditingChanged];
    // + inserts a variable's {name} at the cursor (its menu is set in rebuildVariableMenus)
    UIButton *insert = [UIButton buttonWithType:UIButtonTypeSystem];
    [insert setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
    insert.frame = CGRectMake(0, 0, 32, 32);
    insert.showsMenuAsPrimaryAction = YES;
    insert.accessibilityLabel = @"Insert Variable";
    field.rightView = insert;
    field.rightViewMode = UITextFieldViewModeAlways;
    [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [label.widthAnchor constraintEqualToConstant:78],
        [field.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
        [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:11],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-11],
    ]];
    *out = field;
    return cell;
}

// A notification banner as iOS draws one: its icon (the picture, or RC's), the title and the message
- (void)buildPreviewCell {
    _previewCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    _previewCell.selectionStyle = UITableViewCellSelectionStyleNone;
    _previewCell.backgroundColor = [UIColor clearColor];
    UIView *banner = [[UIView alloc] init];
    banner.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
    banner.layer.cornerRadius = 18;
    banner.translatesAutoresizingMaskIntoConstraints = NO;
    [_previewCell.contentView addSubview:banner];
    _previewIcon = [[UIImageView alloc] init];
    _previewIcon.layer.cornerRadius = 8; _previewIcon.clipsToBounds = YES;
    _previewIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _rcIcon = RCNEAppIcon(@"com.saihgupr.remotecompanion") ?: [UIImage systemImageNamed:@"app.fill"];
    _previewTitle = [[UILabel alloc] init];
    _previewTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _previewTitle.translatesAutoresizingMaskIntoConstraints = NO;
    _previewMessage = [[UILabel alloc] init];
    _previewMessage.font = [UIFont systemFontOfSize:15];
    _previewMessage.numberOfLines = 2;
    _previewMessage.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *when = [[UILabel alloc] init];
    when.text = @"now";
    when.font = [UIFont systemFontOfSize:13];
    when.textColor = [UIColor secondaryLabelColor];
    when.translatesAutoresizingMaskIntoConstraints = NO;
    for (UIView *v in @[_previewIcon, _previewTitle, _previewMessage, when]) [banner addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [banner.leadingAnchor constraintEqualToAnchor:_previewCell.contentView.leadingAnchor],
        [banner.trailingAnchor constraintEqualToAnchor:_previewCell.contentView.trailingAnchor],
        [banner.topAnchor constraintEqualToAnchor:_previewCell.contentView.topAnchor constant:4],
        [banner.bottomAnchor constraintEqualToAnchor:_previewCell.contentView.bottomAnchor constant:-4],
        [banner.heightAnchor constraintGreaterThanOrEqualToConstant:64],
        [_previewIcon.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:12],
        [_previewIcon.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
        [_previewIcon.widthAnchor constraintEqualToConstant:38], [_previewIcon.heightAnchor constraintEqualToConstant:38],
        [_previewTitle.leadingAnchor constraintEqualToAnchor:_previewIcon.trailingAnchor constant:12],
        [_previewTitle.topAnchor constraintEqualToAnchor:banner.topAnchor constant:12],
        [_previewTitle.trailingAnchor constraintEqualToAnchor:when.leadingAnchor constant:-8],
        [when.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-14],
        [when.firstBaselineAnchor constraintEqualToAnchor:_previewTitle.firstBaselineAnchor],
        [_previewMessage.leadingAnchor constraintEqualToAnchor:_previewTitle.leadingAnchor],
        [_previewMessage.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-14],
        [_previewMessage.topAnchor constraintEqualToAnchor:_previewTitle.bottomAnchor constant:1],
        [_previewMessage.bottomAnchor constraintLessThanOrEqualToAnchor:banner.bottomAnchor constant:-12],
    ]];
    [when setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)refresh {
    NSString *title = _titleField.text ?: @"";
    _previewTitle.text = title.length ? title : @"Title";
    _previewTitle.textColor = title.length ? [UIColor labelColor] : [UIColor tertiaryLabelColor];
    _previewMessage.text = _messageField.text ?: @"";
    UIImage *picture = RCNEPicture(_notify.image, 76);
    _previewIcon.image = picture ?: _rcIcon;
    _saveButton.enabled = title.length > 0;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _titleField) [_messageField becomeFirstResponder];
    else [textField resignFirstResponder];
    return YES;
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return RCNESectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case RCNESectionPreview: return 1;
        case RCNESectionText: return 2;
        case RCNESectionPicture: return 1;
        case RCNESectionOptions: return 2;
        case RCNESectionButtons: return _buttons.count + (_buttons.count < 4 ? 1 : 0);
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case RCNESectionText: return @"Message";
        case RCNESectionPicture: return @"Picture";
        case RCNESectionOptions: return @"Options";
        case RCNESectionButtons: return @"Buttons";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case RCNESectionText: return @"Shows as a notification, also with RC closed.";
        case RCNESectionPicture: return @"Optional. Shows in place of RC's icon.";
        case RCNESectionOptions: return @"Time Sensitive shows through Focus. Remove After takes it out of Notification Center.";
        case RCNESectionButtons: return @"Shown when the notification is held. Each runs a trigger of its own, listed under Notifications.";
    }
    return nil;
}

- (UITableViewCell *)valueCell:(NSString *)text value:(NSString *)value {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = text;
    cell.detailTextLabel.text = value;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSString *)pictureName {
    if ([_notify.image hasPrefix:@"sf:"]) return [_notify.image substringFromIndex:3];
    if ([_notify.image hasPrefix:@"app:"]) {
        NSString *bundle = [_notify.image substringFromIndex:4];
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL lookup = NSSelectorFromString(@"applicationProxyForIdentifier:"), nameSel = NSSelectorFromString(@"localizedName");
        id proxy = [proxyClass respondsToSelector:lookup] ? ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, lookup, bundle) : nil;
        NSString *name = [proxy respondsToSelector:nameSel] ? ((id (*)(id, SEL))objc_msgSend)(proxy, nameSel) : nil;
        return name.length ? name : bundle;
    }
    return @"None";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case RCNESectionPreview: return _previewCell;
        case RCNESectionText: return indexPath.row == 0 ? _titleCell : _messageCell;
        case RCNESectionPicture: {
            UITableViewCell *cell = [self valueCell:@"Picture" value:[self pictureName]];
            UIImage *picture = RCNEPicture(_notify.image, 29);
            cell.imageView.image = picture;
            return cell;
        }
        case RCNESectionOptions: {
            if (indexPath.row == 0) {
                UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
                cell.textLabel.text = @"Time Sensitive";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UISwitch *toggle = [[UISwitch alloc] init];
                toggle.on = _notify.urgent;
                [toggle addTarget:self action:@selector(urgentChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = toggle;
                return cell;
            }
            NSInteger s = _notify.removeAfter;
            NSString *value = s <= 0 ? @"Never" : (s % 60 == 0 ? [NSString stringWithFormat:@"%ld min", (long)(s / 60)] : [NSString stringWithFormat:@"%ld s", (long)s]);
            return [self valueCell:@"Remove After" value:value];
        }
        case RCNESectionButtons: {
            if ((NSUInteger)indexPath.row >= _buttons.count) {
                UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
                cell.textLabel.text = @"Add Button";
                cell.textLabel.textColor = self.view.tintColor;
                cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
                return cell;
            }
            NSDictionary *button = _buttons[indexPath.row];
            NSMutableArray *details = [NSMutableArray array];
            if ([button[@"red"] boolValue]) [details addObject:@"Red"];
            if ([button[@"unlock"] boolValue]) [details addObject:@"Needs Unlock"];
            UITableViewCell *cell = [self valueCell:button[@"title"] value:[details componentsJoinedByString:@", "]];
            if ([button[@"red"] boolValue]) cell.textLabel.textColor = [UIColor systemRedColor];
            return cell;
        }
    }
    return [[UITableViewCell alloc] init];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.view endEditing:YES];
    if (indexPath.section == RCNESectionPicture) [self choosePicture:[tableView cellForRowAtIndexPath:indexPath]];
    else if (indexPath.section == RCNESectionOptions && indexPath.row == 1) [self chooseRemoveAfter];
    else if (indexPath.section == RCNESectionButtons) {
        if ((NSUInteger)indexPath.row >= _buttons.count) [self nameButton:nil];
        else [self editButton:indexPath.row cell:[tableView cellForRowAtIndexPath:indexPath]];
    }
}

- (void)reloadSection:(NSInteger)section {
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark Picture, options, buttons

- (void)choosePicture:(UITableViewCell *)cell {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *current = [self->_notify.image hasPrefix:@"sf:"] ? [self->_notify.image substringFromIndex:3] : nil;
        RCSymbolPickerViewController *picker = [[RCSymbolPickerViewController alloc] initWithSelectedSymbol:current allowsNone:YES];
        picker.onPick = ^(NSString *name) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_notify.image = name.length ? [@"sf:" stringByAppendingString:name] : nil;
            [self reloadSection:RCNESectionPicture];
            [self refresh];
        };
        [self.navigationController pushViewController:picker animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"App Icon" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        RCAppPickerViewController *picker = [[RCAppPickerViewController alloc] init];
        picker.suppressAutoPop = YES;
        picker.onAppSelected = ^(NSString *name, NSString *bundleId) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_notify.image = [@"app:" stringByAppendingString:bundleId];
            [self reloadSection:RCNESectionPicture];
            [self refresh];
            [self.navigationController popToViewController:self animated:YES];
        };
        [self.navigationController pushViewController:picker animated:YES];
    }]];
    if (_notify.image.length) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"None" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_notify.image = nil;
            [self reloadSection:RCNESectionPicture];
            [self refresh];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)urgentChanged:(UISwitch *)toggle {
    _notify.urgent = toggle.on;
}

- (void)chooseRemoveAfter {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove After" message:@"Minutes until it leaves Notification Center. Leave empty to keep it." preferredStyle:UIAlertControllerStyleAlert];
    NSInteger s = _notify.removeAfter;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Minutes";
        field.keyboardType = UIKeyboardTypeDecimalPad;
        if (s > 0) field.text = s % 60 == 0 ? [NSString stringWithFormat:@"%ld", (long)(s / 60)] : [NSString stringWithFormat:@"%g", s / 60.0];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    UIAlertAction *done = [UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *text = [alert.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"," withString:@"."];
        self->_notify.removeAfter = (NSInteger)llround(MAX(0.0, text.doubleValue) * 60.0);
        [self reloadSection:RCNESectionOptions];
    }];
    [alert addAction:done];
    alert.preferredAction = done;
    [self presentViewController:alert animated:YES completion:nil];
}

// A new button (index nil) or a new name for one
- (void)nameButton:(NSNumber *)index {
    NSMutableDictionary *button = index ? _buttons[index.integerValue] : nil;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:index ? @"Rename Button" : @"New Button" message:nil preferredStyle:UIAlertControllerStyleAlert];
    NSArray *runNames = _runNames, *savedNames = _savedNames;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Name";
        field.text = button[@"title"];
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        // + inserts a variable's {name}, filled in when the notification is posted
        UIButton *insert = [UIButton buttonWithType:UIButtonTypeSystem];
        [insert setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
        insert.frame = CGRectMake(0, 0, 28, 28);
        insert.showsMenuAsPrimaryAction = YES;
        insert.accessibilityLabel = @"Insert Variable";
        __weak UITextField *weakField = field;
        insert.menu = RCVariableInsertMenu(runNames, savedNames, ^(NSString *name) {
            UITextField *f = weakField;
            UITextRange *range = f.selectedTextRange ?: [f textRangeFromPosition:f.endOfDocument toPosition:f.endOfDocument];
            [f replaceRange:range withText:[NSString stringWithFormat:@"{%@}", name]];
        });
        field.rightView = insert;
        field.rightViewMode = UITextFieldViewModeAlways;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    UIAlertAction *done = [UIAlertAction actionWithTitle:index ? @"Save" : @"Add" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!name.length) return;
        if (button) button[@"title"] = name;
        else [self->_buttons addObject:[@{ @"id": [RCNotifyCommand newID], @"title": name, @"red": @NO, @"unlock": @NO } mutableCopy]];
        [self reloadSection:RCNESectionButtons];
    }];
    [alert addAction:done];
    alert.preferredAction = done;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editButton:(NSInteger)index cell:(UITableViewCell *)cell {
    NSMutableDictionary *button = _buttons[index];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:button[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [weakSelf nameButton:@(index)];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[button[@"red"] boolValue] ? @"Not Red" : @"Red" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        button[@"red"] = @(![button[@"red"] boolValue]);
        [weakSelf reloadSection:RCNESectionButtons];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[button[@"unlock"] boolValue] ? @"Runs While Locked" : @"Needs Unlock" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        button[@"unlock"] = @(![button[@"unlock"] boolValue]);
        [weakSelf reloadSection:RCNESectionButtons];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self->_buttons removeObjectAtIndex:index];
        [self reloadSection:RCNESectionButtons];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark Save

- (void)close {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *title = [_titleField.text stringByTrimmingCharactersInSet:space];
    if (!title.length) return;
    _notify.title = title;
    _notify.message = [_messageField.text stringByTrimmingCharactersInSet:space] ?: @"";
    _notify.buttons = _buttons;
    // Its tap ID stays, so an edit keeps its Notification Tap trigger
    if (!_notify.tapID.length) _notify.tapID = [RCNotifyCommand newID];
    if (self.onSave) self.onSave(_notify.string);
    [RCAppDelegate requestNotificationPermission];
    [self close];
}

@end
