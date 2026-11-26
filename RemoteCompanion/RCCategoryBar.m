#import "RCCategoryBar.h"
#import "RCActionTile.h"

@interface RCCategoryBar ()
@property (nonatomic, strong) NSMutableArray<UIButton *> *chips;
// Floating: how much of the bar is showing (0 = hidden, barHeight = fully shown), and the
// last scroll position, measured from the top of the content (0 = scrolled to the top)
@property (nonatomic, assign) CGFloat revealed;
@property (nonatomic, assign) CGFloat lastOffset;
// The bar's space is added once the scroll view is on screen: an inset set in
// viewDidLoad is ignored by the navigation bar, which leaves the large title
// collapsed until the first scroll.
@property (nonatomic, weak) UIScrollView *insetToApply;
@property (nonatomic, assign) BOOL appliedInset;
// The chips' titles and icons, to lay them out again when the number of lines changes
@property (nonatomic, copy) NSArray *lastTitles;
@property (nonatomic, copy) NSArray *lastIcons;
@end

@implementation RCCategoryBar

+ (CGFloat)barHeight {
    return 48;
}

// 1, 2 or 3 lines of chips (Layout > Category Bar Lines): 48 points for one, 38 more for each other
- (CGFloat)height {
    return 48 + (MAX(1, MIN(3, self.rows)) - 1) * 38;
}

- (void)setRows:(NSInteger)rows {
    rows = MAX(1, MIN(3, rows));
    if (rows == _rows) return;
    UIScrollView *host = [self.superview isKindOfClass:[UIScrollView class]] ? (UIScrollView *)self.superview : nil;
    if (host) [self detachFromScrollView:host];   // gives back the old height
    _rows = rows;
    CGRect frame = self.frame;
    frame.size.height = [self height];
    self.frame = frame;
    [self setChipTitles:self.lastTitles ?: @[] icons:self.lastIcons];
    if (host) [self attachToScrollView:host];     // makes room for the new one
}

- (void)layoutSettingChanged:(NSNotification *)note {
    if (![note.userInfo[RCLayoutOptionKey] isEqual:RCLayoutOptionBarLines]) return;
    if (self.picker) return;
    if ([note.object isEqual:self.layoutScreen ?: RCLayoutTriggers]) self.rows = RCLayoutBarLines(self.layoutScreen);
}

- (instancetype)initWithWidth:(CGFloat)width {
    return [self initWithWidth:width screen:nil];
}

