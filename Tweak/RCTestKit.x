// On-device test kit - see RCTestKit.h.
//
// Everything is plain JSON over /api/testkit/ (and "testkit ..." on the UNIX socket), with
// results returned synchronously, so a test runner or an agent can drive the device and
// check outcomes without scraping the text log:
//
//   GET  /api/testkit/info              what this build supports
//   GET  /api/testkit/probe             snapshot of the device state that tests check
//   GET  /api/testkit/journal?since=N   events after seq N (&type=prefix, &limit=); the journal records
//                                       only while the test kit is in use (a run, or a request in the
//                                       last 10 minutes), so a client's first request turns it on
//   POST /api/testkit/journal/clear
//   POST /api/testkit/mark?label=...    a labelled marker, e.g. the start of a test step
//   POST /api/testkit/run               body (or ?cmd=): a command; returns its output
//   POST /api/testkit/capture?on=1|0    dry-run: triggers are recorded, actions don't run
//   POST /api/testkit/snapshot          save device state and config (a restore is owed until restore runs;
//                                       if SpringBoard restarts first, the tweak restores at launch)
//   POST /api/testkit/restore           put them back
//   POST /api/testkit/lua               body (or ?code=): Lua; returns what it printed and returned
//   GET  /api/testkit/suites            the test suites
//   POST /api/testkit/suite/run?name=   run one (conditions, toggles, all, guided, differential, replay);
//                                       &wait=1 returns the report when done (or after 5 minutes);
//                                       toggles: &disruptive=1 adds Wi-Fi etc.;
//                                       guided / differential / replay: &steps=id,id:3 runs only those, each
//                                       the given number of times (default 1, or &repeat=N);
//                                       guided: &auto=1 does the screen gestures, lock and unlock itself;
//                                       differential: &replay=1 replays the presses (hands off) and adds
//                                       a timing sweep, &states=locked|unlocked|both picks the starting state
//   GET  /api/testkit/suite/steps?name= the steps of guided / differential / replay on this device, grouped,
//                                       in the order they run (guided: &auto=1 for automatic mode)
//   POST /api/testkit/suite/skip        skip the current guided step; suite/stop ends the run
//   GET  /api/testkit/report[?id=]      the current/last run, or a saved one; &redact=1 replaces personal
//                                       values (Wi-Fi / Bluetooth names, third-party app ids) with placeholders
//                                       and adds "redacted": true if there were any
//   GET  /api/testkit/reports           saved reports: ids, and a summary of each
//   POST /api/testkit/report/delete?id= delete a saved report; reports/clear deletes them all
//   GET  /api/testkit/passcode          whether a passcode is set for unlocking during tests, and for how long
//   POST /api/testkit/passcode/forget   forget it now
//        testkit passcode/set code=...  (UNIX socket only - the Test Kit screen; refused over the network)
//   POST /api/testkit/unlock            unlock the phone with it (wakes the screen first)
//   POST /api/testkit/replay            body (or ?seq=): simulated button presses at exact times, e.g.
//                                       "vU@0 vD@7 ^D@125 ^U@147" (v = down, ^ = up; U / D = Volume Up /
//                                       Down, H = Home, P = Power; @ms from the start). Triggers are captured, not run
//                                       (&capture=0 runs them); returns what the HID listener saw and which
//                                       triggers fired within &settle= ms (default 1500) of the last event;
//                                       &jitter=N moves every gap by up to +/- N ms, keeping the order

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <notify.h>
#import <unistd.h>
#import <sys/utsname.h>
#import <mach/mach_time.h>
#import <pthread.h>
#import "RCTestKit.h"

extern void SRLog(NSString *format, ...);
extern BOOL RCCommandFromLocalSocket(void);
extern void RCTouchEvent(double x, double y, BOOL down);
extern void RCTouchEventSystemGesture(double x, double y, BOOL down);
extern void RCTouchSetBottomEdge(BOOL on);

@interface SBFluidSwitcherScreenEdgePanGestureRecognizer : UIScreenEdgePanGestureRecognizer
@end

static const NSUInteger kRCTKJournalCapacity = 4000;
static NSString *const kRCTKSnapshotPath = @"/var/mobile/Documents/rc_testkit_snapshot.plist";

static NSMutableArray<NSDictionary *> *g_tkEvents;
static unsigned long long g_tkNextSeq = 1;
static BOOL g_tkCapture = NO;
// suite/skip and suite/stop: a run checks these between steps and while it waits, so Stop
// takes effect at once - a replay or scripted touch in progress lets go of what it holds
static volatile BOOL g_tkSkipStep = NO;
static volatile BOOL g_tkStopRun = NO;

// Waits, cut short if the run is stopped; NO if it was
static BOOL RCTKSleep(NSTimeInterval seconds) {
    double end = [[NSDate date] timeIntervalSince1970] + seconds;
    while (!g_tkStopRun) {
        double left = end - [[NSDate date] timeIntervalSince1970];
        if (left <= 0) return YES;
        [NSThread sleepForTimeInterval:MIN(left, 0.05)];
    }
    [NSThread sleepForTimeInterval:0.01]; // loops waiting on something else don't spin
    return NO;
}
// Changes on every respring, so a client following the journal sees it restart from seq 1
static NSString *g_tkSession;

static NSObject *RCTKLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [NSObject new];
        g_tkEvents = [NSMutableArray arrayWithCapacity:kRCTKJournalCapacity];
    });
    return lock;
}

static double RCTKNowMs(void) {
    return [[NSDate date] timeIntervalSince1970] * 1000.0;
}

#pragma mark - Journal

// Returns the event's sequence number
static unsigned long long RCTKRecord(NSString *type, NSDictionary *info) {
    NSMutableDictionary *event = [NSMutableDictionary dictionaryWithCapacity:info.count + 3];
    if (info) [event addEntriesFromDictionary:info];
    event[@"t"] = @(RCTKNowMs());
    event[@"type"] = type;
    unsigned long long seq;
    @synchronized (RCTKLock()) {
        seq = g_tkNextSeq++;
        event[@"seq"] = @(seq);
        [g_tkEvents addObject:event];
        if (g_tkEvents.count > kRCTKJournalCapacity) {
            [g_tkEvents removeObjectsInRange:NSMakeRange(0, g_tkEvents.count - kRCTKJournalCapacity)];
        }
    }
    return seq;
}

// In use: a run in progress, or a test kit request (the app's Test Kit screen polls while
// it's open) in the last 10 minutes
static volatile BOOL g_tkRunning = NO;
static volatile CFAbsoluteTime g_tkLastUse = -1e9;

BOOL RCTKJournalOn(void) {
    return g_tkRunning || CFAbsoluteTimeGetCurrent() - g_tkLastUse < 600;
}

void RCTKRecordEvent(NSString *type, NSDictionary *info) {
    if (type) RCTKRecord(type, info);
}

// The proximity sensor's last report (1 near, 0 far, -1 none since the respring) - kept apart
// from the journal, which is off when the test kit isn't in use and drops old events anyway
static volatile int g_tkProximity = -1;

void RCTKNoteProximity(BOOL near) {
    g_tkProximity = near ? 1 : 0;
    RCTKEvent(@"hid.proximity", @{ @"near": @(near) });
}

static NSDictionary *RCTKJournal(unsigned long long since, NSString *typePrefix, NSUInteger limit) {
    NSMutableArray *events = [NSMutableArray array];
    unsigned long long next, oldest;
    @synchronized (RCTKLock()) {
        for (NSDictionary *event in g_tkEvents) {
            if ([event[@"seq"] unsignedLongLongValue] <= since) continue;
            if (typePrefix.length && ![event[@"type"] hasPrefix:typePrefix]) continue;
            [events addObject:event];
            if (limit && events.count >= limit) break;
        }
        next = events.count ? [[events.lastObject objectForKey:@"seq"] unsignedLongLongValue] : MAX(since, g_tkNextSeq - 1);
        oldest = g_tkEvents.count ? [g_tkEvents.firstObject[@"seq"] unsignedLongLongValue] : g_tkNextSeq;
    }
    return @{ @"events": events, @"next": @(next), @"oldest": @(oldest), @"session": g_tkSession ?: @"" };
}

#pragma mark - Capture (dry-run)

BOOL RCTKCaptureTrigger(NSString *triggerKey) {
    if (!g_tkCapture) return NO;
    RCTKEvent(@"trigger.captured", @{ @"key": triggerKey ?: @"" });
    return YES;
}

#pragma mark - Probe

static id RCTKSend(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (!target || ![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, sel);
}

// For BOOL / integer getters: nil when the selector isn't there
static NSNumber *RCTKSendLong(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (!target || ![target respondsToSelector:sel]) return nil;
    return @(((long (*)(id, SEL))objc_msgSend)(target, sel));
}

static NSNumber *RCTKSendBool(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (!target || ![target respondsToSelector:sel]) return nil;
    return @(((BOOL (*)(id, SEL))objc_msgSend)(target, sel));
}

static id RCTKShared(NSString *className, NSString *accessor) {
    return RCTKSend(NSClassFromString(className), accessor);
}

static NSString *RCTKStatus(NSString *command) {
    NSString *output = RCHandleCommand(command);
    return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

static NSString *RCTKPackageVersion(void) {
    static NSString *version;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *path in @[@"/var/jb/var/lib/dpkg/status", @"/var/lib/dpkg/status"]) {
            // Rootful package databases are large and can hold descriptions that aren't valid
            // UTF-8, which fails a strict read of the whole file - fall back to Latin-1
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (!data) continue;
            NSString *status = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
            NSRange pkg = [status rangeOfString:@"Package: com.saihgupr.remotecompanion\n"];
            if (pkg.location == NSNotFound) continue;
            NSString *rest = [status substringFromIndex:pkg.location];
            NSRange end = [rest rangeOfString:@"\n\n"];
            if (end.location != NSNotFound) rest = [rest substringToIndex:end.location];
            for (NSString *line in [rest componentsSeparatedByString:@"\n"]) {
                if ([line hasPrefix:@"Version: "]) version = [line substringFromIndex:9];
            }
            break;
        }
    });
    return version ?: @"unknown";
}

static NSDictionary *RCTKLatestPhoto(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dcim = @"/var/mobile/Media/DCIM";
    NSString *latest = nil;
    NSDate *latestDate = nil;
    NSSet *media = [NSSet setWithArray:@[@"heic", @"jpg", @"jpeg", @"png", @"gif", @"mov", @"mp4"]];
    for (NSString *folder in [fm contentsOfDirectoryAtPath:dcim error:nil]) {
        NSString *dir = [dcim stringByAppendingPathComponent:folder];
        for (NSString *file in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            if (![media containsObject:file.pathExtension.lowercaseString]) continue;
            NSDate *date = [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:file] error:nil][NSFileModificationDate];
            if (date && (!latestDate || [date compare:latestDate] == NSOrderedDescending)) {
                latestDate = date;
                latest = file;
            }
        }
    }
    if (!latest) return @{};
    return @{ @"file": latest, @"t": @([latestDate timeIntervalSince1970] * 1000.0) };
}

// light: only the fast reads (for polling) - no device info, status commands, photos or config
static NSDictionary *RCTKProbeWith(BOOL light) {
    NSMutableDictionary *probe = [NSMutableDictionary dictionary];
    probe[@"t"] = @(RCTKNowMs());

    struct utsname systemInfo;
    uname(&systemInfo);
    if (!light) probe[@"device"] = @{
        @"model": @(systemInfo.machine),
        @"ios": [UIDevice currentDevice].systemVersion ?: @"",
        @"jailbreak": [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"rootless" : @"rootful",
        @"tweakVersion": RCTKPackageVersion()
    };

    // SpringBoard UI state - read on the main thread
    __block NSMutableDictionary *ui = [NSMutableDictionary dictionary];
    void (^readUI)(void) = ^{
        id sb = [UIApplication sharedApplication];
        ui[@"screenOn"] = RCTKSendBool(RCTKShared(@"SBBacklightController", @"sharedInstance"), @"screenIsOn") ?: [NSNull null];
        ui[@"locked"] = RCTKSendBool(RCTKShared(@"SBLockScreenManager", @"sharedInstance"), @"isUILocked") ?: [NSNull null];
        id frontApp = RCTKSend(sb, @"_accessibilityFrontMostApplication");
        ui[@"frontApp"] = RCTKSend(frontApp, @"bundleIdentifier") ?: @"com.apple.springboard";
        ui[@"siriVisible"] = RCTKSendBool(NSClassFromString(@"SBAssistantController"), @"isVisible") ?: [NSNull null];
        ui[@"controlCenterVisible"] = RCTKSendBool(RCTKShared(@"SBControlCenterController", @"sharedInstanceIfExists"), @"isVisible") ?: @NO;
        // Spotlight (a swipe down on the home screen), and the Today view / App Library
        id iconController = RCTKShared(@"SBIconController", @"sharedInstance");
        ui[@"spotlightVisible"] = RCTKSendBool(iconController, @"isAnySearchVisibleOrTransitioning") ?: @NO;
        ui[@"homeOverlayVisible"] = RCTKSendBool(iconController, @"isShowingHomeScreenOverlay") ?: @NO;
        id switcher = RCTKShared(@"SBMainSwitcherViewController", @"sharedInstanceIfExists");
        ui[@"switcherVisible"] = RCTKSendBool(switcher, @"isMainSwitcherVisible") ?: RCTKSendBool(RCTKShared(@"SBMainSwitcherControllerCoordinator", @"sharedInstance"), @"isAnySwitcherVisible") ?: [NSNull null];
        ui[@"rotationLocked"] = RCTKSendBool(RCTKShared(@"SBOrientationLockManager", @"sharedInstance"), @"isUserLocked") ?: [NSNull null];
        ui[@"darkMode"] = @((BOOL)([UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark));

        // Ringer: the ring/silent switch (iOS 14's SpringBoard has no ringerControl)
        id ringer = RCTKSend(sb, @"ringerControl");
        NSNumber *muted = RCTKSendBool(ringer, @"_accessibilityIsRingerMuted") ?: RCTKSendBool(ringer, @"isRingerMuted");
        if (!muted) {
            NSNumber *state = RCTKSendLong(sb, @"ringerSwitchState");
            if (state) muted = @((BOOL)(((int)state.longValue) == 0));
        }
        ui[@"ringerMuted"] = muted ?: [NSNull null];

        id wifi = RCTKShared(@"SBWiFiManager", @"sharedInstance");
        ui[@"wifiEnabled"] = RCTKSendBool(wifi, @"wiFiEnabled") ?: [NSNull null];

        // What's playing, from SpringBoard's media controller (the condition asks MediaRemote)
        id media = RCTKShared(@"SBMediaController", @"sharedInstance");
        NSNumber *playing = RCTKSendBool(media, @"isPlaying");
        id nowPlaying = RCTKSend(media, @"nowPlayingApplication");
        // Without a now-playing app, SpringBoard's paused flag can't be trusted either way: it
        // was set with MediaRemote saying Paused (a session that outlived its app) and with
        // MediaRemote saying Unknown (nothing played since a respring). Unknown then.
        BOOL paused = [RCTKSendBool(media, @"isPaused") boolValue];
        if (playing.boolValue) ui[@"player"] = @"PLAYING";
        else if (nowPlaying) ui[@"player"] = paused ? @"PAUSED" : [NSNull null];
        else if (paused) ui[@"player"] = [NSNull null];
        else ui[@"player"] = playing ? @"STOPPED" : [NSNull null];
        // The status bar's orientation (the condition asks SpringBoard's active orientation)
        NSNumber *orientation = RCTKSendLong(sb, @"statusBarOrientation");
        ui[@"orientation"] = orientation ? (orientation.longValue >= 3 ? @"LANDSCAPE" : @"PORTRAIT") : [NSNull null];
        // Recording (or mirroring) the screen
        ui[@"screenCaptured"] = @([UIScreen mainScreen].isCaptured);
        ui[@"wifiNetwork"] = RCTKSend(wifi, @"currentNetworkName") ?: [NSNull null];
    };
    if ([NSThread isMainThread]) readUI(); else dispatch_sync(dispatch_get_main_queue(), readUI);
    [probe addEntriesFromDictionary:ui];

    // Audio volume (0-1)
    id av = RCTKShared(@"AVSystemController", @"sharedAVSystemController");
    SEL activeSel = NSSelectorFromString(@"getActiveCategoryVolume:andName:");
    if ([av respondsToSelector:activeSel]) {
        float volume = -1;
        NSString *name = nil;
        if (((BOOL (*)(id, SEL, float *, NSString **))objc_msgSend)(av, activeSel, &volume, &name)) probe[@"volume"] = @(volume);
    }

    dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
    probe[@"bluetoothPowered"] = RCTKSendBool(RCTKShared(@"BluetoothManager", @"sharedInstance"), @"powered") ?: [NSNull null];
    probe[@"lowPowerMode"] = @([NSProcessInfo processInfo].isLowPowerModeEnabled);

    id torch = ((id (*)(id, SEL, NSString *))objc_msgSend)(NSClassFromString(@"AVCaptureDevice"), NSSelectorFromString(@"defaultDeviceWithMediaType:"), @"vide");
    NSNumber *torchMode = RCTKSendLong(torch, @"torchMode");
    probe[@"flashlightOn"] = torchMode ? @((BOOL)(torchMode.longValue == 1)) : [NSNull null];

    id mc = RCTKShared(@"MCProfileConnection", @"sharedConnection");
    id maxInactivity = [mc respondsToSelector:NSSelectorFromString(@"userValueForSetting:")]
        ? ((id (*)(id, SEL, NSString *))objc_msgSend)(mc, NSSelectorFromString(@"userValueForSetting:"), @"maxInactivity") : nil;
    if (maxInactivity) probe[@"autoLockSeconds"] = @([maxInactivity intValue]);

    if (light) return probe;

    // Vibration in Silent / Ring mode (iOS 17: the Haptics menu sets both); unset means on
    CFPreferencesAppSynchronize(CFSTR("com.apple.springboard"));
    for (NSArray *pair in @[@[@"silent-vibrate", @"silentVibration"], @[@"ring-vibrate", @"ringVibration"]]) {
        Boolean valid = false;
        Boolean on = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)pair[0], CFSTR("com.apple.springboard"), &valid);
        probe[pair[1]] = @((BOOL)(valid ? on : YES));
    }

    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;
    probe[@"battery"] = @{
        @"level": @(device.batteryLevel),
        @"charging": @((BOOL)(device.batteryState == UIDeviceBatteryStateCharging || device.batteryState == UIDeviceBatteryStateFull))
    };

    // States only the status commands know how to read
    probe[@"status"] = @{
        @"dnd": RCTKStatus(@"dnd status"),
        @"airplane": RCTKStatus(@"airplane status"),
        @"cellular": RCTKStatus(@"cell status"),
        @"location": RCTKStatus(@"location status")
    };

    probe[@"latestPhoto"] = RCTKLatestPhoto();

    NSDictionary *config = RCCopyTriggerConfig();
    probe[@"tweak"] = @{
        @"masterEnabled": @([config[@"masterEnabled"] boolValue]),
        @"triggerCount": @([config[@"triggers"] count]),
        @"capture": @(g_tkCapture)
    };
    return probe;
}

static NSDictionary *RCTKProbe(void) {
    return RCTKProbeWith(NO);
}

#pragma mark - Snapshot / restore

// A trigger config with the test kit's own bindings taken out: a trigger whose only action is
// the test kit's placeholder is off, with no actions. A real config never has them, so if the
// live one does, an earlier run's restore was missed - they must not be saved as the user's.
static NSDictionary *RCTKWithoutTestBindings(NSDictionary *config) {
    NSMutableDictionary *triggers = [config[@"triggers"] mutableCopy];
    BOOL changed = NO;
    for (NSString *key in [triggers allKeys]) {
        NSDictionary *trigger = triggers[key];
        if (![trigger isKindOfClass:[NSDictionary class]] || ![trigger[@"actions"] isEqual:@[@"testkit noop"]]) continue;
        NSMutableDictionary *clean = [trigger mutableCopy];
        clean[@"enabled"] = @NO;
        clean[@"actions"] = @[];
        triggers[key] = clean;
        changed = YES;
    }
    if (!changed) return config;
    NSMutableDictionary *clean = [config mutableCopy];
    clean[@"triggers"] = triggers;
    return clean;
}

// The snapshot on disk says whether a restore is still owed ("restorePending"): a run that
// SpringBoard restarted in the middle of never got to restore, so the tweak does it at launch
// (see the %ctor), and a new snapshot doesn't replace one that's still owed - the earlier one is
// the user's real state.
static NSDictionary *RCTKTakeSnapshot(void) {
    NSDictionary *owed = [NSDictionary dictionaryWithContentsOfFile:kRCTKSnapshotPath];
    if ([owed[@"restorePending"] boolValue]) {
        RCTKEvent(@"testkit.snapshot", @{ @"kept": @"an earlier snapshot still owed a restore" });
        return owed;
    }
    NSDictionary *probe = RCTKProbe();
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    snapshot[@"t"] = probe[@"t"];
    for (NSString *key in @[@"wifiEnabled", @"bluetoothPowered", @"lowPowerMode", @"rotationLocked", @"darkMode", @"flashlightOn", @"volume", @"autoLockSeconds"]) {
        if (probe[key] && probe[key] != [NSNull null]) snapshot[key] = probe[key];
    }
    NSString *dnd = [probe[@"status"][@"dnd"] uppercaseString];
    if ([dnd containsString:@"ON"] || [dnd containsString:@"OFF"]) snapshot[@"dndOn"] = @((BOOL)([dnd containsString:@"ON"] && ![dnd containsString:@"OFF"]));
    NSDictionary *config = RCCopyTriggerConfig();
    if (config) snapshot[@"config"] = RCTKWithoutTestBindings(config);
    snapshot[@"restorePending"] = @YES;
    [snapshot writeToFile:kRCTKSnapshotPath atomically:YES];
    RCTKEvent(@"testkit.snapshot", nil);
    return snapshot;
}

