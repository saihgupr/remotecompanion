#import "RCScreenSelect.h"
#import "RCScreen.h"
#import "RCToastPill.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/runtime.h>
#import <objc/message.h>

extern void SRLog(NSString *format, ...);

static void rc_select_main_sync(dispatch_block_t block) {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static BOOL rc_select_is_locked(void) {
    __block BOOL locked = NO;
    rc_select_main_sync(^{
        Class backlightCls = objc_getClass("SBBacklightController");
        id backlight = [backlightCls respondsToSelector:@selector(sharedInstance)]
            ? ((id (*)(id, SEL))objc_msgSend)(backlightCls, @selector(sharedInstance))
            : nil;
        if (backlight && [backlight respondsToSelector:@selector(screenIsOn)]) {
            if (!((BOOL (*)(id, SEL))objc_msgSend)(backlight, @selector(screenIsOn))) {
                locked = YES;
                return;
            }
        }
        Class lsmCls = objc_getClass("SBLockScreenManager");
        id lsm = [lsmCls respondsToSelector:@selector(sharedInstance)]
            ? ((id (*)(id, SEL))objc_msgSend)(lsmCls, @selector(sharedInstance))
            : nil;
        if (!lsm || ![lsm respondsToSelector:@selector(isUILocked)]) return;
        if (!((BOOL (*)(id, SEL))objc_msgSend)(lsm, @selector(isUILocked))) return;

        // On iOS 17+, pulling Notification Center also sets isUILocked; bit 2 on SBLockStateAggregator distinguishes a real lock.
        Class aggCls = objc_getClass("SBLockStateAggregator");
        id agg = [aggCls respondsToSelector:@selector(sharedInstance)]
            ? ((id (*)(id, SEL))objc_msgSend)(aggCls, @selector(sharedInstance))
            : nil;
        if (agg && [agg respondsToSelector:@selector(lockState)]) {
            NSUInteger lockState = ((NSUInteger (*)(id, SEL))objc_msgSend)(agg, @selector(lockState));
            locked = (lockState & 2) != 0;
        } else {
            locked = YES;
        }
    });
    return locked;
}

static void rc_select_dismiss_cc_if_visible(void) {
    rc_select_main_sync(^{
        id cc = nil;
        Class cccCls = objc_getClass("SBControlCenterCoordinator");
        if ([cccCls respondsToSelector:@selector(sharedInstanceIfExists)]) {
            cc = ((id (*)(id, SEL))objc_msgSend)(cccCls, @selector(sharedInstanceIfExists));
        }
        if (!cc) {
            Class ccCls = objc_getClass("SBControlCenterController");
            if ([ccCls respondsToSelector:@selector(sharedInstanceIfExists)]) {
                cc = ((id (*)(id, SEL))objc_msgSend)(ccCls, @selector(sharedInstanceIfExists));
            }
        }
        if (cc && [cc respondsToSelector:@selector(isVisible)] && ((BOOL (*)(id, SEL))objc_msgSend)(cc, @selector(isVisible))) {
            if ([cc respondsToSelector:@selector(dismissAnimated:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(cc, @selector(dismissAnimated:), YES);
            }
        }
    });
}

static UIWindowScene *rc_select_window_scene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL wsmSel = @selector(windowSceneManager);
    if ([app respondsToSelector:wsmSel]) {
        id wsm = ((id (*)(id, SEL))objc_msgSend)(app, wsmSel);
        SEL edSel = @selector(embeddedDisplayWindowScene);
        if (wsm && [wsm respondsToSelector:edSel]) {
            id scene = ((id (*)(id, SEL))objc_msgSend)(wsm, edSel);
            if ([scene isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)scene;
        }
    }
    for (UIScene *s in app.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

static UIInterfaceOrientation rc_select_active_orientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL activeSel = @selector(activeInterfaceOrientation);
    if ([app respondsToSelector:activeSel]) {
        return ((UIInterfaceOrientation (*)(id, SEL))objc_msgSend)(app, activeSel);
    }
    UIWindowScene *scene = rc_select_window_scene();
    return scene ? scene.interfaceOrientation : UIInterfaceOrientationPortrait;
}

static CGFloat rc_select_top_inset(UIWindowScene *scene, BOOL landscape) {
    if (landscape) return 12.0;
    CGFloat topInset = 0;
    if (scene.statusBarManager) {
        topInset = scene.statusBarManager.statusBarFrame.size.height;
    }
    for (UIWindow *w in scene.windows) {
        if (!w.hidden && w.safeAreaInsets.top > topInset) topInset = w.safeAreaInsets.top;
    }
    return topInset > 24.0 ? topInset : 12.0;
}

// Secure window so the selection overlay renders cleanly across SpringBoard/system surfaces on iOS 16+.
@interface RCScreenSelectWindow : UIWindow
@end

@implementation RCScreenSelectWindow
- (BOOL)_shouldCreateContextAsSecure {
    return YES;
}
@end

@interface RCScreenSelectViewController : UIViewController {
    UIView *_overlayView;
    CAShapeLayer *_dimLayer;
    CAShapeLayer *_borderLayer;
    RCToastPillView *_pill;
    UITouch *_activeTouch;
    CGPoint _startPoint;
    CGPoint _currentPoint;
    BOOL _dragging;
    BOOL _ended;
    CGSize _shotSize;
}
@property (nonatomic, copy) void (^onFinish)(BOOL cancelled, CGRect rect);
- (instancetype)initWithShotSize:(CGSize)shotSize;
- (void)showPillTitle:(NSString *)title message:(NSString *)message icon:(NSString *)icon;
- (void)markFinished;
@end

@implementation RCScreenSelectViewController

- (instancetype)initWithShotSize:(CGSize)shotSize {
    if ((self = [super init])) {
        _shotSize = shotSize;
    }
    return self;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.opaque = NO;
    self.view.multipleTouchEnabled = NO;

    _overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    _overlayView.backgroundColor = [UIColor clearColor];
    _overlayView.opaque = NO;
    _overlayView.multipleTouchEnabled = NO;
    [self.view addSubview:_overlayView];

    _dimLayer = [CAShapeLayer layer];
    _dimLayer.fillRule = kCAFillRuleEvenOdd;
    _dimLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.38].CGColor;
    [_overlayView.layer addSublayer:_dimLayer];

    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = [UIColor clearColor].CGColor;
    _borderLayer.strokeColor = [UIColor whiteColor].CGColor;
    _borderLayer.lineWidth = 1.5;
    _borderLayer.shadowColor = [UIColor blackColor].CGColor;
    _borderLayer.shadowOpacity = 0.5;
    _borderLayer.shadowRadius = 2.0;
    _borderLayer.shadowOffset = CGSizeZero;
    [_overlayView.layer addSublayer:_borderLayer];

    [self layoutOverlayFrame];
    [self updateSelectionPaths];
    [self showPillTitle:@"Copy Text" message:@"Drag over text to copy" icon:@"text.viewfinder"];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutOverlayFrame];
    [self updateSelectionPaths];
    [self positionPill];
}

// Match the held screenshot's orientation and point coordinates even when SpringBoard keeps its
// overlay window scene in portrait while a landscape app is foregrounded.
- (void)layoutOverlayFrame {
    CGSize vb = self.view.bounds.size;
    if (vb.width <= 0 || vb.height <= 0) return;

    UIInterfaceOrientation active = rc_select_active_orientation();
    UIWindowScene *scene = self.view.window.windowScene ?: rc_select_window_scene();
    UIInterfaceOrientation sceneOrientation = scene ? scene.interfaceOrientation : UIInterfaceOrientationPortrait;

    BOOL viewIsLandscape = vb.width > vb.height;
    BOOL targetIsLandscape = UIInterfaceOrientationIsLandscape(active);

    if (viewIsLandscape != targetIsLandscape) {
        CGFloat angle = 0;
        if (!viewIsLandscape) {
            angle = (active == UIInterfaceOrientationLandscapeLeft) ? -M_PI_2 : M_PI_2;
        } else {
            angle = (sceneOrientation == UIInterfaceOrientationLandscapeLeft) ? M_PI_2 : -M_PI_2;
        }
        CGFloat w = _shotSize.width > 0 ? _shotSize.width : vb.height;
        CGFloat h = _shotSize.height > 0 ? _shotSize.height : vb.width;
        _overlayView.transform = CGAffineTransformMakeRotation(angle);
        _overlayView.bounds = CGRectMake(0, 0, w, h);
        _overlayView.center = CGPointMake(vb.width * 0.5, vb.height * 0.5);
    } else if (sceneOrientation != UIInterfaceOrientationUnknown && sceneOrientation != active) {
        _overlayView.transform = CGAffineTransformMakeRotation(M_PI);
        _overlayView.bounds = CGRectMake(0, 0, vb.width, vb.height);
        _overlayView.center = CGPointMake(vb.width * 0.5, vb.height * 0.5);
    } else {
        _overlayView.transform = CGAffineTransformIdentity;
        _overlayView.frame = self.view.bounds;
    }
    _dimLayer.frame = _overlayView.bounds;
    _borderLayer.frame = _overlayView.bounds;
}

- (void)positionPill {
    if (!_pill) return;
    CGSize overlaySize = _overlayView.bounds.size;
    if (overlaySize.width <= 0) return;
    UIWindowScene *scene = self.view.window.windowScene ?: rc_select_window_scene();
    BOOL landscape = UIInterfaceOrientationIsLandscape(rc_select_active_orientation());
    CGFloat topY = rc_select_top_inset(scene, landscape) + 6.0;
    CGFloat maxW = [RCToastPillView maxPillWidthForScreenWidth:overlaySize.width];
    CGSize pillSize = [RCToastPillView sizeForTitle:_pill.pillTitle
                                           message:_pill.pillMessage
                                          iconName:_pill.pillIconName
                                      wrapsMessage:NO
                                          maxWidth:maxW];
    _pill.frame = CGRectMake(round((overlaySize.width - pillSize.width) * 0.5),
                             topY,
                             pillSize.width,
                             pillSize.height);
}

- (void)showPillTitle:(NSString *)title message:(NSString *)message icon:(NSString *)icon {
    [_pill removeFromSuperview];
    _pill = [[RCToastPillView alloc] initWithTitle:title message:message iconName:icon];
    _pill.userInteractionEnabled = NO;
    [_overlayView addSubview:_pill];
    [self positionPill];
}

- (CGRect)currentSelectionRect {
    CGRect raw = CGRectMake(_startPoint.x,
                            _startPoint.y,
                            _currentPoint.x - _startPoint.x,
                            _currentPoint.y - _startPoint.y);
    CGRect clamped = CGRectIntersection(CGRectStandardize(raw), _overlayView.bounds);
    return CGRectIsNull(clamped) ? CGRectZero : clamped;
}

- (void)updateSelectionPaths {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIBezierPath *dimPath = [UIBezierPath bezierPathWithRect:_overlayView.bounds];
    if (_dragging) {
        CGRect rect = [self currentSelectionRect];
        if (rect.size.width > 0 && rect.size.height > 0) {
            UIBezierPath *hole = [UIBezierPath bezierPathWithRect:rect];
            [dimPath appendPath:hole];
            _borderLayer.path = hole.CGPath;
        } else {
            _borderLayer.path = NULL;
        }
    } else {
        _borderLayer.path = NULL;
    }
    _dimLayer.path = dimPath.CGPath;
    [CATransaction commit];
}

- (void)markFinished {
    _ended = YES;
    _activeTouch = nil;
    self.view.userInteractionEnabled = NO;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_ended || _activeTouch) return;
    UITouch *touch = [touches anyObject];
    if (!touch) return;
    _activeTouch = touch;
    _startPoint = [touch locationInView:_overlayView];
    _currentPoint = _startPoint;
    _dragging = YES;
    [self updateSelectionPaths];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_ended || !_activeTouch || ![touches containsObject:_activeTouch]) return;
    _currentPoint = [_activeTouch locationInView:_overlayView];
    [self updateSelectionPaths];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_ended || !_activeTouch || ![touches containsObject:_activeTouch]) return;
    _currentPoint = [_activeTouch locationInView:_overlayView];
    [self updateSelectionPaths];
    CGRect rect = [self currentSelectionRect];
    [self markFinished];

    BOOL tiny = (rect.size.width < 8.0 && rect.size.height < 8.0);
    if (tiny) {
        _dragging = NO;
        [self updateSelectionPaths];
    }
    void (^callback)(BOOL, CGRect) = self.onFinish;
    self.onFinish = nil;
    if (callback) callback(tiny, tiny ? CGRectZero : rect);
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_ended || (_activeTouch && ![touches containsObject:_activeTouch])) return;
    [self markFinished];
    _dragging = NO;
    [self updateSelectionPaths];
    void (^callback)(BOOL, CGRect) = self.onFinish;
    self.onFinish = nil;
    if (callback) callback(YES, CGRectZero);
}

