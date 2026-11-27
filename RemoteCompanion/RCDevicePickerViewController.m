#import "RCDevicePickerViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

// An SF Symbol for a device, guessed from its name
static NSString *RCDeviceIconName(NSString *name, RCDevicePickerKind kind) {
    NSString *lower = name.lowercaseString;
    NSSet *words = [NSSet setWithArray:[lower componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]]];
    // Checked in order: phrases match anywhere in the name, single words only as whole words
    NSArray<NSArray<NSString *> *> *rules = @[
        @[ @"airpods max", @"airpodsmax" ], @[ @"airpods pro", @"airpodspro" ], @[ @"airpods", @"airpods" ],
        @[ @"beats", @"beats.headphones" ],
        @[ @"homepod mini", @"homepodmini" ], @[ @"homepod", @"homepod" ],
        @[ @"apple tv", @"appletv" ], @[ @"tv", @"tv" ],
        @[ @"watch", @"applewatch" ],
        @[ @"macbook", @"laptopcomputer" ], @[ @"imac", @"desktopcomputer" ], @[ @"mac", @"desktopcomputer" ],
        @[ @"ipad", @"ipad" ], @[ @"iphone", @"iphone" ],
        @[ @"carplay", @"car" ], @[ @"car", @"car" ],
        @[ @"keyboard", @"keyboard" ], @[ @"mouse", @"computermouse" ],
        @[ @"controller", @"gamecontroller" ], @[ @"xbox", @"gamecontroller" ], @[ @"dualsense", @"gamecontroller" ], @[ @"dualshock", @"gamecontroller" ],
        @[ @"speaker", @"hifispeaker" ], @[ @"soundbar", @"hifispeaker" ], @[ @"sonos", @"hifispeaker" ], @[ @"bose", @"hifispeaker" ], @[ @"jbl", @"hifispeaker" ],
        @[ @"headphones", @"headphones" ], @[ @"headset", @"headphones" ], @[ @"buds", @"headphones" ], @[ @"earbuds", @"headphones" ],
    ];
    for (NSArray<NSString *> *rule in rules) {
        BOOL phrase = [rule[0] containsString:@" "];
        if (phrase ? [lower containsString:rule[0]] : [words containsObject:rule[0]]) {
            if ([UIImage systemImageNamed:rule[1]]) return rule[1];
        }
    }
    if (kind == RCDevicePickerKindWatchFace) {
        return [UIImage systemImageNamed:@"applewatch.watchface"] ? @"applewatch.watchface" : @"applewatch";
    }
    return kind == RCDevicePickerKindAirPlay ? @"airplayaudio" : @"dot.radiowaves.left.and.right";
}

@interface RCDevicePickerViewController () <UISearchResultsUpdating>
@property (nonatomic, assign) RCDevicePickerKind kind;
@property (nonatomic, strong) NSArray<NSDictionary *> *devices;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *errorText;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation RCDevicePickerViewController

- (instancetype)initWithKind:(RCDevicePickerKind)kind title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _kind = kind;
        _devices = @[];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
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

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = self.kind == RCDevicePickerKindWatchFace ? @"Search Faces" : @"Search Devices";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

    [self reload];
}

- (void)cancel {
    if (self.searchController.isActive) self.searchController.active = NO;
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Loading

- (void)reload {
    self.loading = YES;
    self.errorText = nil;
    [self.tableView reloadData];
    NSString *command = @"bluetooth list";
    if (self.kind == RCDevicePickerKindAirPlay) command = @"airplay list";
    else if (self.kind == RCDevicePickerKindWatchFace) command = @"watch faces";
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.loading = NO;
        [strongSelf.refreshControl endRefreshing];
        if (error || !output) {
            strongSelf.errorText = error.localizedDescription ?: @"Couldn't fetch devices";
            strongSelf.devices = @[];
        } else {
            strongSelf.devices = [strongSelf devicesFromOutput:output];
        }
        [strongSelf.tableView reloadData];
    }];
}

