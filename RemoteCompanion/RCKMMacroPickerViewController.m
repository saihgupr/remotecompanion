#import "RCKMMacroPickerViewController.h"
#import "RCKMSettingsViewController.h"
#import "RCConfigManager.h"
#import "RCUITweaker.h"

@interface RCKMInsecureSessionDelegate : NSObject <NSURLSessionDelegate>
+ (instancetype)sharedDelegate;
@end

@implementation RCKMInsecureSessionDelegate
+ (instancetype)sharedDelegate {
    static RCKMInsecureSessionDelegate *del = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        del = [[RCKMInsecureSessionDelegate alloc] init];
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

@interface RCKMMacroPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *allGroups;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredGroups;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL loadOnReturn; // back from Set Up: load the list
@end

@implementation RCKMMacroPickerViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.loadOnReturn) {
        self.loadOnReturn = NO;
        [self fetchMacros];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Keyboard Maestro";
    
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *pickerBG = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = pickerBG;
    self.tableView.backgroundColor = pickerBG;
    
    self.tableView.rowHeight = 60;
    
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Macros & Groups";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Manual" style:UIBarButtonItemStylePlain target:self action:@selector(promptManualEntry)];
    
    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(fetchMacros) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refresh;
    
    [self fetchMacros];
}

static NSString *rc_km_decode_entities(NSString *str) {
    if (!str) return @"";
    NSString *d = [str stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    d = [d stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    d = [d stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    d = [d stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    d = [d stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    d = [d stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    d = [d stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    return d;
}

static NSArray<NSDictionary *> *rc_km_parse_macro_html(NSString *html) {
    if (!html || html.length == 0) return @[];
    
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groupsMap = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *groupOrder = [NSMutableArray array];
    
    NSRegularExpression *optgroupRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)<optgroup\\s+[^>]*label=\"([^\"]+)\"[^>]*>([\\s\\S]*?)(?:</optgroup>|(?=<optgroup)|$)" options:0 error:nil];
    NSRegularExpression *optionRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)<option\\b([^>]+)>" options:0 error:nil];
    NSRegularExpression *labelAttrRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\blabel=\"([^\"]+)\"" options:0 error:nil];
    NSRegularExpression *valueAttrRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\bvalue=\"([^\"]+)\"" options:0 error:nil];
    
    NSMutableDictionary *nameBatch = [NSMutableDictionary dictionary];
    NSArray<NSTextCheckingResult *> *groupMatches = [optgroupRegex matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    for (NSTextCheckingResult *gMatch in groupMatches) {
        if (gMatch.numberOfRanges < 3) continue;
        NSString *rawGroupName = [html substringWithRange:[gMatch rangeAtIndex:1]];
        NSString *groupName = rc_km_decode_entities([rawGroupName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
        if (groupName.length == 0) continue;
        
        NSRange contentRange = [gMatch rangeAtIndex:2];
        if (contentRange.location == NSNotFound || contentRange.length == 0) continue;
        NSString *groupContent = [html substringWithRange:contentRange];
        
        NSMutableArray *macros = [NSMutableArray array];
        NSArray<NSTextCheckingResult *> *optMatches = [optionRegex matchesInString:groupContent options:0 range:NSMakeRange(0, groupContent.length)];
        for (NSTextCheckingResult *oMatch in optMatches) {
            NSString *tagAttrs = [groupContent substringWithRange:[oMatch rangeAtIndex:1]];
            
            NSTextCheckingResult *lMatch = [labelAttrRegex firstMatchInString:tagAttrs options:0 range:NSMakeRange(0, tagAttrs.length)];
            NSTextCheckingResult *vMatch = [valueAttrRegex firstMatchInString:tagAttrs options:0 range:NSMakeRange(0, tagAttrs.length)];
            
            if (lMatch && lMatch.numberOfRanges >= 2 && vMatch && vMatch.numberOfRanges >= 2) {
                NSString *macroName = rc_km_decode_entities([[tagAttrs substringWithRange:[lMatch rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
                NSString *macroUid = [[tagAttrs substringWithRange:[vMatch rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (macroName.length > 0 && macroUid.length > 0) {
                    nameBatch[macroUid] = macroName;
                    [macros addObject:@{
                        @"name": macroName,
                        @"uid": macroUid
                    }];
                }
            }
        }
        
        if (macros.count == 0) continue;
        
        NSString *groupKey = [groupName lowercaseString];
        NSMutableDictionary *existingGroup = groupsMap[groupKey];
        if (existingGroup) {
            NSMutableArray *existingMacros = existingGroup[@"macros"];
            NSMutableSet *existingUids = [NSMutableSet set];
            for (NSDictionary *m in existingMacros) {
                if (m[@"uid"]) [existingUids addObject:m[@"uid"]];
            }
            for (NSDictionary *m in macros) {
                if (![existingUids containsObject:m[@"uid"]]) {
                    [existingMacros addObject:m];
                    [existingUids addObject:m[@"uid"]];
                }
            }
        } else {
            NSMutableDictionary *newGroup = [NSMutableDictionary dictionaryWithDictionary:@{
                @"name": groupName,
                @"macros": macros
            }];
            groupsMap[groupKey] = newGroup;
            [groupOrder addObject:groupKey];
        }
    }
    
    if (nameBatch.count > 0) {
        [[RCConfigManager sharedManager] registerKMMacroNamesBatch:nameBatch];
    }
    
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in groupOrder) {
        if (groupsMap[key]) {
            [result addObject:groupsMap[key]];
        }
    }
    return result;
}

- (void)fetchMacros {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    if (!cm.kmUrl.length) {
        [self.tableView.refreshControl endRefreshing];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Keyboard Maestro Not Configured"
                                                                       message:@"Set up your Keyboard Maestro web server's URL to pick a macro, or enter one by hand."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        // Set Up opens its settings here; back from them, the list loads
        UIAlertAction *setUp = [UIAlertAction actionWithTitle:@"Set Up" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            self.loadOnReturn = YES;
            [self.navigationController pushViewController:[[RCKMSettingsViewController alloc] init] animated:YES];
        }];
        [alert addAction:setUp];
        alert.preferredAction = setUp;
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
    
    NSString *base = cm.kmUrl;
    if (![base hasPrefix:@"http://"] && !([base hasPrefix:@"https://"])) {
        base = [NSString stringWithFormat:@"http://%@", base];
    }
    if ([base hasSuffix:@"/action.html"]) {
        base = [base substringToIndex:base.length - 12];
    } else if ([base hasSuffix:@"/authenticatedaction.html"]) {
        base = [base substringToIndex:base.length - 25];
    } else if ([base hasSuffix:@"/authenticated.html"]) {
        base = [base substringToIndex:base.length - 19];
    }
    if ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/authenticated.html", base]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
    
    if (cm.kmUser.length > 0 || cm.kmPassword.length > 0) {
        NSString *authStr = [NSString stringWithFormat:@"%@:%@", cm.kmUser ?: @"", cm.kmPassword ?: @""];
        NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64 = [authData base64EncodedStringWithOptions:0];
        [req setValue:[NSString stringWithFormat:@"Basic %@", base64] forHTTPHeaderField:@"Authorization"];
    }
    
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = 10.0;
    sessionConfig.timeoutIntervalForResource = 10.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:[RCKMInsecureSessionDelegate sharedDelegate] delegateQueue:nil];
    
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView.refreshControl endRefreshing];
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Manual" style:UIBarButtonItemStylePlain target:self action:@selector(promptManualEntry)];
            
            NSHTTPURLResponse *httpRes = (NSHTTPURLResponse *)res;
            if (!err && httpRes.statusCode == 200 && data) {
                NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSArray<NSDictionary *> *groups = rc_km_parse_macro_html(html);
                if (groups.count > 0) {
                    self.allGroups = groups;
                    [self updateFilteredResults];
                    [self.tableView reloadData];
                    return;
                }
            }
            
            // Error handling
            NSString *msg = err ? err.localizedDescription : (httpRes.statusCode == 401 ? @"Authentication failed (check Web Server username/password)" : [NSString stringWithFormat:@"HTTP Error %ld", (long)httpRes.statusCode]);
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Failed to Load Macros"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Retry" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [self fetchMacros];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Manual Entry" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [self promptManualEntry];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }] resume];
}

- (void)promptManualEntry {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Keyboard Maestro Macro"
                                                                   message:@"Enter Macro Name or UUID (and optional trigger value):"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Macro Name or UUID (e.g. Sleep Display)";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Trigger Value / Parameter (optional)";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *macro = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *val = [alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!macro.length) return;
        
        NSString *cmd;
        if (val.length) {
            cmd = [NSString stringWithFormat:@"km trigger \"%@\" \"%@\"", macro, val];
        } else {
            cmd = [NSString stringWithFormat:@"km trigger \"%@\"", macro];
        }
        if (self.onMacroSelected) self.onMacroSelected(cmd);
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateFilteredResults {
    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (!query.length) {
        self.filteredGroups = self.allGroups;
    } else {
        NSMutableArray *res = [NSMutableArray array];
        for (NSDictionary *group in self.allGroups) {
            NSString *groupName = [group[@"name"] lowercaseString];
            NSArray *macros = group[@"macros"];
            NSMutableArray *matchingMacros = [NSMutableArray array];
            
            for (NSDictionary *m in macros) {
                NSString *name = [m[@"name"] lowercaseString];
                NSString *uid = [m[@"uid"] lowercaseString];
                if ([name containsString:query] || [uid containsString:query] || [groupName containsString:query]) {
                    [matchingMacros addObject:m];
                }
            }
            
            if (matchingMacros.count > 0) {
                [res addObject:@{
                    @"name": group[@"name"] ?: @"",
                    @"macros": [matchingMacros copy]
                }];
            }
        }
        self.filteredGroups = [res copy];
    }
}

#pragma mark - Search Results Updating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self updateFilteredResults];
    [self.tableView reloadData];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.filteredGroups.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section < self.filteredGroups.count) {
        NSDictionary *group = self.filteredGroups[section];
        NSArray *macros = group[@"macros"];
        return [NSString stringWithFormat:@"%@ (%lu)", group[@"name"] ?: @"Group", (unsigned long)macros.count];
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < self.filteredGroups.count) {
        NSArray *macros = self.filteredGroups[section][@"macros"];
        return macros.count;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"KMCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"KMCell"];
    }
    
    RCConfigManager *cm = [RCConfigManager sharedManager];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.layer.borderColor = [cm tweakColorForKey:@"borders" defaultVal:0.14].CGColor;
    cell.layer.borderWidth = 1.0;
    cell.layer.masksToBounds = YES;
    
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    
    NSDictionary *group = self.filteredGroups[indexPath.section];
    NSArray *macros = group[@"macros"];
    NSDictionary *macro = macros[indexPath.row];
    
    cell.textLabel.text = macro[@"name"] ?: @"Macro";
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    
    cell.imageView.image = [UIImage systemImageNamed:@"command"];
    cell.imageView.tintColor = [UIColor systemOrangeColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *group = self.filteredGroups[indexPath.section];
    NSArray *macros = group[@"macros"];
    NSDictionary *macro = macros[indexPath.row];
    NSString *macroName = macro[@"name"] ?: @"";
    NSString *macroUid = macro[@"uid"] ?: @"";
    
    if (macroUid.length > 0 && macroName.length > 0) {
        [[RCConfigManager sharedManager] registerKMMacroName:macroName forUid:macroUid];
    }
    
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:macroName
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"Trigger (No Parameter)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *target = macroUid.length > 0 ? macroUid : [NSString stringWithFormat:@"\"%@\"", macroName];
        NSString *cmd = [NSString stringWithFormat:@"km trigger %@", target];
        if (self.onMacroSelected) self.onMacroSelected(cmd);
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"Trigger with Parameter…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIAlertController *paramAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Trigger: %@", macroName]
                                                                            message:@"Enter optional trigger parameter/value passed to KM %TriggerValue%:"
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [paramAlert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = @"Parameter / Value (optional)";
            tf.autocorrectionType = UITextAutocorrectionTypeNo;
            tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];
        [paramAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [paramAlert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *pAction) {
            NSString *val = [paramAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *target = macroUid.length > 0 ? macroUid : [NSString stringWithFormat:@"\"%@\"", macroName];
            NSString *cmd;
            if (val.length > 0) {
                cmd = [NSString stringWithFormat:@"km trigger %@ \"%@\"", target, val];
            } else {
                cmd = [NSString stringWithFormat:@"km trigger %@", target];
            }
            if (self.onMacroSelected) self.onMacroSelected(cmd);
            [self.navigationController popViewControllerAnimated:YES];
        }]];
        [self presentViewController:paramAlert animated:YES completion:nil];
    }]];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    if (sheet.popoverPresentationController) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
