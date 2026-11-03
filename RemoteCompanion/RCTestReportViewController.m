#import "RCTestReportViewController.h"
#import "RCTestKitViewController.h"
#import "RCConfigManager.h"

// A test's full detail, as JSON
@interface RCTestDetailViewController : UIViewController
@property (nonatomic, strong) NSDictionary *test;
@end

@implementation RCTestDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.view.backgroundColor = [cm tweakColorForKey:@"settingsBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    UITextView *text = [[UITextView alloc] initWithFrame:self.view.bounds];
    text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    text.editable = NO;
    text.backgroundColor = [UIColor clearColor];
    text.textColor = [UIColor labelColor];
    text.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    text.textContainerInset = UIEdgeInsetsMake(16, 12, 16, 12);
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.test options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    text.text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    [self.view addSubview:text];
}

@end

@interface RCTestReportViewController ()
@property (nonatomic, copy) NSString *reportId;
@property (nonatomic, strong) NSDictionary *report;
@property (nonatomic, strong) NSArray<NSString *> *groupTitles;              // "Failed", "Skipped", "Passed" - those with tests
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *groups;
@property (nonatomic, assign) NSUInteger loadAttempts;
@end

@implementation RCTestReportViewController

#pragma mark - Describing tests

// "statusbar swipe left" for "guided.statusbar_swipe_left"
static NSString *RCTestName(NSDictionary *test, NSString *suite) {
    if ([test[@"name"] isKindOfClass:[NSString class]] && [test[@"name"] length]) return test[@"name"]; // a step's own name
    NSString *name = test[@"id"] ?: @"";
    NSRange dot = [name rangeOfString:@"."];
    if (dot.location != NSNotFound && ([suite isEqualToString:@"all"] || [[name substringToIndex:dot.location] isEqualToString:suite])) {
        name = [name substringFromIndex:dot.location + 1];
    }
    return [[name stringByReplacingOccurrencesOfString:@"_" withString:@" "] stringByReplacingOccurrencesOfString:@"." withString:@": "];
}

static NSString *RCDescribeValue(id value) {
    if (!value || value == [NSNull null]) return @"none";
    if ([value isKindOfClass:[NSArray class]]) return [value count] ? [value componentsJoinedByString:@", "] : @"none";
    if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return [value boolValue] ? @"TRUE" : @"FALSE";
    return [value description];
}

// One line on what happened, when the detail says something beyond pass/fail
static NSString *RCTestOutcome(NSDictionary *test);

// The step's own detail (what sets it apart from others with its name), then what happened
static NSString *RCTestSummary(NSDictionary *test) {
    NSString *note = [test[@"note"] isKindOfClass:[NSString class]] && [test[@"note"] length] ? test[@"note"] : nil;
    NSString *outcome = RCTestOutcome(test);
    if (note && outcome) return [NSString stringWithFormat:@"%@\n%@", note, outcome];
    return note ?: outcome;
}

