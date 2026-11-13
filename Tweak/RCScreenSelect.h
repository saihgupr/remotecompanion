#import <Foundation/Foundation.h>

// Copies text on the screen to the clipboard and returns the copied text:
//   ""             every line on the screen (screen copy)
//   rect [SECONDS] user draws a box on screen, then copies the lines inside (20 s default, 120 max)
// Never called on SpringBoard's main thread.
NSString *RCScreenCopyCommand(NSString *args);

