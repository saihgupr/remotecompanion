// Gestures: record what you do on the screen, then play it back as an action.
//
// Recording watches the digitizer through the HID listener (Tweak.x), so touches still reach
// whatever is on screen and the phone is used normally until the Stop pill is tapped. Touches
// that start on the pill are left out. A recording is saved by name in the gesture library,
// /var/mobile/Documents/rc_gestures.plist.
//
// Playback sends each frame the way the touchscreen does: positions as fractions of the screen,
// no target, and the touchscreen's own sender ID (learned from a real touch, kept per boot). iOS
// then routes the touches itself, like a finger: to the Home Screen, an app, or a system gesture.
// Touches with any other sender ID never reach an app.

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import <os/lock.h>
#import <objc/message.h>
#import <sys/sysctl.h>
#import "RCGestures.h"

void SRLog(NSString *format, ...);
void SRLogMin(NSString *format, ...);
BOOL RCCommandFromLocalSocket(void);

typedef struct __IOHIDEvent *RCHIDEventRef;
typedef struct __IOHIDEventSystemClient *RCHIDClientRef;
extern CFArrayRef IOHIDEventGetChildren(RCHIDEventRef event);
extern double IOHIDEventGetFloatValue(RCHIDEventRef event, int field);
extern int IOHIDEventGetIntegerValue(RCHIDEventRef event, int field);
extern int IOHIDEventGetType(RCHIDEventRef event);
extern uint64_t IOHIDEventGetSenderID(RCHIDEventRef event);
extern uint64_t IOHIDEventGetTimeStamp(RCHIDEventRef event);
extern RCHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t transducerType, uint32_t index, uint32_t identity,
    uint32_t eventMask, uint32_t buttonMask, double x, double y, double z, double tipPressure, double barrelPressure, boolean_t range, boolean_t touch, uint32_t options);
extern RCHIDEventRef IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t index, uint32_t identity, uint32_t eventMask,
    double x, double y, double z, double tipPressure, double twist, boolean_t range, boolean_t touch, uint32_t options);
extern void IOHIDEventAppendEvent(RCHIDEventRef parent, RCHIDEventRef child, uint32_t options);
extern void IOHIDEventSetIntegerValue(RCHIDEventRef event, uint32_t field, int32_t value);
extern void IOHIDEventSetFloatValue(RCHIDEventRef event, uint32_t field, double value);
extern void IOHIDEventSetSenderID(RCHIDEventRef event, uint64_t senderID);
extern RCHIDClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientDispatchEvent(RCHIDClientRef client, RCHIDEventRef event);

// One finger in a frame, in points of the screen held upright (the digitizer's own frame,
// whatever way the screen is turned)
typedef struct {
    uint8_t slot;      // the digitizer's number for this finger, the same from down to up
    uint8_t touching;  // 0 on the frame that lifts it
    uint8_t edge;      // which screen edge it's on: the edge bits of the touchscreen's event mask >> 24
                       // (1 bottom, 8 left, ...), 0 for none
    double x;
    double y;
} RCTouchFinger;

static NSString *const kRCGesturesPath = @"/var/mobile/Documents/rc_gestures.plist";
static const NSTimeInterval kRCGestureMaxSeconds = 600;
static const int kRCGestureMaxFingers = 10;

#pragma mark - Library

// A recording's frames, packed: per frame a float time, a byte count, then per finger a byte slot,
// a byte of flags (1 touching, 2 bottom edge, bits 2-5 the edge bits) and float x, y in points.
// Older recordings have only the bottom edge bit.
typedef struct {
    double t;
    int count;
    RCTouchFinger fingers[kRCGestureMaxFingers];
} RCGestureFrame;

static NSMutableArray<NSMutableDictionary *> *rc_gestures_load(void) {
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:kRCGesturesPath];
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *g in root[@"gestures"]) {
        if ([g isKindOfClass:[NSDictionary class]] && [g[@"name"] isKindOfClass:[NSString class]] && [g[@"frames"] isKindOfClass:[NSData class]]) {
            [list addObject:[g mutableCopy]];
        }
    }
    return list;
}

static BOOL rc_gestures_save(NSArray *list) {
    // The library's settings are kept alongside
    NSMutableDictionary *root = [[NSDictionary dictionaryWithContentsOfFile:kRCGesturesPath] mutableCopy] ?: [NSMutableDictionary dictionary];
    root[@"gestures"] = list;
    return [root writeToFile:kRCGesturesPath atomically:YES];
}

// Show Stop After: seconds without a touch before the Stop button comes out by itself (0: never)
static double rc_gestures_idle_stop(void) {
    return [[NSDictionary dictionaryWithContentsOfFile:kRCGesturesPath][@"idleStopSeconds"] doubleValue];
}

static BOOL rc_gestures_set_setting(NSString *key, id value) {
    NSMutableDictionary *root = [[NSDictionary dictionaryWithContentsOfFile:kRCGesturesPath] mutableCopy] ?: [NSMutableDictionary dictionaryWithObject:@[] forKey:@"gestures"];
    root[key] = value;
    return [root writeToFile:kRCGesturesPath atomically:YES];
}

// Stop on Touch: a new finger on the screen while a gesture plays stops it
static BOOL rc_gestures_stop_on_touch(void) {
    id value = [NSDictionary dictionaryWithContentsOfFile:kRCGesturesPath][@"stopOnTouch"];
    return value ? [value boolValue] : YES;
}

// Show Touches: dots where a playing gesture's fingers are
static BOOL rc_gestures_show_touches(void) {
    id value = [NSDictionary dictionaryWithContentsOfFile:kRCGesturesPath][@"showTouches"];
    return value ? [value boolValue] : YES;
}

static BOOL rc_gestures_set_idle_stop(double seconds) {
    return rc_gestures_set_setting(@"idleStopSeconds", @(MAX(0, seconds)));
}

// Tab Size: how big the recording tab is (small, medium or large)
static NSArray<NSString *> *rc_gestures_tab_sizes(void) {
    return @[@"small", @"medium", @"large"];
}

static NSString *rc_gestures_tab_size(void) {
    NSString *size = [NSDictionary dictionaryWithContentsOfFile:kRCGesturesPath][@"tabSize"];
    return [rc_gestures_tab_sizes() containsObject:size] ? size : @"medium";
}

static CGFloat rc_gestures_tab_scale(void) {
    NSString *size = rc_gestures_tab_size();
    return [size isEqualToString:@"small"] ? 0.75 : [size isEqualToString:@"large"] ? 1.3 : 1.0;
}

static NSMutableDictionary *rc_gesture_named(NSArray<NSMutableDictionary *> *list, NSString *name) {
    for (NSMutableDictionary *g in list) {
        if ([g[@"name"] caseInsensitiveCompare:name] == NSOrderedSame) return g;
    }
    return nil;
}

static NSData *rc_gesture_pack(const RCGestureFrame *frames, NSUInteger count) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i < count; i++) {
        float t = (float)frames[i].t;
        uint8_t n = (uint8_t)frames[i].count;
        [data appendBytes:&t length:4];
        [data appendBytes:&n length:1];
        for (int j = 0; j < n; j++) {
            const RCTouchFinger *f = &frames[i].fingers[j];
            uint8_t head[2] = { f->slot, (uint8_t)((f->touching ? 1 : 0) | (f->edge == 1 ? 2 : 0) | ((f->edge & 0xF) << 2)) };
            float xy[2] = { (float)f->x, (float)f->y };
            [data appendBytes:head length:2];
            [data appendBytes:xy length:8];
        }
    }
    return data;
}

static NSMutableData *rc_gesture_unpack(NSData *data, NSUInteger *outCount) {
    NSMutableData *frames = [NSMutableData data];
    const uint8_t *p = data.bytes, *end = p + data.length;
    NSUInteger count = 0;
    while (p + 5 <= end) {
        RCGestureFrame frame = {0};
        float t;
        memcpy(&t, p, 4);
        frame.t = t;
        int n = p[4];
        p += 5;
        if (n > kRCGestureMaxFingers || p + n * 10 > end) break;
        // A frame from a file can hold anything: a time that isn't a number or is far off would
        // keep playback waiting, and a position that isn't a number can't be sent
        if (!isfinite(t) || t < 0 || t > 3600) break;
        BOOL bad = NO;
        for (int j = 0; j < n; j++) {
            float xy[2];
            memcpy(xy, p + 2 + j * 10, 8);
            if (!isfinite(xy[0]) || !isfinite(xy[1]) || fabsf(xy[0]) > 10000 || fabsf(xy[1]) > 10000) bad = YES;
        }
        if (bad) break;
        for (int j = 0; j < n; j++) {
            float xy[2];
            memcpy(xy, p + 2, 8);
            uint8_t edge = (p[1] >> 2) & 0xF;
            if (!edge && (p[1] & 2)) edge = 1; // an older recording's bottom edge
            frame.fingers[j] = (RCTouchFinger){ p[0], (uint8_t)(p[1] & 1), edge, xy[0], xy[1] };
            p += 10;
        }
        frame.count = n;
        [frames appendBytes:&frame length:sizeof(frame)];
        count++;
    }
    *outCount = count;
    return frames;
}

// Strokes: a stroke runs from a frame where the first finger goes down to the one that lifts the last
static NSUInteger rc_gesture_stroke_count(const RCGestureFrame *frames, NSUInteger count) {
    NSUInteger strokes = 0;
    BOOL wasDown = NO;
    for (NSUInteger i = 0; i < count; i++) {
        BOOL down = NO;
        for (int j = 0; j < frames[i].count; j++) down = down || frames[i].fingers[j].touching;
        if (down && !wasDown) strokes++;
        wasDown = down;
    }
    return strokes;
}

#pragma mark - Recording

typedef NS_ENUM(NSInteger, RCGestureRecordState) {
    RCGestureRecordIdle,
    RCGestureRecordCounting,
    RCGestureRecordRecording,
};

