#import "RCSettingsViewController.h"
#import "RCWhatsNew.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"
#import "RCIntegrationsViewController.h"
#import "RCSettingsPageViewController.h"
#import "RCTestKitViewController.h"
#import "RCRunningViewController.h"
#import "RCWebUIAccessViewController.h"
#import "RCVariablesViewController.h"
#import "RCVariableIcon.h"
#import "RCTweaksViewController.h"
#import "RCGesturesViewController.h"
#import "RCAddOnCatalog.h"
#import "RCAddOnsViewController.h"
#import "RCBackup.h"
#import "RCExcludedAppsViewController.h"
#import "RCConfigManager+AppExclusions.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

@interface RCSettingsViewController () <UIDocumentPickerDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<NSDictionary *> *searchResults;
@property (nonatomic, strong) UISwitch *masterSwitch;
@property (nonatomic, strong) UISwitch *webUISwitch;
@property (nonatomic, strong) NSDate *addressCopiedUntil; // the Address row says Copied until then
@property (nonatomic, copy, readwrite) NSString *subpage;
@end

NSString *const RCSettingsSubpageWebUI = @"webUI";
NSString *const RCSettingsSubpageBackup = @"backup";

@implementation RCSettingsViewController

+ (instancetype)subpage:(NSString *)subpage {
    RCSettingsViewController *vc = [[self alloc] init];
    vc.subpage = subpage;
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = self.subpage ? [self titleForRowID:[self rowForSubpage:self.subpage]] : @"Settings";
    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];

    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    // Close button (a page has the back button instead)
    if (!self.subpage) self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSettings)];
    
    // Setup Table View
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 50;
    
    // Improved Section Spacing
    if (@available(iOS 15.0, *)) {
        // The spacing is built into the header heights below, the same way the
        // Triggers screen does it; the default top padding left too much air
        // under the large title.
        self.tableView.sectionHeaderTopPadding = 0;
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
    if (self.subpage) {
        // A page: no chips, search or footer
        [self applyTweaks];
        return;
    }

    // Search: every setting here and on the pages it opens
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    // Footer lives at the bottom of the table content (tableFooterView) so it
    // only appears once you scroll to the bottom, instead of floating over content.
    [self setupFooterView];
    [self setupWhatsNewHeader];
    [self applyTweaks];
}

// At the top: this version's What's New, as a row like the others (opens the card again)
- (void)setupWhatsNewHeader {
    if (![RCWhatsNew hasWhatsNew]) return;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat width = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 72)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIControl *row = [[UIControl alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    row.layer.cornerRadius = 10;
    row.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    row.layer.borderWidth = 1.0;
    row.isAccessibilityElement = YES;
    row.accessibilityTraits = UIAccessibilityTraitButton;
    row.accessibilityLabel = [RCWhatsNew whatsNewTitle];
    [row addTarget:self action:@selector(openWhatsNew) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:row];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"]];
    icon.tintColor = [UIColor systemYellowColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *label = [[UILabel alloc] init];
    label.text = [RCWhatsNew whatsNewTitle];
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.tintColor = [UIColor tertiaryLabelColor];
    chevron.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    for (UIView *view in @[icon, label, chevron]) { view.userInteractionEnabled = NO; [row addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:header.safeAreaLayoutGuide.leadingAnchor constant:20],
        [row.trailingAnchor constraintEqualToAnchor:header.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [row.topAnchor constraintEqualToAnchor:header.topAnchor constant:16],
        [row.heightAnchor constraintEqualToConstant:48],
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:24],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)setupFooterView {
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    footerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *appTitleLabel = [[UILabel alloc] init];
    appTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    appTitleLabel.textAlignment = NSTextAlignmentCenter;
    appTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    appTitleLabel.textColor = [UIColor secondaryLabelColor];
    appTitleLabel.text = @"RemoteCompanion";

    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.font = [UIFont systemFontOfSize:13];
    versionLabel.textColor = [UIColor secondaryLabelColor];

    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    versionLabel.text = [NSString stringWithFormat:@"v%@", version];

    [footerView addSubview:appTitleLabel];
    [footerView addSubview:versionLabel];

    appTitleLabel.userInteractionEnabled = YES;
    versionLabel.userInteractionEnabled = YES;

    UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGitHub)];
    [appTitleLabel addGestureRecognizer:titleTap];

    UITapGestureRecognizer *versionTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGitHub)];
    [versionLabel addGestureRecognizer:versionTap];

    [NSLayoutConstraint activateConstraints:@[
        [appTitleLabel.centerXAnchor constraintEqualToAnchor:footerView.centerXAnchor],
        [appTitleLabel.topAnchor constraintEqualToAnchor:footerView.topAnchor constant:10],
        [appTitleLabel.heightAnchor constraintEqualToConstant:20],

        [versionLabel.centerXAnchor constraintEqualToAnchor:footerView.centerXAnchor],
        [versionLabel.topAnchor constraintEqualToAnchor:appTitleLabel.bottomAnchor constant:0],
        [versionLabel.heightAnchor constraintEqualToConstant:16]
    ]];

    self.tableView.tableFooterView = footerView;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

