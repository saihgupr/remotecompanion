#import "RCSymbolPickerViewController.h"
#import "RCConfigManager.h"
#import "RCCategoryBar.h"

// Categories of symbols: title, names. Names a system doesn't have are left out when shown.
static NSArray<NSArray *> *RCSymbolCategories(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *raw = @[
            @[@"Common", @[@"bell.fill", @"bell.slash.fill", @"bell.badge.fill", @"checkmark.circle.fill", @"xmark.circle.fill", @"exclamationmark.triangle.fill", @"exclamationmark.circle.fill", @"info.circle.fill", @"questionmark.circle.fill", @"star.fill", @"heart.fill", @"flag.fill", @"bolt.fill", @"sparkles", @"hand.thumbsup.fill", @"hand.thumbsdown.fill", @"hand.raised.fill", @"lightbulb.fill", @"flame.fill", @"gift.fill", @"tag.fill", @"bookmark.fill", @"pin.fill", @"eye.fill", @"eye.slash.fill", @"lock.fill", @"lock.open.fill", @"key.fill", @"shield.fill", @"person.fill", @"person.2.fill", @"house.fill", @"gearshape.fill", @"trash.fill", @"pencil", @"paperplane.fill", @"envelope.fill", @"message.fill", @"text.bubble.fill", @"phone.fill", @"magnifyingglass", @"link", @"doc.fill", @"folder.fill"]],
            @[@"Media", @[@"play.fill", @"pause.fill", @"stop.fill", @"playpause.fill", @"forward.fill", @"backward.fill", @"forward.end.fill", @"backward.end.fill", @"shuffle", @"repeat", @"repeat.1", @"music.note", @"music.note.list", @"music.mic", @"headphones", @"speaker.fill", @"speaker.slash.fill", @"speaker.wave.1.fill", @"speaker.wave.2.fill", @"speaker.wave.3.fill", @"mic.fill", @"mic.slash.fill", @"camera.fill", @"video.fill", @"video.slash.fill", @"photo.fill", @"film.fill", @"tv.fill", @"radio", @"airplayaudio", @"airplayvideo", @"hifispeaker.fill", @"waveform", @"record.circle.fill"]],
            @[@"Devices", @[@"iphone", @"ipad", @"applewatch", @"airpods", @"airpodspro", @"laptopcomputer", @"desktopcomputer", @"display", @"keyboard", @"printer.fill", @"gamecontroller.fill", @"flashlight.on.fill", @"flashlight.off.fill", @"battery.100", @"battery.25", @"battery.0", @"battery.100.bolt", @"powerplug.fill", @"bolt.circle.fill", @"cpu", @"memorychip", @"externaldrive.fill", @"simcard.fill", @"faceid", @"touchid", @"lock.rotation", @"rotate.right.fill", @"iphone.radiowaves.left.and.right", @"car.fill"]],
            @[@"Connectivity", @[@"wifi", @"wifi.slash", @"wifi.exclamationmark", @"antenna.radiowaves.left.and.right", @"airplane", @"dot.radiowaves.left.and.right", @"personalhotspot", @"network", @"globe", @"location.fill", @"location.slash.fill", @"cloud.fill", @"icloud.fill", @"icloud.slash.fill", @"arrow.down.circle.fill", @"arrow.up.circle.fill", @"arrow.triangle.2.circlepath"]],
            @[@"Home", @[@"house.fill", @"lightbulb.fill", @"lightbulb.slash.fill", @"lamp.desk.fill", @"fan.fill", @"thermometer", @"door.left.hand.open", @"bed.double.fill", @"sofa.fill", @"washer.fill", @"lock.shield.fill", @"sensor.fill", @"web.camera.fill", @"key.fill"]],
            @[@"Weather & Time", @[@"sun.max.fill", @"moon.fill", @"moon.stars.fill", @"cloud.sun.fill", @"cloud.rain.fill", @"cloud.bolt.fill", @"cloud.snow.fill", @"snowflake", @"wind", @"tornado", @"umbrella.fill", @"thermometer.sun.fill", @"sunrise.fill", @"sunset.fill", @"moon.zzz.fill", @"zzz", @"alarm.fill", @"clock.fill", @"timer", @"hourglass", @"stopwatch.fill", @"calendar"]],
            @[@"Life", @[@"heart.text.square.fill", @"waveform.path.ecg", @"figure.walk", @"bicycle", @"drop.fill", @"pills.fill", @"cross.fill", @"bandage.fill", @"cup.and.saucer.fill", @"fork.knife", @"cart.fill", @"bag.fill", @"creditcard.fill", @"dollarsign.circle.fill", @"briefcase.fill", @"book.fill", @"graduationcap.fill", @"pawprint.fill", @"leaf.fill", @"gamecontroller.fill"]],
            @[@"Symbols", @[@"plus.circle.fill", @"minus.circle.fill", @"multiply.circle.fill", @"number", @"textformat", @"checkmark", @"xmark", @"exclamationmark", @"questionmark", @"arrow.right", @"arrow.left", @"arrow.up", @"arrow.down", @"arrow.clockwise", @"arrow.counterclockwise", @"arrow.uturn.backward", @"chevron.right", @"circle.fill", @"square.fill", @"triangle.fill", @"diamond.fill", @"hexagon.fill", @"seal.fill", @"power", @"togglepower", @"slider.horizontal.3", @"switch.2", @"1.circle.fill", @"2.circle.fill", @"3.circle.fill", @"a.circle.fill"]],
        ];
        NSMutableArray *available = [NSMutableArray array];
        for (NSArray *category in raw) {
            NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
            for (NSString *name in category[1]) if ([UIImage systemImageNamed:name]) [names addObject:name];
            if (names.count) [available addObject:@[category[0], names.array]];
        }
        list = available;
    });
    return list;
}

