#import "RCHAEntityPickerViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"

@interface RCHAInsecureSessionDelegate : NSObject <NSURLSessionDelegate>
+ (instancetype)sharedDelegate;
@end

@implementation RCHAInsecureSessionDelegate
+ (instancetype)sharedDelegate {
    static RCHAInsecureSessionDelegate *del = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        del = [[RCHAInsecureSessionDelegate alloc] init];
    });
    return del;
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}
@end

@interface RCHAEntityPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *allEntities;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredEntities;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSString *currentEntityId;
@property (nonatomic, copy) NSString *currentService;
@property (nonatomic, assign) BOOL presentedCurrentChoices;
@end

static void rc_ha_mark_action_selected(UIAlertAction *action, BOOL selected) {
    if (!selected) return;
    @try { [action setValue:@(YES) forKey:@"checked"]; } @catch (NSException *e) {}
}

@implementation RCHAEntityPickerViewController

+ (BOOL)parseCommand:(NSString *)command entityId:(NSString **)entityId service:(NSString **)service {
    if (entityId) *entityId = nil;
    if (service) *service = nil;
    if (![command isKindOfClass:[NSString class]]) return NO;

    NSString *raw = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![raw hasPrefix:@"ha "]) return NO;
    raw = [[raw substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (part.length > 0) [parts addObject:part];
    }
    if (parts.count < 2) return NO;

    NSString *subCmd = [parts[0] lowercaseString];
    if ([subCmd isEqualToString:@"raw"]) return NO; // raw JSON doesn't map to an entity action

    NSString *eid = parts[1];
    NSString *serviceName = nil;
    if ([subCmd isEqualToString:@"call"]) {
        if (parts.count < 3) return NO;
        serviceName = [parts[1] lowercaseString];
        eid = parts[2];
        if (![serviceName containsString:@"."]) return NO;
    } else if ([subCmd isEqualToString:@"toggle"] || [subCmd isEqualToString:@"turn_on"] || [subCmd isEqualToString:@"turn_off"]) {
        NSString *domain = [eid componentsSeparatedByString:@"."].firstObject;
        serviceName = [NSString stringWithFormat:@"%@.%@", domain, subCmd];
    } else if ([subCmd containsString:@"."]) {
        serviceName = subCmd;
    } else {
        NSString *domain = [eid componentsSeparatedByString:@"."].firstObject;
        serviceName = [NSString stringWithFormat:@"%@.%@", domain, subCmd];
    }

    if (![eid containsString:@"."] || !serviceName.length) return NO;
    if (entityId) *entityId = eid;
    if (service) *service = serviceName;
    return YES;
}

+ (NSString *)friendlyNameForEntity:(NSString *)entityId {
    if (![entityId isKindOfClass:[NSString class]]) return @"";
    NSArray *parts = [entityId componentsSeparatedByString:@"."];
    NSString *name = parts.count > 1 ? parts[1] : entityId;
    name = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    return [name capitalizedString];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Home Assistant";
    
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *pickerBG = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = pickerBG;
    self.tableView.backgroundColor = pickerBG;
    
    self.tableView.rowHeight = 64;
    
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Entities";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Manual" style:UIBarButtonItemStylePlain target:self action:@selector(promptManualEntry)];
    
    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(fetchEntities) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refresh;
    
    NSString *editingEntity = nil;
    NSString *editingService = nil;
    BOOL hasEditingEntity = [RCHAEntityPickerViewController parseCommand:self.editingCommand entityId:&editingEntity service:&editingService];
    self.currentEntityId = editingEntity;
    self.currentService = editingService;

    // Editing the action for one entity needs no network round trip, and an offline Home
    // Assistant shouldn't put an error in front of the choices.
    if (!(self.opensOnCurrentChoices && hasEditingEntity)) {
        [self fetchEntities];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.opensOnCurrentChoices && !self.presentedCurrentChoices && self.currentEntityId.length) {
        self.presentedCurrentChoices = YES;
        [self presentChoicesForEntity:self.currentEntityId fromIndexPath:nil];
    }
}

