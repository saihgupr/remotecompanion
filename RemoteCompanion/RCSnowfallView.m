#import "RCSnowfallView.h"
#import <QuartzCore/QuartzCore.h>

// Three depths of snow, far to near. The far flakes are small and crisp, the near ones are big
// and out of focus. That spread is what makes the fall read as depth instead of a flat sheet,
// and each band gets its own emitter so the bands can move at different speeds.
typedef NS_ENUM(NSInteger, RCSnowBand) {
    RCSnowBandFar = 0,
    RCSnowBandMid,
    RCSnowBandNear,
};

#pragma mark - Flake images

// Every flake is drawn white and then tinted by its cell: white in dark mode, a cool blue-gray
// in light mode. One set of images therefore serves both appearances, and the tint can change
// when the iPhone switches between them.

static void RCDrawWhiteGlow(CGContextRef ctx, CGPoint center, CGFloat radius,
                            const CGFloat *alphas, const CGFloat *locations, size_t count) {
    CGFloat components[24] = {0};
    for (size_t i = 0; i < count && i < 6; i++) {
        components[i * 4 + 0] = 1.0;
        components[i * 4 + 1] = 1.0;
        components[i * 4 + 2] = 1.0;
        components[i * 4 + 3] = alphas[i];
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, locations, count);
    CGContextDrawRadialGradient(ctx, gradient, center, 0, center, radius, 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

// A tiny, crisp flake: a small bright core with a quick soft edge.
static void RCDrawFarFlake(CGContextRef ctx, CGFloat size) {
    CGFloat mid = size / 2.0;
    const CGFloat alphas[] = {1.0, 0.98, 0.42, 0.0};
    const CGFloat locations[] = {0.0, 0.38, 0.76, 1.0};
    RCDrawWhiteGlow(ctx, CGPointMake(mid, mid), mid, alphas, locations, 4);
}

// A soft flake made of a few overlapping dabs, so it reads as a small clump of crystals and
// its slow spin is visible.
static void RCDrawMidFlake(CGContextRef ctx, CGFloat size) {
    const struct { CGFloat x, y, r, a; } lobes[] = {
        {0.44, 0.46, 0.40, 0.75},
        {0.60, 0.58, 0.28, 0.55},
        {0.46, 0.30, 0.22, 0.45},
    };
    for (size_t i = 0; i < sizeof(lobes) / sizeof(lobes[0]); i++) {
        CGFloat alphas[] = {lobes[i].a, lobes[i].a * 0.55, 0.0};
        CGFloat locations[] = {0.0, 0.55, 1.0};
        RCDrawWhiteGlow(ctx, CGPointMake(size * lobes[i].x, size * lobes[i].y), size * lobes[i].r,
                        alphas, locations, 3);
    }
}

// A large, out-of-focus flake: a wide halo and a soft filled disc that only ever gets fainter
// toward its edge. A bright rim would read as a bubble on screen, especially on a dark one.
static void RCDrawNearFlake(CGContextRef ctx, CGFloat size) {
    CGFloat mid = size / 2.0;

    const CGFloat haloAlphas[] = {0.20, 0.12, 0.03, 0.0};
    const CGFloat haloLocations[] = {0.0, 0.55, 0.88, 1.0};
    RCDrawWhiteGlow(ctx, CGPointMake(mid, mid), mid, haloAlphas, haloLocations, 4);

    const CGFloat bodyAlphas[] = {0.34, 0.24, 0.12, 0.04, 0.0};
    const CGFloat bodyLocations[] = {0.0, 0.35, 0.62, 0.85, 1.0};
    RCDrawWhiteGlow(ctx, CGPointMake(mid, mid), mid * 0.46, bodyAlphas, bodyLocations, 5);
}

// Flake images are built once and kept: the snow may be switched on and off many times, and the
// same few sizes are all it needs.
static UIImage *RCFlakeImage(CGFloat side, RCSnowBand band) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

    NSString *key = [NSString stringWithFormat:@"%.1f-%ld", side, (long)band];
    UIImage *cached = cache[key];
    if (cached) return cached;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        if (band == RCSnowBandNear) RCDrawNearFlake(context.CGContext, side);
        else if (band == RCSnowBandMid) RCDrawMidFlake(context.CGContext, side);
        else RCDrawFarFlake(context.CGContext, side);
    }];
    cache[key] = image;
    return image;
}

// The steady birth rate of each cell in a band. The screen width scales these (see
// -applyDensity), so a big phone gets more snow than a small one.
static NSArray<NSNumber *> *RCBirthRatesForBand(RCSnowBand band) {
    switch (band) {
        case RCSnowBandFar: return @[@1.7, @1.1];
        case RCSnowBandMid: return @[@0.85, @0.5];
        case RCSnowBandNear: return @[@0.3];
    }
    return @[];
}

#pragma mark - View

@interface RCSnowfallView ()
@property (nonatomic, assign, getter=isSnowing) BOOL snowing;
@property (nonatomic, strong) NSMutableArray<CAEmitterLayer *> *emitterLayers;
@property (nonatomic, assign) BOOL stopping;
@property (nonatomic, assign) BOOL reduceMotion;
@end

