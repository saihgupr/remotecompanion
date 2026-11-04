#import "RCGesturesViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCGestureDetailViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Top: Record New Gesture. Then the recording tab's options (Show Stop After, Tab Size),
// then the gestures (or one status row), so neither gets lost below a long list.
typedef NS_ENUM(NSInteger, RCGestureSection) {
    RCGestureSectionTop,
    RCGestureSectionOptions,
    RCGestureSectionList,
};

@interface RCGesturesViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *gestures; // @{ name, duration, strokes }
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *errorText;
@property (nonatomic, assign) BOOL waitingForRecording;
@property (nonatomic, assign) double idleStop; // Show Stop After, in seconds (0: never)
@property (nonatomic, copy) NSString *tabSize; // Tab Size: small, medium or large
@property (nonatomic, assign) BOOL stopOnTouch; // Stop on Touch: a touch stops a playing gesture
@property (nonatomic, strong) UIBarButtonItem *clearButton;     // Select mode's Clear, bottom right
@property (nonatomic, strong) UIBarButtonItem *selectAllButton; // and Select All, bottom left
@property (nonatomic, strong) UIBarButtonItem *exportButton;    // and Export, in the middle
@property (nonatomic, strong) UIBarButtonItem *moreButton;      // the ⋯ menu, top right
@property (nonatomic, weak) RCGestureDetailViewController *detail; // a gesture's page, when open
@end

@implementation RCGesturesViewController

+ (NSString *)commandForGesture:(NSString *)name {
    return [self commandForGesture:name speed:1];
}

+ (NSString *)speedSuffix:(double)speed {
    return fabs(speed - 1) < 0.01 || speed <= 0 ? @"" : [NSString stringWithFormat:@" %gx", speed];
}

+ (NSString *)commandForGesture:(NSString *)name speed:(double)speed {
    if (name.length == 0) return [@"gesture play-latest" stringByAppendingString:[self speedSuffix:speed]];
    return [NSString stringWithFormat:@"gesture play \"%@\"%@", name, [self speedSuffix:speed]];
}

// What follows "gesture play": the quoted name, then the speed
+ (NSString *)playArgumentsOf:(NSString *)command speed:(NSString **)speedOut {
    if (speedOut) *speedOut = nil;
    if (![command isKindOfClass:[NSString class]]) return nil;
    NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
    if ([command isEqualToString:@"gesture play-latest"] || [command hasPrefix:@"gesture play-latest "]) {
        if (speedOut) *speedOut = [[command substringFromIndex:19] stringByTrimmingCharactersInSet:space];
        return @"";
    }
    if (![command hasPrefix:@"gesture play "]) return nil;
    NSString *rest = [[command substringFromIndex:13] stringByTrimmingCharactersInSet:space];
    if ([rest hasPrefix:@"\""] && rest.length > 1) {
        NSRange close = [rest rangeOfString:@"\"" options:0 range:NSMakeRange(1, rest.length - 1)];
        if (close.location != NSNotFound) {
            if (speedOut) *speedOut = [[rest substringFromIndex:close.location + 1] stringByTrimmingCharactersInSet:space];
            return [rest substringWithRange:NSMakeRange(1, close.location - 1)];
        }
    }
    return rest;
}

+ (NSString *)gestureForCommand:(NSString *)command {
    return [self playArgumentsOf:command speed:NULL];
}

+ (double)speedForCommand:(NSString *)command {
    NSString *speed = nil;
    [self playArgumentsOf:command speed:&speed];
    double value = [[speed.lowercaseString stringByReplacingOccurrencesOfString:@"x" withString:@""] doubleValue];
    return value > 0 ? value : 1;
}

+ (NSString *)titleForSpeed:(double)speed {
    return [NSString stringWithFormat:@"%g\u00D7", speed];
}

// The speeds a Play Gesture action offers
+ (NSArray<NSNumber *> *)speeds {
    return @[@0.5, @1, @1.5, @2, @3];
}

