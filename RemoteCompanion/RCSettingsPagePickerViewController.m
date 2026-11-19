#import "RCSettingsPagePickerViewController.h"
#import "RCAppPickerViewController.h"
#import "RCConfigManager.h"

typedef NS_ENUM(NSInteger, RCSettingsPageSection) {
    RCSettingsPageSectionCommon = 0,
    RCSettingsPageSectionApps,
    RCSettingsPageSectionOther,
    RCSettingsPageSectionCount
};

// A row inside a Settings page: its name, an optional icon, and the rows it opens. The names are
// exactly what Settings shows on iOS 15, because the tweak taps the row with this text.
static NSArray<NSDictionary *> *RCSettingsPageTree(void) {
    static NSArray<NSDictionary *> *tree;
    if (!tree) {
        tree = @[
            @{ @"name": @"Wi-Fi", @"icon": @"wifi" },
            @{ @"name": @"Bluetooth", @"icon": @"bolt.horizontal.fill" },
            @{ @"name": @"Cellular", @"icon": @"antenna.radiowaves.left.and.right", @"children": @[
                @{ @"name": @"Cellular Data Options" },
                @{ @"name": @"Personal Hotspot" }
            ] },
            @{ @"name": @"Notifications", @"icon": @"bell.badge.fill" },
            // On iPad this row is just "Sounds"; that name can be typed under Other
            @{ @"name": @"Sounds & Haptics", @"icon": @"speaker.wave.2.fill", @"children": @[
                @{ @"name": @"Ringtone" },
                @{ @"name": @"Text Tone" },
                @{ @"name": @"New Mail" },
                @{ @"name": @"Sent Mail" },
                @{ @"name": @"Reminders" },
                @{ @"name": @"AirDrop" },
                @{ @"name": @"Keyboard Clicks" },
                @{ @"name": @"Lock Sound" }
            ] },
            @{ @"name": @"Display & Brightness", @"icon": @"sun.max.fill", @"children": @[
                @{ @"name": @"Auto-Lock" },
                @{ @"name": @"Text Size" },
                @{ @"name": @"Bold Text" }
            ] },
            @{ @"name": @"General", @"icon": @"gear", @"children": @[
                @{ @"name": @"About" },
                @{ @"name": @"Software Update" },
                @{ @"name": @"iPhone Storage" },
                @{ @"name": @"Background App Refresh" },
                @{ @"name": @"Date & Time" },
                @{ @"name": @"Keyboard" },
                @{ @"name": @"Language & Region" },
                @{ @"name": @"VPN & Device Management" },
                @{ @"name": @"Reset" },
                @{ @"name": @"Shut Down" }
            ] },
            @{ @"name": @"Battery", @"icon": @"battery.25", @"children": @[
                @{ @"name": @"Battery Health" },
                @{ @"name": @"Low Power Mode" }
            ] },
            @{ @"name": @"Privacy", @"icon": @"hand.raised.fill", @"children": @[
                @{ @"name": @"Location Services" },
                @{ @"name": @"Tracking" },
                @{ @"name": @"Analytics & Improvements" },
                @{ @"name": @"Apple Advertising" }
            ] },
            @{ @"name": @"Accessibility", @"icon": ([UIImage systemImageNamed:@"accessibility"] ? @"accessibility" : @"figure.stand"), @"children": @[
                @{ @"name": @"VoiceOver" },
                @{ @"name": @"Zoom" },
                @{ @"name": @"Display & Text Size" },
                @{ @"name": @"Motion" },
                @{ @"name": @"Spoken Content" },
                @{ @"name": @"Touch" },
                @{ @"name": @"Voice Control" },
                @{ @"name": @"Home Button" }
            ] }
        ];
    }
    return tree;
}

static NSArray<NSDictionary *> *RCChildren(NSDictionary *node) {
    NSArray *children = node[@"children"];
    return [children isKindOfClass:[NSArray class]] ? children : @[];
}

@interface RCSettingsPagePickerViewController ()
// The rows at this level, looked up from the path when the view loads
@property (nonatomic, copy) NSArray<NSDictionary *> *nodes;
// The rows above this page, outermost first, handed down by each push
@property (nonatomic, copy) NSArray<NSString *> *path;
// Editing opens on the parent of the saved page, once, so the tick is visible without hunting
@property (nonatomic, assign) BOOL restoredPath;

- (NSArray<NSDictionary *> *)nodesForPath:(NSArray<NSString *> *)path;
- (NSDictionary *)nodeNamed:(NSString *)name inNodes:(NSArray<NSDictionary *> *)nodes;
- (NSString *)trimmedLabel:(NSString *)label;
- (NSString *)joinedPath:(NSArray<NSString *> *)path;
- (BOOL)isCurrentPath:(NSArray<NSString *> *)path;
- (BOOL)isListedLabel:(NSString *)label;
- (BOOL)label:(NSString *)wanted existsInNodes:(NSArray<NSDictionary *> *)nodes prefix:(NSArray<NSString *> *)prefix;
- (void)finishWithPath:(NSArray<NSString *> *)path;
- (void)pushPageForPath:(NSArray<NSString *> *)path animated:(BOOL)animated;
- (void)restoreSavedPath;
- (void)configureCell:(UITableViewCell *)cell forNode:(NSDictionary *)node atPath:(NSArray<NSString *> *)path;
@end