static os_unfair_lock g_recLock = OS_UNFAIR_LOCK_INIT;
static volatile BOOL g_recActive;          // read on the HID thread without the lock
static RCGestureRecordState g_recState;
static NSString *g_recName;
static BOOL g_recReturnToApp;
static NSString *g_recResult = @"idle";    // what "gesture record-status" answers once it's over
static NSMutableData *g_recFrames;         // RCGestureFrame
static double g_recStart;                  // time of the first recorded frame, 0 before it
static double g_recLastTouch;              // time of the latest recorded frame, or when recording began
static double g_recIdleStop;               // Show Stop After, read when recording starts
static CGSize g_recScreen;                 // the screen held upright, in points
static CGRect g_recPillRect;               // the pill, in the same space: touches starting there are left out
static uint32_t g_recIgnored;              // slots that started on the pill
static uint32_t g_recDown;                 // slots down and recorded

static UIWindow *g_pillWindow;
static NSTimer *g_pillTimer;
static NSDate *g_pillStarted;

static void rc_gesture_record_finish(BOOL save);

#pragma mark - The touchscreen's sender ID

static NSString *const kRCSenderCachePath = @"/var/mobile/Library/Caches/com.goldenappleguy.rc.touch-sender.plist";
static uint64_t g_touchSender;

static long rc_boot_time(void) {
    struct timeval boot = {0};
    size_t size = sizeof(boot);
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    sysctl(mib, 2, &boot, &size, NULL, 0);
    return boot.tv_sec;
}

// Learned from the first real touch after SpringBoard starts, and saved for the rest of the boot
static void rc_learn_sender(RCHIDEventRef event) {
    uint64_t sender = IOHIDEventGetSenderID(event);
    if (!sender || sender == g_touchSender) return;
    g_touchSender = sender;
    uint64_t saved = sender;
    long boot = rc_boot_time();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [@{ @"sender": @(saved), @"boot": @(boot) } writeToFile:kRCSenderCachePath atomically:YES];
    });
}

static uint64_t rc_touch_sender(void) {
    if (g_touchSender) return g_touchSender;
    NSDictionary *cache = [NSDictionary dictionaryWithContentsOfFile:kRCSenderCachePath];
    if (labs([cache[@"boot"] longValue] - rc_boot_time()) <= 2) g_touchSender = [cache[@"sender"] unsignedLongLongValue];
    return g_touchSender;
}

#pragma mark - Recording (from the HID listener)

#pragma mark - Playback state

static volatile BOOL g_playCancel;
static volatile BOOL g_playing;
static volatile BOOL g_playStopOnTouch;
static volatile BOOL g_playTouched;            // the last playback was stopped by a touch
static NSString *g_playResult = @"none";       // how the last playback ended (gesture play-status)

// The touches playback sends, by timestamp, so they aren't mistaken for real ones
static uint64_t g_sentStamps[64];
static volatile uint32_t g_sentNext;

static void rc_gesture_note_sent(uint64_t stamp) {
    g_sentStamps[g_sentNext++ % 64] = stamp;
}

static BOOL rc_gesture_was_sent(uint64_t stamp) {
    for (int i = 0; i < 64; i++) if (g_sentStamps[i] == stamp) return YES;
    return NO;
}

// What the watcher saw during the current playback, for the log
static uint32_t g_watchEvents, g_watchSent, g_watchDowns, g_watchMixed;

// Playback's fingers all have this contact size (read back as fixed point, so close to it); a
// real fingertip's varies
static BOOL rc_gesture_finger_is_sent(RCHIDEventRef child) {
    return fabs(IOHIDEventGetFloatValue(child, 0xB0014) - 0.04) < 1e-4;
}

static void rc_gesture_watch_real_touch(RCHIDEventRef event) {
    BOOL playing = g_playing;
    if (playing) g_watchEvents++;
    BOOL sentEvent = rc_gesture_was_sent(IOHIDEventGetTimeStamp(event));
    if (playing && sentEvent) g_watchSent++;
    CFArrayRef children = IOHIDEventGetChildren(event);
    if (!children) return;
    for (CFIndex i = 0; i < CFArrayGetCount(children); i++) {
        RCHIDEventRef child = (RCHIDEventRef)CFArrayGetValueAtIndex(children, i);
        if (IOHIDEventGetType(child) != 11) continue;
        // A finger of playback's own, whether it came alone or with a real one in the same event
        if (rc_gesture_finger_is_sent(child)) continue;
        if (sentEvent && playing) {
            g_watchMixed++;
            if (g_watchMixed <= 3) SRLog(@"[Gesture] a real finger came inside a playback event (size %.6f)", IOHIDEventGetFloatValue(child, 0xB0014));
        }
        // A new touch: its mask says the touch changed (0x2) and it's on. A finger already down
        // when playback started (the one that ran the trigger) only moves, rests or lifts.
        uint32_t index = (uint32_t)IOHIDEventGetIntegerValue(child, 0xB0005);
        BOOL touching = IOHIDEventGetIntegerValue(child, 0xB0009) != 0;
        uint32_t mask = (uint32_t)IOHIDEventGetIntegerValue(child, 0xB0007);
        if (playing && touching && (mask & 0x2)) {
            g_watchDowns++;
            SRLog(@"[Gesture] touch down during playback: finger %u (size %.4f, mask 0x%x, %@), stop on touch %@",
                index, IOHIDEventGetFloatValue(child, 0xB0014), mask, sentEvent ? @"inside a playback event" : @"its own event",
                g_playStopOnTouch ? @"on" : @"off");
            if (g_playStopOnTouch && !g_playCancel) {
                g_playTouched = YES;
                g_playCancel = YES;
            }
        }
    }
}

void RCGestureHIDEvent(const void *rawEvent) {
    RCHIDEventRef event = (RCHIDEventRef)rawEvent;
    if (!g_touchSender) rc_learn_sender(event);
    rc_gesture_watch_real_touch(event);
    if (!g_recActive) return;
    CFArrayRef children = IOHIDEventGetChildren(event);
    if (!children) return;
    double now = CFAbsoluteTimeGetCurrent();

    os_unfair_lock_lock(&g_recLock);
    if (g_recState != RCGestureRecordRecording) {
        os_unfair_lock_unlock(&g_recLock);
        return;
    }
    RCGestureFrame frame = {0};
    for (CFIndex i = 0; i < CFArrayGetCount(children) && frame.count < kRCGestureMaxFingers; i++) {
        RCHIDEventRef child = (RCHIDEventRef)CFArrayGetValueAtIndex(children, i);
        if (IOHIDEventGetType(child) != 11) continue;
        uint32_t slot = (uint32_t)IOHIDEventGetIntegerValue(child, 0xB0005) & 31;
        BOOL touching = IOHIDEventGetIntegerValue(child, 0xB0009) != 0;
        double x = IOHIDEventGetFloatValue(child, 0xB0000) * g_recScreen.width;
        double y = IOHIDEventGetFloatValue(child, 0xB0001) * g_recScreen.height;
        uint32_t bit = 1u << slot;
        if (g_recIgnored & bit) {
            if (!touching) g_recIgnored &= ~bit;
            continue;
        }
        if (!(g_recDown & bit)) {
            if (!touching) continue;
            if (CGRectContainsPoint(g_recPillRect, CGPointMake(x, y))) {
                g_recIgnored |= bit;
                continue;
            }
        }
        if (touching) g_recDown |= bit; else g_recDown &= ~bit;
        uint32_t mask = (uint32_t)IOHIDEventGetIntegerValue(child, 0xB0007);
        // An edge touch carries 0x40000 and its edge's bit: 0x1000000 bottom, 0x8000000 left, ...
        uint8_t edge = (mask & 0x40000) ? (uint8_t)((mask >> 24) & 0xF) : 0;
        frame.fingers[frame.count++] = (RCTouchFinger){ (uint8_t)slot, (uint8_t)touching, edge, x, y };
    }
    if (frame.count) {
        if (g_recStart == 0) g_recStart = now;
        g_recLastTouch = now;
        frame.t = now - g_recStart;
        [g_recFrames appendBytes:&frame length:sizeof(frame)];
    }
    BOOL tooLong = g_recStart > 0 && now - g_recStart > kRCGestureMaxSeconds;
    os_unfair_lock_unlock(&g_recLock);
    if (tooLong) dispatch_async(dispatch_get_main_queue(), ^{ rc_gesture_record_finish(YES); });
}

// Drawn over the lock screen too, like the other windows that must always show
@interface RCGesturePillWindow : UIWindow
@end
@implementation RCGesturePillWindow
- (BOOL)_shouldCreateContextAsSecure { return YES; }
@end

// The recording control. During the countdown: a pill at the top, "Starting in 3" with Cancel.
// While recording: only a red tab at the screen's edge, blinking like a recording light. Pulled
// (or tapped) out, more of it shows, steady, with a white Stop square; it tucks back after a few
// seconds. Only the tab takes touches (and those aren't recorded). Dragged, the whole tab follows
// the finger; let go, it springs to the nearer side at that height.
typedef NS_ENUM(NSInteger, RCPillMode) {
    RCPillCountdown,
    RCPillTab,
    RCPillOut,
};

// Sizes at Medium; rc_gesture_pill_sizes scales them for Tab Size when recording starts
static CGFloat kRCTabHeight = 60;    // the capsule's height
static CGFloat kRCCapsuleWidth = 120;
static CGFloat kRCTabCorner = 14;    // rounded-rectangle corners, not a half circle
static CGFloat kRCTuckedShown = 20;  // how much shows tucked in
static CGFloat kRCTuckedTouch = 34;  // the touch area tucked in (from the edge), never smaller
static CGFloat kRCOutShown = 76;     // how much shows pulled out
static CGFloat kRCStopSize = 20;     // the white Stop square

static void rc_gesture_pill_sizes(CGFloat scale) {
    kRCTabHeight = round(60 * scale);
    kRCCapsuleWidth = round(120 * scale);
    kRCTabCorner = round(14 * scale);
    kRCTuckedShown = round(20 * scale);
    kRCTuckedTouch = MAX(34, kRCTuckedShown + 14);
    kRCOutShown = round(76 * scale);
    kRCStopSize = round(20 * scale);
}

