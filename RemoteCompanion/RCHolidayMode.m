#import "RCHolidayMode.h"
#import "RCConfigManager.h"
#import "RCSnowfallView.h"

// The present in the header: a red gift, with a soft red glow behind it while the snow is on.
// It presses in and springs back, so it feels like a button and not a picture.
@interface RCPresentButton : UIButton
@property (nonatomic, assign, getter=isSnowing) BOOL snowing;
@end

@implementation RCPresentButton {
    UIView *_halo;
    UIView *_glyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        _halo = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)];
        _halo.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.16];
        _halo.layer.cornerRadius = 9;
        _halo.layer.cornerCurve = kCACornerCurveContinuous;
        _halo.userInteractionEnabled = NO;
        _halo.alpha = 0;
        [self addSubview:_halo];

        // The gift itself: bundled artwork, with SF Symbol / emoji fallback
        UIImage *gift = [[UIImage imageNamed:@"HolidayPresent"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        if (gift) {
            UIImageView *imageView = [[UIImageView alloc] initWithImage:gift];
            imageView.contentMode = UIViewContentModeScaleAspectFit;
            _glyph = imageView;
        } else {
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *configuration =
                    [UIImageSymbolConfiguration configurationWithPointSize:23 weight:UIImageSymbolWeightSemibold];
                gift = [UIImage systemImageNamed:@"gift.fill" withConfiguration:configuration];
            }
            if (gift) {
                UIImageView *imageView = [[UIImageView alloc] initWithImage:gift];
                imageView.tintColor = [UIColor systemRedColor];
                imageView.contentMode = UIViewContentModeCenter;
                _glyph = imageView;
            } else {
                UILabel *label = [[UILabel alloc] init];
                label.text = @"\U0001F381";   // 🎁
                label.font = [UIFont systemFontOfSize:20];
                label.textAlignment = NSTextAlignmentCenter;
                _glyph = label;
            }
        }
        _glyph.userInteractionEnabled = NO;
        [self addSubview:_glyph];

        self.accessibilityLabel = @"Toggle holiday snowfall";
        self.accessibilityHint = @"Turns the snow on or off";
        self.accessibilityValue = @"Off";
        self.accessibilityTraits = UIAccessibilityTraitButton;

        [self addTarget:self action:@selector(pressDown) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(pressUp) forControlEvents:UIControlEventTouchUpInside |
                                                       UIControlEventTouchUpOutside |
                                                       UIControlEventTouchCancel];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    // The button has no title or image of its own; without this the bar button item would
    // size the custom view to nothing and the present would not show.
    return CGSizeMake(40, 44);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _halo.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds) + 5.0);
    _glyph.frame = CGRectMake(0, 0, 32, 32);
    _glyph.center = _halo.center;
}

- (void)setSnowing:(BOOL)snowing {
    BOOL changed = (_snowing != snowing);
    _snowing = snowing;
    self.accessibilityValue = snowing ? @"On" : @"Off";
    if (!changed) return;

    [UIView animateWithDuration:(snowing ? 0.28 : 0.2) delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self->_halo.alpha = snowing ? 1.0 : 0.0; }
                     completion:nil];
    if (snowing) {
        // A small pop as the snow starts
        _halo.transform = CGAffineTransformMakeScale(0.6, 0.6);
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ self->_halo.transform = CGAffineTransformIdentity; }
                         completion:nil];
    }
}

- (void)pressDown {
    [UIView animateWithDuration:0.11 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = CGAffineTransformMakeScale(0.86, 0.86); }
                     completion:nil];
}

- (void)pressUp {
    [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.4 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = CGAffineTransformIdentity; }
                     completion:nil];
}

@end

#pragma mark -

// The snow that is up right now, if any. Weak, so a view removed some other way can never leave
// this class thinking it is still snowing.
static __weak RCSnowfallView *gSnowView;
// The present last handed to a screen, so the snow can light its glow up and down.
static __weak RCPresentButton *gPresentButton;

@interface RCHolidayMode ()
+ (void)ensureObserving;
+ (void)handleConfigChanged:(NSNotification *)note;
+ (UIWindow *)hostWindow;
@end

@implementation RCHolidayMode

+ (void)ensureObserving {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleConfigChanged:)
                                                     name:RCConfigChangedNotification
                                                   object:nil];
    });
}

#pragma mark - The setting

+ (BOOL)isEnabled {
    [self ensureObserving];
    return [RCConfigManager sharedManager].holidayModeEnabled;
}

+ (void)setEnabled:(BOOL)enabled {
    [self ensureObserving];
    [RCConfigManager sharedManager].holidayModeEnabled = enabled;
    [self refresh];
}

#pragma mark - The snow

+ (BOOL)isSnowing {
    return [gSnowView isSnowing];
}

+ (void)toggleSnow {
    [self ensureObserving];
    if (![self isEnabled]) {
        [self stopSnow];
        return;
    }
    if ([self isSnowing]) {
        [self stopSnow];
        return;
    }

    UIWindow *window = [self hostWindow];
    if (!window) return;

    // A snow view from a quick earlier tap may still be fading out: take it away at once
    [gSnowView removeFromSuperview];

    RCSnowfallView *snow = [[RCSnowfallView alloc] initWithFrame:window.bounds];
    snow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // A window subview goes over the app's own screens but under anything presented after it,
    // which is where the snow belongs
    [window addSubview:snow];
    gSnowView = snow;
    [snow startSnowing];
    [gPresentButton setSnowing:YES];
}

+ (void)stopSnow {
    RCSnowfallView *snow = gSnowView;
    [gPresentButton setSnowing:NO];
    if (!snow) return;

    __weak RCSnowfallView *weakSnow = snow;
    [snow stopSnowingWithCompletion:^{
        if (gSnowView == weakSnow) gSnowView = nil;
    }];
}

+ (void)refresh {
    [self ensureObserving];
    if (![self isEnabled]) {
        [self stopSnow];
    } else {
        [gPresentButton setSnowing:[self isSnowing]];
    }
}

+ (void)handleConfigChanged:(NSNotification *)note {
    // The setter saves on the main thread; a reload from the tweak or the Web UI may not, so
    // step over to the main queue before touching the snow
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![RCConfigManager sharedManager].holidayModeEnabled) [self stopSnow];
    });
}

#pragma mark - The present

+ (UIBarButtonItem *)presentBarButtonItemWithTarget:(id)target action:(SEL)action {
    [self ensureObserving];
    RCPresentButton *button = [[RCPresentButton alloc] initWithFrame:CGRectMake(0, 0, 40, 44)];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [button setSnowing:[self isSnowing]];
    gPresentButton = button;

    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:button];
    item.accessibilityLabel = @"Toggle holiday snowfall";
    return item;
}

#pragma mark - Helpers

+ (UIWindow *)hostWindow {
    UIApplication *application = [UIApplication sharedApplication];
    for (UIWindow *window in application.windows) {
        if (window.isKeyWindow) return window;
    }
    if (@available(iOS 15.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }
    return application.windows.firstObject;
}

@end
