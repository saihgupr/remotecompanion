#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// screen capture [PATH] [SCALE] [QUALITY] [grid [SPACING]]: a JPEG of the screen as SpringBoard shows
// it (default /var/mobile/tmp/rc-screen.jpg, at 0.5 of its size in points, JPEG quality 0.6). PATH
// must be in /var/mobile/tmp or /tmp. "grid" draws labelled lines every SPACING points (default 100)
// so a point can be read off the picture. Replies "PATH WIDTHxHEIGHT BYTES bytes".
//
// screen settle [MAX]: waits until the screen stops changing (a page sliding in, an app opening),
// at most MAX seconds (default 3). Replies "Settled after N ms" or "Still changing after N ms".
NSString *RCScreenCommand(NSString *cmd);

// Waits until the screen stops changing, at most `maxSeconds`: YES when it did. Not on the main
// thread (returns NO at once there). *waited: how long it took.
BOOL RCScreenSettle(double maxSeconds, double *waited);

// Draws a screen grab (always upright) into the current image context the way the screen is turned
// now, at `scale` times its size in points. Main thread.
void RCScreenDrawShot(UIImage *shot, double scale);