static NSDictionary *RCTKRestore(void) {
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:kRCTKSnapshotPath];
    if (!snapshot) return @{ @"error": @"no snapshot" };

    NSMutableArray *commands = [NSMutableArray array];
    if (snapshot[@"config"] && ![snapshot[@"config"] isEqual:RCCopyTriggerConfig()]) {
        RCSetTriggerConfig(snapshot[@"config"]);
        [commands addObject:@"(config restored)"];
    }

    NSDictionary *now = RCTKProbe();
    void (^restore)(NSString *, NSString *, NSString *) = ^(NSString *key, NSString *onCommand, NSString *offCommand) {
        id want = snapshot[key];
        if (!want || [now[key] isEqual:want]) return;
        [commands addObject:[want boolValue] ? onCommand : offCommand];
    };
    restore(@"wifiEnabled", @"wifi on", @"wifi off");
    restore(@"bluetoothPowered", @"bluetooth on", @"bluetooth off");
    restore(@"lowPowerMode", @"lpm on", @"lpm off");
    restore(@"rotationLocked", @"rotate lock", @"rotate unlock");
    restore(@"darkMode", @"appearance dark", @"appearance light");
    restore(@"flashlightOn", @"flashlight on", @"flashlight off");
    if (snapshot[@"dndOn"]) {
        NSString *dndNow = [now[@"status"][@"dnd"] uppercaseString];
        BOOL isOn = [dndNow containsString:@"ON"] && ![dndNow containsString:@"OFF"];
        if (isOn != [snapshot[@"dndOn"] boolValue]) [commands addObject:[snapshot[@"dndOn"] boolValue] ? @"dnd on" : @"dnd off"];
    }
    if (snapshot[@"autoLockSeconds"] && ![now[@"autoLockSeconds"] isEqual:snapshot[@"autoLockSeconds"]]) {
        int seconds = [snapshot[@"autoLockSeconds"] intValue];
        [commands addObject:seconds >= INT_MAX ? @"autolock never" : [NSString stringWithFormat:@"autolock %d", seconds]];
    }
    if (snapshot[@"volume"] && fabs([now[@"volume"] doubleValue] - [snapshot[@"volume"] doubleValue]) > 0.01) {
        [commands addObject:[NSString stringWithFormat:@"set-vol %.2f", [snapshot[@"volume"] doubleValue] * 100.0]];
    }

    NSMutableArray *results = [NSMutableArray array];
    for (NSString *command in commands) {
        if ([command hasPrefix:@"("]) { [results addObject:@{ @"command": command }]; continue; }
        [results addObject:@{ @"command": command, @"output": RCTKStatus(command) }];
    }
    NSMutableDictionary *done = [snapshot mutableCopy];
    done[@"restorePending"] = @NO;
    [done writeToFile:kRCTKSnapshotPath atomically:YES];
    RCTKEvent(@"testkit.restore", @{ @"commands": commands });
    return @{ @"restored": results };
}


#pragma mark - Suites

// A suite run: started over HTTP (suite/run), executed on a background queue, results
// recorded as they happen (report, and test.result events in the journal), saved as JSON
// under kRCTKReportsDir when done.

static NSString *const kRCTKReportsDir = @"/var/mobile/Documents/rc_testkit_reports";
static NSMutableDictionary *g_tkRun; // the run in progress, or the last one

static void RCTKRecordResult(NSMutableDictionary *run, NSString *testId, NSString *status, NSDictionary *detail, double ms) {
    NSMutableDictionary *result = [@{ @"id": testId, @"status": status } mutableCopy];
    // A step's name, as the step list shows it; a repeat ("id#2") gets its number
    // Stock vs Tweak runs a step from each starting state ("id.locked", "id.unlocked")
    NSString *prefix = [run[@"suite"] stringByAppendingString:@"."];
    if (prefix && [testId hasPrefix:prefix]) {
        NSArray *parts = [[testId substringFromIndex:prefix.length] componentsSeparatedByString:@"#"];
        NSArray *idAndState = [parts.firstObject componentsSeparatedByString:@"."];
        NSString *state = idAndState.count > 1 ? @{ @"locked": @"From the lock screen", @"unlocked": @"From the home screen" }[idAndState[1]] : nil;
        NSString *name, *note;
        @synchronized (run) { name = run[@"stepNames"][idAndState[0]]; note = run[@"stepNotes"][idAndState[0]]; }
        if (state) note = note ? [NSString stringWithFormat:@"%@. %@", state, note] : state;
        if (name) result[@"name"] = parts.count > 1 ? [NSString stringWithFormat:@"%@ (%@)", name, parts[1]] : name;
        if (note) result[@"note"] = note;
    }
    if (detail.count) result[@"detail"] = detail;
    if (ms >= 0) result[@"ms"] = @(round(ms));
    @synchronized (run) { [run[@"tests"] addObject:result]; }
    RCTKEvent(@"test.result", result);
}

static BOOL RCTKCondition(NSString *key, NSString *value) {
    return RCEvaluateIfCondition(@{ @"conditionKey": key, @"expectedValue": value });
}

// "ON"/"OFF" from a probe boolean or a status line ("DND OFF"); nil if unknown
static NSString *RCTKOnOff(id state) {
    if (!state || state == [NSNull null]) return nil;
    if ([state isKindOfClass:[NSString class]]) {
        NSString *upper = [state uppercaseString];
        if ([upper containsString:@"OFF"]) return @"OFF";
        if ([upper containsString:@"ON"]) return @"ON";
        return nil;
    }
    return [state boolValue] ? @"ON" : @"OFF";
}

// The cheap part of the probe, for polling while waiting on a change
static NSDictionary *RCTKProbeLight(void) {
    return RCTKProbeWith(YES);
}

#pragma mark Conditions suite

// Every If condition, evaluated with the device left as it is: enumerated conditions must
// read TRUE for exactly one value, and that value must match the device state where the
// probe can read it independently
static void RCTKSuiteConditions(NSMutableDictionary *run) {
    NSDictionary *p = RCTKProbe();
    NSDictionary *status = p[@"status"];

    NSString *autolock = nil;
    int seconds = [p[@"autoLockSeconds"] intValue];
    if (p[@"autoLockSeconds"]) {
        if (seconds >= INT_MAX) autolock = @"NEVER";
        else if (seconds == 30) autolock = @"30S";
        else if (seconds % 60 == 0 && seconds / 60 >= 1 && seconds / 60 <= 5) autolock = [NSString stringWithFormat:@"%dM", seconds / 60];
    }
    id none = [NSNull null];
    NSString *(^yesNo)(id, NSString *, NSString *) = ^NSString *(id state, NSString *yes, NSString *no) {
        if (!state || state == [NSNull null]) return nil;
        return [state boolValue] ? yes : no;
    };

    // key, values, the value the device state says should be TRUE (or null if unreadable)
    NSArray *specs = @[
        @[@"lock", @[@"LOCKED", @"UNLOCKED"], yesNo(p[@"locked"], @"LOCKED", @"UNLOCKED") ?: none],
        @[@"autolock", @[@"30S", @"1M", @"2M", @"3M", @"4M", @"5M", @"NEVER"], autolock ?: none],
        @[@"player", @[@"PLAYING", @"PAUSED", @"STOPPED"], p[@"player"] ?: none],
        @[@"wifi", @[@"ON", @"OFF"], RCTKOnOff(p[@"wifiEnabled"]) ?: none],
        @[@"bluetooth", @[@"ON", @"OFF"], RCTKOnOff(p[@"bluetoothPowered"]) ?: none],
        @[@"cellular", @[@"ON", @"OFF"], RCTKOnOff(status[@"cellular"]) ?: none],
        @[@"location", @[@"ON", @"OFF"], RCTKOnOff(status[@"location"]) ?: none],
        @[@"airplane", @[@"ON", @"OFF"], RCTKOnOff(status[@"airplane"]) ?: none],
        @[@"dnd", @[@"ON", @"OFF"], RCTKOnOff(status[@"dnd"]) ?: none],
        @[@"lpm", @[@"ON", @"OFF"], RCTKOnOff(p[@"lowPowerMode"]) ?: none],
        @[@"ringer", @[@"SILENT", @"RING"], yesNo(p[@"ringerMuted"], @"SILENT", @"RING") ?: none],
        @[@"silent_vibration", @[@"ON", @"OFF"], RCTKOnOff(p[@"silentVibration"]) ?: none],
        @[@"ring_vibration", @[@"ON", @"OFF"], RCTKOnOff(p[@"ringVibration"]) ?: none],
        @[@"orientation", @[@"PORTRAIT", @"LANDSCAPE"], p[@"orientation"] ?: none],
        @[@"rotation_lock", @[@"LOCKED", @"UNLOCKED"], yesNo(p[@"rotationLocked"], @"LOCKED", @"UNLOCKED") ?: none],
        @[@"appearance", @[@"DARK", @"LIGHT"], yesNo(p[@"darkMode"], @"DARK", @"LIGHT") ?: none],
        @[@"flashlight", @[@"ON", @"OFF"], RCTKOnOff(p[@"flashlightOn"]) ?: none],
        @[@"screenrecord", @[@"ACTIVE", @"INACTIVE"], yesNo(p[@"screenCaptured"], @"ACTIVE", @"INACTIVE") ?: none],
        @[@"charging", @[@"CHARGING", @"NOT_CHARGING"], yesNo(p[@"battery"][@"charging"], @"CHARGING", @"NOT_CHARGING") ?: none],
        // The sensor's last report; with none yet, whoever runs the test is looking at the
        // phone, so nothing should cover it
        @[@"proximity", @[@"NEAR", @"FAR"], g_tkProximity == 1 ? @"NEAR" : @"FAR"],
        @[@"screen", @[@"ON", @"OFF"], RCTKOnOff(p[@"screenOn"]) ?: none],
    ];

    for (NSArray *spec in specs) {
        NSString *key = spec[0];
        NSArray *values = spec[1];
        id truth = spec[2];
        double start = RCTKNowMs();
        NSMutableArray *trueValues = [NSMutableArray array];
        for (NSString *value in values) {
            if (RCTKCondition(key, value)) [trueValues addObject:value];
        }
        double ms = RCTKNowMs() - start;
        // Auto-Lock can be set to a value the condition doesn't list (e.g. 10 minutes)
        BOOL zeroAllowed = [key isEqualToString:@"autolock"] && truth == none;
        BOOL exclusive = trueValues.count == 1 || (zeroAllowed && trueValues.count == 0);
        RCTKRecordResult(run, [NSString stringWithFormat:@"conditions.%@.exclusive", key], exclusive ? @"pass" : @"fail",
                         @{ @"true": trueValues, @"values": values }, ms);
        if (truth != none) {
            BOOL matches = trueValues.count == 1 && [trueValues[0] isEqualToString:truth];
            NSMutableDictionary *detail = [@{ @"state": truth, @"true": trueValues } mutableCopy];
            if ([key isEqualToString:@"proximity"] && g_tkProximity < 0) detail[@"assumed"] = @"nothing covers the proximity sensor (it hasn't reported since the respring)";
            RCTKRecordResult(run, [NSString stringWithFormat:@"conditions.%@.matchesState", key], matches ? @"pass" : @"fail", detail, -1);
        } else {
            RCTKRecordResult(run, [NSString stringWithFormat:@"conditions.%@.matchesState", key], @"skip",
                             @{ @"reason": @"the probe can't read this state" }, -1);
        }
    }

    // One expectation: the condition with this value should read `expected`
    void (^expect)(NSString *, NSString *, NSString *, BOOL) = ^(NSString *testId, NSString *key, NSString *value, BOOL expected) {
        double start = RCTKNowMs();
        BOOL got = RCTKCondition(key, value);
        RCTKRecordResult(run, testId, got == expected ? @"pass" : @"fail",
                         @{ @"condition": key, @"value": value, @"expected": @(expected), @"got": @(got) }, RCTKNowMs() - start);
    };

    // Day of week: today, tomorrow, the weekday/weekend groups, a list
    NSArray *days = @[@"SUN", @"MON", @"TUE", @"WED", @"THU", @"FRI", @"SAT"];
    NSInteger weekday = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday fromDate:[NSDate date]]; // 1 = Sunday
    NSString *today = days[weekday - 1], *tomorrow = days[weekday % 7];
    BOOL isWeekend = weekday == 1 || weekday == 7;
    expect(@"conditions.day_of_week.today", @"day_of_week", today, YES);
    expect(@"conditions.day_of_week.tomorrow", @"day_of_week", tomorrow, NO);
    expect(@"conditions.day_of_week.weekdays", @"day_of_week", @"WEEKDAYS", !isWeekend);
    expect(@"conditions.day_of_week.weekends", @"day_of_week", @"WEEKENDS", isWeekend);
    expect(@"conditions.day_of_week.list", @"day_of_week", [NSString stringWithFormat:@"%@,%@", tomorrow, today], YES);

    // Time of day: a range around now, and one starting an hour from now
    NSDateComponents *now = [[NSCalendar currentCalendar] components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[NSDate date]];
    NSInteger minutes = now.hour * 60 + now.minute;
    NSString *(^hhmm)(NSInteger) = ^NSString *(NSInteger m) {
        m = ((m % 1440) + 1440) % 1440;
        return [NSString stringWithFormat:@"%02ld:%02ld", (long)(m / 60), (long)(m % 60)];
    };
    expect(@"conditions.time_between.now", @"time_between", [NSString stringWithFormat:@"%@-%@", hhmm(minutes - 60), hhmm(minutes + 60)], YES);
    expect(@"conditions.time_between.later", @"time_between", [NSString stringWithFormat:@"%@-%@", hhmm(minutes + 60), hhmm(minutes + 120)], NO);

    // Thresholds around the current battery level and volume
    double battery = [p[@"battery"][@"level"] doubleValue] * 100.0;
    if (battery >= 10 && battery <= 90) {
        expect(@"conditions.battery.above", @"battery", [NSString stringWithFormat:@"ABOVE %.0f", battery - 5], YES);
        expect(@"conditions.battery.below", @"battery", [NSString stringWithFormat:@"BELOW %.0f", battery + 5], YES);
        expect(@"conditions.battery.notAbove", @"battery", [NSString stringWithFormat:@"ABOVE %.0f", battery + 5], NO);
    } else {
        RCTKRecordResult(run, @"conditions.battery", @"skip", @{ @"reason": @"battery level too close to 0 or 100", @"level": @(battery) }, -1);
    }
    if (p[@"volume"]) {
        double volume = [p[@"volume"] doubleValue] * 100.0;
        if (volume >= 10 && volume <= 90) {
            expect(@"conditions.volume.above", @"volume", [NSString stringWithFormat:@"ABOVE %.0f", volume - 5], YES);
            expect(@"conditions.volume.below", @"volume", [NSString stringWithFormat:@"BELOW %.0f", volume + 5], YES);
            expect(@"conditions.volume.notAbove", @"volume", [NSString stringWithFormat:@"ABOVE %.0f", volume + 5], NO);
        } else {
            RCTKRecordResult(run, @"conditions.volume", @"skip", @{ @"reason": @"volume too close to 0 or 100", @"level": @(volume) }, -1);
        }
    }

    // Names: the current Wi-Fi network (exact and lowercase), and ones that don't exist
    NSString *ssid = [p[@"wifiNetwork"] isKindOfClass:[NSString class]] ? p[@"wifiNetwork"] : nil;
    if (ssid.length) {
        expect(@"conditions.wifi_network.current", @"wifi_network", ssid, YES);
        expect(@"conditions.wifi_network.caseInsensitive", @"wifi_network", ssid.lowercaseString, YES);
    } else {
        RCTKRecordResult(run, @"conditions.wifi_network.current", @"skip", @{ @"reason": @"not on Wi-Fi" }, -1);
    }
    expect(@"conditions.wifi_network.other", @"wifi_network", @"RCTK No Such Network", NO);
    expect(@"conditions.bt_device.other", @"bt_device", @"RCTK No Such Device", NO);

    // Focus (iOS 15+): Off / Any Focus / the active one by name, against "focus status". A
    // build without Focus answers nothing; iOS 14 says it needs iOS 15.
    NSString *focus = RCTKStatus(@"focus status");
    if (focus.length == 0 || [focus hasPrefix:@"Focus requires"] || [focus hasPrefix:@"Error"]) {
        RCTKRecordResult(run, @"conditions.focus", @"skip", @{ @"reason": focus.length ? focus : @"no Focus support in this build" }, -1);
    } else {
        BOOL off = [focus isEqualToString:@"Off"];
        expect(@"conditions.focus.off", @"focus", @"OFF", off);
        expect(@"conditions.focus.any", @"focus", @"ON", !off);
        if (!off) {
            expect(@"conditions.focus.current", @"focus", focus, YES);
            expect(@"conditions.focus.caseInsensitive", @"focus", focus.lowercaseString, YES);
        }
        expect(@"conditions.focus.other", @"focus", @"RCTK No Such Focus", NO);
    }

    NSString *front = p[@"frontApp"];
    if (front.length && ![front isEqualToString:@"com.apple.springboard"]) {
        expect(@"conditions.front_app.current", @"front_app", front, YES);
    }
    expect(@"conditions.front_app.other", @"front_app", @"com.example.rctk.none", NO);
}

#pragma mark Toggles suite

// Waits until read() returns `want` (polling), up to timeout. Returns the ms it took, or -1.
static double RCTKWaitFor(id (^read)(void), id want, double timeoutMs, id *last) {
    double start = RCTKNowMs();
    while (YES) {
        id now = read();
        if (last) *last = now;
        if ([now isEqual:want]) return RCTKNowMs() - start;
        if (RCTKNowMs() - start > timeoutMs) return -1;
        RCTKSleep(0.1);
    }
}

