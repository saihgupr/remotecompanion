#import "RCDevAnnotate.h"
#import "RCDevAnnotateAction.h"
#import "RCScreen.h"
#import "RCSpawn.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <errno.h>
#import <fcntl.h>
#import <signal.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

extern void SRLog(NSString *format, ...);
extern void SRLogMin(NSString *format, ...);

static void rc_dev_main_sync(dispatch_block_t block) {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static NSString *rc_dev_sh_quote(NSString *val) {
    if (!val || val.length == 0) return @"''";
    return [NSString stringWithFormat:@"'%@'", [val stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static const char *rc_dev_shell_path(void) {
    if (access("/var/jb/bin/sh", X_OK) == 0) return "/var/jb/bin/sh";
    if (access("/var/jb/usr/bin/sh", X_OK) == 0) return "/var/jb/usr/bin/sh";
    return "/bin/sh";
}

static int rc_dev_posix_spawn(pid_t *pid,
                              const char *path,
                              const posix_spawn_file_actions_t *file_actions,
                              char *const argv[],
                              char *const envp[]) {
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT);
#endif
    int ret = posix_spawn(pid, path, file_actions, &attr, argv, envp);
    posix_spawnattr_destroy(&attr);
    return ret;
}

static void rc_dev_move_fd_above_stdio(int *fd) {
    if (!fd || *fd < 0 || *fd > STDERR_FILENO) return;
    int moved = fcntl(*fd, F_DUPFD_CLOEXEC, 3);
    if (moved >= 0) {
        close(*fd);
        *fd = moved;
    }
}

static BOOL rc_dev_drain_fd(int *fd, NSMutableData *outData) {
    if (!fd || *fd < 0) return NO;
    BOOL readAny = NO;
    char buf[4096];
    while (true) {
        ssize_t n = read(*fd, buf, sizeof(buf));
        if (n > 0) {
            [outData appendBytes:buf length:(NSUInteger)n];
            readAny = YES;
        } else if (n == 0) {
            close(*fd);
            *fd = -1;
            break;
        } else if (errno == EINTR) {
            continue;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
            break;
        } else {
            close(*fd);
            *fd = -1;
            break;
        }
    }
    return readAny;
}

static BOOL rc_dev_is_locked(void) {
    __block BOOL locked = NO;
    rc_dev_main_sync(^{
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

static void rc_dev_dismiss_cc_if_visible(void) {
    rc_dev_main_sync(^{
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

static UIWindowScene *rc_dev_window_scene(void) {
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

static UIInterfaceOrientation rc_dev_active_orientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL activeSel = @selector(activeInterfaceOrientation);
    if ([app respondsToSelector:activeSel]) {
        return ((UIInterfaceOrientation (*)(id, SEL))objc_msgSend)(app, activeSel);
    }
    UIWindowScene *scene = rc_dev_window_scene();
    return scene ? scene.interfaceOrientation : UIInterfaceOrientationPortrait;
}

static CGFloat rc_dev_top_inset(UIWindowScene *scene, BOOL landscape) {
    if (landscape) return 12.0;
    CGFloat topInset = 0;
    if (scene.statusBarManager) {
        topInset = scene.statusBarManager.statusBarFrame.size.height;
    }
    for (UIWindow *w in scene.windows) {
        if (!w.hidden && w.safeAreaInsets.top > topInset) topInset = w.safeAreaInsets.top;
    }
    return topInset > 20.0 ? topInset : 20.0;
}

static CGFloat rc_dev_bottom_inset(UIWindowScene *scene, BOOL landscape) {
    CGFloat bottomInset = 0;
    for (UIWindow *w in scene.windows) {
        if (!w.hidden && w.safeAreaInsets.bottom > bottomInset) bottomInset = w.safeAreaInsets.bottom;
    }
    if (landscape) return bottomInset > 0 ? MIN(bottomInset, 21.0) : 12.0;
    return bottomInset > 0 ? bottomInset : 16.0;
}

// Secure window that can also become key so the inline UITextView opens the keyboard cleanly.
@interface RCDevAnnotateWindow : UIWindow
@end

@implementation RCDevAnnotateWindow
- (BOOL)_shouldCreateContextAsSecure {
    return YES;
}
- (BOOL)_canBecomeKeyWindow {
    return YES;
}
@end

@interface RCDevAnnotateViewController : UIViewController <UITextViewDelegate> {
    UIImage *_heldShot;
    UIView *_overlayView;
    UIImageView *_shotView;
    CAShapeLayer *_rectLayer;

    UIView *_barContainer;
    UIVisualEffectView *_blurView;
    UIButton *_cancelButton;
    UIView *_micPulseView;
    UIButton *_micButton;
    UITextView *_textView;
    UILabel *_placeholderLabel;
    UIButton *_sendButton;

    UITouch *_activeTouch;
    CGPoint _startPoint;
    CGPoint _currentPoint;
    BOOL _draggingNewRect;
    BOOL _hasSelection;
    CGRect _selectedRect;
    BOOL _ended;
    BOOL _dockTop;
    CGFloat _keyboardHeight;

    // Dictation subprocess state
    BOOL _dictating;
    BOOL _flushingFinalDictation;
    BOOL _loggedFirstPartial;
    NSString *_dictationErrorHint;
    NSUInteger _dictateGeneration;
    pid_t _dictatePid;
    int _dictateInFd;
    NSObject *_dictateLock;
    NSString *_committedPrefix;
    NSString *_currentDictationSegment;
}
@property (nonatomic, copy) void (^onFinish)(BOOL cancelled, CGRect selectedRect, CGSize overlaySize, NSString *text);
- (instancetype)initWithShot:(UIImage *)shot;
- (void)prepareForDismiss;
@end

@implementation RCDevAnnotateViewController

- (instancetype)initWithShot:(UIImage *)shot {
    self = [super init];
    if (self) {
        _heldShot = shot;
        _dictateLock = [NSObject new];
        _dictatePid = -1;
        _dictateInFd = -1;
        _committedPrefix = @"";
        _currentDictationSegment = @"";
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopDictationWaitSeconds:0.0];
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.view.multipleTouchEnabled = NO;

    _overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    _overlayView.backgroundColor = [UIColor blackColor];
    _overlayView.multipleTouchEnabled = NO;
    [self.view addSubview:_overlayView];

    _shotView = [[UIImageView alloc] initWithImage:_heldShot];
    _shotView.frame = _overlayView.bounds;
    _shotView.contentMode = UIViewContentModeScaleToFill;
    _shotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _shotView.userInteractionEnabled = NO;
    [_overlayView addSubview:_shotView];

    _rectLayer = [CAShapeLayer layer];
    _rectLayer.strokeColor = [UIColor colorWithRed:1.0 green:59.0/255.0 blue:48.0/255.0 alpha:1.0].CGColor;
    _rectLayer.fillColor = [UIColor colorWithRed:1.0 green:59.0/255.0 blue:48.0/255.0 alpha:0.08].CGColor;
    _rectLayer.lineWidth = 3.0;
    _rectLayer.shadowColor = [UIColor blackColor].CGColor;
    _rectLayer.shadowOpacity = 0.45;
    _rectLayer.shadowRadius = 2.0;
    _rectLayer.shadowOffset = CGSizeZero;
    [_overlayView.layer addSublayer:_rectLayer];

    [self buildComposerBar];
    [self layoutOverlayFrame];
    [self layoutComposerBarAnimated:NO];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];

    // Turn on microphone immediately when the overlay opens.
    [self startDictation];
}

- (void)buildComposerBar {
    _barContainer = [[UIView alloc] initWithFrame:CGRectZero];
    _barContainer.backgroundColor = [UIColor clearColor];
    _barContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    _barContainer.layer.shadowOpacity = 0.35;
    _barContainer.layer.shadowRadius = 14.0;
    _barContainer.layer.shadowOffset = CGSizeMake(0, 6);
    [_overlayView addSubview:_barContainer];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.layer.cornerRadius = 22.0;
    _blurView.layer.masksToBounds = YES;
    _blurView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    _blurView.layer.borderWidth = 1.0;
    [_barContainer addSubview:_blurView];

    UIView *content = _blurView.contentView;

    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *smallCfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    [_cancelButton setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:smallCfg] forState:UIControlStateNormal];
    _cancelButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    _cancelButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    _cancelButton.layer.cornerRadius = 17.0;
    [_cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:_cancelButton];

    _micPulseView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 34, 34)];
    _micPulseView.backgroundColor = [UIColor colorWithRed:1.0 green:59.0/255.0 blue:48.0/255.0 alpha:0.28];
    _micPulseView.layer.cornerRadius = 17.0;
    _micPulseView.userInteractionEnabled = NO;
    _micPulseView.alpha = 0.0;
    [content addSubview:_micPulseView];

    _micButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _micButton.layer.cornerRadius = 17.0;
    [_micButton addTarget:self action:@selector(micTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:_micButton];

    _textView = [[UITextView alloc] init];
    _textView.delegate = self;
    _textView.backgroundColor = [UIColor clearColor];
    _textView.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    _textView.textColor = [UIColor whiteColor];
    _textView.tintColor = [UIColor colorWithRed:1.0 green:59.0/255.0 blue:48.0/255.0 alpha:1.0];
    _textView.keyboardAppearance = UIKeyboardAppearanceDark;
    _textView.textContainerInset = UIEdgeInsetsMake(7, 4, 7, 4);
    _textView.textContainer.lineFragmentPadding = 0;
    _textView.scrollEnabled = NO;

    UIToolbar *kbToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 40)];
    kbToolbar.barStyle = UIBarStyleBlack;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboardTapped)];
    kbToolbar.items = @[flex, done];
    _textView.inputAccessoryView = kbToolbar;
    [content addSubview:_textView];

    _placeholderLabel = [[UILabel alloc] init];
    _placeholderLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    _placeholderLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.52];
    _placeholderLabel.userInteractionEnabled = NO;
    [_textView addSubview:_placeholderLabel];

    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *sendCfg = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightMedium];
    [_sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill" withConfiguration:sendCfg] forState:UIControlStateNormal];
    _sendButton.tintColor = [UIColor colorWithRed:1.0 green:59.0/255.0 blue:48.0/255.0 alpha:1.0];
    [_sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:_sendButton];

    [self updateMicAppearance];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutOverlayFrame];
    [self updateRectLayer];
    [self layoutComposerBarAnimated:NO];
}