@implementation RCSettingsPagePickerViewController

// Rounded inset list, like the other pickers
- (instancetype)init {
    return [self initWithPath:@[]];
}

- (instancetype)initWithPath:(NSArray<NSString *> *)path {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _path = [path copy] ?: @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.nodes = [self nodesForPath:self.path];
    self.title = self.path.count ? self.path.lastObject : @"Settings Page";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = 52;

    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.restoredPath || self.path.count) return;
    self.restoredPath = YES;
    [self restoreSavedPath];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - The tree

- (NSArray<NSDictionary *> *)nodesForPath:(NSArray<NSString *> *)path {
    NSArray<NSDictionary *> *nodes = RCSettingsPageTree();
    for (NSString *name in path) {
        NSDictionary *match = [self nodeNamed:name inNodes:nodes];
        if (!match) return @[];
        nodes = RCChildren(match);
    }
    return nodes;
}

- (NSDictionary *)nodeNamed:(NSString *)name inNodes:(NSArray<NSDictionary *> *)nodes {
    for (NSDictionary *node in nodes) {
        if ([node[@"name"] caseInsensitiveCompare:name] == NSOrderedSame) return node;
    }
    return nil;
}

- (NSString *)trimmedLabel:(NSString *)label {
    return [label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)joinedPath:(NSArray<NSString *> *)path {
    return [path componentsJoinedByString:@" > "];
}

// The full path from the top, e.g. "General > About", matches the page the action uses now
- (BOOL)isCurrentPath:(NSArray<NSString *> *)path {
    NSString *saved = [self trimmedLabel:self.currentLabel];
    if (!saved.length || !path.count) return NO;
    return [[self joinedPath:path] caseInsensitiveCompare:saved] == NSOrderedSame;
}

// Whether this label is any row in the tree, at any depth (a leaf or a page with rows under it)
- (BOOL)isListedLabel:(NSString *)label {
    NSString *wanted = [self trimmedLabel:label];
    if (!wanted.length) return NO;
    return [self label:wanted existsInNodes:RCSettingsPageTree() prefix:@[]];
}

- (BOOL)label:(NSString *)wanted existsInNodes:(NSArray<NSDictionary *> *)nodes prefix:(NSArray<NSString *> *)prefix {
    for (NSDictionary *node in nodes) {
        NSArray<NSString *> *path = [prefix arrayByAddingObject:node[@"name"]];
        if ([[self joinedPath:path] caseInsensitiveCompare:wanted] == NSOrderedSame) return YES;
        if ([self label:wanted existsInNodes:RCChildren(node) prefix:path]) return YES;
    }
    return NO;
}

#pragma mark - Choosing

// A picked page hands the whole path to the caller. Pushed inside Select Action, that screen
// closes the whole picker; presented on its own when editing, this nav closes itself first.
- (void)finishWithPath:(NSArray<NSString *> *)path {
    NSString *chosen = [self trimmedLabel:[self joinedPath:path]];
    if (!chosen.length) return;
    void (^select)(NSString *) = self.onSelect;
    UINavigationController *nav = self.navigationController;
    UIViewController *root = nav.viewControllers.firstObject;
    // Presented to edit an action: the first screen of the nav is this picker. Pushed inside
    // Select Action: the first screen is the action picker, which closes the flow itself.
    BOOL presented = root ? (nav.presentingViewController != nil && [root isKindOfClass:[RCSettingsPagePickerViewController class]])
                          : (self.presentingViewController != nil);
    if (presented) {
        [nav ?: self dismissViewControllerAnimated:YES completion:^{
            if (select) select(chosen);
        }];
        return;
    }
    if (select) select(chosen);
}

- (void)pushPageForPath:(NSArray<NSString *> *)path animated:(BOOL)animated {
    RCSettingsPagePickerViewController *child = [[RCSettingsPagePickerViewController alloc] initWithPath:path];
    child.currentLabel = self.currentLabel;
    child.onSelect = self.onSelect;
    [self.navigationController pushViewController:child animated:animated];
}

// Editing "General > About" opens on General with About ticked, so the saved page is visible
// instead of buried. Only follows rows that exist in the tree.
- (void)restoreSavedPath {
    NSString *saved = [self trimmedLabel:self.currentLabel];
    if (![self isListedLabel:saved]) return;
    NSArray<NSString *> *parts = [saved componentsSeparatedByString:@" > "];
    if (parts.count < 2) return;

    NSMutableArray<NSString *> *canonical = [NSMutableArray array];
    NSArray<NSDictionary *> *nodes = RCSettingsPageTree();
    for (NSString *part in parts) {
        NSDictionary *match = [self nodeNamed:[self trimmedLabel:part] inNodes:nodes];
        if (!match) return;
        [canonical addObject:match[@"name"]];
        nodes = RCChildren(match);
    }
    for (NSUInteger depth = 1; depth < canonical.count; depth++) {
        [self pushPageForPath:[canonical subarrayWithRange:NSMakeRange(0, depth)] animated:NO];
    }
}

// An app's Settings page shows the app's name. Every installed app is listed: a page can come
// from a Settings.bundle, a jailbreak preference bundle, or the Settings app's own list, so
// there is no reliable way to ask which apps have one. A name with no row finds nothing.
- (void)presentAppPicker {
    RCAppPickerViewController *picker = [[RCAppPickerViewController alloc] init];
    picker.title = @"App";
    picker.suppressAutoPop = YES; // the app list is dismissed here, then the name is handed on
    picker.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelAppPicker)];
    __weak typeof(self) weakSelf = self;
    picker.onAppSelected = ^(NSString *name, __unused NSString *bundleId) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf dismissViewControllerAnimated:YES completion:^{
            [strongSelf finishWithPath:@[name]];
        }];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)cancelAppPicker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)promptForName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Settings Page"
                                                                   message:@"The row name as the Settings app shows it."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Wi-Fi";
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.returnKeyType = UIReturnKeyDone;
        // Editing a page that came from an app or from typing starts with that name
        NSString *saved = [weakSelf trimmedLabel:weakSelf.currentLabel];
        if (saved.length && ![weakSelf isListedLabel:saved]) textField.text = saved;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *open = [UIAlertAction actionWithTitle:@"Open" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text;
        // Close the alert first, so closing the picker afterwards dismisses the picker and not the alert
        [alert dismissViewControllerAnimated:NO completion:^{
            [weakSelf finishWithPath:(text.length ? @[text] : @[])];
        }];
    }];
    [alert addAction:open];
    alert.preferredAction = open;
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // A pushed page shows only the rows under it
    return self.path.count ? 1 : RCSettingsPageSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.path.count || section == RCSettingsPageSectionCommon) return self.nodes.count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.path.count) return nil;
    if (section == RCSettingsPageSectionCommon) return @"Common Pages";
    if (section == RCSettingsPageSectionApps) return @"Apps";
    return @"Other";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.path.count) return nil;
    if (section == RCSettingsPageSectionApps) return @"Apps without a Settings page have no row to find.";
    return nil;
}

