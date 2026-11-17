#import <UIKit/UIKit.h>

// ---------------------------------------------------------------------------
// TEMPORARY DESIGN PROTOTYPE - Select Action ("the functions menu")
//
// Shared parts for six takes on the action picker: the page and block colours,
// the search field, the category chips, the list rows and the grid tiles. Every
// font goes through UIFontMetrics, and every colour comes from the app's tweak
// colours or a semantic label colour.
//
// Nothing here is referenced by the shipping picker. RCActionPickerViewController
// is untouched; this is a separate gallery of still screens.
// ---------------------------------------------------------------------------

extern const CGFloat RCFMColumnBreak;

UIColor *RCFMPageColor(void);
UIColor *RCFMBlockColor(void);
UIColor *RCFMBorderColor(void);
UIColor *RCFMSeparatorColor(void);
UIColor *RCFMAccent(void);

CGFloat RCFMBasePointSize(UIFontTextStyle style);
UIFont *RCFMFont(UIFontTextStyle style, UIFontWeight weight);
UIFont *RCFMMonoFont(CGFloat size, UIFontTextStyle style, UIFontWeight weight);

// A representative slice of the real catalog: the same names and SF Symbols as
// RCActionPickerViewController, only a few per section.
NSArray<NSString *> *RCFMSectionTitles(void);
NSArray<NSArray<NSDictionary *> *> *RCFMSections(void);
NSDictionary *RCFMActionNamed(NSString *name);

NSString *RCFMSectionIcon(NSString *title);
NSString *RCFMShortSectionTitle(NSString *title);

#pragma mark - Pieces

@interface RCFMChipView : UIControl
@property (nonatomic, assign, getter=isChosen) BOOL chosen;
@property (nonatomic, assign) BOOL usesAccent;
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol compact:(BOOL)compact;
@end

@interface RCFMSearchFieldView : UIView
- (instancetype)initWithPlaceholder:(NSString *)placeholder text:(NSString *)text large:(BOOL)large;
@end

@interface RCFMRowView : UIView
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *valueText;
@property (nonatomic, copy) NSString *categoryTag;
@property (nonatomic, assign) BOOL opensMore;
@property (nonatomic, assign) BOOL topHit;
- (instancetype)initWithAction:(NSDictionary *)action;
@end

@interface RCFMTileView : UIView
- (instancetype)initWithAction:(NSDictionary *)action;
@end

NSArray<RCFMRowView *> *RCFMRowsForActions(NSArray<NSDictionary *> *actions);
NSArray<RCFMRowView *> *RCFMRowsForNames(NSArray<NSString *> *names);
NSArray<NSArray<RCFMTileView *> *> *RCFMTileRowsForActions(NSArray<NSDictionary *> *actions);

#pragma mark - Screen

// An edge-to-edge vertical screen mock. Add the pieces in order; the stack
// grows to its content and the card clips it like a screenshot.
@interface RCFMScreenView : UIView
@property (nonatomic, strong, readonly) UIStackView *stack;
- (void)addHeaderWithTitle:(NSString *)title showsCancel:(BOOL)showsCancel compact:(BOOL)compact;
- (RCFMSearchFieldView *)addSearchFieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text large:(BOOL)large;
- (void)addChipRow:(NSArray<RCFMChipView *> *)chips;
- (void)addSectionTitle:(NSString *)title;
- (void)addRows:(NSArray<RCFMRowView *> *)rows;
- (void)addTileGrid:(NSArray<NSArray<RCFMTileView *> *> *)grid;
- (void)addSpacer:(CGFloat)height;
@end