@end

@interface RCScreenSelectSession : NSObject
@property (nonatomic, strong) NSObject *lock;
@property (nonatomic, assign) BOOL resolved;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) CGRect rect;
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@end

@implementation RCScreenSelectSession
@end

static NSObject *rc_select_state_lock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static BOOL g_selectActive = NO;

static NSString *rc_screen_copy_all(void) {
    rc_select_dismiss_cc_if_visible();
    RCScreenSettle(1.5, NULL);
    NSString *error = nil;
    NSString *text = RCScreenAllText(&error);
    if (!text) return [NSString stringWithFormat:@"Error: %@\n", error ?: @"Couldn't read the screen"];
    if (!text.length) return @"Error: There's no text on the screen\n";
    rc_select_main_sync(^{
        [UIPasteboard generalPasteboard].string = text;
    });
    return [text stringByAppendingString:@"\n"];
}

static NSString *rc_screen_copy_rect(double timeout) {
    @synchronized (rc_select_state_lock()) {
        if (g_selectActive) return @"Error: A selection is already open\n";
        if (rc_select_is_locked()) return @"Error: Device is locked\n";
        g_selectActive = YES;
    }

    __block RCScreenSelectWindow *window = nil;
    __block RCScreenSelectViewController *vc = nil;
    void (^cleanup)(void) = ^{
        rc_select_main_sync(^{
            vc.onFinish = nil;
            window.hidden = YES;
            window.rootViewController = nil;
            window = nil;
            vc = nil;
        });
        @synchronized (rc_select_state_lock()) {
            g_selectActive = NO;
        }
    };

    @try {
        rc_select_dismiss_cc_if_visible();
        RCScreenSettle(1.5, NULL);

        if (rc_select_is_locked()) {
            cleanup();
            return @"Error: Device is locked\n";
        }

        UIImage *heldShot = RCScreenGrabImage();
        if (!heldShot) {
            cleanup();
            return @"Error: Couldn't capture the screen\n";
        }

        RCScreenSelectSession *session = [RCScreenSelectSession new];
        session.lock = [NSObject new];
        session.semaphore = dispatch_semaphore_create(0);

        __block BOOL hasScene = NO;
        rc_select_main_sync(^{
            UIWindowScene *scene = rc_select_window_scene();
            if (!scene) return;
            hasScene = YES;
            CGRect bounds = scene.coordinateSpace.bounds;
            if (CGRectIsEmpty(bounds)) bounds = [UIScreen mainScreen].bounds;

            window = [[RCScreenSelectWindow alloc] initWithWindowScene:scene];
            window.frame = bounds;
            window.windowLevel = UIWindowLevelAlert + 2600.0;
            window.backgroundColor = [UIColor clearColor];
            window.opaque = NO;
            window.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

            vc = [[RCScreenSelectViewController alloc] initWithShotSize:heldShot.size];
            vc.onFinish = ^(BOOL cancelled, CGRect rect) {
                @synchronized (session.lock) {
                    if (session.resolved) return;
                    session.resolved = YES;
                    session.cancelled = cancelled;
                    session.rect = rect;
                    dispatch_semaphore_signal(session.semaphore);
                }
            };
            window.rootViewController = vc;
            window.hidden = NO;
            [window makeKeyAndVisible];
        });

        if (!hasScene) {
            cleanup();
            return @"Error: No active display scene\n";
        }

        dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
        long waitResult = dispatch_semaphore_wait(session.semaphore, deadline);

        BOOL timedOut = NO;
        BOOL cancelled = NO;
        CGRect selectedRect = CGRectZero;
        @synchronized (session.lock) {
            if (waitResult != 0 && !session.resolved) {
                session.resolved = YES;
                timedOut = YES;
            } else {
                cancelled = session.cancelled;
                selectedRect = session.rect;
            }
        }

        if (timedOut) {
            rc_select_main_sync(^{ [vc markFinished]; });
            cleanup();
            return @"Error: Selection timed out\n";
        }
        if (cancelled) {
            cleanup();
            return @"Error: Selection cancelled\n";
        }

        rc_select_main_sync(^{
            [vc showPillTitle:@"Reading…" message:nil icon:@"text.viewfinder"];
        });

        NSString *error = nil;
        NSString *text = RCScreenTextInRect(heldShot, selectedRect, &error);
        if (!text || !text.length) {
            NSString *pillTitle = error ? @"Couldn't read text" : @"No text found";
            rc_select_main_sync(^{
                [vc showPillTitle:pillTitle message:nil icon:@"xmark.circle.fill"];
            });
            [NSThread sleepForTimeInterval:0.5];
            cleanup();
            return [NSString stringWithFormat:@"Error: %@\n", error ?: @"No text found"];
        }

        rc_select_main_sync(^{
            [UIPasteboard generalPasteboard].string = text;
            [vc showPillTitle:@"Copied" message:nil icon:@"checkmark.circle.fill"];
        });
        [NSThread sleepForTimeInterval:0.5];
        cleanup();
        return [text stringByAppendingString:@"\n"];
    } @catch (NSException *e) {
        SRLog(@"[Screen] screen copy rect exception: %@", e);
        cleanup();
        return [NSString stringWithFormat:@"Error: %@\n", e.reason ?: @"Selection failed"];
    }
}

NSString *RCScreenCopyCommand(NSString *args) {
    if ([NSThread isMainThread]) return @"Error: screen copy can't run on the main thread\n";

    NSString *trimmed = [args ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return rc_screen_copy_all();

    NSArray<NSString *> *words = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if (!words.count || ![[words[0] lowercaseString] isEqualToString:@"rect"] || words.count > 2) {
        return @"Usage: screen copy [rect [SECONDS]]\n";
    }

    double timeout = 20.0;
    if (words.count == 2) {
        double parsed = 0;
        NSScanner *scanner = [NSScanner scannerWithString:words[1]];
        if (![scanner scanDouble:&parsed] || !scanner.isAtEnd || !isfinite(parsed) || parsed <= 0) {
            return @"Usage: screen copy [rect [SECONDS]]\n";
        }
        timeout = MIN(MAX(parsed, 1.0), 120.0);
    }
    return rc_screen_copy_rect(timeout);
}