- (void)layoutOverlayFrame {
    CGSize vb = self.view.bounds.size;
    if (vb.width <= 0 || vb.height <= 0) return;

    UIInterfaceOrientation active = rc_dev_active_orientation();
    UIWindowScene *scene = self.view.window.windowScene ?: rc_dev_window_scene();
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
        _overlayView.transform = CGAffineTransformMakeRotation(angle);
        _overlayView.bounds = CGRectMake(0, 0, vb.height, vb.width);
        _overlayView.center = CGPointMake(vb.width * 0.5, vb.height * 0.5);
    } else if (sceneOrientation != UIInterfaceOrientationUnknown && sceneOrientation != active) {
        _overlayView.transform = CGAffineTransformMakeRotation(M_PI);
        _overlayView.bounds = CGRectMake(0, 0, vb.width, vb.height);
        _overlayView.center = CGPointMake(vb.width * 0.5, vb.height * 0.5);
    } else {
        _overlayView.transform = CGAffineTransformIdentity;
        _overlayView.frame = self.view.bounds;
    }
    _shotView.frame = _overlayView.bounds;
    _rectLayer.frame = _overlayView.bounds;
}

- (CGFloat)composerHeightForTextWidth:(CGFloat)textWidth {
    if (textWidth <= 0) return 48.0;
    CGSize fit = [_textView sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)];
    CGFloat clampedTextH = MIN(MAX(ceil(fit.height), 34.0), 82.0);
    _textView.scrollEnabled = (fit.height > 82.0);
    return MAX(48.0, clampedTextH + 14.0);
}

- (CGRect)bottomBarFrameForSize:(CGSize)barSize overlaySize:(CGSize)overlaySize scene:(UIWindowScene *)scene landscape:(BOOL)landscape {
    CGFloat x = round((overlaySize.width - barSize.width) * 0.5);
    CGFloat bottomInset = rc_dev_bottom_inset(scene, landscape);
    CGFloat y = overlaySize.height - bottomInset - barSize.height;
    return CGRectMake(x, y, barSize.width, barSize.height);
}