// A search result: scroll to its row and flash it
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSString *rowID = self.highlightRowID;
    if (!rowID) return;
    self.highlightRowID = nil;
    [self flashRowID:rowID];
}

- (void)flashRowID:(NSString *)rowID {
    NSArray *sections = [self sections];
    for (NSUInteger s = 0; s < sections.count; s++) {
        NSUInteger r = [sections[s][@"rows"] indexOfObject:rowID];
        if (r == NSNotFound) continue;
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:r inSection:s];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
            });
        });
        return;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

- (void)dismissSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Web UI URL

- (NSString *)deviceIPAddress {
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
                if (!address && [name isEqualToString:@"pdp_ip0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    if (interfaces) freeifaddrs(interfaces);
    return address;
}

- (NSString *)webUIUrlString {
    if ([[RCConfigManager sharedManager].webUIAccess isEqualToString:@"local"]) return @"http://localhost:8080";
    NSString *ip = [self deviceIPAddress];
    if (ip.length) {
        return [NSString stringWithFormat:@"http://%@:8080", ip];
    }
    return @"http://localhost:8080";
}

#pragma mark - Sections and rows

// Row IDs on this screen; "page:<n>" opens an RCSettingsPage
static NSString *const RCMainRowEnableAll = @"enableAll";
static NSString *const RCMainRowHoliday = @"holidayMode";
static NSString *const RCMainRowExcludedApps = @"excludedApps";
static NSString *const RCMainRowTweaks = @"tweaks";
static NSString *const RCMainRowGestures = @"gestures";
static NSString *const RCMainRowWebUI = @"webUI";
static NSString *const RCMainRowAccess = @"access";
static NSString *const RCMainRowOpenWebUI = @"openWebUI";
static NSString *const RCMainRowWebUIAddress = @"webUIAddress";
static NSString *const RCMainRowIntegrations = @"integrations";
static NSString *const RCMainRowAddOns = @"addOns";
static NSString *const RCMainRowVariables = @"variables";
static NSString *const RCMainRowWebUIPage = @"webUIPage";
static NSString *const RCMainRowBackup = @"backup";
static NSString *const RCMainRowExport = @"export";
static NSString *const RCMainRowImport = @"import";
static NSString *const RCMainRowExportSecrets = @"exportSecrets";
// Export Configuration includes passwords and tokens only with this on (off to begin with)
static NSString *const RCExportIncludesSecretsKey = @"RCExportIncludesSecrets";

static NSString *RCPageRow(RCSettingsPage page) { return [NSString stringWithFormat:@"page:%ld", (long)page]; }

// The row on Settings that opens a page
- (NSString *)rowForSubpage:(NSString *)subpage {
    return [subpage isEqualToString:RCSettingsSubpageWebUI] ? RCMainRowWebUIPage : RCMainRowBackup;
}

// Every section: {title, symbol, rows, footer (optional)}. The category bar has a chip for each
// titled one. Every row on Settings opens a page; switches and one-tap actions are on the pages.
- (NSArray<NSDictionary *> *)allSections {
    return [self sectionsForSubpage:self.subpage];
}

- (NSArray<NSDictionary *> *)sectionsForSubpage:(NSString *)subpage {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if ([subpage isEqualToString:RCSettingsSubpageWebUI]) {
        NSMutableArray *sections = [NSMutableArray arrayWithObject:
            @{ @"title": @"Web UI", @"rows": @[RCMainRowWebUI],
               @"footer": @"The built-in Web UI configures RemoteCompanion from a browser on any device that can reach this iPhone." }];
        if (cm.webUIEnabled) {
            [sections addObject:@{ @"title": @"Access", @"rows": @[RCMainRowAccess],
                                   @"footer": @"Which networks can open the Web UI, and the password it asks for." }];
            [sections addObject:@{ @"title": @"Open", @"rows": @[RCMainRowOpenWebUI, RCMainRowWebUIAddress],
                                   @"footer": @"Open the address in a browser on a computer, or tap it to copy it." }];
        }
        return sections;
    }
    if ([subpage isEqualToString:RCSettingsSubpageBackup]) {
        BOOL secrets = [[NSUserDefaults standardUserDefaults] boolForKey:RCExportIncludesSecretsKey];
        return @[ @{ @"title": @"Backup", @"rows": @[RCMainRowExport, RCMainRowImport],
                     @"footer": @"Export saves everything on this device: settings, integrations, triggers, add-ons, gestures and variables. Import puts it back on any device." },
                  @{ @"title": @"Passwords and Tokens", @"rows": @[RCMainRowExportSecrets],
                     @"footer": secrets
                        ? @"The file holds the passwords and tokens saved for integrations, servers and devices, the Web UI's API token, and passcodes typed into Unlock actions, so keep it private."
                        : @"Left out of the file: the passwords and tokens saved for integrations, servers and devices, the Web UI's API token, passcodes typed into Unlock actions, and saved variables. Importing it here keeps the ones this device has; on another device, enter them again. Text inside actions, such as a command or a web request, stays as written." } ];
    }
    NSMutableArray *connections = [NSMutableArray arrayWithObjects:RCMainRowWebUIPage, RCMainRowIntegrations, nil];
    if ([RCAddOnCatalog catalogAvailable]) [connections addObject:RCMainRowAddOns]; // once the tweak has written its catalog
    return @[
        @{ @"title": @"", @"rows": @[RCMainRowHoliday, RCMainRowEnableAll] },
        @{ @"title": @"Triggers", @"symbol": @"bolt.fill",
           @"rows": @[RCPageRow(RCSettingsPageButtons), RCPageRow(RCSettingsPageSwipeTriggers), RCPageRow(RCSettingsPageNFC), RCMainRowExcludedApps] },
        @{ @"title": @"Appearance", @"symbol": @"paintbrush.fill", @"rows": @[RCPageRow(RCSettingsPageLayout), RCPageRow(RCSettingsPageBanners)] },
        // Web UI, and what connects RemoteCompanion to other services and tweaks
        @{ @"title": @"Connections", @"symbol": @"network", @"rows": connections },
        // What's been made and saved here: recorded gestures, variables, and the backup of it all
        @{ @"title": @"Data", @"symbol": @"tray.full.fill", @"rows": @[RCMainRowGestures, RCMainRowVariables, RCMainRowBackup] },
        @{ @"title": @"System", @"symbol": @"gearshape.fill", @"rows": @[RCMainRowTweaks, RCPageRow(RCSettingsPageSecurity), RCPageRow(RCSettingsPageDiagnostics)] },
    ];
}

- (BOOL)searching {
    return self.searchController.isActive && self.searchController.searchBar.text.length > 0;
}

// What the table shows: search results, or every section
- (NSArray<NSDictionary *> *)sections {
    if ([self searching]) return @[ @{ @"title": @"Results", @"rows": self.searchResults ?: @[] } ];
    return [self allSections];
}

- (NSString *)titleForRowID:(NSString *)rowID {
    if ([rowID hasPrefix:@"page:"]) return [RCSettingsPageViewController titleForPage:[[rowID substringFromIndex:5] integerValue]];
    NSDictionary *titles = @{ RCMainRowHoliday: @"Holiday Mode", RCMainRowEnableAll: @"Enable All Triggers", RCMainRowExcludedApps: @"Excluded Apps",
                              RCMainRowTweaks: @"iOS Tweaks",
                              RCMainRowGestures: @"Gestures", RCMainRowWebUI: @"Web UI", RCMainRowAccess: @"Access",
                              RCMainRowOpenWebUI: @"Open in Safari", RCMainRowWebUIAddress: @"Address", RCMainRowIntegrations: @"Integrations", RCMainRowAddOns: @"Add-ons",
                              RCMainRowVariables: @"Variables", RCMainRowWebUIPage: @"Web UI", RCMainRowBackup: @"Backup",
                              RCMainRowExport: @"Export Configuration", RCMainRowImport: @"Import Configuration",
                              RCMainRowExportSecrets: @"Include Passwords and Tokens" };
    return titles[rowID] ?: rowID;
}

#pragma mark - Search

// Every row here and on the pages: {title, where (its section or page), rowID, page (for a page's row)}
- (NSArray<NSDictionary *> *)searchIndex {
    NSMutableArray *index = [NSMutableArray array];
    for (NSDictionary *section in [self allSections]) {
        for (NSString *rowID in section[@"rows"]) {
            [index addObject:@{ @"title": [self titleForRowID:rowID], @"where": [section[@"title"] length] ? section[@"title"] : @"Settings", @"rowID": rowID }];
        }
    }
    for (RCSettingsPage page = 0; page < RCSettingsPageCount; page++) {
        RCSettingsPageViewController *pageVC = [[RCSettingsPageViewController alloc] initWithPage:page];
        NSString *pageTitle = [RCSettingsPageViewController titleForPage:page];
        for (NSDictionary *entry in [pageVC searchEntries]) {
            [index addObject:@{ @"title": entry[@"title"], @"where": pageTitle, @"rowID": entry[@"rowID"], @"page": @(page) }];
        }
    }
    for (NSString *subpage in @[RCSettingsSubpageWebUI, RCSettingsSubpageBackup]) {
        NSString *where = [self titleForRowID:[self rowForSubpage:subpage]];
        for (NSDictionary *section in [self sectionsForSubpage:subpage]) {
            for (NSString *rowID in section[@"rows"]) {
                [index addObject:@{ @"title": [self titleForRowID:rowID], @"where": where, @"rowID": rowID, @"subpage": subpage }];
            }
        }
    }
    for (NSDictionary *entry in [RCTweaksViewController searchEntries]) {
        [index addObject:@{ @"title": entry[@"title"], @"where": [self titleForRowID:RCMainRowTweaks], @"rowID": entry[@"rowID"], @"tweaks": @YES }];
    }
    return index;
}

// A row matches when every word typed starts a word of its name or of where it is
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *results = [NSMutableArray array];
    if (text.length) {
        NSArray *typed = [[text lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        for (NSDictionary *entry in [self searchIndex]) {
            NSString *haystack = [[NSString stringWithFormat:@"%@ %@", entry[@"title"], entry[@"where"]] lowercaseString];
            NSArray *words = [haystack componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
            BOOL all = YES;
            for (NSString *t in typed) {
                if (!t.length) continue;
                BOOL found = NO;
                for (NSString *w in words) if ([w hasPrefix:t]) { found = YES; break; }
                if (!found) { all = NO; break; }
            }
            if (all) [results addObject:entry];
        }
    }
    self.searchResults = results;
    [self.tableView reloadData];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[self sections].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self sections][section][@"title"];
    CGFloat headerHeight = [self tableView:tableView heightForHeaderInSection:section];
    if (!title.length && ![self searching]) return [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, headerHeight)];
    // The first header sits close under the category bar; the others leave a little air above
    BOOL first = (headerHeight < 30);
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, headerHeight)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, first ? 4 : 12, tableView.bounds.size.width - 40, 20)];
    label.text = [self searching] && [self.searchResults count] == 0 ? @"NO RESULTS" : [title uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [headerView addSubview:label];
    // the group's symbol, the same as its chip's
    NSString *symbol = [self sections][section][@"symbol"];
    UIImage *image = symbol ? [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]] : nil;
    if (image) {
        UIImageView *icon = [[UIImageView alloc] initWithImage:image];
        icon.tintColor = [UIColor secondaryLabelColor];
        icon.contentMode = UIViewContentModeCenter;
        icon.frame = CGRectMake(20, label.frame.origin.y, 16, 20);
        [headerView addSubview:icon];
        CGRect frame = label.frame;
        frame.origin.x += 22;
        frame.size.width -= 22;
        label.frame = frame;
    }
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self searching]) return 28.0;
    if (![[self sections][section][@"title"] length]) return 10.0; // Enable All Triggers, under the chips
    if (self.subpage) return section == 0 ? 32.0 : 38.0;
    return 38.0;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [self sections][section][@"footer"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self searching]) return tableView.rowHeight;
    return RCSettingsRowHeight(tableView, [self tableView:tableView cellForRowAtIndexPath:indexPath]);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[self sections][section][@"rows"] count];
}