- (instancetype)initWithWidth:(CGFloat)width screen:(NSString *)screen {
    self = [super initWithFrame:CGRectMake(0, 0, width, [RCCategoryBar barHeight])];
    _layoutScreen = [screen copy];
    _rows = RCLayoutBarLines(screen);
    if (self) {
        _selectedIndex = -1;
        _chips = [NSMutableArray array];
        self.showsHorizontalScrollIndicator = NO;
        self.alwaysBounceHorizontal = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        CGRect frame = self.frame;
        frame.size.height = [self height];
        self.frame = frame;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutSettingChanged:) name:RCLayoutChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setChipTitles:(NSArray<NSString *> *)chipTitles {
    [self setChipTitles:chipTitles icons:nil];
}

- (void)setChipTitles:(NSArray<NSString *> *)chipTitles icons:(NSArray *)icons {
    self.lastTitles = chipTitles;
    self.lastIcons = icons;
    for (UIButton *chip in self.chips) [chip removeFromSuperview];
    [self.chips removeAllObjects];

    if (self.picker && _rows != 1) {
        _rows = 1;
        CGRect frame = self.frame;
        frame.size.height = [self height];
        self.frame = frame;
    }
    NSMutableArray *titles = self.picker ? [NSMutableArray array] : [NSMutableArray arrayWithObject:@"All"];
    [titles addObjectsFromArray:chipTitles];
    NSInteger first = self.picker ? 0 : -1; // the first chip's index: All is -1
    CGFloat height = [self height];
    CGFloat x = 16;
    CGFloat lineX[3] = { 16, 16, 16 };
    NSInteger lineCount = MAX(1, MIN(3, self.rows));
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
        [chip setTitle:titles[i] forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        // The icon before the name, when there are icons (All: a grid)
        id icon = nil;
        if (icons && self.picker) icon = i < icons.count ? icons[i] : nil;
        else if (icons) icon = i == 0 ? [UIImage systemImageNamed:@"square.grid.2x2.fill"] : (i - 1 < icons.count ? icons[i - 1] : nil);
        BOOL hasIcon = [icon isKindOfClass:[UIImage class]];
        if (hasIcon) {
            [chip setImage:icon forState:UIControlStateNormal];
            [chip setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold] forImageInState:UIControlStateNormal];
            chip.adjustsImageWhenHighlighted = NO;
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // UIButtonConfiguration is iOS 15+: the gap between icon and name from the insets
        chip.contentEdgeInsets = UIEdgeInsetsMake(7, hasIcon ? 12 : 14, 7, hasIcon ? 20 : 14);
        if (hasIcon) chip.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
#pragma clang diagnostic pop
        [chip sizeToFit];
        if (self.rows >= 2) {
            // Several lines: into the shortest one, so they all end about the same place
            NSInteger line = 0;
            for (NSInteger l = 1; l < lineCount; l++) if (lineX[l] < lineX[line]) line = l;
            CGFloat chipHeight = chip.bounds.size.height;
            chip.frame = CGRectMake(lineX[line], 6 + line * (chipHeight + 6), chip.bounds.size.width, chipHeight);
            lineX[line] += chip.bounds.size.width + 8;
            CGFloat longest = 0;
            for (NSInteger l = 0; l < lineCount; l++) longest = MAX(longest, lineX[l]);
            x = longest - chip.bounds.size.width - 8; // the loop adds it back below
        } else {
            chip.frame = CGRectMake(x, (height - chip.bounds.size.height) / 2.0, chip.bounds.size.width, chip.bounds.size.height);
        }
        chip.layer.cornerRadius = chip.bounds.size.height / 2.0;
        chip.tag = (NSInteger)i + first; // -1 = All
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:chip];
        [self.chips addObject:chip];
        x += chip.bounds.size.width + 8;
    }
    self.contentSize = CGSizeMake(x + 8, height);
    if (self.selectedIndex >= (NSInteger)chipTitles.count) _selectedIndex = -1;
    [self updateChips];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self updateChips];
}

- (void)scrollToStart {
    [self.layer removeAllAnimations];
    [self setContentOffset:CGPointMake(-self.contentInset.left, self.contentOffset.y) animated:NO];
}

- (void)updateChips {
    for (UIButton *chip in self.chips) {
        BOOL selected = (chip.tag == self.selectedIndex);
        chip.backgroundColor = selected ? [UIColor labelColor] : [UIColor tertiarySystemFillColor];
        [chip setTitleColor:selected ? [UIColor systemBackgroundColor] : [UIColor labelColor] forState:UIControlStateNormal];
        chip.tintColor = selected ? [UIColor systemBackgroundColor] : [UIColor labelColor];
    }
}

#pragma mark - Floating

- (void)attachToTableView:(UITableView *)tableView {
    // Keeps the first section header's own spacing (no default table header gap)
    tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, CGFLOAT_MIN)];
    [self attachToScrollView:tableView];
}

- (void)attachToScrollView:(UIScrollView *)tableView {
    self.insetToApply = tableView;
    self.appliedInset = NO;
    self.revealed = [self height];
    self.lastOffset = 0;
    [tableView addSubview:self];
    // Above the rows and cells whenever they're made: a reload on coming back to the screen put
    // them over the bar (it was lost until the next scroll brought it to the front)
    self.layer.zPosition = 1000;
    [self layoutInScrollView:tableView];
}

- (void)detachFromScrollView:(UIScrollView *)scrollView {
    if (self.insetToApply == scrollView) self.insetToApply = nil;
    if (self.superview != scrollView) return;
    if (self.appliedInset) {
        CGFloat height = [self height];
        UIEdgeInsets inset = scrollView.contentInset;
        inset.top = MAX(0, inset.top - height);
        scrollView.contentInset = inset;
        if (@available(iOS 13.0, *)) {
            UIEdgeInsets indicators = scrollView.verticalScrollIndicatorInsets;
            indicators.top = MAX(0, indicators.top - height);
            scrollView.verticalScrollIndicatorInsets = indicators;
        }
        self.appliedInset = NO;
    }
    [self removeFromSuperview];
}