@interface RCGesturePillController : UIViewController
@property (nonatomic, assign) RCPillMode mode;
@property (nonatomic, strong) UIView *countdown;
@property (nonatomic, strong) UILabel *countdownLabel;
@property (nonatomic, strong) UIView *cancelButton;
@property (nonatomic, strong) UIView *tab;
@property (nonatomic, strong) UIView *light;     // the white Stop square, shown when pulled out
@property (nonatomic, assign) CGFloat tabY;      // the tab's top, on the screen as it's turned now
@property (nonatomic, assign) BOOL onLeft;       // on the left edge instead of the right
@property (nonatomic, strong) NSTimer *tuckTimer;
@property (nonatomic, assign) BOOL idleOut;      // out because of Show Stop After
@property (nonatomic, assign) BOOL dragging;     // following a finger
@property (nonatomic, assign) CGPoint dragStart; // the tab's top left on the screen when the drag began
- (void)showCountdown:(int)secondsLeft;
- (void)showRecording:(int)seconds;
- (void)idleFor:(double)idle;
@end

static RCGesturePillController *g_pillController;
static UIColor *rc_record_red(void) { return [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1]; }

@implementation RCGesturePillController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.clipsToBounds = NO;

    // Countdown pill: dark glass, the count, a white Cancel button. Sized when shown.
    UIView *countdown = [[UIView alloc] init];
    countdown.layer.cornerCurve = kCACornerCurveContinuous;
    countdown.layer.borderWidth = 1.2;
    countdown.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    countdown.clipsToBounds = YES;
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [countdown addSubview:glass];
    UIView *tint = [[UIView alloc] init];
    tint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [countdown addSubview:tint];
    UILabel *label = [[UILabel alloc] init];
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    [countdown addSubview:label];
    UIView *cancel = [[UIView alloc] init];
    cancel.backgroundColor = [UIColor colorWithWhite:1 alpha:0.95];
    cancel.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
    UIImageView *x = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"xmark" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    x.tintColor = [UIColor colorWithWhite:0.3 alpha:1];
    x.tag = 1;
    [cancel addSubview:x];
    UILabel *cancelLabel = [[UILabel alloc] init];
    cancelLabel.text = @"Cancel";
    cancelLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    cancelLabel.textColor = [UIColor colorWithWhite:0.08 alpha:1];
    cancelLabel.tag = 2;
    [cancel addSubview:cancelLabel];
    [countdown addSubview:cancel];
    [self.view addSubview:countdown];
    self.countdown = countdown;
    self.countdownLabel = label;
    self.cancelButton = cancel;

    // The tab: one red capsule, mostly past the screen's edge. Tucked, a sliver shows, blinking
    // like a recording light; pulled out, more of it shows, steady, with the white Stop square.
    UIView *tab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kRCCapsuleWidth, kRCTabHeight)];
    tab.backgroundColor = rc_record_red();
    tab.layer.cornerRadius = kRCTabCorner;
    tab.layer.cornerCurve = kCACornerCurveContinuous;
    tab.layer.shadowColor = [UIColor colorWithRed:1.0 green:0.18 blue:0.16 alpha:1].CGColor;
    tab.layer.shadowOffset = CGSizeZero;
    tab.layer.shadowRadius = 10;
    tab.layer.shadowOpacity = 0.6;
    tab.alpha = 0;
    [self.view addSubview:tab];
    self.tab = tab;
    UIView *light = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kRCStopSize, kRCStopSize)];
    light.backgroundColor = [UIColor whiteColor];
    light.layer.cornerRadius = round(kRCStopSize / 4);
    light.layer.cornerCurve = kCACornerCurveContinuous;
    light.alpha = 0;
    [tab addSubview:light];
    self.light = light;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
    [self.view addGestureRecognizer:tap];
    [self.view addGestureRecognizer:pan];
}

- (CGSize)visibleScreen {
    return [UIScreen mainScreen].bounds.size; // follows a sideways app
}

// The window (and so the touch area) for each mode, the capsule inside it, and the area left out
// of the recording. Tucked, the touch area is wider than the sliver that shows, so it's easy to
// catch.
- (void)placeWindowAnimated:(BOOL)animated {
    UIWindow *window = self.view.window;
    if (!window) return;
    CGSize screen = [self visibleScreen];
    BOOL out = self.mode == RCPillOut;
    CGFloat shown = out ? kRCOutShown : kRCTuckedShown;          // how much of the capsule shows
    CGFloat touchWidth = out ? kRCOutShown + 10 : kRCTuckedTouch; // the window
    CGRect frame;
    if (self.mode == RCPillCountdown) {
        frame = window.frame; // set by showCountdown
    } else {
        frame = CGRectMake(self.onLeft ? 0 : screen.width - touchWidth, self.tabY, touchWidth, kRCTabHeight + 8);
    }
    // The capsule's inner end sits `shown` from the edge; the rest runs past it
    CGFloat capsuleX = self.onLeft ? shown - kRCCapsuleWidth : touchWidth - shown;
    CGRect capsule = CGRectMake(capsuleX, 4, kRCCapsuleWidth, kRCTabHeight);
    CGFloat lightX = self.onLeft ? kRCCapsuleWidth - shown / 2 : shown / 2; // in the middle of what shows
    void (^apply)(void) = ^{
        window.frame = frame;
        self.tab.frame = capsule;
        self.light.center = CGPointMake(lightX, kRCTabHeight / 2);
        self.light.alpha = out ? 1 : 0;
        self.tab.alpha = self.mode == RCPillCountdown ? 0 : 1;
        self.countdown.alpha = self.mode == RCPillCountdown ? 1 : 0;
    };
    if (animated) [UIView animateWithDuration:0.34 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState animations:apply completion:nil];
    else apply();
    // It blinks only while tucked; out, it stays lit
    if (out) {
        [self.tab.layer removeAnimationForKey:@"light"];
        [self.tab.layer removeAnimationForKey:@"light-glow"];
    } else if (self.mode == RCPillTab && ![self.tab.layer animationForKey:@"light"]) {
        [self startLight];
    }
    CGRect excluded = [window.screen.coordinateSpace convertRect:frame toCoordinateSpace:[UIScreen mainScreen].fixedCoordinateSpace];
    os_unfair_lock_lock(&g_recLock);
    g_recPillRect = CGRectInset(excluded, -6, -6);
    os_unfair_lock_unlock(&g_recLock);
}

- (void)showCountdown:(int)secondsLeft {
    UIWindow *window = self.view.window;
    self.countdownLabel.text = [NSString stringWithFormat:@"Starting in %d", secondsLeft];
    UILabel *cancelLabel = [self.cancelButton viewWithTag:2];
    UIView *x = [self.cancelButton viewWithTag:1];
    CGFloat height = 40, buttonHeight = 30;
    CGFloat labelWidth = ceil([@"Starting in 0" sizeWithAttributes:@{ NSFontAttributeName: self.countdownLabel.font }].width);
    CGFloat cancelWidth = ceil([cancelLabel.text sizeWithAttributes:@{ NSFontAttributeName: cancelLabel.font }].width);
    CGFloat buttonWidth = 12 + 11 + 6 + cancelWidth + 12;
    CGFloat width = 16 + labelWidth + 14 + buttonWidth + 5;
    self.countdown.frame = CGRectMake(0, 0, width, height);
    self.countdown.layer.cornerRadius = height / 2;
    self.countdownLabel.frame = CGRectMake(16, 0, labelWidth, height);
    self.cancelButton.frame = CGRectMake(width - 5 - buttonWidth, (height - buttonHeight) / 2, buttonWidth, buttonHeight);
    self.cancelButton.layer.cornerRadius = buttonHeight / 2;
    x.frame = CGRectMake(12, (buttonHeight - 11) / 2, 11, 11);
    cancelLabel.frame = CGRectMake(12 + 11 + 6, 0, cancelWidth + 2, buttonHeight);
    if (window && fabs(window.frame.size.width - width) > 0.5) {
        CGSize screen = [self visibleScreen];
        window.frame = CGRectMake((screen.width - width) / 2, window.frame.origin.y, width, height);
        [self placeWindowAnimated:NO];
    }
}

- (void)showRecording:(int)seconds {
    if (self.mode != RCPillCountdown) return;
    CGSize screen = [self visibleScreen];
    self.tabY = round(screen.height * (screen.width > screen.height ? 0.4 : 0.32));
    self.mode = RCPillTab;
    [self placeWindowAnimated:YES];
}

// A recording light: once a second the tab dims from bright to dark red, like a lamp, and its glow
// goes out, with short fades. It stays solid.
- (void)startLight {
    id bright = (id)rc_record_red().CGColor;
    id dim = (id)[UIColor colorWithRed:0.42 green:0.05 blue:0.04 alpha:1].CGColor;
    for (NSArray *part in @[ @[@"backgroundColor", @[bright, bright, dim, dim, bright], @"light"],
                             @[@"shadowOpacity", @[@0.9, @0.9, @0, @0, @0.9], @"light-glow"] ]) {
        CAKeyframeAnimation *blink = [CAKeyframeAnimation animationWithKeyPath:part[0]];
        blink.values = part[1];
        blink.keyTimes = @[@0, @0.45, @0.55, @0.95, @1.0];
        blink.duration = 1.0;
        blink.repeatCount = HUGE_VALF;
        blink.removedOnCompletion = NO;
        [self.tab.layer addAnimation:blink forKey:part[2]];
    }
}

// Show Stop After: out by itself after a while without touches, and it stays out until the next one
- (void)idleFor:(double)idle {
    if (self.dragging) return;
    if (self.mode == RCPillTab && g_recIdleStop > 0 && idle >= g_recIdleStop) {
        [self setOut:YES];
        [self.tuckTimer invalidate];
        self.tuckTimer = nil;
        self.idleOut = YES;
    } else if (self.idleOut && idle < 0.5) {
        self.idleOut = NO;
        if (self.mode == RCPillOut) [self setOut:NO];
    }
}

