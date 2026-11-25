#import <UIKit/UIKit.h>

// Setting something up where it's needed, instead of a trip to Settings: the server or device
// editor opens from the screen that needs one, and that screen carries on once it's saved.
typedef NS_ENUM(NSInteger, RCSetupKind) {
    RCSetupKindSSHHost,     // Settings > Integrations > SSH Hosts
    RCSetupKindRemoteRC,    // Settings > Integrations > Remote RC Clients
};

// Opens the editor for a new one, pushed when the screen is in a navigation controller, else
// presented; then gets what was saved (its "id" among it) once the editor has closed
void RCOpenSetupEditor(UIViewController *from, RCSetupKind kind, void (^then)(NSDictionary *saved));

// There's none yet: an alert saying what the action needs, with Cancel and Add Server / Add Device
void RCPresentSetupNeeded(UIViewController *from, RCSetupKind kind, NSString *title, NSString *message, void (^then)(NSDictionary *saved));

// "Add Server…" / "Add Device…" for the end of a list of them in an action sheet
UIAlertAction *RCSetupAddAction(UIViewController *from, RCSetupKind kind, void (^then)(NSDictionary *saved));
