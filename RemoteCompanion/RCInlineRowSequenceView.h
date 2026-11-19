#import <UIKit/UIKit.h>

#import "RCInlineRowItem.h"

typedef NS_ENUM(NSInteger, RCInlineRowSequenceStyle) {
    RCInlineRowSequenceStyleChips = 0,     // tapping a row asks for the value elsewhere
    RCInlineRowSequenceStyleInline,        // the row opens in place
    RCInlineRowSequenceStyleSheet,         // tapping a row slides a sheet up
    RCInlineRowSequenceStyleInspector,     // tapping a row selects it
};

// One action's row as a card: the row itself, and the editor it opens under it.
@interface RCInlineRowCardView : UIView
@property (nonatomic, strong, readonly) RCInlineRowItem *item;
@property (nonatomic, copy) void (^onActivate)(void);
@property (nonatomic, assign) BOOL showsGrabber;
@property (nonatomic, assign, getter=isExpanded) BOOL expanded;
@property (nonatomic, assign, getter=isSelected) BOOL selected;
@property (nonatomic, assign, getter=isDimmed) BOOL dimmed;
- (instancetype)initWithItem:(RCInlineRowItem *)item;
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
- (void)refresh;
@end

// A sequence of those cards, the way the action sequence lays them out.
@interface RCInlineRowSequenceView : UIView
@property (nonatomic, strong, readonly) NSArray<RCInlineRowItem *> *items;
@property (nonatomic, strong, readonly) NSArray<RCInlineRowCardView *> *cards;
@property (nonatomic, assign, readonly) RCInlineRowSequenceStyle style;
@property (nonatomic, assign) NSInteger expandedIndex;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^onActivate)(NSInteger index, RCInlineRowItem *item);
- (instancetype)initWithItems:(NSArray<RCInlineRowItem *> *)items style:(RCInlineRowSequenceStyle)style;
- (void)refresh;
- (void)setExpandedIndex:(NSInteger)index animated:(BOOL)animated;
@end