- (CGRect)topBarFrameForSize:(CGSize)barSize overlaySize:(CGSize)overlaySize scene:(UIWindowScene *)scene landscape:(BOOL)landscape {
    CGFloat x = round((overlaySize.width - barSize.width) * 0.5);
    CGFloat topInset = rc_dev_top_inset(scene, landscape);
    return CGRectMake(x, topInset + 8.0, barSize.width, barSize.height);
}

- (void)layoutComposerBarAnimated:(BOOL)animated {
    CGSize overlaySize = _overlayView.bounds.size;
    if (overlaySize.width <= 0 || overlaySize.height <= 0) return;

    UIWindowScene *scene = self.view.window.windowScene ?: rc_dev_window_scene();
    BOOL landscape = UIInterfaceOrientationIsLandscape(rc_dev_active_orientation());

    CGFloat barW = MIN(overlaySize.width - 24.0, 520.0);
    // Left controls: 10 + 34 (cancel) + 6 + 34 (mic) + 8 = 92; Right: 8 + 34 (send) + 8 = 50
    CGFloat textWidth = MAX(60.0, barW - 92.0 - 50.0);
    CGFloat barH = [self composerHeightForTextWidth:textWidth];
    CGSize barSize = CGSizeMake(barW, barH);

    CGRect targetFrame;
    if (_keyboardHeight > 0.5) {
        CGFloat x = round((overlaySize.width - barW) * 0.5);
        CGFloat topLimit = rc_dev_top_inset(scene, landscape) + 8.0;
        CGFloat y = MAX(topLimit, overlaySize.height - _keyboardHeight - 10.0 - barH);
        targetFrame = CGRectMake(x, y, barW, barH);
    } else {
        CGRect bottomFrame = [self bottomBarFrameForSize:barSize overlaySize:overlaySize scene:scene landscape:landscape];
        if (_hasSelection && CGRectIntersectsRect(CGRectInset(_selectedRect, -6.0, -6.0), bottomFrame)) {
            _dockTop = YES;
        } else {
            _dockTop = NO;
        }
        targetFrame = _dockTop
            ? [self topBarFrameForSize:barSize overlaySize:overlaySize scene:scene landscape:landscape]
            : bottomFrame;
    }

    void (^applyFrames)(void) = ^{
        self->_barContainer.frame = targetFrame;
        self->_blurView.frame = self->_barContainer.bounds;

        CGFloat btnY = round((barH - 34.0) * 0.5);
        self->_cancelButton.frame = CGRectMake(10.0, btnY, 34.0, 34.0);
        self->_micButton.frame = CGRectMake(50.0, btnY, 34.0, 34.0);
        self->_micPulseView.center = self->_micButton.center;
        self->_sendButton.frame = CGRectMake(barW - 42.0, btnY, 34.0, 34.0);

        CGFloat textH = barH - 14.0;
        self->_textView.frame = CGRectMake(92.0, 7.0, textWidth, textH);
        self->_placeholderLabel.frame = CGRectMake(4.0, 7.0, textWidth - 8.0, 20.0);
    };

    if (animated) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:applyFrames completion:nil];
    } else {
        applyFrames();
    }
}

- (void)updateMicAppearance {
    UIImageSymbolConfiguration *micCfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    if (_dictating) {
        [_micButton setImage:[UIImage systemImageNamed:@"mic.fill" withConfiguration:micCfg] forState:UIControlStateNormal];
        _micButton.tintColor = [UIColor colorWithRed:1.0 green:59.0/255.0 blue:48.0/255.0 alpha:1.0];
        _micButton.backgroundColor = [UIColor colorWithRed:1.0 green:59.0/255.0 blue:48.0/255.0 alpha:0.22];
        _micPulseView.alpha = 0.35;
        _placeholderLabel.text = @"Listening… drag to circle";
    } else {
        [_micButton setImage:[UIImage systemImageNamed:@"mic.slash.fill" withConfiguration:micCfg] forState:UIControlStateNormal];
        _micButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.6];
        _micButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        _micPulseView.transform = CGAffineTransformIdentity;
        _micPulseView.alpha = 0.0;
        _placeholderLabel.text = _dictationErrorHint ?: @"Type a note…";
    }
    _placeholderLabel.hidden = (_textView.text.length > 0);
}

#pragma mark - Keyboard

- (void)keyboardWillChangeFrame:(NSNotification *)note {
    CGRect endScreen = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIWindow *win = self.view.window;
    if (!win) return;
    CGRect endWin = [win convertRect:endScreen fromWindow:nil];
    CGRect endOverlay = [_overlayView convertRect:endWin fromView:win];
    CGRect overlap = CGRectIntersection(_overlayView.bounds, endOverlay);
    CGFloat newKbdH = (!CGRectIsNull(overlap) && overlap.size.height > 10.0) ? overlap.size.height : 0.0;
    if (fabs(newKbdH - _keyboardHeight) < 1.0) return;
    _keyboardHeight = newKbdH;
    [self layoutComposerBarAnimated:YES];
}

- (void)keyboardWillHide:(NSNotification *)note {
    if (_keyboardHeight <= 0.0) return;
    _keyboardHeight = 0.0;
    [self layoutComposerBarAnimated:YES];
}

- (void)dismissKeyboardTapped {
    [_textView resignFirstResponder];
}

#pragma mark - Selection Rectangle

- (CGRect)activeDrawRect {
    CGRect raw = CGRectMake(_startPoint.x,
                            _startPoint.y,
                            _currentPoint.x - _startPoint.x,
                            _currentPoint.y - _startPoint.y);
    CGRect clamped = CGRectIntersection(CGRectStandardize(raw), _overlayView.bounds);
    return CGRectIsNull(clamped) ? CGRectZero : clamped;
}