+ (NSString *)recordCommand {
    return @"gesture record-toggle";
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _gestures = @[];
        // The settings as last seen, so the rows don't show defaults until the tweak answers
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _idleStop = [defaults doubleForKey:@"RCGestureIdleStop"];
        _tabSize = [defaults stringForKey:@"RCGestureTabSize"];
        _stopOnTouch = [defaults objectForKey:@"RCGestureStopOnTouch"] ? [defaults boolForKey:@"RCGestureStopOnTouch"] : YES;
        self.title = @"Gestures";
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setIdleStop:(double)idleStop {
    _idleStop = idleStop;
    [[NSUserDefaults standardUserDefaults] setDouble:idleStop forKey:@"RCGestureIdleStop"];
}

- (void)setStopOnTouch:(BOOL)stopOnTouch {
    _stopOnTouch = stopOnTouch;
    [[NSUserDefaults standardUserDefaults] setBool:stopOnTouch forKey:@"RCGestureStopOnTouch"];
}

- (void)stopOnTouchChanged:(UISwitch *)toggle {
    self.stopOnTouch = toggle.on;
    NSString *command = toggle.on ? @"gesture stop-on-touch on" : @"gesture stop-on-touch off";
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error || !output) return;
        strongSelf.stopOnTouch = [output hasPrefix:@"on"];
        toggle.on = strongSelf.stopOnTouch;
    }];
}

- (void)setTabSize:(NSString *)tabSize {
    _tabSize = [tabSize copy];
    if (tabSize) [[NSUserDefaults standardUserDefaults] setObject:tabSize forKey:@"RCGestureTabSize"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = 56;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    }
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    [self.tableView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)]];
    [self updateSelectButtons];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self reload];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.tableView.editing) [self endSelecting];
}

#pragma mark - Loading

- (void)reload {
    [self reloadThen:nil];
}

- (void)reloadThen:(void (^)(void))done {
    self.loading = self.gestures.count == 0;
    self.errorText = nil;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"gesture list" completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.loading = NO;
        [strongSelf.refreshControl endRefreshing];
        if (error || !output) {
            strongSelf.errorText = error.localizedDescription ?: @"Couldn't fetch the gestures";
        } else {
            NSMutableArray *list = [NSMutableArray array];
            for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count < 3 || [parts[0] length] == 0) continue;
                [list addObject:@{ @"name": parts[0], @"duration": @([parts[1] doubleValue]), @"strokes": @([parts[2] integerValue]) }];
            }
            if (output.length && list.count == 0 && [output hasPrefix:@"Error"]) strongSelf.errorText = output;
            strongSelf.gestures = list;
        }
        [strongSelf.tableView reloadData];
        if (strongSelf.tableView.editing && strongSelf.gestures.count == 0) [strongSelf endSelecting];
        [strongSelf updateSelectButtons];
        if (done) done();
    }];
    [[RCServerClient sharedClient] executeCommand:@"gesture idle-stop" completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error || !output) return;
        strongSelf.idleStop = [output doubleValue];
        [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCGestureSectionOptions] withRowAnimation:UITableViewRowAnimationNone];
    }];
    [[RCServerClient sharedClient] executeCommand:@"gesture stop-on-touch" completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error || !output || [output hasPrefix:@"Error"]) return;
        strongSelf.stopOnTouch = [output hasPrefix:@"on"];
        [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCGestureSectionOptions] withRowAnimation:UITableViewRowAnimationNone];
    }];
    [[RCServerClient sharedClient] executeCommand:@"gesture tab-size" completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error || !output) return;
        NSString *size = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![[strongSelf tabSizes] containsObject:size]) return;
        strongSelf.tabSize = size;
        [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCGestureSectionOptions] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (NSDictionary *)gestureNamed:(NSString *)name {
    for (NSDictionary *g in self.gestures) {
        if ([g[@"name"] caseInsensitiveCompare:name] == NSOrderedSame) return g;
    }
    return nil;
}

