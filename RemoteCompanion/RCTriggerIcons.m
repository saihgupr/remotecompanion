#import "RCTriggerIcons.h"

// What each icon is made of:
//   base:  symbol names, the first this iOS has is used
//   badge: @"2", @"L"... (letters) or @"sym:timer" (a symbol), in a small circle at the bottom right
//   pair:  two symbols side by side (each a list of names, as for base)
static NSDictionary<NSString *, NSDictionary *> *RCTriggerIconSpecs(void) {
    static NSDictionary *specs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *speakerUp = @[@"speaker.plus.fill", @"speaker.wave.3.fill"];
        NSArray *speakerDown = @[@"speaker.minus.fill", @"speaker.wave.1.fill"];
        NSArray *power = @[@"power"];
        NSArray *statusBar = @[@"rectangle.topthird.inset", @"menubar.rectangle", @"hand.draw"];
        NSArray *edgeLeft = @[@"rectangle.lefthalf.inset.fill", @"rectangle.lefthalf.fill", @"iphone"];
        NSArray *edgeRight = @[@"rectangle.righthalf.inset.fill", @"rectangle.righthalf.fill", @"iphone"];
        NSArray *bottomBar = @[@"rectangle.bottomthird.inset", @"rectangle.bottomhalf.fill", @"square.stack.3d.up.fill"];
        NSArray *swipeUp = @[@"arrow.up.to.line", @"chevron.compact.up"];
        NSArray *home = @[@"circle.circle"];
        NSArray *watch = @[@"applewatch.radiowaves.left.and.right", @"applewatch"];
        NSString *hold = @"sym:timer";
        specs = @{
            @"volume_up_hold":          @{ @"base": speakerUp, @"badge": hold },
            @"volume_down_hold":        @{ @"base": speakerDown, @"badge": hold },
            @"volume_both_press":       @{ @"base": @[@"speaker.wave.2.fill"], @"badge": @"±" },
            @"volume_up_then_down":     @{ @"pair": @[speakerUp, speakerDown] },
            @"volume_down_then_up":     @{ @"pair": @[speakerDown, speakerUp] },
            @"power_double_tap":        @{ @"base": power, @"badge": @"2" },
            @"power_triple_click":      @{ @"base": power, @"badge": @"3" },
            @"power_quadruple_click":   @{ @"base": power, @"badge": @"4" },
            @"power_long_press":        @{ @"base": power, @"badge": hold },
            @"power_volume_up":         @{ @"pair": @[power, speakerUp] },
            @"power_volume_down":       @{ @"pair": @[power, speakerDown] },
            @"trigger_statusbar_left_hold":   @{ @"base": statusBar, @"badge": @"L" },
            @"trigger_statusbar_center_hold": @{ @"base": statusBar, @"badge": @"C" },
            @"trigger_statusbar_right_hold":  @{ @"base": statusBar, @"badge": @"R" },
            @"trigger_statusbar_swipe_left":  @{ @"base": statusBar, @"badge": @"sym:arrow.left" },
            @"trigger_statusbar_swipe_right": @{ @"base": statusBar, @"badge": @"sym:arrow.right" },
            @"trigger_statusbar_double_tap":  @{ @"base": statusBar, @"badge": @"2" },
            @"trigger_edge_left_swipe_up":    @{ @"base": edgeLeft, @"badge": @"sym:arrow.up" },
            @"trigger_edge_left_swipe_down":  @{ @"base": edgeLeft, @"badge": @"sym:arrow.down" },
            @"trigger_edge_right_swipe_up":   @{ @"base": edgeRight, @"badge": @"sym:arrow.up" },
            @"trigger_edge_right_swipe_down": @{ @"base": edgeRight, @"badge": @"sym:arrow.down" },
            @"trigger_bottombar_swipe_left":  @{ @"base": bottomBar, @"badge": @"sym:arrow.left" },
            @"trigger_bottombar_swipe_right": @{ @"base": bottomBar, @"badge": @"sym:arrow.right" },
            @"trigger_bottom_swipe_up_left":   @{ @"base": swipeUp, @"badge": @"L" },
            @"trigger_bottom_swipe_up_center": @{ @"base": swipeUp, @"badge": @"C" },
            @"trigger_bottom_swipe_up_right":  @{ @"base": swipeUp, @"badge": @"R" },
            @"trigger_home_double_click":    @{ @"base": home, @"badge": @"2" },
            @"trigger_home_triple_click":    @{ @"base": home, @"badge": @"3" },
            @"trigger_home_quadruple_click": @{ @"base": home, @"badge": @"4" },
            @"trigger_home_hold":            @{ @"base": home, @"badge": hold },
            @"trigger_home_power":           @{ @"pair": @[home, power] },
            @"touchid_tap":                  @{ @"base": @[@"touchid"] },
            @"touchid_hold":                 @{ @"base": @[@"touchid"], @"badge": hold },
            @"trigger_ringer_mute":          @{ @"base": @[@"bell.slash.fill"] },
            @"trigger_ringer_unmute":        @{ @"base": @[@"bell.fill"] },
            @"trigger_ringer_toggle":        @{ @"pair": @[@[@"bell.fill"], @[@"bell.slash.fill"]] },
            @"trigger_watch_ping":           @{ @"base": watch },
            @"trigger_watch_ping_hold":      @{ @"base": watch, @"badge": hold },
        };
    });
    return specs;
}