- (void)updateRectLayer {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect rect = _draggingNewRect ? [self activeDrawRect] : (_hasSelection ? _selectedRect : CGRectZero);
    if (rect.size.width > 0 && rect.size.height > 0) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:4.0];
        _rectLayer.path = path.CGPath;
    } else {
        _rectLayer.path = NULL;
    }
    [CATransaction commit];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_ended || _activeTouch) return;
    UITouch *touch = [touches anyObject];
    if (!touch) return;
    CGPoint pt = [touch locationInView:_overlayView];
    if ([touch.view isDescendantOfView:_barContainer] || CGRectContainsPoint(_barContainer.frame, pt)) {
        return;
    }
    _activeTouch = touch;
    _startPoint = pt;
    _currentPoint = pt;
    _draggingNewRect = YES;
    [self updateRectLayer];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_ended || !_activeTouch || ![touches containsObject:_activeTouch]) return;
    _currentPoint = [_activeTouch locationInView:_overlayView];
    [self updateRectLayer];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_ended || !_activeTouch || ![touches containsObject:_activeTouch]) return;
    _currentPoint = [_activeTouch locationInView:_overlayView];
    _activeTouch = nil;
    _draggingNewRect = NO;

    CGRect drawn = [self activeDrawRect];
    if (drawn.size.width >= 8.0 || drawn.size.height >= 8.0) {
        _hasSelection = YES;
        _selectedRect = drawn;
        [self updateRectLayer];
        [self layoutComposerBarAnimated:YES];
    } else {
        // Tiny tap: keep any existing rectangle and just dismiss keyboard if active.
        if (_textView.isFirstResponder) {
            [_textView resignFirstResponder];
        }
        [self updateRectLayer];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_ended || (_activeTouch && ![touches containsObject:_activeTouch])) return;
    _activeTouch = nil;
    _draggingNewRect = NO;
    [self updateRectLayer];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidBeginEditing:(UITextView *)textView {
    _dictationErrorHint = nil;
    if (_dictating) {
        [self pauseDictation];
    } else {
        [self updateMicAppearance];
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    _placeholderLabel.hidden = (textView.text.length > 0);
    _committedPrefix = textView.text ?: @"";
    _currentDictationSegment = @"";
    [self layoutComposerBarAnimated:NO];
}

#pragma mark - Dictation Bridge (rc-dictate)

- (NSString *)joinPrefix:(NSString *)prefix withSpeech:(NSString *)speech {
    NSString *p = prefix ?: @"";
    NSString *s = speech ?: @"";
    if (p.length == 0) return s;
    if (s.length == 0) return p;
    BOOL endsWithSpace = [[NSCharacterSet whitespaceAndNewlineCharacterSet]
        characterIsMember:[p characterAtIndex:p.length - 1]];
    return endsWithSpace ? [p stringByAppendingString:s] : [NSString stringWithFormat:@"%@ %@", p, s];
}

- (void)startDictation {
    if (_ended) return;
    _loggedFirstPartial = NO;
    _dictationErrorHint = nil;
    NSString *toolPath = rc_tool_path(@"rc-dictate");
    if (!toolPath) {
        SRLogMin(@"[DevAnnotate] rc-dictate not found");
        _dictating = NO;
        [self updateMicAppearance];
        return;
    }

    [self stopDictationWaitSeconds:0.0];

    int inPipe[2] = { -1, -1 };
    int outPipe[2] = { -1, -1 };
    if (pipe(inPipe) != 0) {
        _dictating = NO;
        [self updateMicAppearance];
        return;
    }
    if (pipe(outPipe) != 0) {
        close(inPipe[0]);
        close(inPipe[1]);
        _dictating = NO;
        [self updateMicAppearance];
        return;
    }

    int devNull = open("/dev/null", O_WRONLY);
    rc_dev_move_fd_above_stdio(&inPipe[0]);
    rc_dev_move_fd_above_stdio(&inPipe[1]);
    rc_dev_move_fd_above_stdio(&outPipe[0]);
    rc_dev_move_fd_above_stdio(&outPipe[1]);
    rc_dev_move_fd_above_stdio(&devNull);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, inPipe[0], STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    if (devNull >= 0) {
        posix_spawn_file_actions_adddup2(&actions, devNull, STDERR_FILENO);
        if (devNull > STDERR_FILENO) posix_spawn_file_actions_addclose(&actions, devNull);
    }
    if (inPipe[0] > STDERR_FILENO) posix_spawn_file_actions_addclose(&actions, inPipe[0]);
    if (inPipe[1] > STDERR_FILENO) posix_spawn_file_actions_addclose(&actions, inPipe[1]);
    if (outPipe[0] > STDERR_FILENO) posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    if (outPipe[1] > STDERR_FILENO) posix_spawn_file_actions_addclose(&actions, outPipe[1]);

    extern char **environ;
    char *argv[] = { (char *)toolPath.fileSystemRepresentation, NULL };
    pid_t pid = -1;
    int err = rc_dev_posix_spawn(&pid, argv[0], &actions, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (devNull >= 0) close(devNull);
    close(inPipe[0]);
    close(outPipe[1]);

    if (err != 0 || pid <= 0) {
        SRLogMin(@"[DevAnnotate] Failed to spawn rc-dictate: %d", err);
        close(inPipe[1]);
        close(outPipe[0]);
        _dictating = NO;
        [self updateMicAppearance];
        return;
    }

#ifdef F_SETNOSIGPIPE
    fcntl(inPipe[1], F_SETNOSIGPIPE, 1);
#endif

    NSUInteger gen = 0;
    @synchronized (_dictateLock) {
        _dictateGeneration++;
        gen = _dictateGeneration;
        _dictatePid = pid;
        _dictateInFd = inPipe[1];
        _committedPrefix = _textView.text ?: @"";
        _currentDictationSegment = @"";
    }

    _dictating = YES;
    [self updateMicAppearance];

    int readFd = outPipe[0];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableData *buf = [NSMutableData data];
        char chunk[2048];
        while (true) {
            ssize_t n = read(readFd, chunk, sizeof(chunk));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) break;
            [buf appendBytes:chunk length:(NSUInteger)n];
            while (true) {
                const uint8_t *bytes = buf.bytes;
                NSUInteger len = buf.length;
                NSUInteger nl = NSNotFound;
                for (NSUInteger i = 0; i < len; i++) {
                    if (bytes[i] == '\n') { nl = i; break; }
                }
                if (nl == NSNotFound) break;
                NSData *lineData = [buf subdataWithRange:NSMakeRange(0, nl)];
                [buf replaceBytesInRange:NSMakeRange(0, nl + 1) withBytes:NULL length:0];
                if (lineData.length == 0) continue;
                id parsed = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
                if (![parsed isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *event = (NSDictionary *)parsed;
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    [strongSelf handleDictateEvent:event generation:gen];
                });
            }
        }
        close(readFd);
        int status = 0;
        waitpid(pid, &status, 0);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            @synchronized (strongSelf->_dictateLock) {
                if (strongSelf->_dictateGeneration == gen) {
                    strongSelf->_dictatePid = -1;
                    if (strongSelf->_dictateInFd >= 0) {
                        close(strongSelf->_dictateInFd);
                        strongSelf->_dictateInFd = -1;
                    }
                    if (strongSelf->_dictating) {
                        strongSelf->_dictating = NO;
                        [strongSelf updateMicAppearance];
                    }
                }
            }
        });
    });
}

