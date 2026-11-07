#import "RCNewTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"

@interface RCNewTriggerViewController () <UISearchResultsUpdating>
// Everything the picker was given, and the part currently shown (the search filters it)
@property (nonatomic, strong) NSArray<NSString *> *allSectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *allSections;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation RCNewTriggerViewController

- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"New Trigger";
        NSMutableArray *titles = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
        for (NSDictionary *item in items) {
            NSString *section = item[@"section"] ?: @"Other";
            if (!groups[section]) { groups[section] = [NSMutableArray array]; [titles addObject:section]; }
            [groups[section] addObject:item];
        }
        NSMutableArray *sections = [NSMutableArray array];
        for (NSString *section in titles) [sections addObject:groups[section]];
        _allSectionTitles = titles;
        _allSections = sections;
        _sectionTitles = titles;
        _sections = sections;
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

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Triggers";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.text = @"No Triggers Found";
    self.emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.delegate = self;
}

#pragma mark - Navigation

// The new trigger's action editor is showing (its setup screen finished, or it opened
// directly): this picker's job is done, so drop it from beneath the editor
- (void)navigationController:(UINavigationController *)nav didShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    if (![nav.viewControllers containsObject:self]) {
        if (nav.delegate == self) nav.delegate = nil;
        return;
    }
    if (![vc isKindOfClass:[RCActionsViewController class]]) return;
    // Only when the action list sits directly on this menu: opened from an add-on's own list (which
    // sits between them), Back should return through that list and this menu
    NSUInteger at = [nav.viewControllers indexOfObject:self];
    if (at + 1 >= nav.viewControllers.count || nav.viewControllers[at + 1] != vc) return;
    NSMutableArray *vcs = [nav.viewControllers mutableCopy];
    [vcs removeObject:self];
    nav.delegate = nil;
    [nav setViewControllers:vcs animated:NO];
}

#pragma mark - Search

// Letters and numbers only, lowercased, so "wifi" finds "Wi-Fi Network" and
// "applaunch" finds "App Launch"
- (NSString *)normalizedText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) return @"";
    NSString *folded = [[text stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch
                                                  locale:nil] lowercaseString];
    NSMutableString *letters = [NSMutableString stringWithCapacity:folded.length];
    NSCharacterSet *lettersAndNumbers = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < folded.length; i++) {
        unichar character = [folded characterAtIndex:i];
        if ([lettersAndNumbers characterIsMember:character]) [letters appendFormat:@"%C", character];
    }
    return letters;
}

- (BOOL)item:(NSDictionary *)item matchesSearch:(NSString *)query {
    NSMutableString *text = [NSMutableString string];
    for (NSString *key in @[@"title", @"section", @"detail", @"keywords"]) {
        id value = item[key];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            if (text.length > 0) [text appendString:@" "];
            [text appendString:value];
        }
    }
    return [[self normalizedText:text] containsString:query];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [self normalizedText:searchController.searchBar.text];
    if (query.length == 0) {
        self.sectionTitles = self.allSectionTitles;
        self.sections = self.allSections;
    } else {
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        NSMutableArray<NSArray<NSDictionary *> *> *sections = [NSMutableArray array];
        for (NSUInteger i = 0; i < self.allSections.count; i++) {
            NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
            for (NSDictionary *item in self.allSections[i]) {
                if ([self item:item matchesSearch:query]) [matches addObject:item];
            }
            if (matches.count > 0) {
                [titles addObject:i < self.allSectionTitles.count ? self.allSectionTitles[i] : @""];
                [sections addObject:matches];
            }
        }
        self.sectionTitles = titles;
        self.sections = sections;
    }
    self.tableView.backgroundView = self.sections.count == 0 ? self.emptyLabel : nil;
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sectionTitles[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSDictionary *item = self.sections[indexPath.section][indexPath.row];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.textLabel.text = item[@"title"];
    cell.textLabel.textColor = [UIColor labelColor];
    UIImage *custom = [item[@"image"] isKindOfClass:[UIImage class]] ? item[@"image"] : nil;
    cell.imageView.image = custom ?: [UIImage systemImageNamed:item[@"icon"] ?: @"circle"];
    cell.imageView.tintColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.text = item[@"detail"];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.sections[indexPath.section][indexPath.row];
    void (^handler)(void) = item[@"handler"];
    if (!handler) return;
    // The setup screen is pushed under a clean navigation bar, not an active search
    if (self.searchController.isActive) self.searchController.active = NO;
    handler();
}

@end
