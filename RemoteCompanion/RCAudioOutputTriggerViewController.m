#import "RCAudioOutputTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCServerClient.h"
#import <objc/runtime.h>
#import <dlfcn.h>

@interface RCAudioOutputTriggerViewController ()
@property (nonatomic, strong) NSArray *deviceNames;
@property (nonatomic, assign) BOOL isDisconnectTrigger;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, strong) NSString *triggerKey;
@end

@implementation RCAudioOutputTriggerViewController

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
    self.title = self.triggerKey ? @"Edit Audio Output" : @"New Audio Output";
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applyTweaks) 
                                                 name:@"RCConfigTweaksChangedNotification" 
                                               object:nil];
    
    [self applyTweaks];
    if (self.triggerKey) {
        self.isDisconnectTrigger = [self.triggerKey hasPrefix:@"output_unset_"];
    } else {
        self.isDisconnectTrigger = NO;
    }
    self.isLoading = YES;
    
    [self loadAudioOutputs];
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


// Device names from a list command's output, one per line
static NSArray *RCOutputNamesFromListOutput(NSString *output) {
    NSMutableArray *names = [NSMutableArray array];
    if (!output || [output containsString:@"Error:"] || [output hasPrefix:@"No "]) return names;
    for (NSString *line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *clean = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([clean containsString:@" # "]) clean = [clean componentsSeparatedByString:@" # "].lastObject;
        if ([clean isEqualToString:@"Speaker"]) clean = @"iPhone"; // how the phone's own output is named in a trigger
        if (clean.length > 0 && ![clean hasPrefix:@"*"]) [names addObject:clean];
    }
    return names;
}

// AirPlay devices and paired Bluetooth devices, together
- (void)loadAudioOutputs {
    RCServerClient *client = [RCServerClient sharedClient];
    [client executeCommand:@"airplay list" completion:^(NSString * _Nullable airplay, NSError * _Nullable error) {
        [client executeCommand:@"bluetooth list" completion:^(NSString * _Nullable bluetooth, NSError * _Nullable error2) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isLoading = NO;
                NSMutableArray *names = [NSMutableArray array];
                for (NSString *name in [RCOutputNamesFromListOutput(airplay) arrayByAddingObjectsFromArray:RCOutputNamesFromListOutput(bluetooth)]) {
                    if (![names containsObject:name]) [names addObject:name];
                }
                self.deviceNames = names;
                [self.tableView reloadData];

                if (names.count == 0) {
                    UILabel *emptyLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
                    emptyLabel.text = @"No Devices Found";
                    emptyLabel.textAlignment = NSTextAlignmentCenter;
                    emptyLabel.textColor = [UIColor secondaryLabelColor];
                    self.tableView.backgroundView = emptyLabel;
                } else {
                    self.tableView.backgroundView = nil;
                }
            });
        }];
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
            cell.textLabel.text = @"Set as Output";
            cell.accessoryType = !self.isDisconnectTrigger ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else {
            cell.textLabel.text = @"Unset as Output";
            cell.accessoryType = self.isDisconnectTrigger ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
        cell.detailTextLabel.text = nil;
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
    
    NSString *prefix = self.isDisconnectTrigger ? @"output_unset_" : @"output_set_";
    NSString *triggerKey = [prefix stringByAppendingString:name];
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    
    // Create friendly name
    NSString *subTitle = self.isDisconnectTrigger ? @"Output Unset:" : @"Output Set:";
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