- (void)handleDictateEvent:(NSDictionary *)event generation:(NSUInteger)gen {
    @synchronized (_dictateLock) {
        if (_dictateGeneration != gen) return;
    }
    if (_ended && !_flushingFinalDictation) return;

    NSString *type = [event[@"type"] description] ?: @"";
    if ([type isEqualToString:@"ready"]) {
        SRLogMin(@"[DevAnnotate] Dictation ready (onDevice=%@ locale=%@)", event[@"onDevice"], event[@"locale"]);
    } else if ([type isEqualToString:@"level"]) {
        if (!_dictating) return;
        double clamped = MIN(1.0, MAX(0.0, [event[@"v"] doubleValue]));
        CGFloat scale = 1.0 + (CGFloat)clamped * 0.42;
        CGFloat alpha = 0.22 + (CGFloat)clamped * 0.58;
        UIColor *micBg = [UIColor colorWithRed:1.0 green:59.0/255.0 blue:48.0/255.0 alpha:(CGFloat)(0.22 + clamped * 0.36)];
        [UIView animateWithDuration:0.08 animations:^{
            self->_micPulseView.transform = CGAffineTransformMakeScale(scale, scale);
            self->_micPulseView.alpha = alpha;
            self->_micButton.backgroundColor = micBg;
        }];
    } else if ([type isEqualToString:@"partial"] || [type isEqualToString:@"final"]) {
        if (_textView.isFirstResponder) return;
        NSString *speech = [event[@"text"] isKindOfClass:[NSString class]] ? event[@"text"] : @"";
        if (!_loggedFirstPartial && speech.length > 0) {
            _loggedFirstPartial = YES;
            SRLogMin(@"[DevAnnotate] Dictation received speech (%lu chars)", (unsigned long)speech.length);
        }
        _currentDictationSegment = speech;
        NSString *combined = [self joinPrefix:_committedPrefix withSpeech:speech];
        _textView.text = combined;
        _placeholderLabel.hidden = (combined.length > 0);
        if ([type isEqualToString:@"final"]) {
            _committedPrefix = combined;
            _currentDictationSegment = @"";
        }
        [self layoutComposerBarAnimated:NO];
        if (combined.length > 0 && _textView.scrollEnabled) {
            [_textView scrollRangeToVisible:NSMakeRange(combined.length - 1, 1)];
        }
    } else if ([type isEqualToString:@"error"]) {
        NSString *msg = [event[@"message"] description] ?: @"Dictation error";
        SRLogMin(@"[DevAnnotate] Dictation error: %@", msg);
        _dictationErrorHint = @"Mic unavailable — tap to type";
        [self pauseDictation];
    }
}

- (void)stopDictationWaitSeconds:(NSTimeInterval)waitSeconds {
    pid_t pid = -1;
    int inFd = -1;
    @synchronized (_dictateLock) {
        pid = _dictatePid;
        inFd = _dictateInFd;
        _dictateInFd = -1;
        if (waitSeconds <= 0) {
            _dictateGeneration++;
            _dictatePid = -1;
        }
    }
    if (inFd >= 0) {
        const char *stopMsg = "stop\n";
        write(inFd, stopMsg, 5);
        close(inFd);
    }
    if (pid > 0) {
        if (waitSeconds > 0) {
            CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + waitSeconds;
            while (CFAbsoluteTimeGetCurrent() < deadline) {
                pid_t curPid = -1;
                @synchronized (_dictateLock) {
                    curPid = _dictatePid;
                }
                if (curPid <= 0) {
                    pid = -1;
                    break;
                }
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            }
            // Let any final queued main-thread transcript event apply before reading _textView.
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        if (pid > 0) {
            kill(pid, SIGTERM);
            @synchronized (_dictateLock) {
                _dictateGeneration++;
                _dictatePid = -1;
            }
        }
    }
}

- (void)pauseDictation {
    _dictating = NO;
    [self stopDictationWaitSeconds:0.15];
    _committedPrefix = _textView.text ?: @"";
    _currentDictationSegment = @"";
    [self updateMicAppearance];
}

#pragma mark - Actions

- (void)micTapped {
    if (_ended) return;
    if (_dictating) {
        [self pauseDictation];
    } else {
        if (_textView.isFirstResponder) {
            [_textView resignFirstResponder];
        }
        [self startDictation];
    }
}

- (void)cancelTapped {
    if (_ended) return;
    _ended = YES;
    _dictating = NO;
    [self stopDictationWaitSeconds:0.0];
    [self prepareForDismiss];
    void (^cb)(BOOL, CGRect, CGSize, NSString *) = self.onFinish;
    self.onFinish = nil;
    if (cb) cb(YES, CGRectZero, CGSizeZero, @"");
}

- (void)sendTapped {
    if (_ended) return;
    _ended = YES;
    if (_dictating) {
        _dictating = NO;
        [self updateMicAppearance];
        _flushingFinalDictation = YES;
        [self stopDictationWaitSeconds:0.65];
        _flushingFinalDictation = NO;
    } else {
        [self stopDictationWaitSeconds:0.0];
    }
    NSString *finalText = [_textView.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    CGRect finalRect = _hasSelection ? _selectedRect : CGRectZero;
    CGSize overlaySize = _overlayView.bounds.size;
    SRLogMin(@"[DevAnnotate] Sending (textLen=%lu, hasRect=%d)", (unsigned long)finalText.length, !CGRectIsEmpty(finalRect));

    [self prepareForDismiss];
    void (^cb)(BOOL, CGRect, CGSize, NSString *) = self.onFinish;
    self.onFinish = nil;
    if (cb) cb(NO, finalRect, overlaySize, finalText);
}

- (void)prepareForDismiss {
    _ended = YES;
    _dictating = NO;
    _activeTouch = nil;
    [self stopDictationWaitSeconds:0.0];
    self.view.userInteractionEnabled = NO;
    if (_textView.isFirstResponder) {
        [_textView resignFirstResponder];
    }
    [self.view endEditing:YES];
}

@end

@interface RCDevAnnotateSession : NSObject
@property (nonatomic, strong) NSObject *lock;
@property (nonatomic, assign) BOOL resolved;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) CGRect selectedRect;
@property (nonatomic, assign) CGSize overlaySize;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@end

@implementation RCDevAnnotateSession
@end

static NSObject *rc_dev_state_lock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static BOOL g_devAnnotateActive = NO;

static NSData *rc_dev_render_annotated_png(UIImage *heldShot, CGRect selectedRect, CGSize overlaySize) {
    if (!heldShot) return nil;
    CGFloat srcW = heldShot.size.width;
    CGFloat srcH = heldShot.size.height;
    if (srcW <= 0 || srcH <= 0) return nil;

    CGFloat maxDim = MAX(srcW, srcH);
    CGFloat ratio = (maxDim > 1600.0) ? (1600.0 / maxDim) : 1.0;
    CGSize outSize = CGSizeMake(round(srcW * ratio), round(srcH * ratio));

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = YES;
    UIImage *rendered = [[[UIGraphicsImageRenderer alloc] initWithSize:outSize format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [heldShot drawInRect:CGRectMake(0, 0, outSize.width, outSize.height)];

        if (!CGRectIsEmpty(selectedRect) && selectedRect.size.width >= 4.0 && selectedRect.size.height >= 4.0 &&
            overlaySize.width > 0 && overlaySize.height > 0) {
            CGFloat sx = outSize.width / overlaySize.width;
            CGFloat sy = outSize.height / overlaySize.height;
            CGRect box = CGRectMake(selectedRect.origin.x * sx,
                                    selectedRect.origin.y * sy,
                                    selectedRect.size.width * sx,
                                    selectedRect.size.height * sy);
            CGFloat strokeW = MAX(4.0, round(MAX(outSize.width, outSize.height) / 320.0));
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:6.0];
            [[UIColor colorWithWhite:0.0 alpha:0.45] setStroke];
            path.lineWidth = strokeW + 2.5;
            [path stroke];
            [[UIColor colorWithRed:1.0 green:59.0/255.0 blue:48.0/255.0 alpha:1.0] setStroke];
            path.lineWidth = strokeW;
            [path stroke];
        }
    }];
    return rendered ? UIImagePNGRepresentation(rendered) : nil;
}

