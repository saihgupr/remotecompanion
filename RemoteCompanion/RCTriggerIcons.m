#import "RCTriggerIcons.h"

// Most button and gesture triggers are drawn as a tiny phone: the button that's pressed (on the
// phone's side, or its Home button), or the part of the screen that's touched, with a dot where
// a finger holds or an arrow for a swipe, and what happens inside the screen (2×, a clock for a
// hold, + for two buttons together, arrows for one button then the other).
//   buttons: volUp, volDown, power, ringer      home: a Home button
//   zone: top, bottom, left, right               dot: L, C, R (in the top zone)
//   arrow: left, right, up, down (in the zone)   arrowAt: L, C, R (a swipe up from the bottom)
//   mark: @"2×" (text), @"sym:clock" (a symbol), @"arrows:up,down"
//   symbol: a plain symbol instead of the phone (Touch ID), with a mark as a small badge
static NSDictionary<NSString *, NSDictionary *> *RCPhoneIconSpecs(void) {
    static NSDictionary *specs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *hold = @"sym:clock";
        specs = @{
            @"volume_up_hold":          @{ @"buttons": @[@"volUp"], @"mark": hold },
            @"volume_down_hold":        @{ @"buttons": @[@"volDown"], @"mark": hold },
            @"volume_both_press":       @{ @"buttons": @[@"volUp", @"volDown"], @"mark": @"+" },
            @"volume_up_then_down":     @{ @"buttons": @[@"volUp", @"volDown"], @"mark": @"arrows:up,down" },
            @"volume_down_then_up":     @{ @"buttons": @[@"volUp", @"volDown"], @"mark": @"arrows:down,up" },
            @"power_double_tap":        @{ @"buttons": @[@"power"], @"mark": @"2×" },
            @"power_triple_click":      @{ @"buttons": @[@"power"], @"mark": @"3×" },
            @"power_quadruple_click":   @{ @"buttons": @[@"power"], @"mark": @"4×" },
            @"power_volume_up":         @{ @"buttons": @[@"power", @"volUp"], @"mark": @"+" },
            @"power_volume_down":       @{ @"buttons": @[@"power", @"volDown"], @"mark": @"+" },
            @"power_long_press":        @{ @"buttons": @[@"power"], @"mark": hold },
            @"trigger_statusbar_left_hold":   @{ @"zone": @"top", @"dot": @"L" },
            @"trigger_statusbar_center_hold": @{ @"zone": @"top", @"dot": @"C" },
            @"trigger_statusbar_right_hold":  @{ @"zone": @"top", @"dot": @"R" },
            @"trigger_statusbar_swipe_left":  @{ @"zone": @"top", @"arrow": @"left" },
            @"trigger_statusbar_swipe_right": @{ @"zone": @"top", @"arrow": @"right" },
            @"trigger_statusbar_double_tap":  @{ @"zone": @"top", @"mark": @"2×" },
            @"trigger_edge_left_swipe_up":    @{ @"zone": @"left", @"arrow": @"up" },
            @"trigger_edge_left_swipe_down":  @{ @"zone": @"left", @"arrow": @"down" },
            @"trigger_edge_right_swipe_up":   @{ @"zone": @"right", @"arrow": @"up" },
            @"trigger_edge_right_swipe_down": @{ @"zone": @"right", @"arrow": @"down" },
            @"trigger_bottombar_swipe_left":  @{ @"zone": @"bottom", @"arrow": @"left" },
            @"trigger_bottombar_swipe_right": @{ @"zone": @"bottom", @"arrow": @"right" },
            @"trigger_bottom_swipe_up_left":   @{ @"arrowAt": @"L" },
            @"trigger_bottom_swipe_up_center": @{ @"arrowAt": @"C" },
            @"trigger_bottom_swipe_up_right":  @{ @"arrowAt": @"R" },
            @"trigger_home_double_click":    @{ @"home": @YES, @"mark": @"2×" },
            @"trigger_home_triple_click":    @{ @"home": @YES, @"mark": @"3×" },
            @"trigger_home_quadruple_click": @{ @"home": @YES, @"mark": @"4×" },
            @"trigger_home_hold":            @{ @"home": @YES, @"mark": hold },
            @"trigger_home_power":           @{ @"home": @YES, @"buttons": @[@"power"], @"mark": @"+" },
            @"shake":                        @{ @"shake": @YES },
            @"touchid_tap":                  @{ @"symbol": @"touchid" },
            @"touchid_hold":                 @{ @"symbol": @"touchid", @"mark": hold },
            @"trigger_ringer_mute":          @{ @"buttons": @[@"ringer"], @"mark": @"sym:bell.slash.fill" },
            @"trigger_ringer_unmute":        @{ @"buttons": @[@"ringer"], @"mark": @"sym:bell.fill" },
            @"trigger_ringer_toggle":        @{ @"buttons": @[@"ringer"], @"mark": @"sym:arrow.up.arrow.down" },
            // No phone button: the watch (tall like the phone, so it's as big), with a clock for a hold
            @"trigger_watch_ping":           @{ @"symbol": @"applewatch", @"tall": @YES },
            @"trigger_watch_ping_hold":      @{ @"symbol": @"applewatch", @"tall": @YES, @"mark": hold },
        };
    });
    return specs;
}

