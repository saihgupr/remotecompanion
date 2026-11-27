#import <UIKit/UIKit.h>

// Holiday Mode: slow snowfall in the app controlled by the Holiday Mode toggle in Settings.
//
// The setting lives in the shared config (`holidayModeEnabled`, off by default) so the Web UI can
// change it too.
@interface RCHolidayMode : NSObject

+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;

+ (BOOL)isSnowing;
+ (void)startSnow;
+ (void)stopSnow;

// Settles the snow against the config: starts it when Holiday Mode is on, stops it when off.
// Safe to call as often as you like.
+ (void)refresh;

@end