#pragma mark - Rows

- (BOOL)showsStatusRow {
    return self.loading || self.errorText || self.gestures.count == 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RCGestureSectionTop) return 1;
    if (section == RCGestureSectionOptions) return 3;
    return [self showsStatusRow] ? 1 : self.gestures.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == RCGestureSectionOptions) return @"Settings";
    if (section == RCGestureSectionList) return @"Saved Gestures";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCGestureSectionOptions) return @"While recording, a red tab sits at the screen's edge. Pull it out to show Stop. Show Stop After brings Stop out by itself after a time without a touch. Stop on Touch stops a playing gesture when you touch the screen.";
    if (section != RCGestureSectionTop) return nil;
    return @"Recording starts after a short countdown. Use the phone as usual, then tap Stop. Touches play back with the same timing, so start from the screen the gesture begins on.";
}

- (NSDictionary *)gestureAtRow:(NSInteger)row {
    return row >= 0 && row < (NSInteger)self.gestures.count ? self.gestures[row] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.imageView.tintColor = [UIColor secondaryLabelColor];

    if (indexPath.section == RCGestureSectionOptions && indexPath.row == 2) {
        cell.textLabel.text = @"Stop on Touch";
        cell.imageView.image = [UIImage systemImageNamed:@"hand.raised"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = self.stopOnTouch;
        [toggle addTarget:self action:@selector(stopOnTouchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }
    if (indexPath.section == RCGestureSectionOptions) {
        UITableViewCell *value = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        value.backgroundColor = cell.backgroundColor;
        value.selectedBackgroundView = cell.selectedBackgroundView;
        BOOL size = indexPath.row == 1;
        value.textLabel.text = size ? @"Tab Size" : @"Show Stop After";
        value.textLabel.textColor = [UIColor labelColor];
        value.detailTextLabel.text = size ? [self tabSizeTitle:self.tabSize] : [self idleStopTitle:self.idleStop];
        value.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        value.imageView.image = [UIImage systemImageNamed:size ? @"arrow.up.left.and.arrow.down.right" : @"stop.circle"];
        value.imageView.tintColor = [UIColor secondaryLabelColor];
        value.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return value;
    }
    if (indexPath.section == RCGestureSectionTop) {
        cell.textLabel.text = @"Record New Gesture";
        cell.textLabel.textColor = self.view.tintColor;
        cell.imageView.image = [UIImage systemImageNamed:@"record.circle"];
        cell.imageView.tintColor = [UIColor systemRedColor];
        return cell;
    }

    NSDictionary *g = [self gestureAtRow:indexPath.row];
    if (!g) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.numberOfLines = 0;
        if (self.loading) {
            cell.textLabel.text = @"Loading Gestures…";
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        } else {
            cell.textLabel.text = self.errorText ?: @"No Gestures";
        }
        return cell;
    }
    cell.textLabel.text = g[@"name"];
    cell.imageView.image = [UIImage systemImageNamed:@"hand.draw.fill"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    NSInteger strokes = [g[@"strokes"] integerValue];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld %@, %.1f s", (long)strokes, strokes == 1 ? @"Touch" : @"Touches", [g[@"duration"] doubleValue]];
    return cell;
}

// Only recorded gestures can be selected or swiped
- (BOOL)isSavedGestureAt:(NSIndexPath *)indexPath {
    if (indexPath.section != RCGestureSectionList) return NO;
    return [self gestureAtRow:indexPath.row] != nil;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isSavedGestureAt:indexPath];
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView.editing) return [self isSavedGestureAt:indexPath];
    return indexPath.section != RCGestureSectionList || [self gestureAtRow:indexPath.row] != nil;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView.editing && ![self isSavedGestureAt:indexPath]) return nil;
    return indexPath;
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView.editing) [self updateSelectButtons];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView.editing) {
        [self updateSelectButtons];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == RCGestureSectionOptions) {
        if (indexPath.row == 2) return;
        UIView *source = [tableView cellForRowAtIndexPath:indexPath];
        if (indexPath.row == 1) [self chooseTabSizeFromView:source];
        else [self chooseIdleStopFromView:source];
        return;
    }
    if (indexPath.section == RCGestureSectionTop) {
        [self askNameAndRecord];
        return;
    }
    NSDictionary *g = [self gestureAtRow:indexPath.row];
    if (!g) return;
    [self openGesture:g[@"name"]];
}

