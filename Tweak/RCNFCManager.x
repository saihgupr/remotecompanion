#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreNFC/CoreNFC.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>

// Declare the external trigger function from Tweak.x
extern void RCExecuteTrigger(NSString *triggerKey);

// Declare the external logging function from Tweak.x
extern void SRLog(NSString *format, ...);

// Declare the external NFC enabled check
extern BOOL RCIsNFCEnabled();

// Declare the screen-off window from Tweak.x
extern NSTimeInterval RCNFCScreenOffWindow();

// Experimental NFC: iOS's own background tag reader (iPhone XS and later) reads tags while the screen is
// on; the scan below runs only with the screen off. From Tweak.x.
extern BOOL RCNFCBackgroundReading();

// Darwin notifications shared with RCNFCReader (in nfcd)
#define kRCNFCBackgroundState "com.pizzaman.rc.nfc_background"         // state 1: Experimental NFC is on
#define kRCNFCBackgroundTag   "com.pizzaman.rc.nfc_background_tag"     // a tag: state = ID length << 56 | ID bytes

// The scan paused by the NFC Scanner action (Pause / Resume / Toggle) until resumed or a respring.
// Only the scan: with Experimental NFC, tags are still read while the screen is on.
static BOOL g_rcnfcScannerPaused;
// The screen is dark (com.apple.springboard.hasBlankedScreen): SpringBoard's own screen state can lag it
static BOOL g_rcnfcScreenBlanked;

// ============ Private NearField API ============
@class NFReaderSession, NFTag;

@protocol NFReaderSessionDelegate <NSObject>
@optional
- (void)readerSession:(id)session didDetectTags:(NSArray *)tags;
- (void)readerSession:(id)session didDetectTags:(NSArray *)tags connectedTagIndex:(id)index;
- (void)readerSessionDidEndUnexpectedly:(id)session;
@end

@interface NFHardwareManager : NSObject
+ (instancetype)sharedHardwareManager;
- (id)startReaderSessionWithDelegate:(id<NFReaderSessionDelegate>)delegate;
@end

@protocol NFTag <NSObject>
- (NSData *)tagID;
- (unsigned int)type;
@end

// ============ RCNFCManager Interface ============

@interface RCNFCManager : NSObject <NFCTagReaderSessionDelegate, NFReaderSessionDelegate>
@property (nonatomic, strong) NFCTagReaderSession *tagSession;
@property (nonatomic, strong) id privateSession; // NFReaderSession
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, strong) NSDate *lastScanTime;
@property (nonatomic, assign) BOOL wakeHandled;
@property (nonatomic, copy) NSString *lastTagUID;     // the tag read last, and when: held against the phone, it isn't read again
@property (nonatomic, strong) NSDate *lastTagTime;
@property (nonatomic, assign) NSUInteger heldReads;            // reads of the same tag in a row: it is staying on the phone
@property (nonatomic, assign) NSTimeInterval lastRescanDelay;  // how long the scan waited before the read just made
@property (nonatomic, assign) NSTimeInterval rescanLateness;   // how much later than planned the scan that made the read started
@property (nonatomic, strong) NSDate *suspendedUntil; // the app is scanning itself: no restart before then
@property (nonatomic, strong) NSDate *sessionStart;
@property (nonatomic, strong) NSDate *lastActivity;   // the last wake or tag
@property (nonatomic, strong) NSDate *screenOffSince; // when the screen was first seen off, nil while it is on
@property (nonatomic, strong) NSTimer *screenWatch;   // checks the screen while a scan is open
@property (nonatomic, assign) NSUInteger endedEarly;  // sessions iOS ended on its own, in a row
@property (nonatomic, assign) BOOL quiet;             // a routine restart (Wallet still on screen): not logged step by step
@property (nonatomic, assign) BOOL waitingLogged;     // "waiting for the controller" logged for this scan

+ (instancetype)sharedInstance;
- (void)startScanning;
- (void)stopScanning;
- (void)handleScreenWake;
@end

@implementation RCNFCManager

+ (instancetype)sharedInstance {
    static RCNFCManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isScanning = NO;
        _wakeHandled = NO;
        SRLog(@"RCNFCManager initialized");
    }
    return self;
}

// A tag seen again within this long of the last time it was seen is still on the phone, so it is
// not a new tap. Each look takes about a rescan delay plus the time polling needs to start, so
// this has to be longer than that and short enough that taking the tag away for a moment counts.
static const NSTimeInterval kRCNFCRepeatWindow = 1.0;
// A scan starts again this long after a tag was read, while the screen is on
static const NSTimeInterval kRCNFCRescanDelay = 0.3;
// A tag that stays on the phone is looked for less and less often, up to this long between looks:
// a scan started every moment keeps the reader on, which makes nfcd switch it off for a while
static const NSTimeInterval kRCNFCMaxRescanDelay = 5.0;
// The app's own scanner has the reader this long after it asks the tweak to stop
static const NSTimeInterval kRCNFCAppHoldsReader = 120.0;
// nfcd gives the NFC controller to one session at a time, in the order they asked, and doesn't take
// it from a session that has it: while the scan is open, Apple Pay and Wallet wait for it.
// A new scan that is waiting for the controller tries to start polling this often until it gets it
static const NSTimeInterval kRCNFCWaitRetry = 0.5;