static UIImage *RCFirstSymbol(NSArray<NSString *> *names, CGFloat size, UIImageSymbolWeight weight) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    for (NSString *name in names) {
        UIImage *image = [UIImage systemImageNamed:name withConfiguration:config];
        if (image) return image;
    }
    return nil;
}

// Draws an image fitted into a box, centred
static void RCDrawFitted(UIImage *image, CGRect box) {
    CGSize size = image.size;
    if (size.width <= 0 || size.height <= 0) return;
    CGFloat scale = MIN(1.0, MIN(box.size.width / size.width, box.size.height / size.height));
    CGSize drawn = CGSizeMake(size.width * scale, size.height * scale);
    [image drawInRect:CGRectMake(CGRectGetMidX(box) - drawn.width / 2, CGRectGetMidY(box) - drawn.height / 2, drawn.width, drawn.height)];
}

static UIImage *RCIconFromSpec(NSDictionary *spec, NSString *name, CGFloat pointSize);

UIImage *RCTriggerIconImage(NSString *triggerKey, CGFloat pointSize) {
    NSDictionary *spec = RCTriggerIconSpecs()[triggerKey ?: @""];
    return spec ? RCIconFromSpec(spec, triggerKey, pointSize) : nil;
}

UIImage *RCTriggerSymbolImage(NSString *symbolName, CGFloat pointSize) {
    if (!symbolName.length) return nil;
    return RCIconFromSpec(@{ @"base": @[symbolName] }, [@"symbol:" stringByAppendingString:symbolName], pointSize);
}

static UIImage *RCIconFromSpec(NSDictionary *spec, NSString *name, CGFloat pointSize) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    NSString *cacheKey = [NSString stringWithFormat:@"%@@%.1f", name, pointSize];
    UIImage *cached = [cache objectForKey:cacheKey];
    if (cached) return cached;

    // Every icon has the same box, so text beside it lines up whatever it is
    CGSize canvas = CGSizeMake(ceil(pointSize * 1.5), ceil(pointSize * 1.2));
    NSArray *pair = spec[@"pair"];
    UIImage *base = pair ? nil : RCFirstSymbol(spec[@"base"], pointSize * 0.9, UIImageSymbolWeightMedium);
    UIImage *left = pair ? RCFirstSymbol(pair[0], pointSize * 0.62, UIImageSymbolWeightMedium) : nil;
    UIImage *right = pair ? RCFirstSymbol(pair[1], pointSize * 0.62, UIImageSymbolWeightMedium) : nil;
    if (!base && !(left && right)) return nil;

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvas];
    UIImage *drawn = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        [[UIColor blackColor] setFill];
        if (base) {
            RCDrawFitted([base imageWithTintColor:[UIColor blackColor]], CGRectMake(0, 0, canvas.width, canvas.height));
        } else {
            CGFloat half = canvas.width / 2;
            RCDrawFitted([left imageWithTintColor:[UIColor blackColor]], CGRectMake(0, 0, half - 1, canvas.height));
            RCDrawFitted([right imageWithTintColor:[UIColor blackColor]], CGRectMake(half + 1, 0, half - 1, canvas.height));
        }
        NSString *badge = spec[@"badge"];
        if (!badge) return;
        // A small circle at the bottom right, cut free of the symbol under it, its mark cut out of it
        CGFloat d = round(pointSize * 0.66);
        CGRect circle = CGRectMake(canvas.width - d, canvas.height - d, d, d);
        CGContextSetBlendMode(context, kCGBlendModeClear);
        CGContextFillEllipseInRect(context, CGRectInset(circle, -1.5, -1.5));
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        CGContextFillEllipseInRect(context, circle);
        CGContextSetBlendMode(context, kCGBlendModeClear);
        if ([badge hasPrefix:@"sym:"]) {
            UIImage *mark = RCFirstSymbol(@[[badge substringFromIndex:4]], d * 0.52, UIImageSymbolWeightBold);
            RCDrawFitted([mark imageWithTintColor:[UIColor blackColor]], CGRectInset(circle, d * 0.18, d * 0.18));
        } else {
            NSDictionary *attributes = @{ NSFontAttributeName: [UIFont systemFontOfSize:d * 0.68 weight:UIFontWeightHeavy], NSForegroundColorAttributeName: [UIColor blackColor] };
            CGSize size = [badge sizeWithAttributes:attributes];
            [badge drawAtPoint:CGPointMake(CGRectGetMidX(circle) - size.width / 2, CGRectGetMidY(circle) - size.height / 2) withAttributes:attributes];
        }
        CGContextSetBlendMode(context, kCGBlendModeNormal);
    }];
    UIImage *icon = [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [cache setObject:icon forKey:cacheKey];
    return icon;
}
