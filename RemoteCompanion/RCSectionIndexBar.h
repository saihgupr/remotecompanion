#import <UIKit/UIKit.h>

// The alphabet index down the left edge of the Triggers list: a star for
// Favorites, then one letter per category initial, scrubbed with a finger. The
// table glides to the first category filed under the letter, a small floating
// capsule names it, and each new letter ticks the haptic. On lift the index
// settles on the category and the scroll indicator stays out of the way.
//
// It floats over the screen rather than scrolling with the table, so it is
// added to the view controller's view and given the table it drives.
@interface RCSectionIndexBar : UIView

@property (nonatomic, weak) UITableView *tableView;

// The chrome above the list's first row: the navigation bar, the large title
// and the category bar, measured from the top of the view. The rail stays
// below it, so it never covers a chip.
@property (nonatomic, assign) CGFloat topChrome;

// The table's sections, in the order the table shows them. The rail draws one
// entry per distinct initial (Favorites gets a star) and jumps to the first
// section with that initial. Icons are UIImage or NSNull and only appear in the
// floating capsule.
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
