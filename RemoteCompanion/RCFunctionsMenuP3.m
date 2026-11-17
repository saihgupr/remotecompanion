#import "RCFunctionsMenuPrototypeKit.h"
#import "RCFunctionsMenuPrototypeScreens.h"

// ---------------------------------------------------------------------------
// P3. Search first - a large search field at the top, then Recent and Favorites
// as cards, then the usual sections. The chip row stays away until you scroll.
// ---------------------------------------------------------------------------

@interface RCFMP3SearchFirstScreen : RCFMScreenView
@end

@implementation RCFMP3SearchFirstScreen

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addHeaderWithTitle:@"Select Action" showsCancel:YES compact:NO];
        [self addSearchFieldWithPlaceholder:@"Search all actions" text:nil large:YES];

        [self addSectionTitle:@"Recent"];
        [self addRows:RCFMRowsForNames(@[@"Screenshot", @"Set Volume...", @"Play/Pause"])];

        [self addSectionTitle:@"Favorites"];
        [self addRows:RCFMRowsForNames(@[@"Home Assistant: Control Entity...", @"Set Volume...", @"Lock Device"])];

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

RCFMScreenView *RCFMMakeP3(void) {
    return [[RCFMP3SearchFirstScreen alloc] initWithFrame:CGRectZero];
}