@implementation RCSnowfallView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.accessibilityElementsHidden = YES;
        self.layer.masksToBounds = YES;
        self.alpha = 0;
        _reduceMotion = UIAccessibilityIsReduceMotionEnabled();
        _emitterLayers = [NSMutableArray array];

        // Far first, so the near flakes are drawn on top of it
        for (RCSnowBand band = RCSnowBandFar; band <= RCSnowBandNear; band++) {
            // Reduce Motion: fewer flakes, and no big near ones
            if (band == RCSnowBandNear && _reduceMotion) continue;
            CAEmitterLayer *layer = [self emitterLayerForBand:band];
            [self.layer addSublayer:layer];
            [self.emitterLayers addObject:layer];
        }
    }
    return self;
}

- (void)dealloc {
    for (CAEmitterLayer *layer in self.emitterLayers) {
        layer.emitterCells = nil;
        [layer removeFromSuperlayer];
    }
}

#pragma mark - Emitters

- (CAEmitterLayer *)emitterLayerForBand:(RCSnowBand)band {
    CAEmitterLayer *layer = [CAEmitterLayer layer];
    layer.emitterShape = kCAEmitterLayerRectangle;
    layer.renderMode = kCAEmitterLayerUnordered;
    layer.birthRate = 0;   // started by -startSnowing
    layer.seed = (uint32_t)arc4random();
    layer.emitterSize = CGSizeMake(200, 4);
    layer.emitterPosition = CGPointMake(100, -18);

    NSMutableArray<CAEmitterCell *> *cells = [NSMutableArray array];
    if (band == RCSnowBandFar) {
        CAEmitterCell *grain = [self flakeCellWithSide:7 band:band];
        grain.lifetime = 38;
        grain.lifetimeRange = 10;
        grain.velocity = 14;
        grain.velocityRange = 2;
        grain.scale = 0.5;
        grain.scaleRange = 0.22;
        grain.alphaRange = 0.28;
        grain.alphaSpeed = -0.014;
        grain.spin = 0.15;
        grain.spinRange = 0.45;
        grain.xAcceleration = -0.10;
        grain.emissionRange = 0.16;
        [cells addObject:grain];

        CAEmitterCell *drift = [self flakeCellWithSide:10 band:band];
        drift.lifetime = 40;
        drift.lifetimeRange = 10;
        drift.velocity = 17;
        drift.velocityRange = 3;
        drift.scale = 0.55;
        drift.scaleRange = 0.18;
        drift.alphaRange = 0.25;
        drift.alphaSpeed = -0.012;
        drift.spin = 0.1;
        drift.spinRange = 0.4;
        drift.xAcceleration = 0.12;
        drift.emissionRange = 0.22;
        [cells addObject:drift];
    } else if (band == RCSnowBandMid) {
        CAEmitterCell *soft = [self flakeCellWithSide:18 band:band];
        soft.lifetime = 34;
        soft.lifetimeRange = 9;
        soft.velocity = 22;
        soft.velocityRange = 4;
        soft.scale = 0.68;
        soft.scaleRange = 0.2;
        soft.alphaRange = 0.3;
        soft.alphaSpeed = -0.015;
        soft.spin = 0.3;
        soft.spinRange = 0.7;
        soft.xAcceleration = 0.08;
        soft.emissionRange = 0.22;
        [cells addObject:soft];

        CAEmitterCell *bigger = [self flakeCellWithSide:24 band:band];
        bigger.lifetime = 32;
        bigger.lifetimeRange = 8;
        bigger.velocity = 27;
        bigger.velocityRange = 4;
        bigger.scale = 0.6;
        bigger.scaleRange = 0.18;
        bigger.alphaRange = 0.25;
        bigger.alphaSpeed = -0.013;
        bigger.spin = -0.22;
        bigger.spinRange = 0.6;
        bigger.xAcceleration = -0.12;
        bigger.emissionRange = 0.2;
        [cells addObject:bigger];
    } else {
        CAEmitterCell *bokeh = [self flakeCellWithSide:52 band:band];
        bokeh.lifetime = 34;
        bokeh.lifetimeRange = 8;
        bokeh.velocity = 30;
        bokeh.velocityRange = 6;
        bokeh.scale = 0.85;
        bokeh.scaleRange = 0.35;
        bokeh.alphaRange = 0.2;
        bokeh.alphaSpeed = -0.010;
        bokeh.spin = 0.1;
        bokeh.spinRange = 0.35;
        bokeh.xAcceleration = 0.06;
        bokeh.yAcceleration = 0.18;
        bokeh.emissionRange = 0.3;
        [cells addObject:bokeh];
    }

    layer.emitterCells = cells;
    return layer;
}

