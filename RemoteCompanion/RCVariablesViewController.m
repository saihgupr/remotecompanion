#import "RCVariablesViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

@interface RCVariablesViewController ()
@property (nonatomic, strong) NSArray<NSString *> *names;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *values;
@property (nonatomic, assign) BOOL loaded;
- (void)reload;
@end

// The tweak posts this after the saved variables change
static void RCVariablesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    RCVariablesViewController *controller = (__bridge RCVariablesViewController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{ [controller reload]; });
}

@implementation RCVariablesViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Variables";
        _names = @[];
        _values = @{};
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, CFSTR("com.pizzaman.rc.variables_changed"), NULL);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addVariable)];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, RCVariablesChanged,
                                    CFSTR("com.pizzaman.rc.variables_changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"var list" completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.refreshControl endRefreshing];
            if (![parsed isKindOfClass:[NSDictionary class]]) return; // the tweak didn't answer: keep what's shown
            strongSelf.values = parsed;
            strongSelf.names = [[parsed allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
            strongSelf.loaded = YES;
            [strongSelf.tableView reloadData];
        });
    }];
}

// One command; the page reloads when it's done
- (void)send:(NSString *)command {
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reload]; });
    }];
}

static BOOL RCVariableNameAllowed(NSString *name) {
    if (name.length == 0 || name.length > 40 || [name isEqualToString:@"round"]) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    if ([name rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return NO;
    return ![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[name characterAtIndex:0]];
}

// A new variable (name nil) or a new value for one
- (void)editVariable:(NSString *)name {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name ?: @"New Variable"
                                                                   message:name ? nil : @"Letters, digits and _, not starting with a digit."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    if (!name) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Name";
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            textField.spellCheckingType = UITextSpellCheckingTypeNo;
        }];
    }
    NSString *current = name ? self.values[name] : nil;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Value";
        textField.text = current;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.spellCheckingType = UITextSpellCheckingTypeNo;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        NSString *variable = name ?: [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *value = [alert.textFields.lastObject.text stringByReplacingOccurrencesOfString:@"\n" withString:@" "] ?: @"";
        if (!RCVariableNameAllowed(variable)) {
            UIAlertController *refused = [UIAlertController alertControllerWithTitle:@"Name Not Allowed"
                                                                             message:@"Use letters, digits and _, without spaces, not starting with a digit. \"round\" is reserved."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            [refused addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf presentViewController:refused animated:YES completion:nil];
            return;
        }
        [weakSelf send:[NSString stringWithFormat:@"var set %@ %@", variable, value]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addVariable {
    [self editVariable:nil];
}

#pragma mark - Rows

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.names.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Set Variable actions save variables here, for all triggers. In an action's text, {name} becomes the value. Tap one to change it; swipe to delete.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    if (!self.names.count) {
        cell.textLabel.text = self.loaded ? @"No Variables" : @"Loading…";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSString *name = self.names[indexPath.row];
    NSString *value = [self.values[name] description];
    cell.textLabel.text = name;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightRegular];
    cell.detailTextLabel.text = value.length ? value : @"No value";
    cell.detailTextLabel.textColor = value.length ? [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor];
    cell.detailTextLabel.numberOfLines = 3;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.names.count) [self editVariable:self.names[indexPath.row]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.names.count) return nil;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(__unused UIContextualAction *action, __unused UIView *view, void (^done)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { done(NO); return; }
        NSString *name = strongSelf.names[indexPath.row];
        // Gone from the list at once; the tweak catches up
        NSMutableDictionary *values = [strongSelf.values mutableCopy];
        [values removeObjectForKey:name];
        strongSelf.values = values;
        NSMutableArray *names = [strongSelf.names mutableCopy];
        [names removeObjectAtIndex:indexPath.row];
        strongSelf.names = names;
        if (names.count) [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        else [tableView reloadData];
        done(YES);
        [strongSelf send:[@"var delete " stringByAppendingString:name]];
    }];
    delete.image = [UIImage systemImageNamed:@"trash.fill"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

@end
