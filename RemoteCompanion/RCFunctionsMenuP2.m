#import "RCFunctionsMenuPrototypeKit.h"
#import "RCFunctionsMenuPrototypeScreens.h"

// ---------------------------------------------------------------------------
// P2. Icon chips - the same screen, with a symbol on every category chip. The
// chips are a little tighter, and the chosen one is filled with the accent.
// ---------------------------------------------------------------------------

@interface RCFMP2IconChipsScreen : RCFMScreenView
@end

@implementation RCFMP2IconChipsScreen

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addHeaderWithTitle:@"Select Action" showsCancel:YES compact:NO];
        [self addSearchFieldWithPlaceholder:@"Search Actions" text:nil large:NO];

        NSMutableArray *chips = [NSMutableArray array];
        RCFMChipView *all = [[RCFMChipView alloc] initWithTitle:@"All" symbol:@"square.grid.2x2.fill" compact:YES];
        all.usesAccent = YES;
        all.chosen = YES;
        [chips addObject:all];
        for (NSString *title in RCFMSectionTitles()) {
            RCFMChipView *chip = [[RCFMChipView alloc] initWithTitle:title symbol:RCFMSectionIcon(title) compact:YES];
            chip.usesAccent = YES;
            [chips addObject:chip];
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

RCFMScreenView *RCFMMakeP2(void) {
    return [[RCFMP2IconChipsScreen alloc] initWithFrame:CGRectZero];
}