// Apple Pay (the side button double-click, or a pass shown on the lock screen) and the Wallet app need
// the NFC controller for the cards: while one of them is on screen, the scan steps aside
static BOOL rcnfc_atLeastIOS15(void) {
    static int answer = -1;
    if (answer < 0) answer = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){15, 0, 0}];
    return answer;
}

// Apple Pay on iOS 14 (the Home button double-click): a transient overlay window, hosting a view from the
// process whose state is given. YES while one is on screen.
static BOOL rcnfc_overlayFromProcess(id state) {
    SEL pidSel = NSSelectorFromString(@"pid");
    int pid = [state respondsToSelector:pidSel] ? ((int (*)(id, SEL))objc_msgSend)(state, pidSel) : 0;
    if (pid <= 0) return NO;
    Class overlayWindow = objc_getClass("SBTransientOverlayWindow");
    if (!overlayWindow) return NO;
    SEL serviceSel = NSSelectorFromString(@"serviceProcessIdentifier");
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.hidden || ![window isKindOfClass:overlayWindow]) continue;
        NSMutableArray *controllers = [NSMutableArray array];
        if (window.rootViewController) [controllers addObject:window.rootViewController];
        for (NSUInteger i = 0; i < controllers.count; i++) {
            UIViewController *controller = controllers[i];
            if ([controller respondsToSelector:serviceSel] && ((int (*)(id, SEL))objc_msgSend)(controller, serviceSel) == pid) return YES;
            [controllers addObjectsFromArray:controller.childViewControllers];
            if (controller.presentedViewController) [controllers addObject:controller.presentedViewController];
        }
    }
    return NO;
}

static BOOL rcnfc_walletOnScreen(void) {
    // The Wallet app in front - while unlocked: locked, it still counts as in front behind the lock screen
    Class lockClass = objc_getClass("SBLockScreenManager");
    SEL sharedLock = NSSelectorFromString(@"sharedInstance"), uiLocked = NSSelectorFromString(@"isUILocked");
    id lockManager = [lockClass respondsToSelector:sharedLock] ? ((id (*)(Class, SEL))objc_msgSend)(lockClass, sharedLock) : nil;
    BOOL locked = [lockManager respondsToSelector:uiLocked] && ((BOOL (*)(id, SEL))objc_msgSend)(lockManager, uiLocked);
    id springBoard = [UIApplication sharedApplication];
    SEL frontSel = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    id front = !locked && [springBoard respondsToSelector:frontSel] ? ((id (*)(id, SEL))objc_msgSend)(springBoard, frontSel) : nil;
    if ([front respondsToSelector:@selector(bundleIdentifier)] && [[front bundleIdentifier] isEqualToString:@"com.apple.Passbook"]) return YES;

    // Apple Pay (the side button double-click, or a pass on the lock screen) runs in these services. They
    // keep running once closed, so what counts is being in front, or running rather than suspended
    // (task state 2; suspended is 3), which on iOS 17 is the sign PassbookUIService is on screen.
    Class controllerClass = objc_getClass("SBApplicationController");
    SEL shared = NSSelectorFromString(@"sharedInstance"), lookup = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (![controllerClass respondsToSelector:shared]) return NO;
    id controller = ((id (*)(Class, SEL))objc_msgSend)(controllerClass, shared);
    if (![controller respondsToSelector:lookup]) return NO;
    for (NSString *bundle in @[@"com.apple.PassbookUIService", @"com.apple.PassbookUISceneService"]) {
        id app = ((id (*)(id, SEL, id))objc_msgSend)(controller, lookup, bundle);
        SEL stateSel = NSSelectorFromString(@"processState");
        id state = [app respondsToSelector:stateSel] ? ((id (*)(id, SEL))objc_msgSend)(app, stateSel) : nil;
        SEL foreground = NSSelectorFromString(@"isForeground"), taskState = NSSelectorFromString(@"taskState");
        BOOL isFront = [state respondsToSelector:foreground] && ((BOOL (*)(id, SEL))objc_msgSend)(state, foreground);
        long long task = [state respondsToSelector:taskState] ? ((long long (*)(id, SEL))objc_msgSend)(state, taskState) : -1;
        if (isFront) return YES;
        // iOS 14 keeps PassbookUIService running whenever the phone is locked, so there it says nothing
        if (task == 2 && rcnfc_atLeastIOS15()) return YES;
        if ([bundle isEqualToString:@"com.apple.PassbookUIService"] && rcnfc_overlayFromProcess(state)) return YES;
    }
    return NO;
}

