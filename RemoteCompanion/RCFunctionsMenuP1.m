#import "RCFunctionsMenuPrototypeKit.h"
#import "RCFunctionsMenuPrototypeScreens.h"

// ---------------------------------------------------------------------------
// P1. Current - the shipping screen as it is today: a large title, Cancel, the
// search field, one line of text-only chips, then the sections as list rows.
// ---------------------------------------------------------------------------

@interface RCFMP1CurrentScreen : RCFMScreenView
@end

@implementation RCFMP1CurrentScreen

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addHeaderWithTitle:@"Select Action" showsCancel:YES compact:NO];
        [self addSearchFieldWithPlaceholder:@"Search Actions" text:nil large:NO];

        NSMutableArray *chips = [NSMutableArray array];
        RCFMChipView *all = [[RCFMChipView alloc] initWithTitle:@"All" symbol:nil compact:NO];
        all.chosen = YES;
        [chips addObject:all];
        for (NSString *title in RCFMSectionTitles()) {
            [chips addObject:[[RCFMChipView alloc] initWithTitle:title symbol:nil compact:NO]];
        }
        [self addChipRow:chips];

        NSArray<NSString *> *titles = RCFMSectionTitles();
        NSArray<NSArray<NSDictionary *> *> *sections = RCFMSections();
        for (NSUInteger i = 0; i < titles.count; i++) {
            [self addSectionTitle:titles[i]];
            [self addRows:RCFMRowsForActions(sections[i])];
        }
        [self addSpacer:24];
    }
    return self;
}

@end

RCFMScreenView *RCFMMakeP1(void) {
    return [[RCFMP1CurrentScreen alloc] initWithFrame:CGRectZero];
}
