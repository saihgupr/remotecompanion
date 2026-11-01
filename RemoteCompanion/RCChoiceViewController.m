#import "RCChoiceViewController.h"
#import "RCConfigManager.h"
#import "RCNumberSettingViewController.h"

static NSString *const RCTimedPausePrefix = @"button triggers pause ";

// A line under the choices for the actions that need one
static NSString *RCChoiceNote(NSString *key, NSArray<NSString *> *suffixes) {
    NSDictionary *notes = @{
        @"autolock": @"Toggle switches between Never and the time it was set to before.",
        @"buttontriggers": @"Stops RemoteCompanion's button and gesture triggers; the buttons and gestures work as usual, and other triggers keep running. Resume with Resume Button Triggers, from the Triggers screen, or by restarting the iPhone.",
        @"haptics": @"When the system plays haptics.",
        @"anc": @"For AirPods and Beats with Noise Control.",
        @"camera_photo": @"Opens the Camera in this mode.",
        @"camera_video": @"Opens the Camera to record video with this lens.",
        @"nfcscanner": @"Pause stops NFC tag triggers until a Resume.",
    };
    if (notes[key]) return notes[key];
    if ([suffixes containsObject:@"toggle"]) return @"Toggle switches to the other state each time it runs.";
    return nil;
}

@interface RCChoiceViewController ()
@property (nonatomic, copy) NSDictionary *info;
@property (nonatomic, copy) NSString *selectedSuffix;  // the checked choice
@property (nonatomic, copy) NSString *timedMinutes;    // "30" or "{name}": the checked choice is a timed pause
@property (nonatomic, copy) NSArray *otherActions;
@property (nonatomic, strong) UISelectionFeedbackGenerator *feedback;
@end

@implementation RCChoiceViewController

+ (BOOL)isTimedPauseCommand:(NSString *)command {
    if (![command.lowercaseString hasPrefix:RCTimedPausePrefix]) return NO;
    NSString *rest = [command substringFromIndex:RCTimedPausePrefix.length];
    return rest.length > 0 && ![rest isEqualToString:@"15"] && ![rest isEqualToString:@"60"];
}

- (instancetype)initWithToggleInfo:(NSDictionary *)info current:(NSString *)current otherActions:(NSArray *)otherActions {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _info = [info copy];
        _otherActions = [otherActions copy];
        self.title = info[@"name"];
        if ([RCChoiceViewController isTimedPauseCommand:current]) {
            _timedMinutes = [[current substringFromIndex:RCTimedPausePrefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        } else if (current) {
            NSDictionary *matched = [[RCConfigManager sharedManager] toggleInfoForCommand:current];
            if ([matched[@"key"] isEqualToString:info[@"key"]]) _selectedSuffix = matched[@"currentSuffix"];
        }
    }
    return self;
}

- (BOOL)isButtonTriggers {
    return [self.info[@"key"] isEqualToString:@"buttontriggers"];
}

- (BOOL)isRootOfPresented {
    return self.navigationController.viewControllers.firstObject == self && self.presentingViewController;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    }
    // Nothing changes until Save (Add while adding): the checkmark only marks the choice
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.saveTitle ?: @"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.tableView.tableHeaderView = [self headerView];
    self.tableView.delaysContentTouches = NO; // a row lights up as soon as it's touched
    self.feedback = [[UISelectionFeedbackGenerator alloc] init];
    [self.feedback prepare];
    [self updateSave];
}

// The action's icon over its name
- (UIView *)headerView {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 96)];
    UIView *tile = [[UIView alloc] init];
    tile.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12];
    tile.layer.cornerRadius = 16;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:tile];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.info[@"icon"] ?: @"switch.2"]];
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightRegular];
    icon.tintColor = [UIColor labelColor];
    icon.contentMode = UIViewContentModeCenter;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [tile.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [tile.topAnchor constraintEqualToAnchor:header.topAnchor constant:16],
        [tile.widthAnchor constraintEqualToConstant:64],
        [tile.heightAnchor constraintEqualToConstant:64],
        [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    return header;
}

- (void)updateSave {
    self.navigationItem.rightBarButtonItem.enabled = self.selectedSuffix != nil || self.timedMinutes != nil;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSArray<NSString *> *)suffixes {
    return self.info[@"suffixes"] ?: @[];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self suffixes].count + ([self isButtonTriggers] ? 1 : 0);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Choose One";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return RCChoiceNote(self.info[@"key"], [self suffixes]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selection = [[UIView alloc] init];
    selection.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selection;
    cell.textLabel.textColor = [UIColor labelColor];
    NSArray *suffixes = [self suffixes];
    BOOL checked = [self isCheckedRow:indexPath.row];
    if (indexPath.row < (NSInteger)suffixes.count) {
        cell.textLabel.text = self.info[@"displaySuffixes"][indexPath.row];
    } else {
        // Pause Button Triggers: for a time of the user's own
        cell.textLabel.text = @"For a Time…";
        cell.detailTextLabel.text = self.timedMinutes ? [self minutesText:self.timedMinutes] : nil;
    }
    cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits = checked ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
    return cell;
}

