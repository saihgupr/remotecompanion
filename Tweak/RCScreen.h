#import <Foundation/Foundation.h>

// screen capture [PATH] [SCALE] [QUALITY] [grid [SPACING]]: a JPEG of the screen as SpringBoard shows
// it (default /var/mobile/tmp/rc-screen.jpg, at 0.5 of its size in points, JPEG quality 0.6). PATH
// must be in /var/mobile/tmp or /tmp. "grid" draws labelled lines every SPACING points (default 100)
// so a point can be read off the picture. Replies "PATH WIDTHxHEIGHT BYTES bytes".
//
// screen settle [MAX]: waits until the screen stops changing (a page sliding in, an app opening),
// at most MAX seconds (default 3). Replies "Settled after N ms" or "Still changing after N ms".
//
// Text on the screen, read with Apple's text recognition (Vision, in SpringBoard), so any drawn
// text counts, in any app. Never on SpringBoard's main thread (from it, these run on their own):
// screen ocr [fast] [--json]: every line of text with its box in points
// screen find "Text": where the best match is
// screen tap "Text": waits for the screen to settle, then taps it
// screen wait "Text" [SECONDS]: waits until it shows and the screen has settled (default 10 s, at most 120)
NSString *RCScreenCommand(NSString *cmd);

// Waits until the screen stops changing, at most `maxSeconds`: YES when it did. Not on the main
// thread (returns NO at once there). *waited: how long it took.
BOOL RCScreenSettle(double maxSeconds, double *waited);

// The Text on Screen condition: whether a line on screen has this text (case doesn't matter).
// NO from the main thread, or when the screen can't be read.
BOOL RCScreenShowsText(NSString *text);
