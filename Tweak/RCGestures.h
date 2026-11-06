#import <Foundation/Foundation.h>

// Gestures: touches recorded while the phone is used normally, saved by name in a library
// (rc_gestures.plist) and played back as an action. All of it lives in RCGestures.m; Tweak.x
// only passes it digitizer events and "gesture ..." commands.

void RCGestureHIDEvent(const void *event);   // every digitizer event, from the HID listener's thread
NSString *RCGestureCommand(NSString *cmd);   // "gesture ..." commands
NSArray<NSDictionary *> *RCGestureList(void); // name, duration, strokes: for the web UI (/api/gestures)
