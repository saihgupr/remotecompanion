#import "RCPlayGestureViewController.h"
#import "RCGesturesViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

typedef NS_ENUM(NSInteger, RCPlayGestureSection) {
    RCPlayGestureSectionGesture,
    RCPlayGestureSectionSpeed,
};

@interface RCPlayGestureViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *gestures; // @{ name, duration, strokes }
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *errorText;
@property (nonatomic, copy) NSString *chosen; // @"" is Latest Recording, nil is none yet
@property (nonatomic, assign) double speed;
// Record New Gesture: the name being recorded while the app has stepped aside (nil: none)
@property (nonatomic, copy) NSString *recordingName;
@end

@implementation RCPlayGestureViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _gestures = @[];
        _speed = 1;
        self.title = @"Play Gesture";
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = 56;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    if (self.command) {
        self.chosen = [RCGesturesViewController gestureForCommand:self.command];
        self.speed = [RCGesturesViewController speedForCommand:self.command];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
    [self updateSaveButton];
    [self reload];
}

- (void)updateSaveButton {
    self.navigationItem.rightBarButtonItem.enabled = self.chosen != nil;
}

- (void)save {
    if (!self.chosen || !self.onSave) return;
    self.onSave([RCGesturesViewController commandForGesture:self.chosen speed:self.speed]);
}

#pragma mark - Loading

- (void)reload {
    self.loading = YES;
    self.errorText = nil;
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"gesture list" completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.loading = NO;
        if (error || !output) {
            strongSelf.errorText = error.localizedDescription ?: @"Couldn't fetch the gestures";
        } else if ([output hasPrefix:@"Error"]) {
            strongSelf.errorText = output;
        } else {
            NSMutableArray *list = [NSMutableArray array];
            for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count < 3 || [parts[0] length] == 0) continue;
                [list addObject:@{ @"name": parts[0], @"duration": @([parts[1] doubleValue]), @"strokes": @([parts[2] integerValue]) }];
            }
            strongSelf.gestures = list;
        }
        [strongSelf.tableView reloadData];
    }];
}

#pragma mark - Rows

// Gesture rows: Latest Recording, the action's own gesture when it's no longer in the library,
// then the library (or one status row)
- (BOOL)chosenIsMissing {
    if (self.chosen.length == 0 || self.loading || self.errorText) return NO;
    for (NSDictionary *g in self.gestures) if ([g[@"name"] caseInsensitiveCompare:self.chosen] == NSOrderedSame) return NO;
    return YES;
}