// Logged only when it changes
static BOOL rcnfc_walletCheck(void) {
    static BOOL wasOnScreen;
    BOOL onScreen = rcnfc_walletOnScreen();
    if (onScreen != wasOnScreen) SRLog(@"[NFC] Wallet / Apple Pay %@", onScreen ? @"on screen - the scan steps aside" : @"closed - scanning again");
    wasOnScreen = onScreen;
    return onScreen;
}

static BOOL rcnfc_screenIsOn(void) {
    Class backlightClass = objc_getClass("SBBacklightController");
    id backlight = backlightClass ? ((id (*)(Class, SEL))objc_msgSend)(backlightClass, NSSelectorFromString(@"sharedInstance")) : nil;
    SEL screenIsOn = NSSelectorFromString(@"screenIsOn");
    if ([backlight respondsToSelector:screenIsOn]) return ((BOOL (*)(id, SEL))objc_msgSend)(backlight, screenIsOn);
    return YES;
}

// Starts a scan again while the screen stays on: a read, or iOS ending the session, closes the
// scan, and without this the next tag waits for the next wake
- (void)scheduleRescanAfter:(NSTimeInterval)delay {
    NSDate *planned = [NSDate dateWithTimeIntervalSinceNow:delay];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.isScanning) return;
        if (self.suspendedUntil && [self.suspendedUntil timeIntervalSinceNow] > 0) {
            SRLog(@"[NFC] Not restarting: the app is scanning");
            self.quiet = NO;
            return;
        }
        if (![self screenOffWindowOpen]) {
            SRLog(@"[NFC] Not restarting: the screen is off and nothing was read for %.0f s", RCNFCScreenOffWindow());
            self.quiet = NO;
            return;
        }
        // Timers stand still while the phone idles with the screen off, so the scan can restart much
        // later than planned. A tag that stayed on the phone meanwhile is the same tap, not a new one.
        self.rescanLateness = MAX(0, -[planned timeIntervalSinceNow]);
        if (self.rescanLateness > 2.0) SRLog(@"[NFC] The restart ran %.0f s late", self.rescanLateness);
        if (!self.quiet) SRLog(@"[NFC] Restarting the scan");
        [self startScanning];
    });
}

- (void)scheduleRescan {
    [self scheduleRescanAfter:kRCNFCRescanDelay];
}

// With the screen off the scan goes on until the window has passed since the screen turned off
// or the last wake or tag, whichever is later (Settings > NFC With Screen Off). YES while the
// screen is on, or the window is still open.
- (BOOL)screenOffWindowOpen {
    if (rcnfc_screenIsOn()) {
        self.screenOffSince = nil;
        return YES;
    }
    if (!self.screenOffSince) self.screenOffSince = [NSDate date];
    NSDate *base = self.lastActivity && [self.lastActivity compare:self.screenOffSince] == NSOrderedDescending ? self.lastActivity : self.screenOffSince;
    return -[base timeIntervalSinceNow] < RCNFCScreenOffWindow();
}

- (void)noteActivity {
    self.lastActivity = [NSDate date];
}

// No callback says the screen has gone dark on every iOS version, so an open scan looks at it
- (void)startScreenWatch {
    [self.screenWatch invalidate];
    self.screenWatch = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        if (!self.isScanning) {
            [timer invalidate];
            self.screenWatch = nil;
            return;
        }
        if (rcnfc_walletCheck()) {
            [self stopScanning];
            [self scheduleRescanAfter:1.0];
            return;
        }
        if ([self screenOffWindowOpen]) return;
        SRLog(@"[NFC] Screen off and nothing read for %.0f s - stopping the scan", RCNFCScreenOffWindow());
        [self stopScanning];
    }];
}

// YES when the tag is the one just read: held against the phone, not a new tap. The longer the
// scan waits between looks, the longer a tag that is still there can go unseen.
- (BOOL)isRepeatOfTag:(NSString *)uid {
    NSTimeInterval window = MAX(kRCNFCRepeatWindow, self.lastRescanDelay + 0.8) + self.rescanLateness;
    BOOL repeat = self.lastTagUID && [self.lastTagUID isEqualToString:uid] && self.lastTagTime &&
                  [[NSDate date] timeIntervalSinceDate:self.lastTagTime] < window;
    self.lastTagUID = uid;
    self.lastTagTime = [NSDate date];
    return repeat;
}