- (void)setOut:(BOOL)out {
    if (self.dragging) return;
    self.idleOut = NO;
    [self.tuckTimer invalidate];
    self.tuckTimer = nil;
    self.mode = out ? RCPillOut : RCPillTab;
    [self placeWindowAnimated:YES];
    if (out) {
        __weak typeof(self) weakSelf = self;
        self.tuckTimer = [NSTimer scheduledTimerWithTimeInterval:3.5 repeats:NO block:^(NSTimer *timer) { [weakSelf setOut:NO]; }];
    }
}

- (void)tapped {
    if (self.mode == RCPillCountdown) {
        rc_gesture_record_finish(NO);
    } else if (self.mode == RCPillTab) {
        [self setOut:YES];
    } else {
        [self.tuckTimer invalidate];
        [UIView animateWithDuration:0.1 animations:^{ self.light.transform = CGAffineTransformMakeScale(0.85, 0.85); }];
        rc_gesture_record_finish(YES);
    }
}

// Dragged, the whole tab follows the finger. Let go, it springs to the nearer side at that height:
// pulled a little away from the edge it started at, Stop comes out; pushed toward it, or moved to
// the other side, it tucks in.
- (void)dragged:(UIPanGestureRecognizer *)pan {
    if (self.mode == RCPillCountdown) return;
    UIWindow *window = self.view.window;
    CGSize screen = [self visibleScreen];
    CGPoint move = [pan translationInView:window];
    if (pan.state == UIGestureRecognizerStateBegan) {
        [self.tuckTimer invalidate];
        self.tuckTimer = nil;
        self.idleOut = NO;
        self.dragging = YES;
        // Carried, the tab is a rounded square with the Stop square in it, still blinking, fully
        // on the screen where its visible part was
        CGFloat side = kRCTabHeight;
        CGFloat x = self.onLeft ? 0 : screen.width - side;
        self.dragStart = CGPointMake(x, window.frame.origin.y + self.tab.frame.origin.y);
        if (![self.tab.layer animationForKey:@"light"]) [self startLight];
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            window.frame = CGRectMake(self.dragStart.x - 4, self.dragStart.y - 4, side + 8, side + 8);
            self.tab.frame = CGRectMake(4, 4, side, side);
            self.light.center = CGPointMake(side / 2, side / 2);
            self.light.alpha = 1;
        } completion:nil];
    } else if (pan.state == UIGestureRecognizerStateChanged && self.dragging) {
        // Free, but its middle stays on the screen
        CGFloat side = kRCTabHeight;
        CGFloat x = MIN(MAX(self.dragStart.x + move.x, -side / 2), screen.width - side / 2);
        CGFloat y = MIN(MAX(self.dragStart.y + move.y, -side / 2), screen.height - side / 2);
        window.frame = CGRectMake(x - 4, y - 4, side + 8, side + 8);
    } else if (self.dragging && (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled)) {
        self.dragging = NO;
        CGRect tab = CGRectOffset(self.tab.frame, window.frame.origin.x, window.frame.origin.y); // on the screen
        BOOL wasLeft = self.onLeft;
        self.onLeft = CGRectGetMidX(tab) < screen.width / 2;
        self.tabY = MIN(MAX(tab.origin.y - 4, 60), screen.height - kRCTabHeight - 60);
        CGFloat away = wasLeft ? move.x : -move.x; // toward the middle
        BOOL out;
        if (self.onLeft != wasLeft) out = NO;
        else if (away > 6) out = YES;
        else if (away < -6) out = NO;
        else out = self.mode == RCPillOut;
        self.mode = out ? RCPillOut : RCPillTab;
        [self setOut:out]; // springs into place, and out, starts the tuck timer
    }
}

@end

static void rc_gesture_pill_update(void) {
    os_unfair_lock_lock(&g_recLock);
    RCGestureRecordState state = g_recState;
    os_unfair_lock_unlock(&g_recLock);
    if (state == RCGestureRecordCounting) {
        int left = (int)ceil(3.0 + [g_pillStarted timeIntervalSinceNow]);
        [g_pillController showCountdown:MAX(left, 1)];
        if (left <= 0) {
            os_unfair_lock_lock(&g_recLock);
            g_recState = RCGestureRecordRecording;
            g_recLastTouch = CFAbsoluteTimeGetCurrent();
            os_unfair_lock_unlock(&g_recLock);
            g_recIdleStop = rc_gestures_idle_stop();
            g_pillStarted = [NSDate date];
            AudioServicesPlaySystemSound(1113); // begin recording
            SRLog(@"[Gesture] recording '%@'", g_recName);
            rc_gesture_pill_update();
        }
    } else if (state == RCGestureRecordRecording) {
        [g_pillController showRecording:(int)-[g_pillStarted timeIntervalSinceNow]];
        os_unfair_lock_lock(&g_recLock);
        double lastTouch = g_recLastTouch;
        os_unfair_lock_unlock(&g_recLock);
        [g_pillController idleFor:CFAbsoluteTimeGetCurrent() - lastTouch];
    }
}

static UIWindowScene *rc_gesture_window_scene(void) {
    id app = [UIApplication sharedApplication];
    SEL wsmSel = NSSelectorFromString(@"windowSceneManager");
    id wsm = [app respondsToSelector:wsmSel] ? ((id (*)(id, SEL))objc_msgSend)(app, wsmSel) : nil;
    SEL embeddedSel = NSSelectorFromString(@"embeddedDisplayWindowScene");
    id scene = [wsm respondsToSelector:embeddedSel] ? ((id (*)(id, SEL))objc_msgSend)(wsm, embeddedSel) : nil;
    if ([scene isKindOfClass:[UIWindowScene class]]) return scene;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

static void rc_gesture_record_start(NSString *name, BOOL returnToApp) {
    CGSize screen = [UIScreen mainScreen].fixedCoordinateSpace.bounds.size;
    UIWindowScene *scene = rc_gesture_window_scene();
    UIWindow *window = scene ? [[RCGesturePillWindow alloc] initWithWindowScene:scene] : [[RCGesturePillWindow alloc] init];
    CGFloat top = 0;
    for (UIWindow *w in scene.windows) top = MAX(top, w.safeAreaInsets.top);
    // Placed on the screen as it's turned now (UIScreen bounds follow a sideways app); the
    // recording itself stays in the upright frame
    CGSize visible = [UIScreen mainScreen].bounds.size;
    BOOL sideways = visible.width > visible.height;
    window.frame = CGRectMake((visible.width - 200) / 2, sideways ? 12 : MAX(top, 20) + 8, 200, 40); // sized to its text when shown
    window.windowLevel = UIWindowLevelAlert + 2600;
    window.backgroundColor = [UIColor clearColor];
    window.clipsToBounds = NO; // the glow reaches past the tab
    rc_gesture_pill_sizes(rc_gestures_tab_scale());
    g_pillController = [[RCGesturePillController alloc] init];
    window.rootViewController = g_pillController;
    window.hidden = NO;
    g_pillWindow = window;

    os_unfair_lock_lock(&g_recLock);
    g_recName = name;
    g_recReturnToApp = returnToApp;
    g_recResult = @"recording";
    g_recFrames = [NSMutableData data];
    g_recStart = 0;
    g_recScreen = screen;
    g_recPillRect = CGRectInset([window convertRect:window.bounds toCoordinateSpace:[UIScreen mainScreen].fixedCoordinateSpace], -6, -6);
    g_recIgnored = 0;
    g_recDown = 0;
    g_recState = RCGestureRecordCounting;
    g_recActive = YES;
    os_unfair_lock_unlock(&g_recLock);

    g_pillStarted = [NSDate date];
    rc_gesture_pill_update();
    g_pillTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { rc_gesture_pill_update(); }];
    SRLog(@"[Gesture] countdown for '%@'", name);
}

static void rc_gesture_reopen_app(void) {
    Class serviceClass = objc_getClass("FBSOpenApplicationService");
    if (!serviceClass) return;
    id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, NSSelectorFromString(@"serviceWithDefaultShellEndpoint"));
    SEL openSel = NSSelectorFromString(@"openApplication:withOptions:completion:");
    if ([service respondsToSelector:openSel]) {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(service, openSel, @"com.saihgupr.remotecompanion", nil, nil);
    }
}

// Ends a recording on the main thread: saved under its name (replacing one of the same name), or dropped
// Stopped by a trigger (Record Gesture run again): when that trigger is itself a touch - a status
// bar or edge gesture - its stroke is the last one recorded, still down or just lifted. It's left
// out, or playing the gesture back would run the trigger and start recording again.
static NSData *rc_gesture_without_stop_stroke(NSData *raw, double stopTime) {
    NSUInteger count = raw.length / sizeof(RCGestureFrame);
    const RCGestureFrame *frames = raw.bytes;
    NSUInteger lastStart = NSNotFound;
    BOOL wasDown = NO;
    for (NSUInteger i = 0; i < count; i++) {
        BOOL down = NO;
        for (int j = 0; j < frames[i].count; j++) down = down || frames[i].fingers[j].touching;
        if (down && !wasDown) lastStart = i;
        wasDown = down;
    }
    if (lastStart == NSNotFound) return raw;
    BOOL stillDown = wasDown;
    BOOL justLifted = stopTime - frames[count - 1].t < 0.3;
    if (!stillDown && !justLifted) return raw;
    return [raw subdataWithRange:NSMakeRange(0, lastStart * sizeof(RCGestureFrame))];
}

