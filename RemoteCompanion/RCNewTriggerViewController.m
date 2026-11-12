#import "RCNewTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCActionTile.h"
#import "RCCategoryBar.h"
#import "RCTriggerIcons.h"

@interface RCNewTriggerViewController () <UISearchResultsUpdating, UITableViewDataSource, UITableViewDelegate,
                                          UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
// Everything the picker was given, and the part currently shown (the search filters it)
@property (nonatomic, strong) NSArray<NSString *> *allSectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *allSections;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
// List: the table. Compact: the grid. Only the one for the layout setting is shown.
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UICollectionView *collectionView;
// Compact: the Triggers list's category bar over the grid, and the section it picked (nil: All)
@property (nonatomic, strong) RCCategoryBar *categoryBar;
@property (nonatomic, copy) NSString *selectedCategoryTitle;
@end

@implementation RCNewTriggerViewController

- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items {
    self = [super initWithNibName:nil bundle:nil];
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
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = bg;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 52;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:RCActionGridLayout()];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.backgroundColor = bg;
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.collectionView registerClass:[RCActionTileCell class] forCellWithReuseIdentifier:@"Tile"];
    [self.collectionView registerClass:[RCActionGridHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"Header"];
    [self.view addSubview:self.collectionView];

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

    // Compact: chips for the sections, as on Triggers. A chip narrows the grid (and a search) to its section.
    self.categoryBar = [[RCCategoryBar alloc] initWithWidth:self.view.bounds.size.width];
    NSMutableArray *chipIcons = [NSMutableArray array];
    for (NSString *title in self.allSectionTitles) [chipIcons addObject:RCTriggerCategoryIcon(title) ?: [NSNull null]];
    [self.categoryBar setChipTitles:self.allSectionTitles icons:chipIcons];
    self.categoryBar.selectedIndex = -1;
    __weak typeof(self) weakSelf = self;
    self.categoryBar.onSelect = ^(NSInteger index) {
        weakSelf.selectedCategoryTitle = (index >= 0 && index < (NSInteger)weakSelf.allSectionTitles.count) ? weakSelf.allSectionTitles[index] : nil;
        [weakSelf reloadData];
    };

    // List or Compact (Settings), followed while open
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutChanged:) name:RCLayoutChangedNotification object:nil];
    [self applyLayout];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Layout (List or Compact)

- (BOOL)compact {
    return RCLayoutIsCompact(RCLayoutNewTrigger);
}

- (UIScrollView *)activeScrollView {
    return [self compact] ? self.collectionView : self.tableView;
}

- (void)layoutChanged:(NSNotification *)note {
    if ([note.object isEqual:RCLayoutNewTrigger]) [self applyLayout];
}

// Shows the table or the grid; the other is hidden behind it. The category bar comes with the grid.
- (void)applyLayout {
    UIScrollView *active = [self activeScrollView];
    UIScrollView *other = active == self.tableView ? (UIScrollView *)self.collectionView : self.tableView;
    if ([self compact]) {
        if (self.categoryBar.superview != self.collectionView) [self.categoryBar attachToScrollView:self.collectionView];
    } else if (self.categoryBar.superview) {
        [self.categoryBar detachFromScrollView:self.collectionView];
        self.selectedCategoryTitle = nil;
        self.categoryBar.selectedIndex = -1;
    }
    active.hidden = NO;
    other.hidden = YES;
    // The navigation bar follows the first scroll view
    [self.view sendSubviewToBack:other];
    [self.view sendSubviewToBack:active];
    if (@available(iOS 15.0, *)) [self setContentScrollView:active forEdge:NSDirectionalRectEdgeAll];
    [self reloadData];
}

- (void)reloadData {
    UIScrollView *active = [self activeScrollView];
    UIScrollView *other = active == self.tableView ? (UIScrollView *)self.collectionView : self.tableView;
    if ([other isKindOfClass:[UITableView class]]) ((UITableView *)other).backgroundView = nil;
    else ((UICollectionView *)other).backgroundView = nil;
    UIView *empty = (active == self.tableView ? self.sections.count : [self gridSections].count) == 0 ? self.emptyLabel : nil;
    if (active == self.tableView) self.tableView.backgroundView = empty;
    else self.collectionView.backgroundView = empty;
    [self.tableView reloadData];
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
    if ([self compact]) [self.categoryBar layoutInScrollView:self.collectionView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if ([self compact]) [self.categoryBar layoutInScrollView:self.collectionView];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.collectionView) [self.categoryBar scrollViewDidScroll:scrollView];
}

// The grid's sections: all of them (as the search left them), or the one its chip picked
- (NSArray<NSArray<NSDictionary *> *> *)gridSections {
    if (!self.selectedCategoryTitle) return self.sections;
    NSUInteger at = [self.sectionTitles indexOfObject:self.selectedCategoryTitle];
    return at == NSNotFound ? @[] : @[self.sections[at]];
}

- (NSArray<NSString *> *)gridSectionTitles {
    if (!self.selectedCategoryTitle) return self.sectionTitles;
    return [self.sectionTitles containsObject:self.selectedCategoryTitle] ? @[self.selectedCategoryTitle] : @[];
}

// The grid's columns follow a rotation
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.collectionView.collectionViewLayout invalidateLayout];
    } completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        if ([self compact]) [self.categoryBar layoutInScrollView:self.collectionView];
    }];
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
    [self reloadData];
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
    [self selectItem:self.sections[indexPath.section][indexPath.row]];
}

#pragma mark - Grid (Compact)

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return [self gridSections].count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self gridSections][section].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RCActionTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Tile" forIndexPath:indexPath];
    NSDictionary *item = [self gridSections][indexPath.section][indexPath.item];
    // The icon its triggers have in the Triggers list, when there is one
    UIImage *custom = [item[@"compactImage"] isKindOfClass:[UIImage class]] ? item[@"compactImage"]
                    : [item[@"image"] isKindOfClass:[UIImage class]] ? item[@"image"] : nil;
    [cell setName:item[@"title"] icon:item[@"icon"] ?: @"circle" image:custom];
    // The list's detail, on a tile: a built-in trigger already added is checked; an add-on
    // shows how many of its triggers are added
    NSString *detail = [item[@"detail"] isKindOfClass:[NSString class]] ? item[@"detail"] : nil;
    NSInteger count = [item[@"addedCount"] integerValue];
    cell.count = count;
    cell.checked = detail.length > 0 && count == 0;
    cell.plainChecked = YES;
    cell.accessibilityValue = detail;
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    RCActionGridHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"Header" forIndexPath:indexPath];
    NSString *title = [self gridSectionTitles][indexPath.section];
    [header setTitle:title icon:RCTriggerCategoryIcon(title)];
    return header;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return RCActionTileSize(RCGridWidth(collectionView));
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section {
    return CGSizeMake(collectionView.bounds.size.width, section == 0 ? 30 : 38);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    [self selectItem:[self gridSections][indexPath.section][indexPath.item]];
}

#pragma mark - Choosing

- (void)selectItem:(NSDictionary *)item {
    void (^handler)(void) = item[@"handler"];
    if (!handler) return;
    // The setup screen is pushed under a clean navigation bar, not an active search. Pushing while the
    // search is still closing is dropped, so the choice runs once it has closed.
    if (!self.searchController.isActive) { handler(); return; }
    self.searchController.active = NO;
    id<UIViewControllerTransitionCoordinator> closing = self.searchController.transitionCoordinator ?: self.transitionCoordinator;
    if (!closing || ![closing animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) { handler(); }]) {
        dispatch_async(dispatch_get_main_queue(), handler);
    }
}

@end