// Bluetooth: one name per line. AirPlay: "  Name" or "* Name" (the current output), with a
// trailing " [UID]" on builds that include it.
- (NSArray<NSDictionary *> *)devicesFromOutput:(NSString *)output {
    NSMutableArray *devices = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSString *text = line;
        BOOL current = NO;
        if ((self.kind == RCDevicePickerKindAirPlay || self.kind == RCDevicePickerKindWatchFace) && [text hasPrefix:@"* "]) {
            current = YES;
            text = [text substringFromIndex:2];
        }
        text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length == 0 || [text hasPrefix:@"Error:"] || [text hasPrefix:@"No AirPlay devices found"] || [text hasPrefix:@"No paired Bluetooth devices found"] || [text hasPrefix:@"No Watch faces found"]) continue;

        NSString *name = text;
        NSString *target = text;
        if (self.kind == RCDevicePickerKindAirPlay || self.kind == RCDevicePickerKindWatchFace) {
            NSRange open = [text rangeOfString:@" [" options:NSBackwardsSearch];
            if (open.location != NSNotFound && [text hasSuffix:@"]"]) {
                name = [[text substringToIndex:open.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *uid = [text substringWithRange:NSMakeRange(open.location + 2, text.length - open.location - 3)];
                target = [NSString stringWithFormat:@"%@ # %@", uid, name];
            }
        }
        NSString *dedupeKey = (self.kind == RCDevicePickerKindWatchFace) ? target.lowercaseString : name.lowercaseString;
        if ([seen containsObject:dedupeKey]) continue;
        [seen addObject:dedupeKey];
        [devices addObject:@{ @"name": name, @"target": target, @"current": @(current) }];
    }
    if (self.kind != RCDevicePickerKindWatchFace) {
        [devices sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        }];
    }
    // Editing an action whose device isn't listed (unpaired, or not reachable now): keep it visible
    if (self.currentDevice.length &&
        !(self.kind == RCDevicePickerKindWatchFace && ([self.currentDevice caseInsensitiveCompare:@"next"] == NSOrderedSame || [self.currentDevice caseInsensitiveCompare:@"prev"] == NSOrderedSame || [self.currentDevice caseInsensitiveCompare:@"previous"] == NSOrderedSame))) {
        BOOL foundCurrent = NO;
        for (NSDictionary *d in devices) {
            if ([d[@"name"] caseInsensitiveCompare:self.currentDevice] == NSOrderedSame) { foundCurrent = YES; break; }
        }
        if (!foundCurrent) {
            [devices insertObject:@{ @"name": self.currentDevice, @"target": self.currentDevice, @"missing": @YES } atIndex:0];
        }
    }
    if (self.kind == RCDevicePickerKindWatchFace && self.includeAnyOption) {
        [devices insertObject:@{ @"name": @"Any Watch Face", @"target": @"__ANY__" } atIndex:0];
    }
    return devices;
}

#pragma mark - Rows

- (NSString *)searchText {
    return self.searchController.isActive ? self.searchController.searchBar.text : nil;
}

- (NSArray<NSDictionary *> *)visibleDevices {
    NSString *search = [self searchText];
    if (search.length == 0) return self.devices;
    NSPredicate *match = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", search];
    return [self.devices filteredArrayUsingPredicate:match];
}

// Section 0: devices, or one status row. Section 1: Scan Again / Other Name… (not while searching)
- (NSArray<NSString *> *)extraRows {
    if ([self searchText].length) return @[];
    NSMutableArray *rows = [NSMutableArray array];
    if (self.kind == RCDevicePickerKindWatchFace) {
        [rows addObject:@"Next Watch Face"];
        [rows addObject:@"Previous Watch Face"];
        [rows addObject:@"Other Name…"];
        if (!self.loading && (self.errorText || self.devices.count == 0)) [rows addObject:@"Try Again"];
        return rows;
    }
    if (!self.loading && (self.kind == RCDevicePickerKindAirPlay || self.errorText || self.devices.count == 0)) {
        [rows addObject:self.kind == RCDevicePickerKindAirPlay ? @"Scan Again" : @"Try Again"];
    }
    if (self.kind == RCDevicePickerKindBluetooth) [rows addObject:@"Other Name…"];
    return rows;
}

