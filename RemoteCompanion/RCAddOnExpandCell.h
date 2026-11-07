#import <UIKit/UIKit.h>

extern const CGFloat RCAddOnHeaderHeight;   // the row's title line
extern const CGFloat RCAddOnChoiceHeight;   // each choice under it

// A row for a screen of add-on settings: a title, a value and an arrow, and below them a list of
// choices that opens and folds as the row grows (Auto Layout inside, exact heights set by the table).
// The table never inserts or removes rows, so nothing overlaps while it animates.
@interface RCAddOnExpandCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIImageView *chevron;
@property (nonatomic, strong) UIStackView *choicesStack;
@property (nonatomic, strong) NSLayoutConstraint *clipHeight;
@property (nonatomic, copy) NSArray<NSDictionary *> *choices;       // { label, word }
@property (nonatomic, copy) void (^onToggle)(void);
@property (nonatomic, copy) void (^onChoose)(NSString *word);
// One choice carries the check
- (void)setChoices:(NSArray<NSDictionary *> *)choices selectedWord:(NSString *)word;
// Several carry it (words already added)
- (void)setChoices:(NSArray<NSDictionary *> *)choices checkedWords:(NSSet<NSString *> *)words;
// Call inside an animation to open or fold the choices
- (void)setExpanded:(BOOL)expanded;
@end