// A new reader session is active a moment after it is created, and polling is refused until then
// ("Session not active"): on iOS 15 and later an immediate call left the scan open but deaf. It is
// tried again a few times.
- (void)startPollingSession:(id)session attempt:(int)attempt {
    if (session != self.privateSession) return;
    NSError *error = nil;
    BOOL polling = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(session, NSSelectorFromString(@"startPollingWithError:"), &error);
    if (polling) {
        if (!self.quiet || attempt > 4) SRLog(@"[NFC] Polling started (attempt %d)", attempt);
        self.quiet = NO;
        return;
    }
    // Error 47: nfcd has switched reader mode off for a while (its heat protection). Try again later
    if (error.code == 47 && attempt >= 20) {
        SRLog(@"[NFC] Polling would not start after %d attempts: %@", attempt, error);
        self.quiet = NO;
        [self stopScanning];
        [self scheduleRescanAfter:30.0];
        return;
    }
    // "Session not active" for more than a moment: another session has the controller (Wallet, an
    // app). This one is next in line: keep trying until it gets the controller, then poll at once.
    NSTimeInterval wait = 0.25;
    if (attempt >= 20) {
        if (!self.waitingLogged) SRLog(@"[NFC] Waiting for the NFC controller: %@", error.localizedDescription);
        self.waitingLogged = YES;
        wait = kRCNFCWaitRetry;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self startPollingSession:session attempt:attempt + 1];
    });
}

- (void)startScanning {
    if (!RCIsNFCEnabled()) {
        SRLog(@"[NFC] Scanning is DISABLED in settings, skipping");
        return;
    }

    if (self.isScanning) {
        SRLog(@"[NFC] Already scanning, skipping");
        return;
    }

    if (g_rcnfcScannerPaused) {
        if (!self.quiet) SRLog(@"[NFC] The scanner is paused (NFC Scanner action) - not scanning");
        self.quiet = NO;
        return;
    }

    // Experimental NFC: with the screen on, iOS reads the tags itself and the scan stays out of the way
    if (RCNFCBackgroundReading() && !g_rcnfcScreenBlanked && rcnfc_screenIsOn()) {
        if (!self.quiet) SRLog(@"[NFC] Screen on with Experimental NFC: iOS reads the tags - not scanning");
        self.quiet = NO;
        return;
    }

    // Wallet or Apple Pay is using the controller: look again in a moment
    if (rcnfc_walletCheck()) {
        self.quiet = YES; // looked at every second until it closes: not logged each time
        [self scheduleRescanAfter:1.0];
        return;
    }

    // Debounce: a start right after another one (several wake hooks fire together)
    if (self.lastScanTime && [[NSDate date] timeIntervalSinceDate:self.lastScanTime] < 0.3) {
        SRLog(@"[NFC] Skipping scan (debounce) - trying again shortly");
        [self scheduleRescanAfter:0.4];
        return;
    }

    if (!self.quiet) SRLog(@"[NFC] Starting NFC Session...");
    [self stopScanning];

    self.isScanning = YES;
    self.waitingLogged = NO;
    self.lastScanTime = [NSDate date];
    self.sessionStart = [NSDate date];

    // Force load NearField
    void *nfHandle = dlopen("/System/Library/PrivateFrameworks/NearField.framework/NearField", RTLD_NOW);
    if (!self.quiet) SRLog(@"[NFC] NearField framework loaded: %@", nfHandle ? @"YES" : @"NO");

    // Try Private API
    Class nfManager = NSClassFromString(@"NFHardwareManager");
    if (!self.quiet) SRLog(@"[NFC] NFHardwareManager class: %@", nfManager ? @"FOUND" : @"NOT FOUND");
    
    BOOL privateStarted = NO;
    if (nfManager && [nfManager respondsToSelector:@selector(sharedHardwareManager)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id manager = [nfManager performSelector:@selector(sharedHardwareManager)];
        if (!self.quiet) SRLog(@"[NFC] sharedHardwareManager: %@", manager ? @"GOT" : @"NIL");
        
        if (manager) {
            SEL startWithDelSel = NSSelectorFromString(@"startReaderSessionWithDelegate:");
            SEL startSel = NSSelectorFromString(@"startReaderSession:");
            id session = nil;

            if ([manager respondsToSelector:startWithDelSel]) {
                session = [manager performSelector:startWithDelSel withObject:self];
                if (!self.quiet || !session) SRLog(@"[NFC] Private Session started via startReaderSessionWithDelegate: %@", session ? @"SUCCESS" : @"FAILED");
            } else if ([manager respondsToSelector:startSel]) {
                session = [manager performSelector:startSel withObject:nil];
                if (!self.quiet || !session) SRLog(@"[NFC] Private Session started via startReaderSession: %@", session ? @"SUCCESS" : @"FAILED");
            } else {
                SRLog(@"[NFC] No known start session selector found!");
            }

            if (session) {
                self.privateSession = session;
                
                // Try various delegate setters
                if ([session respondsToSelector:NSSelectorFromString(@"setDelegate:")]) {
                    [session performSelector:NSSelectorFromString(@"setDelegate:") withObject:self];
                    if (!self.quiet) SRLog(@"[NFC] Set delegate via setDelegate:");
                } else if ([session respondsToSelector:NSSelectorFromString(@"setSessionDelegate:")]) {
                    [session performSelector:NSSelectorFromString(@"setSessionDelegate:") withObject:self];
                    if (!self.quiet) SRLog(@"[NFC] Set delegate via setSessionDelegate:");
                }

                if ([session respondsToSelector:NSSelectorFromString(@"startPollingWithError:")]) {
                    [self startPollingSession:session attempt:1];
                    privateStarted = YES;
                } else if ([session respondsToSelector:NSSelectorFromString(@"startPolling")]) {
                    BOOL polling = ((BOOL (*)(id, SEL))objc_msgSend)(session, NSSelectorFromString(@"startPolling"));
                    SRLog(@"[NFC] startPolling: %@", polling ? @"YES" : @"NO");
                    privateStarted = YES;
                } else {
                    SRLog(@"[NFC] Session doesn't respond to startPolling!");
                }
            }
        }
#pragma clang diagnostic pop
    }

    if (privateStarted) {
        if (!self.quiet) SRLog(@"[NFC] Using Private API - scan active");
        [self startScreenWatch];
        return;
    }

    // Fallback to Public API
    SRLog(@"[NFC] Private API failed, trying Public CoreNFC...");
    if ([NFCTagReaderSession readingAvailable]) {
        self.tagSession = [[NFCTagReaderSession alloc] initWithPollingOption:(NFCPollingISO14443 | NFCPollingISO15693) delegate:self queue:dispatch_get_main_queue()];
        self.tagSession.alertMessage = @"Scan tag...";
        [self.tagSession beginSession];
        SRLog(@"[NFC] Started Public Tag Session");
    } else {
        SRLog(@"[NFC] NFC not supported (CoreNFC)");
        self.isScanning = NO;
        return;
    }

    // Auto-stop after 5 seconds to save battery
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.isScanning) {
            SRLog(@"[NFC] Scan timed out (5s limit) - Stopping to save battery.");
            [self stopScanning];
        }
    });
}

