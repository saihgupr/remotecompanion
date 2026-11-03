#import "RCTestKitViewController.h"
#import "RCTestReportViewController.h"
#import "RCTestKitSetupViewController.h"
#import "RCServerClient.h"
#import "RCConfigManager.h"

typedef NS_ENUM(NSInteger, RCTestKitSection) {
    RCTestKitSectionRun,     // the run in progress (only while there is one)
    RCTestKitSectionSuites,
    RCTestKitSectionUnlock,  // a passcode so test runs can unlock the phone
    RCTestKitSectionReports,
};

// A cell background with a fill from the left, `fraction` of the width: the passcode's time left
@interface RCDrainingBackground : UIView
@property (nonatomic, strong) UIView *fill;
@property (nonatomic, assign) CGFloat fraction;
@end

@implementation RCDrainingBackground
- (instancetype)initWithColor:(UIColor *)color fillColor:(UIColor *)fillColor {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = color;
        self.clipsToBounds = YES;
        _fill = [[UIView alloc] init];
        _fill.backgroundColor = fillColor;
        [self addSubview:_fill];
    }
    return self;
}
- (void)setFraction:(CGFloat)fraction {
    _fraction = MAX(0, MIN(1, fraction));
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.fill.frame = CGRectMake(0, 0, self.bounds.size.width * self.fraction, self.bounds.size.height);
}
@end

@interface RCTestKitViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *suites;   // name, description
@property (nonatomic, strong) NSArray<NSDictionary *> *reports;  // newest first: id, suite, summary, started
@property (nonatomic, strong) NSDictionary *currentRun;          // the run in progress, or nil
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) BOOL polling;
@property (nonatomic, strong) NSDictionary *passcodeStatus;      // set, expiresInSeconds, lifetimeSeconds
@property (nonatomic, strong) NSDate *passcodeExpiry;            // when the tweak forgets it, or nil
@property (nonatomic, assign) BOOL stopping;                     // Stop tapped, the run not ended yet
@end

@implementation RCTestKitViewController

static const NSInteger kRCClearAllTag = 9001;

+ (NSString *)displayNameForSuite:(NSString *)suite {
    NSDictionary *names = @{
        @"conditions": @"If Conditions",
        @"toggles": @"Toggle Actions",
        @"all": @"Conditions + Toggles",
        @"guided": @"Gestures & Sensors",
        @"differential": @"Stock vs Tweak",
        @"replay": @"Button Triggers",
    };
    return names[suite ?: @""] ?: suite ?: @"Test";
}

+ (void)sendRequest:(NSString *)request completion:(void (^)(NSDictionary *, NSError *))completion {
    NSString *command = [@"testkit " stringByAppendingString:request];
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![json isKindOfClass:[NSDictionary class]]) {
            json = nil;
            error = error ?: [NSError errorWithDomain:@"RCTestKit" code:1
                                             userInfo:@{ NSLocalizedDescriptionKey: @"The tweak didn't answer. Is RemoteCompanion installed and SpringBoard resprung?" }];
        }
        if (completion) completion(json, error);
    }];
}

// Shown for each suite (the API's own descriptions are written for the API)
static NSString *RCSuiteBlurb(NSString *suite) {
    NSDictionary *blurbs = @{
        @"conditions": @"Checks each If condition against the phone's current state.",
        @"toggles": @"Switches each toggle action and reads it back, then restores everything.",
        @"guided": @"Checks that each gesture and sensor trigger fires once.",
        @"differential": @"Compares each button press with the tweak off and on.",
        @"replay": @"Checks that each button trigger fires once, with the presses done by the tweak.",
    };
    return blurbs[suite] ?: @"";
}

