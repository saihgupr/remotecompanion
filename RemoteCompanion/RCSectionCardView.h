#import <UIKit/UIKit.h>

// Where a row sits inside its run of cards. This decides which corners are
// rounded and which shared border lines are hidden, so a stack of rows reads
// as one card instead of a pile of boxes.
typedef NS_ENUM(NSInteger, RCSectionCardPosition) {
    RCSectionCardPositionMiddle = 0, // square corners, top and bottom border lines hidden
    RCSectionCardPositionFirst,      // top corners rounded, bottom border line hidden
    RCSectionCardPositionLast,       // bottom corners rounded, top border line hidden
    RCSectionCardPositionSingle,     // all corners rounded, full border
};

// The rounded card drawn behind a table row.
//
// The fill and border are shape layers built from this view's own bounds, and
// they are rebuilt in layoutSubviews whenever those bounds change. That is what
// keeps a card the right width after the device rotates: the row resizes and
// the card follows, with no table reload and no new view needed.
@interface RCSectionCardView : UIView

@property (nonatomic, strong) UIColor *fillColor;
@property (nonatomic, strong) UIColor *borderColor;

// Width of the border line, drawn inside the fill's edge. Default 1.
@property (nonatomic, assign) CGFloat borderWidth;

// Default 12.
@property (nonatomic, assign) CGFloat cornerRadius;

// Default RCSectionCardPositionMiddle.
@property (nonatomic, assign) RCSectionCardPosition position;

// Sets everything the caller cares about in one go. Call it again when a
// reused cell is configured for a different row.
- (void)configureWithFillColor:(UIColor *)fillColor
                   borderColor:(UIColor *)borderColor
                   borderWidth:(CGFloat)borderWidth
                  cornerRadius:(CGFloat)cornerRadius
                      position:(RCSectionCardPosition)position;

@end
