#import "RCNewTriggerViewController.h"
#import "RCConfigManager.h"
#import "RCActionsViewController.h"
#import "RCActionTile.h"
#import "RCCategoryBar.h"
#import "RCTriggerIcons.h"

@interface RCNewTriggerViewController () <UISearchResultsUpdating, UISearchControllerDelegate,
                                          UITableViewDataSource, UITableViewDelegate,
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
// The Triggers list's category bar over the list or grid, and the section it picked (nil: All)
@property (nonatomic, strong) RCCategoryBar *categoryBar;
@property (nonatomic, copy) NSString *selectedCategoryTitle;
@property (nonatomic, copy) NSString *lastSearchQuery;
@property (nonatomic, assign) BOOL didSetInitialTop;
// A chosen item waits here until the search that found it has finished closing
@property (nonatomic, copy) void (^pendingHandler)(void);
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
    if (@available(iOS 15.0, *)) {
        // Spacing above headers is built into the header views instead (see
        // heightForHeaderInSection:), so the first one can sit close to the category bar
        self.tableView.sectionHeaderTopPadding = 0;
    }
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
    self.searchController.delegate = self;
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

    // Chips for the sections, as on Triggers. A chip narrows the list or grid (and a search) to its section.
    self.categoryBar = [[RCCategoryBar alloc] initWithWidth:self.view.bounds.size.width];
    NSMutableArray *chipIcons = [NSMutableArray array];
    for (NSString *title in self.allSectionTitles) [chipIcons addObject:RCTriggerCategoryIcon(title) ?: [NSNull null]];
    [self.categoryBar setChipTitles:self.allSectionTitles icons:chipIcons];
    self.categoryBar.selectedIndex = -1;
    __weak typeof(self) weakSelf = self;
    self.categoryBar.onSelect = ^(NSInteger index) {
        weakSelf.selectedCategoryTitle = (index >= 0 && index < (NSInteger)weakSelf.allSectionTitles.count) ? weakSelf.allSectionTitles[index] : nil;
        [weakSelf reloadData];
        [weakSelf scrollToTop];
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

// Shows the table or the grid; the other is hidden behind it. The category bar follows the active view.
- (void)applyLayout {
    UIScrollView *active = [self activeScrollView];
    UIScrollView *other = active == self.tableView ? (UIScrollView *)self.collectionView : self.tableView;
    [self.categoryBar detachFromScrollView:other];
    if (self.categoryBar.superview != active) {
        if (active == self.tableView) [self.categoryBar attachToTableView:self.tableView];
        else [self.categoryBar attachToScrollView:self.collectionView];
    }
    active.hidden = NO;
    other.hidden = YES;
    // The navigation bar follows the first scroll view
    [self.view sendSubviewToBack:other];
    [self.view sendSubviewToBack:active];
    if (@available(iOS 15.0, *)) [self setContentScrollView:active forEdge:NSDirectionalRectEdgeAll];
    [self reloadData];
    if (self.didSetInitialTop) [self scrollToTop];
}

- (void)scrollToTop {
    UIScrollView *active = [self activeScrollView];
    [active setContentOffset:CGPointMake(0, -active.adjustedContentInset.top) animated:NO];
    [self.categoryBar layoutInScrollView:active];
}

- (void)reloadData {
    UIScrollView *active = [self activeScrollView];
    UIScrollView *other = active == self.tableView ? (UIScrollView *)self.collectionView : self.tableView;
    if ([other isKindOfClass:[UITableView class]]) ((UITableView *)other).backgroundView = nil;
    else ((UICollectionView *)other).backgroundView = nil;
    UIView *empty = [self displayedSections].count == 0 ? self.emptyLabel : nil;
    if (active == self.tableView) self.tableView.backgroundView = empty;
    else self.collectionView.backgroundView = empty;
    [self.tableView reloadData];
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
    [self.categoryBar layoutInScrollView:active];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIScrollView *active = [self activeScrollView];
    if (!self.didSetInitialTop && active.safeAreaInsets.top > 0) {
        self.didSetInitialTop = YES;
        active.contentOffset = CGPointMake(0, -active.adjustedContentInset.top);
    }
    [self.categoryBar layoutInScrollView:active];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == [self activeScrollView]) [self.categoryBar scrollViewDidScroll:scrollView];
}