// Runs `command`, then waits for read() to report `want`; records the step and then whether
// the matching If condition agrees with the new state
static void RCTKToggleStep(NSMutableDictionary *run, NSString *testId, NSString *command, id (^read)(void), id want,
                           NSString *conditionKey, NSString *conditionValue) {
    NSString *output = [RCHandleCommand(command) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    id last = nil;
    double ms = RCTKWaitFor(read, want, 3000, &last);
    RCTKRecordResult(run, testId, ms >= 0 ? @"pass" : @"fail",
                     @{ @"command": command, @"output": output, @"want": want ?: [NSNull null], @"got": last ?: [NSNull null] }, ms);
    if (conditionKey && ms >= 0) {
        BOOL holds = RCTKCondition(conditionKey, conditionValue);
        RCTKRecordResult(run, [testId stringByAppendingString:@".condition"], holds ? @"pass" : @"fail",
                         @{ @"condition": conditionKey, @"value": conditionValue, @"got": @(holds) }, -1);
    }
}

// Each toggle: on/off commands, the toggle command, how to read it back, the matching
// condition, and whether it disrupts connectivity or other apps (run only on request)
static NSArray *RCTKToggleSpecs(void) {
    id (^probeBool)(NSString *) = ^id(NSString *key) {
        return ^id { return RCTKOnOff(RCTKProbeLight()[key]); };
    };
    id (^statusOnOff)(NSString *) = ^id(NSString *command) {
        return ^id { return RCTKOnOff(RCTKStatus(command)); };
    };
    return @[
        @{ @"name": @"lpm", @"on": @"lpm on", @"off": @"lpm off", @"toggle": @"lpm toggle", @"read": probeBool(@"lowPowerMode"), @"condition": @"lpm" },
        @{ @"name": @"rotationLock", @"on": @"rotate lock", @"off": @"rotate unlock", @"toggle": @"rotate toggle", @"read": probeBool(@"rotationLocked"), @"condition": @"rotation_lock", @"conditionOn": @"LOCKED", @"conditionOff": @"UNLOCKED" },
        @{ @"name": @"appearance", @"on": @"appearance dark", @"off": @"appearance light", @"toggle": @"appearance toggle", @"read": probeBool(@"darkMode"), @"condition": @"appearance", @"conditionOn": @"DARK", @"conditionOff": @"LIGHT" },
        @{ @"name": @"flashlight", @"on": @"flashlight on", @"off": @"flashlight off", @"toggle": @"flashlight toggle", @"read": probeBool(@"flashlightOn"), @"condition": @"flashlight" },
        @{ @"name": @"dnd", @"on": @"dnd on", @"off": @"dnd off", @"toggle": @"dnd toggle", @"read": statusOnOff(@"dnd status"), @"condition": @"dnd" },
        @{ @"name": @"bluetooth", @"on": @"bluetooth on", @"off": @"bluetooth off", @"toggle": @"bluetooth toggle", @"read": probeBool(@"bluetoothPowered"), @"condition": @"bluetooth", @"disruptive": @YES },
        @{ @"name": @"wifi", @"on": @"wifi on", @"off": @"wifi off", @"toggle": @"wifi toggle", @"read": probeBool(@"wifiEnabled"), @"condition": @"wifi", @"disruptive": @YES },
        @{ @"name": @"location", @"on": @"location on", @"off": @"location off", @"toggle": @"location toggle", @"read": statusOnOff(@"location status"), @"condition": @"location", @"disruptive": @YES },
        @{ @"name": @"cellular", @"on": @"cellular on", @"off": @"cellular off", @"read": statusOnOff(@"cell status"), @"condition": @"cellular", @"disruptive": @YES },
        @{ @"name": @"airplane", @"on": @"airplane on", @"off": @"airplane off", @"read": statusOnOff(@"airplane status"), @"condition": @"airplane", @"disruptive": @YES },
    ];
}

static void RCTKSuiteToggles(NSMutableDictionary *run, BOOL disruptive) {
    for (NSDictionary *spec in RCTKToggleSpecs()) {
        if (g_tkStopRun) break;
        NSString *name = spec[@"name"];
        if ([spec[@"disruptive"] boolValue] && !disruptive) {
            RCTKRecordResult(run, [NSString stringWithFormat:@"toggles.%@", name], @"skip", @{ @"reason": @"disruptive - run with disruptive=1" }, -1);
            continue;
        }
        id (^read)(void) = spec[@"read"];
        NSString *initial = read();
        if (!initial) {
            RCTKRecordResult(run, [NSString stringWithFormat:@"toggles.%@", name], @"skip", @{ @"reason": @"state unreadable" }, -1);
            continue;
        }
        NSString *other = [initial isEqualToString:@"ON"] ? @"OFF" : @"ON";
        NSString *conditionOn = spec[@"conditionOn"] ?: @"ON", *conditionOff = spec[@"conditionOff"] ?: @"OFF";
        NSString *(^conditionFor)(NSString *) = ^NSString *(NSString *state) {
            return [state isEqualToString:@"ON"] ? conditionOn : conditionOff;
        };
        // Away from the starting state and back with on/off, then the same with toggle
        for (NSString *target in @[other, initial]) {
            NSString *command = [target isEqualToString:@"ON"] ? spec[@"on"] : spec[@"off"];
            RCTKToggleStep(run, [NSString stringWithFormat:@"toggles.%@.%@", name, target.lowercaseString], command, read, target,
                           spec[@"condition"], conditionFor(target));
        }
        if (spec[@"toggle"]) {
            RCTKToggleStep(run, [NSString stringWithFormat:@"toggles.%@.toggle", name], spec[@"toggle"], read, other, spec[@"condition"], conditionFor(other));
            RCTKToggleStep(run, [NSString stringWithFormat:@"toggles.%@.toggleBack", name], spec[@"toggle"], read, initial, spec[@"condition"], conditionFor(initial));
        }
    }

    // Auto-Lock: three values, read back in seconds
    id (^autoLock)(void) = ^id { return RCTKProbeLight()[@"autoLockSeconds"]; };
    RCTKToggleStep(run, @"toggles.autolock.2m", @"autolock 2m", autoLock, @120, @"autolock", @"2M");
    RCTKToggleStep(run, @"toggles.autolock.30s", @"autolock 30s", autoLock, @30, @"autolock", @"30S");
    RCTKToggleStep(run, @"toggles.autolock.never", @"autolock never", autoLock, @(INT_MAX), @"autolock", @"NEVER");

    // Volume: an absolute level, then one step up and back down (1/16 per step)
    id (^volume)(void) = ^id {
        id level = RCTKProbeLight()[@"volume"];
        return level ? @(round([level doubleValue] * 1000) / 1000) : nil;
    };
    RCTKToggleStep(run, @"toggles.volume.set", @"set-vol 25", volume, @0.25, @"volume", @"ABOVE 20");
    RCTKToggleStep(run, @"toggles.volume.up", @"volume up", volume, @0.313, @"volume", @"ABOVE 30");
    RCTKToggleStep(run, @"toggles.volume.down", @"volume down", volume, @0.25, @"volume", @"BELOW 30");
}


#pragma mark Guided suite

// The triggers only a person can do - status bar, screen edges, bottom bar, the ring/silent
// switch, shake, Touch ID, locking, the charger - asked for one at a time with a banner prompt
// (the app calls it Gestures & Sensors). Button presses are the replay suite's: it does them
// exactly, hands off. Every trigger in RCTKGuidedTriggerKeys is bound in a temporary config
// with capture on, so detection is tested without running anyone's actions. A step passes if
// exactly its expected triggers fired, once each, and no other button/gesture trigger did.

static NSArray<NSString *> *RCTKGuidedTriggerKeys(void) {
    return @[@"volume_up_hold", @"volume_down_hold", @"volume_both_press", @"volume_up_then_down", @"volume_down_then_up",
             @"power_double_tap", @"power_long_press", @"power_triple_click", @"power_quadruple_click",
             @"power_volume_up", @"power_volume_down",
             @"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold",
             @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right", @"trigger_statusbar_double_tap",
             @"trigger_home_double_click", @"trigger_home_triple_click", @"trigger_home_quadruple_click",
             @"trigger_ringer_mute", @"trigger_ringer_unmute", @"trigger_ringer_toggle",
             @"shake", @"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down",
             @"trigger_bottombar_swipe_left", @"trigger_bottombar_swipe_right",
             @"trigger_bottom_swipe_up_left", @"trigger_bottom_swipe_up_center", @"trigger_bottom_swipe_up_right",
             @"touchid_tap", @"touchid_hold",
             @"trigger_device_lock", @"trigger_device_unlock", @"trigger_power_connect", @"trigger_power_disconnect"];
}

// State-change triggers that other steps can set off along the way (a Power press that
// locks the phone): they count in their own steps, and are ignored in the rest
static NSSet<NSString *> *RCTKAmbientTriggerKeys(void) {
    return [NSSet setWithArray:@[@"trigger_device_lock", @"trigger_device_unlock", @"trigger_power_connect", @"trigger_power_disconnect"]];
}

static BOOL RCTKHasHomeButton(void) {
    __block long type = -1;
    void (^read)(void) = ^{
        id lockButton = RCTKSend([UIApplication sharedApplication], @"lockHardwareButton");
        NSNumber *value = RCTKSendLong(lockButton, @"homeButtonType");
        if (value) type = value.longValue;
    };
    if ([NSThread isMainThread]) read(); else dispatch_sync(dispatch_get_main_queue(), read);
    return type != 2; // 2: no Home button (Face ID); 1: solid-state Home button
}

// id, name (as lists show it), prompt (the banner's instruction), expected trigger keys, and optionally: oneOf (exactly one of these must fire too),
// home (YES: Home-button phones only, NO: phones without one), gesture (a scripted touch the
// test kit can do itself - see RCTKPerformGesture), auto (lock / unlock: it can do those too),
// homeBar (fails if iOS's home bar gesture took the swipe: a real finger is then cancelled for
// everything else, so the trigger can't fire - a scripted touch isn't, so this is what tells)
static NSArray<NSDictionary *> *RCTKGuidedSteps(BOOL hasHome) {
    NSMutableArray *steps = [NSMutableArray arrayWithArray:@[
        @{ @"id": @"ringer_flip", @"name": @"Ring/Silent Switch Flip", @"prompt": @"Flip the ring/silent switch", @"expect": @[@"trigger_ringer_toggle"], @"oneOf": @[@"trigger_ringer_mute", @"trigger_ringer_unmute"] },
        @{ @"id": @"ringer_flip_back", @"name": @"Ring/Silent Switch Flip Back", @"prompt": @"Flip the ring/silent switch back", @"expect": @[@"trigger_ringer_toggle"], @"oneOf": @[@"trigger_ringer_mute", @"trigger_ringer_unmute"] },
        @{ @"id": @"statusbar_left_hold", @"name": @"Status Bar Left Hold", @"gesture": @[@"hold", @0.15, @0.025, @600, @"system"], @"prompt": @"Touch and hold the top-left corner", @"expect": @[@"trigger_statusbar_left_hold"] },
        @{ @"id": @"statusbar_center_hold", @"name": @"Status Bar Center Hold", @"gesture": @[@"hold", @0.5, @0.025, @600, @"system"], @"prompt": @"Touch and hold the top-center", @"expect": @[@"trigger_statusbar_center_hold"] },
        @{ @"id": @"statusbar_right_hold", @"name": @"Status Bar Right Hold", @"gesture": @[@"hold", @0.85, @0.025, @600, @"system"], @"prompt": @"Touch and hold the top-right corner", @"expect": @[@"trigger_statusbar_right_hold"] },
        @{ @"id": @"statusbar_double_tap", @"name": @"Status Bar Double Tap", @"gesture": @[@"doubletap", @0.5, @0.025, @"system"], @"prompt": @"Double-tap the status bar", @"expect": @[@"trigger_statusbar_double_tap"] },
        @{ @"id": @"statusbar_swipe_left", @"name": @"Status Bar Swipe Left", @"gesture": @[@"swipe", @0.75, @0.025, @0.25, @0.025, @300, @"system"], @"prompt": @"Swipe left along the status bar", @"expect": @[@"trigger_statusbar_swipe_left"] },
        @{ @"id": @"statusbar_swipe_right", @"name": @"Status Bar Swipe Right", @"gesture": @[@"swipe", @0.25, @0.025, @0.75, @0.025, @300, @"system"], @"prompt": @"Swipe right along the status bar", @"expect": @[@"trigger_statusbar_swipe_right"] },
        @{ @"id": @"edge_left_swipe_up", @"name": @"Left Edge Swipe Up", @"gesture": @[@"swipe", @0.02, @0.6, @0.02, @0.4, @350, @"system"], @"prompt": @"Put a finger on the left edge of the screen and slide it up", @"expect": @[@"trigger_edge_left_swipe_up"] },
        @{ @"id": @"edge_left_swipe_down", @"name": @"Left Edge Swipe Down", @"gesture": @[@"swipe", @0.02, @0.4, @0.02, @0.6, @350, @"system"], @"prompt": @"Put a finger on the left edge of the screen and slide it down", @"expect": @[@"trigger_edge_left_swipe_down"] },
        @{ @"id": @"edge_right_swipe_up", @"name": @"Right Edge Swipe Up", @"gesture": @[@"swipe", @0.98, @0.6, @0.98, @0.4, @350, @"system"], @"prompt": @"Put a finger on the right edge of the screen and slide it up", @"expect": @[@"trigger_edge_right_swipe_up"] },
        @{ @"id": @"edge_right_swipe_down", @"name": @"Right Edge Swipe Down", @"gesture": @[@"swipe", @0.98, @0.4, @0.98, @0.6, @350, @"system"], @"prompt": @"Put a finger on the right edge of the screen and slide it down", @"expect": @[@"trigger_edge_right_swipe_down"] },
        @{ @"id": @"bottombar_swipe_left", @"name": @"Bottom Bar Swipe Left", @"homeBar": @YES, @"gesture": @[@"swipe", @0.75, @0.985, @0.25, @0.985, @300, @"bottomedge", @"system"], @"prompt": @"Swipe left along the very bottom of the screen", @"expect": @[@"trigger_bottombar_swipe_left"] },
        @{ @"id": @"bottombar_swipe_right", @"name": @"Bottom Bar Swipe Right", @"homeBar": @YES, @"gesture": @[@"swipe", @0.25, @0.985, @0.75, @0.985, @300, @"bottomedge", @"system"], @"prompt": @"Swipe right along the very bottom of the screen", @"expect": @[@"trigger_bottombar_swipe_right"] },
        @{ @"id": @"bottom_swipe_up_left", @"name": @"Bottom Swipe Up (Left)", @"gesture": @[@"swipe", @0.15, @0.985, @0.15, @0.8, @300, @"system"], @"prompt": @"Swipe up from the bottom-left corner", @"expect": @[@"trigger_bottom_swipe_up_left"], @"enable": @[@"trigger_bottom_swipe_up_left"] },
        @{ @"id": @"bottom_swipe_up_center", @"name": @"Bottom Swipe Up (Center)", @"gesture": @[@"swipe", @0.5, @0.985, @0.5, @0.8, @300, @"system"], @"prompt": @"Swipe up from the bottom-center", @"expect": @[@"trigger_bottom_swipe_up_center"], @"enable": @[@"trigger_bottom_swipe_up_center"] },
        @{ @"id": @"bottom_swipe_up_right", @"name": @"Bottom Swipe Up (Right)", @"gesture": @[@"swipe", @0.85, @0.985, @0.85, @0.8, @300, @"system"], @"prompt": @"Swipe up from the bottom-right corner", @"expect": @[@"trigger_bottom_swipe_up_right"], @"enable": @[@"trigger_bottom_swipe_up_right"] },
        @{ @"id": @"shake", @"name": @"Shake Device", @"prompt": @"Shake the phone", @"expect": @[@"shake"] },
        @{ @"id": @"touchid_tap", @"name": @"Touch ID Single Tap", @"prompt": @"Touch the Home button lightly, without pressing it", @"expect": @[@"touchid_tap"], @"home": @YES },
        @{ @"id": @"touchid_hold", @"name": @"Touch ID Hold", @"prompt": @"Rest a finger on the Home button for a second, without pressing it", @"expect": @[@"touchid_hold"], @"home": @YES },
        // Last: they leave the phone locked or need a cable
        @{ @"id": @"device_lock", @"name": @"Device Locked", @"auto": @"lock", @"prompt": @"Lock the phone with the Power button", @"expect": @[@"trigger_device_lock"] },
        @{ @"id": @"device_unlock", @"name": @"Device Unlocked", @"auto": @"unlock", @"prompt": @"Unlock the phone", @"expect": @[@"trigger_device_unlock"], @"keepScreen": @YES },
        @{ @"id": @"power_connect", @"name": @"Power Connected", @"prompt": @"Plug in a charger (or wait 15 s to skip)", @"expect": @[@"trigger_power_connect"], @"optional": @YES },
        @{ @"id": @"power_disconnect", @"name": @"Power Disconnected", @"prompt": @"Unplug the charger (or wait 15 s to skip)", @"expect": @[@"trigger_power_disconnect"], @"optional": @YES },
    ]];
    NSIndexSet *wrongDevice = [steps indexesOfObjectsPassingTest:^BOOL(NSDictionary *step, NSUInteger idx, BOOL *stop) {
        return step[@"home"] && [step[@"home"] boolValue] != hasHome;
    }];
    [steps removeObjectsAtIndexes:wrongDevice];
    return steps;
}

// Trigger keys captured (dry-run) after journal seq `since`
static NSArray<NSString *> *RCTKCapturedSince(unsigned long long since) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSDictionary *event in RCTKJournal(since, @"trigger.captured", 0)[@"events"]) {
        [keys addObject:event[@"key"] ?: @""];
    }
    return keys;
}

// The group a guided or stock-vs-tweak step is listed under (the app's step picker)
static NSString *RCTKStepGroup(NSString *stepId) {
    NSArray *groups = @[
        @[@"power_connect", @"Charger"], @[@"power_disconnect", @"Charger"], @[@"power_volume", @"Power"],
        @[@"home_power", @"Home Button"], @[@"volume", @"Volume"], @[@"power", @"Power"], @[@"ringer", @"Ring/Silent Switch"],
        @[@"statusbar", @"Status Bar"], @[@"home", @"Home Button"], @[@"edge", @"Screen Edges"], @[@"bottom", @"Bottom Edge"],
        @[@"touchid", @"Touch ID"], @[@"shake", @"Motion"], @[@"device_", @"Lock"],
    ];
    for (NSArray *group in groups) if ([stepId hasPrefix:group[0]]) return group[1];
    return @"Other";
}

// The steps a run does. steps=id,id:3,... keeps only those, each done the given number of
// times (1 if none is given; repeat=N sets the default). With `rounds` the list is gone
// through in rounds - round 2 has the steps chosen 2 or more times, and so on - which keeps
// steps that depend on each other (lock, then unlock) together; otherwise each step's
// repeats come in a row. Repeats get #2, #3... ids. Records a skip and returns nil if
// nothing is left.
static NSArray<NSDictionary *> *RCTKSelectSteps(NSArray<NSDictionary *> *all, NSMutableDictionary *run, BOOL rounds) {
    NSUInteger defaultCount = MIN(10, MAX(1, [run[@"repeat"] unsignedIntegerValue]));
    NSMutableDictionary<NSString *, NSNumber *> *counts = nil;
    if ([run[@"steps"] length]) {
        counts = [NSMutableDictionary dictionary];
        for (NSString *item in [run[@"steps"] componentsSeparatedByString:@","]) {
            NSArray *parts = [item componentsSeparatedByString:@":"];
            NSUInteger count = parts.count > 1 ? (NSUInteger)MAX(0, [parts[1] integerValue]) : defaultCount;
            counts[parts[0]] = @(MIN(10, count));
        }
    }
    NSMutableArray *chosen = [NSMutableArray array];
    NSMutableDictionary *names = [NSMutableDictionary dictionary], *notes = [NSMutableDictionary dictionary];
    NSUInteger most = 0;
    for (NSDictionary *step in all) {
        names[step[@"id"]] = step[@"name"] ?: step[@"prompt"];
        if ([step[@"note"] length]) notes[step[@"id"]] = step[@"note"];
        NSUInteger count = counts ? [counts[step[@"id"]] unsignedIntegerValue] : defaultCount;
        if (!count) continue;
        [chosen addObject:@[step, @(count)]];
        most = MAX(most, count);
    }
    @synchronized (run) { run[@"stepNames"] = names; run[@"stepNotes"] = notes; }
    NSMutableArray *steps = [NSMutableArray array];
    void (^add)(NSDictionary *, NSUInteger) = ^(NSDictionary *step, NSUInteger time) {
        NSMutableDictionary *copy = [step mutableCopy];
        if (time > 1) copy[@"id"] = [NSString stringWithFormat:@"%@#%lu", step[@"id"], (unsigned long)time];
        [steps addObject:copy];
    };
    if (rounds) {
        for (NSUInteger round = 1; round <= most; round++) {
            for (NSArray *entry in chosen) if ([entry[1] unsignedIntegerValue] >= round) add(entry[0], round);
        }
    } else {
        for (NSArray *entry in chosen) {
            for (NSUInteger time = 1; time <= [entry[1] unsignedIntegerValue]; time++) add(entry[0], time);
        }
    }
    if (!steps.count) {
        RCTKRecordResult(run, run[@"suite"], @"skip", @{ @"reason": [NSString stringWithFormat:@"no steps match '%@'", run[@"steps"]] }, -1);
        return nil;
    }
    return steps;
}

// What a run is doing now, for anyone following it (the app shows it): phase "ready"
// (waiting for the start press) or "step", and step x of y
static void RCTKSetProgress(NSMutableDictionary *run, NSString *phase, NSUInteger step, NSUInteger of, NSString *title) {
    @synchronized (run) {
        run[@"progress"] = @{ @"phase": phase, @"step": @(step), @"of": @(of), @"title": title ?: @"" };
    }
}

// What's covering the home screen right now (an app, the switcher, Control Center, Siri,
// Spotlight, the Today view or App Library),
// or nil if it's showing. Nothing is reported while the phone is locked.
static NSString *RCTKOffHomeScreen(NSDictionary *probe) {
    if ([probe[@"locked"] boolValue]) return nil;
    if ([probe[@"controlCenterVisible"] boolValue]) return @"controlCenter";
    if ([probe[@"switcherVisible"] boolValue]) return @"switcher";
    if ([probe[@"siriVisible"] boolValue]) return @"siri";
    if ([probe[@"spotlightVisible"] boolValue]) return @"spotlight";
    if ([probe[@"homeOverlayVisible"] boolValue]) return @"todayOrLibrary";
    NSString *front = probe[@"frontApp"];
    if (front.length && ![front isEqualToString:@"com.apple.springboard"]) return front;
    return nil;
}

// SpringBoard's own home action for an app or Siri in front - the handler a Home press
// reaches, so it's no Home button event the HID listener would count. Its name differs:
// iOS 15+ takes the window scene.
static void RCTKHomeAction(void) {
    id ui = RCTKShared(@"SBUIController", @"sharedInstance");
    SEL forScene = NSSelectorFromString(@"handleHomeButtonSinglePressUpForWindowScene:");
    if ([ui respondsToSelector:forScene]) {
        id manager = RCTKSend([UIApplication sharedApplication], @"windowSceneManager");
        id scene = RCTKSend(manager, @"embeddedDisplayWindowScene");
        ((BOOL (*)(id, SEL, id))objc_msgSend)(ui, forScene, scene);
        return;
    }
    for (NSString *name in @[@"handleHomeButtonSinglePressUp", @"handleHomeButtonTap", @"clickedMenuButton"]) {
        if (![ui respondsToSelector:NSSelectorFromString(name)]) continue;
        ((void (*)(id, SEL))objc_msgSend)(ui, NSSelectorFromString(name));
        return;
    }
}