// Alerts and sheets show over a gesture's page when it's open
- (UIViewController *)presenter {
    UIViewController *top = self.navigationController.topViewController;
    return top.view.window ? top : self;
}

- (void)openGesture:(NSString *)name {
    RCGestureDetailViewController *detail = [[RCGestureDetailViewController alloc] init];
    detail.name = name;
    __weak typeof(self) weakSelf = self;
    __weak RCGestureDetailViewController *weakDetail = detail;
    detail.onAction = ^(NSString *action, UIView *source) {
        NSString *current = weakDetail.name;
        if ([action isEqualToString:@"play"]) [weakSelf play:current];
        else if ([action isEqualToString:@"record"]) [weakSelf confirmReplaceRecording:current];
        else if ([action isEqualToString:@"rename"]) [weakSelf askRename:current];
        else if ([action isEqualToString:@"export"]) [weakSelf exportGestures:@[current] fromView:source];
        else if ([action isEqualToString:@"delete"]) [weakSelf confirmDelete:current];
    };
    detail.onChange = ^{ [weakSelf reload]; };
    self.detail = detail;
    [self.navigationController pushViewController:detail animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView.editing || ![self isSavedGestureAt:indexPath]) return nil;
    NSDictionary *g = [self gestureAtRow:indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        [weakSelf confirmDelete:g[@"name"]];
        done(YES);
    }];
    UIContextualAction *more = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"More"
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        [weakSelf showOptionsForGesture:g[@"name"] fromView:[tableView cellForRowAtIndexPath:indexPath]];
        done(YES);
    }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    more.image = [UIImage systemImageNamed:@"ellipsis.circle"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete, more]];
}

#pragma mark - Select

// Select (top right, outside picking; Cancel there while selecting): check gestures, then Clear
// them at the bottom right. Select All, bottom left, checks them all (or none again).
- (NSInteger)selectedCount {
    NSInteger count = 0;
    for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) if ([self isSavedGestureAt:path]) count++;
    return count;
}

- (void)updateSelectButtons {
    if (self.tableView.editing) {
        if (self.navigationItem.rightBarButtonItem.action != @selector(endSelecting)) {
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(endSelecting)];
        }
        NSInteger count = [self selectedCount];
        BOOL allChecked = count > 0 && count == (NSInteger)self.gestures.count;
        self.selectAllButton.title = allChecked ? @"Deselect All" : @"Select All";
        self.clearButton.title = count ? [NSString stringWithFormat:@"Clear (%ld)", (long)count] : @"Clear";
        self.clearButton.enabled = count > 0;
        self.exportButton.enabled = count > 0;
        return;
    }
    // The same button throughout (shown at once, before the list loads); only its menu changes
    if (!self.moreButton) self.moreButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[self moreMenu]];
    else self.moreButton.menu = [self moreMenu];
    if (self.navigationItem.rightBarButtonItem != self.moreButton) self.navigationItem.rightBarButtonItem = self.moreButton;
}

