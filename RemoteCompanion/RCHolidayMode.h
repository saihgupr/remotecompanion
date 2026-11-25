#import <UIKit/UIKit.h>

// Holiday Mode: the red present in the main screen's header and the slow snowfall it turns on.
//
// The setting lives in the shared config (`holidayModeEnabled`, on by default) so the Web UI can
// change it too; the snow itself is only ever on after the present has been tapped, and it starts
// off again on every launch.
@interface RCHolidayMode : NSObject

+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;

+ (BOOL)isSnowing;
+ (void)toggleSnow;
+ (void)stopSnow;

// Settles the snow against the config: stops it when Holiday Mode has been turned off. Safe to
// call as often as you like.
+ (void)refresh;

// The present: a red gift that toggles the snow. One bar button item per screen is enough;
// keep the one it returns and reuse it.
+ (UIBarButtonItem *)presentBarButtonItemWithTarget:(id)target action:(SEL)action;

@end
