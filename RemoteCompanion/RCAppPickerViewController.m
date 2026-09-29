#import "RCAppPickerViewController.h"

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
@end

@implementation RCAppPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (!self.title) self.title = @"Select App";
    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
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
            self.navigationItem.rightBarButtonItem = nil;
        });
    });
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell" forIndexPath:indexPath];
    
    LSApplicationProxy *app = self.filteredApps[indexPath.row];
    cell.textLabel.text = app.localizedName ?: app.applicationIdentifier;
    cell.detailTextLabel.text = app.applicationIdentifier;
    
    // Attempt to load icon
    // Format 0: Small, 1: Small 2x? 2: Table/List size?
    // Let's try standard UIImage private method
    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:app.applicationIdentifier format:0 scale:[UIScreen mainScreen].scale];
    cell.imageView.image = icon;
    cell.accessoryType = [self.selectedBundleIDs containsObject:app.applicationIdentifier] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    LSApplicationProxy *app = self.filteredApps[indexPath.row];
    NSString *bundleId = app.applicationIdentifier;
    NSString *name = app.localizedName ?: bundleId;
    
    if (self.onAppSelected) {
        self.onAppSelected(name, bundleId);
    }
    
    if (self.suppressAutoPop) {
        [self.tableView reloadData];
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
