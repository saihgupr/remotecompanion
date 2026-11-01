#import <UIKit/UIKit.h>

// The Triggers screen in Compact: its sections as a grid of tiles. The screen keeps its data and
// does the work; the grid asks it what to show and tells it what was tapped.
//   Tap: open the trigger.  Long press: run it now.
//   Edit mode: a star on each tile (favorite or not), a minus on the ones that can be deleted,
//   and favorites can be dragged to reorder them.

@protocol RCTriggersGridSource <NSObject>
- (NSInteger)gridSectionCount;
- (NSString *)gridTitleForSection:(NSInteger)section;
- (NSArray<NSString *> *)gridKeysInSection:(NSInteger)section;
- (BOOL)gridSectionIsFavorites:(NSInteger)section;
- (NSString *)gridNameForTrigger:(NSString *)key;
- (NSString *)gridIconForTrigger:(NSString *)key;
- (UIImage *)gridImageForTrigger:(NSString *)key; // an app's icon, or nil
- (NSInteger)gridActionCountForTrigger:(NSString *)key;
- (BOOL)gridTriggerIsFavorite:(NSString *)key;
- (BOOL)gridCanDeleteTrigger:(NSString *)key;
- (void)gridOpenTrigger:(NSString *)key;
- (void)gridRunTrigger:(NSString *)key fromView:(UIView *)view;
- (void)gridToggleFavorite:(NSString *)key;
- (void)gridDeleteTrigger:(NSString *)key fromView:(UIView *)view;
- (void)gridMoveFavoriteFrom:(NSInteger)from to:(NSInteger)to;
- (void)gridDidScroll:(UIScrollView *)scrollView;
@end

@interface RCTriggersGrid : NSObject <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong, readonly) UICollectionView *collectionView;
@property (nonatomic, weak) id<RCTriggersGridSource> source;
@property (nonatomic, assign) BOOL editing;
// Shown under the last section (the app's name and version)
@property (nonatomic, strong) UIView *footerView;
- (instancetype)initWithSource:(id<RCTriggersGridSource>)source;
- (void)reload;
@end