// The ⋯ menu: Select, Import, Export All
- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;
    NSMutableArray *items = [NSMutableArray array];
    if (self.gestures.count) {
        [items addObject:[UIAction actionWithTitle:@"Select" image:[UIImage systemImageNamed:@"checkmark.circle"] identifier:nil handler:^(UIAction *a) { [weakSelf startSelecting]; }]];
    }
    [items addObject:[UIAction actionWithTitle:@"Import" image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(UIAction *a) { [weakSelf importGestures]; }]];
    if (self.gestures.count) {
        [items addObject:[UIAction actionWithTitle:@"Export All" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *a) {
            NSMutableArray *names = [NSMutableArray array];
            for (NSDictionary *g in weakSelf.gestures) [names addObject:g[@"name"]];
            [weakSelf exportGestures:names fromView:nil];
        }]];
    }
    return [UIMenu menuWithTitle:@"" children:items];
}

// A long press on a gesture starts Select with it checked
- (void)longPressed:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan || self.tableView.editing) return;
    NSIndexPath *path = [self.tableView indexPathForRowAtPoint:[press locationInView:self.tableView]];
    if (!path || ![self isSavedGestureAt:path]) return;
    [self startSelecting];
    [self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
    [self updateSelectButtons];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
}

- (void)startSelecting {
    if (self.gestures.count == 0) return;
    [self.tableView setEditing:YES animated:YES];
    self.selectAllButton = [[UIBarButtonItem alloc] initWithTitle:@"Select All" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectAll)];
    self.clearButton = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(confirmClear)];
    self.clearButton.tintColor = [UIColor systemRedColor];
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.exportButton = [[UIBarButtonItem alloc] initWithTitle:@"Export" style:UIBarButtonItemStylePlain target:self action:@selector(exportSelected)];
    UIBarButtonItem *space2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbarItems = @[self.selectAllButton, space, self.exportButton, space2, self.clearButton];
    [self.navigationController setToolbarHidden:NO animated:YES];
    [self updateSelectButtons];
}

- (void)endSelecting {
    [self.tableView setEditing:NO animated:YES];
    [self.navigationController setToolbarHidden:YES animated:YES];
    self.toolbarItems = nil;
    [self updateSelectButtons];
}

- (void)toggleSelectAll {
    BOOL allChecked = [self selectedCount] == (NSInteger)self.gestures.count;
    NSInteger rows = [self.tableView numberOfRowsInSection:RCGestureSectionList];
    for (NSInteger row = 0; row < rows; row++) {
        NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:RCGestureSectionList];
        if (![self isSavedGestureAt:path]) continue;
        if (allChecked) [self.tableView deselectRowAtIndexPath:path animated:NO];
        else [self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self updateSelectButtons];
}

- (void)confirmClear {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) {
        if ([self isSavedGestureAt:path]) [names addObject:[self gestureAtRow:path.row][@"name"]];
    }
    if (names.count == 0) return;
    BOOL all = names.count == self.gestures.count;
    NSString *title = all ? @"Clear All Gestures?"
        : names.count == 1 ? @"Clear Gesture?" : [NSString stringWithFormat:@"Clear %lu Gestures?", (unsigned long)names.count];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:names.count == 1 ? @"Actions that play it stop working." : @"Actions that play them stop working."
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [weakSelf deleteGestures:names];
    }]];
    [[self presenter] presentViewController:alert animated:YES completion:nil];
}

// One at a time, then the list again
- (void)deleteGestures:(NSArray<NSString *> *)names {
    if (names.count == 0) {
        [self endSelecting];
        [self reload];
        return;
    }
    NSString *command = [NSString stringWithFormat:@"gesture delete \"%@\"", names.firstObject];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        [weakSelf deleteGestures:[names subarrayWithRange:NSMakeRange(1, names.count - 1)]];
    }];
}

#pragma mark - Export and Import

- (void)exportSelected {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) {
        if ([self isSavedGestureAt:path]) [names addObject:[self gestureAtRow:path.row][@"name"]];
    }
    if (names.count) [self exportGestures:names fromView:nil];
}