- (void)fetchEntities {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if (!cm.haUrl.length || !cm.haToken.length) {
        [self.tableView.refreshControl endRefreshing];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Home Assistant Not Configured"
                                                                       message:@"Please configure your Home Assistant Server URL and Access Token in Settings."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Manual Entry" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self promptManualEntry];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
            [self.navigationController popViewControllerAnimated:YES];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [_spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:_spinner];
    
    NSString *base = cm.haUrl;
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/states", base]];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 10.0;
    [req setValue:[NSString stringWithFormat:@"Bearer %@", cm.haToken] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 10.0;
    config.timeoutIntervalForResource = 10.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:[RCHAInsecureSessionDelegate sharedDelegate] delegateQueue:nil];
    
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView.refreshControl endRefreshing];
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Manual" style:UIBarButtonItemStylePlain target:self action:@selector(promptManualEntry)];
            
            NSHTTPURLResponse *httpRes = (NSHTTPURLResponse *)res;
            if (!err && httpRes.statusCode == 200 && data) {
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([json isKindOfClass:[NSArray class]]) {
                    NSArray *supportedDomains = @[@"light", @"switch", @"scene", @"script", @"automation", @"media_player", @"cover", @"climate", @"lock", @"fan", @"button", @"input_boolean", @"vacuum", @"camera"];
                    NSMutableArray *valid = [NSMutableArray array];
                    for (NSDictionary *entity in (NSArray *)json) {
                        if (![entity isKindOfClass:[NSDictionary class]]) continue;
                        NSString *eid = entity[@"entity_id"];
                        if (!eid.length) continue;
                        NSString *domain = [eid componentsSeparatedByString:@"."].firstObject;
                        if ([supportedDomains containsObject:domain]) {
                            [valid addObject:entity];
                        }
                    }
                    
                    [valid sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                        NSString *nameA = a[@"attributes"][@"friendly_name"] ?: a[@"entity_id"];
                        NSString *nameB = b[@"attributes"][@"friendly_name"] ?: b[@"entity_id"];
                        return [nameA localizedCaseInsensitiveCompare:nameB];
                    }];
                    
                    self.allEntities = [valid copy];
                    [self updateFilteredResults];
                    [self.tableView reloadData];
                    [self scrollToCurrentEntity];
                    return;
                }
            }
            
            // Error handling
            NSString *msg = err ? err.localizedDescription : (httpRes.statusCode == 401 ? @"Unauthorized (check HA token)" : [NSString stringWithFormat:@"HTTP Error %ld", (long)httpRes.statusCode]);
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Failed to Load Entities"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Retry" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [self fetchEntities];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Manual Entry" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [self promptManualEntry];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }] resume];
}

- (void)scrollToCurrentEntity {
    if (!self.currentEntityId.length || self.filteredEntities.count == 0) return;
    for (NSUInteger row = 0; row < self.filteredEntities.count; row++) {
        if ([self.filteredEntities[row][@"entity_id"] isEqualToString:self.currentEntityId]) {
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
                                  atScrollPosition:UITableViewScrollPositionMiddle
                                          animated:NO];
            return;
        }
    }
}

- (void)promptManualEntry {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Home Assistant Command"
                                                                   message:@"Enter Home Assistant command or entity ID (e.g. toggle light.bedroom or call light.turn_on light.bedroom):"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"toggle light.bedroom";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *val = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!val.length) return;
        NSString *cmd = [val hasPrefix:@"ha "] ? val : [NSString stringWithFormat:@"ha %@", val];
        if (self.onEntitySelected) self.onEntitySelected(cmd);
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateFilteredResults {
    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (!query.length) {
        self.filteredEntities = self.allEntities;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *entity, NSDictionary *bindings) {
            NSString *eid = [entity[@"entity_id"] lowercaseString];
            NSString *name = [entity[@"attributes"][@"friendly_name"] lowercaseString];
            return [eid containsString:query] || (name && [name containsString:query]);
        }];
        self.filteredEntities = [self.allEntities filteredArrayUsingPredicate:pred];
    }
}