- (void)configureCell:(UITableViewCell *)cell forNode:(NSDictionary *)node atPath:(NSArray<NSString *> *)path {
    cell.textLabel.text = node[@"name"];
    NSString *icon = node[@"icon"];
    cell.imageView.image = icon.length ? [UIImage systemImageNamed:icon] : nil;

    NSArray<NSString *> *fullPath = [path arrayByAddingObject:node[@"name"]];
    if ([self isCurrentPath:fullPath]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else if (RCChildren(node).count > 0) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.imageView.tintColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    // Rows under a pushed page: the children of the page that was tapped
    if (self.path.count) {
        [self configureCell:cell forNode:self.nodes[indexPath.row] atPath:self.path];
        return cell;
    }

    if (indexPath.section == RCSettingsPageSectionCommon) {
        [self configureCell:cell forNode:self.nodes[indexPath.row] atPath:@[]];
        return cell;
    }

    if (indexPath.section == RCSettingsPageSectionApps) {
        cell.textLabel.text = @"Choose an App...";
        cell.imageView.image = [UIImage systemImageNamed:@"square.grid.2x2.fill"];
    } else {
        cell.textLabel.text = @"Type a Name...";
        cell.imageView.image = [UIImage systemImageNamed:@"keyboard"];
        // A name that is not a listed page came from an app or from typing it
        NSString *saved = [self trimmedLabel:self.currentLabel];
        if (saved.length && ![self isListedLabel:saved]) cell.detailTextLabel.text = saved;
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.path.count && indexPath.section == RCSettingsPageSectionApps) {
        [self presentAppPicker];
        return;
    }
    if (!self.path.count && indexPath.section == RCSettingsPageSectionOther) {
        [self promptForName];
        return;
    }

    NSDictionary *node = self.nodes[indexPath.row];
    NSArray<NSString *> *fullPath = [self.path arrayByAddingObject:node[@"name"]];
    // A row with rows under it drills down; a leaf is the page itself
    if (RCChildren(node).count > 0) {
        [self pushPageForPath:fullPath animated:YES];
        return;
    }
    [self finishWithPath:fullPath];
}

@end
