#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, RCNotifyWatchMode) {
    RCNotifyWatchNormal = 0, // stock iOS routing (alerts Watch only while iPhone is locked)
    RCNotifyWatchAlso   = 1, // --watch: force alert on Watch too, even while iPhone is unlocked
    RCNotifyWatchOnly   = 2, // --watch only: force alert on Watch and suppress iPhone banner/sound
};

// A Notification action's command, taken apart and put back together:
//   notify "Title" "Message" [--urgent] [--watch [only]] [--remove-after SECONDS] [--image "sf:NAME"|"app:BUNDLE"]
//          [--image-url "URL"] [--tap ID] [--button "ID|Title|flags"]... [--wait SECONDS]
// The tap ID names its Notification Tap trigger (notiftap_<ID>), each button's ID its button
// trigger (notifbtn_<ID>); flags are "red" and "unlock", comma-separated.
@interface RCNotifyCommand : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, assign) BOOL urgent;
@property (nonatomic, assign) RCNotifyWatchMode watchMode;
@property (nonatomic, assign) NSInteger removeAfter;   // seconds, 0 keeps it
// Wait for Response: seconds the action waits for an answer (0: it doesn't); the answer (Tap, a
// button's name, Cleared, Expired, Timed Out) goes in the run's {notify_response}
@property (nonatomic, assign) NSInteger wait;
@property (nonatomic, copy) NSString *image;           // "sf:NAME", "app:BUNDLE" or nil
@property (nonatomic, copy) NSString *imageURL;        // http(s) photo attached to the notification, or nil
@property (nonatomic, copy) NSString *tapID;
// @{ id, title, red: @BOOL, unlock: @BOOL }, at most 4
@property (nonatomic, copy) NSArray<NSDictionary *> *buttons;

+ (BOOL)isNotifyCommand:(NSString *)command;   // a Notification action (not notify clear)
+ (instancetype)commandWithString:(NSString *)command;
- (NSString *)string;
+ (NSString *)newID;
// The run variable a waiting Notification action sets, when one of these actions waits; else nil
+ (NSString *)responseVariableIn:(NSArray *)actions;
// A pasted action (a string or an action dictionary): a Notification action gets a new tap ID and
// new button IDs, so the copy has triggers of its own; anything else comes back as a copy
+ (id)copyOfActionWithNewIDs:(id)item;
@end