#pragma mark - Search Results Updating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self updateFilteredResults];
    [self.tableView reloadData];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredEntities.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HACell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"HACell"];
    }
    
    RCConfigManager *cm = [RCConfigManager sharedManager];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.layer.masksToBounds = YES;
    
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    
    NSDictionary *entity = self.filteredEntities[indexPath.row];
    NSString *eid = entity[@"entity_id"] ?: @"";
    NSString *friendlyName = entity[@"attributes"][@"friendly_name"] ?: eid;
    NSString *state = entity[@"state"] ?: @"";
    NSString *domain = [eid componentsSeparatedByString:@"."].firstObject;
    
    cell.textLabel.text = friendlyName;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", eid, state];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    
    NSString *symbolName = @"house.fill";
    UIColor *symbolColor = [UIColor systemBlueColor];
    
    if ([domain isEqualToString:@"light"]) {
        symbolName = @"lightbulb.fill";
        symbolColor = [UIColor systemYellowColor];
    } else if ([domain isEqualToString:@"switch"]) {
        symbolName = @"power";
        symbolColor = [UIColor systemGreenColor];
    } else if ([domain isEqualToString:@"scene"]) {
        symbolName = @"sparkles";
        symbolColor = [UIColor systemPurpleColor];
    } else if ([domain isEqualToString:@"script"]) {
        symbolName = @"command";
        symbolColor = [UIColor systemIndigoColor];
    } else if ([domain isEqualToString:@"automation"]) {
        symbolName = @"gearshape.2.fill";
        symbolColor = [UIColor systemOrangeColor];
    } else if ([domain isEqualToString:@"media_player"]) {
        symbolName = @"play.circle.fill";
        symbolColor = [UIColor systemPinkColor];
    } else if ([domain isEqualToString:@"cover"]) {
        symbolName = @"slider.horizontal.3";
        symbolColor = [UIColor systemGrayColor];
    } else if ([domain isEqualToString:@"lock"]) {
        symbolName = @"lock.fill";
        symbolColor = [UIColor systemRedColor];
    } else if ([domain isEqualToString:@"fan"]) {
        symbolName = @"fanblades.fill";
        symbolColor = [UIColor systemTealColor];
    }
    
    cell.imageView.image = [UIImage systemImageNamed:symbolName];
    cell.imageView.tintColor = symbolColor;
    BOOL isCurrentEntity = self.editingCommand.length > 0 && [eid isEqualToString:self.currentEntityId];
    cell.accessoryType = isCurrentEntity ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *entity = self.filteredEntities[indexPath.row];
    NSString *eid = entity[@"entity_id"] ?: @"";
    if (!eid.length) return;

    // Scenes, scripts and automations have just one possible action, so adding one goes
    // straight in. While editing, show the choices so the current action is visible.
    NSString *fixedAction = [self fixedActionForEntity:eid];
    if (fixedAction.length && !self.editingCommand.length) {
        if (self.onEntitySelected) self.onEntitySelected([self commandForEntity:eid action:fixedAction]);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    [self presentChoicesForEntity:eid fromIndexPath:indexPath];
}

- (NSString *)fixedActionForEntity:(NSString *)eid {
    NSString *domain = [eid componentsSeparatedByString:@"."].firstObject;
    if ([domain isEqualToString:@"scene"]) return @"scene.turn_on";
    if ([domain isEqualToString:@"script"]) {
        return [NSString stringWithFormat:@"script.%@", [eid componentsSeparatedByString:@"."].lastObject];
    }
    if ([domain isEqualToString:@"automation"]) return @"automation.trigger";
    return nil;
}