static NSString *RCSuiteIcon(NSString *suite) {
    NSDictionary *icons = @{ @"conditions": @"questionmark.diamond", @"toggles": @"switch.2", @"all": @"checklist",
                             @"guided": @"hand.point.up.left", @"differential": @"square.split.2x1",
                             @"replay": @"play.circle" };
    return icons[suite] ?: @"checklist";
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Test Kit";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"settingsBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    // Until the tweak answers: the suites it has had since the start
    self.suites = @[@{ @"name": @"conditions" }, @{ @"name": @"toggles" }, @{ @"name": @"guided" }, @{ @"name": @"replay" }, @{ @"name": @"differential" }];
    self.reports = @[];
    [self loadSuites];
    [self loadReports];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshPasscodeStatus];
    [self poll];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(poll) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.pollTimer invalidate];
    self.pollTimer = nil;
}

#pragma mark - Loading

- (void)loadSuites {
    [RCTestKitViewController sendRequest:@"suites" completion:^(NSDictionary *json, NSError *error) {
        NSMutableArray *suites = [NSMutableArray array];
        for (NSDictionary *suite in json[@"suites"]) {
            if ([suite isKindOfClass:[NSDictionary class]] && ![suite[@"name"] isEqual:@"all"]) [suites addObject:suite];
        }
        if (!suites.count) return;
        self.suites = suites;
        [self.tableView reloadData];
    }];
}

- (void)loadReports {
    [RCTestKitViewController sendRequest:@"reports" completion:^(NSDictionary *json, NSError *error) {
        if (!json) return;
        NSArray *items = [json[@"items"] isKindOfClass:[NSArray class]] ? json[@"items"] : @[];
        self.reports = items;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCTestKitSectionReports] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

// The run in progress: shown at the top while it lasts; when it ends, its report opens
- (void)poll {
    [self updatePasscodeCountdown];
    if (self.polling) return;
    self.polling = YES;
    [RCTestKitViewController sendRequest:@"report" completion:^(NSDictionary *json, NSError *error) {
        self.polling = NO;
        BOOL running = [json[@"status"] isEqual:@"running"];
        NSDictionary *previous = self.currentRun;
        self.currentRun = running ? json : nil;
        if (!running) self.stopping = NO;
        if (running || previous) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCTestKitSectionRun] withRowAnimation:UITableViewRowAnimationNone];
        }
        if (previous && !running) {
            [self loadReports];
            if ([json[@"id"] isEqual:previous[@"id"]] && self.navigationController.topViewController == self) {
                [self.navigationController pushViewController:[[RCTestReportViewController alloc] initWithReportId:json[@"id"]] animated:YES];
            }
        }
    }];
}

#pragma mark - Running

- (void)startSuite:(NSString *)suite options:(NSString *)options {
    NSString *request = [NSString stringWithFormat:@"suite/run name=%@%@", suite, options ?: @""];
    [RCTestKitViewController sendRequest:request completion:^(NSDictionary *json, NSError *error) {
        if (!json || json[@"error"]) {
            [self showMessage:@"Couldn't Start" text:json[@"error"] ?: error.localizedDescription];
            return;
        }
        [self poll];
    }];
}

- (void)confirmSuite:(NSString *)suite {
    if (self.currentRun) {
        [self showMessage:@"A Test Is Running" text:@"Stop it first, or wait for it to finish."];
        return;
    }
    NSString *name = [RCTestKitViewController displayNameForSuite:suite];
    UIAlertController *alert;
    if ([suite isEqualToString:@"toggles"]) {
        alert = [UIAlertController alertControllerWithTitle:name
                                                    message:@"Each toggle is switched and put back afterwards. Toggles that drop connections for a moment are left out unless you include them."
                                             preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:@"Run" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self startSuite:suite options:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Run, Including Connections" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self startSuite:suite options:@"&disruptive=1"];
        }]];
    } else if ([suite isEqualToString:@"guided"] || [suite isEqualToString:@"differential"] || [suite isEqualToString:@"replay"]) {
        // Who does the steps, which ones and how many times first
        RCTestKitSetupViewController *setup = [[RCTestKitSetupViewController alloc] initWithSuite:suite];
        __weak typeof(self) weakSelf = self;
        setup.onStart = ^(NSString *options) {
            [weakSelf.navigationController popToViewController:weakSelf animated:YES];
            [weakSelf startSuite:suite options:options];
        };
        [self.navigationController pushViewController:setup animated:YES];
        return;
    } else {
        [self startSuite:suite options:nil];
        return;
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    NSIndexPath *row = [NSIndexPath indexPathForRow:[[self.suites valueForKey:@"name"] indexOfObject:suite] inSection:RCTestKitSectionSuites];
    alert.popoverPresentationController.sourceView = [self.tableView cellForRowAtIndexPath:row] ?: self.view;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)stopRun {
    self.stopping = YES;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCTestKitSectionRun] withRowAnimation:UITableViewRowAnimationNone];
    [RCTestKitViewController sendRequest:@"suite/stop" completion:nil];
}