// Saves a recording under `name`, replacing one of the same name. A finger still down at the
// end is lifted where it was.
static BOOL rc_gesture_store(NSString *name, NSData *raw) {
    NSUInteger count = raw.length / sizeof(RCGestureFrame);
    if (count == 0) return NO;
    NSMutableData *all = [raw mutableCopy];
    RCGestureFrame last = ((const RCGestureFrame *)raw.bytes)[count - 1];
    BOOL anyDown = NO;
    for (int j = 0; j < last.count; j++) {
        anyDown = anyDown || last.fingers[j].touching;
        last.fingers[j].touching = 0;
    }
    if (anyDown) {
        last.t += 0.016;
        [all appendBytes:&last length:sizeof(last)];
        count++;
    }
    const RCGestureFrame *frames = all.bytes;
    NSMutableArray *list = rc_gestures_load();
    NSMutableDictionary *existing = rc_gesture_named(list, name);
    if (existing) [list removeObject:existing];
    NSUInteger strokes = rc_gesture_stroke_count(frames, count);
    [list addObject:[@{
        @"name": name,
        @"created": [NSDate date],
        @"duration": @(frames[count - 1].t),
        @"strokes": @(strokes),
        @"screen": @[@(g_recScreen.width), @(g_recScreen.height)],
        @"frames": rc_gesture_pack(frames, count),
    } mutableCopy]];
    BOOL ok = rc_gestures_save(list);
    g_recResult = ok ? [NSString stringWithFormat:@"saved\t%@", name] : @"failed";
    SRLogMin(@"[Gesture] saved '%@': %lu strokes, %.1f s, %lu frames%@", name, (unsigned long)strokes, frames[count - 1].t,
             (unsigned long)count, ok ? @"" : @" - WRITE FAILED");
    AudioServicesPlaySystemSound(1114); // end recording
    return ok;
}

// The next free "Gesture N"
static NSString *rc_gesture_suggested_name(void) {
    NSArray *list = rc_gestures_load();
    for (NSInteger n = 1; ; n++) {
        NSString *name = [NSString stringWithFormat:@"Gesture %ld", (long)n];
        if (!rc_gesture_named(list, name)) return name;
    }
}

static UIWindow *g_namePromptWindow;

// Asks for a name over whatever is on screen, prefilled with the next "Gesture N"
static void rc_gesture_ask_name(NSData *raw) {
    NSUInteger count = raw.length / sizeof(RCGestureFrame);
    const RCGestureFrame *frames = raw.bytes;
    NSString *suggested = rc_gesture_suggested_name();
    UIWindowScene *scene = rc_gesture_window_scene();
    UIWindow *window = scene ? [[RCGesturePillWindow alloc] initWithWindowScene:scene] : [[RCGesturePillWindow alloc] init];
    window.windowLevel = UIWindowLevelAlert + 2600;
    window.backgroundColor = [UIColor clearColor];
    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = [UIColor clearColor];
    window.rootViewController = root;
    [window makeKeyAndVisible];
    g_namePromptWindow = window;

    NSUInteger strokes = rc_gesture_stroke_count(frames, count);
    NSString *detail = [NSString stringWithFormat:@"%lu %@, %.1f s", (unsigned long)strokes, strokes == 1 ? @"touch" : @"touches", frames[count - 1].t];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Gesture" message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = suggested;
        field.placeholder = suggested;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeAlways;
    }];
    void (^close)(void) = ^{
        g_namePromptWindow.hidden = YES;
        g_namePromptWindow = nil;
    };
    [alert addAction:[UIAlertAction actionWithTitle:@"Discard" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        g_recResult = @"cancelled";
        SRLog(@"[Gesture] recording discarded");
        close();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [[alert.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"\"" withString:@""]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        rc_gesture_store(name.length ? name : suggested, raw);
        close();
    }]];
    alert.preferredAction = alert.actions.lastObject;
    dispatch_async(dispatch_get_main_queue(), ^{ [root presentViewController:alert animated:YES completion:nil]; });
}

static void rc_gesture_record_finish_ex(BOOL save, BOOL byTrigger);

static void rc_gesture_record_finish(BOOL save) {
    rc_gesture_record_finish_ex(save, NO);
}

static void rc_gesture_record_finish_ex(BOOL save, BOOL byTrigger) {
    os_unfair_lock_lock(&g_recLock);
    if (!g_recActive) {
        os_unfair_lock_unlock(&g_recLock);
        return;
    }
    g_recActive = NO;
    BOOL recorded = g_recState == RCGestureRecordRecording;
    g_recState = RCGestureRecordIdle;
    NSData *raw = g_recFrames;
    g_recFrames = nil;
    if (byTrigger && g_recStart > 0) raw = rc_gesture_without_stop_stroke(raw, CFAbsoluteTimeGetCurrent() - g_recStart);
    NSString *name = g_recName;
    BOOL returnToApp = g_recReturnToApp;
    os_unfair_lock_unlock(&g_recLock);

    [g_pillTimer invalidate];
    g_pillTimer = nil;
    g_pillWindow.hidden = YES;
    g_pillWindow = nil;
    g_pillController = nil;

    NSUInteger count = raw.length / sizeof(RCGestureFrame);
    if (!save || !recorded) {
        g_recResult = @"cancelled";
        SRLog(@"[Gesture] recording '%@' cancelled", name);
    } else if (count == 0) {
        g_recResult = @"empty";
        SRLog(@"[Gesture] recording '%@' had no touches", name);
    } else if (!name) {
        // Started by the Record Gesture action: named now, over whatever is on screen
        g_recResult = @"naming";
        rc_gesture_ask_name(raw);
    } else {
        rc_gesture_store(name, raw);
    }
    if (returnToApp) rc_gesture_reopen_app();
}

// Runs a block on the main thread and waits for it
static void rc_on_main_sync(dispatch_block_t block) {
    if ([NSThread isMainThread]) block();
    else dispatch_sync(dispatch_get_main_queue(), block);
}

#pragma mark - Playback


static dispatch_queue_t rc_gesture_play_queue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.goldenappleguy.rc.gesture-play", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static uint64_t rc_mach_from_seconds(double seconds) {
    static mach_timebase_info_data_t info;
    if (info.denom == 0) mach_timebase_info(&info);
    return (uint64_t)(seconds * 1e9 * info.denom / info.numer);
}

// Waits until `deadline` (mach time) in short naps, so Stop is quick
static BOOL rc_gesture_wait_until(uint64_t deadline) {
    while (mach_absolute_time() < deadline) {
        if (g_playCancel) return NO;
        uint64_t step = mach_absolute_time() + rc_mach_from_seconds(0.05);
        mach_wait_until(MIN(deadline, step));
    }
    return !g_playCancel;
}

// One frame as the touchscreen sends it. *down holds the fingers already down (by slot): a
// finger's first frame is its down, then moves, and its last (not touching) lifts it.
// `screen` is the size the gesture was recorded on: positions go out as fractions of it, so on a
// screen of another size the gesture is stretched to fit (the home bar stays at the bottom)
// `extra` goes into every mask: 0x80 (cancel) when a stopped gesture lets go
static void rc_gesture_send_frame_ex(const RCGestureFrame *frame, uint32_t *down, CGSize screen, uint64_t sender, uint32_t extra) {
    static RCHIDClientRef client;
    if (!client) client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client || frame->count == 0) return;
    uint64_t ts = mach_absolute_time();
    rc_gesture_note_sent(ts);
    RCHIDEventRef parent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, ts, 3, 99, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    if (!parent) return;
    IOHIDEventSetIntegerValue(parent, 0xB0019, 1); // display integrated
    IOHIDEventSetIntegerValue(parent, 0x4, 1);
    uint32_t parentMask = 0x23 | extra;
    for (int i = 0; i < frame->count; i++) {
        const RCTouchFinger *f = &frame->fingers[i];
        uint32_t bit = 1u << (f->slot & 31);
        uint32_t mask = (!f->touching ? 0x2 : (*down & bit) ? 0x4 : 0x3) | extra; // touch (lift) / position / range | touch
        // A finger on a screen edge carries its edge bits, as the touchscreen sends them: without
        // them iOS doesn't start the home bar gesture or an app's swipe back from the left edge
        if (f->edge) {
            uint32_t edgeBits = ((uint32_t)(f->edge & 0xF) << 24) | 0x40000;
            mask |= edgeBits | (*down & bit ? 0 : 0x40);
            parentMask |= edgeBits | 0x40;
        }
        RCHIDEventRef finger = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, ts, f->slot, 3, mask,
            MIN(MAX(f->x / screen.width, 0), 1), MIN(MAX(f->y / screen.height, 0), 1), 0, 0, 0, (boolean_t)f->touching, (boolean_t)f->touching, 0);
        if (finger) {
            IOHIDEventSetFloatValue(finger, 0xB0014, 0.04); // contact size
            IOHIDEventSetFloatValue(finger, 0xB0015, 0.04);
            IOHIDEventAppendEvent(parent, finger, 0);
            CFRelease(finger);
        }
        if (f->touching) *down |= bit; else *down &= ~bit;
    }
    IOHIDEventSetIntegerValue(parent, 0xB0007, (int32_t)parentMask);
    IOHIDEventSetIntegerValue(parent, 0xB0008, 1);
    IOHIDEventSetIntegerValue(parent, 0xB0009, 1);
    IOHIDEventSetSenderID(parent, sender);
    IOHIDEventSystemClientDispatchEvent(client, parent);
    CFRelease(parent);
}

static void rc_gesture_send_frame(const RCGestureFrame *frame, uint32_t *down, CGSize screen, uint64_t sender) {
    rc_gesture_send_frame_ex(frame, down, screen, sender, 0);
}

#pragma mark - Show Touches

// While a gesture plays, a dot under each of its fingers, in a window that takes no touches
static UIWindow *g_dotsWindow;
static NSMutableDictionary<NSNumber *, UIView *> *g_dots; // by finger slot