- (void)stopScanning {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if (self.tagSession) { 
        [self.tagSession invalidateSession]; 
        self.tagSession = nil; 
        SRLog(@"[NFC] Stopped public tag session");
    }
    if (self.privateSession) {
        if ([self.privateSession respondsToSelector:NSSelectorFromString(@"endSession")]) {
            [self.privateSession performSelector:NSSelectorFromString(@"endSession")];
        }
        self.privateSession = nil;
        if (!self.quiet) SRLog(@"[NFC] Stopped private session");
    }
#pragma clang diagnostic pop
    [self.screenWatch invalidate];
    self.screenWatch = nil;
    self.isScanning = NO;
}

- (void)handleScreenWake {
    if (!RCIsNFCEnabled()) {
        return;
    }
    // Experimental NFC: iOS reads the tags while the screen is on. These wake hooks also fire as the
    // screen goes dark, so they leave the scan alone: the screen-dark notification starts and ends it.
    if (RCNFCBackgroundReading()) {
        return;
    }

    // Prevent duplicate handling within short window
    if (self.wakeHandled) {
        SRLog(@"[NFC-WAKE] Wake already handled recently, skipping");
        return;
    }
    self.wakeHandled = YES;
    self.suspendedUntil = nil;
    self.quiet = NO;
    [self noteActivity];
    
    // Reset wake flag after 1 second (was 3s)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.wakeHandled = NO;
    });
    
    SRLog(@"[NFC-WAKE] Screen wake detected - waiting 500ms before NFC...");
    self.rescanLateness = 0;
    
    // Delay before starting NFC to let hardware warm up after sleep
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        SRLog(@"[NFC-WAKE] Delay complete, starting NFC scan");
        [self startScanning];
    });
}

// MARK: - Shared Processing

// Helper to get clean hex string from data
static NSString *sr_hexStringFromData(NSData *data) {
    const unsigned char *dataBuffer = (const unsigned char *)[data bytes];
    if (!dataBuffer) return @"";
    NSUInteger dataLength = [data length];
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];
    for (int i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02X", (unsigned int)dataBuffer[i]];
    }
    return [hexString copy];
}