- (void)showMessage:(NSString *)title text:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table

- (UITableViewCell *)styledCellWithStyle:(UITableViewCellStyle)style {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selection = [[UIView alloc] init];
    selection.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selection;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 0;
    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

#pragma mark - Passcode for tests

- (NSString *)passcodeDetail {
    if (!self.passcodeExpiry) return @"Not set";
    NSInteger minutes = MAX(1, (NSInteger)ceil(self.passcodeExpiry.timeIntervalSinceNow / 60.0));
    return minutes == 1 ? @"Forgotten in 1 minute" : [NSString stringWithFormat:@"Forgotten in %ld minutes", (long)minutes];
}

- (CGFloat)passcodeFraction {
    double lifetime = [self.passcodeStatus[@"lifetimeSeconds"] doubleValue] ?: 1800;
    return self.passcodeExpiry ? self.passcodeExpiry.timeIntervalSinceNow / lifetime : 0;
}

// Every second: the time left and the fill, on the cell as it is (no reload, no flicker)
- (void)updatePasscodeCountdown {
    if (!self.passcodeExpiry) return;
    if (self.passcodeExpiry.timeIntervalSinceNow <= 0) {
        [self refreshPasscodeStatus];
        return;
    }
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:RCTestKitSectionUnlock]];
    cell.detailTextLabel.text = [self passcodeDetail];
    if ([cell.backgroundView isKindOfClass:[RCDrainingBackground class]]) ((RCDrainingBackground *)cell.backgroundView).fraction = [self passcodeFraction];
}