// Puts the home screen back before a guided step, so whatever the last one opened (a
// swipe can bring up Spotlight, Control Center or another app; a Home double-click the
// switcher) doesn't get in the way. Closing one thing can reveal another (the switcher
// goes back to the app behind it), so it repeats a few times. Returns what it closed.
static NSString *RCTKReturnHome(void) {
    NSMutableArray *closed = [NSMutableArray array];
    for (int attempt = 0; attempt < 3; attempt++) {
        NSString *covering = RCTKOffHomeScreen(RCTKProbeLight());
        if (!covering) break;
        [closed addObject:covering];
        dispatch_sync(dispatch_get_main_queue(), ^{
            id icons = RCTKShared(@"SBIconController", @"sharedInstance");
            if ([covering isEqualToString:@"controlCenter"]) {
                id controlCenter = RCTKShared(@"SBControlCenterController", @"sharedInstanceIfExists");
                if ([controlCenter respondsToSelector:@selector(dismissAnimated:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(controlCenter, @selector(dismissAnimated:), YES);
            } else if ([covering isEqualToString:@"switcher"]) {
                // iOS 15+ / iOS 14
                id switcher = RCTKShared(@"SBMainSwitcherControllerCoordinator", @"sharedInstance") ?: RCTKShared(@"SBMainSwitcherViewController", @"sharedInstance");
                SEL dismiss = NSSelectorFromString(@"dismissMainSwitcherNoninteractivelyAnimated:");
                // Then the home action, which is what a Home press does in the switcher
                if (attempt == 0 && [switcher respondsToSelector:dismiss]) ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(switcher, dismiss, YES);
                else RCTKHomeAction();
            } else if ([covering isEqualToString:@"spotlight"] && [icons respondsToSelector:@selector(dismissSearchView)]) {
                ((void (*)(id, SEL))objc_msgSend)(icons, @selector(dismissSearchView));
            } else if ([covering isEqualToString:@"todayOrLibrary"]) {
                // iOS 15+ / iOS 14 names
                for (NSString *name in @[@"dismissHomeScreenOverlaysAnimated:", @"dismissHomeScreenOverlayAnimated:"]) {
                    if (![icons respondsToSelector:NSSelectorFromString(name)]) continue;
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(icons, NSSelectorFromString(name), YES);
                    break;
                }
            } else {
                RCTKHomeAction(); // an app, or Siri
            }
        });
        double start = RCTKNowMs();
        while ([covering isEqual:RCTKOffHomeScreen(RCTKProbeLight())] && RCTKNowMs() - start < 1500) RCTKSleep(0.1);
    }
    if (!closed.count) return nil;
    RCTKEvent(@"testkit.returnHome", @{ @"closed": closed, @"home": @(RCTKOffHomeScreen(RCTKProbeLight()) == nil) });
    RCTKSleep(0.5);
    return [closed componentsJoinedByString:@", "];
}

// Suites that need the user's hands start only once they're on the home screen and press
// Volume Up - a run started from the app or the API would otherwise begin before they're
// at the phone, and some triggers (the status bar's) only work on the home screen. Capture
// is on by then, so the press doesn't run any trigger. Returns NO if the run was stopped
// or nobody started it within two minutes.
static BOOL RCTKWaitForReady(NSMutableDictionary *run, NSString *title, NSUInteger steps) {
    RCTKSetProgress(run, @"ready", 0, steps, title);
    NSString *prompt = @"Go to the home screen, then press Volume Up to start";
    RCShowPrompt(title, prompt, @"play.circle", 120.0);
    unsigned long long since = RCTKRecord(@"mark", @{ @"label": @"ready?" });
    double start = RCTKNowMs();
    while (!g_tkStopRun && RCTKNowMs() - start < 120000) {
        NSArray *presses = RCTKJournal(since, @"hid.volume", 0)[@"events"];
        for (NSDictionary *event in presses) {
            since = [event[@"seq"] unsignedLongLongValue];
            if (![event[@"button"] isEqualToString:@"up"] || ![event[@"down"] boolValue]) continue;
            if ([RCTKProbeLight()[@"frontApp"] isEqualToString:@"com.apple.springboard"]) {
                RCShowPrompt(title, [NSString stringWithFormat:@"%lu steps - starting...", (unsigned long)steps], @"checklist", 2.5);
                RCTKSleep(3.0);
                return YES;
            }
            RCShowPrompt(title, @"Go to the home screen first, then press Volume Up", @"house", 120.0);
        }
        RCTKSleep(0.1);
    }
    RCHidePrompt();
    RCTKRecordResult(run, [run[@"suite"] stringByAppendingString:@".start"], @"skip",
                     @{ @"reason": g_tkStopRun ? @"run stopped" : @"not started - nobody pressed Volume Up on the home screen" }, -1);
    return NO;
}

static NSArray<NSDictionary *> *RCTKParseReplay(NSString *seq, NSString **error);
static NSString *RCTKReplaySend(NSArray<NSDictionary *> *events, double *startMs);
static NSString *RCTKCurrentPasscode(void);
static NSDictionary *RCTKUnlock(void);

// A scripted touch, through the tweak's own touch path (RCTouchEvent): @[kind, ...] with spots
// as fractions of the portrait screen - @[@"hold", x, y, ms], @[@"tap", x, y],
// @[@"doubletap", x, y], @[@"swipe", x1, y1, x2, y2, ms] (a move every ~16 ms); a last element
// @"system" also delivers each touch to SpringBoard's system gesture window, as iOS does for a
// real finger (RCTouchEventSystemGesture) - the screen-edge triggers listen there, and every
// scripted gesture sends it, to be as close to a real touch as it can. @"bottomedge" before it
// marks the touch as landing on the bottom edge, as a real one there is (RCTouchSetBottomEdge).
// Blocks until done.
static void RCTKPerformGesture(NSArray *gesture) {
    void (*touch)(double, double, BOOL) = [gesture.lastObject isEqual:@"system"] ? RCTouchEventSystemGesture : RCTouchEvent;
    BOOL bottomEdge = [gesture containsObject:@"bottomedge"];
    if (bottomEdge) RCTouchSetBottomEdge(YES);
    __block CGSize size = CGSizeZero;
    dispatch_sync(dispatch_get_main_queue(), ^{ size = [UIScreen mainScreen].bounds.size; });
    double w = MIN(size.width, size.height), h = MAX(size.width, size.height);
    NSString *kind = gesture.firstObject;
    double (^x)(NSUInteger) = ^double(NSUInteger i) { return [gesture[i] doubleValue] * w; };
    double (^y)(NSUInteger) = ^double(NSUInteger i) { return [gesture[i] doubleValue] * h; };
    if ([kind isEqualToString:@"hold"] || [kind isEqualToString:@"tap"]) {
        touch(x(1), y(2), YES);
        RCTKSleep(([kind isEqualToString:@"hold"] ? [gesture[3] doubleValue] : 60) / 1000.0);
        touch(x(1), y(2), NO);
    } else if ([kind isEqualToString:@"doubletap"]) {
        for (int i = 0; i < 2; i++) {
            touch(x(1), y(2), YES);
            RCTKSleep(0.06);
            touch(x(1), y(2), NO);
            if (i == 0) RCTKSleep(0.12);
        }
    } else if ([kind isEqualToString:@"swipe"]) {
        double ms = [gesture[5] doubleValue];
        int steps = MAX(4, (int)(ms / 16));
        touch(x(1), y(2), YES);
        double t = 0;
        for (int i = 1; i <= steps; i++) {
            if (!RCTKSleep(ms / steps / 1000.0)) break;
            t = (double)i / steps;
            touch(x(1) + (x(3) - x(1)) * t, y(2) + (y(4) - y(2)) * t, YES);
        }
        RCTKSleep(0.016);
        touch(x(1) + (x(3) - x(1)) * t, y(2) + (y(4) - y(2)) * t, NO);
    }
    if (bottomEdge) RCTouchSetBottomEdge(NO);
}

static NSString *const kRCTKHomeBarTook = @"iOS's home bar took the swipe, so a real finger's trigger wouldn't fire";

// Whether the tweak does this step itself in automatic mode
static BOOL RCTKGuidedStepScripted(NSDictionary *step) {
    return step[@"gesture"] || [step[@"auto"] isEqualToString:@"lock"] || ([step[@"auto"] isEqualToString:@"unlock"] && RCTKCurrentPasscode());
}

// Automatic: the steps only a person can do come first, so they can then leave the phone alone
// while the tweak does the rest; locking and unlocking stay last
static NSArray<NSDictionary *> *RCTKGuidedOrder(NSArray<NSDictionary *> *steps, BOOL autoMode) {
    if (!autoMode) return steps;
    NSMutableArray *byHand = [NSMutableArray array], *scripted = [NSMutableArray array], *last = [NSMutableArray array];
    for (NSDictionary *step in steps) {
        if (step[@"auto"]) [last addObject:step];
        else if (step[@"gesture"]) [scripted addObject:step];
        else [byHand addObject:step];
    }
    return [[byHand arrayByAddingObjectsFromArray:scripted] arrayByAddingObjectsFromArray:last];
}

static void RCTKSuiteGuided(NSMutableDictionary *run) {
    BOOL hasHome = RCTKHasHomeButton();
    NSArray *steps = RCTKSelectSteps(RCTKGuidedOrder(RCTKGuidedSteps(hasHome), [run[@"auto"] boolValue]), run, YES);
    if (!steps) return;
    NSSet *buttonKeys = [NSSet setWithArray:RCTKGuidedTriggerKeys()];
    @synchronized (run) { run[@"homeButton"] = @(hasHome); }

    // Bind every button/gesture trigger to a placeholder action, and record instead of running
    NSMutableDictionary *config = [RCCopyTriggerConfig() mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *triggers = [config[@"triggers"] mutableCopy] ?: [NSMutableDictionary dictionary];
    // Triggers a step lists under "enable" are on only during that step: the bottom swipe-up
    // zones take the bottom edge from iOS while on, which blocks swiping up to unlock or go home
    // (from every step, not just the chosen ones - a run without those steps keeps them off)
    NSMutableSet *stepOnly = [NSMutableSet set];
    for (NSDictionary *step in RCTKGuidedSteps(hasHome)) [stepOnly addObjectsFromArray:step[@"enable"] ?: @[]];
    for (NSString *key in RCTKGuidedTriggerKeys()) {
        NSMutableDictionary *trigger = [triggers[key] mutableCopy] ?: [NSMutableDictionary dictionary];
        trigger[@"enabled"] = @(![stepOnly containsObject:key]);
        trigger[@"actions"] = @[@"testkit noop"];
        triggers[key] = trigger;
    }
    config[@"triggers"] = triggers;
    config[@"masterEnabled"] = @YES;
    RCSetTriggerConfig(config);
    NSDictionary *(^configEnabling)(NSArray *) = ^NSDictionary *(NSArray *keys) {
        NSMutableDictionary *withKeys = [config mutableCopy];
        NSMutableDictionary *stepTriggers = [config[@"triggers"] mutableCopy];
        for (NSString *key in keys) {
            NSMutableDictionary *trigger = [stepTriggers[key] mutableCopy];
            trigger[@"enabled"] = @YES;
            stepTriggers[key] = trigger;
        }
        withKeys[@"triggers"] = stepTriggers;
        return withKeys;
    };
    g_tkCapture = YES;
    RCTKEvent(@"testkit.capture", @{ @"on": @YES });

    // auto=1: the test kit does the steps it can (screen gestures, lock, unlock with a test
    // passcode); the rest (ring/silent switch, shake, Touch ID, charger) are still asked for
    BOOL autoMode = [run[@"auto"] boolValue];
    if (autoMode) {
        RCShowPrompt(@"Gestures & Sensors", @"Doing the screen gestures - you'll be asked for the rest", @"hand.point.up.left", 3.0);
        RCTKSleep(2.0);
    }
    BOOL started = autoMode || RCTKWaitForReady(run, @"Gestures & Sensors", steps.count);

    NSUInteger index = 0, passed = 0;
    for (NSDictionary *step in started ? steps : @[]) {
        index++;
        if (g_tkStopRun) break;
        g_tkSkipStep = NO;
        NSString *testId = [@"guided." stringByAppendingString:step[@"id"]];
        NSString *title = [NSString stringWithFormat:@"Step %lu of %lu", (unsigned long)index, (unsigned long)steps.count];
        RCTKSetProgress(run, @"step", index, steps.count, step[@"prompt"]);
        if (![step[@"keepScreen"] boolValue]) RCTKReturnHome();
        if ([step[@"enable"] count]) RCSetTriggerConfig(configEnabling(step[@"enable"]));
        NSDictionary *before = [step[@"quiet"] boolValue] ? RCTKProbe() : nil; // for its latest photo
        unsigned long long since = RCTKRecord(@"mark", @{ @"label": testId });
        BOOL scripted = autoMode && RCTKGuidedStepScripted(step);
        // A scripted step's banner is gone before its touch: it sits where the status bar gestures go
        RCShowPrompt(title, scripted ? [@"Doing: " stringByAppendingString:step[@"prompt"]] : step[@"prompt"],
                     scripted ? @"play.circle" : @"hand.point.up.left", scripted ? 1.2 : 60.0);
        if (scripted) {
            RCTKSleep(1.6);
            if (step[@"gesture"]) RCTKPerformGesture(step[@"gesture"]);
            else if ([step[@"auto"] isEqualToString:@"lock"]) { NSString *e = nil; RCTKReplaySend(RCTKParseReplay(@"vP@0 ^P@90", &e), NULL); }
            else RCTKUnlock();
        }

        NSArray *expect = step[@"expect"];
        NSArray *oneOf = step[@"oneOf"];
        double start = RCTKNowMs(), firstAt = -1;
        BOOL timedOut = NO, homeBarTook = NO;
        while (YES) {
            NSArray *got = RCTKCapturedSince(since);
            BOOL allExpected = YES;
            for (NSString *key in expect) if (![got containsObject:key]) allExpected = NO;
            if (got.count && firstAt < 0) firstAt = RCTKNowMs();
            if (allExpected) break;
            // A real finger iOS's home bar took is cancelled: its trigger isn't coming
            if ([step[@"homeBar"] boolValue] && [RCTKJournal(since, @"ios.homeBarGesture", 1)[@"events"] count]) { homeBarTook = YES; break; }
            if (g_tkSkipStep || g_tkStopRun) break;
            if (RCTKNowMs() - start > ([step[@"optional"] boolValue] ? 15000 : 20000)) { timedOut = YES; break; }
            RCTKSleep(0.05);
        }
        if (homeBarTook) {
            RCTKRecordResult(run, testId, @"fail", @{ @"expected": expect, @"got": RCTKCapturedSince(since), @"problems": @[kRCTKHomeBarTook] }, RCTKNowMs() - start);
            if ([step[@"enable"] count]) RCSetTriggerConfig(config);
            RCShowPrompt(title, [@"Failed: " stringByAppendingString:kRCTKHomeBarTook], @"xmark.circle.fill", 1.5);
            RCTKSleep(2.0);
            continue;
        }
        if (g_tkSkipStep || g_tkStopRun || timedOut) {
            NSString *reason = timedOut ? @"timed out - no input detected" : (g_tkStopRun ? @"run stopped" : @"skipped");
            RCTKRecordResult(run, testId, @"skip", @{ @"reason": reason, @"got": RCTKCapturedSince(since) }, -1);
            if ([step[@"enable"] count]) RCSetTriggerConfig(config);
            RCShowPrompt(title, timedOut ? @"Skipped (timed out)" : @"Skipped", @"forward.fill", 1.5);
            RCTKSleep(2.0);
            continue;
        }
        double detected = RCTKNowMs() - start;
        RCTKSleep(1.2); // anything that fires a moment later counts too

        NSMutableArray *got = [NSMutableArray array];
        NSSet *ambient = RCTKAmbientTriggerKeys();
        for (NSString *key in RCTKCapturedSince(since)) {
            if (![buttonKeys containsObject:key]) continue;
            if ([ambient containsObject:key] && ![expect containsObject:key]) continue;
            [got addObject:key];
        }
        NSMutableArray *problems = [NSMutableArray array];
        NSCountedSet *counts = [[NSCountedSet alloc] initWithArray:got];
        for (NSString *key in expect) {
            if ([counts countForObject:key] != 1) [problems addObject:[NSString stringWithFormat:@"%@ fired %lu times", key, (unsigned long)[counts countForObject:key]]];
        }
        NSUInteger oneOfCount = 0;
        for (NSString *key in oneOf) oneOfCount += [counts countForObject:key];
        if (oneOf && oneOfCount != 1) [problems addObject:[NSString stringWithFormat:@"expected one of %@, got %lu", [oneOf componentsJoinedByString:@"/"], (unsigned long)oneOfCount]];
        for (NSString *key in counts) {
            if (![expect containsObject:key] && ![oneOf containsObject:key]) [problems addObject:[NSString stringWithFormat:@"unexpected %@", key]];
        }
        if ([step[@"homeBar"] boolValue] && [RCTKJournal(since, @"ios.homeBarGesture", 1)[@"events"] count]) [problems addObject:kRCTKHomeBarTook];
        if (before) {
            NSString *photoBefore = before[@"latestPhoto"][@"file"], *photoAfter = RCTKProbe()[@"latestPhoto"][@"file"];
            if (photoAfter.length && ![photoAfter isEqualToString:photoBefore ?: @""]) [problems addObject:@"iOS also took a screenshot"];
            for (NSDictionary *event in RCTKJournal(since, @"screen", 0)[@"events"]) {
                if (![event[@"on"] boolValue]) { [problems addObject:@"the phone also slept"]; break; }
            }
        }
        BOOL pass = problems.count == 0;
        if (pass) passed++;
        NSMutableDictionary *detail = [@{ @"expected": expect, @"got": got } mutableCopy];
        if (problems.count) detail[@"problems"] = problems;
        // iOS's own response to the same gesture, if it opened something (Control Center, an app)
        NSString *leftOpen = RCTKOffHomeScreen(RCTKProbeLight());
        if (leftOpen) detail[@"leftOpen"] = leftOpen;
        RCTKRecordResult(run, testId, pass ? @"pass" : @"fail", detail, detected);
        if ([step[@"enable"] count]) RCSetTriggerConfig(config);
        RCShowPrompt(title, pass ? @"Passed" : [@"Failed: " stringByAppendingString:problems.firstObject],
                     pass ? @"checkmark.circle.fill" : @"xmark.circle.fill", 1.5);
        RCTKSleep(2.0);
    }

    g_tkCapture = NO;
    RCTKEvent(@"testkit.capture", @{ @"on": @NO });
    if (started) RCShowPrompt(@"Gestures & Sensors", [NSString stringWithFormat:@"Done: %lu of %lu passed", (unsigned long)passed, (unsigned long)steps.count],
                 @"flag.checkered", 3.0);
}


#pragma mark Differential suite (stock vs tweak)

// Each physical input twice: once with RemoteCompanion's master switch off (stock iOS),
// once with the tweak armed but not claiming the input - every button trigger unbound except
// a placeholder quadruple-click, which arms the Power hold-back-and-replay machinery. The
// outcome (screen on/off sequence, screenshot saved, volume change, Siri, switcher, front
// app) must be the same. If the presses themselves differed between the passes, the step is
// inconclusive rather than failed.

// Never a step: Power + Volume held down - held long enough it starts Emergency SOS, which
// can call emergency services by itself.
static NSArray<NSDictionary *> *RCTKParseReplay(NSString *seq, NSString **error);

static NSArray<NSDictionary *> *RCTKDifferentialSteps(BOOL hasHome) {
    NSMutableArray *steps = [NSMutableArray arrayWithArray:@[
        @{ @"id": @"power_single", @"name": @"Power Single Press", @"buttons": @[@"power"], @"prompt": @"Press Power once", @"seq": @"vP@0 ^P@90" },
        @{ @"id": @"power_double", @"name": @"Power Double Press", @"buttons": @[@"power"], @"prompt": @"Double-press Power", @"seq": @"vP@0 ^P@80 vP@220 ^P@300" },
        @{ @"id": @"power_triple", @"name": @"Power Triple Press", @"buttons": @[@"power"], @"prompt": @"Triple-press Power", @"seq": @"vP@0 ^P@80 vP@220 ^P@300 vP@440 ^P@520" },
        @{ @"id": @"power_volume_up", @"name": @"Power + Volume Up", @"buttons": @[@"power", @"volumeUp"], @"prompt": @"Press Power + Volume Up together", @"seq": @"vP@0 vU@20 ^U@180 ^P@200" },
        // Stock iOS sleeps or not depending on which is released last. "ordered": a pass
        // counts only if the buttons went down in "order" and "releasedLast" was let go
        // clearly last (15 ms or more after the other) - what the prompt asks for.
        // With Volume Down still held when Power is released, stock iOS usually stays awake but
        // sometimes sleeps (in safe mode too), so the tweak defines it: never sleep. "defined":
        // the tweak pass must give these values whatever stock did (other values still have to
        // match, except the volume steps, which follow how long Volume Down was held). The
        // "plain" one arms no multi-click trigger, so the press isn't held back at all.
        @{ @"id": @"power_volume_down_hold", @"name": @"Volume Down + Power", @"buttons": @[@"power", @"volumeDown"], @"ordered": @YES,
           @"order": @[@"volumeDown", @"power"], @"releasedLast": @"volumeDown", @"defined": @{ @"screen": @"stayed on" },
           @"prompt": @"Volume Down, then Power; Power released first", @"replayOnly": @YES,
           @"note": @"Power released first, with a multi-click trigger set up",
           @"hint": @"Volume Down first, and let go of Power first", @"seq": @"vD@0 vP@60 ^P@200 ^D@320" },
        @{ @"id": @"power_volume_down_hold_plain", @"name": @"Volume Down + Power", @"buttons": @[@"power", @"volumeDown"], @"ordered": @YES, @"plain": @YES,
           @"order": @[@"volumeDown", @"power"], @"releasedLast": @"volumeDown", @"defined": @{ @"screen": @"stayed on" },
           @"prompt": @"Volume Down, then Power; Power released first", @"replayOnly": @YES,
           @"note": @"Power released first, with no trigger set up",
           @"hint": @"Volume Down first, and let go of Power first", @"seq": @"vD@0 vP@60 ^P@200 ^D@320" },
        @{ @"id": @"power_volume_down_inside", @"name": @"Power + Volume Down", @"note": @"Volume Down released first", @"buttons": @[@"power", @"volumeDown"], @"ordered": @YES,
           @"order": @[@"power", @"volumeDown"], @"releasedLast": @"power",
           @"prompt": @"Power, then Volume Down; Volume Down released first", @"replayOnly": @YES,
           @"hint": @"Power first, and let go of Volume Down first", @"seq": @"vP@0 vD@60 ^D@200 ^P@320" },
        @{ @"id": @"home_power", @"name": @"Home + Power", @"buttons": @[@"home", @"power"], @"prompt": @"Press Home + Power together", @"home": @YES, @"seq": @"vH@0 vP@20 ^P@180 ^H@200",
           @"defined": @{ @"screen": @"stayed on", @"screenshotSaved": @YES } },
        @{ @"id": @"volume_up", @"name": @"Volume Up Press", @"buttons": @[@"volumeUp"], @"prompt": @"Press Volume Up once", @"seq": @"vU@0 ^U@90" },
        @{ @"id": @"volume_both", @"name": @"Volume Up + Down", @"buttons": @[@"volumeUp", @"volumeDown"], @"prompt": @"Press Volume Up + Down together", @"seq": @"vU@0 vD@5 ^D@150 ^U@155" },
    ]];
    // Replay only: a sweep of timings and orders around the steps above, each judged against
    // stock - or against the defined behaviour where the tweak defines one (see below).
    NSArray *sweep = @[
        @[@"power_double_gap100", @"vP@0 ^P@60 vP@160 ^P@220", @"Power Double Press", @"100 ms gap"],
        @[@"power_double_gap180", @"vP@0 ^P@70 vP@250 ^P@320", @"Power Double Press", @"180 ms gap"],
        @[@"power_double_gap260", @"vP@0 ^P@70 vP@330 ^P@400", @"Power Double Press", @"260 ms gap"],
        @[@"power_double_gap350", @"vP@0 ^P@70 vP@420 ^P@490", @"Power Double Press", @"350 ms gap"],
        @[@"power_triple_gap150", @"vP@0 ^P@60 vP@210 ^P@270 vP@420 ^P@480", @"Power Triple Press", @"150 ms gaps"],
        @[@"power_triple_gap300", @"vP@0 ^P@70 vP@370 ^P@440 vP@740 ^P@810", @"Power Triple Press", @"300 ms gaps"],
        @[@"power_volume_up_vfirst", @"vU@0 vP@40 ^P@180 ^U@200", @"Volume Up + Power", @"Power released first"],
        @[@"power_volume_up_plast", @"vP@0 vU@40 ^U@160 ^P@200", @"Power + Volume Up", @"Power released last"],
        @[@"power_volume_down_short_dlast", @"vD@0 vP@30 ^P@120 ^D@160", @"Volume Down + Power", @"Short press, Volume Down released last"],
        @[@"power_volume_down_long_dlast", @"vD@0 vP@100 ^P@400 ^D@500", @"Volume Down + Power", @"Long press, Volume Down released last"],
        @[@"power_volume_down_short_plast", @"vD@0 vP@30 ^D@120 ^P@160", @"Volume Down + Power", @"Short press, Power released last"],
        @[@"power_volume_down_pfirst_dlast", @"vP@0 vD@30 ^P@150 ^D@200", @"Power + Volume Down", @"Volume Down released last"],
        @[@"power_volume_down_pfirst_long", @"vP@0 vD@100 ^D@400 ^P@500", @"Power + Volume Down", @"Long press, Power released last"],
    ];
    NSArray *homeSweep = @[
        @[@"home_power_pfirst", @"vP@0 vH@20 ^H@180 ^P@200", @"Power + Home", @"Power released last"],
        @[@"home_power_hlast", @"vH@0 vP@20 ^H@180 ^P@200", @"Home + Power", @"Power released last"],
        @[@"home_power_hold", @"vH@0 vP@40 ^P@400 ^H@450", @"Home + Power", @"Held longer"],
    ];
    NSDictionary *names = @{ @"U": @"volumeUp", @"D": @"volumeDown", @"H": @"home", @"P": @"power" };
    for (NSArray *entry in hasHome ? [sweep arrayByAddingObjectsFromArray:homeSweep] : sweep) {
        NSString *error = nil;
        NSArray *events = RCTKParseReplay(entry[1], &error);
        NSMutableArray *buttons = [NSMutableArray array];
        BOOL volumeHeld = NO, volumeHeldAtPowerUp = NO;
        NSMutableSet *held = [NSMutableSet set];
        for (NSDictionary *event in events) {
            NSString *button = names[event[@"button"]];
            if (![buttons containsObject:button]) [buttons addObject:button];
            if ([event[@"down"] boolValue]) [held addObject:event[@"button"]]; else [held removeObject:event[@"button"]];
            volumeHeld = [held containsObject:@"U"] || [held containsObject:@"D"];
            if ([event[@"button"] isEqualToString:@"P"] && ![event[@"down"] boolValue] && volumeHeld) volumeHeldAtPowerUp = YES;
        }
        NSMutableDictionary *step = [@{ @"id": entry[0], @"buttons": buttons, @"name": entry[2], @"note": entry[3],
                                        @"prompt": [NSString stringWithFormat:@"%@ - %@", entry[2], entry[3]], @"seq": entry[1], @"replayOnly": @YES } mutableCopy];
        // Defined behaviour: a Volume button held at Power's release doesn't sleep; Home + Power
        // takes a screenshot and stays on
        if (volumeHeldAtPowerUp) step[@"defined"] = @{ @"screen": @"stayed on" };
        if ([buttons containsObject:@"home"] && [buttons containsObject:@"power"]) step[@"defined"] = @{ @"screen": @"stayed on", @"screenshotSaved": @YES };
        [steps addObject:step];
    }

    NSIndexSet *wrongDevice = [steps indexesOfObjectsPassingTest:^BOOL(NSDictionary *step, NSUInteger idx, BOOL *stop) {
        return step[@"home"] && [step[@"home"] boolValue] != hasHome;
    }];
    [steps removeObjectsAtIndexes:wrongDevice];
    return steps;
}

static NSDictionary *RCTKConfigWith(NSDictionary *base, BOOL master, BOOL armed) {
    NSMutableDictionary *config = [base mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *triggers = [config[@"triggers"] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in RCTKGuidedTriggerKeys()) {
        NSMutableDictionary *trigger = [triggers[key] mutableCopy];
        if (!trigger) continue;
        trigger[@"enabled"] = @NO;
        triggers[key] = trigger;
    }
    if (armed) triggers[@"power_quadruple_click"] = @{ @"enabled": @YES, @"actions": @[@"testkit noop"], @"name": @"Test kit placeholder" };
    config[@"triggers"] = triggers;
    config[@"masterEnabled"] = @(master);
    return config;
}

// The real (not replayed) button presses after `since`: e.g. @{ @"power": @2, @"volumeUp": @1 }
// Real presses since `since`: a count per button, plus - when more than one button was
// used - the order they first went down and which was released last ("together" within
// 15 ms), which can change what iOS does with a chord. Only presses up to journal entry
// `until` (0: no limit) of the step's `buttons` count: after the first of them, a press of
// any other button (Home to wake an iPhone 8, say) ends the input, and its entry is
// returned in *foreignAt. A release only counts if it ends a press-down seen here: a
// replayed press's release is sometimes journaled without its replay mark (SpringBoard
// clears the flag on the main thread before the HID listener records the release), and it
// mustn't read as Power held for a long time, or change which button was released last.
static NSDictionary *RCTKInputsSince(unsigned long long since, unsigned long long until, NSArray *buttons,
                                     double *lastInputAt, unsigned long long *foreignAt) {
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSMutableArray *order = [NSMutableArray array];
    NSMutableSet *held = [NSMutableSet set]; // pressed here and not released yet
    NSString *lastUp = nil, *previousUp = nil;
    double lastUpAt = 0, previousUpAt = 0, powerDownAt = 0;
    for (NSDictionary *event in RCTKJournal(since, @"hid.", 0)[@"events"]) {
        if (until && [event[@"seq"] unsignedLongLongValue] > until) break;
        if ([event[@"replay"] boolValue]) continue;
        NSString *button = [event[@"type"] isEqualToString:@"hid.power"] ? @"power"
                         : [event[@"type"] isEqualToString:@"hid.home"] ? @"home"
                         : [event[@"button"] isEqualToString:@"up"] ? @"volumeUp" : @"volumeDown";
        if (![buttons containsObject:button]) {
            // Before the step's first press it's just getting ready (waking the phone)
            if (![event[@"down"] boolValue] || !order.count) continue;
            if (foreignAt) *foreignAt = [event[@"seq"] unsignedLongLongValue];
            break;
        }
        BOOL isDown = [event[@"down"] boolValue];
        if (!isDown && ![held containsObject:button]) continue; // no press-down of its own (see above)
        if (isDown) [held addObject:button]; else [held removeObject:button];
        if (lastInputAt) *lastInputAt = MAX(*lastInputAt, [event[@"t"] doubleValue]);
        if ([button isEqualToString:@"power"]) {
            // Held long enough for iOS's own long press (Siri, power-off): a different input
            if (isDown) powerDownAt = [event[@"t"] doubleValue];
            else if (powerDownAt && [event[@"t"] doubleValue] - powerDownAt > 500) counts[@"powerHeldLong"] = @YES;
        }
        if (!isDown) {
            if (![button isEqualToString:lastUp]) { previousUp = lastUp; previousUpAt = lastUpAt; }
            lastUp = button; lastUpAt = [event[@"t"] doubleValue];
            continue;
        }
        counts[button] = @([counts[button] integerValue] + 1);
        if (![order containsObject:button]) [order addObject:button];
    }
    if (order.count > 1) {
        counts[@"order"] = order;
        if (lastUp) counts[@"releasedLast"] = previousUp && lastUpAt - previousUpAt < 15 ? @"together" : lastUp;
    }
    return counts;
}

// Everything a pass changed between journal entries `since` and `until`, and the probes
// before and after. The screen is the list of its changes ("slept", "woke"). SpringBoard's
// notification is read after the fact - a quick off/on can arrive as two "on"s - so each
// one counts as a change from the state before. A wake more than 600 ms after the last
// Power / Home event (real or replayed) is the user waking the phone (a tap, raising it),
// and ends what the pass is judged on.
static NSDictionary *RCTKOutcome(unsigned long long since, unsigned long long until, NSDictionary *before, NSDictionary *after) {
    double lastButtonAt = 0;
    BOOL on = [before[@"screenOn"] boolValue];
    NSMutableArray *changes = [NSMutableArray array];
    for (NSDictionary *event in RCTKJournal(since, nil, 0)[@"events"]) {
        if ([event[@"seq"] unsignedLongLongValue] > until) break;
        NSString *type = event[@"type"];
        if ([type isEqualToString:@"hid.power"] || [type isEqualToString:@"hid.home"]) lastButtonAt = [event[@"t"] doubleValue];
        if (![type isEqualToString:@"screen"]) continue;
        if (!on && (!lastButtonAt || [event[@"t"] doubleValue] - lastButtonAt > 600)) break;
        on = !on;
        [changes addObject:on ? @"woke" : @"slept"];
    }
    NSString *screen = changes.count ? [changes componentsJoinedByString:@", then "]
                                     : ([before[@"screenOn"] boolValue] ? @"stayed on" : @"stayed off");
    NSString *photoBefore = before[@"latestPhoto"][@"file"], *photoAfter = after[@"latestPhoto"][@"file"];
    BOOL screenshot = photoAfter.length && ![photoAfter isEqualToString:photoBefore ?: @""];
    long volumeSteps = lround(([after[@"volume"] doubleValue] - [before[@"volume"] doubleValue]) * 16.0);
    NSMutableDictionary *outcome = [@{
        @"screen": screen,
        @"screenshotSaved": @(screenshot),
        @"volumeSteps": @(volumeSteps),
        @"siri": @([after[@"siriVisible"] boolValue]),
        @"switcher": @([after[@"switcherVisible"] boolValue]),
    } mutableCopy];
    if (![after[@"frontApp"] isEqual:before[@"frontApp"]]) outcome[@"frontApp"] = after[@"frontApp"] ?: @"";
    return outcome;
}

// One pass: prompt, wait for the input, let it settle, record the outcome. Returns nil if no
// input came (timeout, skip, stop).
static NSDictionary *RCTKDifferentialPass(NSString *title, NSString *prompt, NSArray *buttons) {
    NSDictionary *before = RCTKProbe();
    unsigned long long since = RCTKRecord(@"mark", @{ @"label": title });
    RCShowPrompt(title, prompt, @"hand.point.up.left", 60.0);

    // Wait for the first press, then until nothing has been pressed for 2.5 s - or another
    // button is pressed, which is the user waking the phone
    double start = RCTKNowMs(), lastInput = 0;
    unsigned long long foreign = 0;
    while (YES) {
        double last = 0;
        NSDictionary *inputs = RCTKInputsSince(since, 0, buttons, &last, &foreign);
        if (inputs.count) lastInput = last;
        if (lastInput > 0 && (foreign || RCTKNowMs() - lastInput > 2500)) break;
        if (g_tkSkipStep || g_tkStopRun || (lastInput == 0 && RCTKNowMs() - start > 45000)) return nil;
        RCTKSleep(0.05);
    }
    unsigned long long until = RCTKRecord(@"mark", @{ @"label": [title stringByAppendingString:@" (recorded)"] });
    if (foreign) until = foreign - 1;
    NSDictionary *after = RCTKProbe();
    NSDictionary *inputs = RCTKInputsSince(since, until, buttons, NULL, NULL);
    NSDictionary *outcome = RCTKOutcome(since, until, before, after);

    // Siri / switcher / an app left open would get in the way of the next pass
    if ([outcome[@"siri"] boolValue] || [outcome[@"switcher"] boolValue]) {
        RCShowPrompt(title, @"Close it and go back to the home screen", @"house", 4.0);
        RCTKSleep(4.0);
    }
    return @{ @"inputs": inputs, @"outcome": outcome };
}

static NSArray<NSDictionary *> *RCTKParseReplay(NSString *seq, NSString **error);
static NSString *RCTKReplaySend(NSArray<NSDictionary *> *events, double *startMs);
static void RCTKReplaySetConfig(NSDictionary *config);
static BOOL RCTKReplayWake(NSDictionary *unbound);
static NSString *RCTKCurrentPasscode(void);
static NSDictionary *RCTKUnlock(void);

// What a replayed timeline pressed, in RCTKInputsSince's terms (the journal can miss a
// press - with the master switch off the tweak doesn't record Power - but here we know)
static NSDictionary *RCTKInputsFromReplay(NSArray<NSDictionary *> *events) {
    NSDictionary *names = @{ @"U": @"volumeUp", @"D": @"volumeDown", @"H": @"home", @"P": @"power" };
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSMutableArray *order = [NSMutableArray array];
    NSString *lastUp = nil, *previousUp = nil;
    double lastUpAt = 0, previousUpAt = 0, powerDownAt = 0;
    for (NSDictionary *event in events) {
        NSString *button = names[event[@"button"]];
        double ms = [event[@"ms"] doubleValue];
        if ([event[@"down"] boolValue]) {
            counts[button] = @([counts[button] integerValue] + 1);
            if (![order containsObject:button]) [order addObject:button];
            if ([button isEqualToString:@"power"]) powerDownAt = ms;
        } else {
            if ([button isEqualToString:@"power"] && ms - powerDownAt > 500) counts[@"powerHeldLong"] = @YES;
            if (![button isEqualToString:lastUp]) { previousUp = lastUp; previousUpAt = lastUpAt; }
            lastUp = button; lastUpAt = ms;
        }
    }
    if (order.count > 1) {
        counts[@"order"] = order;
        if (lastUp) counts[@"releasedLast"] = previousUp && lastUpAt - previousUpAt < 15 ? @"together" : lastUp;
    }
    return counts;
}

// Every replayed pass of a step starts the same way, so stock and tweak passes are alike:
// locked with the screen on (here), or unlocked on the home screen (RCTKReplayUnlockedStart,
// with the Test Kit passcode). Locks and wakes with guarded Power presses under `unbound` (the
// stock config).
static BOOL RCTKReplayLockedStart(NSDictionary *unbound) {
    if (![RCTKProbe()[@"locked"] boolValue]) {
        if (![RCTKProbeLight()[@"screenOn"] boolValue] && !RCTKReplayWake(unbound)) return NO;
        RCTKReplaySetConfig(unbound);
        NSString *error = nil;
        RCTKReplaySend(RCTKParseReplay(@"vP@0 ^P@90", &error), NULL);
        double start = RCTKNowMs();
        while ([RCTKProbeLight()[@"screenOn"] boolValue] && RCTKNowMs() - start < 3000) RCTKSleep(0.1);
        RCTKSleep(0.5);
    }
    return RCTKReplayWake(unbound) && [RCTKProbe()[@"locked"] boolValue];
}

// "The user did something": restarts iOS's idle timer, so a lock screen woken a few seconds ago
// doesn't dim and sleep in the middle of a pass
static void RCTKResetIdleTimer(void) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        id app = [UIApplication sharedApplication];
        SEL reset = NSSelectorFromString(@"resetIdleTimerAndUndim");
        if ([app respondsToSelector:reset]) ((void (*)(id, SEL))objc_msgSend)(app, reset);
    });
}

// Or unlocked, on the home screen - with the Test Kit passcode (RCTKUnlock)
static BOOL RCTKReplayUnlockedStart(NSDictionary *unbound) {
    if (!RCTKCurrentPasscode()) return NO;
    RCTKReplaySetConfig(unbound);
    if (![RCTKProbeLight()[@"screenOn"] boolValue] && !RCTKReplayWake(unbound)) return NO;
    if ([RCTKProbe()[@"locked"] boolValue] && ![RCTKUnlock()[@"unlocked"] boolValue]) return NO;
    RCTKReturnHome();
    RCTKSleep(0.5);
    return ![RCTKProbe()[@"locked"] boolValue] && [RCTKProbeLight()[@"screenOn"] boolValue];
}

// A pass done by hand starts the same way every time too: unlocked, on the home screen. If the
// last press locked the phone, the tweak wakes it, then unlocks it with the Test Kit passcode
// or asks for it to be unlocked. NO if it stayed locked (or the run was stopped).
static BOOL RCTKManualStart(NSString *title, NSDictionary *unbound) {
    if (![RCTKProbeLight()[@"screenOn"] boolValue] && !RCTKReplayWake(unbound)) return NO;
    if ([RCTKProbe()[@"locked"] boolValue] && !(RCTKCurrentPasscode() && [RCTKUnlock()[@"unlocked"] boolValue])) {
        RCShowPrompt(title, @"Unlock the phone to continue", @"lock.open", 120.0);
        double start = RCTKNowMs();
        while ([RCTKProbe()[@"locked"] boolValue] && !g_tkStopRun && RCTKNowMs() - start < 120000) RCTKSleep(0.3);
        RCHidePrompt();
        if ([RCTKProbe()[@"locked"] boolValue]) return NO;
    }
    RCTKReturnHome();
    RCTKSleep(0.5);
    return YES;
}

// The same pass with the step's presses replayed (see RCTKReplay) instead of asked for: from
// the step's start state (step "state": locked, or unlocked on the home screen), the pass's
// config goes in, then the presses, then 2.5 s for what iOS does. The inputs are the timeline's.
static NSDictionary *RCTKDifferentialReplayPass(NSString *title, NSDictionary *step, NSDictionary *config, NSDictionary *unbound) {
    BOOL unlocked = [step[@"state"] isEqualToString:@"unlocked"];
    if (!(unlocked ? RCTKReplayUnlockedStart(unbound) : RCTKReplayLockedStart(unbound))) return nil;
    RCTKReplaySetConfig(config);
    // The screen has to be on - and stay on - when the presses start: right after a wake, the
    // lock screen can go dark again within ~0.1 s, and a pass started that way measures a
    // different input (its first press wakes instead of sleeping). Woken again (under
    // `unbound`) until it has stayed on for 0.8 s.
    BOOL steady = NO;
    for (int attempt = 0; attempt < 3 && !steady; attempt++) {
        if (![RCTKProbeLight()[@"screenOn"] boolValue]) {
            if (!RCTKReplayWake(unbound)) break;
            RCTKReplaySetConfig(config);
        }
        RCTKResetIdleTimer();
        steady = YES;
        double start = RCTKNowMs();
        while (RCTKNowMs() - start < 800) {
            if (![RCTKProbeLight()[@"screenOn"] boolValue]) { steady = NO; break; }
            RCTKSleep(0.05);
        }
    }
    if (!steady) return nil;
    RCTKResetIdleTimer(); // and the lock screen's dim timer starts over just before the presses
    NSString *error = nil;
    NSArray *events = RCTKParseReplay(step[@"seq"], &error);
    if (!events) return nil;
    NSDictionary *before = RCTKProbe();
    unsigned long long since = RCTKRecord(@"mark", @{ @"label": title });
    RCShowPrompt(title, step[@"prompt"], @"play.circle", 2.0);
    NSString *sent = RCTKReplaySend(events, NULL);
    if (!sent) return nil;
    // Saving a screenshot can take a few seconds (an iPhone 8 on the lock screen); both passes
    // of a step that's defined to take one wait the same, longer time
    RCTKSleep([step[@"defined"][@"screenshotSaved"] boolValue] ? 4.0 : 2.5);
    unsigned long long until = RCTKRecord(@"mark", @{ @"label": [title stringByAppendingString:@" (recorded)"] });
    NSDictionary *after = RCTKProbe();
    NSDictionary *outcome = RCTKOutcome(since, until, before, after);
    return @{ @"inputs": RCTKInputsFromReplay(events), @"outcome": outcome, @"sent": sent, @"startedLocked": @(!unlocked) };
}

static const NSUInteger kRCTKDifferentialAttempts = 3; // an inconclusive step is redone twice

static void RCTKSuiteDifferential(NSMutableDictionary *run) {
    BOOL hasHome = RCTKHasHomeButton();
    NSArray *steps = RCTKSelectSteps(RCTKDifferentialSteps(hasHome), run, NO);
    if (!steps) return;
    NSDictionary *base = RCCopyTriggerConfig();
    NSDictionary *stockConfig = RCTKConfigWith(base, NO, NO);
    NSDictionary *tweakConfig = RCTKConfigWith(base, YES, YES);
    NSDictionary *tweakPlainConfig = RCTKConfigWith(base, YES, NO); // for "plain" steps
    @synchronized (run) { run[@"homeButton"] = @(hasHome); }
    g_tkCapture = YES;
    RCTKEvent(@"testkit.capture", @{ @"on": @YES });

    // replay=1: the tweak replays each step's presses - nobody presses anything
    BOOL replay = [run[@"replay"] boolValue];
    if (replay) {
        RCShowPrompt(@"Stock vs Tweak", @"Replaying button presses - leave the phone alone", @"play.circle", 3.0);
        RCTKSleep(2.0);
    }
    if (replay) {
        // Each step from the lock screen, and - with a Test Kit passcode - unlocked too
        // (states=locked|unlocked|both; the default is both when there's a passcode)
        NSString *states = [run[@"states"] isKindOfClass:[NSString class]] ? run[@"states"] : (RCTKCurrentPasscode() ? @"both" : @"locked");
        NSMutableArray *expanded = [NSMutableArray array];
        for (NSDictionary *step in steps) {
            for (NSString *state in @[@"locked", @"unlocked"]) {
                if (![states isEqualToString:@"both"] && ![states isEqualToString:state]) continue;
                NSMutableDictionary *withState = [step mutableCopy];
                withState[@"state"] = state;
                withState[@"id"] = [NSString stringWithFormat:@"%@.%@", step[@"id"], state];
                [expanded addObject:withState];
            }
        }
        steps = expanded;
    } else {
        steps = [steps filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"replayOnly != YES"]];
    }
    BOOL started = replay || RCTKWaitForReady(run, @"Stock vs Tweak", steps.count);

    NSUInteger index = 0, same = 0;
    for (NSDictionary *step in started ? steps : @[]) {
        index++;
        if (g_tkStopRun) break;
        g_tkSkipStep = NO;
        RCTKSetProgress(run, @"step", index, steps.count, step[@"prompt"]);
        NSString *testId = [@"differential." stringByAppendingString:step[@"id"]];
        // An inconclusive attempt (the input wasn't the same both times, or wasn't the one
        // asked for) is redone, up to kRCTKDifferentialAttempts in all; earlier attempts
        // stay in the report.
        NSMutableArray *earlier = [NSMutableArray array];
        NSMutableDictionary *detail = nil;
        NSString *status = nil, *retryHint = nil;
        BOOL stepAbandoned = NO;
        for (NSUInteger attempt = 1; attempt <= kRCTKDifferentialAttempts; attempt++) {
            if (retryHint) {
                RCShowPrompt([NSString stringWithFormat:@"Step %lu of %lu - again", (unsigned long)index, (unsigned long)steps.count],
                             retryHint, @"arrow.counterclockwise", 3.0);
                RCTKSleep(3.5);
            }
            NSMutableDictionary *passes = [NSMutableDictionary dictionary];
            for (NSString *pass in @[@"stock", @"tweak"]) {
                NSDictionary *passConfig = [pass isEqualToString:@"stock"] ? stockConfig : [step[@"plain"] boolValue] ? tweakPlainConfig : tweakConfig;
                NSString *title = [NSString stringWithFormat:@"Step %lu of %lu - %@", (unsigned long)index, (unsigned long)steps.count,
                                   [pass isEqualToString:@"stock"] ? @"stock" : @"with tweak"];
                NSDictionary *result;
                if (replay) {
                    result = RCTKDifferentialReplayPass(title, step, passConfig, stockConfig);
                } else {
                    result = nil;
                    if (RCTKManualStart(title, stockConfig)) {
                        RCSetTriggerConfig(passConfig);
                        RCTKSleep(0.5);
                        result = RCTKDifferentialPass(title, step[@"prompt"], step[@"buttons"]);
                    }
                }
                if (!result) break;
                passes[pass] = result;
                if (!replay) {
                    RCShowPrompt(title, @"Recorded", @"checkmark", 1.0);
                    RCTKSleep(1.2);
                }
            }
            if (passes.count < 2) {
                RCTKRecordResult(run, testId, @"skip", @{ @"reason": g_tkStopRun ? @"run stopped" : replay ? @"couldn't replay the presses (or wake the screen)" : @"no input / skipped", @"passes": passes,
                                                          @"earlierAttempts": earlier }, -1);
                stepAbandoned = YES;
                break;
            }
            NSDictionary *stock = passes[@"stock"], *tweak = passes[@"tweak"];
            detail = [@{ @"stock": stock, @"tweak": tweak, @"attempt": @(attempt) } mutableCopy];
            if (replay) detail[@"seq"] = step[@"seq"];
            NSMutableDictionary *stockInputs = [stock[@"inputs"] mutableCopy], *tweakInputs = [tweak[@"inputs"] mutableCopy];
            if (![step[@"ordered"] boolValue]) {
                [stockInputs removeObjectsForKeys:@[@"order", @"releasedLast"]];
                [tweakInputs removeObjectsForKeys:@[@"order", @"releasedLast"]];
            }
            if (stockInputs[@"powerHeldLong"] || tweakInputs[@"powerHeldLong"]) {
                status = @"skip";
                detail[@"reason"] = @"not the requested input - Power was held long enough for iOS's long press (over 0.5 s)";
                retryHint = @"Power was down for over half a second - tap it quicker";
            } else if ([step[@"ordered"] boolValue] &&
                       (![stockInputs[@"order"] isEqual:step[@"order"]] || ![tweakInputs[@"order"] isEqual:step[@"order"]] ||
                        ![stockInputs[@"releasedLast"] isEqual:step[@"releasedLast"]] || ![tweakInputs[@"releasedLast"] isEqual:step[@"releasedLast"]])) {
                status = @"skip";
                detail[@"reason"] = [NSString stringWithFormat:@"not the requested input - wanted %@ down first and %@ released last",
                                     [step[@"order"] firstObject], step[@"releasedLast"]];
                retryHint = step[@"hint"];
            } else if (![stockInputs isEqual:tweakInputs]) {
                status = @"skip";
                detail[@"reason"] = @"inconclusive - the presses (or their order) differed between the two passes";
                retryHint = [step[@"ordered"] boolValue] ? @"The presses differed - same order both times, and release the last button clearly after"
                                                         : @"The presses differed - do exactly the same thing both times";
            } else if (step[@"defined"]) {
                NSDictionary *defined = step[@"defined"];
                NSMutableArray *differs = [NSMutableArray array], *stockDiffers = [NSMutableArray array];
                NSMutableSet *keys = [NSMutableSet setWithArray:[stock[@"outcome"] allKeys]];
                [keys addObjectsFromArray:[tweak[@"outcome"] allKeys]];
                for (NSString *key in keys) {
                    if ([key isEqualToString:@"volumeSteps"]) continue;
                    id want = defined[key] ?: stock[@"outcome"][key];
                    if (![want isEqual:tweak[@"outcome"][key]]) [differs addObject:key];
                    if (defined[key] && ![defined[key] isEqual:stock[@"outcome"][key]]) [stockDiffers addObject:key];
                }
                detail[@"defined"] = defined;
                if (stockDiffers.count) detail[@"stockDiffers"] = stockDiffers; // stock didn't do what's defined this time
                status = differs.count ? @"fail" : @"pass";
                if (differs.count) detail[@"differs"] = differs;
                break;
            } else if ([stock[@"outcome"] isEqual:tweak[@"outcome"]]) {
                status = @"pass";
                break;
            } else {
                status = @"fail";
                NSMutableArray *differs = [NSMutableArray array];
                NSMutableSet *keys = [NSMutableSet setWithArray:[stock[@"outcome"] allKeys]];
                [keys addObjectsFromArray:[tweak[@"outcome"] allKeys]];
                for (NSString *key in keys) if (![stock[@"outcome"][key] isEqual:tweak[@"outcome"][key]]) [differs addObject:key];
                detail[@"differs"] = differs;
                break;
            }
            if (attempt < kRCTKDifferentialAttempts && !g_tkStopRun) [earlier addObject:detail];
            else break;
        }
        if (stepAbandoned) continue;
        if (earlier.count) detail[@"earlierAttempts"] = earlier;
        if ([status isEqualToString:@"pass"]) same++;
        RCTKRecordResult(run, testId, status, detail, -1);
        NSString *verdict = [status isEqualToString:@"pass"] ? (detail[@"defined"] ? (detail[@"stockDiffers"] ? @"As defined (stock didn't do it this time)" : @"As defined, and same as stock") : @"Same as stock")
                          : [status isEqualToString:@"fail"] ? [(detail[@"defined"] ? @"Not as defined: " : @"Differs: ") stringByAppendingString:[detail[@"differs"] componentsJoinedByString:@", "]]
                          : @"Inconclusive - the input wasn't the same both times";
        RCShowPrompt([NSString stringWithFormat:@"Step %lu of %lu", (unsigned long)index, (unsigned long)steps.count], verdict,
                     [status isEqualToString:@"pass"] ? @"checkmark.circle.fill" : @"exclamationmark.circle.fill", 1.5);
        RCTKSleep(2.0);
    }

    if (replay) {
        RCTKReplayWake(stockConfig);
        if (RCTKCurrentPasscode()) RCTKUnlock(); // leave the phone unlocked, as it was
    }
    g_tkCapture = NO;
    RCTKEvent(@"testkit.capture", @{ @"on": @NO });
    // By hand, the last press may have put the phone to sleep: wake it for the result
    if (started && !replay && ![RCTKProbeLight()[@"screenOn"] boolValue]) RCTKReplayWake(stockConfig);
    if (started) RCShowPrompt(@"Stock vs Tweak", [NSString stringWithFormat:@"Done: %lu of %lu same as stock", (unsigned long)same, (unsigned long)steps.count],
                 @"flag.checkered", 3.0);
}

#pragma mark Running

static NSString *RCTKSuiteTitle(NSString *suite) {
    return @{ @"conditions": @"If Conditions", @"toggles": @"Toggle Actions", @"all": @"Conditions + Toggles",
              @"guided": @"Gestures & Sensors", @"replay": @"Button Triggers", @"differential": @"Stock vs Tweak" }[suite ?: @""];
}

static NSDictionary *RCTKSuites(void) {
    return @{ @"suites": @[
        @{ @"name": @"conditions", @"changesState": @NO, @"description": @"If Conditions: every condition has exactly one value TRUE, and it matches the phone's state" },
        @{ @"name": @"toggles", @"changesState": @YES, @"description": @"Toggle Actions: each one switches and reads back, and its condition follows; the phone's state is saved first and put back. disruptive=1 adds Wi-Fi, Bluetooth, Location, Cellular and Airplane Mode" },
        @{ @"name": @"all", @"changesState": @YES, @"description": @"conditions, then toggles" },
        @{ @"name": @"guided", @"changesState": @YES, @"description": @"Gestures & Sensors: each gesture and sensor trigger; a step passes when exactly its trigger fires. auto=1: the tweak does the steps it can (unlocking with a test passcode) and asks for the rest, first. Triggers are swapped for test ones (with capture on) and put back" },
        @{ @"name": @"replay", @"changesState": @YES, @"description": @"Button Triggers: each button trigger, with the presses sent by the tweak - exact, then with varied timing; hands off. Power presses are limited for safety. Triggers are swapped for test ones (with capture on) and put back" },
        @{ @"name": @"differential", @"changesState": @YES, @"description": @"Stock vs Tweak: each button press twice - master switch off, then with the tweak armed but not claiming it - and what iOS does must match, or match the tweak's defined behaviour. replay=1: the tweak does the presses and adds a timing sweep" },
    ] };
}

static NSDictionary *RCTKSummarize(NSMutableDictionary *run) {
    NSMutableDictionary *report;
    @synchronized (run) {
        report = [run mutableCopy];
        report[@"tests"] = [run[@"tests"] copy];
    }
    NSUInteger pass = 0, fail = 0, skip = 0;
    for (NSDictionary *test in report[@"tests"]) {
        NSString *status = test[@"status"];
        if ([status isEqualToString:@"pass"]) pass++; else if ([status isEqualToString:@"fail"]) fail++; else skip++;
    }
    report[@"summary"] = @{ @"pass": @(pass), @"fail": @(fail), @"skip": @(skip), @"total": @(pass + fail + skip) };
    return report;
}

static void RCTKSuiteReplay(NSMutableDictionary *run);

static NSDictionary *RCTKRunSuite(NSString *name, NSDictionary *params) {
    BOOL disruptive = [params[@"disruptive"] boolValue], wait = [params[@"wait"] boolValue];
    if (![@[@"conditions", @"toggles", @"all", @"guided", @"differential", @"replay"] containsObject:name ?: @""]) {
        return @{ @"error": [NSString stringWithFormat:@"unknown suite '%@'", name ?: @""], @"suites": RCTKSuites()[@"suites"] };
    }
    NSMutableDictionary *run;
    @synchronized (RCTKLock()) {
        if ([g_tkRun[@"status"] isEqualToString:@"running"]) return @{ @"error": @"a run is in progress", @"id": g_tkRun[@"id"] };
        NSDictionary *probe = RCTKProbe();
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"yyyyMMdd-HHmmss";
        run = [@{
            @"id": [NSString stringWithFormat:@"%@-%@", [formatter stringFromDate:[NSDate date]], name],
            @"suite": name, @"disruptive": @(disruptive), @"status": @"running",
            @"started": @(RCTKNowMs()), @"device": probe[@"device"], @"session": g_tkSession ?: @"",
            @"steps": params[@"steps"] ?: @"", @"repeat": @(MAX(1, [params[@"repeat"] integerValue])), @"replay": @([params[@"replay"] boolValue]), @"auto": @([params[@"auto"] boolValue]), @"states": params[@"states"] ?: [NSNull null],
            @"tests": [NSMutableArray array]
        } mutableCopy];
        g_tkRun = run;
        g_tkRunning = YES;
        g_tkStopRun = NO;
        g_tkSkipStep = NO;
    }
    RCTKEvent(@"suite.start", @{ @"id": run[@"id"], @"suite": name });

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL changesState = ![name isEqualToString:@"conditions"];
        if (changesState) RCTKTakeSnapshot();
        if ([name isEqualToString:@"conditions"] || [name isEqualToString:@"all"]) RCTKSuiteConditions(run);
        if ([name isEqualToString:@"toggles"] || [name isEqualToString:@"all"]) RCTKSuiteToggles(run, disruptive);
        if ([name isEqualToString:@"guided"]) RCTKSuiteGuided(run);
        if ([name isEqualToString:@"differential"]) RCTKSuiteDifferential(run);
        if ([name isEqualToString:@"replay"]) RCTKSuiteReplay(run);
        if (g_tkStopRun) {
            @synchronized (run) { run[@"stopped"] = @YES; }
            RCShowPrompt(RCTKSuiteTitle(name) ?: @"Test", @"Stopped", @"stop.circle", 2.0);
            g_tkStopRun = NO;
        }
        if (changesState) {
            NSDictionary *restored = RCTKRestore();
            @synchronized (run) { run[@"restored"] = restored[@"restored"] ?: @[]; }
        }
        @synchronized (run) {
            run[@"status"] = @"done";
            g_tkRunning = NO;
            [run removeObjectsForKeys:@[@"stepNames", @"stepNotes"]]; // each result has them by now
            run[@"finished"] = @(RCTKNowMs());
            run[@"durationMs"] = @(round([run[@"finished"] doubleValue] - [run[@"started"] doubleValue]));
        }
        NSDictionary *report = RCTKSummarize(run);
        [[NSFileManager defaultManager] createDirectoryAtPath:kRCTKReportsDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        [json writeToFile:[kRCTKReportsDir stringByAppendingPathComponent:[report[@"id"] stringByAppendingString:@".json"]] atomically:YES];
        RCTKEvent(@"suite.end", @{ @"id": report[@"id"], @"summary": report[@"summary"] });
        dispatch_semaphore_signal(done);
    });

    if (!wait) return @{ @"id": run[@"id"], @"status": @"running" };
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_SEC)));
    return RCTKSummarize(run);
}