static NSDictionary *rc_dev_parse_last_json_line(NSString *output) {
    if (!output.length) return nil;
    NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSInteger i = (NSInteger)lines.count - 1; i >= 0; i--) {
        NSString *line = [lines[(NSUInteger)i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![line hasPrefix:@"{"]) continue;
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([parsed isKindOfClass:[NSDictionary class]]) return (NSDictionary *)parsed;
    }
    return nil;
}

static void rc_dev_deliver_over_ssh(NSDictionary *targetHost,
                                    NSDictionary *components,
                                    UIImage *heldShot,
                                    CGRect selectedRect,
                                    CGSize overlaySize,
                                    NSString *text,
                                    void (^showToast)(NSString *title, NSString *subtitle, NSString *icon)) {
    NSString *editorDisplay = [RCDevAnnotateAction editorDisplayNameForComponents:components];
    void (^notify)(NSString *, NSString *, NSString *) = ^(NSString *title, NSString *sub, NSString *icon) {
        if (showToast) showToast(title, sub, icon);
    };

    NSData *pngData = rc_dev_render_annotated_png(heldShot, selectedRect, overlaySize);
    if (!pngData) {
        notify(@"Send Failed", @"Couldn't render annotated screenshot", @"xmark.circle.fill");
        return;
    }

    NSDictionary *preset = [RCDevAnnotateAction presetForId:components[@"editor"]];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"image_b64"] = [pngData base64EncodedStringWithOptions:0] ?: @"";
    payload[@"text"] = text ?: @"";
    payload[@"strategy"] = preset[@"strategy"] ?: @"clipboard_paste";
    payload[@"bundle_id"] = preset[@"bundleId"] ?: @"";
    payload[@"app_name"] = preset[@"appName"] ?: @"";
    payload[@"custom_app"] = components[@"customApp"] ?: @"";
    payload[@"auto_send"] = components[@"autoSend"] ?: @YES;
    payload[@"delivery"] = preset[@"delivery"] ?: @"queue";
    payload[@"project_dir"] = components[@"projectDir"] ?: @"";
    payload[@"image_paste_delay_ms"] = preset[@"imagePasteDelayMs"] ?: @450;
    payload[@"submit_key"] = preset[@"submitKey"] ?: @"return";

    NSData *stdinData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!stdinData) {
        notify(@"Send Failed", @"Couldn't encode payload", @"xmark.circle.fill");
        return;
    }

    NSString *host = targetHost[@"host"] ?: @"";
    NSString *user = targetHost[@"user"] ?: @"mobile";
    NSNumber *portNum = targetHost[@"port"] ?: @22;
    NSInteger port = [portNum integerValue] > 0 ? [portNum integerValue] : 22;
    NSString *authType = targetHost[@"authType"] ?: @"password";
    NSString *password = targetHost[@"password"] ?: @"";
    NSString *keyPath = targetHost[@"keyPath"] ?: @"";

    NSString *targetDestination = user.length > 0 ? [NSString stringWithFormat:@"%@@%@", user, host] : host;
    NSString *scriptB64 = [RCDevAnnotateAction deliverPythonScriptBase64];
    NSString *remoteCmd = [NSString stringWithFormat:
        @"P=$(command -v python3 2>/dev/null); "
        @"if [ -z \"$P\" ]; then for d in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do [ -x \"$d\" ] && P=\"$d\" && break; done; fi; "
        @"[ -n \"$P\" ] || { echo '{\"ok\":false,\"error\":\"python3 not found on Mac\"}'; exit 1; }; "
        @"exec \"$P\" -c 'import base64; exec(base64.b64decode(\"%@\"))'",
        scriptB64];

    NSString *fullSSHCmd = nil;
    BOOL useSSHPass = NO;
    if ([authType isEqualToString:@"key"] && keyPath.length > 0) {
        NSString *effectiveKeyPath = [keyPath stringByExpandingTildeInPath];
        fullSSHCmd = [NSString stringWithFormat:@"ssh -i %@ -p %ld -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 %@ %@",
                      rc_dev_sh_quote(effectiveKeyPath),
                      (long)port,
                      rc_dev_sh_quote(targetDestination),
                      rc_dev_sh_quote(remoteCmd)];
    } else if (password.length > 0) {
        useSSHPass = YES;
        fullSSHCmd = [NSString stringWithFormat:@"sshpass -e ssh -p %ld -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 %@ %@",
                      (long)port,
                      rc_dev_sh_quote(targetDestination),
                      rc_dev_sh_quote(remoteCmd)];
    } else {
        fullSSHCmd = [NSString stringWithFormat:@"ssh -p %ld -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 %@ %@",
                      (long)port,
                      rc_dev_sh_quote(targetDestination),
                      rc_dev_sh_quote(remoteCmd)];
    }

    int inPipe[2] = { -1, -1 };
    int outPipe[2] = { -1, -1 };
    if (pipe(inPipe) != 0) {
        notify(@"Send Failed", @"Couldn't create pipe", @"xmark.circle.fill");
        return;
    }
    if (pipe(outPipe) != 0) {
        close(inPipe[0]);
        close(inPipe[1]);
        notify(@"Send Failed", @"Couldn't create pipe", @"xmark.circle.fill");
        return;
    }

    rc_dev_move_fd_above_stdio(&inPipe[0]);
    rc_dev_move_fd_above_stdio(&inPipe[1]);
    rc_dev_move_fd_above_stdio(&outPipe[0]);
    rc_dev_move_fd_above_stdio(&outPipe[1]);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, inPipe[0], STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDERR_FILENO);
    if (inPipe[0] > STDERR_FILENO) posix_spawn_file_actions_addclose(&actions, inPipe[0]);
    if (inPipe[1] > STDERR_FILENO) posix_spawn_file_actions_addclose(&actions, inPipe[1]);
    if (outPipe[0] > STDERR_FILENO) posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    if (outPipe[1] > STDERR_FILENO) posix_spawn_file_actions_addclose(&actions, outPipe[1]);

    NSString *basePath = @"/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
    extern char **environ;
    NSMutableArray<NSString *> *envArray = [NSMutableArray array];
    for (char **env = environ; *env != NULL; env++) {
        NSString *envStr = [NSString stringWithUTF8String:*env];
        if (envStr && ![envStr hasPrefix:@"PATH="] && ![envStr hasPrefix:@"SSHPASS="]) {
            [envArray addObject:envStr];
        }
    }
    [envArray addObject:[NSString stringWithFormat:@"PATH=%@", basePath]];
    if (useSSHPass && password.length > 0) {
        [envArray addObject:[NSString stringWithFormat:@"SSHPASS=%@", password]];
    }
    char **newEnviron = malloc(sizeof(char *) * (envArray.count + 1));
    for (NSUInteger i = 0; i < envArray.count; i++) {
        newEnviron[i] = strdup([envArray[i] UTF8String]);
    }
    newEnviron[envArray.count] = NULL;

    pid_t pid = -1;
    const char *sh = rc_dev_shell_path();
    char *args[] = { (char *)sh, "-c", (char *)[fullSSHCmd UTF8String], NULL };
    int spawnErr = rc_dev_posix_spawn(&pid, sh, &actions, args, newEnviron);
    posix_spawn_file_actions_destroy(&actions);

    for (NSUInteger i = 0; i < envArray.count; i++) {
        if (newEnviron[i]) {
            memset(newEnviron[i], 0, strlen(newEnviron[i]));
            free(newEnviron[i]);
        }
    }
    free(newEnviron);

    close(inPipe[0]);
    close(outPipe[1]);

    if (spawnErr != 0 || pid <= 0) {
        close(inPipe[1]);
        close(outPipe[0]);
        SRLogMin(@"[DevAnnotate] SSH spawn failed: %d", spawnErr);
        notify(@"Send Failed", @"Couldn't start ssh", @"xmark.circle.fill");
        return;
    }

