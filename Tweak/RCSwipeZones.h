#import <UIKit/UIKit.h>

// Swipe Triggers > Adjust on Screen: SpringBoard's overlay that draws every swipe trigger zone and
// distance at its real size over whatever app is open, each with a handle to drag (and - and +
// buttons for a point at a time). Changes apply at once and are saved. Hide tucks it into a small
// button at the side, which brings it back.
//
// The app opens it by posting kRCSwipeZonesShowNotification.
#define kRCSwipeZonesShowNotification "com.pizzaman.rc.swipe_zones.show"
// Its state is 1 while the zones are drawn: every app and SpringBoard hide their status bar, so
// the clock and icons don't cover the zone names
#define kRCSwipeZonesOpenNotification "com.pizzaman.rc.swipe_zones.open"

// Open with the zones drawn (while it is, SpringBoard's edge gestures are held back)
BOOL RCSwipeZonesIsExpanded(void);
// A handle is being dragged (swipe and button triggers are paused meanwhile)
BOOL RCSwipeZonesIsDragging(void);

// In Tweak.x: the config as the tweak has it, and applying swipe settings to it (a value equal to
// its default removes the key); save also writes the config for the app, the CLI and the Web UI
NSDictionary *RCSwipeZonesConfig(void);
void RCSwipeZonesApply(NSDictionary<NSString *, NSNumber *> *values, NSDictionary<NSString *, NSNumber *> *defaults, BOOL save);
