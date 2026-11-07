#import <UIKit/UIKit.h>

// The add-ons (ADDONS.md) installed on this device, as the app shows them: action picker
// entries, names and option summaries for actions, Settings > Banners entries and conditions.
@interface RCAddOnCatalog : NSObject

// The valid, installed add-ons, as the tweak loaded them
+ (NSArray<NSDictionary *> *)addOns;

// Whether the tweak's catalog (rc_addons.json) could be read; the lists below are empty until it is
+ (BOOL)catalogAvailable;

// Installed, valid add-ons the user turned off ("addons disable <id>"); they offer nothing
+ (NSArray<NSDictionary *> *)disabledAddOns;

// An add-on by its id, on or off (nil when there's none), and whether it's on
+ (NSDictionary *)addOnWithId:(NSString *)identifier;
+ (BOOL)isAddOnEnabled:(NSString *)identifier;

// The add-on's own icon: an image (nil when it uses a symbol), else its symbol
+ (UIImage *)iconImageForAddOn:(NSDictionary *)addOn;
+ (NSString *)iconForAddOn:(NSDictionary *)addOn;

// A thing's own icon (an action's, trigger's or condition's), else the add-on's
+ (UIImage *)imageForOwnIcon:(NSString *)icon inAddOn:(NSDictionary *)addOn;
+ (NSString *)symbolForOwnIcon:(NSString *)icon inAddOn:(NSDictionary *)addOn;

// Names of add-ons whose app or tweak isn't installed (no "requires" path exists)
+ (NSArray<NSString *> *)absentAddOnNames;

// Whether rc_addon_commands.js (how add-on commands are read) loaded; without it add-on actions
// show no names or options
+ (BOOL)commandsScriptLoaded;

// Files with a problem, each "file.json: reason"
+ (NSArray<NSString *> *)problems;

// A symbol name this iOS has, else nil (an unknown name shows no icon; many are iOS 15+)
+ (NSString *)availableSymbol:(NSString *)name;

// The icon for add-on things without one of their own: the puzzle piece (iOS 14's form there)
+ (NSString *)defaultSymbol;

// The Darwin notification the tweak posts each time the add-ons change
+ (const char *)changedNotification;

// Action picker sections, one per add-on: { title: add-on name, actions: [entries as below] }
+ (NSArray<NSDictionary *> *)pickerSections;

// The add-on named name's icon (an SF Symbol; the puzzle piece when it has none)
+ (NSString *)iconForAddOnNamed:(NSString *)name;

// The image of an add-on action command's icon (its own, or the add-on's), or nil when it is a symbol
+ (UIImage *)imageForCommand:(NSString *)command;

// The image of an add-on trigger key's icon, or nil
+ (UIImage *)imageForTriggerKey:(NSString *)key;

// The add-on named name's image icon (a png or jpg its icon names), or nil
+ (UIImage *)iconImageForAddOnNamed:(NSString *)name;

// The picker's Add-ons rows, one per add-on: { name, command: "__ADDON__<id>", icon, image (a UIImage or NSNull), count }
+ (NSArray<NSDictionary *> *)addOnRows;

// An add-on's picker entries (as pickerSections gives them, plus shortName without the add-on's name)
+ (NSArray<NSDictionary *> *)actionsForAddOn:(NSString *)identifier;

// Action picker entries: { name: "Add-on: Action", command: "<id> <action>", icon }
+ (NSArray<NSDictionary *> *)pickerActions;

// "Add-on: Action" for an add-on command (with or without options), or nil
+ (NSString *)nameForCommand:(NSString *)command;

// The action's icon for an add-on command, or nil
+ (NSString *)iconForCommand:(NSString *)command;

// The chosen options and input ("Back · 4K"), or nil when there are none
+ (NSString *)summaryForCommand:(NSString *)command;

// Whether picking the action asks for options or input first
+ (BOOL)commandAsksForDetails:(NSString *)command;

// The action option's choice that appears in words (a choice's word, any case), or nil
+ (NSDictionary *)choiceForOption:(NSDictionary *)option inWords:(NSArray<NSString *> *)words;

// The words that are the action's free-text field rather than a choice, joined, or nil
+ (NSString *)inputInWords:(NSArray<NSString *> *)words action:(NSDictionary *)action;

// The words after an action's own, as the tweak reads them: choice words first (at most one per
// option), then the input, which starts at the first other word or after "--".
// { "choices": { option id: choice }, "input": text (absent when there's none) }
+ (NSDictionary *)splitWords:(NSArray<NSString *> *)words action:(NSDictionary *)action;

// Typed input as it goes in a command: "--" in front when it starts with a choice word (or "--"),
// so it's read as text. nil when empty.
+ (NSString *)wordsForInput:(NSString *)input action:(NSDictionary *)action;

// Opens a screen with the action's options (each with Keep Current) and field, then calls completion with
// the full command. current: the command being edited, whose choices are ticked; may be nil.
// Not called when cancelled.
+ (void)presentDetailsFrom:(UIViewController *)controller command:(NSString *)command current:(NSString *)current completion:(void (^)(NSString *command))completion;

// Settings > Banners entries for actions with a banner: { id: "<id> <action>", name, icon }
+ (NSArray<NSDictionary *> *)bannerItems;

// Triggers from add-on events: { key: "addon_<id>_<trigger>[_<state>]", name, icon, image (UIImage, if its icon is an image), section: add-on name }.
// One for the event, and one for each state its banner names.
+ (NSArray<NSDictionary *> *)triggerEvents;

// A trigger key's name as the add-on words it ("Add-on: Trigger (State)"), or nil
+ (NSString *)nameForTriggerKey:(NSString *)key;

// Whether a trigger key is an add-on's (addon_...)
+ (BOOL)isAddOnTriggerKey:(NSString *)key;

// The triggers add-ons offer, one group per add-on:
// { id, title, icon, image (UIImage or NSNull), triggers: [ { key, title, name, states: [ { key, label, name } ] } ] }
+ (NSArray<NSDictionary *> *)addOnTriggerGroups;

// The icon for an add-on trigger key, or nil
+ (NSString *)iconForTriggerKey:(NSString *)key;

// Conditions: { key: "add-on:<id>:<condition>", name, type: "number"|"choice", choices: [labels] }
+ (NSArray<NSDictionary *> *)conditions;

@end