#pragma mark - Tile

@interface RCSymbolTileCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, assign) BOOL chosen;
@end

@implementation RCSymbolTileCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        RCConfigManager *cm = [RCConfigManager sharedManager];
        self.contentView.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
        self.contentView.layer.cornerRadius = 12;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.layer.borderColor = [UIColor systemBlueColor].CGColor;

        self.iconView = [[UIImageView alloc] init];
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        self.iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.iconView];

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont systemFontOfSize:9.5];
        self.nameLabel.textColor = [UIColor secondaryLabelColor];
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.nameLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-7],
            [self.iconView.widthAnchor constraintEqualToConstant:30],
            [self.iconView.heightAnchor constraintEqualToConstant:30],
            [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4],
            [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],
            [self.nameLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
        ]];
    }
    return self;
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.contentView.backgroundColor = chosen ? [[UIColor systemBlueColor] colorWithAlphaComponent:0.22] : [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    self.contentView.layer.borderWidth = chosen ? 1.5 : 0;
    self.iconView.tintColor = chosen ? [UIColor systemBlueColor] : [UIColor labelColor];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.contentView.transform = highlighted ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity;
    }];
}

@end

#pragma mark - Picker

@interface RCSymbolPickerViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating>
@property (nonatomic, copy) NSString *selected;
@property (nonatomic, assign) BOOL allowsNone;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) RCCategoryBar *categoryBar;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) NSInteger category; // -1 = All
@property (nonatomic, strong) NSArray<NSString *> *shown; // "" = None
@end

@implementation RCSymbolPickerViewController