- (NSArray<NSDictionary *> *)gestureRows {
    NSMutableArray *rows = [NSMutableArray arrayWithObjects:@{ @"record": @YES }, @{ @"name": @"", @"latest": @YES }, nil];
    if ([self chosenIsMissing]) [rows addObject:@{ @"name": self.chosen, @"missing": @YES }];
    if (self.loading || self.errorText || self.gestures.count == 0) [rows addObject:@{ @"status": @YES }];
    else [rows addObjectsFromArray:self.gestures];
    return rows;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == RCPlayGestureSectionGesture ? [self gestureRows].count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == RCPlayGestureSectionGesture ? @"Gesture" : @"Playback Speed";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCPlayGestureSectionGesture) return @"Record New Gesture steps aside so you can do it on the screen, then tap Stop; it's picked here once saved. Manage gestures in Settings > Gestures.";
    return @"Faster or slower playback can change flicks and long presses.";
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

    if (indexPath.section == RCPlayGestureSectionSpeed) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISegmentedControl *control = [self speedControl];
        control.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:control];
        UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [control.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [control.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [control.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        ]];
        return cell;
    }

    NSDictionary *g = [self gestureRows][indexPath.row];
    if ([g[@"status"] boolValue]) {
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
    if ([g[@"record"] boolValue]) {
        cell.textLabel.text = @"Record New Gesture";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.detailTextLabel.text = @"Do it on the screen, then tap Stop";
        cell.imageView.image = [UIImage systemImageNamed:@"record.circle"];
        cell.imageView.tintColor = [UIColor systemRedColor];
        return cell;
    }
    BOOL ticked = self.chosen && [g[@"name"] caseInsensitiveCompare:self.chosen] == NSOrderedSame;
    cell.accessoryType = ticked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if ([g[@"latest"] boolValue]) {
        cell.textLabel.text = @"Latest Recording";
        cell.detailTextLabel.text = @"Whichever gesture was recorded last";
        cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
        return cell;
    }
    cell.textLabel.text = g[@"name"];
    cell.imageView.image = [UIImage systemImageNamed:@"hand.draw.fill"];
    if ([g[@"missing"] boolValue]) {
        cell.detailTextLabel.text = @"Not Found";
    } else {
        NSInteger strokes = [g[@"strokes"] integerValue];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld %@, %.1f s", (long)strokes, strokes == 1 ? @"Touch" : @"Touches", [g[@"duration"] doubleValue]];
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == RCPlayGestureSectionGesture && ![[self gestureRows][indexPath.row][@"status"] boolValue];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (![self tableView:tableView shouldHighlightRowAtIndexPath:indexPath]) return;
    if ([[self gestureRows][indexPath.row][@"record"] boolValue]) {
        [self askNameAndRecord];
        return;
    }
    self.chosen = [self gestureRows][indexPath.row][@"name"];
    [self updateSaveButton];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:RCPlayGestureSectionGesture] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Recording

- (BOOL)hasGestureNamed:(NSString *)name {
    for (NSDictionary *g in self.gestures) if ([g[@"name"] caseInsensitiveCompare:name] == NSOrderedSame) return YES;
    return NO;
}

- (NSString *)suggestedName {
    for (NSInteger n = 1; ; n++) {
        NSString *name = [NSString stringWithFormat:@"Gesture %ld", (long)n];
        if (![self hasGestureNamed:name]) return name;
    }
}

// The same names Settings > Gestures allows: quotes would break the command
- (NSString *)cleanName:(NSString *)name {
    NSString *clean = [[name ?: @"" stringByReplacingOccurrencesOfString:@"\"" withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return clean;
}

- (void)askNameAndRecord {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Gesture"
        message:@"The app steps aside and counts down. Do the gesture, then tap Stop." preferredStyle:UIAlertControllerStyleAlert];
    NSString *suggested = [self suggestedName];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = suggested;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *record = [UIAlertAction actionWithTitle:@"Record" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *name = [strongSelf cleanName:alert.textFields.firstObject.text];
        if (name.length == 0) name = suggested;
        if ([strongSelf hasGestureNamed:name]) [strongSelf confirmReplace:name];
        else [strongSelf record:name];
    }];
    [alert addAction:record];
    alert.preferredAction = record;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmReplace:(NSString *)name {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Replace Gesture?"
        message:[NSString stringWithFormat:@"A gesture named “%@” already exists. A new recording replaces it, for every action that plays it.", name]
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [weakSelf record:name]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// As in Settings > Gestures: the app steps aside, the tweak counts down, records until Stop and
// opens the app again, here
- (void)record:(NSString *)name {
    NSString *command = [NSString stringWithFormat:@"gesture record \"%@\" return", name];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error || [output hasPrefix:@"Error"]) {
                [strongSelf showMessage:@"Couldn't Record" detail:error.localizedDescription ?: [output stringByReplacingOccurrencesOfString:@"Error: " withString:@""]];
                return;
            }
            strongSelf.recordingName = name;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
            if ([[UIApplication sharedApplication] respondsToSelector:@selector(suspend)]) {
                [[UIApplication sharedApplication] performSelector:@selector(suspend)];
            }
#pragma clang diagnostic pop
        });
    }];
}

// Back from recording: the new gesture is picked (Save keeps it), or what went wrong is said
- (void)appBecameActive {
    if (!self.recordingName) return;
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"gesture record-status" completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSString *status = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
            if ([status isEqualToString:@"recording"] || [status isEqualToString:@"naming"]) return; // opened again before Stop
            NSString *name = strongSelf.recordingName;
            strongSelf.recordingName = nil;
            if ([status hasPrefix:@"saved\t"]) {
                strongSelf.chosen = [status substringFromIndex:6].length ? [status substringFromIndex:6] : name;
                [strongSelf updateSaveButton];
            } else if ([status isEqualToString:@"empty"]) {
                [strongSelf showMessage:@"Nothing Recorded" detail:@"No touches were recorded before Stop."];
            } else if ([status isEqualToString:@"failed"]) {
                [strongSelf showMessage:@"Couldn't Save" detail:@"The recording couldn't be saved."];
            }
            [strongSelf reload];
        });
    }];
}

- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Speed

- (UISegmentedControl *)speedControl {
    NSArray<NSNumber *> *speeds = [RCGesturesViewController speeds];
    NSMutableArray *titles = [NSMutableArray array];
    for (NSNumber *speed in speeds) [titles addObject:[RCGesturesViewController titleForSpeed:speed.doubleValue]];
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:titles];
    control.selectedSegmentIndex = UISegmentedControlNoSegment;
    for (NSUInteger i = 0; i < speeds.count; i++) {
        if (fabs(speeds[i].doubleValue - self.speed) < 0.01) control.selectedSegmentIndex = i;
    }
    if (control.selectedSegmentIndex == UISegmentedControlNoSegment) {
        // A speed typed in a command: shown as its own segment
        [control insertSegmentWithTitle:[RCGesturesViewController titleForSpeed:self.speed] atIndex:control.numberOfSegments animated:NO];
        control.selectedSegmentIndex = control.numberOfSegments - 1;
    }
    [control addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    return control;
}

- (void)speedChanged:(UISegmentedControl *)control {
    NSArray<NSNumber *> *speeds = [RCGesturesViewController speeds];
    if (control.selectedSegmentIndex >= 0 && control.selectedSegmentIndex < (NSInteger)speeds.count) {
        self.speed = speeds[control.selectedSegmentIndex].doubleValue;
    }
}

@end