static NSDictionary *RCTKReport(NSString *reportId) {
    NSMutableDictionary *run = g_tkRun;
    if (!reportId.length) return run ? RCTKSummarize(run) : @{ @"error": @"no runs yet" };
    // The run in progress isn't saved until it ends
    if (run && [run[@"id"] isEqual:reportId] && [run[@"status"] isEqual:@"running"]) return RCTKSummarize(run);
    NSData *data = [NSData dataWithContentsOfFile:[kRCTKReportsDir stringByAppendingPathComponent:[reportId stringByAppendingString:@".json"]]];
    id report = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return report ?: @{ @"error": [NSString stringWithFormat:@"no report '%@'", reportId] };
}

// Saved reports: their ids (oldest first), and newest first a summary of each for a list
static NSDictionary *RCTKReports(void) {
    NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:kRCTKReportsDir error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *ids = [NSMutableArray array], *items = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file hasSuffix:@".json"]) continue;
        NSString *reportId = [file stringByDeletingPathExtension];
        [ids addObject:reportId];
        NSData *data = [NSData dataWithContentsOfFile:[kRCTKReportsDir stringByAppendingPathComponent:file]];
        NSDictionary *report = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![report isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *item = [@{ @"id": reportId } mutableCopy];
        for (NSString *key in @[@"suite", @"summary", @"started", @"finished", @"status", @"device"]) {
            if (report[key]) item[key] = report[key];
        }
        [items insertObject:item atIndex:0];
    }
    return @{ @"reports": ids, @"items": items };
}

