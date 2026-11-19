#import <Foundation/Foundation.h>

// Opens the Developer Mode annotation overlay (live dictation + red rectangle over a frozen
// screenshot) and delivers the annotated image + prompt text to the configured editor over SSH.
// Never called on SpringBoard's main thread.
NSString *RCDevAnnotateCommand(NSString *cmd,
                               NSDictionary *config,
                               void (^showToast)(NSString *title, NSString *subtitle, NSString *icon));