#ifdef F_SETNOSIGPIPE
    fcntl(inPipe[1], F_SETNOSIGPIPE, 1);
#endif

    // Write payload on a separate queue so large images never deadlock stdout reading.
    int writeFd = inPipe[1];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const uint8_t *bytes = stdinData.bytes;
        NSUInteger total = stdinData.length;
        NSUInteger offset = 0;
        while (offset < total) {
            ssize_t written = write(writeFd, bytes + offset, total - offset);
            if (written > 0) {
                offset += (NSUInteger)written;
            } else if (written < 0 && errno == EINTR) {
                continue;
            } else {
                break;
            }
        }
        close(writeFd);
    });

    int readFd = outPipe[0];
    int flags = fcntl(readFd, F_GETFL);
    if (flags >= 0) fcntl(readFd, F_SETFL, flags | O_NONBLOCK);

    NSMutableData *outData = [NSMutableData data];
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 20.0;
    BOOL exited = NO;
    int status = 0;
    // Read without poll(), which SpringBoard's sandbox refuses on pipes.
    while (readFd >= 0) {
        if (CFAbsoluteTimeGetCurrent() >= deadline) break;
        if (rc_dev_drain_fd(&readFd, outData)) continue;
        if (!exited && waitpid(pid, &status, WNOHANG) == pid) {
            exited = YES;
            rc_dev_drain_fd(&readFd, outData);
            break;
        }
        usleep(20000);
    }
    if (readFd >= 0) {
        close(readFd);
        readFd = -1;
    }

    while (!exited) {
        pid_t r = waitpid(pid, &status, WNOHANG);
        if (r == pid) {
            exited = YES;
            break;
        }
        if (r < 0 && errno != EINTR) break;
        if (CFAbsoluteTimeGetCurrent() >= deadline) break;
        usleep(20000);
    }

    if (!exited) {
        kill(pid, SIGTERM);
        for (int i = 0; i < 20 && !exited; i++) {
            if (waitpid(pid, &status, WNOHANG) == pid) exited = YES;
            else usleep(20000);
        }
        if (!exited) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
        }
        SRLogMin(@"[DevAnnotate] SSH delivery timed out to %@", host);
        notify(@"Send Failed", @"Timed out reaching Mac", @"xmark.circle.fill");
        return;
    }

    int exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1;

    NSString *outStr = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
    NSDictionary *res = rc_dev_parse_last_json_line(outStr);
    if (res && [res[@"ok"] boolValue]) {
        NSString *detail = [res[@"detail"] isKindOfClass:[NSString class]] ? res[@"detail"] : nil;
        BOOL autoSend = components[@"autoSend"] ? [components[@"autoSend"] boolValue] : YES;
        NSString *title = [NSString stringWithFormat:@"%@ %@", autoSend ? @"Sent to" : @"Pasted to", editorDisplay];
        NSString *subtitle = nil;
        if (detail.length > 0 && ![detail isEqualToString:editorDisplay]) {
            if ([preset[@"strategy"] isEqualToString:@"opencode_api"] && autoSend) {
                subtitle = [NSString stringWithFormat:@"Session: %@", detail];
            } else {
                subtitle = detail;
            }
        }
        SRLogMin(@"[DevAnnotate] %@ (%@)", title, subtitle ?: @"ok");
        notify(title, subtitle, @"checkmark.circle.fill");
    } else {
        NSString *errMsg = [res[@"error"] isKindOfClass:[NSString class]] ? res[@"error"] : nil;
        if (!errMsg.length) {
            NSString *trimmed = [outStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *lastLine = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] lastObject] ?: @"";
            errMsg = lastLine.length ? [lastLine substringToIndex:MIN(lastLine.length, (NSUInteger)120)]
                                     : [NSString stringWithFormat:@"SSH failed (%d)", exitCode];
        }
        SRLogMin(@"[DevAnnotate] Delivery failed (%d): %@", exitCode, outStr);
        notify(@"Send Failed", errMsg, @"xmark.circle.fill");
    }
}