- (NSString *)serviceForEntity:(NSString *)eid action:(NSString *)action {
    if ([action isEqualToString:@"toggle"] || [action isEqualToString:@"turn_on"] || [action isEqualToString:@"turn_off"]) {
        NSString *domain = [eid componentsSeparatedByString:@"."].firstObject;
        return [NSString stringWithFormat:@"%@.%@", domain, action];
    }
    return action;
}

- (NSString *)commandForEntity:(NSString *)eid action:(NSString *)action {
    if ([action isEqualToString:@"toggle"] || [action isEqualToString:@"turn_on"] || [action isEqualToString:@"turn_off"]) {
        return [NSString stringWithFormat:@"ha %@ %@", action, eid];
    }
    return [NSString stringWithFormat:@"ha call %@ %@", action, eid];
}

- (void)addChoiceToSheet:(UIAlertController *)sheet title:(NSString *)title entity:(NSString *)eid action:(NSString *)action {
    NSString *service = [self serviceForEntity:eid action:action];
    NSString *command = [self commandForEntity:eid action:action];
    UIAlertAction *choice = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (self.onEntitySelected) self.onEntitySelected(command);
        [self.navigationController popViewControllerAnimated:YES];
    }];
    BOOL shortAction = [action isEqualToString:@"toggle"] || [action isEqualToString:@"turn_on"] || [action isEqualToString:@"turn_off"];
    NSString *currentVerb = [self.currentService componentsSeparatedByString:@"."].lastObject;
    BOOL selected = [service isEqualToString:self.currentService] || (shortAction && [currentVerb isEqualToString:action]);
    rc_ha_mark_action_selected(choice, selected);
    [sheet addAction:choice];
}

- (void)presentChoicesForEntity:(NSString *)eid fromIndexPath:(NSIndexPath *)indexPath {
    NSString *domain = [eid componentsSeparatedByString:@"."].firstObject;
    NSString *friendlyName = [RCHAEntityPickerViewController friendlyNameForEntity:eid];
    // Adding keeps the original "Toggle (Friendly Name)" labels; editing uses the sheet's
    // title for the name so the ticked choice stays short.
    NSString *suffix = self.editingCommand.length > 0 ? @"" : [NSString stringWithFormat:@" (%@)", friendlyName];
    
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:friendlyName
                                                                   message:eid
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    if ([domain isEqualToString:@"scene"]) {
        [self addChoiceToSheet:sheet title:@"Activate Scene" entity:eid action:@"scene.turn_on"];
    } else if ([domain isEqualToString:@"script"]) {
        [self addChoiceToSheet:sheet title:@"Run Script" entity:eid
                        action:[NSString stringWithFormat:@"script.%@", [eid componentsSeparatedByString:@"."].lastObject]];
    } else if ([domain isEqualToString:@"automation"]) {
        [self addChoiceToSheet:sheet title:@"Trigger Automation" entity:eid action:@"automation.trigger"];
    } else {
        [self addChoiceToSheet:sheet title:[@"Toggle" stringByAppendingString:suffix] entity:eid action:@"toggle"];
        [self addChoiceToSheet:sheet title:[@"Turn On" stringByAppendingString:suffix] entity:eid action:@"turn_on"];
        [self addChoiceToSheet:sheet title:[@"Turn Off" stringByAppendingString:suffix] entity:eid action:@"turn_off"];
    }
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        if (self.opensOnCurrentChoices) [self.navigationController popViewControllerAnimated:YES];
    }]];
    
    if (sheet.popoverPresentationController) {
        UITableViewCell *cell = indexPath ? [self.tableView cellForRowAtIndexPath:indexPath] : nil;
        if (cell) {
            sheet.popoverPresentationController.sourceView = cell;
            sheet.popoverPresentationController.sourceRect = cell.bounds;
        } else {
            sheet.popoverPresentationController.sourceView = self.view;
            sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        }
    }
    
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
