#import <Foundation/Foundation.h>

// Screen actions and the Screen Shows Text condition: what rc-screen reads on the screen, for
// triggers. Never on SpringBoard's main thread: rc-screen asks SpringBoard for the screen.

// screen tap "Text" | screen wait "Text" [SECONDS] | screen scroll-to "Text"
// screen capture [PATH] [SCALE] [QUALITY]: a JPEG of the screen (default /var/mobile/tmp/rc-screen.jpg,
// at 0.5 of its points, quality 0.6)
NSString *RCScreenCommand(NSString *cmd);

// Whether an element on screen has this text in its label or value (case doesn't matter)
BOOL RCScreenShowsText(NSString *text);