// Whether a row holds the checked choice
- (BOOL)isCheckedRow:(NSInteger)row {
    NSArray *suffixes = [self suffixes];
    if (row < (NSInteger)suffixes.count) return !self.timedMinutes && [suffixes[row] isEqualToString:self.selectedSuffix ?: @""];
    return self.timedMinutes != nil;
}

// The checkmarks (and the timed pause's minutes) on the rows on screen
- (void)refreshChecks {
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
        BOOL checked = [self isCheckedRow:path.row];
        cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.accessibilityTraits = checked ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
        if (path.row >= (NSInteger)[self suffixes].count) cell.detailTextLabel.text = self.timedMinutes ? [self minutesText:self.timedMinutes] : nil;
    }
}

- (NSString *)minutesText:(NSString *)minutes {
    if ([minutes hasPrefix:@"{"]) return minutes;
    return [minutes isEqualToString:@"1"] ? @"1 minute" : [NSString stringWithFormat:@"%@ minutes", minutes];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *suffixes = [self suffixes];
    if (indexPath.row >= (NSInteger)suffixes.count) {
        [self askMinutes];
        return;
    }
    // One choice: the checkmark moves here (the rows change in place, without a reload)
    self.selectedSuffix = suffixes[indexPath.row];
    self.timedMinutes = nil;
    [self refreshChecks];
    [self updateSave];
    [self.feedback selectionChanged];
    [self.feedback prepare];
}

// Pause Button Triggers for a number of minutes, or a variable
- (void)askMinutes {
    RCNumberSettingViewController *editor = [[RCNumberSettingViewController alloc] initWithTitle:@"For a Time" label:@"Minutes"
                                                                                             value:self.timedMinutes otherActions:self.otherActions];
    editor.placeholder = @"30";
    editor.minimum = 1;
    editor.maximum = 1440;
    editor.allowsRound = NO;
    editor.note = @"Button triggers resume by themselves after this long, up to a day.";
    editor.saveTitle = @"Done";
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(id minutes, __unused NSInteger choice) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.timedMinutes = [minutes isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%ld", (long)[minutes integerValue]] : [minutes description];
        strongSelf.selectedSuffix = nil;
        [strongSelf refreshChecks];
        [strongSelf updateSave];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    if (@available(iOS 15.0, *)) {
        nav.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent]];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

// The checked choice as a command
- (NSString *)chosenCommand {
    if (self.timedMinutes) return [RCTimedPausePrefix stringByAppendingString:self.timedMinutes];
    NSString *suffix = self.selectedSuffix;
    if (!suffix) return nil;
    NSString *prefix = [self.info[@"matchedPrefix"] length] ? self.info[@"matchedPrefix"] : [self.info[@"prefixes"] firstObject] ?: @"";
    // AudioMix's toggle is the bare command
    if (![self.info[@"matchedPrefix"] length] && [self.info[@"key"] isEqualToString:@"audiomix"] && [suffix isEqualToString:@"toggle"]) return @"audiomix";
    return [prefix stringByAppendingString:suffix];
}

- (void)save {
    NSString *command = [self chosenCommand];
    if (!command) return;
    void (^onPick)(NSString *) = self.onPick;
    if ([self isRootOfPresented]) {
        // Editing: this screen closes, then the action changes
        [self dismissViewControllerAnimated:YES completion:^{ if (onPick) onPick(command); }];
    } else if (onPick) {
        onPick(command); // in the picker: whoever opened it closes it
    }
}

@end
