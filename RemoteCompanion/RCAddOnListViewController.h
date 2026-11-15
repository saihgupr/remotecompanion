#import <UIKit/UIKit.h>

// A list setting's page (an add-on setting of type "list"): its items, each one opening an editor
// with a control per field; Add, swipe to delete, and Edit to reorder. Every change is saved at
// once with "addons set <id> <setting> <JSON>".
@interface RCAddOnListViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

- (instancetype)initWithAddOnId:(NSString *)addOnId setting:(NSDictionary *)setting items:(NSArray *)items;

@end

// How setting values read on the add-on's pages
@interface RCAddOnSettingText : NSObject

// A number as written ("80", "0.5"), with the control's unit
+ (NSString *)textForNumber:(id)value control:(NSDictionary *)control;
// A field's value: On or Off, a choice's label, a number with its unit, or text
+ (NSString *)textForValue:(id)value control:(NSDictionary *)control;
// A list's items in one line: each item's first field
+ (NSString *)summaryForItems:(NSArray *)items setting:(NSDictionary *)setting;
// A typed number as a command takes it (a decimal comma becomes a point); nil if it isn't one
+ (NSString *)numberForTyped:(NSString *)typed;
// A text control's names to pick from: its suggestionsFile (read now), then its suggestions;
// empty when it has neither
+ (NSArray<NSString *> *)suggestionsForControl:(NSDictionary *)control;

@end

// Picks a name for a text setting or field: the suggestions with a search field, and "Use '...'"
// for typed text that isn't one of them. completion gets the text, then the screen closes.
@interface RCAddOnSuggestionsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>

- (instancetype)initWithTitle:(NSString *)title suggestions:(NSArray<NSString *> *)suggestions current:(NSString *)current completion:(void (^)(NSString *text))completion;

@end