- (void)processTag:(id<NFCTag>)tag session:(id)session {
    NSData *uidData = nil;
    if (tag.type == NFCTagTypeMiFare) {
        if ([tag conformsToProtocol:@protocol(NFCMiFareTag)]) {
            uidData = [(id<NFCMiFareTag>)tag identifier];
        }
    } else if (tag.type == NFCTagTypeISO15693) {
        if ([tag conformsToProtocol:@protocol(NFCISO15693Tag)]) {
            uidData = [(id<NFCISO15693Tag>)tag identifier];
        }
    } else if (tag.type == NFCTagTypeISO7816Compatible) {
        if ([tag conformsToProtocol:@protocol(NFCISO7816Tag)]) {
            uidData = [(id<NFCISO7816Tag>)tag identifier];
        }
    }
    
    if (uidData) {
        NSString *uidString = sr_hexStringFromData(uidData);
        NSString *triggerKey = [NSString stringWithFormat:@"nfc_%@", uidString];
        SRLog(@"Tag UID: %@ -> Trigger Key: %@", uidString, triggerKey);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            SRLog(@"Executing trigger: %@", triggerKey);
            // Haptic Feedback
            AudioServicesPlaySystemSound(1520);
            RCExecuteTrigger(triggerKey);
            
            if ([session isKindOfClass:[NFCTagReaderSession class]]) {
                ((NFCTagReaderSession *)session).alertMessage = [NSString stringWithFormat:@"Triggered: %@", uidString];
                [(NFCTagReaderSession *)session invalidateSession];
            } else if ([session isKindOfClass:[NFCNDEFReaderSession class]]) {
                ((NFCNDEFReaderSession *)session).alertMessage = [NSString stringWithFormat:@"Triggered: %@", uidString];
                [(NFCNDEFReaderSession *)session invalidateSession];
            }
        });
    } else {
        SRLog(@"Could not read UID");
        if ([session isKindOfClass:[NFCTagReaderSession class]]) {
            [(NFCTagReaderSession *)session invalidateSessionWithErrorMessage:@"Unknown ID"];
        } else if ([session isKindOfClass:[NFCNDEFReaderSession class]]) {
            [(NFCNDEFReaderSession *)session invalidateSessionWithErrorMessage:@"Unknown ID"];
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate

- (void)tagReaderSession:(NFCTagReaderSession *)session didDetectTags:(NSArray<__kindof id<NFCTag>> *)tags {
    SRLog(@"Tag Detected (Tag Session): %lu tags found", (unsigned long)tags.count);
    if (tags.count > 0) {
        id<NFCTag> tag = tags.firstObject;
        SRLog(@"Connecting to tag type: %ld", (long)tag.type);
        [session connectToTag:tag completionHandler:^(NSError * _Nullable error) {
            if (error) {
                SRLog(@"Connection to tag failed: %@", error);
                [session invalidateSessionWithErrorMessage:@"Connection failed"];
                return;
            }
            SRLog(@"Connected to tag successfully");
            [self processTag:tag session:session];
        }];
    }
}

- (void)tagReaderSession:(NFCTagReaderSession *)session didInvalidateWithError:(NSError *)error {
    SRLog(@"Tag Session Invalidated: %@", error);
    if (session == self.tagSession) self.isScanning = NO;
}



// MARK: - NFReaderSessionDelegate (Private)

- (void)readerSession:(id)session didDetectTags:(NSArray *)tags connectedTagIndex:(id)index {
    SRLog(@"Private API (3-arg): didDetectTags count=%lu", (unsigned long)tags.count);
    [self readerSession:session didDetectTags:tags];
}

- (void)didDetectTags:(NSArray *)tags connectedTagIndex:(id)index {
    SRLog(@"Private API (short 2-arg): didDetectTags count=%lu", (unsigned long)tags.count);
    [self readerSession:nil didDetectTags:tags];
}

- (void)didDetectTags:(NSArray *)tags {
    SRLog(@"Private API (short 1-arg): didDetectTags count=%lu", (unsigned long)tags.count);
    [self readerSession:nil didDetectTags:tags];
}

- (void)readerSession:(id)session didDetectTags:(NSArray *)tags {
    SRLog(@"Private API (2-arg): didDetectTags count=%lu", (unsigned long)tags.count);
    for (id tag in tags) {
        SRLog(@"Detected private tag: %@", tag);
        NSData *uidData = nil;
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        if ([tag respondsToSelector:@selector(tagID)]) {
            uidData = [tag performSelector:NSSelectorFromString(@"tagID")];
        } else if ([tag respondsToSelector:@selector(UID)]) {
            uidData = [tag performSelector:NSSelectorFromString(@"UID")];
        } else if ([tag respondsToSelector:@selector(identifier)]) {
            uidData = [tag performSelector:NSSelectorFromString(@"identifier")];
        }
#pragma clang diagnostic pop
        
        if (uidData) {
            NSString *uidString = sr_hexStringFromData(uidData);
            NSString *triggerKey = [NSString stringWithFormat:@"nfc_%@", uidString];
            SRLog(@"Private Tag UID: %@ -> Trigger Key: %@", uidString, triggerKey);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL repeat = [self isRepeatOfTag:uidString];
                SRLog(@"[NFC] Tag read with the screen %@", rcnfc_screenIsOn() ? @"on" : @"off");
                if (repeat) {
                    SRLog(@"[NFC] Same tag as a moment ago - not triggering again");
                } else {
                    // Haptic Feedback
                    AudioServicesPlaySystemSound(1520);
                    RCExecuteTrigger(triggerKey);
                }
                self.endedEarly = 0;
                [self noteActivity];
                [self stopScanning];
                // Looking again: quickly after a new tap, then 0.3 s, 0.6 s, 1.2 s ... while the same tag stays
                self.heldReads = repeat ? self.heldReads + 1 : 0;
                NSTimeInterval delay = self.heldReads == 0 ? kRCNFCRescanDelay
                    : MIN(kRCNFCRescanDelay * pow(2.0, (double)(self.heldReads - 1)), kRCNFCMaxRescanDelay);
                self.lastRescanDelay = delay;
                [self scheduleRescanAfter:delay];
            });
        } else {
            SRLog(@"Could not extract UID from private tag: %@", tag);
        }
    }
}

