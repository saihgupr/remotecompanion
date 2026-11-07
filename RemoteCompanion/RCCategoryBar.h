#import <UIKit/UIKit.h>

// Horizontally scrolling category chips: "All" followed by one chip per title.
// Floats at the top of a table to filter it by section: it hides as you scroll
// down and reappears as soon as you scroll up.
@interface RCCategoryBar : UIScrollView

// -1 = All, otherwise an index into titles
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^onSelect)(NSInteger index);
// 1, 2 or 3 lines of chips (Layout > Category Bar Lines sets it; it follows changes while shown)
@property (nonatomic, assign) NSInteger rows;
// The bar's height for its number of lines
- (CGFloat)height;

+ (CGFloat)barHeight;
- (instancetype)initWithWidth:(CGFloat)width;
// Rebuilds the chips; chipTitles are what the chips show (same count as the sections)
- (void)setChipTitles:(NSArray<NSString *> *)chipTitles;
// The same, with an icon before each chip's name (icons: UIImage or NSNull, one per title; All
// gets a grid)
- (void)setChipTitles:(NSArray<NSString *> *)chipTitles icons:(NSArray *)icons;
// Back to the far left (All), even if a chip was just scrolled into view
- (void)scrollToStart;

// Floats the bar over the top of the table (insetting its content by the bar's height).
// The screen must forward scrollViewDidScroll: to -scrollViewDidScroll:, and call
// -layoutInScrollView: from viewDidLayoutSubviews (the table's size and insets aren't
// known yet when the bar is attached, and change with rotation / the large title).
- (void)attachToTableView:(UITableView *)tableView;
// The same for any scroll view, such as a collection view
- (void)attachToScrollView:(UIScrollView *)scrollView;
// Takes the bar off a scroll view it was attached to, giving back the space it made
- (void)detachFromScrollView:(UIScrollView *)scrollView;
- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
- (void)layoutInScrollView:(UIScrollView *)scrollView;

@end