// The sections shown: all of them (as the search left them), or the one the category chip picked
- (NSArray<NSArray<NSDictionary *> *> *)displayedSections {
    if (!self.selectedCategoryTitle) return self.sections;
    NSUInteger at = [self.sectionTitles indexOfObject:self.selectedCategoryTitle];
    return at == NSNotFound ? @[] : @[self.sections[at]];
}

- (NSArray<NSString *> *)displayedSectionTitles {
    if (!self.selectedCategoryTitle) return self.sectionTitles;
    return [self.sectionTitles containsObject:self.selectedCategoryTitle] ? @[self.selectedCategoryTitle] : @[];
}

// The grid's columns follow a rotation
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.collectionView.collectionViewLayout invalidateLayout];
    } completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.categoryBar layoutInScrollView:[self activeScrollView]];
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
    BOOL queryChanged = ![query isEqualToString:self.lastSearchQuery ?: @""];
    self.lastSearchQuery = query;
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
    if (queryChanged) [self scrollToTop];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self displayedSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self displayedSections][section].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self displayedSectionTitles][section];
    CGFloat height = [self tableView:tableView heightForHeaderInSection:section];
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, height)];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [title uppercaseString];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [headerView addSubview:label];

    UIImage *icon = RCTriggerCategoryIcon(title);
    if (icon) {
        UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
        iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.tintColor = label.textColor;
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [headerView addSubview:iconView];
        [NSLayoutConstraint activateConstraints:@[
            [iconView.leadingAnchor constraintEqualToAnchor:headerView.safeAreaLayoutGuide.leadingAnchor constant:20],
            [iconView.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
            [iconView.widthAnchor constraintEqualToConstant:18],
            [iconView.heightAnchor constraintEqualToConstant:18],
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:headerView.safeAreaLayoutGuide.leadingAnchor constant:icon ? 44 : 20],
        [label.trailingAnchor constraintEqualToAnchor:headerView.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [label.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:-5],
        [label.heightAnchor constraintEqualToConstant:20],
    ]];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    // The first section sits just below the category bar. The others keep their old
    // spacing, including the 15pt sectionHeaderTopPadding they had on iOS 15+.
    if (section == 0) return 29.0f;
    CGFloat topPadding = 0;
    if (@available(iOS 15.0, *)) topPadding = 15;
    return 40.0f + topPadding;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSDictionary *item = [self displayedSections][indexPath.section][indexPath.row];

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
    [self selectItem:[self displayedSections][indexPath.section][indexPath.row]];
}

#pragma mark - Grid (Compact)

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return [self displayedSections].count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self displayedSections][section].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RCActionTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Tile" forIndexPath:indexPath];
    NSDictionary *item = [self displayedSections][indexPath.section][indexPath.item];
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
    NSString *title = [self displayedSectionTitles][indexPath.section];
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
    [self selectItem:[self displayedSections][indexPath.section][indexPath.item]];
}

#pragma mark - Choosing

- (void)selectItem:(NSDictionary *)item {
    void (^handler)(void) = item[@"handler"];
    if (!handler) return;
    // The setup screen is pushed under a clean navigation bar, not an active search. Pushing while the
    // search is still closing is dropped (on iPad), so the choice runs once it has closed.
    if (!self.searchController.isActive) { handler(); return; }
    // Held so the choice runs once, whichever reports the search closed first
    self.pendingHandler = handler;
    self.searchController.active = NO;
    __weak typeof(self) weakSelf = self;
    // In case the dismissal does not report back (it does on most releases), do not
    // leave the tap doing nothing.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf runPendingHandler];
    });
    // And run it as soon as the closing search's transition ends, if it reports one
    id<UIViewControllerTransitionCoordinator> closing = self.searchController.transitionCoordinator ?: self.transitionCoordinator;
    if (closing) {
        [closing animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
            [weakSelf runPendingHandler];
        }];
    }
}

- (void)searchControllerDidDismissSearchController:(UISearchController *)searchController {
    [self runPendingHandler];
}

- (void)runPendingHandler {
    void (^pending)(void) = self.pendingHandler;
    self.pendingHandler = nil;
    if (pending) pending();
}

@end
