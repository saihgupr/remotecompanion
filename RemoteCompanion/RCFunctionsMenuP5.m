#import "RCFunctionsMenuPrototypeKit.h"
#import "RCFunctionsMenuPrototypeScreens.h"

// ---------------------------------------------------------------------------
// P5. Large grid - two-column tiles with the icon, the name and a one-line
// subtitle, grouped under the category headers. No List / Compact switch.
// ---------------------------------------------------------------------------

@interface RCFMP5GridScreen : RCFMScreenView
@end

@implementation RCFMP5GridScreen

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addHeaderWithTitle:@"Select Action" showsCancel:YES compact:NO];
        [self addSearchFieldWithPlaceholder:@"Search Actions" text:nil large:NO];

        NSArray<NSString *> *titles = RCFMSectionTitles();
        NSArray<NSArray<NSDictionary *> *> *sections = RCFMSections();
        for (NSUInteger i = 0; i < titles.count; i++) {
            [self addSectionTitle:titles[i]];
            [self addTileGrid:RCFMTileRowsForActions(sections[i])];
        }
        [self addSpacer:24];
    }
    return self;
}

@end

RCFMScreenView *RCFMMakeP5(void) {
    return [[RCFMP5GridScreen alloc] initWithFrame:CGRectZero];
}