// The settings every flake shares. A little sideways lean in the velocity cone plus a tiny
// sideways acceleration gives the slow, uneven drift, and the fall speeds stay between about
// 12 and 36 points a second.
- (CAEmitterCell *)flakeCellWithSide:(CGFloat)side band:(RCSnowBand)band {
    UIImage *image = RCFlakeImage(side, band);
    CAEmitterCell *cell = [CAEmitterCell emitterCell];
    cell.contents = (__bridge id)image.CGImage;
    cell.contentsScale = image.scale;
    cell.minificationFilter = kCAFilterLinear;
    cell.magnificationFilter = kCAFilterLinear;
    cell.color = [self tintForBand:band].CGColor;
    cell.emissionLongitude = M_PI_2;   // straight down (0 points right, so a quarter turn is down)
    cell.emissionRange = 0.2;
    cell.yAcceleration = 0.28;
    cell.birthRate = 0;                // set by -applyDensity
    return cell;
}

// White on the app's dark backgrounds; a cool blue-gray on the light ones, where white would
// all but disappear.
- (UIColor *)tintForBand:(RCSnowBand)band {
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        return [UIColor colorWithWhite:1.0 alpha:1.0];
    }
    if (band == RCSnowBandNear) {
        return [UIColor colorWithRed:0.58 green:0.66 blue:0.78 alpha:0.9];
    }
    return [UIColor colorWithRed:0.55 green:0.63 blue:0.75 alpha:0.95];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateEmitterGeometry];
    if (self.snowing) [self applyDensity];
}

// The emitters run along the top edge, a little wider than the screen so the sides are as busy
// as the middle. Called on layout, so a rotation or a size change moves them with the window.
- (void)updateEmitterGeometry {
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CAEmitterLayer *layer in self.emitterLayers) {
        layer.frame = bounds;
        layer.emitterPosition = CGPointMake(CGRectGetMidX(bounds), -18);
        layer.emitterSize = CGSizeMake(CGRectGetWidth(bounds) + 140, 4);
    }
    [CATransaction commit];
}

// More snow on a wider screen, less on a narrow one, and about a third as much with Reduce
// Motion on.
- (void)applyDensity {
    CGFloat widthScale = MAX(0.55, CGRectGetWidth(self.bounds) / 390.0);
    CGFloat density = widthScale * (self.reduceMotion ? 0.34 : 1.0);
    [self.emitterLayers enumerateObjectsUsingBlock:^(CAEmitterLayer *layer, NSUInteger index, __unused BOOL *stop) {
        NSArray<NSNumber *> *rates = RCBirthRatesForBand((RCSnowBand)index);
        [layer.emitterCells enumerateObjectsUsingBlock:^(CAEmitterCell *cell, NSUInteger cellIndex, __unused BOOL *innerStop) {
            if (cellIndex < rates.count) {
                cell.birthRate = rates[cellIndex].floatValue * density;
            }
        }];
    }];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection) return;
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self updateTints];
        }
    }
}

- (void)updateTints {
    [self.emitterLayers enumerateObjectsUsingBlock:^(CAEmitterLayer *layer, NSUInteger index, __unused BOOL *stop) {
        CGColorRef color = [self tintForBand:(RCSnowBand)index].CGColor;
        for (CAEmitterCell *cell in layer.emitterCells) cell.color = color;
    }];
}

#pragma mark - On and off

- (void)startSnowing {
    if (self.snowing) return;
    self.snowing = YES;
    self.stopping = NO;

    [self updateEmitterGeometry];
    [self applyDensity];
    [self updateTints];   // the window's light or dark appearance is known now

    // Start as if the snow had already been falling for a while, so the first frame is snowed
    // in from top to bottom instead of building up over half a minute. The particles are made
    // from the emitter's own clock, so winding that clock back fills the screen for free.
    static const CFTimeInterval kPrewarm = 30.0;
    CFTimeInterval now = CACurrentMediaTime();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CAEmitterLayer *layer in self.emitterLayers) {
        [layer removeAllAnimations];
        layer.beginTime = now - kPrewarm;
        layer.birthRate = 1.0;
    }
    [CATransaction commit];

    self.alpha = 0;
    [UIView animateWithDuration:0.8 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.alpha = 1; }
                     completion:nil];
}

- (void)stopSnowingWithCompletion:(void (^)(void))completion {
    if (self.stopping) {
        if (completion) completion();
        return;
    }
    self.stopping = YES;
    self.snowing = NO;

    // No new flakes; the ones already falling fade out with the view
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CAEmitterLayer *layer in self.emitterLayers) {
        [layer removeAllAnimations];
        layer.birthRate = 0;
    }
    [CATransaction commit];

    [UIView animateWithDuration:0.6 delay:0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.alpha = 0; }
                     completion:^(__unused BOOL finished) {
        [self tearDown];
        if (completion) completion();
    }];
}

- (void)tearDown {
    NSArray<CAEmitterLayer *> *layers = [self.emitterLayers copy];
    [self.emitterLayers removeAllObjects];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CAEmitterLayer *layer in layers) {
        [layer removeAllAnimations];
        layer.birthRate = 0;
        layer.emitterCells = nil;
        [layer removeFromSuperlayer];
    }
    [CATransaction commit];
    [self removeFromSuperview];
}

@end
