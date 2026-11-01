#import <UIKit/UIKit.h>

// The action picker's and Banners' grid: square tiles (an icon over a name) under section titles.

@interface RCActionTileCell : UICollectionViewCell
@property (nonatomic, strong, readonly) UIImageView *iconView;
@property (nonatomic, strong, readonly) UILabel *nameLabel;
// A small chevron in the corner: tapping opens another screen or asks for more
@property (nonatomic, assign) BOOL opensMore;
// Banners: a tinted tile with a checkmark
@property (nonatomic, assign) BOOL checked;
- (void)setName:(NSString *)name icon:(NSString *)icon;
// image: a picture of its own (an add-on's), shown instead of the symbol
- (void)setName:(NSString *)name icon:(NSString *)icon image:(UIImage *)image;
// Triggers in Compact: a trigger with no actions yet gets a quieter tile
@property (nonatomic, assign) BOOL dimmed;
// Triggers in Compact: how many actions it runs, in a small badge at the top right (0: none)
@property (nonatomic, assign) NSInteger count;
// Triggers in Compact, Edit mode: a star (filled for a favorite) at the top left and, for a
// trigger that can be deleted, a minus at the top right
- (void)showEditBadgesFavorite:(BOOL)favorite deletable:(BOOL)deletable onFavorite:(void (^)(void))onFavorite onDelete:(void (^)(void))onDelete;
- (void)hideEditBadges;
@end

// A section's title over its tiles, or (as a footer) a note under them
@interface RCActionGridHeader : UICollectionReusableView
@property (nonatomic, strong, readonly) UILabel *label;
- (void)setTitle:(NSString *)title;
- (void)setNote:(NSString *)note;
@end

// The layout both grids use
UICollectionViewFlowLayout *RCActionGridLayout(void);
// One tile's size for a grid this wide: as many columns as fit, at least three
CGSize RCActionTileSize(CGFloat gridWidth);
// A footer note's height for this text and grid width
CGFloat RCActionGridNoteHeight(NSString *note, CGFloat gridWidth);

#pragma mark - List rows

// The List layout of the same screens: a row per action (an icon, its name, a chevron or a
// checkmark), grouped into rounded cards like an inset-grouped table
@interface RCActionRowCell : UICollectionViewCell
@property (nonatomic, assign) BOOL opensMore;
@property (nonatomic, assign) BOOL checked;
- (void)setName:(NSString *)name icon:(NSString *)icon image:(UIImage *)image;
// Its place in its section: the first and last rows round their corners, the others get a separator
- (void)setFirst:(BOOL)first last:(BOOL)last;
@end

// A row's size in a list this wide
CGSize RCActionRowSize(CGFloat listWidth, CGFloat height);

#pragma mark - Layout setting (List or Compact, per screen)

extern NSString *const RCLayoutTriggers;
extern NSString *const RCLayoutActionPicker;
extern NSString *const RCLayoutBanners;
// Posted when a screen's layout changes (object: the screen's key)
extern NSString *const RCLayoutChangedNotification;

BOOL RCLayoutIsCompact(NSString *screen);
void RCLayoutSetCompact(NSString *screen, BOOL compact);
// The screens, in order: @[title, key]
NSArray<NSArray<NSString *> *> *RCLayoutScreens(void);
// A settings row for one screen: its title and a List / Compact control
UITableViewCell *RCLayoutSettingCell(NSString *title, NSString *screen);

#pragma mark - App icons

// An app's icon, rounded, this many points square; nil when the app isn't installed
UIImage *RCAppIconImage(NSString *bundleId, CGFloat side);
