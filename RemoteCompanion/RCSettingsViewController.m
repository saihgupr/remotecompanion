#import "RCSettingsViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"
#import "RCIntegrationsViewController.h"
#import "RCAdvancedSettingsViewController.h"
#import "RCTestKitViewController.h"
#import "RCRunningViewController.h"
#import "RCWebUIAccessViewController.h"
#import "RCVariablesViewController.h"
#import "RCVariableIcon.h"
#import "RCGesturesViewController.h"
#import "RCAddOnCatalog.h"
#import "RCAddOnsViewController.h"
#import "RCBackup.h"
#import "RCColorPickerViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <netinet/in.h>

@interface RCSettingsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *masterSwitch;
@property (nonatomic, strong) UISwitch *webUISwitch;
@end

// Sections of the Settings table, in order. Backup sits at the bottom.
typedef NS_ENUM(NSInteger, RCSettingsSection) {
    RCSettingsSectionGeneral,
    RCSettingsSectionIntegrations,
    RCSettingsSectionAdvanced,
    RCSettingsSectionGestures,
    RCSettingsSectionDiagnostics,
    RCSettingsSectionBackup,
};

@implementation RCSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Settings";
    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];

    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    // Close button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSettings)];
    
    // Setup Table View
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 50;
    
    // Improved Section Spacing
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
    }
    
    [self.view addSubview:self.tableView];

    // Footer lives at the bottom of the table content (tableFooterView) so it
    // only appears once you scroll to the bottom, instead of floating over content.
    [self setupFooterView];

    // Constraints - table fills the view, footer scrolls with content
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    // Listen for color tweak changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleTweaksChanged:)
                                                 name:@"RCConfigTweaksChangedNotification"
                                               object:nil];
    [self applyTweaks];
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

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RCSettingsSectionBackup + 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title;
    if (section == RCSettingsSectionGeneral) title = @"General";
    else if (section == RCSettingsSectionIntegrations) title = @"Integrations";
    else if (section == RCSettingsSectionAdvanced) title = @"Advanced Settings";
    else if (section == RCSettingsSectionGestures) title = @"Gestures";
    else if (section == RCSettingsSectionDiagnostics) title = @"Diagnostics";
    else title = @"Backup";
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, tableView.bounds.size.width - 40, 20)];
    label.text = [title uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40.0f;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCSettingsSectionGeneral) {
        return @"Enable the built-in Web UI to configure RemoteCompanion from a browser.";
    } else if (section == RCSettingsSectionIntegrations) {
        return @"Configure connections to external services and automations.";
    } else if (section == RCSettingsSectionAdvanced) {
        return @"NFC, banners, logging, and display options, and the variables that Set Variable actions save.";
    } else if (section == RCSettingsSectionGestures) {
        return @"Recorded gestures and the recording tab's options.";
    } else if (section == RCSettingsSectionDiagnostics) {
        return @"See what's running on this device, and run tests that share their results.";
    } else if (section == RCSettingsSectionBackup) {
        return @"Export saves everything on this device: settings, integrations, triggers, add-ons, gestures and variables. Import puts it back on any device. The file may include saved passwords and tokens, so keep it private.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RCSettingsSectionGeneral) {
        return [RCConfigManager sharedManager].webUIEnabled ? 4 : 2;
    }
    if (section == RCSettingsSectionBackup) {
        return 2; // Export / Import
    }
    if (section == RCSettingsSectionAdvanced) {
        return 2; // Advanced Settings / Variables
    }
    if (section == RCSettingsSectionDiagnostics) {
        return 2; // Running, Test Kit
    }
    if (section == RCSettingsSectionIntegrations) {
        // Integrations, then Add-ons (ADDONS.md) once the tweak has written its catalog
        return [RCAddOnCatalog catalogAvailable] ? 2 : 1;
    }
    if (section == RCSettingsSectionGestures) {
        return 2; // Gestures, Icon Color
    }
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    
    BOOL isLinkRow = (indexPath.section == RCSettingsSectionGeneral && indexPath.row >= 2) ||
                     (indexPath.section == RCSettingsSectionGestures && indexPath.row == 1);
    UITableViewCellStyle style = isLinkRow ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;

    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.masksToBounds = YES;
    cell.textLabel.textColor = [UIColor labelColor];
    if (cell.detailTextLabel) {
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    
    if (indexPath.section == RCSettingsSectionGeneral) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Enable All Triggers";
            _masterSwitch = [[UISwitch alloc] init];
            _masterSwitch.on = cm.masterEnabled;
            [_masterSwitch addTarget:self action:@selector(masterToggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = _masterSwitch;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Web UI";
            _webUISwitch = [[UISwitch alloc] init];
            _webUISwitch.on = cm.webUIEnabled;
            [_webUISwitch addTarget:self action:@selector(webUIToggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = _webUISwitch;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Access";
            cell.detailTextLabel.text = [RCWebUIAccessViewController titleForAccess:cm.webUIAccess];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Open Web UI";
            cell.detailTextLabel.text = [self webUIUrlString];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == RCSettingsSectionIntegrations && indexPath.row == 1) {
        cell.textLabel.text = @"Add-ons";
        cell.imageView.image = [UIImage systemImageNamed:[RCAddOnCatalog defaultSymbol]];
        cell.imageView.tintColor = [UIColor systemOrangeColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == RCSettingsSectionIntegrations) {
        cell.textLabel.text = @"Integrations";
        UIImage *puzzleImg = [UIImage systemImageNamed:@"puzzlepiece.extension.fill"];
        if (!puzzleImg) {
            puzzleImg = [UIImage systemImageNamed:@"network"];
        }
        cell.imageView.image = puzzleImg;
        cell.imageView.tintColor = [UIColor systemIndigoColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == RCSettingsSectionAdvanced && indexPath.row == 1) {
        cell.textLabel.text = @"Variables";
        cell.imageView.image = RCVariableMenuIcon();
        cell.imageView.tintColor = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == RCSettingsSectionAdvanced) {
        cell.textLabel.text = @"Advanced Settings";
        UIImage *img = [UIImage systemImageNamed:@"gearshape.2.fill"];
        if (!img) img = [UIImage systemImageNamed:@"gearshape"];
        cell.imageView.image = img;
        cell.imageView.tintColor = [UIColor systemPurpleColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == RCSettingsSectionGestures) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Gestures";
            cell.imageView.image = [UIImage systemImageNamed:@"hand.draw.fill"];
            cell.imageView.tintColor = [RCColorPickerViewController colorForName:cm.gesturesIconColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Icon Color";
            cell.imageView.image = [UIImage systemImageNamed:@"circle.fill"];
            cell.imageView.tintColor = [RCColorPickerViewController colorForName:cm.gesturesIconColor];
            cell.detailTextLabel.text = [RCColorPickerViewController titleForName:cm.gesturesIconColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == RCSettingsSectionBackup) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Export Configuration";
            cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
            cell.imageView.tintColor = [UIColor systemBlueColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Import Configuration";
            cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
            cell.imageView.tintColor = [UIColor systemGreenColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == RCSettingsSectionDiagnostics) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Running";
            cell.imageView.image = [UIImage systemImageNamed:@"list.bullet.rectangle"];
            cell.imageView.tintColor = [UIColor systemGreenColor];
        } else {
            cell.textLabel.text = @"Test Kit";
            cell.imageView.image = [UIImage systemImageNamed:@"checklist"] ?: [UIImage systemImageNamed:@"list.bullet.rectangle"];
            cell.imageView.tintColor = [UIColor systemTealColor];
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == RCSettingsSectionGeneral && indexPath.row == 2) {
        [self.navigationController pushViewController:[[RCWebUIAccessViewController alloc] init] animated:YES];
    } else if (indexPath.section == RCSettingsSectionGeneral && indexPath.row == 3) {
        [self openWebUI];
    } else if (indexPath.section == RCSettingsSectionIntegrations && indexPath.row == 1) {
        [self.navigationController pushViewController:[[RCAddOnsViewController alloc] initShowing:RCAddOnsListAll] animated:YES];
    } else if (indexPath.section == RCSettingsSectionIntegrations) {
        RCIntegrationsViewController *integrationsVC = [[RCIntegrationsViewController alloc] init];
        [self.navigationController pushViewController:integrationsVC animated:YES];
    } else if (indexPath.section == RCSettingsSectionAdvanced && indexPath.row == 1) {
        [self.navigationController pushViewController:[[RCVariablesViewController alloc] init] animated:YES];
    } else if (indexPath.section == RCSettingsSectionAdvanced) {
        [self.navigationController pushViewController:[[RCAdvancedSettingsViewController alloc] init] animated:YES];
    } else if (indexPath.section == RCSettingsSectionGestures) {
        if (indexPath.row == 0) {
            [self.navigationController pushViewController:[[RCGesturesViewController alloc] init] animated:YES];
        } else {
            [self presentGesturesIconColorPicker];
        }
    } else if (indexPath.section == RCSettingsSectionDiagnostics) {
        if (indexPath.row == 0) {
            [self.navigationController pushViewController:[[RCRunningViewController alloc] init] animated:YES];
        } else {
            [self.navigationController pushViewController:[[RCTestKitViewController alloc] init] animated:YES];
        }
    } else if (indexPath.section == RCSettingsSectionBackup) {
        if (indexPath.row == 0) {
            [self exportConfig];
        } else {
            [self importConfig];
        }
    }
}

#pragma mark - Actions

- (void)masterToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].masterEnabled = sender.on;
}

- (void)webUIToggleChanged:(UISwitch *)sender {
    [RCConfigManager sharedManager].webUIEnabled = sender.on;
    [self.tableView reloadData];
}

- (void)openWebUI {
    NSURL *url = [NSURL URLWithString:[self webUIUrlString]];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/saihgupr/RemoteCompanion"] options:@{} completionHandler:nil];
}

// A small popup of color swatches for the Gestures row icon. Picking one saves it
// and repaints the row, so the change is visible when the popup closes.
- (void)presentGesturesIconColorPicker {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    RCColorPickerViewController *picker = [[RCColorPickerViewController alloc] initWithSelectedName:cm.gesturesIconColor];
    __weak typeof(self) weakSelf = self;
    picker.onPick = ^(NSString *name) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [RCConfigManager sharedManager].gesturesIconColor = name;
        [strongSelf.tableView reloadData];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Backup / Import

- (void)exportConfig {
    // One file with the configuration and everything that lives beside it (add-ons,
    // gestures, notification filters, variables, blacklist), built by the tweak so
    // Import Configuration can put a new device back exactly as this one is.
    NSError *error = nil;
    NSData *jsonData = [RCBackup fullBackupJSONDataWithError:&error];
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