static UIImage *RCSymbol(NSString *name, CGFloat size, UIImageSymbolWeight weight) {
    if (!name.length) return nil;
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
    return [image imageWithTintColor:[UIColor blackColor]];
}

// Draws an image fitted into a box, centred
static void RCDrawFitted(UIImage *image, CGRect box, CGBlendMode mode) {
    CGSize size = image.size;
    if (size.width <= 0 || size.height <= 0) return;
    CGFloat scale = MIN(1.0, MIN(box.size.width / size.width, box.size.height / size.height));
    CGSize drawn = CGSizeMake(size.width * scale, size.height * scale);
    [image drawInRect:CGRectMake(CGRectGetMidX(box) - drawn.width / 2, CGRectGetMidY(box) - drawn.height / 2, drawn.width, drawn.height) blendMode:mode alpha:1];
}

static void RCDrawText(NSString *text, CGRect box, CGFloat size) {
    NSDictionary *attributes = @{ NSFontAttributeName: [UIFont systemFontOfSize:size weight:UIFontWeightHeavy], NSForegroundColorAttributeName: [UIColor blackColor] };
    CGSize textSize = [text sizeWithAttributes:attributes];
    [text drawAtPoint:CGPointMake(CGRectGetMidX(box) - textSize.width / 2, CGRectGetMidY(box) - textSize.height / 2) withAttributes:attributes];
}