- (void)setIcon:(NSString *)symbol color:(UIColor *)color onCell:(UITableViewCell *)cell {
    cell.imageView.image = RCSettingsIcon(symbol, color);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    id row = [self sections][indexPath.section][@"rows"][indexPath.row];
    NSDictionary *result = [row isKindOfClass:[NSDictionary class]] ? row : nil; // a search result
    NSString *rowID = result ? result[@"rowID"] : row;

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:result ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.masksToBounds = YES;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (result) {
        cell.textLabel.text = result[@"title"];
        cell.detailTextLabel.text = result[@"where"];
        return cell;
    }

    cell.textLabel.text = [self titleForRowID:rowID];
    cell.textLabel.numberOfLines = 0; // a long name wraps (RCSettingsRowHeight)
    if ([rowID hasPrefix:@"page:"]) {
        RCSettingsPage page = [[rowID substringFromIndex:5] integerValue];
        [self setIcon:[RCSettingsPageViewController symbolForPage:page] color:[RCSettingsPageViewController colorForPage:page] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowHoliday]) {
        UISwitch *holidaySwitch = [[UISwitch alloc] init];
        holidaySwitch.on = cm.holidayModeEnabled;
        [holidaySwitch addTarget:self action:@selector(holidayModeToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = holidaySwitch;
        [self setIcon:@"gift.fill" color:[UIColor systemRedColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowEnableAll]) {
        _masterSwitch = [[UISwitch alloc] init];
        _masterSwitch.on = cm.masterEnabled;
        [_masterSwitch addTarget:self action:@selector(masterToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = _masterSwitch;
        [self setIcon:@"checkmark" color:[UIColor systemGreenColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowExcludedApps]) {
        NSUInteger excludedCount = 0;
        for (NSString *key in [cm allConfiguredTriggerKeys]) excludedCount += [cm excludedAppsForTrigger:key].count;
        cell.detailTextLabel.text = excludedCount ? [NSString stringWithFormat:@"%lu", (unsigned long)excludedCount] : @"None";
        [self setIcon:@"nosign" color:[UIColor systemRedColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowTweaks]) {
        [self setIcon:@"slider.horizontal.3" color:[UIColor systemGrayColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowWebUIPage]) {
        cell.detailTextLabel.text = cm.webUIEnabled ? @"On" : @"Off";
        [self setIcon:@"globe" color:[UIColor systemBlueColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowBackup]) {
        [self setIcon:([UIImage systemImageNamed:@"externaldrive.fill"] ? @"externaldrive.fill" : @"tray.full.fill") color:[UIColor systemTealColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowGestures]) {
        [self setIcon:@"hand.draw.fill" color:[UIColor systemPinkColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowWebUI]) {
        _webUISwitch = [[UISwitch alloc] init];
        _webUISwitch.on = cm.webUIEnabled;
        [_webUISwitch addTarget:self action:@selector(webUIToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = _webUISwitch;
        [self setIcon:@"globe" color:[UIColor systemBlueColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowAccess]) {
        cell.detailTextLabel.text = [RCWebUIAccessViewController titleForAccess:cm.webUIAccess];
        [self setIcon:@"lock.shield.fill" color:[UIColor systemBlueColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowOpenWebUI]) {
        // A link, not a page: blue text and an arrow out of the app
        if (!result) {
            cell.textLabel.textColor = [UIColor systemBlueColor];
            UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.right"]];
            arrow.tintColor = [UIColor tertiaryLabelColor];
            arrow.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
            [arrow sizeToFit];
            cell.accessoryView = arrow;
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        [self setIcon:@"safari.fill" color:[UIColor systemBlueColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowWebUIAddress]) {
        if (!result) {
            BOOL copied = self.addressCopiedUntil && [self.addressCopiedUntil timeIntervalSinceNow] > 0;
            cell.detailTextLabel.text = copied ? @"Copied" : [[self webUIUrlString] stringByReplacingOccurrencesOfString:@"http://" withString:@""];
            UIImageView *copy = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:copied ? @"checkmark" : @"doc.on.doc"]];
            copy.tintColor = copied ? [UIColor systemGreenColor] : [UIColor tertiaryLabelColor];
            copy.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightRegular];
            [copy sizeToFit];
            cell.accessoryView = copy;
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        [self setIcon:@"link" color:[UIColor systemGrayColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowIntegrations]) {
        [self setIcon:([UIImage systemImageNamed:@"puzzlepiece.extension.fill"] ? @"puzzlepiece.extension.fill" : @"network") color:[UIColor systemIndigoColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowAddOns]) {
        [self setIcon:[RCAddOnCatalog defaultSymbol] color:[UIColor systemOrangeColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowVariables]) {
        // The variable "x", white on orange like the other icons
        cell.imageView.image = RCSettingsIconWithGlyph(RCVariableMenuIconActionSized(20.0), [UIColor systemOrangeColor]);
    } else if ([rowID isEqualToString:RCMainRowExport]) {
        [self setIcon:@"square.and.arrow.up.fill" color:[UIColor systemBlueColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowImport]) {
        [self setIcon:@"square.and.arrow.down.fill" color:[UIColor systemGreenColor] onCell:cell];
    } else if ([rowID isEqualToString:RCMainRowExportSecrets]) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:RCExportIncludesSecretsKey];
        [toggle addTarget:self action:@selector(exportSecretsChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        [self setIcon:@"key.fill" color:[UIColor systemGrayColor] onCell:cell];
    }
    if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id row = [self sections][indexPath.section][@"rows"][indexPath.row];
    if ([row isKindOfClass:[NSDictionary class]]) {
        [self openSearchResult:row];
        return;
    }
    [self openRowID:row];
}

- (void)openRowID:(NSString *)rowID {
    UIViewController *next = nil;
    if ([rowID hasPrefix:@"page:"]) next = [RCSettingsPageViewController viewControllerForPage:[[rowID substringFromIndex:5] integerValue] highlightRowID:nil];
    else if ([rowID isEqualToString:RCMainRowExcludedApps]) next = [[RCExcludedAppsViewController alloc] init];
    else if ([rowID isEqualToString:RCMainRowTweaks]) next = [[RCTweaksViewController alloc] init];
    else if ([rowID isEqualToString:RCMainRowGestures]) next = [[RCGesturesViewController alloc] init];
    else if ([rowID isEqualToString:RCMainRowAccess]) next = [[RCWebUIAccessViewController alloc] init];
    else if ([rowID isEqualToString:RCMainRowIntegrations]) next = [[RCIntegrationsViewController alloc] init];
    else if ([rowID isEqualToString:RCMainRowAddOns]) next = [[RCAddOnsViewController alloc] initShowing:RCAddOnsListAll];
    else if ([rowID isEqualToString:RCMainRowVariables]) next = [[RCVariablesViewController alloc] init];
    else if ([rowID isEqualToString:RCMainRowWebUIPage]) next = [RCSettingsViewController subpage:RCSettingsSubpageWebUI];
    else if ([rowID isEqualToString:RCMainRowBackup]) next = [RCSettingsViewController subpage:RCSettingsSubpageBackup];
    else if ([rowID isEqualToString:RCMainRowOpenWebUI]) [self openWebUI];
    else if ([rowID isEqualToString:RCMainRowWebUIAddress]) [self copyWebUIAddress];
    else if ([rowID isEqualToString:RCMainRowExport]) [self exportConfig];
    else if ([rowID isEqualToString:RCMainRowImport]) [self importConfig];
    if (next) [self.navigationController pushViewController:next animated:YES];
}

// A result on a page opens the page at that row; one on this screen ends the search and flashes it
- (void)openSearchResult:(NSDictionary *)result {
    if (result[@"subpage"]) {
        RCSettingsViewController *page = [RCSettingsViewController subpage:result[@"subpage"]];
        page.highlightRowID = result[@"rowID"];
        [self.navigationController pushViewController:page animated:YES];
        return;
    }
    if (result[@"tweaks"]) {
        RCTweaksViewController *tweaks = [[RCTweaksViewController alloc] init];
        tweaks.highlightRowID = result[@"rowID"];
        [self.navigationController pushViewController:tweaks animated:YES];
        return;
    }
    if (result[@"page"]) {
        [self.navigationController pushViewController:[RCSettingsPageViewController viewControllerForPage:[result[@"page"] integerValue] highlightRowID:result[@"rowID"]] animated:YES];
        return;
    }
    NSString *rowID = result[@"rowID"];
    self.searchController.active = NO;
    [self.tableView reloadData];
    [self flashRowID:rowID];
}

#pragma mark - Actions

- (void)masterToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].masterEnabled = sender.on;
}

- (void)exportSecretsChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:RCExportIncludesSecretsKey];
    [self.tableView reloadData]; // the footer says what the file holds
}

- (void)webUIToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].webUIEnabled = sender.on;
    [self.tableView reloadData];
}

- (void)holidayModeToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].holidayModeEnabled = sender.on;
}

- (void)openWebUI {
    NSURL *url = [NSURL URLWithString:[self webUIUrlString]];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

// Copies the address and says so in the row for a moment
- (void)copyWebUIAddress {
    [UIPasteboard generalPasteboard].string = [self webUIUrlString];
    self.addressCopiedUntil = [NSDate dateWithTimeIntervalSinceNow:1.5];
    [self.tableView reloadData];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)openWhatsNew {
    [RCWhatsNew showWhatsNewFrom:self];
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/saihgupr/RemoteCompanion"] options:@{} completionHandler:nil];
}
#pragma mark - Backup / Import

- (void)exportConfig {
    // One file with the configuration and everything that lives beside it (add-ons,
    // gestures, notification filters, variables, blacklist), built by the tweak so
    // Import Configuration can put a new device back exactly as this one is.
    NSError *error = nil;
    BOOL secrets = [[NSUserDefaults standardUserDefaults] boolForKey:RCExportIncludesSecretsKey];
    NSData *jsonData = [RCBackup fullBackupJSONDataIncludingSecrets:secrets error:&error];
    if (!jsonData) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Export Failed" message:error.localizedDescription ?: @"Could not export configuration" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // Use system /tmp directly to avoid sandbox confusion for system app
    NSString *exportPath = [@"/tmp" stringByAppendingPathComponent:[RCBackup defaultFileName]];

    NSError *writeError = nil;
    BOOL written = [jsonData writeToFile:exportPath options:NSDataWritingAtomic error:&writeError];

    if (!written || writeError) {
        NSLog(@"[RemoteCompanion] Error writing export file: %@", writeError);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Export Error" message:[NSString stringWithFormat:@"Failed to write to:\n%@\n\n%@", exportPath, writeError.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Copy Path" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [UIPasteboard generalPasteboard].string = exportPath;
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // The file holds the stored passwords and tokens: keep the /tmp copy private
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:exportPath error:NULL];

    NSURL *fileURL = [NSURL fileURLWithPath:exportPath];
    if (!fileURL) {
         NSLog(@"[RemoteCompanion] Error: fileURL is nil");
         return;
    }

    // The share sheet renders app icons for AirDrop and other activities, which
    // crashes IconServices on this iPad. A document picker saves the file without
    // building those icons, and Save to Files is the usual destination anyway.
    // (The Backup section footer already says the file holds saved passwords and tokens.)
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL] asCopy:YES];
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importConfig {
    // iOS 14+ supported. Open in place keeps the picker's own flow; the read path
    // below falls back to a coordinated copy for provider-backed files.
    NSArray *types = @[[UTType typeWithIdentifier:@"public.json"], [UTType typeWithIdentifier:@"public.plain-text"]];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate (Import only)

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    // Scope access for open-in-place URLs. Provider-backed files can still refuse
    // a direct read, so fall back to a coordinated copy.
    BOOL accessing = [url startAccessingSecurityScopedResource];

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];

    if (!data) {
        NSError *coordError = nil;
        data = [self coordinatedCopyOfURL:url error:&coordError];
    }

    if (accessing) {
        [url stopAccessingSecurityScopedResource];
    }

    if (!data) {
        // The app is sandboxed, so provider files can stay unreadable even with a
        // security scope. The tweak runs in SpringBoard and can read them.
        data = [self readFileThroughTweak:url.path];
    }

    if (!data) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Failed" message:[NSString stringWithFormat:@"Could not read file: %@", readError.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    if ([RCBackup isFullBackupData:data]) {
        [self confirmFullBackupRestore:data];
    } else {
        // An older export: every key it has is applied, the files it never had are skipped
        [self confirmConfigImport:data];
    }
}

- (void)importConfigData:(NSData *)data {
    NSError *error = nil;
    BOOL success = [[RCConfigManager sharedManager] importConfigFromJSON:data error:&error];
    [self.tableView reloadData];

    if (success) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Complete" message:@"Settings and triggers are in place. Return to Triggers to see the changes." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        NSLog(@"[RemoteCompanion] Import Parsing Failed: %@", error);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Failed" message:error.localizedDescription ?: @"Invalid configuration file" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)confirmConfigImport:(NSData *)data {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Configuration?"
                                                                   message:@"Settings and triggers in the file are applied. Everything else on this device stays as it is, and an existing trigger is updated, not duplicated."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self importConfigData:data];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmFullBackupRestore:(NSData *)data {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Configuration?"
                                                                   message:@"This replaces all settings, triggers, integrations and add-ons on this device with the ones in the file."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error = nil;
        BOOL success = [RCBackup restoreFullBackupData:data error:&error];
        [self.tableView reloadData];

        UIAlertController *result = success
            ? [UIAlertController alertControllerWithTitle:@"Import Complete" message:@"Everything from the file is in place." preferredStyle:UIAlertControllerStyleAlert]
            : [UIAlertController alertControllerWithTitle:@"Import Failed" message:error.localizedDescription ?: @"Could not import the file" preferredStyle:UIAlertControllerStyleAlert];
        [result addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:result animated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"[RemoteCompanion] Import cancelled by user");
}

// Ask the tweak to read the file and hand back base64. The tweak lives in
// SpringBoard, outside the app sandbox, so iCloud Drive files are readable there.
- (NSData *)readFileThroughTweak:(NSString *)path {
    if (path.length == 0) return nil;
    NSString *encoded = [RCBackup sendTweakCommand:[NSString stringWithFormat:@"read file %@", path]];
    if (encoded.length == 0 || [encoded hasPrefix:@"Error"]) return nil;
    return [[NSData alloc] initWithBase64EncodedString:encoded options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

// Ask the file provider for a local copy. Works even when a direct read of the
// picked URL is refused, which is common for iCloud Drive and SMB sources.
- (NSData *)coordinatedCopyOfURL:(NSURL *)url error:(NSError **)error {
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block NSData *result = nil;
    __block NSError *copyError = nil;
    NSError *coordError = nil;

    [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingForUploading error:&coordError byAccessor:^(NSURL *newURL) {
        result = [NSData dataWithContentsOfURL:newURL options:0 error:&copyError];
    }];

    if (!result && error) *error = copyError ?: coordError;
    return result;
}

@end
