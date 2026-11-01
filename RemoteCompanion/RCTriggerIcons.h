#import <UIKit/UIKit.h>

// A trigger's own icon, so the button and gesture triggers are told apart at a glance: a symbol
// with a small badge (2 / 3 / 4 for clicks, a timer for a hold, L / C / R for a side, an arrow for a
// direction), or two symbols side by side (Power + Volume Up). A template image, so it takes the
// tint of wherever it's shown. nil for a trigger without one (the caller uses its plain symbol).
UIImage *RCTriggerIconImage(NSString *triggerKey, CGFloat pointSize);

// A plain symbol drawn in the same box, so icons with and without badges line up
UIImage *RCTriggerSymbolImage(NSString *symbolName, CGFloat pointSize);