static UIImage *RCDrawPhoneIcon(NSDictionary *spec, CGFloat side) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        CGFloat k = side / 40.0;
        // A rect in the 40 × 40 drawing
        CGRect (^R)(CGFloat, CGFloat, CGFloat, CGFloat) = ^CGRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
            return CGRectMake(x * k, y * k, w * k, h * k);
        };
        UIColor *ink = [UIColor blackColor];
        [ink setFill];
        [ink setStroke];
        NSString *mark = spec[@"mark"];

        // A plain symbol, with its mark as a badge at the bottom right
        NSString *symbol = spec[@"symbol"];
        if (symbol) {
            // A tall symbol fills the height the phone does
            BOOL tall = [spec[@"tall"] boolValue];
            BOOL press = [spec[@"press"] boolValue];
            UIImage *image = RCSymbol(symbol, (tall ? 34 : 26) * k, UIImageSymbolWeightRegular) ?: RCSymbol(spec[@"fallback"], 26 * k, UIImageSymbolWeightRegular);
            RCDrawFitted(image, tall ? R(4, 1, 30, 38) : (press ? R(1, 1, 30, 30) : R(3, 3, 32, 32)), kCGBlendModeNormal);
            NSString *letter = spec[@"letter"];
            if (press) {
                // A finger pressing it at the bottom right, set off from the symbol by a thin gap
                UIImage *finger = RCSymbol(@"hand.point.up.left.fill", 17 * k, UIImageSymbolWeightRegular);
                CGRect box = R(20, 17, 19, 22);
                for (NSInteger dx = -1; dx <= 1; dx++) {
                    for (NSInteger dy = -1; dy <= 1; dy++) {
                        RCDrawFitted(finger, CGRectOffset(box, dx * 1.6 * k, dy * 1.6 * k), kCGBlendModeDestinationOut);
                    }
                }
                RCDrawFitted(finger, box, kCGBlendModeNormal);
            } else if (letter.length) {
                CGContextSetBlendMode(context, kCGBlendModeClear);
                CGContextFillEllipseInRect(context, R(23, 23, 17, 17));
                CGContextSetBlendMode(context, kCGBlendModeNormal);
                CGContextFillEllipseInRect(context, R(24.5, 24.5, 14, 14));
                CGContextSetBlendMode(context, kCGBlendModeClear);
                RCDrawText(letter, R(24.5, 24.5, 14, 14), 9.5 * k);
                CGContextSetBlendMode(context, kCGBlendModeNormal);
            } else if ([mark hasPrefix:@"sym:"]) {
                CGContextSetBlendMode(context, kCGBlendModeClear);
                CGContextFillEllipseInRect(context, R(24, 24, 16, 16));
                CGContextSetBlendMode(context, kCGBlendModeNormal);
                CGContextFillEllipseInRect(context, R(25.5, 25.5, 13, 13));
                RCDrawFitted(RCSymbol([mark substringFromIndex:4], 8.5 * k, UIImageSymbolWeightBold), R(27.5, 27.5, 9, 9), kCGBlendModeDestinationOut);
            }
            return;
        }

        // Shake: the phone (as big as the others), with motion lines just outside it
        if ([spec[@"shake"] boolValue]) {
            UIBezierPath *phone = [UIBezierPath bezierPathWithRoundedRect:R(9, 1, 22, 38) cornerRadius:5 * k];
            phone.lineWidth = 2.4 * k;
            [phone stroke];
            for (NSNumber *side in @[@-1, @1]) {
                for (NSNumber *step in @[@0, @1]) {
                    CGFloat x = 20 + side.doubleValue * (14.5 + step.doubleValue * 4);
                    UIBezierPath *line = [UIBezierPath bezierPath];
                    line.lineWidth = 2 * k;
                    line.lineCapStyle = kCGLineCapRound;
                    CGFloat half = 5 - step.doubleValue * 1.2;
                    // A slight curve, bowing away from the phone
                    [line moveToPoint:CGPointMake((x - side.doubleValue * 1.2) * k, (20 - half) * k)];
                    [line addQuadCurveToPoint:CGPointMake((x - side.doubleValue * 1.2) * k, (20 + half) * k)
                                 controlPoint:CGPointMake((x + side.doubleValue * 1.8) * k, 20 * k)];
                    [line stroke];
                }
            }
            return;
        }

        // The phone
        UIBezierPath *outline = [UIBezierPath bezierPathWithRoundedRect:R(9, 1, 22, 38) cornerRadius:5 * k];
        outline.lineWidth = 2.4 * k;
        [outline stroke];
        for (NSString *button in spec[@"buttons"]) {
            CGRect r = CGRectZero;
            if ([button isEqualToString:@"ringer"]) r = R(5, 5, 3.4, 5);
            else if ([button isEqualToString:@"volUp"]) r = R(5, 12, 3.4, 7);
            else if ([button isEqualToString:@"volDown"]) r = R(5, 21, 3.4, 7);
            else if ([button isEqualToString:@"power"]) r = R(31.6, 11, 3.4, 10);
            [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:1.4 * k] fill];
        }
        BOOL home = [spec[@"home"] boolValue];
        if (home) {
            UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:R(16, 29.5, 8, 8)];
            ring.lineWidth = 2.2 * k;
            [ring stroke];
        }

        // The part of the screen that's touched
        NSString *zone = spec[@"zone"];
        CGRect zoneRect = CGRectZero;
        if ([zone isEqualToString:@"top"]) zoneRect = R(11, 3, 18, 8);
        else if ([zone isEqualToString:@"bottom"]) zoneRect = R(11, 29, 18, 8);
        else if ([zone isEqualToString:@"left"]) zoneRect = R(11, 3, 7, 34);
        else if ([zone isEqualToString:@"right"]) zoneRect = R(22, 3, 7, 34);
        if (zone) {
            [[ink colorWithAlphaComponent:0.42] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:zoneRect cornerRadius:3 * k] fill];
            [ink setFill];
        }
        NSString *dot = spec[@"dot"];
        if (dot) {
            CGFloat x = [dot isEqualToString:@"L"] ? 12 : [dot isEqualToString:@"C"] ? 17 : 22;
            CGContextFillEllipseInRect(context, R(x, 4, 6, 6));
        }
        NSString *arrow = spec[@"arrow"];
        if (arrow && zone) {
            BOOL side = [zone isEqualToString:@"left"] || [zone isEqualToString:@"right"];
            CGRect r = side ? CGRectInset(zoneRect, 0, 6 * k) : zoneRect;
            RCDrawFitted(RCSymbol([@"arrow." stringByAppendingString:arrow], (side ? 14 : 12) * k, UIImageSymbolWeightBlack), r, kCGBlendModeNormal);
        }
        NSString *arrowAt = spec[@"arrowAt"];
        if (arrowAt) {
            CGFloat x = [arrowAt isEqualToString:@"L"] ? 11 : [arrowAt isEqualToString:@"C"] ? 16 : 21;
            RCDrawFitted(RCSymbol(@"arrow.up", 14 * k, UIImageSymbolWeightBlack), R(x, 18, 8, 16), kCGBlendModeNormal);
            [[UIBezierPath bezierPathWithRoundedRect:R(14, 35, 12, 1.8) cornerRadius:0.9 * k] fill];   // the home bar
        }

        // What happens, inside the screen
        if (!mark) return;
        CGRect inside = home ? R(11, 7, 18, 20) : [zone isEqualToString:@"top"] ? R(11, 13, 18, 20) : R(11, 9, 18, 22);
        if ([mark hasPrefix:@"sym:"]) {
            RCDrawFitted(RCSymbol([mark substringFromIndex:4], 12 * k, UIImageSymbolWeightBold), inside, kCGBlendModeNormal);
        } else if ([mark hasPrefix:@"arrows:"]) {
            NSArray *names = [[mark substringFromIndex:7] componentsSeparatedByString:@","];
            CGFloat half = inside.size.height / 2;
            RCDrawFitted(RCSymbol([@"arrow." stringByAppendingString:names.firstObject], 10 * k, UIImageSymbolWeightBlack),
                         CGRectMake(inside.origin.x, inside.origin.y, inside.size.width, half), kCGBlendModeNormal);
            RCDrawFitted(RCSymbol([@"arrow." stringByAppendingString:names.lastObject], 10 * k, UIImageSymbolWeightBlack),
                         CGRectMake(inside.origin.x, inside.origin.y + half, inside.size.width, half), kCGBlendModeNormal);
        } else {
            RCDrawText(mark, inside, 11 * k);
        }
    }];
}

