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
