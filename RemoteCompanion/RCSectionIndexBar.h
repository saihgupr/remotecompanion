#import <UIKit/UIKit.h>

// The vertical section index down the left edge of a grouped table: one short
// code per section, scrubbed with a finger. The table glides to the section
// under the finger, a small floating capsule names it, and each new section
// ticks the haptic. On lift the index settles on the section and the scroll
// indicator stays out of the way.
//
// It floats over the screen rather than scrolling with the table, so it is
// added to the view controller's view and given the table it drives.
@interface RCSectionIndexBar : UIView

@property (nonatomic, weak) UITableView *tableView;

// The chrome above the list's first row: the navigation bar, the large title
// and the category bar, measured from the top of the view. The rail starts
// below it, so it never covers a chip.
@property (nonatomic, assign) CGFloat topChrome;

// One entry per table section, in the same order. Icons are UIImage or NSNull
// and only appear in the floating capsule.
- (void)setSectionTitles:(NSArray<NSString *> *)titles icons:(NSArray *)icons;

// Recomputes the rail for the host's current size and safe area. Call from
// viewDidLayoutSubviews.
- (void)layoutInView:(UIView *)host;

// Grid mode, an empty list or a single category all leave nothing to scrub.
// A hidden bar takes no touches and fades in and out with the layout change.
- (void)setShown:(BOOL)shown animated:(BOOL)animated;

// A finger on the table wins over a glide that is still running.
- (void)cancelScrollAnimation;

@end
