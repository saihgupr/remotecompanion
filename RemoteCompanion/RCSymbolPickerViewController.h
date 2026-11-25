#import <UIKit/UIKit.h>

// One icon in the picker: the symbol over its name (Settings > Layout's preview draws them too)
@interface RCSymbolTileCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, assign) BOOL chosen;
// Layout > Icons > Tile Names: Hide - the symbol alone, larger; the name stays for VoiceOver
@property (nonatomic, assign) BOOL iconOnly;
@end

// A category chip's icon (Favorites, Common, Media ...), or nil
UIImage *RCSymbolCategoryIcon(NSString *title);

// A tile's size in a grid this wide, at Layout > Icons > Per Row (more on a wider screen), square
CGSize RCSymbolTileSize(CGFloat gridWidth);

// Picks an SF Symbol from a searchable grid of icon tiles, filtered by category chips.
// Typing a symbol name that isn't in the grid offers it too. Push it onto a navigation stack.
@interface RCSymbolPickerViewController : UIViewController

// selected: the current symbol name, or nil. allowsNone: offers a "None" tile.
- (instancetype)initWithSelectedSymbol:(NSString *)selected allowsNone:(BOOL)allowsNone;

// Called with the picked name ("" for None) when Done is tapped; the picker then goes back. Tapping an
// icon only marks it, and Back leaves without calling this.
@property (nonatomic, copy) void (^onPick)(NSString *name);

// Shown first, as a Favorites category (set before it's shown); nil for none
@property (nonatomic, copy) NSArray<NSString *> *favoriteSymbols;

@end