static void rc_gesture_dots_show(void) {
    if (g_dotsWindow) return;
    UIWindowScene *scene = rc_gesture_window_scene();
    UIWindow *window = scene ? [[RCGesturePillWindow alloc] initWithWindowScene:scene] : [[RCGesturePillWindow alloc] init];
    window.frame = [UIScreen mainScreen].bounds;
    window.windowLevel = UIWindowLevelAlert + 2590; // under the recording tab
    window.backgroundColor = [UIColor clearColor];
    window.userInteractionEnabled = NO;
    window.hidden = NO;
    g_dotsWindow = window;
    g_dots = [NSMutableDictionary dictionary];
}

static void rc_gesture_dots_hide(void) {
    UIWindow *window = g_dotsWindow;
    g_dotsWindow = nil;
    g_dots = nil;
    [UIView animateWithDuration:0.2 animations:^{ window.alpha = 0; } completion:^(BOOL finished) { window.hidden = YES; }];
}

// Moves the dots to a frame's fingers. Positions are fractions of the recorded screen, placed on
// this one as it's turned now.
static void rc_gesture_dots_update(const RCGestureFrame *frame, CGSize screen) {
    if (!g_dotsWindow) return;
    CGSize fixed = [UIScreen mainScreen].fixedCoordinateSpace.bounds.size;
    for (int i = 0; i < frame->count; i++) {
        const RCTouchFinger *f = &frame->fingers[i];
        NSNumber *slot = @(f->slot);
        UIView *dot = g_dots[slot];
        if (!f->touching) {
            if (!dot) continue;
            [g_dots removeObjectForKey:slot];
            [UIView animateWithDuration:0.15 animations:^{
                dot.alpha = 0;
                dot.transform = CGAffineTransformMakeScale(1.3, 1.3);
            } completion:^(BOOL finished) { [dot removeFromSuperview]; }];
            continue;
        }
        if (!dot) {
            dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
            dot.layer.cornerRadius = 20;
            dot.backgroundColor = [UIColor colorWithWhite:1 alpha:0.55];
            dot.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.25].CGColor;
            dot.layer.borderWidth = 1.5;
            dot.layer.shadowColor = [UIColor blackColor].CGColor;
            dot.layer.shadowOpacity = 0.3;
            dot.layer.shadowRadius = 4;
            dot.layer.shadowOffset = CGSizeZero;
            dot.userInteractionEnabled = NO;
            [g_dotsWindow addSubview:dot];
            g_dots[slot] = dot;
        }
        CGPoint p = CGPointMake(MIN(MAX(f->x / screen.width, 0), 1) * fixed.width, MIN(MAX(f->y / screen.height, 0), 1) * fixed.height);
        dot.center = [[UIScreen mainScreen].fixedCoordinateSpace convertPoint:p toCoordinateSpace:g_dotsWindow];
    }
}

static void rc_gesture_dots_frame(const RCGestureFrame *frame, CGSize screen) {
    RCGestureFrame copy = *frame;
    dispatch_async(dispatch_get_main_queue(), ^{ rc_gesture_dots_update(&copy, screen); });
}

// Playback speed from "2x", "0.5x" or "1.5": 1 when missing, kept between 0.25 and 4
static double rc_gesture_speed(NSString *word) {
    NSString *text = [word.lowercaseString stringByReplacingOccurrencesOfString:@"x" withString:@""];
    double speed = text.length ? text.doubleValue : 1;
    return speed > 0 ? MIN(MAX(speed, 0.25), 4) : 1;
}

static void rc_gesture_play(NSString *name, const RCGestureFrame *frames, NSUInteger count, uint64_t sender, double speed, CGSize recorded) {
    g_playCancel = NO;
    g_playTouched = NO;
    g_watchEvents = g_watchSent = g_watchDowns = g_watchMixed = 0;
    g_playResult = @"playing";
    g_playStopOnTouch = rc_gestures_stop_on_touch();
    BOOL dots = rc_gestures_show_touches();
    if (dots) dispatch_async(dispatch_get_main_queue(), ^{ rc_gesture_dots_show(); });
    g_playing = YES;
    __block CGSize screen = CGSizeZero;
    rc_on_main_sync(^{ screen = [UIScreen mainScreen].fixedCoordinateSpace.bounds.size; });
    if (recorded.width > 0 && recorded.height > 0) {
        if (fabs(recorded.width - screen.width) > 1 || fabs(recorded.height - screen.height) > 1) {
            SRLog(@"[Gesture] recorded on %gx%g, playing on %gx%g: scaled", recorded.width, recorded.height, screen.width, screen.height);
        }
        screen = recorded;
    }
    NSUInteger edgeFrames = 0;
    for (NSUInteger k = 0; k < count; k++) for (int j = 0; j < frames[k].count; j++) if (frames[k].fingers[j].edge) { edgeFrames++; break; }
    SRLog(@"[Gesture] playing '%@' at %gx (%lu frames, %lu on an edge), stop on touch %@",
        name, speed, (unsigned long)count, (unsigned long)edgeFrames, g_playStopOnTouch ? @"on" : @"off");
    uint64_t start = mach_absolute_time();
    uint32_t down = 0;
    RCTouchFinger held[32] = {0}; // where each finger down was last sent
    NSUInteger i = 0;
    for (; i < count; i++) {
        if (!rc_gesture_wait_until(start + rc_mach_from_seconds(MAX(0, frames[i].t) / speed))) break;
        rc_gesture_send_frame(&frames[i], &down, screen, sender);
        if (dots) rc_gesture_dots_frame(&frames[i], screen);
        for (int j = 0; j < frames[i].count; j++) held[frames[i].fingers[j].slot & 31] = frames[i].fingers[j];
    }
    if (down) {
        // Stopped mid-stroke. Lifting a moving finger reads as a flick, so a half-done swipe up
        // from the home bar would still go home: the fingers stay still a moment, then let go as
        // a cancelled touch, which iOS drops
        RCGestureFrame still = {0};
        for (uint32_t slot = 0; slot < 32 && still.count < kRCGestureMaxFingers; slot++) {
            if (down & (1u << slot)) still.fingers[still.count++] = held[slot];
        }
        for (int k = 0; k < 6 && still.count; k++) {
            rc_gesture_send_frame(&still, &down, screen, sender);
            mach_wait_until(mach_absolute_time() + rc_mach_from_seconds(0.02));
        }
        for (int j = 0; j < still.count; j++) still.fingers[j].touching = 0;
        rc_gesture_send_frame_ex(&still, &down, screen, sender, 0x80);
        down = 0;
    }
    if (dots) dispatch_async(dispatch_get_main_queue(), ^{ rc_gesture_dots_hide(); });
    g_playResult = g_playTouched ? @"stopped by touch" : g_playCancel ? @"stopped" : @"done";
    SRLog(@"[Gesture] '%@' %@: %u touch events seen, %u of them sent by playback (%u with a real finger inside), %u new fingers",
        name, g_playResult, g_watchEvents, g_watchSent, g_watchMixed, g_watchDowns);
    g_playing = NO;
}

#pragma mark - Commands

// Words of a command, "quoted parts" kept whole
static NSArray<NSString *> *rc_gesture_words(NSString *text) {
    NSMutableArray *words = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    scanner.charactersToBeSkipped = nil;
    NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
    while (!scanner.isAtEnd) {
        [scanner scanCharactersFromSet:space intoString:NULL];
        if (scanner.isAtEnd) break;
        NSString *word = nil;
        if ([scanner scanString:@"\"" intoString:NULL]) {
            [scanner scanUpToString:@"\"" intoString:&word];
            [scanner scanString:@"\"" intoString:NULL];
        } else {
            [scanner scanUpToCharactersFromSet:space intoString:&word];
        }
        [words addObject:word ?: @""];
    }
    return words;
}

NSArray<NSDictionary *> *RCGestureList(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *g in rc_gestures_load()) {
        if (![g[@"name"] isKindOfClass:[NSString class]]) continue;
        [out addObject:@{ @"name": g[@"name"], @"duration": g[@"duration"] ?: @0, @"strokes": g[@"strokes"] ?: @0 }];
    }
    return out;
}

#pragma mark - Tap, hold and swipe

// A touch made up on the spot (gesture tap / hold / swipe), played like a recording. Points are in
// screen points as the screen is turned now (what rc-screen reports); they're turned upright here.
static CGPoint rc_gesture_upright(CGPoint p, CGSize *fixedSize) {
    __block CGPoint out = p;
    __block CGSize size = CGSizeZero;
    rc_on_main_sync(^{
        UIScreen *screen = [UIScreen mainScreen];
        out = [screen.coordinateSpace convertPoint:p toCoordinateSpace:screen.fixedCoordinateSpace];
        size = screen.fixedCoordinateSpace.bounds.size;
    });
    if (fixedSize) *fixedSize = size;
    return out;
}

// The edge a touch starts on (the touchscreen's edge bits >> 24): iOS starts the home bar
// gesture, swipe back and the like only for touches that begin there
static uint8_t rc_gesture_edge(CGPoint p, CGSize size) {
    if (p.y >= size.height - 2) return 0x1; // bottom
    if (p.x <= 2) return 0x8;               // left
    if (p.y <= 2) return 0x2;               // top
    if (p.x >= size.width - 2) return 0x4;  // right
    return 0;
}

// Frames from (x1,y1) to (x2,y2) over `seconds`, lifting at the end; the same point for a tap
// or hold. A still finger keeps reporting, as a real one does, so long presses register.
static NSData *rc_gesture_make(CGPoint from, CGPoint to, double seconds, CGSize size) {
    NSMutableData *data = [NSMutableData data];
    uint8_t edge = rc_gesture_edge(from, size);
    double step = 1.0 / 60;
    int moves = MAX(1, (int)ceil(seconds / step));
    for (int i = 0; i <= moves; i++) {
        double f = (double)i / moves;
        RCGestureFrame frame = {0};
        frame.t = seconds * f;
        frame.count = 1;
        frame.fingers[0].slot = 2;
        frame.fingers[0].touching = 1;
        frame.fingers[0].edge = edge;
        frame.fingers[0].x = from.x + (to.x - from.x) * f;
        frame.fingers[0].y = from.y + (to.y - from.y) * f;
        [data appendBytes:&frame length:sizeof(frame)];
    }
    RCGestureFrame lift = {0};
    lift.t = seconds + step;
    lift.count = 1;
    lift.fingers[0].slot = 2;
    lift.fingers[0].edge = edge;
    lift.fingers[0].x = to.x;
    lift.fingers[0].y = to.y;
    [data appendBytes:&lift length:sizeof(lift)];
    return data;
}

