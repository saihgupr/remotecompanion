#import "RCBluetoothTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCServerClient.h"
#import <objc/runtime.h>
#import <dlfcn.h>

@interface BluetoothDevice : NSObject
- (NSString *)name;
- (NSString *)address;
@end

@interface BluetoothManager : NSObject
+ (instancetype)sharedInstance;
- (NSArray *)pairedDevices;
@end

@interface RCBluetoothTriggerViewController ()
@property (nonatomic, strong) NSArray *deviceNames;
@property (nonatomic, assign) BOOL isDisconnectTrigger;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, strong) NSString *triggerKey;
@end

@implementation RCBluetoothTriggerViewController

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _triggerKey = triggerKey;
    }
    return self;
}

- (instancetype)init {
    return [self initWithTriggerKey:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.triggerKey ? @"Edit Bluetooth" : @"New Bluetooth";
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applyTweaks) 
                                                 name:@"RCConfigTweaksChangedNotification" 
                                               object:nil];
    
    [self applyTweaks];
    if (self.triggerKey) {
        self.isDisconnectTrigger = [self.triggerKey hasPrefix:@"bt_disconnect_"];
    } else {
        self.isDisconnectTrigger = NO;
    }
    self.isLoading = YES;
    
    [self loadBluetoothDevices];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.navigationController.navigationBar.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
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


- (void)loadBluetoothDevices {
    [[RCServerClient sharedClient] executeCommand:@"bluetooth list" completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isLoading = NO;
            if (output && ![output isEqualToString:@"No paired Bluetooth devices found\n"] && ![output containsString:@"Error:"]) {
                NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                NSMutableArray *validNames = [NSMutableArray array];
                for (NSString *line in lines) {
                    NSString *cleanLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    // Skip empty lines or known unwanted output
                    if (cleanLine.length > 0 && ![cleanLine hasPrefix:@"*"]) {
                        [validNames addObject:cleanLine];
                    }
                }
                self.deviceNames = [validNames copy];
            } else {
                self.deviceNames = @[];
            }
            [self.tableView reloadData];
            
            if (!self.deviceNames || self.deviceNames.count == 0) {
                UILabel *emptyLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
                emptyLabel.text = @"No Paired Devices Found";
                emptyLabel.textAlignment = NSTextAlignmentCenter;
                emptyLabel.textColor = [UIColor secondaryLabelColor];
                self.tableView.backgroundView = emptyLabel;
            } else {
                self.tableView.backgroundView = nil;
            }
        });
    }];
}


#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2; // Connect / Disconnect
    if (self.isLoading) return 1; // Loading indicator
    return self.deviceNames.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Trigger Event";
    return @"Select Device";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    }
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Connected to Device";
            cell.accessoryType = !self.isDisconnectTrigger ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else {
            cell.textLabel.text = @"Disconnected from Device";
            cell.accessoryType = self.isDisconnectTrigger ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
        cell.detailTextLabel.text = nil;
        // This cell may be the reused Loading row: its spinner would hide the checkmark
        cell.accessoryView = nil;
    } else {
        if (self.isLoading) {
            cell.textLabel.text = @"Loading...";
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            cell.accessoryView = spinner;
            return cell;
        }
        
        NSString *deviceName = self.deviceNames[indexPath.row];
        cell.textLabel.text = deviceName;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 0) {
        self.isDisconnectTrigger = (indexPath.row == 1);
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    } else {
        if (self.isLoading) return;
        NSString *deviceName = self.deviceNames[indexPath.row];
        [self saveTriggerForDeviceName:deviceName];
    }
}
- (void)saveTriggerForDeviceName:(NSString *)name {
    if (!name || name.length == 0) return;
    
    NSString *prefix = self.isDisconnectTrigger ? @"bt_disconnect_" : @"bt_connect_";
    NSString *triggerKey = [prefix stringByAppendingString:name];
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    
    // Create friendly name
    NSString *subTitle = self.isDisconnectTrigger ? @"Disconnected from" : @"Connected to";
    NSString *friendlyName = [NSString stringWithFormat:@"%@ %@", subTitle, name];
    
    if (self.triggerKey) {
        // Handle migration if key changed
        if (![self.triggerKey isEqualToString:triggerKey]) {
            NSDictionary *oldData = [config triggerDataForKey:self.triggerKey];
            NSArray *actions = oldData[@"actions"] ?: @[];
            
            NSDictionary *newData = @{
                @"name": friendlyName,
                @"enabled": @YES,
                @"actions": actions
            };
            [config updateTrigger:triggerKey withData:newData];
            [config removeTrigger:self.triggerKey];
        } else {
            // Just update metadata
            NSMutableDictionary *mutableData = [[config triggerDataForKey:triggerKey] mutableCopy];
            mutableData[@"name"] = friendlyName;
            [config updateTrigger:triggerKey withData:mutableData];
        }
        
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        // Create new
        NSDictionary *triggerData = @{
            @"name": friendlyName,
            @"enabled": @YES,
            @"actions": @[]
        };
        [config updateTrigger:triggerKey withData:triggerData];
        
        // Redirect to action picker
        RCActionsViewController *vc = [[RCActionsViewController alloc] initWithTriggerKey:triggerKey];
        NSMutableArray *vcs = [self.navigationController.viewControllers mutableCopy];
        [vcs removeLastObject]; // Remove self
        [vcs addObject:vc];
        [self.navigationController setViewControllers:vcs animated:YES];
    }
}

@end
