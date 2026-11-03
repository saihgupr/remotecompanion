#import "RCShortcutPickerViewController.h"
#import "RCServerClient.h"
#import <dlfcn.h>
#import <objc/runtime.h>

@interface NSTask : NSObject
@property (copy) NSString *launchPath;
@property (copy) NSArray *arguments;
@property (retain) id standardOutput;
@property (retain) id standardError;
- (void)launch;
- (void)waitUntilExit;
@end

@interface RCShortcutPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSString *> *shortcuts;
@property (nonatomic, strong) NSArray<NSString *> *filteredShortcuts;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation RCShortcutPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Select Shortcut";
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ShortcutCell"];
    self.tableView.rowHeight = 60; // Consistent sizing
    
    // Setup Search
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Shortcuts";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    
    if (self.showsSilentOption) self.tableView.tableHeaderView = [self silentOptionHeader];
    [self loadShortcuts];
}

- (UIView *)silentOptionHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 64)];
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemBackgroundColor];
    card.layer.cornerRadius = 10;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:card];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Run Silently";
    label.font = [UIFont systemFontOfSize:17];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:label];

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = self.runSilently;
    [toggle addTarget:self action:@selector(silentSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:toggle];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
        [label.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [label.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [toggle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [toggle.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-8],
    ]];
    return header;
}

- (void)silentSwitchChanged:(UISwitch *)sender {
    self.runSilently = sender.on;
}

- (void)loadShortcuts {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *results = [NSMutableArray array];
        NSMutableString *debugLog = [NSMutableString string];

        // From the tweak, which reads them from the Shortcuts database (no SpringCuts needed)
        dispatch_semaphore_t listed = dispatch_semaphore_create(0);
        __block NSString *listOutput = nil;
        [[RCServerClient sharedClient] executeCommand:@"shortcuts list" completion:^(NSString *output, NSError *error) {
            listOutput = output;
            dispatch_semaphore_signal(listed);
        }];
        BOOL answered = dispatch_semaphore_wait(listed, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC))) == 0;
        for (NSString *line in [listOutput componentsSeparatedByString:@"\n"]) {
            if (line.length && ![results containsObject:line]) [results addObject:line];
        }
        BOOL listedByTweak = listOutput.length > 0; // a lone newline: no shortcuts
        if (!listedByTweak) [debugLog appendFormat:@"%@\nLoading via springcuts -l...\n", answered ? @"No list from RemoteCompanion" : @"RemoteCompanion didn't answer"];

        if (!listedByTweak) @try {
            Class NSTaskClass = NSClassFromString(@"NSTask");
            if (!NSTaskClass) {
                 [debugLog appendString:@"❌ NSTask class not found\n"];
            } else {
                id task = [[NSTaskClass alloc] init];
                
                // Use performSelector/KVC to set properties if simpler, or cast to 'id'
                [task performSelector:@selector(setLaunchPath:) withObject:@"/var/jb/usr/bin/springcuts"];
                
                NSString *binPath = @"/var/jb/usr/bin/springcuts";
                if (![[NSFileManager defaultManager] fileExistsAtPath:binPath]) {
                     binPath = @"/usr/bin/springcuts";
                     [task performSelector:@selector(setLaunchPath:) withObject:binPath];
                }
                
                [task performSelector:@selector(setArguments:) withObject:@[@"-l"]];
                
                NSPipe *outPipe = [NSPipe pipe];
                [task performSelector:@selector(setStandardOutput:) withObject:outPipe];
                
                [task performSelector:@selector(launch)];
                
                NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
                [task performSelector:@selector(waitUntilExit)];
                
                NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                
                if (output.length > 0) {
                    // Parse output...
                NSArray *lines = [output componentsSeparatedByString:@"\n"];
                for (NSString *line in lines) {
                    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (trimmed.length > 0 && ![trimmed isEqualToString:@"Shortcut names:"]) {
                        // Remove trailing comma if present
                        if ([trimmed hasSuffix:@","]) {
                            trimmed = [trimmed substringToIndex:trimmed.length - 1];
                        }
                        [results addObject:trimmed];
                    }
                }
            } else {
                 [debugLog appendString:@"❌ No output from springcuts\n"];
            }
            
            }
        } @catch (NSException *e) {
            [debugLog appendFormat:@"❌ NSTask crashed: %@\n", e];
        }

        // Fallback to popen if NSTask was unavailable or produced no results
        if (results.count == 0) {
            NSString *binPath = @"/var/jb/usr/bin/springcuts";
            if (![[NSFileManager defaultManager] fileExistsAtPath:binPath]) {
                binPath = @"/usr/bin/springcuts";
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:binPath]) {
                NSString *cmd = [NSString stringWithFormat:@"%@ -l", binPath];
                FILE *fp = popen([cmd UTF8String], "r");
                if (fp) {
                    char buf[1024];
                    NSMutableString *output = [NSMutableString string];
                    while (fgets(buf, sizeof(buf), fp) != NULL) {
                        NSString *lineStr = [NSString stringWithUTF8String:buf];
                        if (lineStr) [output appendString:lineStr];
                    }
                    pclose(fp);
                    NSArray *lines = [output componentsSeparatedByString:@"\n"];
                    for (NSString *line in lines) {
                        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        if (trimmed.length > 0 && ![trimmed isEqualToString:@"Shortcut names:"]) {
                            if ([trimmed hasSuffix:@","]) {
                                trimmed = [trimmed substringToIndex:trimmed.length - 1];
                            }
                            if (![results containsObject:trimmed]) {
                                [results addObject:trimmed];
                            }
                        }
                    }
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.shortcuts = [results sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
            [self.tableView reloadData];
            self.navigationItem.rightBarButtonItem = nil;
            
            if (results.count == 0) {
                NSString *binPath = @"/var/jb/usr/bin/springcuts";
                if (![[NSFileManager defaultManager] fileExistsAtPath:binPath]) {
                    binPath = @"/usr/bin/springcuts";
                }
                
                if (![[NSFileManager defaultManager] fileExistsAtPath:binPath]) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SpringCuts Missing" 
                                                                                   message:@"Please install SpringCuts from Havoc to enable shortcuts support." 
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        [self dismissViewControllerAnimated:YES completion:nil];
                    }]];
                    [self presentViewController:alert animated:YES completion:nil];
                } else {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Debug Log" message:debugLog preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                }
            }
        });
    });
}