// The tweak writes the gestures to a JSON file, then the share sheet sends it on
- (void)exportGestures:(NSArray<NSString *> *)names fromView:(UIView *)source {
    NSString *fileName = @"Gestures";
    if (names.count == 1) {
        NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/:\\"];
        fileName = [[names.firstObject componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"-"];
    }
    NSString *path = [@"/tmp" stringByAppendingPathComponent:[fileName stringByAppendingPathExtension:@"json"]];
    NSMutableString *command = [NSMutableString stringWithFormat:@"gesture export \"%@\"", path];
    for (NSString *name in names) [command appendFormat:@" \"%@\"", name];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || ![output hasPrefix:@"Exported"]) {
            [strongSelf showMessage:@"Couldn't Export" detail:error.localizedDescription ?: [output stringByReplacingOccurrencesOfString:@"Error: " withString:@""]];
            return;
        }
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
        UIView *anchor = source ?: strongSelf.view;
        share.popoverPresentationController.sourceView = anchor;
        share.popoverPresentationController.sourceRect = anchor.bounds;
        if (!source && strongSelf.exportButton) share.popoverPresentationController.barButtonItem = strongSelf.exportButton;
        share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *shareError) {
            if (completed && strongSelf.tableView.editing) [strongSelf endSelecting];
        };
        [[strongSelf presenter] presentViewController:share animated:YES completion:nil];
    }];
}

- (void)importGestures {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON]];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [[self presenter] presentViewController:picker animated:YES completion:nil];
}

// Each file is copied where the tweak can read it, then added one after another
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in urls) {
        BOOL accessing = [url startAccessingSecurityScopedResource];
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (accessing) [url stopAccessingSecurityScopedResource];
        if (!data) continue;
        NSString *path = [NSString stringWithFormat:@"/tmp/rc-gesture-import-%lu.json", (unsigned long)paths.count];
        if ([data writeToFile:path atomically:YES]) [paths addObject:path];
    }
    if (!paths.count) {
        [self showMessage:@"Couldn't Import" detail:@"The file couldn't be read."];
        return;
    }
    [self importPaths:paths imported:0 failure:nil];
}

- (void)importPaths:(NSArray<NSString *> *)paths imported:(NSInteger)imported failure:(NSString *)failure {
    if (paths.count == 0) {
        [self reload];
        if (imported) {
            [self showMessage:imported == 1 ? @"Imported 1 Gesture" : [NSString stringWithFormat:@"Imported %ld Gestures", (long)imported] detail:nil];
        } else {
            [self showMessage:@"Couldn't Import" detail:failure ?: @"No gestures were found in the file."];
        }
        return;
    }
    NSString *path = paths.firstObject;
    NSArray *rest = [paths subarrayWithRange:NSMakeRange(1, paths.count - 1)];
    NSString *command = [NSString stringWithFormat:@"gesture import \"%@\"", path];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        NSInteger added = [output hasPrefix:@"Imported "] ? [[output substringFromIndex:9] integerValue] : 0;
        NSString *problem = added ? failure : (error.localizedDescription ?: [output stringByReplacingOccurrencesOfString:@"Error: " withString:@""]);
        [weakSelf importPaths:rest imported:imported + added failure:problem];
    }];
}

#pragma mark - Show Stop After

- (NSString *)idleStopTitle:(double)seconds {
    return seconds <= 0 ? @"Never" : [NSString stringWithFormat:@"%.0f Seconds", seconds];
}