static NSDictionary *RCTKDeleteReport(NSString *reportId) {
    if (!reportId.length || [reportId containsString:@"/"] || [reportId hasPrefix:@"."]) return @{ @"error": @"missing or invalid id" };
    NSString *path = [kRCTKReportsDir stringByAppendingPathComponent:[reportId stringByAppendingString:@".json"]];
    NSError *error = nil;
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    return deleted ? @{ @"deleted": reportId } : @{ @"error": error.localizedDescription ?: @"not deleted" };
}

// Every saved report
static NSDictionary *RCTKClearReports(void) {
    NSFileManager *files = [NSFileManager defaultManager];
    NSUInteger deleted = 0;
    for (NSString *name in [files contentsOfDirectoryAtPath:kRCTKReportsDir error:nil]) {
        if (![name hasSuffix:@".json"]) continue;
        if ([files removeItemAtPath:[kRCTKReportsDir stringByAppendingPathComponent:name] error:nil]) deleted++;
    }
    return @{ @"deleted": @(deleted) };
}

// A copy of a report with personal values replaced, for sharing: Wi-Fi network names
// (the current one, and any a condition test used), Bluetooth / AirPlay device names, and
// third-party app bundle ids (which say what's installed). Apple apps and the test kit's
// own made-up names are kept.
static NSString *RCTKRedactString(NSString *string, NSArray<NSArray<NSString *> *> *names) {
    for (NSArray<NSString *> *name in names) {
        string = [string stringByReplacingOccurrencesOfString:name[0] withString:name[1] options:NSCaseInsensitiveSearch range:NSMakeRange(0, string.length)];
    }
    return string;
}

static BOOL RCTKIsPrivateAppId(id value) {
    return [value isKindOfClass:[NSString class]] && [value containsString:@"."] && ![value hasPrefix:@"com.apple."] && ![value hasPrefix:@"com.example.rctk."];
}

static id RCTKRedactObject(id object, NSArray *names) {
    if ([object isKindOfClass:[NSString class]]) return RCTKRedactString(object, names);
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *copy = [NSMutableArray array];
        for (id item in object) [copy addObject:RCTKRedactObject(item, names)];
        return copy;
    }
    if (![object isKindOfClass:[NSDictionary class]]) return object;
    NSMutableDictionary *copy = [NSMutableDictionary dictionary];
    BOOL appCondition = [object[@"condition"] isEqual:@"front_app"];
    [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        BOOL appId = [key isEqual:@"frontApp"] || (appCondition && [key isEqual:@"value"]);
        copy[key] = appId && RCTKIsPrivateAppId(value) ? @"<app>" : RCTKRedactObject(value, names);
    }];
    return copy;
}

static NSDictionary *RCTKRedact(NSDictionary *report) {
    if (report[@"error"]) return report;
    NSMutableArray *names = [NSMutableArray array];
    void (^add)(id, NSString *) = ^(id name, NSString *placeholder) {
        if ([name isKindOfClass:[NSString class]] && [name length] >= 2 && ![name hasPrefix:@"RCTK "]) [names addObject:@[name, placeholder]];
    };
    add(RCTKProbeLight()[@"wifiNetwork"], @"<Wi-Fi network>");
    NSDictionary *placeholders = @{ @"wifi_network": @"<Wi-Fi network>", @"bt_device": @"<Bluetooth device>", @"airplay": @"<AirPlay device>", @"focus": @"<Focus>" };
    for (NSDictionary *test in report[@"tests"]) {
        NSString *condition = test[@"detail"][@"condition"] ?: @"";
        id value = test[@"detail"][@"value"];
        // A Focus condition's Off and Any Focus values aren't names
        if ([condition isEqual:@"focus"] && ([value isEqual:@"OFF"] || [value isEqual:@"ON"])) continue;
        NSString *placeholder = placeholders[condition];
        if (placeholder) add(value, placeholder);
    }
    // Longest first, so a name containing another is replaced whole
    [names sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [@([b[0] length]) compare:@([a[0] length])]; }];
    // "redacted" only when something was replaced, so a report with nothing personal in it
    // can be shared without asking
    NSMutableDictionary *redacted = [RCTKRedactObject(report, names) mutableCopy];
    if (![redacted isEqual:report]) redacted[@"redacted"] = @YES;
    return redacted;
}

static NSDictionary *RCTKLua(NSString *code) {
    if (!code.length) return @{ @"error": @"missing code" };
    RCTKEvent(@"testkit.lua", nil);
    __block NSDictionary *result;
    void (^evaluate)(void) = ^{ result = RCEvaluateLuaCapturing(code); };
    if ([NSThread isMainThread]) evaluate(); else dispatch_sync(dispatch_get_main_queue(), evaluate);
    return result;
}

#pragma mark - Routing

#pragma mark - Replay (simulated button presses)

