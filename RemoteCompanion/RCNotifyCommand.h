#import <Foundation/Foundation.h>

// A Notification action's command, taken apart and put back together:
//   notify "Title" "Message" [--urgent] [--remove-after SECONDS] [--image "sf:NAME"|"app:BUNDLE"]
//          [--tap ID] [--button "ID|Title|flags"]...
// The tap ID names its Notification Tap trigger (notiftap_<ID>), each button's ID its button
// trigger (notifbtn_<ID>); flags are "red" and "unlock", comma-separated.
@interface RCNotifyCommand : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, assign) BOOL urgent;
@property (nonatomic, assign) NSInteger removeAfter;   // seconds, 0 keeps it
@property (nonatomic, copy) NSString *image;           // "sf:NAME", "app:BUNDLE" or nil
@property (nonatomic, copy) NSString *tapID;
// @{ id, title, red: @BOOL, unlock: @BOOL }, at most 4
@property (nonatomic, copy) NSArray<NSDictionary *> *buttons;

+ (BOOL)isNotifyCommand:(NSString *)command;   // a Notification action (not notify clear)
+ (instancetype)commandWithString:(NSString *)command;
- (NSString *)string;
+ (NSString *)newID;
@end