- (void)chooseIdleStopFromView:(UIView *)source {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Show Stop After" message:@"Time without a touch before the Stop button comes out by itself."
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *choice in @[@0, @3, @5, @10, @30]) {
        double seconds = choice.doubleValue;
        NSString *title = [self idleStopTitle:seconds];
        if (fabs(seconds - self.idleStop) < 0.5) title = [title stringByAppendingString:@" \u2713"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSString *command = [NSString stringWithFormat:@"gesture idle-stop %g", seconds];
            [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                if (!error && output) strongSelf.idleStop = [output doubleValue];
                [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCGestureSectionOptions] withRowAnimation:UITableViewRowAnimationNone];
            }];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = source ?: self.view;
    sheet.popoverPresentationController.sourceRect = source ? source.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [[self presenter] presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Tab Size

- (NSArray<NSString *> *)tabSizes {
    return @[@"small", @"medium", @"large"];
}

- (NSString *)tabSizeTitle:(NSString *)size {
    return (size ?: @"medium").capitalizedString;
}

- (void)chooseTabSizeFromView:(UIView *)source {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Tab Size" message:@"Size of the red tab shown while recording."
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSString *size in [self tabSizes]) {
        NSString *title = [self tabSizeTitle:size];
        if ([size isEqualToString:self.tabSize ?: @"medium"]) title = [title stringByAppendingString:@" \u2713"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSString *command = [@"gesture tab-size " stringByAppendingString:size];
            [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                NSString *now = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (!error && [[strongSelf tabSizes] containsObject:now]) strongSelf.tabSize = now;
                [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCGestureSectionOptions] withRowAnimation:UITableViewRowAnimationNone];
            }];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = source ?: self.view;
    sheet.popoverPresentationController.sourceRect = source ? source.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [[self presenter] presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Gesture options

- (void)showOptionsForGesture:(NSString *)name fromView:(UIView *)source {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    BOOL exists = [self gestureNamed:name] != nil;
    if (exists) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Play" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf play:name]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:exists ? @"Replace Recording" : @"Record" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (exists) [weakSelf confirmReplaceRecording:name];
        else [weakSelf record:name];
    }]];
    if (exists) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf askRename:name]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Export" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf exportGestures:@[name] fromView:source]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [weakSelf confirmDelete:name]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = source ?: self.view;
    sheet.popoverPresentationController.sourceRect = source ? source.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [[self presenter] presentViewController:sheet animated:YES completion:nil];
}

// A name without double quotes (they mark the name in the action)
- (NSString *)cleanName:(NSString *)text {
    NSString *name = [[text stringByReplacingOccurrencesOfString:@"\"" withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return name;
}

- (NSString *)suggestedName {
    for (NSInteger n = 1; ; n++) {
        NSString *name = [NSString stringWithFormat:@"Gesture %ld", (long)n];
        if (![self gestureNamed:name]) return name;
    }
}

- (void)askNameAndRecord {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Gesture" message:nil preferredStyle:UIAlertControllerStyleAlert];
    NSString *suggested = [self suggestedName];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = suggested;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Record" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *name = [strongSelf cleanName:alert.textFields.firstObject.text];
        if (name.length == 0) name = suggested;
        if ([strongSelf gestureNamed:name]) {
            [strongSelf confirmReplace:name];
            return;
        }
        [strongSelf record:name];
    }]];
    [[self presenter] presentViewController:alert animated:YES completion:nil];
}

- (void)confirmReplace:(NSString *)name {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Replace Gesture?"
        message:[NSString stringWithFormat:@"A gesture named “%@” already exists. A new recording replaces it.", name]
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [weakSelf record:name]; }]];
    [[self presenter] presentViewController:alert animated:YES completion:nil];
}

// The app steps aside; the tweak counts down, records until Stop and opens the app again
- (void)record:(NSString *)name {
    NSString *command = [NSString stringWithFormat:@"gesture record \"%@\" return", name];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || [output hasPrefix:@"Error"]) {
            [strongSelf showMessage:@"Couldn't Record" detail:error.localizedDescription ?: [output stringByReplacingOccurrencesOfString:@"Error: " withString:@""]];
            return;
        }
        strongSelf.waitingForRecording = YES;
        [strongSelf stepAside];
    }];
}

- (void)play:(NSString *)name {
    // A second for the app to step aside first: the gesture plays on whatever is on screen
    NSString *command = [NSString stringWithFormat:@"gesture play-soon \"%@\"", name];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || [output hasPrefix:@"Error"]) {
            [strongSelf showMessage:@"Couldn't Play" detail:error.localizedDescription ?: [output stringByReplacingOccurrencesOfString:@"Error: " withString:@""]];
            return;
        }
        [strongSelf stepAside];
    }];
}

