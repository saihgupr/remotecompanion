#import "RCFunctionsMenuPrototypeKit.h"
#import "RCFunctionsMenuPrototypeScreens.h"

// ---------------------------------------------------------------------------
// P6. Command palette - one field, one flat ranked list. Each row carries a
// small category tag, and the best match is already highlighted. With the field
// empty this list becomes Recents.
// ---------------------------------------------------------------------------

@interface RCFMP6PaletteScreen : RCFMScreenView
@end

@implementation RCFMP6PaletteScreen

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addHeaderWithTitle:@"Select Action" showsCancel:YES compact:YES];
        [self addSearchFieldWithPlaceholder:@"Search every action" text:@"set" large:YES];

        // A small count above the ranked matches
        UIView *countHolder = [[UIView alloc] init];
        UILabel *count = [[UILabel alloc] init];
        count.text = @"5 results";
        count.font = RCFMFont(UIFontTextStyleCaption1, UIFontWeightRegular);
        count.textColor = [UIColor secondaryLabelColor];
        count.translatesAutoresizingMaskIntoConstraints = NO;
        [countHolder addSubview:count];
        [NSLayoutConstraint activateConstraints:@[
            [count.leadingAnchor constraintEqualToAnchor:countHolder.leadingAnchor constant:20],
            [count.topAnchor constraintEqualToAnchor:countHolder.topAnchor constant:6],
            [count.bottomAnchor constraintEqualToAnchor:countHolder.bottomAnchor constant:-2],
        ]];
        [self.stack addArrangedSubview:countHolder];

        NSArray<NSString *> *names = @[@"Set Volume...", @"Set Brightness...", @"Set Variable...",
                                       @"Set Ringer Volume...", @"Set Focus..."];
        NSArray<NSString *> *tags = @[@"Sound", @"Device", @"Logic", @"Sound", @"Device"];
        NSMutableArray<RCFMRowView *> *rows = [NSMutableArray array];
        for (NSUInteger i = 0; i < names.count; i++) {
            NSDictionary *action = RCFMActionNamed(names[i]);
            if (!action) continue;
            RCFMRowView *row = [[RCFMRowView alloc] initWithAction:action];
            row.categoryTag = tags[i];
            row.opensMore = NO;
            row.topHit = (i == 0);
            [rows addObject:row];
        }
        [self addRows:rows];
        [self addSpacer:24];
    }
    return self;
}

@end

RCFMScreenView *RCFMMakeP6(void) {
    return [[RCFMP6PaletteScreen alloc] initWithFrame:CGRectZero];
}
