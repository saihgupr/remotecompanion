#import "RCAddOnExpandCell.h"
#import "RCConfigManager.h"

const CGFloat RCAddOnHeaderHeight = 52.0;
const CGFloat RCAddOnChoiceHeight = 46.0;
#define kHeaderHeight RCAddOnHeaderHeight
#define kChoiceHeight RCAddOnChoiceHeight

// One option as a single row: its title, the chosen value and an arrow, and below them its
// choices (Keep Current first), which show or hide as the row resizes itself with Auto Layout.
// The table never inserts or removes rows, so nothing overlaps while it animates.


@implementation RCAddOnExpandCell

- (instancetype)init {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if (self) {
        RCConfigManager *cm = [RCConfigManager sharedManager];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
        self.contentView.clipsToBounds = YES;

        UIView *header = [[UIView alloc] init];
        header.translatesAutoresizingMaskIntoConstraints = NO;
        [header addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headerTapped)]];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:17];
        _titleLabel.textColor = [UIColor labelColor];
        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = [UIFont systemFontOfSize:17];
        _valueLabel.textColor = [UIColor secondaryLabelColor];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_valueLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
        _chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"
                                                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold]]];
        _chevron.tintColor = [UIColor tertiaryLabelColor];
        for (UIView *v in @[_titleLabel, _valueLabel, _chevron]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [header addSubview:v];
        }

        // The choices sit in a clipped box whose height changes, so they stay visible while the row
        // grows or shrinks around them (hiding them would make them vanish at once)
        _choicesStack = [[UIStackView alloc] init];
        _choicesStack.axis = UILayoutConstraintAxisVertical;
        _choicesStack.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *clip = [[UIView alloc] init];
        clip.clipsToBounds = YES;
        [clip addSubview:_choicesStack];
        _clipHeight = [clip.heightAnchor constraintEqualToConstant:0];
        _clipHeight.priority = 999;

        UIStackView *root = [[UIStackView alloc] initWithArrangedSubviews:@[header, clip]];
        root.axis = UILayoutConstraintAxisVertical;
        root.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:root];

        NSLayoutConstraint *headerHeight = [header.heightAnchor constraintEqualToConstant:kHeaderHeight];
        headerHeight.priority = 999;   // a hidden option's row is 0 high
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [root.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [root.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [root.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            headerHeight, _clipHeight,
            [_choicesStack.topAnchor constraintEqualToAnchor:clip.topAnchor],
            [_choicesStack.leadingAnchor constraintEqualToAnchor:clip.leadingAnchor],
            [_choicesStack.trailingAnchor constraintEqualToAnchor:clip.trailingAnchor],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [_chevron.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_chevron.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:_chevron.leadingAnchor constant:-10],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_valueLabel.leadingAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)headerTapped { if (self.onToggle) self.onToggle(); }

- (void)choiceTapped:(UITapGestureRecognizer *)tap {
    NSUInteger index = (NSUInteger)tap.view.tag;
    if (index < self.choices.count && self.onChoose) self.onChoose(self.choices[index][@"word"] ?: @"");
}

- (void)setChoices:(NSArray<NSDictionary *> *)choices selectedWord:(NSString *)word {
    if (![choices isEqualToArray:_choices]) {
        _choices = [choices copy];
        for (UIView *row in self.choicesStack.arrangedSubviews) { [self.choicesStack removeArrangedSubview:row]; [row removeFromSuperview]; }
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        for (NSUInteger i = 0; i < choices.count; i++) {
            UIView *row = [[UIView alloc] init];
            row.tag = (NSInteger)i;
            row.translatesAutoresizingMaskIntoConstraints = NO;
            UILabel *label = [[UILabel alloc] init];
            label.text = choices[i][@"label"] ?: choices[i][@"word"];
            label.textColor = [UIColor labelColor];
            label.font = [UIFont systemFontOfSize:16];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"
                                                                            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]];
            check.tintColor = [UIColor systemBlueColor];
            check.tag = 100;   // not a row index: viewWithTag also matches the row itself
            check.translatesAutoresizingMaskIntoConstraints = NO;
            UIView *line = [[UIView alloc] init];
            line.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"separators" defaultVal:0.30];
            line.translatesAutoresizingMaskIntoConstraints = NO;
            [row addSubview:label];
            [row addSubview:check];
            [row addSubview:line];
            [row addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(choiceTapped:)]];
            [self.choicesStack addArrangedSubview:row];
            NSLayoutConstraint *height = [row.heightAnchor constraintEqualToConstant:kChoiceHeight];
            height.priority = 999;
            [NSLayoutConstraint activateConstraints:@[
                height,
                [line.topAnchor constraintEqualToAnchor:row.topAnchor],
                [line.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
                [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
                [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
                [label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor constant:18],
                [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
                [label.trailingAnchor constraintLessThanOrEqualToAnchor:check.leadingAnchor constant:-8],
                [check.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
                [check.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            ]];
        }
    }
    [self applyChecks:^BOOL(NSString *candidate) { return [candidate.lowercaseString isEqualToString:(word ?: @"").lowercaseString]; }];
}

- (void)setChoices:(NSArray<NSDictionary *> *)choices checkedWords:(NSSet<NSString *> *)words {
    [self setChoices:choices selectedWord:nil];
    [self applyChecks:^BOOL(NSString *candidate) { return [words containsObject:candidate]; }];
}

- (void)applyChecks:(BOOL (^)(NSString *word))isChecked {
    for (UIView *row in self.choicesStack.arrangedSubviews) {
        NSUInteger i = (NSUInteger)row.tag;
        [row viewWithTag:100].hidden = !isChecked(self.choices[i][@"word"] ?: @"");
    }
}

// Call inside an animation (the table's batch update) to open or fold the choices
- (void)setExpanded:(BOOL)expanded {
    self.clipHeight.constant = expanded ? self.choices.count * kChoiceHeight : 0;
    self.chevron.transform = expanded ? CGAffineTransformMakeRotation((CGFloat)M_PI_2) : CGAffineTransformIdentity;
}

@end