static NSString *rc_gesture_touch_command(NSString *verb, NSArray<NSString *> *words) {
    // gesture tap X Y | hold X Y [SECONDS] | swipe X1 Y1 X2 Y2 [SECONDS]
    BOOL swipe = [verb isEqualToString:@"swipe"];
    NSUInteger points = swipe ? 4 : 2;
    if (words.count < 2 + points) {
        return swipe ? @"Error: Use gesture swipe X1 Y1 X2 Y2 [SECONDS]\n" : [NSString stringWithFormat:@"Error: Use gesture %@ X Y%@\n", verb, [verb isEqualToString:@"hold"] ? @" [SECONDS]" : @""];
    }
    NSCharacterSet *number = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.-"];
    for (NSUInteger i = 2; i < words.count; i++) {
        if (![[words[i] stringByTrimmingCharactersInSet:number] isEqualToString:@""]) return [NSString stringWithFormat:@"Error: Not a number: %@\n", words[i]];
    }
    double seconds = [verb isEqualToString:@"tap"] ? 0.05 : swipe ? 0.3 : 1;
    if (words.count > 2 + points) seconds = MIN(MAX([words[2 + points] doubleValue], 0.02), 30);
    CGSize size = CGSizeZero;
    CGPoint from = rc_gesture_upright(CGPointMake([words[2] doubleValue], [words[3] doubleValue]), &size);
    CGPoint to = swipe ? rc_gesture_upright(CGPointMake([words[4] doubleValue], [words[5] doubleValue]), NULL) : from;
    // A point on the edge (0, or the width) is kept just inside
    from = CGPointMake(MIN(MAX(from.x, 0), size.width - 0.5), MIN(MAX(from.y, 0), size.height - 0.5));
    to = CGPointMake(MIN(MAX(to.x, 0), size.width - 0.5), MIN(MAX(to.y, 0), size.height - 0.5));
    if (g_playing) return @"Error: A gesture is already playing\n";
    uint64_t sender = rc_touch_sender();
    if (!sender) return @"Error: Touch the screen once first (after a respring the touchscreen's ID isn't known yet)\n";
    NSData *frames = rc_gesture_make(from, to, seconds, size);
    NSUInteger count = frames.length / sizeof(RCGestureFrame);
    NSString *name = verb;
    dispatch_block_t play = ^{ rc_gesture_play(name, frames.bytes, count, sender, 1, size); };
    // Waits for the touch to finish, so the next command sees its result; from the main thread
    // (the Web UI) it can't wait
    if ([NSThread isMainThread]) {
        dispatch_async(rc_gesture_play_queue(), play);
    } else {
        dispatch_sync(rc_gesture_play_queue(), play);
        if (g_playTouched) return @"Stopped by a touch\n";
    }
    return [NSString stringWithFormat:@"%@%@\n", [[verb substringToIndex:1] uppercaseString], [verb substringFromIndex:1]];
}

