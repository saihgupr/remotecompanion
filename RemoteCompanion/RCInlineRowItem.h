#import <UIKit/UIKit.h>

// Posted with the item as the object whenever an editor changes its value, so a row, a card and
// the sheet in front of it all read the same value.
extern NSString *const RCInlineRowValueChangedNotification;

typedef NS_ENUM(NSInteger, RCInlineRowKind) {
    RCInlineRowKindNumber = 0,
    RCInlineRowKindChoice,
    RCInlineRowKindText,
};

// One action's value, the way a row shows and edits it: a number with its unit, one of a few
// choices, or a line of text. It is also what turns back into a command ("set-vol 40").
@interface RCInlineRowItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, assign) RCInlineRowKind kind;
// The editor's caption, and a number's unit
@property (nonatomic, copy) NSString *caption;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic, assign) BOOL unitNeedsSpace;
@property (nonatomic, assign) double minimumValue;
@property (nonatomic, assign) double maximumValue;
@property (nonatomic, assign) double step;
@property (nonatomic, assign) NSInteger decimals;
// A step of 0.5 needs decimals to be typed and kept
@property (nonatomic, assign) BOOL allowsDecimals;
@property (nonatomic, assign) double numberValue;
// "{name}" instead of a number, like the shipping editor's variable fields
@property (nonatomic, copy) NSString *variableName;
// {round} only has a value inside a Repeat
@property (nonatomic, assign) BOOL allowsRound;
// A choice's options (what the chips read), and the values they stand for in the command
@property (nonatomic, copy) NSArray<NSString *> *options;
@property (nonatomic, copy) NSArray<NSString *> *optionValues;
@property (nonatomic, assign) NSInteger choiceIndex;
// A text value
@property (nonatomic, copy) NSString *textValue;
@property (nonatomic, copy) NSString *placeholder;
// The command the value belongs to ("delay ", "set-vol "), put back in front on save
@property (nonatomic, copy) NSString *prefix;
// For a value that isn't a plain prefix and text ("toast" keeps its subtitle and icon)
@property (nonatomic, copy) NSString *(^commandBuilder)(RCInlineRowItem *item);
- (NSString *)numberText;
- (NSString *)displayValue;
// What the number field reads, and what typing in it sets
- (NSString *)editableNumberText;
- (void)applyEditableNumberText:(NSString *)text;
// The command this value makes, or nil when it isn't one (out of range, unfinished, empty)
- (NSString *)command;
@end

void RCInlineRowNotifyValueChanged(RCInlineRowItem *item);
