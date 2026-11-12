#import <UIKit/UIKit.h>

// A trigger's own icon, so the button and gesture triggers are told apart at a glance: a tiny
// phone with the pressed button filled in, or the touched part of the screen with a dot or an
// arrow, and what happens inside (2×, a clock for a hold, + for two buttons). A template image,
// so it takes the tint of wherever it's shown. nil for a trigger without one.
UIImage *RCTriggerIconImage(NSString *triggerKey, CGFloat pointSize);

// A plain symbol drawn in the same box, so icons with and without badges line up
UIImage *RCTriggerSymbolImage(NSString *symbolName, CGFloat pointSize);

// The same, with a letter in a small badge at the bottom right: a created trigger's first letter,
// so NFC tags, networks and devices of one kind are told apart. No letter: the plain symbol.
UIImage *RCTriggerLetterImage(NSString *symbolName, NSString *letter, CGFloat pointSize);

// A name the two functions above take in place of a symbol's: the Bluetooth logo, drawn (there's
// no symbol for it)
extern NSString *const RCBluetoothIconName;

// The Bluetooth logo on its own, about as tall as a symbol of this size: for rows and chips that
// show plain symbols. A template image.
UIImage *RCBluetoothIcon(CGFloat pointSize);

// A Triggers section's icon, by its title ("Volume Buttons", "NFC Tags"...): for the category
// chips and the section titles. A template symbol; nil for an unknown section.
UIImage *RCTriggerCategoryIcon(NSString *sectionTitle);

// The same for an action category ("Media", "Connectivity"...), and "Enabled". nil for an unknown one.
UIImage *RCActionCategoryIcon(NSString *sectionTitle);