NSString *RCGestureCommand(NSString *cmd) {
    NSArray<NSString *> *words = rc_gesture_words(cmd);
    NSString *verb = words.count > 1 ? words[1].lowercaseString : @"";
    NSString *arg = words.count > 2 ? [words[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : @"";

    if ([@[@"tap", @"hold", @"swipe"] containsObject:verb]) return rc_gesture_touch_command(verb, words);

    if ([verb isEqualToString:@"list"]) {
        NSMutableString *out = [NSMutableString string];
        for (NSDictionary *g in rc_gestures_load()) {
            [out appendFormat:@"%@\t%.1f\t%ld\n", g[@"name"], [g[@"duration"] doubleValue], (long)[g[@"strokes"] integerValue]];
        }
        return out;
    }

    if ([verb isEqualToString:@"record"]) {
        if (!arg.length) return @"Error: Name needed\n";
        __block BOOL busy = NO;
        rc_on_main_sync(^{
            busy = g_recActive;
            if (!busy) rc_gesture_record_start(arg, words.count > 3 && [words[3] isEqualToString:@"return"]);
        });
        return busy ? @"Error: Already recording\n" : [NSString stringWithFormat:@"Recording '%@' in 3 seconds\n", arg];
    }
    if ([verb isEqualToString:@"record-toggle"]) {
        // The Record Gesture action: one run starts recording, the next stops it. Without a name
        // it's named when it stops; with one it's saved under it.
        if (g_namePromptWindow) return @"Error: A recording is waiting for its name\n";
        __block BOOL started = NO;
        rc_on_main_sync(^{
            if (g_recActive) {
                rc_gesture_record_finish_ex(YES, YES);
            } else {
                rc_gesture_record_start(arg.length ? arg : nil, NO);
                started = YES;
            }
        });
        return started ? @"Recording in 3 seconds\n" : [g_recResult stringByAppendingString:@"\n"];
    }
    if ([verb isEqualToString:@"record-stop"] || [verb isEqualToString:@"record-cancel"]) {
        BOOL save = [verb isEqualToString:@"record-stop"];
        rc_on_main_sync(^{ rc_gesture_record_finish(save); });
        return [g_recResult stringByAppendingString:@"\n"];
    }
    if ([verb isEqualToString:@"idle-stop"]) {
        // gesture idle-stop [SECONDS]: Show Stop After (0 never); without a number, the setting
        if (words.count > 2) rc_gestures_set_idle_stop([arg doubleValue]);
        return [NSString stringWithFormat:@"%g\n", rc_gestures_idle_stop()];
    }
    if ([verb isEqualToString:@"play-status"]) {
        return [g_playResult stringByAppendingString:@"\n"];
    }
    if ([verb isEqualToString:@"stop-on-touch"]) {
        // gesture stop-on-touch [on|off]: Stop on Touch; without one, the setting
        if (words.count > 2) {
            NSString *value = arg.lowercaseString;
            if (![@[@"on", @"off"] containsObject:value]) return @"Error: Use on or off\n";
            rc_gestures_set_setting(@"stopOnTouch", @([value isEqualToString:@"on"]));
        }
        return rc_gestures_stop_on_touch() ? @"on\n" : @"off\n";
    }
    if ([verb isEqualToString:@"show-touches"]) {
        // gesture show-touches [on|off]: Show Touches; without one, the setting
        if (words.count > 2) {
            NSString *value = arg.lowercaseString;
            if (![@[@"on", @"off"] containsObject:value]) return @"Error: Use on or off\n";
            rc_gestures_set_setting(@"showTouches", @([value isEqualToString:@"on"]));
        }
        return rc_gestures_show_touches() ? @"on\n" : @"off\n";
    }
    if ([verb isEqualToString:@"tab-size"]) {
        // gesture tab-size [small|medium|large]: Tab Size; without one, the setting
        NSString *size = arg.lowercaseString;
        if (words.count > 2) {
            if (![rc_gestures_tab_sizes() containsObject:size]) return @"Error: Size must be small, medium or large\n";
            rc_gestures_set_setting(@"tabSize", size);
        }
        return [rc_gestures_tab_size() stringByAppendingString:@"\n"];
    }
    if ([verb isEqualToString:@"record-status"]) {
        return [g_recResult stringByAppendingString:@"\n"];
    }

    if ([verb isEqualToString:@"play"] || [verb isEqualToString:@"play-soon"] || [verb isEqualToString:@"play-latest"]) {
        // gesture play "Name" [SPEED] | play-latest [SPEED], with SPEED like 2x or 0.5x
        BOOL latest = [verb isEqualToString:@"play-latest"];
        NSUInteger speedWord = latest ? 2 : 3;
        double speed = words.count > speedWord ? rc_gesture_speed(words[speedWord]) : 1;
        NSArray *list = rc_gestures_load();
        NSDictionary *g = nil;
        if (latest) {
            // The newest recording (a recording again replaces the old one, so it's newest too)
            for (NSDictionary *each in list) {
                if (!g || [each[@"created"] compare:g[@"created"]] == NSOrderedDescending) g = each;
            }
            if (!g) return @"Error: Nothing recorded yet\n";
        } else {
            g = rc_gesture_named(list, arg);
            if (!g) return [NSString stringWithFormat:@"Error: No gesture named '%@'\n", arg];
        }
        if (g_playing) return @"Error: A gesture is already playing\n";
        uint64_t sender = rc_touch_sender();
        if (!sender) return @"Error: Touch the screen once first (after a respring the touchscreen's ID isn't known yet)\n";
        NSUInteger count = 0;
        NSData *frames = rc_gesture_unpack(g[@"frames"], &count);
        if (!count) return @"Error: The gesture is empty\n";
        NSString *name = g[@"name"];
        NSArray *size = g[@"screen"];
        CGSize recorded = [size isKindOfClass:[NSArray class]] && size.count == 2 && [size[0] isKindOfClass:[NSNumber class]] && [size[1] isKindOfClass:[NSNumber class]]
            ? CGSizeMake([size[0] doubleValue], [size[1] doubleValue]) : CGSizeZero;
        dispatch_block_t play = ^{ rc_gesture_play(name, frames.bytes, count, sender, speed, recorded); };
        if ([verb isEqualToString:@"play-soon"]) {
            // From the app's Gestures screen: a second for the app to step aside first
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), rc_gesture_play_queue(), play);
            return [NSString stringWithFormat:@"Playing '%@' in a second\n", name];
        }
        // A trigger's actions run off the main thread and the next one waits for the gesture to
        // finish; a command from the app or rc returns at once
        if ([NSThread isMainThread] || RCCommandFromLocalSocket()) dispatch_async(rc_gesture_play_queue(), play);
        else dispatch_sync(rc_gesture_play_queue(), play);
        return [NSString stringWithFormat:@"Playing '%@'\n", name];
    }
    if ([verb isEqualToString:@"stop"]) {
        g_playCancel = YES;
        return g_playing ? @"Stopping\n" : @"Nothing playing\n";
    }

    if ([verb isEqualToString:@"export"]) {
        // gesture export PATH ["Name" ...]: the named gestures (all without names) as a JSON file,
        // into a temporary folder (the app and rc-mcp pass files that way)
        if (!arg.length) return @"Error: File path needed\n";
        NSString *target = arg.stringByStandardizingPath;
        if (!([target hasPrefix:@"/tmp/"] || [target hasPrefix:@"/private/tmp/"] || [target hasPrefix:@"/var/mobile/tmp/"]) || [target containsString:@"/../"]) {
            return @"Error: Use a path in /tmp or /var/mobile/tmp\n";
        }
        NSArray *list = rc_gestures_load();
        NSMutableArray *chosen = [NSMutableArray array];
        if (words.count > 3) {
            for (NSString *name in [words subarrayWithRange:NSMakeRange(3, words.count - 3)]) {
                NSDictionary *g = rc_gesture_named(list, name);
                if (!g) return [NSString stringWithFormat:@"Error: No gesture named '%@'\n", name];
                [chosen addObject:g];
            }
        } else {
            [chosen addObjectsFromArray:list];
        }
        if (!chosen.count) return @"Error: No gestures to export\n";
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *g in chosen) {
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = g[@"name"];
            entry[@"created"] = @([g[@"created"] isKindOfClass:[NSDate class]] ? [g[@"created"] timeIntervalSince1970] : 0);
            entry[@"duration"] = g[@"duration"] ?: @0;
            entry[@"strokes"] = g[@"strokes"] ?: @0;
            if ([g[@"screen"] isKindOfClass:[NSArray class]]) entry[@"screen"] = g[@"screen"];
            entry[@"frames"] = [g[@"frames"] isKindOfClass:[NSData class]] ? [g[@"frames"] base64EncodedStringWithOptions:0] : @"";
            [out addObject:entry];
        }
        NSDictionary *file = @{ @"type": @"RemoteCompanion Gestures", @"version": @1, @"gestures": out };
        NSData *json = [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted error:NULL];
        if (![json writeToFile:arg atomically:YES]) return @"Error: The file couldn't be written\n";
        return [NSString stringWithFormat:@"Exported %lu\n", (unsigned long)out.count];
    }
    if ([verb isEqualToString:@"import"]) {
        // gesture import PATH: adds the file's gestures; a name already in use gets a number
        NSData *data = arg.length ? [NSData dataWithContentsOfFile:arg] : nil;
        if (!data) return @"Error: The file couldn't be read\n";
        NSDictionary *file = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *entries = [file isKindOfClass:[NSDictionary class]] ? file[@"gestures"] : nil;
        if (![entries isKindOfClass:[NSArray class]]) return @"Error: Not a gestures file\n";
        NSMutableArray *list = rc_gestures_load();
        NSUInteger added = 0;
        for (NSDictionary *entry in entries) {
            if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"name"] isKindOfClass:[NSString class]] || ![entry[@"frames"] isKindOfClass:[NSString class]]) continue;
            NSData *frames = [[NSData alloc] initWithBase64EncodedString:entry[@"frames"] options:0];
            NSUInteger count = 0;
            if (!frames.length || !rc_gesture_unpack(frames, &count) || !count) continue;
            NSString *base = [[entry[@"name"] stringByReplacingOccurrencesOfString:@"\"" withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!base.length) base = @"Gesture";
            NSString *name = base;
            for (NSInteger n = 2; rc_gesture_named(list, name); n++) name = [NSString stringWithFormat:@"%@ %ld", base, (long)n];
            NSMutableDictionary *g = [NSMutableDictionary dictionary];
            g[@"name"] = name;
            // Only numbers where numbers belong: anything else from the file is left out (a string
            // or a list there would crash SpringBoard when it's read as a number)
            id createdValue = entry[@"created"], durationValue = entry[@"duration"], strokesValue = entry[@"strokes"];
            double created = [createdValue isKindOfClass:[NSNumber class]] ? [createdValue doubleValue] : 0;
            g[@"created"] = created > 0 && isfinite(created) ? [NSDate dateWithTimeIntervalSince1970:created] : [NSDate date];
            NSData *unpackedData = rc_gesture_unpack(frames, &count);
            const RCGestureFrame *unpacked = unpackedData.bytes;
            double duration = [durationValue isKindOfClass:[NSNumber class]] && isfinite([durationValue doubleValue]) ? [durationValue doubleValue] : (count ? unpacked[count - 1].t : 0);
            g[@"duration"] = @(MIN(MAX(duration, 0), 3600));
            g[@"strokes"] = [strokesValue isKindOfClass:[NSNumber class]] ? @([strokesValue integerValue]) : @(rc_gesture_stroke_count(unpacked, count));
            NSArray *screen = entry[@"screen"];
            if ([screen isKindOfClass:[NSArray class]] && screen.count == 2 && [screen[0] isKindOfClass:[NSNumber class]] && [screen[1] isKindOfClass:[NSNumber class]] &&
                isfinite([screen[0] doubleValue]) && isfinite([screen[1] doubleValue]) && [screen[0] doubleValue] > 0 && [screen[1] doubleValue] > 0) {
                g[@"screen"] = @[screen[0], screen[1]];
            }
            g[@"frames"] = frames;
            [list addObject:g];
            added++;
        }
        if (!added) return @"Error: No gestures found in the file\n";
        if (!rc_gestures_save(list)) return @"Error: The gestures couldn't be saved\n";
        return [NSString stringWithFormat:@"Imported %lu\n", (unsigned long)added];
    }
    if ([verb isEqualToString:@"delete"]) {
        NSMutableArray *list = rc_gestures_load();
        NSMutableDictionary *g = rc_gesture_named(list, arg);
        if (!g) return [NSString stringWithFormat:@"Error: No gesture named '%@'\n", arg];
        [list removeObject:g];
        rc_gestures_save(list);
        return [NSString stringWithFormat:@"Deleted '%@'\n", arg];
    }
    if ([verb isEqualToString:@"trim"]) {
        // gesture trim "Name" START END: keeps what happened between START and END (seconds) and
        // starts it at 0. A finger down at START starts there; one still down at END lifts there.
        if (words.count < 5) return @"Error: Usage: gesture trim \"Name\" START END\n";
        double from = MAX(0, [words[3] doubleValue]), to = [words[4] doubleValue];
        if (to <= from) return @"Error: The end must come after the start\n";
        NSMutableArray *list = rc_gestures_load();
        NSMutableDictionary *g = rc_gesture_named(list, arg);
        if (!g) return [NSString stringWithFormat:@"Error: No gesture named '%@'\n", arg];
        NSUInteger count = 0;
        NSData *data = rc_gesture_unpack(g[@"frames"], &count);
        const RCGestureFrame *frames = data.bytes;
        NSMutableData *kept = [NSMutableData data];
        NSUInteger keptCount = 0;
        RCGestureFrame last = {0};
        for (NSUInteger i = 0; i < count; i++) {
            if (frames[i].t < from - 1e-6 || frames[i].t > to + 1e-6) continue;
            RCGestureFrame f = frames[i];
            f.t = MAX(0, f.t - from);
            [kept appendBytes:&f length:sizeof(f)];
            keptCount++;
            last = f;
        }
        if (!keptCount) return @"Error: Nothing happens in that part\n";
        // Lift any finger still down where it ends
        RCGestureFrame lift = last;
        int lifting = 0;
        for (int j = 0; j < last.count; j++) {
            if (last.fingers[j].touching) {
                lift.fingers[lifting] = last.fingers[j];
                lift.fingers[lifting].touching = 0;
                lifting++;
            }
        }
        if (lifting) {
            lift.count = lifting;
            lift.t = last.t + 0.008;
            [kept appendBytes:&lift length:sizeof(lift)];
            keptCount++;
        }
        const RCGestureFrame *out = kept.bytes;
        NSUInteger strokes = rc_gesture_stroke_count(out, keptCount);
        if (!strokes) return @"Error: No touches in that part\n";
        g[@"frames"] = rc_gesture_pack(out, keptCount);
        g[@"duration"] = @(out[keptCount - 1].t);
        g[@"strokes"] = @(strokes);
        if (!rc_gestures_save(list)) return @"Error: The gesture couldn't be saved\n";
        return [NSString stringWithFormat:@"Trimmed to %.1f s\n", out[keptCount - 1].t];
    }
    if ([verb isEqualToString:@"rename"]) {
        NSString *to = words.count > 3 ? [words[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : @"";
        if (!to.length) return @"Error: Usage: gesture rename \"Old\" \"New\"\n";
        NSMutableArray *list = rc_gestures_load();
        NSMutableDictionary *g = rc_gesture_named(list, arg);
        if (!g) return [NSString stringWithFormat:@"Error: No gesture named '%@'\n", arg];
        NSMutableDictionary *other = rc_gesture_named(list, to);
        if (other && other != g) return [NSString stringWithFormat:@"Error: '%@' already exists\n", to];
        g[@"name"] = to;
        rc_gestures_save(list);
        return [NSString stringWithFormat:@"Renamed to '%@'\n", to];
    }

    return @"Usage: gesture tap X Y | hold X Y [SECONDS] | swipe X1 Y1 X2 Y2 [SECONDS] | list | record \"Name\" | record-toggle [\"Name\"] | record-stop | record-cancel | record-status | play \"Name\" [SPEED] | play-soon \"Name\" [SPEED] | play-latest [SPEED] | play-status | stop | idle-stop [SECONDS] | tab-size [small|medium|large] | stop-on-touch [on|off] | show-touches [on|off] | export PATH [\"Name\" ...] | import PATH | trim \"Name\" START END | delete \"Name\" | rename \"Old\" \"New\"\n";
}
