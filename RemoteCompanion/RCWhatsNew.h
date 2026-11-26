#import <UIKit/UIKit.h>

// What's New: a card on the first launch after an update, listing that version's new features (and,
// on a first install, a welcome on the same card instead). New Trigger and Select Action show the
// version's new triggers and actions in a "New" section at the top until each is used or dismissed.
// The text, icons and lists all live in RCWhatsNew.m, one entry per version.
@interface RCWhatsNew : NSObject

// At launch: the card for this version once (Welcome on a first install), nothing otherwise
+ (void)showIfNeededFrom:(UIViewController *)host;
// This version's card again (the row at the top of Settings); NO when it has none
+ (BOOL)hasWhatsNew;
// "What's New in 4.6"
+ (NSString *)whatsNewTitle;
+ (void)showWhatsNewFrom:(UIViewController *)host;

// "New" in New Trigger: a built-in trigger by its key, any other kind by its menu title
+ (BOOL)isNewTrigger:(NSString *)itemId;
// "New" in Select Action: an action by its command
+ (BOOL)isNewAction:(NSString *)command;
// Used or dismissed: back to its usual place only
+ (void)dismissTrigger:(NSString *)itemId;
+ (void)dismissAction:(NSString *)command;
+ (void)dismissTriggers:(NSArray<NSString *> *)itemIds;
+ (void)dismissActions:(NSArray<NSString *> *)commands;

// What's New marks: a "NEW" capsule tight on a tile's top right corner; a red dot on a
// list row's icon, at its top right corner
+ (UILabel *)newTag;
+ (UIView *)newDot;
+ (void)pinTag:(UIView *)tag toCornerOf:(UIView *)tile in:(UIView *)container;
// A mark at an icon's top right corner: placed now (frames), or held there (constraints)
+ (void)placeTag:(UIView *)tag onIcon:(UIView *)icon;
+ (void)pinTag:(UIView *)tag toIcon:(UIView *)icon in:(UIView *)container;

@end

// Posted when items are dismissed, so an open picker can drop them from its New section
extern NSString *const RCWhatsNewDismissedNotification;