// A press is posted through IOHIDEventSystemClientDispatchEvent - the system-wide path the
// real buttons report through, which the tweak's HID listener taps and SpringBoard's button
// handling acts on - so the tweak sees it the way it sees a real press, and iOS acts on it.
//
// Power is guarded so a replay can't do anything a person would regret:
// - Emergency SOS by presses (5 quick ones; it can call by itself): at most
//   kRCTKMaxPowerPresses Power presses in any kRCTKPowerWindowMs, counted across replays -
//   a replay that would go over waits (RCTKReplaySend), one with more is refused.
// - Emergency SOS / power-off by holding (Power with a volume button, or Power alone, held):
//   Power held at most kRCTKMaxPowerHoldMs, and down together with another button at most
//   kRCTKMaxPowerOverlapMs (Power + Home held is also the iPhone 8's force restart).
static const NSUInteger kRCTKMaxPowerPresses = 4;
static const double kRCTKPowerWindowMs = 10000;
static const double kRCTKMaxPowerHoldMs = 1500;
static const double kRCTKMaxPowerOverlapMs = 800;

typedef struct __IOHIDEvent *RCTKHIDEventRef;
typedef struct __IOHIDEventSystemClient *RCTKHIDClientRef;

// Why these events break a Power guard (see above), or nil if they don't
static NSString *RCTKPowerGuardError(NSArray<NSDictionary *> *events) {
    NSUInteger powerPresses = 0;
    double powerDownAt = -1, overlapFrom = -1;
    NSMutableSet *down = [NSMutableSet set];
    for (NSDictionary *event in events) {
        NSString *button = event[@"button"];
        double ms = [event[@"ms"] doubleValue];
        if ([event[@"down"] boolValue]) [down addObject:button]; else [down removeObject:button];
        if ([button isEqualToString:@"P"]) {
            if ([event[@"down"] boolValue]) { powerPresses++; powerDownAt = ms; }
            else if (ms - powerDownAt > kRCTKMaxPowerHoldMs) {
                return [NSString stringWithFormat:@"Power held %.0f ms - at most %.0f (a longer hold opens Siri, the power-off screen or Emergency SOS)", ms - powerDownAt, kRCTKMaxPowerHoldMs];
            }
        }
        BOOL together = [down containsObject:@"P"] && down.count > 1;
        if (together && overlapFrom < 0) overlapFrom = ms;
        if (!together && overlapFrom >= 0) {
            if (ms - overlapFrom > kRCTKMaxPowerOverlapMs) {
                return [NSString stringWithFormat:@"Power held with another button for %.0f ms - at most %.0f (held together they start Emergency SOS or a restart)", ms - overlapFrom, kRCTKMaxPowerOverlapMs];
            }
            overlapFrom = -1;
        }
    }
    if (powerPresses > kRCTKMaxPowerPresses) {
        return [NSString stringWithFormat:@"%lu Power presses - at most %lu (5 start Emergency SOS)", (unsigned long)powerPresses, (unsigned long)kRCTKMaxPowerPresses];
    }
    return nil;
}

static NSArray<NSDictionary *> *RCTKParseReplay(NSString *seq, NSString **error) {
    NSDictionary *usages = @{ @"U": @0xE9, @"D": @0xEA, @"H": @0x40, @"P": @0x30 };
    NSMutableArray *events = [NSMutableArray array];
    NSMutableSet *held = [NSMutableSet set];
    double last = 0;
    for (NSString *token in [seq componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if (!token.length) continue;
        NSRange at = [token rangeOfString:@"@"];
        NSString *head = at.location == NSNotFound ? token : [token substringToIndex:at.location];
        NSString *button = head.length == 2 ? [head substringFromIndex:1] : nil;
        BOOL down = [head hasPrefix:@"v"];
        if (at.location == NSNotFound || !button || (!down && ![head hasPrefix:@"^"])) {
            *error = [NSString stringWithFormat:@"can't read '%@' - use e.g. vU@0 ^U@120", token];
            return nil;
        }
        if (!usages[button]) {
            *error = [NSString stringWithFormat:@"unknown button '%@' (U, D, H, P)", button];
            return nil;
        }
        double ms = [[token substringFromIndex:at.location + 1] doubleValue];
        if (ms < last || ms > 10000) {
            *error = [NSString stringWithFormat:@"'%@': times must go up, within 10 s", token];
            return nil;
        }
        if (down == [held containsObject:button]) {
            *error = [NSString stringWithFormat:@"'%@': %@", token, down ? @"already down" : @"not down"];
            return nil;
        }
        if (down) [held addObject:button]; else [held removeObject:button];
        last = ms;
        [events addObject:@{ @"button": button, @"down": @(down), @"ms": @(ms), @"usage": usages[button] }];
    }
    if (held.count) {
        *error = [NSString stringWithFormat:@"%@ never released", [held.allObjects componentsJoinedByString:@", "]];
        return nil;
    }
    NSString *guard = RCTKPowerGuardError(events);
    if (guard) {
        *error = guard;
        return nil;
    }
    if (!events.count) *error = @"no presses";
    return events.count ? events : nil;
}

// Posts the events at their times, from a thread of its own (on time to the millisecond);
// returns when the last one is sent, with when each went out ("vU@0 vD@7 ..."), and the
// wall-clock time of the start in *startMs
static NSString *RCTKReplaySend(NSArray<NSDictionary *> *events, double *startMs) {
    static RCTKHIDClientRef (*clientCreate)(CFAllocatorRef);
    static RCTKHIDEventRef (*keyboardEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, boolean_t, uint32_t);
    static void (*dispatchEvent)(RCTKHIDClientRef, RCTKHIDEventRef);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        clientCreate = dlsym(iokit, "IOHIDEventSystemClientCreate");
        keyboardEvent = dlsym(iokit, "IOHIDEventCreateKeyboardEvent");
        dispatchEvent = dlsym(iokit, "IOHIDEventSystemClientDispatchEvent");
    });
    if (!clientCreate || !keyboardEvent || !dispatchEvent) return nil;

    // At most kRCTKMaxPowerPresses Power presses in any kRCTKPowerWindowMs, across replays:
    // wait for older ones to drop out of the window first. One replay at a time.
    static NSMutableArray<NSNumber *> *powerPressTimes;
    static NSObject *sendLock;
    static dispatch_once_t lockOnce;
    dispatch_once(&lockOnce, ^{ powerPressTimes = [NSMutableArray array]; sendLock = [NSObject new]; });
    NSUInteger powerPresses = 0;
    for (NSDictionary *event in events) if ([event[@"button"] isEqualToString:@"P"] && [event[@"down"] boolValue]) powerPresses++;
    if (RCTKPowerGuardError(events)) return nil;
    @synchronized (sendLock) {
    while (powerPresses) {
        double now = RCTKNowMs();
        while (powerPressTimes.count && now - powerPressTimes.firstObject.doubleValue > kRCTKPowerWindowMs) [powerPressTimes removeObjectAtIndex:0];
        if (powerPressTimes.count + powerPresses <= kRCTKMaxPowerPresses) break;
        double wait = powerPressTimes.firstObject.doubleValue + kRCTKPowerWindowMs - now + 50;
        RCTKEvent(@"replay.wait", @{ @"ms": @(round(wait)), @"reason": @"Power press limit" });
        if (!RCTKSleep(wait / 1000.0)) return nil;
    }

    NSMutableArray *sent = [NSMutableArray array];
    __block double start = 0;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        RCTKHIDClientRef client = clientCreate(kCFAllocatorDefault);
        mach_timebase_info_data_t base;
        mach_timebase_info(&base);
        uint64_t t0 = mach_absolute_time();
        start = RCTKNowMs();
        NSMutableSet<NSNumber *> *held = [NSMutableSet set];
        uint64_t slice = (uint64_t)(20e6 * base.denom / base.numer);
        for (NSDictionary *event in events) {
            // Waits in slices so a stopped run doesn't wait out the timeline, then exactly
            uint64_t due = t0 + (uint64_t)([event[@"ms"] doubleValue] * 1e6 * base.denom / base.numer);
            while (!g_tkStopRun && mach_absolute_time() + slice < due) mach_wait_until(mach_absolute_time() + slice);
            if (g_tkStopRun) {
                for (NSNumber *usage in held) {
                    RCTKHIDEventRef up = keyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 0x0C, usage.unsignedIntValue, NO, 0);
                    if (up) { dispatchEvent(client, up); CFRelease(up); }
                }
                RCTKEvent(@"replay.stopped", @{ @"released": @(held.count) });
                break;
            }
            mach_wait_until(due);
            if ([event[@"down"] boolValue]) [held addObject:event[@"usage"]]; else [held removeObject:event[@"usage"]];
            uint64_t now = mach_absolute_time();
            RCTKHIDEventRef hid = keyboardEvent(kCFAllocatorDefault, now, 0x0C, [event[@"usage"] unsignedIntValue], [event[@"down"] boolValue], 0);
            if (hid) {
                dispatchEvent(client, hid);
                CFRelease(hid);
            }
            if ([event[@"button"] isEqualToString:@"P"] && [event[@"down"] boolValue]) {
                @synchronized (powerPressTimes) { [powerPressTimes addObject:@(RCTKNowMs())]; }
            }
            [sent addObject:[NSString stringWithFormat:@"%@%@@%.0f", [event[@"down"] boolValue] ? @"v" : @"^", event[@"button"],
                             (double)(now - t0) * base.numer / base.denom / 1e6]];
        }
        if (client) CFRelease(client);
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
    if (startMs) *startMs = start;
    return [sent componentsJoinedByString:@" "];
    }
}

// The presses the HID listener saw after journal entry `since`, relative to startMs
static NSString *RCTKReplaySeen(unsigned long long since, double startMs) {
    NSMutableArray *seen = [NSMutableArray array];
    for (NSDictionary *event in RCTKJournal(since, @"hid.", 0)[@"events"]) {
        NSString *type = event[@"type"];
        if (![@[@"hid.volume", @"hid.home", @"hid.power"] containsObject:type]) continue;
        NSString *button = [type isEqualToString:@"hid.home"] ? @"H" : [type isEqualToString:@"hid.power"] ? @"P"
                         : [event[@"button"] isEqualToString:@"up"] ? @"U" : @"D";
        // ↻: a press the tweak itself posted (its replay of a held-back Power press to iOS)
        [seen addObject:[NSString stringWithFormat:@"%@%@%@@%.0f", [event[@"replay"] boolValue] ? @"↻" : @"", [event[@"down"] boolValue] ? @"v" : @"^", button,
                         [event[@"t"] doubleValue] - startMs]];
    }
    return [seen componentsJoinedByString:@" "];
}

// The same presses with every gap moved by up to +/- jitter ms, keeping their order (so
// what overlaps still overlaps) - a sloppier or tidier version of the same input
static NSArray<NSDictionary *> *RCTKJitter(NSArray<NSDictionary *> *events, double jitter) {
    if (jitter <= 0) return events;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:events.count];
    double last = -1;
    for (NSDictionary *event in events) {
        double ms = [event[@"ms"] doubleValue] + (jitter > 0 ? ((double)arc4random_uniform(2001) / 1000.0 - 1.0) * jitter : 0);
        ms = MAX(ms, last + 1);
        if (!out.count) ms = 0;
        last = ms;
        NSMutableDictionary *moved = [event mutableCopy];
        moved[@"ms"] = @(round(ms));
        [out addObject:moved];
    }
    // Moved past a Power guard (a hold or overlap a little too long): the exact timeline
    return RCTKPowerGuardError(out) ? events : out;
}

static NSString *RCTKReplayString(NSArray<NSDictionary *> *events) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSDictionary *event in events) {
        [parts addObject:[NSString stringWithFormat:@"%@%@@%@", [event[@"down"] boolValue] ? @"v" : @"^", event[@"button"], event[@"ms"]]];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSDictionary *RCTKReplay(NSString *seq, NSDictionary *params) {
    NSString *error = nil;
    NSArray *events = RCTKParseReplay(seq ?: @"", &error);
    if (!events) return @{ @"error": error };
    if (params[@"jitter"]) events = RCTKJitter(events, [params[@"jitter"] doubleValue]);

    BOOL capture = !params[@"capture"] || [params[@"capture"] boolValue];
    double settle = params[@"settle"] ? [params[@"settle"] doubleValue] : 1500;
    BOOL wasCapturing = g_tkCapture;
    if (capture) g_tkCapture = YES;
    unsigned long long since = RCTKRecord(@"replay.start", @{ @"seq": RCTKReplayString(events), @"capture": @(capture) });
    double startMs = 0;
    NSString *sent = RCTKReplaySend(events, &startMs);
    if (!sent) {
        if (capture) g_tkCapture = wasCapturing;
        return @{ @"error": @"IOHID functions not found" };
    }
    RCTKSleep(settle / 1000.0);
    if (capture) g_tkCapture = wasCapturing;

    NSMutableArray *fired = [NSMutableArray array];
    for (NSDictionary *event in RCTKJournal(since, @"trigger", 0)[@"events"]) {
        if (![event[@"type"] isEqualToString:@"trigger"]) continue;
        [fired addObject:[NSString stringWithFormat:@"%@@%.0f", event[@"key"], [event[@"t"] doubleValue] - startMs]];
    }
    RCTKRecord(@"replay.end", @{ @"fired": fired });
    return @{ @"seq": RCTKReplayString(events), @"sent": sent, @"seen": RCTKReplaySeen(since, startMs), @"fired": fired, @"capture": @(capture) };
}

#pragma mark Replay suite

// Button triggers checked by replaying presses at exact times - no one presses anything.
// Each step is a timeline and the triggers it must fire (how many times each); any other
// button trigger firing fails it. The first time a step runs its timeline is exact; repeats
// move every gap by up to +/- 25 ms (keeping the order), so a run also tries sloppier and
// tidier versions of the same input. Power steps come last, as they can lock the phone; the
// screen is woken before each one (a Power press, within the Power guards above).
static NSArray<NSString *> *RCTKReplayTriggerKeys(BOOL hasHome) {
    NSArray *keys = @[@"volume_up_hold", @"volume_down_hold", @"volume_both_press", @"volume_up_then_down", @"volume_down_then_up",
                      @"power_double_tap", @"power_triple_click", @"power_quadruple_click", @"power_long_press",
                      @"power_volume_up", @"power_volume_down"];
    return hasHome ? [keys arrayByAddingObjectsFromArray:@[@"trigger_home_double_click", @"trigger_home_triple_click", @"trigger_home_quadruple_click"]] : keys;
}

// id, prompt (what it does), seq, expect {trigger: times}; optionally bind (only these
// triggers on), home (Home-button phones only)
static NSArray<NSDictionary *> *RCTKReplaySteps(BOOL hasHome) {
    NSArray *steps = @[
        @{ @"id": @"volume_up_tap", @"prompt": @"Volume Up Press", @"note": @"No trigger expected", @"seq": @"vU@0 ^U@90", @"expect": @{} },
        @{ @"id": @"volume_up_hold", @"prompt": @"Volume Up Hold", @"seq": @"vU@0 ^U@700", @"expect": @{ @"volume_up_hold": @1 } },
        @{ @"id": @"volume_down_hold", @"prompt": @"Volume Down Hold", @"seq": @"vD@0 ^D@700", @"expect": @{ @"volume_down_hold": @1 } },
        @{ @"id": @"volume_up_then_down", @"prompt": @"Volume Up then Down", @"seq": @"vU@0 ^U@90 vD@200 ^D@290", @"expect": @{ @"volume_up_then_down": @1 } },
        @{ @"id": @"volume_down_then_up", @"prompt": @"Volume Down then Up", @"seq": @"vD@0 ^D@90 vU@200 ^U@290", @"expect": @{ @"volume_down_then_up": @1 } },
        @{ @"id": @"volume_both", @"prompt": @"Volume Up + Down", @"seq": @"vU@0 vD@5 ^D@150 ^U@155", @"expect": @{ @"volume_both_press": @1 } },
        @{ @"id": @"volume_both_sloppy", @"prompt": @"Volume Up + Down", @"note": @"Barely overlapping", @"seq": @"vD@0 vU@76 ^D@123 ^U@182", @"expect": @{ @"volume_both_press": @1 } },
        @{ @"id": @"volume_both_held", @"prompt": @"Volume Up + Down", @"note": @"Held", @"seq": @"vU@0 vD@40 ^U@450 ^D@470", @"expect": @{ @"volume_both_press": @1 } },
        @{ @"id": @"volume_both_chain", @"prompt": @"Volume Up + Down", @"note": @"Up, Down, Up in a row: one press", @"seq": @"vU@0 vD@112 ^U@124 ^D@221 vU@236 ^U@337", @"expect": @{ @"volume_both_press": @1 } },
        @{ @"id": @"volume_both_twice", @"prompt": @"Volume Up + Down", @"note": @"Twice in a row", @"seq": @"vU@0 vD@5 ^D@120 ^U@125 vU@250 vD@255 ^D@370 ^U@375", @"expect": @{ @"volume_both_press": @2 } },
        @{ @"id": @"volume_both_tap_tap", @"prompt": @"Volume Up + Down", @"note": @"Up, then Down, with no sequence trigger set up",
           @"seq": @"vU@0 ^U@100 vD@150 ^D@250", @"expect": @{ @"volume_both_press": @1 }, @"bind": @[@"volume_both_press"] },
        @{ @"id": @"home_double_click", @"prompt": @"Home Double Click", @"seq": @"vH@0 ^H@80 vH@180 ^H@260", @"expect": @{ @"trigger_home_double_click": @1 }, @"home": @YES },
        @{ @"id": @"home_triple_click", @"prompt": @"Home Triple Click", @"seq": @"vH@0 ^H@80 vH@180 ^H@260 vH@360 ^H@440", @"expect": @{ @"trigger_home_triple_click": @1 }, @"home": @YES },
        @{ @"id": @"home_quadruple_click", @"prompt": @"Home Quadruple Click", @"seq": @"vH@0 ^H@80 vH@180 ^H@260 vH@360 ^H@440 vH@540 ^H@620", @"expect": @{ @"trigger_home_quadruple_click": @1 }, @"home": @YES },
        @{ @"id": @"power_double_tap", @"prompt": @"Power Double-Tap", @"seq": @"vP@0 ^P@80 vP@220 ^P@300", @"expect": @{ @"power_double_tap": @1 } },
        @{ @"id": @"power_triple_click", @"prompt": @"Power Triple Click", @"seq": @"vP@0 ^P@80 vP@220 ^P@300 vP@440 ^P@520", @"expect": @{ @"power_triple_click": @1 } },
        @{ @"id": @"power_quadruple_click", @"prompt": @"Power Quadruple Click", @"seq": @"vP@0 ^P@80 vP@220 ^P@300 vP@440 ^P@520 vP@660 ^P@740", @"expect": @{ @"power_quadruple_click": @1 } },
        @{ @"id": @"power_long_press", @"prompt": @"Power Long Press", @"seq": @"vP@0 ^P@900", @"expect": @{ @"power_long_press": @1 } },
        @{ @"id": @"power_volume_up", @"prompt": @"Power + Volume Up", @"seq": @"vP@0 vU@40 ^U@200 ^P@240", @"expect": @{ @"power_volume_up": @1 } },
        @{ @"id": @"power_volume_down", @"prompt": @"Power + Volume Down", @"seq": @"vP@0 vD@40 ^D@200 ^P@240", @"expect": @{ @"power_volume_down": @1 } },
        @{ @"id": @"power_single", @"prompt": @"Power Press", @"note": @"No trigger expected; locks the phone", @"seq": @"vP@0 ^P@90", @"expect": @{} },
    ];
    NSIndexSet *wrongDevice = [steps indexesOfObjectsPassingTest:^BOOL(NSDictionary *step, NSUInteger idx, BOOL *stop) {
        return step[@"home"] && [step[@"home"] boolValue] != hasHome;
    }];
    NSMutableArray *kept = [steps mutableCopy];
    [kept removeObjectsAtIndexes:wrongDevice];
    return kept;
}

// Wakes the screen with a Power press if it's off - with no test triggers bound, so the tweak
// hands it to iOS, and within the Power guards. YES if the screen is on.
// Applies a test config and waits until SpringBoard's main thread has taken it in: the tweak
// reloads the config there (gesture windows and all), which can take longer than a fixed wait,
// and a press arriving meanwhile is handled late - a held press then reads as a tap
static void RCTKReplaySetConfig(NSDictionary *config) {
    RCSetTriggerConfig(config);
    RCTKSleep(0.3); // the change notification reaches the tweak
    for (int i = 0; i < 2; i++) dispatch_sync(dispatch_get_main_queue(), ^{}); // and its reload has run
    RCTKSleep(0.2);
}

static BOOL RCTKReplayWake(NSDictionary *unbound) {
    if ([RCTKProbeLight()[@"screenOn"] boolValue]) return YES;
    RCTKReplaySetConfig(unbound);
    NSString *error = nil;
    RCTKReplaySend(RCTKParseReplay(@"vP@0 ^P@90", &error), NULL);
    double start = RCTKNowMs();
    while (RCTKNowMs() - start < 3000) {
        if ([RCTKProbeLight()[@"screenOn"] boolValue]) return YES;
        RCTKSleep(0.1);
    }
    return NO;
}

static void RCTKSuiteReplay(NSMutableDictionary *run) {
    BOOL hasHome = RCTKHasHomeButton();
    NSArray *steps = RCTKSelectSteps(RCTKReplaySteps(hasHome), run, NO);
    if (!steps) return;
    NSArray *keys = RCTKReplayTriggerKeys(hasHome);
    @synchronized (run) { run[@"homeButton"] = @(hasHome); }

    // A test config with the replayed triggers bound to a placeholder (or only a step's "bind"),
    // with capture on so nothing runs
    NSDictionary *saved = RCCopyTriggerConfig() ?: @{};
    NSDictionary *(^configBinding)(NSArray *) = ^NSDictionary *(NSArray *bound) {
        NSMutableDictionary *config = [saved mutableCopy];
        NSMutableDictionary *triggers = [config[@"triggers"] mutableCopy] ?: [NSMutableDictionary dictionary];
        for (NSString *key in keys) {
            NSMutableDictionary *trigger = [triggers[key] mutableCopy] ?: [NSMutableDictionary dictionary];
            trigger[@"enabled"] = @([bound containsObject:key]);
            trigger[@"actions"] = @[@"testkit noop"];
            triggers[key] = trigger;
        }
        config[@"triggers"] = triggers;
        config[@"masterEnabled"] = @YES;
        return config;
    };
    g_tkCapture = YES;
    RCTKEvent(@"testkit.capture", @{ @"on": @YES });
    RCShowPrompt(@"Button Triggers", @"Replaying button presses - leave the phone alone", @"play.circle", 3.0);
    RCTKSleep(2.0);

    NSUInteger index = 0, passed = 0;
    NSMutableDictionary *timesRun = [NSMutableDictionary dictionary];
    NSArray *boundNow = nil; // the bindings of the config in place; switched only when a step needs others
    for (NSDictionary *step in steps) {
        index++;
        if (g_tkStopRun) break;
        NSString *testId = [@"replay." stringByAppendingString:step[@"id"]];
        RCTKSetProgress(run, @"step", index, steps.count, step[@"prompt"]);
        BOOL power = [step[@"seq"] containsString:@"P@"];
        if (power) {
            // A previous Power step may have locked the phone: wake it (the lock screen is fine)
            if (![RCTKProbeLight()[@"screenOn"] boolValue]) boundNow = @[];
            if (!RCTKReplayWake(configBinding(@[]))) {
                RCTKRecordResult(run, testId, @"skip", @{ @"reason": @"the screen stayed off - couldn't wake it" }, -1);
                continue;
            }
        } else {
            RCTKReturnHome();
        }
        NSArray *bound = step[@"bind"] ?: keys;
        if (![bound isEqualToArray:boundNow ?: @[@""]]) {
            RCTKReplaySetConfig(configBinding(bound));
            boundNow = bound;
        } else {
            RCTKSleep(0.3);
        }

        // Repeats come as "id#2", "id#3" (RCTKSelectSteps)
        NSString *baseId = [step[@"id"] componentsSeparatedByString:@"#"].firstObject;
        NSUInteger attempt = [timesRun[baseId] unsignedIntegerValue] + 1;
        timesRun[baseId] = @(attempt);
        NSString *error = nil;
        NSArray *events = RCTKParseReplay(step[@"seq"], &error);
        if (attempt > 1) events = RCTKJitter(events, 25);
        unsigned long long since = RCTKRecord(@"mark", @{ @"label": testId });
        double startMs = 0;
        NSString *sent = RCTKReplaySend(events, &startMs);
        RCTKSleep(1.5); // anything that fires a moment later counts too

        NSCountedSet *got = [[NSCountedSet alloc] init];
        NSMutableArray *gotList = [NSMutableArray array];
        for (NSDictionary *event in RCTKJournal(since, @"trigger.captured", 0)[@"events"]) {
            if (![keys containsObject:event[@"key"]]) continue;
            [got addObject:event[@"key"]];
            [gotList addObject:[NSString stringWithFormat:@"%@@%.0f", event[@"key"], [event[@"t"] doubleValue] - startMs]];
        }
        NSDictionary *expect = step[@"expect"];
        NSMutableArray *problems = [NSMutableArray array];
        for (NSString *key in expect) {
            NSUInteger want = [expect[key] unsignedIntegerValue], have = [got countForObject:key];
            if (have != want) [problems addObject:[NSString stringWithFormat:@"%@ fired %lu times, expected %lu", key, (unsigned long)have, (unsigned long)want]];
        }
        for (NSString *key in got) if (!expect[key]) [problems addObject:[NSString stringWithFormat:@"unexpected %@", key]];
        if (!sent) [problems addObject:@"couldn't send the presses (IOHID functions not found)"];

        BOOL pass = problems.count == 0;
        if (pass) passed++;
        NSMutableDictionary *detail = [@{ @"seq": RCTKReplayString(events), @"sent": sent ?: @"", @"seen": RCTKReplaySeen(since, startMs),
                                          @"expected": expect, @"got": gotList, @"attempt": @(attempt) } mutableCopy];
        if (problems.count) detail[@"problems"] = problems;
        RCTKRecordResult(run, testId, pass ? @"pass" : @"fail", detail, -1);
    }

    RCTKReplayWake(configBinding(@[]));
    if (RCTKCurrentPasscode()) RCTKUnlock(); // the last Power step locks the phone
    RCSetTriggerConfig(saved);
    g_tkCapture = NO;
    RCTKEvent(@"testkit.capture", @{ @"on": @NO });
    RCTKReturnHome();
    RCShowPrompt(@"Button Triggers", [NSString stringWithFormat:@"Done: %lu of %lu passed", (unsigned long)passed, (unsigned long)index],
                 passed == index ? @"checkmark.circle.fill" : @"exclamationmark.circle.fill", 3.0);
}

#pragma mark - Unlocking for tests

// A passcode the user typed into the Test Kit screen, so runs (and whoever drives the test
// kit) can unlock the phone between steps. It's guarded like this:
// - Set only over the UNIX socket - from this phone - never over the network.
// - Kept only here, in SpringBoard's memory: never in the config, the log (handle_command
//   redacts the command), the journal or a report, and never returned by any endpoint. A
//   respring forgets it, and so does kRCTKPasscodeLifetimeMs passing.
// - Forgotten the moment an unlock with it doesn't work, so a wrong passcode is tried at
//   most once - iOS disables the phone (or erases it, if set to) after repeated wrong ones.
static const double kRCTKPasscodeLifetimeMs = 30 * 60 * 1000;
static NSString *g_tkPasscode;
static double g_tkPasscodeExpiresAt;
static __thread BOOL g_tkFromNetwork = NO;

static NSString *RCTKCurrentPasscode(void) {
    @synchronized (RCTKLock()) {
        if (g_tkPasscode && RCTKNowMs() > g_tkPasscodeExpiresAt) g_tkPasscode = nil;
        return g_tkPasscode;
    }
}

static void RCTKForgetPasscode(void) {
    @synchronized (RCTKLock()) { g_tkPasscode = nil; g_tkPasscodeExpiresAt = 0; }
}

static NSDictionary *RCTKPasscodeStatus(void) {
    NSString *passcode = RCTKCurrentPasscode();
    return @{ @"set": @(passcode != nil), @"expiresInSeconds": @(passcode ? round((g_tkPasscodeExpiresAt - RCTKNowMs()) / 1000) : 0),
              @"lifetimeSeconds": @(kRCTKPasscodeLifetimeMs / 1000) };
}

static NSDictionary *RCTKSetPasscode(NSString *passcode) {
    if (g_tkFromNetwork) return @{ @"error": @"the passcode can only be set on the phone (Test Kit screen), not over the network" };
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    if (passcode.length < 4 || passcode.length > 64 || [passcode rangeOfCharacterFromSet:space].location != NSNotFound) {
        return @{ @"error": @"not a passcode (4-64 characters, no spaces)" };
    }
    @synchronized (RCTKLock()) {
        g_tkPasscode = [passcode copy];
        g_tkPasscodeExpiresAt = RCTKNowMs() + kRCTKPasscodeLifetimeMs;
    }
    RCTKEvent(@"passcode", @{ @"set": @YES }); // that it was set - not what it is
    return RCTKPasscodeStatus();
}

// Unlocks with the passcode (waking the screen with a guarded Power press if it's off)
static NSDictionary *RCTKUnlock(void) {
    NSString *passcode = RCTKCurrentPasscode();
    if (!passcode) return @{ @"error": @"no passcode set - enter it in Test Kit on the phone", @"unlocked": @NO };
    if (![RCTKProbe()[@"locked"] boolValue]) return @{ @"unlocked": @YES, @"wasLocked": @NO };
    if (![RCTKProbeLight()[@"screenOn"] boolValue]) {
        NSString *error = nil;
        RCTKReplaySend(RCTKParseReplay(@"vP@0 ^P@90", &error), NULL);
        double start = RCTKNowMs();
        while (![RCTKProbeLight()[@"screenOn"] boolValue] && RCTKNowMs() - start < 3000) RCTKSleep(0.1);
        RCTKSleep(0.3);
    }
    __block BOOL accepted = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        id manager = RCTKShared(@"SBLockScreenManager", @"sharedInstance");
        SEL sel = NSSelectorFromString(@"_attemptUnlockWithPasscode:finishUIUnlock:");
        if ([manager respondsToSelector:sel]) accepted = ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(manager, sel, passcode, YES);
    });
    double start = RCTKNowMs();
    while ([RCTKProbe()[@"locked"] boolValue] && RCTKNowMs() - start < 3000) RCTKSleep(0.1);
    BOOL unlocked = ![RCTKProbe()[@"locked"] boolValue];
    if (!unlocked) {
        RCTKForgetPasscode();
        RCTKEvent(@"passcode", @{ @"forgotten": @YES, @"reason": @"unlock failed" });
        return @{ @"unlocked": @NO, @"accepted": @(accepted),
                  @"error": @"the passcode didn't unlock the phone, so it was forgotten (a wrong one is never tried twice) - enter it again in Test Kit" };
    }
    RCTKEvent(@"unlock", nil);
    return @{ @"unlocked": @YES, @"wasLocked": @YES };
}