static NSString *RCTestOutcome(NSDictionary *test) {
    NSDictionary *d = [test[@"detail"] isKindOfClass:[NSDictionary class]] ? test[@"detail"] : nil;
    if (!d) return nil;
    if ([d[@"reason"] isKindOfClass:[NSString class]]) return d[@"reason"];
    if ([d[@"problems"] isKindOfClass:[NSArray class]] && [d[@"problems"] count]) {
        NSString *problems = [d[@"problems"] componentsJoinedByString:@"; "];
        // A replayed step: the presses, to replay it again
        return [d[@"seq"] isKindOfClass:[NSString class]] ? [NSString stringWithFormat:@"%@ - presses: %@", problems, d[@"seq"]] : problems;
    }
    NSDictionary *defined = [d[@"defined"] isKindOfClass:[NSDictionary class]] ? d[@"defined"] : nil;
    if ([d[@"differs"] isKindOfClass:[NSArray class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *key in d[@"differs"]) {
            if (defined[key]) [parts addObject:[NSString stringWithFormat:@"%@: should be %@, tweak %@", key, RCDescribeValue(defined[key]), RCDescribeValue(d[@"tweak"][@"outcome"][key])]];
            else [parts addObject:[NSString stringWithFormat:@"%@: stock %@, tweak %@", key,
                                   RCDescribeValue(d[@"stock"][@"outcome"][key]), RCDescribeValue(d[@"tweak"][@"outcome"][key])]];
        }
        return [parts componentsJoinedByString:@"; "];
    }
    // A defined behaviour that stock didn't show this time
    if (defined && [d[@"stockDiffers"] isKindOfClass:[NSArray class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *key in d[@"stockDiffers"]) [parts addObject:[NSString stringWithFormat:@"%@ %@ as defined (stock: %@)", key, RCDescribeValue(defined[key]), RCDescribeValue(d[@"stock"][@"outcome"][key])]];
        return [parts componentsJoinedByString:@"; "];
    }
    if (d[@"stock"] && d[@"tweak"]) return [NSString stringWithFormat:@"stock and tweak: %@", RCDescribeValue(d[@"stock"][@"outcome"][@"screen"])];
    if (d[@"condition"] && d[@"expected"]) {
        return [NSString stringWithFormat:@"%@ = %@: expected %@, got %@", d[@"condition"], d[@"value"], RCDescribeValue(d[@"expected"]), RCDescribeValue(d[@"got"])];
    }
    if (d[@"want"]) return [NSString stringWithFormat:@"wanted %@, got %@", RCDescribeValue(d[@"want"]), RCDescribeValue(d[@"got"])];
    if (d[@"state"]) return [NSString stringWithFormat:@"state %@, TRUE for %@", d[@"state"], RCDescribeValue(d[@"true"])];
    if (d[@"true"]) return [NSString stringWithFormat:@"TRUE for %@", RCDescribeValue(d[@"true"])];
    return nil;
}

static NSString *RCDeviceLine(NSDictionary *report) {
    NSDictionary *device = report[@"device"];
    if (![device isKindOfClass:[NSDictionary class]]) return @"";
    return [NSString stringWithFormat:@"%@, iOS %@ (%@), RemoteCompanion %@", device[@"model"] ?: @"?", device[@"ios"] ?: @"?",
            device[@"jailbreak"] ?: @"?", device[@"tweakVersion"] ?: @"?"];
}

static NSString *RCWhenLine(NSDictionary *report) {
    if (!report[@"started"]) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[report[@"started"] doubleValue] / 1000.0];
    NSString *when = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
    double seconds = [report[@"durationMs"] doubleValue] / 1000.0;
    if (seconds <= 0) return when;
    return seconds < 60 ? [NSString stringWithFormat:@"%@, %.0f s", when, seconds]
                        : [NSString stringWithFormat:@"%@, %.0f min %.0f s", when, floor(seconds / 60), fmod(seconds, 60)];
}

static NSString *RCCountsLine(NSDictionary *report) {
    NSDictionary *s = report[@"summary"];
    return [NSString stringWithFormat:@"%@ passed, %@ failed, %@ skipped", s[@"pass"] ?: @0, s[@"fail"] ?: @0, s[@"skip"] ?: @0];
}

// The readable summary that goes with a shared report: what failed and was skipped, and why
static NSString *RCShareText(NSDictionary *report) {
    NSString *suite = report[@"suite"];
    NSMutableString *text = [NSMutableString stringWithFormat:@"RemoteCompanion test report: %@\n%@\n%@\n%@\n",
                             [RCTestKitViewController displayNameForSuite:suite], RCCountsLine(report), RCDeviceLine(report), RCWhenLine(report)];
    for (NSString *status in @[@"fail", @"skip"]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (NSDictionary *test in report[@"tests"]) {
            if (![test[@"status"] isEqual:status]) continue;
            NSString *summary = RCTestSummary(test);
            [lines addObject:[NSString stringWithFormat:@"%@ %@%@", [status isEqual:@"fail"] ? @"✗" : @"–", RCTestName(test, suite),
                              summary ? [@": " stringByAppendingString:summary] : @""]];
        }
        if (lines.count) [text appendFormat:@"\n%@\n%@\n", [status isEqual:@"fail"] ? @"Failed" : @"Skipped", [lines componentsJoinedByString:@"\n"]];
    }
    if ([report[@"redacted"] boolValue]) [text appendString:@"\nWi-Fi and Bluetooth names and third-party app IDs are hidden."];
    [text appendString:@"\nFull details are in the attached JSON."];
    return text;
}

#pragma mark - View

- (instancetype)initWithReportId:(NSString *)reportId {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _reportId = [reportId copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Report";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"settingsBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    self.groups = @[];
    self.groupTitles = @[];
    [self load];
}

- (void)load {
    self.loadAttempts++;
    NSString *request = [@"report id=" stringByAppendingString:self.reportId];
    [RCTestKitViewController sendRequest:request completion:^(NSDictionary *json, NSError *error) {
        // A run that just ended is saved a moment after it reports itself done
        if ((!json || json[@"error"]) && self.loadAttempts < 3) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self load]; });
            return;
        }
        if (!json || json[@"error"]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't Load Report"
                                                                           message:json[@"error"] ?: error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        [self showReport:json];
    }];
}

