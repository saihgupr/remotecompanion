#import "RCFunctionsMenuPrototypeKit.h"
#import "RCFunctionsMenuPrototypeScreens.h"

// ---------------------------------------------------------------------------
// P4. Rows with values - the list rows carry the action's current setting on
// the right, so a glance down the list tells you what each step will do.
// Compact chrome leaves the room for it.
// ---------------------------------------------------------------------------

@interface RCFMP4ValuesScreen : RCFMScreenView
@end

@implementation RCFMP4ValuesScreen

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addHeaderWithTitle:@"Select Action" showsCancel:YES compact:YES];
        [self addSearchFieldWithPlaceholder:@"Search Actions" text:nil large:NO];

        NSMutableArray *chips = [NSMutableArray array];
        RCFMChipView *all = [[RCFMChipView alloc] initWithTitle:@"All" symbol:nil compact:YES];
        all.chosen = YES;
        [chips addObject:all];
        for (NSString *title in RCFMSectionTitles()) {
            [chips addObject:[[RCFMChipView alloc] initWithTitle:title symbol:nil compact:YES]];
        }
        [self addChipRow:chips];

        // The settings a row would show: the current volume, the default timer,
        // the app that was picked last time.
        NSDictionary<NSString *, NSString *> *values = @{
            @"Set Volume...": @"40%",
            @"Set Ringer Volume...": @"70%",
            @"Open App...": @"AudioStream",
            @"Set Brightness...": @"60%",
            @"Timer...": @"10 min",
            @"Home Assistant: Control Entity...": @"Desk Lamp",
            @"Delay": @"2s",
            @"If Condition...": @"Battery > 20%",
        };

        NSArray<NSString *> *titles = RCFMSectionTitles();
        NSArray<NSArray<NSDictionary *> *> *sections = RCFMSections();
        for (NSUInteger i = 0; i < titles.count; i++) {
            [self addSectionTitle:titles[i]];
            NSArray<RCFMRowView *> *rows = RCFMRowsForActions(sections[i]);
            for (RCFMRowView *row in rows) {
                NSString *value = values[row.name];
                if (value.length) {
                    row.valueText = value;
                    row.opensMore = NO;
                }
            }
            [self addRows:rows];
        }
        [self addSpacer:24];
    }
    return self;
}

@end

RCFMScreenView *RCFMMakeP4(void) {
    return [[RCFMP4ValuesScreen alloc] initWithFrame:CGRectZero];
}