- (void)didEndUnexpectedly {
    SRLog(@"Private API (short): didEndUnexpectedly");
    [self readerSessionDidEndUnexpectedly:nil];
}

- (void)readerSessionDidEndUnexpectedly:(id)session {
    NSTimeInterval lasted = self.sessionStart ? -[self.sessionStart timeIntervalSinceNow] : 0;
    SRLog(@"Private NFC Session ended unexpectedly after %.1f s", lasted);
    if (session != nil && session != self.privateSession) return;
    self.isScanning = NO;
    // A session that ends again and again at once is left alone, so it can't loop
    self.endedEarly = lasted < 5.0 ? self.endedEarly + 1 : 0;
    if (self.endedEarly <= 3) [self scheduleRescan];
    else SRLog(@"[NFC] The session keeps ending - not restarting until the next wake");
}

@end


// ============ HOOKS ============

// OPTION 1: Multiple wake detection hooks for reliability

%hook CSCoverSheetViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SRLog(@"[NFC-WAKE] CSCoverSheetViewController viewWillAppear");
    [[RCNFCManager sharedInstance] handleScreenWake];
}
%end

%hook SBBacklightController
- (void)turnOnScreenIsUserAction:(BOOL)isUserAction {
    %orig;
    SRLog(@"[NFC-WAKE] SBBacklightController turnOnScreenIsUserAction: %d", isUserAction);
    [[RCNFCManager sharedInstance] handleScreenWake];
}

- (void)setBacklightLevel:(float)level {
    %orig;
    SRLog(@"[NFC] Backlight level %.2f (scanning: %@)", level, [[RCNFCManager sharedInstance] isScanning] ? @"yes" : @"no");
    if (level == 0) {
        SRLog(@"[NFC] Screen turned OFF (level 0) - stopping scan");
        [[RCNFCManager sharedInstance] stopScanning];
    }
}
%end

// Additional hook: SBScreenWakeAnimationController - fires during wake animation
%hook SBScreenWakeAnimationController
- (void)_handleAnimationCompletionIfNeeded {
    %orig;
    SRLog(@"[NFC-WAKE] SBScreenWakeAnimationController _handleAnimationCompletionIfNeeded");
    [[RCNFCManager sharedInstance] handleScreenWake];
}
%end

// Additional hook: SBLockScreenManager - early wake detection
%hook SBLockScreenManager
- (void)_handleBacklightLevelWillChange:(id)notification {
    %orig;
    SRLog(@"[NFC-WAKE] SBLockScreenManager _handleBacklightLevelWillChange");
    [[RCNFCManager sharedInstance] handleScreenWake];
}
%end

#import <notify.h>

static void stop_nfc_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    SRLog(@"[NFC] Received stop_nfc notification - yielding to app");
    [RCNFCManager sharedInstance].suspendedUntil = [NSDate dateWithTimeIntervalSinceNow:kRCNFCAppHoldsReader];
    [[RCNFCManager sharedInstance] stopScanning];
}

static void resume_nfc_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    SRLog(@"[NFC] Received resume_nfc notification - the app is done");
    RCNFCManager *manager = [RCNFCManager sharedInstance];
    manager.suspendedUntil = nil;
    [manager noteActivity];
    // A page that has just read a tag takes a moment to let go of the reader: on iOS 14 a scan
    // started sooner reports that it is polling and hears nothing for the rest of the session
    [manager scheduleRescanAfter:2.5];
}