- (void)stepAside {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(suspend)]) {
        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
    }
#pragma clang diagnostic pop
}

- (void)appBecameActive {
    if (!self.waitingForRecording) {
        [self reload];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"gesture record-status" completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *status = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
        if ([status isEqualToString:@"recording"]) return; // opened again before Stop: still waiting
        strongSelf.waitingForRecording = NO;
        if ([status hasPrefix:@"saved\t"]) {
            [strongSelf reload];
        } else {
            [strongSelf reload];
            if ([status isEqualToString:@"empty"]) [strongSelf showMessage:@"Nothing Recorded" detail:@"No touches were recorded before Stop."];
            else if ([status isEqualToString:@"failed"]) [strongSelf showMessage:@"Couldn't Save" detail:@"The recording couldn't be saved."];
        }
    }];
}

- (void)askRename:(NSString *)name {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Gesture" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = name;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *to = [strongSelf cleanName:alert.textFields.firstObject.text];
        if (to.length == 0 || [to isEqualToString:name]) return;
        NSString *command = [NSString stringWithFormat:@"gesture rename \"%@\" \"%@\"", name, to];
        [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
            if (error || [output hasPrefix:@"Error"]) {
                [strongSelf showMessage:@"Couldn't Rename" detail:error.localizedDescription ?: [output stringByReplacingOccurrencesOfString:@"Error: " withString:@""]];
                return;
            }
            [strongSelf renameInActionsFrom:name to:to];
            if ([strongSelf.detail.name isEqualToString:name]) strongSelf.detail.name = to;
            [strongSelf reload];
        }];
    }]];
    [[self presenter] presentViewController:alert animated:YES completion:nil];
}

// Actions that play the gesture follow it to its new name
- (void)renameInActionsFrom:(NSString *)from to:(NSString *)to {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSMutableDictionary *config = [cm valueForKey:@"config"];
    if (![config isKindOfClass:[NSMutableDictionary class]]) return;
    __block BOOL changed = NO;
    __block id (^replace)(id) = nil;
    id (^walk)(id) = ^id(id item) {
        if ([item isKindOfClass:[NSString class]]) {
            NSString *played = [RCGesturesViewController gestureForCommand:item];
            if (played.length && [played caseInsensitiveCompare:from] == NSOrderedSame) {
                changed = YES;
                return [RCGesturesViewController commandForGesture:to speed:[RCGesturesViewController speedForCommand:item]];
            }
            return item;
        }
        if ([item isKindOfClass:[NSArray class]]) {
            NSMutableArray *out = [NSMutableArray array];
            for (id child in item) [out addObject:replace(child)];
            return out;
        }
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *out = [NSMutableDictionary dictionary];
            [(NSDictionary *)item enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) { out[key] = replace(value); }];
            return out;
        }
        return item;
    };
    replace = walk;
    NSMutableDictionary *updated = walk(config);
    replace = nil;
    if (!changed) return;
    [config setDictionary:updated];
    [cm saveConfig];
}

// Recording again throws the old recording away, so it's asked first
- (void)confirmReplaceRecording:(NSString *)name {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Replace Recording?"
        message:@"The current recording is lost. Actions that play this gesture play the new one." preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [weakSelf record:name];
    }]];
    [[self presenter] presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDelete:(NSString *)name {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Gesture?"
        message:@"Actions that play it stop working." preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        NSString *command = [NSString stringWithFormat:@"gesture delete \"%@\"", name];
        [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf.detail && [strongSelf.detail.name isEqualToString:name]) [strongSelf.navigationController popToViewController:strongSelf animated:YES];
            [strongSelf reload];
        }];
    }]];
    [[self presenter] presentViewController:alert animated:YES completion:nil];
}

- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [[self presenter] presentViewController:alert animated:YES completion:nil];
}

@end