- (void)showReport:(NSDictionary *)report {
    self.report = report;
    self.title = [RCTestKitViewController displayNameForSuite:report[@"suite"]];
    NSMutableArray *titles = [NSMutableArray array], *groups = [NSMutableArray array];
    NSDictionary *names = @{ @"fail": @"Failed", @"skip": @"Skipped", @"pass": @"Passed" };
    for (NSString *status in @[@"fail", @"skip", @"pass"]) {
        NSMutableArray *tests = [NSMutableArray array];
        for (NSDictionary *test in report[@"tests"]) {
            if ([test isKindOfClass:[NSDictionary class]] && [test[@"status"] isEqual:status]) [tests addObject:test];
        }
        if (!tests.count) continue;
        [titles addObject:names[status]];
        [groups addObject:tests];
    }
    self.groupTitles = titles;
    self.groups = groups;
    self.navigationItem.rightBarButtonItem.enabled = YES;
    [self.tableView reloadData];
}

#pragma mark - Sharing

// Personal values are left out unless the user chooses to include them - a choice only
// offered when the report has any
- (void)share {
    NSString *request = [NSString stringWithFormat:@"report id=%@&redact=1", self.reportId];
    [RCTestKitViewController sendRequest:request completion:^(NSDictionary *redacted, NSError *error) {
        if (!redacted || redacted[@"error"]) return;
        if (![redacted[@"redacted"] boolValue]) {
            [self shareReport:redacted];
            return;
        }
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Share Report"
                                                                       message:@"Wi-Fi and Bluetooth names and the IDs of apps you've installed are hidden unless you include them."
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Share" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self shareReport:redacted];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Share With Personal Info" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [RCTestKitViewController sendRequest:[@"report id=" stringByAppendingString:self.reportId] completion:^(NSDictionary *full, NSError *fullError) {
                if (full && !full[@"error"]) [self shareReport:full];
            }];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
        [self presentViewController:sheet animated:YES completion:nil];
    }];
}

- (void)shareReport:(NSDictionary *)report {
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    NSString *file = [NSString stringWithFormat:@"RemoteCompanion-%@.json", self.reportId];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:file]];
    if (![json writeToURL:url atomically:YES]) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[RCShareText(report), url] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:activity animated:YES completion:nil];
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
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 0;
    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.report ? 1 + self.groups.count : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Summary" : self.groupTitles[section - 1];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : self.groups[section - 1].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleSubtitle];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            NSInteger fail = [self.report[@"summary"][@"fail"] integerValue];
            cell.textLabel.text = RCCountsLine(self.report);
            cell.imageView.image = [UIImage systemImageNamed:fail ? @"xmark.circle.fill" : @"checkmark.circle.fill"];
            cell.imageView.tintColor = fail ? [UIColor systemRedColor] : [UIColor systemGreenColor];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = RCDeviceLine(self.report);
            cell.imageView.image = [UIImage systemImageNamed:@"iphone"];
            cell.imageView.tintColor = [UIColor systemGrayColor];
        } else {
            cell.textLabel.text = RCWhenLine(self.report);
            cell.imageView.image = [UIImage systemImageNamed:@"clock"];
            cell.imageView.tintColor = [UIColor systemGrayColor];
        }
        return cell;
    }

    NSDictionary *test = self.groups[indexPath.section - 1][indexPath.row];
    NSString *status = test[@"status"];
    UITableViewCell *cell = [self styledCellWithStyle:UITableViewCellStyleSubtitle];
    cell.textLabel.text = RCTestName(test, self.report[@"suite"]);
    cell.detailTextLabel.text = RCTestSummary(test);
    BOOL pass = [status isEqual:@"pass"], fail = [status isEqual:@"fail"];
    cell.imageView.image = [UIImage systemImageNamed:pass ? @"checkmark.circle" : fail ? @"xmark.circle" : @"minus.circle"];
    cell.imageView.tintColor = pass ? [UIColor systemGreenColor] : fail ? [UIColor systemRedColor] : [UIColor systemGrayColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;
    NSDictionary *test = self.groups[indexPath.section - 1][indexPath.row];
    RCTestDetailViewController *detail = [[RCTestDetailViewController alloc] init];
    detail.test = test;
    detail.title = RCTestName(test, self.report[@"suite"]);
    [self.navigationController pushViewController:detail animated:YES];
}

@end
