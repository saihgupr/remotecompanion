#import <UIKit/UIKit.h>

// The action picker's and Banners' grid: square tiles (an icon over a name) under section titles.

@interface RCActionTileCell : UICollectionViewCell
@property (nonatomic, strong, readonly) UIImageView *iconView;
@property (nonatomic, strong, readonly) UILabel *nameLabel;
// A small chevron in the corner: tapping opens another screen or asks for more
@property (nonatomic, assign) BOOL opensMore;
// Banners: a checkmark
@property (nonatomic, assign) BOOL checked;
// Checked without tinting the whole tile: the check stays, the background and icon do not change
@property (nonatomic, assign) BOOL plainChecked;
- (void)setName:(NSString *)name icon:(NSString *)icon;
// image: a picture of its own (an add-on's), shown instead of the symbol
- (void)setName:(NSString *)name icon:(NSString *)icon image:(UIImage *)image;
// Tile Names: Hide - the icon alone, centred and larger; the name stays for VoiceOver
@property (nonatomic, assign) BOOL iconOnly;
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
// The same, with an icon before the title (nil: none)
- (void)setTitle:(NSString *)title icon:(UIImage *)icon;
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

// The width a grid lays out in: its own, less the safe area at the sides (the Dynamic Island and
// rounded corners in landscape)
CGFloat RCGridWidth(UIScrollView *view);

// A row's size in a list this wide
CGSize RCActionRowSize(CGFloat listWidth, CGFloat height);

#pragma mark - Layout settings (per screen)

// The four screens Settings > Layout sets up, each on its own
extern NSString *const RCLayoutTriggers;
extern NSString *const RCLayoutActionPicker;
extern NSString *const RCLayoutBanners;
// The + menu on Triggers (New Trigger)
extern NSString *const RCLayoutNewTrigger;
// The icon picker (a Show Banner action's Icon, Control Center buttons, notifications): always a grid,
// so it has Per Row, Tile Names and Category Bar Lines only
extern NSString *const RCLayoutIcons;
// The screens, in order: @[title, key]
NSArray<NSArray<NSString *> *> *RCLayoutScreens(void);

// A screen's options (the change notice's userInfo[RCLayoutOptionKey] says which one changed)
extern NSString *const RCLayoutOptionCompact;      // List or Compact
extern NSString *const RCLayoutOptionPerRow;       // tiles per row in Compact
extern NSString *const RCLayoutOptionSections;     // section headings in Compact (Show / Hide)
extern NSString *const RCLayoutOptionNames;        // names on the tiles in Compact (Show / Hide)
extern NSString *const RCLayoutOptionBarLines;     // lines of category chips
extern NSString *const RCLayoutOptionKey;
// Posted when a screen's layout changes (object: the screen's key)
extern NSString *const RCLayoutChangedNotification;

BOOL RCLayoutIsCompact(NSString *screen);
void RCLayoutSetCompact(NSString *screen, BOOL compact);
// Tiles per row: 2, 3 or 4 on Triggers (2 is wide cards), 4, 5 or 6 on Icons, 3, 4 or 5 on the others
// (4 to begin with)
NSInteger RCLayoutPerRow(NSString *screen);
void RCLayoutSetPerRow(NSString *screen, NSInteger count);
NSArray<NSNumber *> *RCLayoutPerRowChoices(NSString *screen);
// One continuous grid, without section headings (while no category chip is picked)
BOOL RCLayoutSectionsHidden(NSString *screen);
void RCLayoutSetSectionsHidden(NSString *screen, BOOL hidden);
// Icons alone, larger, on square tiles; the names stay for VoiceOver
BOOL RCLayoutNamesHidden(NSString *screen);
void RCLayoutSetNamesHidden(NSString *screen, BOOL hidden);
// Category bar: 1, 2 or 3 lines of chips. A nil screen (Settings, the symbol picker) follows Triggers.
NSInteger RCLayoutBarLines(NSString *screen);
void RCLayoutSetBarLines(NSString *screen, NSInteger lines);

// The options Settings > Layout shows for a screen, in order: @[title, option]. Per Row, Section
// Headings and Tile Names only while it's in Compact (Icons: Per Row, Tile Names, Category Bar Lines).
NSArray<NSArray<NSString *> *> *RCLayoutOptionRows(NSString *screen);
// A settings row for one option of one screen: its title and a segmented control
UITableViewCell *RCLayoutOptionCell(NSString *title, NSString *screen, NSString *option);

// A tile's size on one of the tile screens in Compact, for a grid this wide: its Per Row (more on a
// wider screen), square when its names are hidden
CGSize RCActionTileSizeForScreen(CGFloat gridWidth, NSString *screen);

#pragma mark - App icons

// An app's icon, rounded, this many points square; nil when the app isn't installed
UIImage *RCAppIconImage(NSString *bundleId, CGFloat side);
// The same, for an App Launch or App Exit trigger: a green checkmark (launch) or a red x (exit) in a
// white circle at its top right
UIImage *RCAppTriggerIconImage(NSString *bundleId, CGFloat side, BOOL exit);