- (void)refreshPasscodeStatus {
    [RCTestKitViewController sendRequest:@"passcode" completion:^(NSDictionary *json, NSError *error) {
        self.passcodeStatus = json;
        self.passcodeExpiry = [json[@"set"] boolValue] ? [NSDate dateWithTimeIntervalSinceNow:[json[@"expiresInSeconds"] doubleValue]] : nil;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCTestKitSectionUnlock] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

// The passcode goes to the tweak over the UNIX socket and is kept only in SpringBoard's memory
// (see RCTestKit.x); the app doesn't keep it either
- (void)askForPasscode {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Passcode for Tests"
        message:@"Lets test runs unlock the phone between steps. It's kept only in memory - not saved anywhere - and forgotten after 30 minutes, a respring, or if it doesn't unlock the phone."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.secureTextEntry = YES;
        field.placeholder = @"Passcode";
        field.textContentType = UITextContentTypeOneTimeCode; // no password-manager prompt to save it
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Use" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *passcode = alert.textFields.firstObject.text ?: @"";
        alert.textFields.firstObject.text = @"";
        NSString *encoded = [passcode stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]] ?: @"";
        [RCTestKitViewController sendRequest:[@"passcode/set code=" stringByAppendingString:encoded] completion:^(NSDictionary *json, NSError *error) {
            if (json[@"error"] || !json) [self showMessage:@"Couldn't Set the Passcode" text:json[@"error"] ?: error.localizedDescription];
            [self refreshPasscodeStatus];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)passcodeRowTapped {
    if (![self.passcodeStatus[@"set"] boolValue]) {
        [self askForPasscode];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Passcode for Tests" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Forget Now" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [RCTestKitViewController sendRequest:@"passcode/forget" completion:^(NSDictionary *json, NSError *error) { [self refreshPasscodeStatus]; }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Enter Again" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self askForPasscode]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    NSIndexPath *row = [NSIndexPath indexPathForRow:0 inSection:RCTestKitSectionUnlock];
    sheet.popoverPresentationController.sourceView = [self.tableView cellForRowAtIndexPath:row] ?: self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == RCTestKitSectionRun) return self.currentRun ? @"Running" : nil;
    if (section == RCTestKitSectionSuites) return @"Tests";
    if (section == RCTestKitSectionUnlock) return @"Unlocking";
    return @"Reports";
}

// Reports' header (the standard one, so its spacing matches the others) gets Clear All at its
// right, at the top however long the list is
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if (section != RCTestKitSectionReports || ![view isKindOfClass:[UITableViewHeaderFooterView class]]) return;
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    UIButton *clear = [header.contentView viewWithTag:kRCClearAllTag];
    if (!clear) {
        clear = [UIButton buttonWithType:UIButtonTypeSystem];
        clear.tag = kRCClearAllTag;
        clear.translatesAutoresizingMaskIntoConstraints = NO;
        [clear setTitle:@"Clear All" forState:UIControlStateNormal];
        [clear setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        clear.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        [clear addTarget:self action:@selector(confirmClearReports) forControlEvents:UIControlEventTouchUpInside];
        [header.contentView addSubview:clear];
        // On the title's baseline when the title is in place, else at the header's bottom
        BOOL titlePlaced = [header.textLabel isDescendantOfView:header];
        [NSLayoutConstraint activateConstraints:@[
            [clear.trailingAnchor constraintEqualToAnchor:header.contentView.layoutMarginsGuide.trailingAnchor],
            titlePlaced ? [clear.lastBaselineAnchor constraintEqualToAnchor:header.textLabel.lastBaselineAnchor]
                        : [clear.bottomAnchor constraintEqualToAnchor:header.contentView.bottomAnchor constant:-2],
        ]];
    }
    clear.hidden = self.reports.count == 0;
}

- (void)confirmClearReports {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Delete All Reports?"
        message:[NSString stringWithFormat:@"All %lu reports will be deleted from this phone.", (unsigned long)self.reports.count]
        preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [RCTestKitViewController sendRequest:@"reports/clear" completion:^(NSDictionary *json, NSError *error) {
            if (!json) [self showMessage:@"Couldn't Delete" text:error.localizedDescription];
            [self loadReports];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIView *header = [self.tableView headerViewForSection:RCTestKitSectionReports];
    sheet.popoverPresentationController.sourceView = [header viewWithTag:kRCClearAllTag] ?: self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCTestKitSectionSuites) return @"Your settings are put back when a test ends.";
    if (section == RCTestKitSectionUnlock) return @"Optional. Tests that lock the phone can unlock it again with this. Kept in memory only; a passcode that doesn't work is forgotten after one try.";
    if (section == RCTestKitSectionReports && !self.reports.count) return @"Reports of finished tests appear here.";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RCTestKitSectionRun) return self.currentRun ? 2 : 0;
    if (section == RCTestKitSectionSuites) return self.suites.count;
    if (section == RCTestKitSectionUnlock) return 1;
    return self.reports.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == RCTestKitSectionRun) {
        if (indexPath.row == 1) {
            UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleDefault];
            cell.textLabel.text = self.stopping ? @"Stopping..." : @"Stop Test";
            cell.textLabel.textColor = self.stopping ? [UIColor secondaryLabelColor] : [UIColor systemRedColor];
            cell.selectionStyle = self.stopping ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            return cell;
        }
        UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleSubtitle];
        NSDictionary *run = self.currentRun;
        NSDictionary *progress = [run[@"progress"] isKindOfClass:[NSDictionary class]] ? run[@"progress"] : nil;
        NSDictionary *summary = run[@"summary"];
        cell.textLabel.text = [RCTestKitViewController displayNameForSuite:run[@"suite"]];
        NSString *detail;
        if ([progress[@"phase"] isEqual:@"ready"]) {
            detail = @"Waiting to start: go to the home screen and press Volume Up.";
        } else if (progress) {
            detail = [NSString stringWithFormat:@"Step %@ of %@: %@", progress[@"step"], progress[@"of"], progress[@"title"]];
        } else {
            detail = [NSString stringWithFormat:@"%@ tests so far", summary[@"total"] ?: @0];
        }
        if ([summary[@"total"] integerValue] > 0) {
            detail = [detail stringByAppendingFormat:@"\n%@ passed, %@ failed, %@ skipped", summary[@"pass"], summary[@"fail"], summary[@"skip"]];
        }
        cell.detailTextLabel.text = detail;
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
        cell.accessoryView = spinner;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.section == RCTestKitSectionSuites) {
        NSString *suite = self.suites[indexPath.row][@"name"];
        UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleSubtitle];
        cell.textLabel.text = [RCTestKitViewController displayNameForSuite:suite];
        cell.detailTextLabel.text = RCSuiteBlurb(suite);
        cell.imageView.image = [UIImage systemImageNamed:RCSuiteIcon(suite)] ?: [UIImage systemImageNamed:@"list.bullet.rectangle"];
        cell.imageView.tintColor = [UIColor systemTealColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == RCTestKitSectionUnlock) {
        UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleSubtitle];
        cell.textLabel.text = @"Passcode for Tests";
        cell.detailTextLabel.text = [self passcodeDetail];
        if (self.passcodeExpiry) {
            // Orange while it's set, draining from the right as its time runs out
            RCDrainingBackground *background = [[RCDrainingBackground alloc] initWithColor:cell.backgroundColor
                                                                                 fillColor:[[UIColor systemOrangeColor] colorWithAlphaComponent:0.65]];
            background.fraction = [self passcodeFraction];
            cell.backgroundView = background;
        }
        cell.imageView.image = [UIImage systemImageNamed:@"lock.open"];
        cell.imageView.tintColor = [UIColor systemTealColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    NSDictionary *report = self.reports[indexPath.row];
    NSDictionary *summary = report[@"summary"];
    UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleSubtitle];
    cell.textLabel.text = [RCTestKitViewController displayNameForSuite:report[@"suite"]];
    NSString *when = @"";
    if (report[@"started"]) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[report[@"started"] doubleValue] / 1000.0];
        when = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
    }
    NSInteger fail = [summary[@"fail"] integerValue];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@ passed, %@ failed, %@ skipped", when, summary[@"pass"] ?: @0, summary[@"fail"] ?: @0, summary[@"skip"] ?: @0];
    cell.imageView.image = [UIImage systemImageNamed:fail ? @"xmark.circle.fill" : @"checkmark.circle.fill"];
    cell.imageView.tintColor = fail ? [UIColor systemRedColor] : [UIColor systemGreenColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == RCTestKitSectionRun) {
        if (indexPath.row == 1 && !self.stopping) [self stopRun];
    } else if (indexPath.section == RCTestKitSectionSuites) {
        [self confirmSuite:self.suites[indexPath.row][@"name"]];
    } else if (indexPath.section == RCTestKitSectionUnlock) {
        [self passcodeRowTapped];
    } else {
        [self.navigationController pushViewController:[[RCTestReportViewController alloc] initWithReportId:self.reports[indexPath.row][@"id"]] animated:YES];
    }
}

// The row goes at once, inside the swipe action, so its animation is the system's own;
// if the tweak then can't delete the file, the list is reloaded from it
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != RCTestKitSectionReports) return nil;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
                                                                       handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        NSString *reportId = self.reports[indexPath.row][@"id"];
        NSMutableArray *reports = [self.reports mutableCopy];
        [reports removeObjectAtIndex:indexPath.row];
        self.reports = reports;
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [[tableView headerViewForSection:RCTestKitSectionReports] viewWithTag:kRCClearAllTag].hidden = reports.count == 0;
        completion(YES);
        [RCTestKitViewController sendRequest:[@"report/delete id=" stringByAppendingString:reportId] completion:^(NSDictionary *json, NSError *error) {
            if (json[@"deleted"]) return;
            [self loadReports];
            [self showMessage:@"Couldn't Delete" text:json[@"error"] ?: error.localizedDescription];
        }];
    }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

@end
