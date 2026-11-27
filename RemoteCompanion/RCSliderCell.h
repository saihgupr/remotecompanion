#import <UIKit/UIKit.h>

// A setting that's a number: its name and value on top, and below them a slider between − and +
// buttons (held, they repeat). Tapping the value lets a number be typed, or the default put back.
// The value moves in steps (0.01 s, 1 pt...) and stays between min and max.
@interface RCSliderCell : UITableViewCell
// format: how the value reads ("%.2f s", "%.0f pt", "%.0f%%")
- (void)setTitle:(NSString *)title value:(double)value min:(double)min max:(double)max
            step:(double)step defaultValue:(double)defaultValue format:(NSString *)format;
// Called once a change is finished: on letting go of the slider, on each − or + step, and after
// typing. The value is already rounded to a step.
@property (nonatomic, copy) void (^onChange)(double value);
// Called while the slider moves, before it's let go (nil: nothing)
@property (nonatomic, copy) void (^onSlide)(double value);
// The screen that asks for a typed value
@property (nonatomic, weak) UIViewController *presenter;
// A short description shown when typing a value (nil: none)
@property (nonatomic, copy) NSString *message;
@property (nonatomic, readonly) double value;
// The setting's config key, for its lock: the lock after + (held) keeps the value from being changed
// by accident until it's unlocked, here, in the Web UI and in Adjust on Screen (nil: no lock)
@property (nonatomic, copy) NSString *lockKey;
+ (CGFloat)rowHeight;
@end
