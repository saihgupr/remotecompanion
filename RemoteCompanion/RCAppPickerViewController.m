#import "RCAppPickerViewController.h"
#import "RCConfigManager.h"

// Private API Declarations
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *shortVersionString;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSURL *containerURL;
- (UIImage *)iconDataForVariant:(int)variant;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface RCAppPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<LSApplicationProxy *> *allApps;
@property (nonatomic, strong) NSArray<LSApplicationProxy *> *filteredApps;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSMutableArray<NSString *> *chosen; // multi-select: bundle ids, in the order ticked
@property (nonatomic, strong) UIBarButtonItem *doneItem;
@end

@implementation RCAppPickerViewController

// Rounded inset list, like the other pickers
- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = self.allowsMultipleApps ? @"Select Apps" : @"Select App";
    self.chosen = [NSMutableArray arrayWithArray:self.selectedBundleIds ?: @[]];
    if (self.allowsMultipleApps) {
        self.doneItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(donePressed)];
        self.doneItem.enabled = self.chosen.count > 0;
    }
    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"AppCell"];
    self.tableView.rowHeight = 60; // Consistent sizing
    
    // Setup Search
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Apps";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    
    [self loadApps];
}

- (void)loadApps {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        NSArray *apps = [[workspaceClass defaultWorkspace] allInstalledApplications];
        
        // Filter out some internals?
        // Usually we want user visible apps.
        // There is no easy property for "user visible" public on Proxy, but usually we filter by bundle ID prefix or just show all.
        // Let's sort by name.
        
        NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"localizedName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
        self.allApps = [apps sortedArrayUsingDescriptors:@[sort]];
        self.filteredApps = self.allApps;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
            self.navigationItem.rightBarButtonItem = self.doneItem; // nil unless several apps can be ticked
        });
    });
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell" forIndexPath:indexPath];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    
    LSApplicationProxy *app = self.filteredApps[indexPath.row];
    cell.textLabel.text = app.localizedName ?: app.applicationIdentifier;
    cell.detailTextLabel.text = app.applicationIdentifier;
    
    // Attempt to load icon
    // Format 0: Small, 1: Small 2x? 2: Table/List size?
    // Let's try standard UIImage private method
    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:app.applicationIdentifier format:0 scale:[UIScreen mainScreen].scale];
    cell.imageView.image = icon;
    cell.accessoryType = (self.allowsMultipleApps && [self.chosen containsObject:app.applicationIdentifier]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    LSApplicationProxy *app = self.filteredApps[indexPath.row];
    NSString *bundleId = app.applicationIdentifier;
    NSString *name = app.localizedName ?: bundleId;

    if (self.allowsMultipleApps) {
        if ([self.chosen containsObject:bundleId]) [self.chosen removeObject:bundleId];
        else [self.chosen addObject:bundleId];
        self.doneItem.enabled = self.chosen.count > 0;
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
    
    if (self.onAppSelected) {
        self.onAppSelected(name, bundleId);
    }
    
    if (self.suppressAutoPop) {
        return; // Caller handles navigation
    }
    
    if (self.searchController.isActive) {
        [self.searchController dismissViewControllerAnimated:NO completion:^{
            if (self.navigationController && self.navigationController.viewControllers.count > 1) {
                [self.navigationController popViewControllerAnimated:YES];
            } else if (self.presentingViewController) {
                [self dismissViewControllerAnimated:YES completion:nil];
            }
        }];
    } else {
        if (self.navigationController && self.navigationController.viewControllers.count > 1) {
            [self.navigationController popViewControllerAnimated:YES];
        } else if (self.presentingViewController) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }
}


// Multi-select: hands the ticked apps over
- (void)donePressed {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *bundleId in self.chosen) {
        NSString *name = bundleId; // an app that is no longer installed keeps its id
        for (LSApplicationProxy *app in self.allApps) {
            if ([app.applicationIdentifier isEqualToString:bundleId]) { name = app.localizedName ?: bundleId; break; }
        }
        [names addObject:name];
    }
    if (self.onAppsSelected) self.onAppsSelected(names, [self.chosen copy]);
    if (self.suppressAutoPop) return; // Caller handles navigation
    if (self.searchController.isActive) [self.searchController dismissViewControllerAnimated:NO completion:nil];
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    if (text.length == 0) {
        self.filteredApps = self.allApps;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"localizedName CONTAINS[cd] %@ OR applicationIdentifier CONTAINS[cd] %@", text, text];
        self.filteredApps = [self.allApps filteredArrayUsingPredicate:pred];
    }
    [self.tableView reloadData];
}

@end
