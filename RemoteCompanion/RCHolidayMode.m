#import "RCHolidayMode.h"
#import "RCConfigManager.h"
#import "RCSnowfallView.h"

// The snow that is up right now, if any. Weak, so a view removed some other way can never leave
// this class thinking it is still snowing.
static __weak RCSnowfallView *gSnowView;

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

+ (void)startSnow {
    [self ensureObserving];
    if (![self isEnabled]) {
        [self stopSnow];
        return;
    }
    if ([self isSnowing]) return;

    UIWindow *window = [self hostWindow];
    if (!window) return;

    // A snow view from a quick earlier toggle may still be fading out: take it away at once
    [gSnowView removeFromSuperview];

    RCSnowfallView *snow = [[RCSnowfallView alloc] initWithFrame:window.bounds];
    snow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // A window subview goes over the app's own screens but under anything presented after it,
    // which is where the snow belongs
    [window addSubview:snow];
    gSnowView = snow;
    [snow startSnowing];
}

+ (void)stopSnow {
    RCSnowfallView *snow = gSnowView;
    if (!snow) return;

    __weak RCSnowfallView *weakSnow = snow;
    [snow stopSnowingWithCompletion:^{
        if (gSnowView == weakSnow) gSnowView = nil;
    }];
}

+ (void)refresh {
    [self ensureObserving];
    if ([self isEnabled]) {
        [self startSnow];
    } else {
        [self stopSnow];
    }
}

+ (void)handleConfigChanged:(NSNotification *)note {
    // The setter saves on the main thread; a reload from the tweak or the Web UI may not, so
    // step over to the main queue before touching the snow
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refresh];
    });
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
