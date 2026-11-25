#import <UIKit/UIKit.h>

// A full-screen, touch-through layer of slow snow: tiny crisp flakes far away, soft mid-sized
// ones, and a handful of large out-of-focus flakes close up. The flakes are drawn in code, so
// there are no image files to ship. Made fresh each time the snow is switched on; it fades
// itself in, and fades itself out and off the window when asked to stop.
@interface RCSnowfallView : UIView

@property (nonatomic, assign, readonly, getter=isSnowing) BOOL snowing;

- (void)startSnowing;

// Fades the snow out over about 0.6 seconds, then removes the view from its window.
// The completion runs on the main queue after the view is gone.
- (void)stopSnowingWithCompletion:(void (^)(void))completion;

@end