// Adds the space the bar covers, now that the scroll view is in the window and
// its safe area is known. Doing it here rather than as the bar is attached also
// makes the navigation bar open the large title: an inset set before the scroll
// view is on screen is ignored, so it started collapsed until the first scroll.
- (void)applyInsetInScrollView:(UIScrollView *)scrollView {
    if (self.insetToApply != scrollView || !scrollView.window) return;
    self.insetToApply = nil;
    self.appliedInset = YES;

    CGFloat height = [self height];
    BOOL atTop = (scrollView.contentOffset.y + scrollView.adjustedContentInset.top) <= 0.5;
    UIEdgeInsets inset = scrollView.contentInset;
    inset.top += height;
    scrollView.contentInset = inset;
    // Growing the inset doesn't move the scroll position, which would leave the list
    // "scrolled" 48pt into the new space, under the bar, until the first scroll
    if (atTop) scrollView.contentOffset = CGPointMake(scrollView.contentOffset.x, -scrollView.adjustedContentInset.top);
    if (@available(iOS 13.0, *)) {
        UIEdgeInsets indicators = scrollView.verticalScrollIndicatorInsets;
        indicators.top += height;
        scrollView.verticalScrollIndicatorInsets = indicators;
    }
}

// Scroll position measured from the top of the content (0 = scrolled to the top)
- (CGFloat)offsetInScrollView:(UIScrollView *)scrollView {
    return scrollView.contentOffset.y + scrollView.adjustedContentInset.top;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat height = [self height];
    CGFloat offset = [self offsetInScrollView:scrollView];
    CGFloat maxOffset = MAX(0, scrollView.contentSize.height + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom - scrollView.bounds.size.height);
    CGFloat delta = offset - self.lastOffset;
    self.lastOffset = offset;

    // Only a scroll of the user's own hides or shows it: the list settling after a reload or a
    // switch between List and Compact moved it too, which hid the bar until the next real scroll
    BOOL byUser = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating;
    if (offset <= 0) {
        self.revealed = height; // at the top (or pulling down): always shown
    } else if (offset < maxOffset && byUser) {
        // Slide with the scroll - down hides, up reveals. The rubber-band past the
        // bottom is ignored, so bouncing off the end doesn't flicker the bar.
        self.revealed = MIN(height, MAX(0, self.revealed - delta));
    }
    [self positionInScrollView:scrollView offset:offset];
}

// Re-place the bar after a layout change, without treating the change as a scroll
- (void)layoutInScrollView:(UIScrollView *)scrollView {
    [self applyInsetInScrollView:scrollView];
    CGFloat offset = [self offsetInScrollView:scrollView];
    self.lastOffset = offset;
    if (offset <= 0) self.revealed = [self height];
    [self positionInScrollView:scrollView offset:offset];
}

- (void)positionInScrollView:(UIScrollView *)scrollView offset:(CGFloat)offset {
    CGFloat height = [self height];
    CGFloat navBottom = scrollView.adjustedContentInset.top - height; // top of the visible area, below the nav bar
    CGRect frame = self.frame;
    frame.origin.x = 0;
    frame.size.width = scrollView.bounds.size.width;
    // Sits just below the nav bar; while pulling down it moves with the content,
    // leaving room above it for the refresh control
    frame.origin.y = scrollView.contentOffset.y + navBottom + MAX(0, -offset) - (height - self.revealed);
    self.frame = frame;
    self.alpha = self.revealed / height;
    self.userInteractionEnabled = self.revealed > height / 2.0;
    self.backgroundColor = scrollView.backgroundColor; // covers the rows scrolling underneath
    // The chips start clear of the Dynamic Island and rounded corners in landscape
    UIEdgeInsets safe = scrollView.safeAreaInsets;
    if (self.contentInset.left != safe.left || self.contentInset.right != safe.right) {
        self.contentInset = UIEdgeInsetsMake(0, safe.left, 0, safe.right);
    }
    [scrollView bringSubviewToFront:self];
}

- (void)chipTapped:(UIButton *)chip {
    // The chosen category again: back to All, the bar staying where it is
    if (self.picker && chip.tag == self.selectedIndex) return;
    if (chip.tag == self.selectedIndex && chip.tag != -1) {
        self.selectedIndex = -1;
        if (self.onSelect) self.onSelect(-1);
        return;
    }
    self.selectedIndex = chip.tag;
    [self scrollRectToVisible:CGRectInset(chip.frame, -24, 0) animated:YES];
    if (self.onSelect) self.onSelect(chip.tag);
}

@end