NSString *RCDevAnnotateCommand(NSString *cmd,
                               NSDictionary *config,
                               void (^showToast)(NSString *title, NSString *subtitle, NSString *icon)) {
    if ([NSThread isMainThread]) return @"Error: dev-annotate can't run on the main thread\n";

    NSDictionary *components = [RCDevAnnotateAction componentsFromActionString:cmd];
    if (!components) return @"Error: Invalid dev-annotate action\n";

    NSString *hostId = components[@"hostId"] ?: @"";
    if (hostId.length == 0) return @"Error: Missing SSH host\n";

    NSArray *hosts = [config[@"sshHosts"] isKindOfClass:[NSArray class]] ? config[@"sshHosts"] : @[];
    NSDictionary *targetHost = nil;
    for (NSDictionary *h in hosts) {
        if ([h isKindOfClass:[NSDictionary class]] && [h[@"id"] isEqualToString:hostId]) {
            targetHost = h;
            break;
        }
    }
    if (!targetHost) return [NSString stringWithFormat:@"Error: SSH host '%@' not found\n", hostId];

    NSString *hostAddr = targetHost[@"host"] ?: @"";
    NSString *user = targetHost[@"user"] ?: @"mobile";
    if (hostAddr.length == 0 ||
        [hostAddr hasPrefix:@"-"] || [hostAddr rangeOfString:@" "].location != NSNotFound ||
        [user hasPrefix:@"-"] || [user rangeOfString:@" "].location != NSNotFound) {
        return @"Error: Invalid SSH host configuration\n";
    }

    @synchronized (rc_dev_state_lock()) {
        if (g_devAnnotateActive) return @"Error: Annotation overlay is already open\n";
        if (rc_dev_is_locked()) return @"Error: Device is locked\n";
        g_devAnnotateActive = YES;
    }

    __block RCDevAnnotateWindow *window = nil;
    __block RCDevAnnotateViewController *vc = nil;
    void (^cleanup)(void) = ^{
        rc_dev_main_sync(^{
            [vc prepareForDismiss];
            vc.onFinish = nil;
            window.hidden = YES;
            window.rootViewController = nil;
            window = nil;
            vc = nil;
        });
        @synchronized (rc_dev_state_lock()) {
            g_devAnnotateActive = NO;
        }
    };

    @try {
        rc_dev_dismiss_cc_if_visible();
        RCScreenSettle(0.8, NULL);

        if (rc_dev_is_locked()) {
            cleanup();
            return @"Error: Device is locked\n";
        }

        UIImage *heldShot = RCScreenGrabImage();
        if (!heldShot) {
            cleanup();
            return @"Error: Couldn't capture the screen\n";
        }

        RCDevAnnotateSession *session = [RCDevAnnotateSession new];
        session.lock = [NSObject new];
        session.semaphore = dispatch_semaphore_create(0);

        __block BOOL hasScene = NO;
        rc_dev_main_sync(^{
            UIWindowScene *scene = rc_dev_window_scene();
            if (!scene) return;
            hasScene = YES;
            CGRect bounds = scene.coordinateSpace.bounds;
            if (CGRectIsEmpty(bounds)) bounds = [UIScreen mainScreen].bounds;

            window = [[RCDevAnnotateWindow alloc] initWithWindowScene:scene];
            window.frame = bounds;
            window.windowLevel = UIWindowLevelAlert + 2600.0;
            window.backgroundColor = [UIColor clearColor];
            window.opaque = NO;
            window.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

            vc = [[RCDevAnnotateViewController alloc] initWithShot:heldShot];
            vc.onFinish = ^(BOOL cancelled, CGRect selectedRect, CGSize overlaySize, NSString *text) {
                @synchronized (session.lock) {
                    if (session.resolved) return;
                    session.resolved = YES;
                    session.cancelled = cancelled;
                    session.selectedRect = selectedRect;
                    session.overlaySize = overlaySize;
                    session.text = text ?: @"";
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

        dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120.0 * NSEC_PER_SEC));
        long waitResult = dispatch_semaphore_wait(session.semaphore, deadline);

        BOOL timedOut = NO;
        BOOL cancelled = NO;
        CGRect selectedRect = CGRectZero;
        CGSize overlaySize = CGSizeZero;
        NSString *text = @"";
        @synchronized (session.lock) {
            if (waitResult != 0 && !session.resolved) {
                session.resolved = YES;
                timedOut = YES;
            } else {
                cancelled = session.cancelled;
                selectedRect = session.selectedRect;
                overlaySize = session.overlaySize;
                text = session.text ?: @"";
            }
        }

        cleanup();

        if (timedOut) return @"Error: Annotation timed out\n";
        if (cancelled) return @"Cancelled\n";

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                rc_dev_deliver_over_ssh(targetHost, components, heldShot, selectedRect, overlaySize, text, showToast);
            }
        });
        return @"Sending annotation\n";
    } @catch (NSException *e) {
        SRLogMin(@"[DevAnnotate] Exception: %@", e);
        cleanup();
        return [NSString stringWithFormat:@"Error: %@\n", e.reason ?: @"Annotation failed"];
    }
}