// Experimental NFC on or off (settings changed, or at start): RCNFCReader in nfcd is told, and the scan
// starts or stops to match the screen
void RCNFCConfigChanged(void) {
    static int token = NOTIFY_TOKEN_INVALID;
    if (token == NOTIFY_TOKEN_INVALID) notify_register_check(kRCNFCBackgroundState, &token);
    BOOL on = RCNFCBackgroundReading();
    uint64_t previous = 2;
    notify_get_state(token, &previous);
    if (previous == (on ? 1 : 0)) return;
    notify_set_state(token, on ? 1 : 0);
    notify_post(kRCNFCBackgroundState);
    SRLog(@"[NFC] Experimental NFC %@", on ? @"on: iOS reads tags while the screen is on" : @"off");
    RCNFCManager *manager = [RCNFCManager sharedInstance];
    if (!rcnfc_screenIsOn()) return;
    if (on) [manager stopScanning];
    else [manager startScanning];
}

// The NFC Scanner action: "pause", "resume" or "toggle"; returns the state after it
NSString *RCNFCScannerCommand(NSString *what) {
    RCNFCManager *manager = [RCNFCManager sharedInstance];
    BOOL pause = [what isEqualToString:@"pause"] ? YES : [what isEqualToString:@"resume"] ? NO : !g_rcnfcScannerPaused;
    if (![what isEqualToString:@"pause"] && ![what isEqualToString:@"resume"] && ![what isEqualToString:@"toggle"]) {
        return g_rcnfcScannerPaused ? @"paused" : @"running";
    }
    if (pause != g_rcnfcScannerPaused) {
        g_rcnfcScannerPaused = pause;
        SRLog(@"[NFC] Scanner %@ (NFC Scanner action)", pause ? @"paused" : @"resumed");
        if (pause) {
            [manager stopScanning];
        } else {
            [manager noteActivity];
            manager.rescanLateness = 0;
            [manager startScanning];
        }
    }
    return g_rcnfcScannerPaused ? @"paused" : @"running";
}

// A tag iOS's own reader detected (Experimental NFC), from RCNFCReader in nfcd
static void rcnfc_backgroundTag(uint64_t state) {
    unsigned length = (unsigned)(state >> 56);
    if (length == 0 || length > 7 || !RCIsNFCEnabled() || !RCNFCBackgroundReading()) return;
    NSMutableString *uid = [NSMutableString string];
    for (int i = (int)length - 1; i >= 0; i--) [uid appendFormat:@"%02X", (unsigned)((state >> (8 * i)) & 0xFF)];
    RCNFCManager *manager = [RCNFCManager sharedInstance];
    [manager noteActivity];
    if ([manager isRepeatOfTag:uid]) {
        SRLog(@"[NFC] Same tag as a moment ago (iOS reader) - not triggering again");
        return;
    }
    SRLog(@"[NFC] Tag %@ read by iOS (Experimental NFC)", uid);
    AudioServicesPlaySystemSound(1520);
    RCExecuteTrigger([@"nfc_" stringByAppendingString:uid]);
}

%ctor {
    %init;

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        stop_nfc_callback,
        CFSTR("com.pizzaman.rc.stop_nfc"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        resume_nfc_callback,
        CFSTR("com.pizzaman.rc.resume_nfc"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
        
    SRLog(@"[NFC-WAKE] RCNFCManager hooks initialized - multi-hook wake detection active");

    // Experimental NFC: tags from iOS's own reader, and the screen going dark (the scan runs only then)
    int tagToken;
    notify_register_dispatch(kRCNFCBackgroundTag, &tagToken, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        notify_get_state(t, &state);
        rcnfc_backgroundTag(state);
    });
    int blankToken;
    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &blankToken, dispatch_get_main_queue(), ^(int t) {
        uint64_t blanked = 0;
        notify_get_state(t, &blanked);
        g_rcnfcScreenBlanked = blanked != 0;
        if (!RCIsNFCEnabled() || !RCNFCBackgroundReading()) return;
        RCNFCManager *manager = [RCNFCManager sharedInstance];
        if (!blanked) {
            if (manager.isScanning) {
                SRLog(@"[NFC] Screen on with Experimental NFC - ending the screen-off scan");
                [manager stopScanning];
            }
            return;
        }
        if (RCNFCScreenOffWindow() <= 0) return;
        if (g_rcnfcScannerPaused) {
            SRLog(@"[NFC] Screen off with Experimental NFC - the scanner is paused (NFC Scanner action)");
            return;
        }
        // Screen off: tags can be tapped for the screen-off window (Settings > NFC With Screen Off)
        SRLog(@"[NFC] Screen off with Experimental NFC - scanning for %.0f s", RCNFCScreenOffWindow());
        manager.screenOffSince = [NSDate date];
        [manager noteActivity];
        manager.rescanLateness = 0;
        [manager startScanning];
    });
    // Tell nfcd once the settings are readable
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RCNFCConfigChanged(); });
}


