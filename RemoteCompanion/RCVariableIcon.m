#import "RCVariableIcon.h"
#import <CoreText/CoreText.h>

UIImage *RCVariableMenuIconSized(CGFloat side) {
    if (side <= 0) side = 29.0;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format];
    UIImage *rendered = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef ctx = context.CGContext;

        CGFloat fontSize = side * (28.0 / 29.0);
        UIFont *font = [UIFont fontWithName:@"Georgia-BoldItalic" size:fontSize];
        if (!font) {
            UIFontDescriptor *descriptor = [[UIFont systemFontOfSize:fontSize weight:UIFontWeightBold].fontDescriptor
                fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
            font = [UIFont fontWithDescriptor:descriptor size:fontSize] ?: [UIFont boldSystemFontOfSize:fontSize];
        }
        UIColor *orange = [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1.0];
        NSAttributedString *x = [[NSAttributedString alloc] initWithString:@"x" attributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: orange
        }];

        // Center the glyph's own path, not its line box, so the x sits optically centered.
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)x);
        CGRect bounds = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
        CGContextSetTextPosition(ctx,
            (side - CGRectGetWidth(bounds)) / 2.0 - CGRectGetMinX(bounds),
            (side - CGRectGetHeight(bounds)) / 2.0 - CGRectGetMinY(bounds));
        CTLineDraw(line, ctx);
        CFRelease(line);
    }];
    return [rendered imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

UIImage *RCVariableMenuIcon(void) {
    static UIImage *icon;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        icon = RCVariableMenuIconSized(29.0);
    });
    return icon;
}