- (void)showError:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    if (text.length == 0) {
        self.filteredShortcuts = @[];
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"SELF contains[cd] %@", text];
        self.filteredShortcuts = [self.shortcuts filteredArrayUsingPredicate:pred];
    }
    [self.tableView reloadData];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        return self.filteredShortcuts.count;
    }
    return _shortcuts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ShortcutCell" forIndexPath:indexPath];
    
    NSString *shortcut;
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        shortcut = self.filteredShortcuts[indexPath.row];
    } else {
        shortcut = _shortcuts[indexPath.row];
    }
    
    cell.textLabel.text = shortcut;
    cell.imageView.image = [UIImage systemImageNamed:@"command"];
    cell.imageView.tintColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *selected;
    if (self.searchController.isActive && self.searchController.searchBar.text.length > 0) {
        selected = self.filteredShortcuts[indexPath.row];
    } else {
        selected = _shortcuts[indexPath.row];
    }
    
    if (self.onShortcutSelected) {
        self.onShortcutSelected(selected);
    }
    
    if (self.searchController.isActive) {
        [self.searchController dismissViewControllerAnimated:NO completion:^{
            if (self.presentingViewController) {
                [self dismissViewControllerAnimated:YES completion:nil];
            } else {
                [self.navigationController popViewControllerAnimated:YES];
            }
        }];
    } else {
        if (self.presentingViewController) {
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
}

@end