- (BOOL)showsStatusRow {
    return self.loading || self.errorText || [self visibleDevices].count == 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self extraRows].count ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 1) return [self extraRows].count;
    return [self showsStatusRow] ? 1 : [self visibleDevices].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section != 0) return self.kind == RCDevicePickerKindWatchFace ? @"Cycle" : nil;
    if (self.kind == RCDevicePickerKindWatchFace) return @"Watch Faces";
    return self.kind == RCDevicePickerKindAirPlay ? @"Available Outputs" : @"Paired Devices";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 0 || self.loading || self.errorText) return nil;
    if (self.kind == RCDevicePickerKindWatchFace) return @"Switches the active face on your paired Apple Watch.";
    return self.kind == RCDevicePickerKindAirPlay ? @"Only outputs reachable right now are listed." : nil;
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

    if (indexPath.section == 1) {
        NSString *title = [self extraRows][indexPath.row];
        cell.textLabel.text = title;
        BOOL isNext = [title isEqualToString:@"Next Watch Face"];
        BOOL isPrev = [title isEqualToString:@"Previous Watch Face"];
        if (isNext || isPrev) {
            cell.imageView.image = [UIImage systemImageNamed:isNext ? @"forward.fill" : @"backward.fill"];
            cell.imageView.tintColor = self.view.tintColor;
            BOOL ticked = self.currentDevice.length && ((isNext && [self.currentDevice caseInsensitiveCompare:@"next"] == NSOrderedSame) ||
                                                        (isPrev && ([self.currentDevice caseInsensitiveCompare:@"prev"] == NSOrderedSame || [self.currentDevice caseInsensitiveCompare:@"previous"] == NSOrderedSame)));
            cell.accessoryType = ticked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else {
            cell.textLabel.textColor = self.view.tintColor;
            cell.imageView.image = [UIImage systemImageNamed:[title isEqualToString:@"Other Name…"] ? @"pencil" : @"arrow.clockwise"];
            cell.imageView.tintColor = self.view.tintColor;
        }
        return cell;
    }

    if ([self showsStatusRow]) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.numberOfLines = 0;
        if (self.loading) {
            if (self.kind == RCDevicePickerKindWatchFace) cell.textLabel.text = @"Loading Watch faces…";
            else cell.textLabel.text = self.kind == RCDevicePickerKindAirPlay ? @"Scanning for devices…" : @"Loading paired devices…";
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        } else if (self.errorText) {
            cell.textLabel.text = self.errorText;
        } else if ([self searchText].length) {
            cell.textLabel.text = self.kind == RCDevicePickerKindWatchFace ? @"No matching faces" : @"No matching devices";
        } else {
            if (self.kind == RCDevicePickerKindWatchFace) cell.textLabel.text = @"No Watch faces found";
            else cell.textLabel.text = self.kind == RCDevicePickerKindAirPlay ? @"No AirPlay devices found" : @"No paired devices found";
        }
        return cell;
    }

    NSDictionary *device = [self visibleDevices][indexPath.row];
    cell.textLabel.text = device[@"name"];
    cell.imageView.image = [UIImage systemImageNamed:RCDeviceIconName(device[@"name"], self.kind)];
    if ([device[@"missing"] boolValue]) cell.detailTextLabel.text = @"Not Found";
    else if ([device[@"current"] boolValue]) cell.detailTextLabel.text = self.kind == RCDevicePickerKindWatchFace ? @"Current Face" : @"Current Output";
    BOOL ticked = self.currentDevice.length && [device[@"name"] caseInsensitiveCompare:self.currentDevice] == NSOrderedSame;
    cell.accessoryType = ticked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 || ![self showsStatusRow];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        NSString *row = [self extraRows][indexPath.row];
        if ([row isEqualToString:@"Next Watch Face"]) [self choose:@{ @"name": @"Next Watch Face", @"target": @"next" }];
        else if ([row isEqualToString:@"Previous Watch Face"]) [self choose:@{ @"name": @"Previous Watch Face", @"target": @"prev" }];
        else if ([row isEqualToString:@"Other Name…"]) [self promptForName];
        else [self reload];
        return;
    }
    if ([self showsStatusRow]) return;
    [self choose:[self visibleDevices][indexPath.row]];
}

- (void)choose:(NSDictionary *)device {
    if (self.searchController.isActive) self.searchController.active = NO;
    if (self.onDeviceSelected) self.onDeviceSelected(device);
}

// A device that isn't paired yet, or one whose name changes: matched by name when the action runs
- (void)promptForName {
    BOOL isWatchFace = self.kind == RCDevicePickerKindWatchFace;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isWatchFace ? @"Watch Face Name" : @"Device Name"
                                                                   message:isWatchFace ? @"Matches any face on the paired Apple Watch whose name contains this text." : @"Matches any paired or connected device whose name contains this text."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = isWatchFace ? @"Infograph" : @"My Device";
        field.text = self.currentDevice;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Use" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length) [weakSelf choose:@{ @"name": name, @"target": name }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self.tableView reloadData];
}

@end