static NSDictionary *RCTKInfo(void) {
    return @{
        @"testkit": @1,
        @"session": g_tkSession ?: @"",
        @"tweakVersion": RCTKPackageVersion(),
        @"endpoints": @[@"info", @"probe", @"journal", @"journal/clear", @"mark", @"run", @"lua", @"capture", @"snapshot", @"restore",
                        @"suites", @"suite/steps", @"suite/run", @"suite/skip", @"suite/stop", @"report", @"reports", @"report/delete", @"reports/clear",
                        @"replay", @"passcode", @"passcode/forget", @"unlock"]
    };
}

static NSDictionary *RCTKRun(NSString *command) {
    if (!command.length) return @{ @"error": @"missing command" };
    // It would land in the journal (readable over the network) - set it on the phone instead
    if ([[command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] hasPrefix:@"testkit passcode"]) {
        return @{ @"error": @"the passcode can only be set on the phone (Test Kit screen)" };
    }
    RCTKEvent(@"testkit.run", @{ @"command": command });
    double start = RCTKNowMs();
    NSString *output = RCHandleCommand(command) ?: @"";
    return @{ @"command": command, @"output": output, @"ms": @(RCTKNowMs() - start) };
}

// endpoint: the part after /api/testkit/; params: query items and/or body
static NSDictionary *RCTKDispatch(NSString *endpoint, NSDictionary<NSString *, NSString *> *params, NSString *body, int *status) {
    *status = 200;
    if ([endpoint isEqualToString:@"info"]) return RCTKInfo();
    if ([endpoint isEqualToString:@"probe"]) return RCTKProbe();
    if ([endpoint isEqualToString:@"journal"]) {
        NSUInteger limit = params[@"limit"] ? (NSUInteger)[params[@"limit"] integerValue] : 1000;
        return RCTKJournal(strtoull([params[@"since"] UTF8String] ?: "0", NULL, 10), params[@"type"], limit);
    }
    if ([endpoint isEqualToString:@"journal/clear"]) {
        NSUInteger cleared;
        @synchronized (RCTKLock()) {
            cleared = g_tkEvents.count;
            [g_tkEvents removeAllObjects];
        }
        return @{ @"cleared": @(cleared) };
    }
    if ([endpoint isEqualToString:@"mark"]) {
        NSString *label = params[@"label"] ?: body ?: @"";
        return @{ @"label": label, @"seq": @(RCTKRecord(@"mark", @{ @"label": label })) };
    }
    if ([endpoint isEqualToString:@"run"]) return RCTKRun(params[@"cmd"] ?: body);
    if ([endpoint isEqualToString:@"capture"]) {
        NSString *on = params[@"on"] ?: body;
        if (on.length) {
            g_tkCapture = [on boolValue] || [on isEqualToString:@"on"] || [on isEqualToString:@"true"];
            RCTKEvent(@"testkit.capture", @{ @"on": @(g_tkCapture) });
        }
        return @{ @"capture": @(g_tkCapture) };
    }
    if ([endpoint isEqualToString:@"snapshot"]) {
        NSMutableDictionary *snapshot = [RCTKTakeSnapshot() mutableCopy];
        [snapshot removeObjectForKey:@"config"]; // large; stored on the device
        snapshot[@"configSaved"] = @YES;
        return snapshot;
    }
    if ([endpoint isEqualToString:@"restore"]) return RCTKRestore();
    if ([endpoint isEqualToString:@"lua"]) return RCTKLua(params[@"code"] ?: body);
    if ([endpoint isEqualToString:@"replay"]) return RCTKReplay(params[@"seq"] ?: body, params);
    if ([endpoint isEqualToString:@"passcode"]) return RCTKPasscodeStatus();
    if ([endpoint isEqualToString:@"passcode/set"]) return RCTKSetPasscode(params[@"code"]);
    if ([endpoint isEqualToString:@"passcode/forget"]) { RCTKForgetPasscode(); return RCTKPasscodeStatus(); }
    if ([endpoint isEqualToString:@"unlock"]) return RCTKUnlock();
    if ([endpoint isEqualToString:@"suites"]) return RCTKSuites();
    if ([endpoint isEqualToString:@"suite/run"]) {
        NSString *name = params[@"name"] ?: body;
        return RCTKRunSuite(name, params);
    }
    if ([endpoint isEqualToString:@"suite/steps"]) {
        NSString *name = params[@"name"] ?: body;
        BOOL hasHome = RCTKHasHomeButton();
        BOOL guided = [name isEqualToString:@"guided"];
        NSArray *all = guided ? RCTKGuidedOrder(RCTKGuidedSteps(hasHome), [params[@"auto"] boolValue]) : [name isEqualToString:@"differential"] ? RCTKDifferentialSteps(hasHome)
                     : [name isEqualToString:@"replay"] ? RCTKReplaySteps(hasHome) : nil;
        if (!all) return @{ @"error": @"steps are listed for guided, differential and replay" };
        NSMutableArray *steps = [NSMutableArray array];
        for (NSDictionary *step in all) {
            [steps addObject:@{ @"id": step[@"id"], @"name": step[@"name"] ?: step[@"prompt"], @"prompt": step[@"prompt"], @"group": RCTKStepGroup(step[@"id"]), @"seq": step[@"seq"] ?: @"",
                                @"optional": @([step[@"optional"] boolValue]), @"note": step[@"note"] ?: @"",
                                @"replayOnly": @([step[@"replayOnly"] boolValue]), @"scripted": @(guided && RCTKGuidedStepScripted(step)) }];
        }
        return @{ @"suite": name, @"steps": steps };
    }
    if ([endpoint isEqualToString:@"suite/skip"]) { g_tkSkipStep = YES; return @{ @"skip": @YES }; }
    if ([endpoint isEqualToString:@"suite/stop"]) {
        BOOL running = [g_tkRun[@"status"] isEqualToString:@"running"];
        if (running) g_tkStopRun = YES; // otherwise it would stop the next run, or a replay, at once
        return @{ @"stop": @(running) };
    }
    if ([endpoint isEqualToString:@"report"]) {
        NSDictionary *report = RCTKReport(params[@"id"]);
        return [params[@"redact"] boolValue] ? RCTKRedact(report) : report;
    }
    if ([endpoint isEqualToString:@"reports"]) return RCTKReports();
    if ([endpoint isEqualToString:@"report/delete"]) return RCTKDeleteReport(params[@"id"] ?: body);
    if ([endpoint isEqualToString:@"reports/clear"]) return RCTKClearReports();
    *status = 404;
    return @{ @"error": [NSString stringWithFormat:@"unknown endpoint '%@'", endpoint], @"endpoints": RCTKInfo()[@"endpoints"] };
}

static NSString *RCTKJSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{\"error\":\"json\"}";
}

NSString *RCTKHandleHTTP(int fd, const char *buffer, long length, NSString *method, NSString *path, NSString *cors) {
    g_tkLastUse = CFAbsoluteTimeGetCurrent();
    NSURLComponents *components = [NSURLComponents componentsWithString:path];
    NSString *endpoint = [components.path substringFromIndex:MIN(components.path.length, (NSUInteger)13)]; // after "/api/testkit/"
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (item.value) params[item.name] = item.value;
    }

    // Body: whatever followed the headers in the first read, plus the rest per Content-Length
    NSString *body = nil;
    const char *headersEnd = strnstr(buffer, "\r\n\r\n", (size_t)length);
    if (headersEnd && [method isEqualToString:@"POST"]) {
        size_t offset = (size_t)(headersEnd - buffer) + 4;
        NSMutableData *data = [NSMutableData dataWithBytes:buffer + offset length:(size_t)length - offset];
        NSString *headers = [[NSString alloc] initWithBytes:buffer length:offset encoding:NSUTF8StringEncoding];
        NSRange cl = [headers rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
        NSUInteger contentLength = cl.location != NSNotFound ? (NSUInteger)[[headers substringFromIndex:NSMaxRange(cl)] integerValue] : data.length;
        while (data.length < contentLength) {
            char chunk[4096];
            ssize_t n = read(fd, chunk, sizeof(chunk));
            if (n <= 0) break;
            [data appendBytes:chunk length:(size_t)n];
        }
        body = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!body.length) body = nil;
    }

    int status = 200;
    g_tkFromNetwork = YES;
    NSDictionary *result = RCTKDispatch(endpoint, params, body, &status);
    g_tkFromNetwork = NO;
    NSString *json = RCTKJSON(result);
    return [NSString stringWithFormat:@"HTTP/1.1 %d %@\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@",
            status, status == 200 ? @"OK" : @"Not Found", cors, (unsigned long)[json lengthOfBytesUsingEncoding:NSUTF8StringEncoding], json];
}

NSString *RCTKHandleCommand(NSString *args) {
    g_tkLastUse = CFAbsoluteTimeGetCurrent();
    NSString *trimmed = [args stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange space = [trimmed rangeOfString:@" "];
    NSString *endpoint = space.location == NSNotFound ? trimmed : [trimmed substringToIndex:space.location];
    NSString *rest = space.location == NSNotFound ? nil : [trimmed substringFromIndex:space.location + 1];
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    // "testkit suite/run name=guided&steps=a,b" - options as a query string, like the HTTP API's
    if (rest && [rest rangeOfString:@"="].location != NSNotFound && [rest rangeOfString:@" "].location == NSNotFound) {
        NSURLComponents *components = [NSURLComponents new];
        components.percentEncodedQuery = rest;
        for (NSURLQueryItem *item in components.queryItems) {
            if (item.value) params[item.name] = item.value;
        }
        rest = nil;
    } else if ([endpoint isEqualToString:@"journal"] && rest) {
        params[@"since"] = rest;
    }
    int status = 200;
    // From the UNIX socket (this phone) or relayed from the network (the web server's /api/command)
    g_tkFromNetwork = !RCCommandFromLocalSocket();
    NSString *reply = [RCTKJSON(RCTKDispatch(endpoint.length ? endpoint : @"info", params, rest, &status)) stringByAppendingString:@"\n"];
    g_tkFromNetwork = NO;
    return reply;
}

#pragma mark - Events from iOS

// iOS recognizing its screenshot gesture (the chord differs by device)
%hook SBLockHardwareButton
- (void)screenshotRecognizerDidRecognize:(id)recognizer {
    RCTKEvent(@"ios.screenshotGesture", @{ @"source": @"lock" });
    %orig;
}
%end

%hook SBHomeHardwareButton
- (void)screenshotRecognizerDidRecognize:(id)recognizer {
    RCTKEvent(@"ios.screenshotGesture", @{ @"source": @"home" });
    %orig;
}
%end

%hook SBCombinationHardwareButton
- (void)screenshotGesture:(id)gesture {
    RCTKEvent(@"ios.screenshotGesture", @{ @"source": @"combination" });
    %orig;
}
%end

// iOS's home bar gesture taking a touch (phones without a Home button) - checked after the call,
// since the tweak can turn a start into a failure for a sideways swipe a trigger wants
%hook SBFluidSwitcherScreenEdgePanGestureRecognizer
- (void)setState:(UIGestureRecognizerState)state {
    UIGestureRecognizerState before = self.state;
    %orig;
    if (before != UIGestureRecognizerStateBegan && self.state == UIGestureRecognizerStateBegan) RCTKEvent(@"ios.homeBarGesture", @{});
}
%end

%ctor {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;
    %init;
    RCTKLock();
    g_tkSession = [[NSUUID UUID] UUIDString];

    // Screen on/off, as SpringBoard reports it
    int token;
    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t blanked = 0;
        notify_get_state(t, &blanked);
        RCTKEvent(@"screen", @{ @"on": @((BOOL)(blanked == 0)) });
    });
    RCTKEvent(@"testkit.loaded", @{ @"tweakVersion": RCTKPackageVersion() });

    // A run that SpringBoard restarted in the middle of still owes the user their settings
    // back (see RCTKTakeSnapshot): put them back once SpringBoard has settled
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:kRCTKSnapshotPath];
        if (![snapshot[@"restorePending"] boolValue]) return;
        NSDictionary *restored = RCTKRestore();
        SRLog(@"[TestKit] Restored the settings an interrupted run owed: %@", restored[@"restored"]);
        RCTKEvent(@"testkit.restoredAfterRestart", @{ @"restored": restored[@"restored"] ?: @[] });
    });
}
