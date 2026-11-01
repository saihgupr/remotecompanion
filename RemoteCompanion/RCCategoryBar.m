#import "RCCategoryBar.h"

@interface RCCategoryBar ()
@property (nonatomic, strong) NSMutableArray<UIButton *> *chips;
// Floating: how much of the bar is showing (0 = hidden, barHeight = fully shown), and the
// last scroll position, measured from the top of the content (0 = scrolled to the top)
@property (nonatomic, assign) CGFloat revealed;
@property (nonatomic, assign) CGFloat lastOffset;
@end

@implementation RCCategoryBar

+ (CGFloat)barHeight {
    return 48;
}

- (instancetype)initWithWidth:(CGFloat)width {
    self = [super initWithFrame:CGRectMake(0, 0, width, [RCCategoryBar barHeight])];
    if (self) {
        _selectedIndex = -1;
        _chips = [NSMutableArray array];
        self.showsHorizontalScrollIndicator = NO;
        self.alwaysBounceHorizontal = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    }
    return self;
}

- (void)setChipTitles:(NSArray<NSString *> *)chipTitles {
    for (UIButton *chip in self.chips) [chip removeFromSuperview];
    [self.chips removeAllObjects];

    NSMutableArray *titles = [NSMutableArray arrayWithObject:@"All"];
    [titles addObjectsFromArray:chipTitles];
    CGFloat height = [RCCategoryBar barHeight];
    CGFloat x = 16;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
        [chip setTitle:titles[i] forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        chip.contentEdgeInsets = UIEdgeInsetsMake(7, 14, 7, 14); // UIButtonConfiguration is iOS 15+
#pragma clang diagnostic pop
        [chip sizeToFit];
        chip.frame = CGRectMake(x, (height - chip.bounds.size.height) / 2.0, chip.bounds.size.width, chip.bounds.size.height);
        chip.layer.cornerRadius = chip.bounds.size.height / 2.0;
        chip.tag = (NSInteger)i - 1; // -1 = All
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

- (void)updateChips {
    for (UIButton *chip in self.chips) {
        BOOL selected = (chip.tag == self.selectedIndex);
        chip.backgroundColor = selected ? [UIColor labelColor] : [UIColor tertiarySystemFillColor];
        [chip setTitleColor:selected ? [UIColor systemBackgroundColor] : [UIColor labelColor] forState:UIControlStateNormal];
    }
}

#pragma mark - Floating

- (void)attachToTableView:(UITableView *)tableView {
    // Keeps the first section header's own spacing (no default table header gap)
    tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, CGFLOAT_MIN)];
    [self attachToScrollView:tableView];
}

- (void)attachToScrollView:(UIScrollView *)tableView {
    CGFloat height = [RCCategoryBar barHeight];
    BOOL atTop = (tableView.contentOffset.y + tableView.adjustedContentInset.top) <= 0.5;
    UIEdgeInsets inset = tableView.contentInset;
    inset.top += height;
    tableView.contentInset = inset;
    // Growing the inset doesn't move the scroll position, which would leave the list
    // "scrolled" 48pt into the new space, under the bar, until the first scroll
    if (atTop) tableView.contentOffset = CGPointMake(tableView.contentOffset.x, -tableView.adjustedContentInset.top);
    if (@available(iOS 13.0, *)) {
        UIEdgeInsets indicators = tableView.verticalScrollIndicatorInsets;
        indicators.top += height;
        tableView.verticalScrollIndicatorInsets = indicators;
    }
    self.revealed = height;
    self.lastOffset = 0;
    [tableView addSubview:self];
    [self layoutInScrollView:tableView];
}

// Scroll position measured from the top of the content (0 = scrolled to the top)
- (CGFloat)offsetInScrollView:(UIScrollView *)scrollView {
    return scrollView.contentOffset.y + scrollView.adjustedContentInset.top;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat height = [RCCategoryBar barHeight];
    CGFloat offset = [self offsetInScrollView:scrollView];
    CGFloat maxOffset = MAX(0, scrollView.contentSize.height + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom - scrollView.bounds.size.height);
    CGFloat delta = offset - self.lastOffset;
    self.lastOffset = offset;

    if (offset <= 0) {
        self.revealed = height; // at the top (or pulling down): always shown
    } else if (offset < maxOffset) {
        // Slide with the scroll - down hides, up reveals. The rubber-band past the
        // bottom is ignored, so bouncing off the end doesn't flicker the bar.
        self.revealed = MIN(height, MAX(0, self.revealed - delta));
    }
    [self positionInScrollView:scrollView offset:offset];
}

// Re-place the bar after a layout change, without treating the change as a scroll
- (void)layoutInScrollView:(UIScrollView *)scrollView {
    CGFloat offset = [self offsetInScrollView:scrollView];
    self.lastOffset = offset;
    if (offset <= 0) self.revealed = [RCCategoryBar barHeight];
    [self positionInScrollView:scrollView offset:offset];
}

- (void)positionInScrollView:(UIScrollView *)scrollView offset:(CGFloat)offset {
    CGFloat height = [RCCategoryBar barHeight];
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
    [scrollView bringSubviewToFront:self];
}

- (void)chipTapped:(UIButton *)chip {
    self.selectedIndex = chip.tag;
    [self scrollRectToVisible:CGRectInset(chip.frame, -24, 0) animated:YES];
    if (self.onSelect) self.onSelect(chip.tag);
}

@end
