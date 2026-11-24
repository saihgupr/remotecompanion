#import "RCDelayPrototypeKit.h"

// ---------------------------------------------------------------------------
// TEMPORARY DESIGN PROTOTYPE - stepper variations
//
// Five takes on the Stepper delay panel (C). C1 is the original stepper in
// RCDelayPrototypeGalleryViewController; each of these is one file of its own.
// Nothing here is referenced by the shipping Delay flow.
// ---------------------------------------------------------------------------

RCDelayVariantView *RCDelayMakeStepperHold(void);      // C2 hold to repeat
RCDelayVariantView *RCDelayMakeStepperScrub(void);     // C3 drag the number
RCDelayVariantView *RCDelayMakeStepperWheel(void);     // C4 snapping wheel
RCDelayVariantView *RCDelayMakeStepperMultiply(void);  // C5 x2 and /2
RCDelayVariantView *RCDelayMakeStepperPill(void);      // C6 one split pill
