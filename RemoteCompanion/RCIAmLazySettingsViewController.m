#import "RCIAmLazySettingsViewController.h"
#import "RCBackup.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"

@interface RCIAmLazySettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *backups;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, copy) NSString *startName;
@property (nonatomic, copy) NSString *lastSize;
@property (nonatomic, assign) NSInteger stableCount;
@property (nonatomic, assign) NSInteger pollCount;
@property (nonatomic, copy) NSString *statusText;
@end

@implementation RCIAmLazySettingsViewController

+ (BOOL)isIAmLazyInstalled {
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm fileExistsAtPath:@"/var/jb/usr/local/bin/ial"] || [fm fileExistsAtPath:@"/usr/local/bin/ial"];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"IAmLazy";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 58;

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
    }

    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleTweaksChanged:)
                                                 name:@"RCConfigTweaksChangedNotification"
                                               object:nil];
    [self applyTweaks];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadBackups];
    if (self.running && !self.pollTimer) [self startPolling];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // The backup keeps running on the phone; only the polling stops
    [self stopPolling];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.pollTimer invalidate];
}

- (void)handleTweaksChanged:(NSNotification *)note {
    [self applyTweaks];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;
    self.tableView.backgroundColor = settingsBG;
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    [self.tableView reloadData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self applyTweaks];
        }
    }
}

#pragma mark - Backups

- (void)reloadBackups {
    NSString *reply = [RCBackup sendTweakCommand:@"ialazy list"];
    self.backups = [self parseBackups:reply];
    [self.tableView reloadData];
}

- (NSArray<NSDictionary *> *)parseBackups:(NSString *)reply {
    if (![reply isKindOfClass:[NSString class]] || reply.length == 0) return @[];
    if ([reply hasPrefix:@"Error"] || [reply isEqualToString:@"none"]) return @[];

    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in [reply componentsSeparatedByString:@"\n"]) {
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        if (parts.count < 4) continue;
        NSNumber *size = @([parts[1] longLongValue]);
        NSNumber *date = @([parts[2] doubleValue]);
        NSString *path = parts[3];
        if (path.length == 0) continue;
        [out addObject:@{ @"name": parts[0], @"size": size, @"date": date, @"path": path }];
    }
    return out;
}

- (NSString *)sizeText:(NSNumber *)size {
    return [NSByteCountFormatter stringFromByteCount:size.longLongValue
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSString *)dateText:(NSNumber *)epoch {
    if (epoch.doubleValue <= 0) return @"";
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:epoch.doubleValue]] ?: @"";
}

- (void)startBackup {
    if (self.running) return;

    self.running = YES;
    self.startName = self.backups.firstObject[@"name"] ?: @"";
    self.lastSize = nil;
    self.stableCount = 0;
    self.pollCount = 0;
    self.statusText = @"Starting the backup…";
    [self.tableView reloadData];

    NSString *reply = [RCBackup sendTweakCommand:@"ialazy backup"];
    if (reply.length == 0) {
        [self finishWithError:@"The tweak is not running. Respring and try again."];
        return;
    }
    if ([reply hasPrefix:@"Error"]) {
        [self finishWithError:reply];
        return;
    }

    self.statusText = @"Backing up. This can take a few minutes.";
    [self.tableView reloadData];
    [self startPolling];
}

- (void)startPolling {
    [self.pollTimer invalidate];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(pollBackup:)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)pollBackup:(NSTimer *)timer {
    if (!self.view.window) {
        [self stopPolling];
        return;
    }

    self.pollCount++;
    if (self.pollCount > 300) {
        [self finishWithError:@"The backup is taking longer than usual. It may still finish, so check back in a few minutes."];
        return;
    }

    NSArray<NSDictionary *> *list = [self parseBackups:[RCBackup sendTweakCommand:@"ialazy list"]];
    if (list.count == 0) return;

    NSDictionary *newest = list.firstObject;
    if (self.startName.length > 0 && [newest[@"name"] isEqualToString:self.startName]) return;

    // Give the archive a moment to stop growing before calling it finished
    NSString *size = [newest[@"size"] stringValue];
    if (![size isEqualToString:(self.lastSize ?: @"")]) {
        self.lastSize = size;
        self.stableCount = 0;
        return;
    }
    self.stableCount++;
    if (self.stableCount < 3) return;

    [self stopPolling];
    self.running = NO;
    self.statusText = nil;
    self.backups = list;
    [self.tableView reloadData];
    [self showFinished:newest];
}

- (void)stopPolling {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
}

- (void)finishWithError:(NSString *)message {
    [self stopPolling];
    self.running = NO;
    self.statusText = nil;
    [self.tableView reloadData];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Backup Failed"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showFinished:(NSDictionary *)backup {
    NSString *message = [NSString stringWithFormat:@"%@\n%@",
                         [self sizeText:backup[@"size"]], [self dateText:backup[@"date"]]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Backup Finished"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy Path" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = backup[@"path"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : self.backups.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Backup" : (self.backups.count ? @"Backups" : nil);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Uses IAmLazy's own backup. Nothing is uploaded: the archive stays in IAmLazy's folder on this iPhone.";
    }
    if (self.backups.count) {
        return @"Copy one to your Mac with: rc backup ~/Desktop";
    }
    return @"No backups yet.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];

    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;

    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.masksToBounds = YES;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];

    if (indexPath.section == 0) {
        cell.textLabel.text = @"Back Up Tweaks Now";
        cell.detailTextLabel.text = self.running ? self.statusText : @"Backs up the installed tweaks and packages";
        cell.textLabel.textColor = self.running ? [UIColor secondaryLabelColor] : [UIColor labelColor];
        if (self.running) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        }
    } else {
        NSDictionary *backup = self.backups[indexPath.row];
        cell.textLabel.text = backup[@"name"];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
            [self sizeText:backup[@"size"]], [self dateText:backup[@"date"]]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        [self startBackup];
        return;
    }

    NSDictionary *backup = self.backups[indexPath.row];
    NSString *message = [NSString stringWithFormat:@"%@\n%@\n\n%@",
        [self sizeText:backup[@"size"]], [self dateText:backup[@"date"]], backup[@"path"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:backup[@"name"]
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy Path" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = backup[@"path"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