- (instancetype)initWithSelectedSymbol:(NSString *)selected allowsNone:(BOOL)allowsNone {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _selected = [selected copy] ?: @"";
        _allowsNone = allowsNone;
        _category = -1;
        self.title = @"Icon";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search or Type a Symbol Name";
    self.searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    NSMutableArray *titles = [NSMutableArray array];
    for (NSArray *c in RCSymbolCategories()) [titles addObject:c[0]];
    self.categoryBar = [[RCCategoryBar alloc] initWithWidth:self.view.bounds.size.width];
    [self.categoryBar setChipTitles:titles];
    self.categoryBar.selectedIndex = -1;
    self.categoryBar.backgroundColor = bg;
    __weak typeof(self) weakSelf = self;
    self.categoryBar.onSelect = ^(NSInteger index) {
        weakSelf.category = index;
        [weakSelf reload];
        [weakSelf.collectionView setContentOffset:CGPointMake(0, -weakSelf.collectionView.adjustedContentInset.top) animated:NO];
    };
    [self.view addSubview:self.categoryBar];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(8, 16, 24, 16);
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = bg;
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[RCSymbolTileCell class] forCellWithReuseIdentifier:@"Tile"];
    [self.view insertSubview:self.collectionView belowSubview:self.categoryBar];

    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat top = self.view.safeAreaInsets.top, height = [RCCategoryBar barHeight];
    self.categoryBar.frame = CGRectMake(0, top, self.view.bounds.size.width, height);
    CGRect frame = CGRectMake(0, top + height, self.view.bounds.size.width, self.view.bounds.size.height - top - height);
    if (!CGRectEqualToRect(self.collectionView.frame, frame)) {
        self.collectionView.frame = frame;
        self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, self.view.safeAreaInsets.bottom, 0);
        [self.collectionView.collectionViewLayout invalidateLayout];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Brings the current icon into view
    NSUInteger index = [self.shown indexOfObject:self.selected];
    if (self.selected.length && index != NSNotFound) {
        [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0] atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reload];
}

// The names to show: the chosen category (or all), narrowed by the search; a typed symbol name
// that isn't listed comes first
- (void)reload {
    NSString *query = [[self.searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString] ?: @"";
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
    NSArray *categories = RCSymbolCategories();
    for (NSInteger i = 0; i < (NSInteger)categories.count; i++) {
        if (self.category >= 0 && i != self.category) continue;
        for (NSString *name in categories[i][1]) {
            if (!query.length) { [names addObject:name]; continue; }
            NSString *words = [name stringByReplacingOccurrencesOfString:@"." withString:@" "];
            for (NSString *term in [query componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ."]]) {
                if (term.length && [words containsString:term]) { [names addObject:name]; break; }
            }
        }
    }
    NSMutableArray *shown = [NSMutableArray array];
    NSString *typed = [query stringByReplacingOccurrencesOfString:@" " withString:@"."];
    if (typed.length && ![names containsObject:typed] && [UIImage systemImageNamed:typed]) [shown addObject:typed];
    if (!query.length && self.category < 0 && self.allowsNone) [shown addObject:@""];
    // The current icon stays findable in All even when it isn't in the list
    if (!query.length && self.category < 0 && self.selected.length && ![names containsObject:self.selected] && [UIImage systemImageNamed:self.selected]) [shown addObject:self.selected];
    [shown addObjectsFromArray:names.array];
    self.shown = shown;
    [self.collectionView reloadData];
}

#pragma mark - Grid

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.shown.count;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = collectionView.bounds.size.width - 32;
    NSInteger columns = MAX(4, (NSInteger)floor((width + 8) / (76 + 8)));
    CGFloat side = floor((width - 8 * (columns - 1)) / columns);
    return CGSizeMake(side, side);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RCSymbolTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Tile" forIndexPath:indexPath];
    NSString *name = self.shown[indexPath.item];
    if (name.length) {
        cell.iconView.image = [UIImage systemImageNamed:name];
        cell.nameLabel.text = name;
    } else {
        cell.iconView.image = [UIImage systemImageNamed:@"nosign"];
        cell.nameLabel.text = @"None";
    }
    cell.chosen = [name isEqualToString:self.selected];
    cell.accessibilityLabel = name.length ? name : @"None";
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *name = self.shown[indexPath.item];
    self.selected = name;
    for (RCSymbolTileCell *cell in collectionView.visibleCells) {
        NSIndexPath *path = [collectionView indexPathForCell:cell];
        if (path) cell.chosen = [self.shown[path.item] isEqualToString:name];
    }
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    void (^onPick)(NSString *) = self.onPick;
    if (onPick) onPick(name);
    // A moment to see the choice, then back
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf.searchController.isActive) weakSelf.searchController.active = NO;
        [weakSelf.navigationController popViewControllerAnimated:YES];
    });
}

@end