static NSCache *RCIconCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    return cache;
}

UIImage *RCTriggerIconImage(NSString *triggerKey, CGFloat pointSize) {
    NSDictionary *spec = RCPhoneIconSpecs()[triggerKey ?: @""];
    // A Notification Tap trigger: a finger pressing a bell (all alike, so one cached drawing)
    if ([triggerKey hasPrefix:@"notiftap_"]) {
        triggerKey = @"notiftap_";
        spec = @{ @"symbol": @"bell.fill", @"press": @YES };
    }
    if (!spec) return nil;
    NSString *cacheKey = [NSString stringWithFormat:@"%@@%.1f", triggerKey, pointSize];
    UIImage *cached = [RCIconCache() objectForKey:cacheKey];
    if (cached) return cached;
    UIImage *icon = [RCDrawPhoneIcon(spec, ceil(pointSize * 1.45)) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [RCIconCache() setObject:icon forKey:cacheKey];
    return icon;
}

UIImage *RCTriggerLetterImage(NSString *symbolName, NSString *letter, CGFloat pointSize) {
    if (!letter.length) return RCTriggerSymbolImage(symbolName, pointSize);
    if (!symbolName.length) return nil;
    NSString *cacheKey = [NSString stringWithFormat:@"letter:%@:%@@%.1f", symbolName, letter, pointSize];
    UIImage *cached = [RCIconCache() objectForKey:cacheKey];
    if (cached) return cached;
    UIImage *icon = [RCDrawPhoneIcon(@{ @"symbol": symbolName, @"letter": letter }, ceil(pointSize * 1.45)) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [RCIconCache() setObject:icon forKey:cacheKey];
    return icon;
}

UIImage *RCTriggerSymbolImage(NSString *symbolName, CGFloat pointSize) {
    if (!symbolName.length) return nil;
    NSString *cacheKey = [NSString stringWithFormat:@"symbol:%@@%.1f", symbolName, pointSize];
    UIImage *cached = [RCIconCache() objectForKey:cacheKey];
    if (cached) return cached;
    UIImage *icon = [RCDrawPhoneIcon(@{ @"symbol": symbolName }, ceil(pointSize * 1.45)) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [RCIconCache() setObject:icon forKey:cacheKey];
    return icon;
}

UIImage *RCTriggerCategoryIcon(NSString *sectionTitle) {
    // Symbols in order of preference: the first this iOS has is used (the later ones are older)
    static NSDictionary<NSString *, NSArray<NSString *> *> *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        icons = @{
            @"Favorites": @[@"star.fill"],
            @"Volume Buttons": @[@"speaker.wave.2.fill"],
            @"Power Button": @[@"power"],
            @"Status Bar": @[@"rectangle.topthird.inset.filled", @"rectangle.topthird.inset", @"menubar.rectangle"],
            @"Edge Gestures": @[@"rectangle.lefthalf.inset.filled", @"rectangle.lefthalf.inset.fill", @"arrow.left.and.right"],
            @"Bottom Bar Gestures": @[@"rectangle.bottomthird.inset.filled", @"rectangle.bottomthird.inset", @"house.fill"],
            @"Home Button": @[@"circle.circle"],
            @"Ringer Switch": @[@"bell.fill"],
            @"Apple Watch": @[@"applewatch"],
            @"Device State": @[@"iphone"],
            @"Motion Gestures": @[@"iphone.radiowaves.left.and.right", @"waveform.path"],
            @"NFC Tags": @[@"wave.3.right"],
            @"Notifications": @[@"bell.fill"],
            @"WiFi Network Triggers": @[@"wifi"],
            @"Bluetooth Device Triggers": @[@"dot.radiowaves.left.and.right"],
            @"Audio Output Triggers": @[@"airplayaudio"],
            @"Notification Triggers": @[@"bell.badge.fill"],
            // An app, entered or closed: alike, told apart by the arrow and the cross
            @"App Launch Triggers": @[@"arrow.up.forward.app.fill", @"arrow.up.right.square.fill"],
            @"App Exit Triggers": @[@"xmark.app.fill", @"xmark.square.fill"],
            @"Scheduled Triggers": @[@"clock.fill"],
            @"MQTT Subscription Triggers": @[@"antenna.radiowaves.left.and.right"],
            @"Add-on Triggers": @[@"puzzlepiece.extension.fill", @"puzzlepiece.fill"],
        };
    });
    for (NSString *name in icons[sectionTitle ?: @""]) {
        UIImage *image = [UIImage systemImageNamed:name];
        if (image) return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return nil;
}
