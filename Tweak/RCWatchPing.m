// Loaded into companionfindlocallyd, which plays the sound when Ping iPhone is used on a paired Apple
// Watch. Each ping is passed to SpringBoard as the Watch Ping trigger (tap) or Watch Ping Hold trigger
// (press and hold, which also asks for the flash). When that trigger has actions, the phone skips the
// sound and flash for that ping; the Watch still gets its usual reply. Without actions, or with the
// trigger's keepDefault set, Ping iPhone works as on a stock iPhone.
//
// Compatible with iOS 14 through iOS 17+. Every class and method is looked up dynamically.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <os/log.h>
#import <stdatomic.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>

#define kRCWatchPingArmed "com.pizzaman.rc.watch_ping_armed" // state: 1 tap has actions, 2 hold has actions (set by SpringBoard)
#define kRCWatchPing      "com.pizzaman.rc.watch_ping"       // posted per ping: state 1 tap, 2 hold

// Sound and flash are skipped until this time (seconds since reference date)
static _Atomic double g_quietUntil;

static void RCLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log(OS_LOG_DEFAULT, "[RemoteCompanion] %{public}@", msg);

    NSString *logLine = [NSString stringWithFormat:@"%@ [WatchPingDaemon] %@\n", [NSDate date], msg];
    const char *paths[] = { "/var/jb/tmp/remotecommand.log", "/tmp/remotecommand.log", NULL };
    for (int i = 0; paths[i]; i++) {
        int fd = open(paths[i], O_WRONLY | O_APPEND | O_CREAT, 0666);
        if (fd >= 0) {
            fchmod(fd, 0666);
            write(fd, logLine.UTF8String, strlen(logLine.UTF8String));
            close(fd);
            break;
        }
    }
}

static uint64_t RCArmedState(void) {
    static int token = NOTIFY_TOKEN_INVALID;
    if (token == NOTIFY_TOKEN_INVALID && notify_register_check(kRCWatchPingArmed, &token) != NOTIFY_STATUS_OK) return 0;
    uint64_t state = 0;
    notify_get_state(token, &state);
    return state;
}

// The ping message: field 1 a timestamp (double), field 2 the flash flag (varint), as seen on iOS 17
static BOOL RCPingWantsFlash(NSData *data) {
    if (![data isKindOfClass:[NSData class]]) return NO;
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length, i = 0;
    while (i < length) {
        uint64_t key = 0;
        for (int shift = 0; i < length && shift < 64; shift += 7) {
            uint8_t b = bytes[i++];
            key |= (uint64_t)(b & 0x7f) << shift;
            if (!(b & 0x80)) break;
        }
        uint64_t field = key >> 3, wire = key & 7;
        if (wire == 0) {
            uint64_t value = 0;
            for (int shift = 0; i < length && shift < 64; shift += 7) {
                uint8_t b = bytes[i++];
                value |= (uint64_t)(b & 0x7f) << shift;
                if (!(b & 0x80)) break;
            }
            if (field == 2) return value != 0;
        } else if (wire == 1) {
            i += 8;
        } else if (wire == 5) {
            i += 4;
        } else if (wire == 2) {
            uint64_t size = 0;
            for (int shift = 0; i < length && shift < 64; shift += 7) {
                uint8_t b = bytes[i++];
                size |= (uint64_t)(b & 0x7f) << shift;
                if (!(b & 0x80)) break;
            }
            if (size > length - MIN(i, length)) return NO;
            i += size;
        } else {
            return NO;
        }
    }
    return NO;
}

static void RCHandlePingWithKind(uint64_t kind) {
    uint64_t armed = RCArmedState();
    RCLog(@"Ping received from Watch: kind=%llu (1=tap, 2=hold), armed=%llu", kind, armed);
    if (armed & kind) {
        atomic_store(&g_quietUntil, [NSDate timeIntervalSinceReferenceDate] + 3.0);
        RCLog(@"Trigger has actions: sound/flash quieted for 3.0s");
    }

    static int token = NOTIFY_TOKEN_INVALID;
    if (token == NOTIFY_TOKEN_INVALID) notify_register_check(kRCWatchPing, &token);
    notify_set_state(token, kind);
    notify_post(kRCWatchPing);
}

static void RCHandlePing(id protobuf) {
    NSData *data = [protobuf respondsToSelector:@selector(data)] ? ((id (*)(id, SEL))objc_msgSend)(protobuf, @selector(data)) : nil;
    uint64_t kind = ([data isKindOfClass:[NSData class]] && RCPingWantsFlash(data)) ? 2 : 1;
    RCHandlePingWithKind(kind);
}

static BOOL RCQuiet(void) {
    return [NSDate timeIntervalSinceReferenceDate] < atomic_load(&g_quietUntil);
}

// Replaces a method to suppress sound/flash while quiet
static void RCQuietWhenArmed(Class cls, NSString *name) {
    if (!cls) return;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    const char *encoding = method_getTypeEncoding(method) ?: "";
    if (strcmp(encoding, "B16@0:8") == 0) {
        IMP previous = method_getImplementation(method);
        method_setImplementation(method, imp_implementationWithBlock(^BOOL(id receiver) {
            if (RCQuiet()) {
                RCLog(@"Silenced sound method: %@", name);
                return YES;
            }
            return ((BOOL (*)(id, SEL))previous)(receiver, selector);
        }));
    } else if (strcmp(encoding, "v16@0:8") == 0) {
        IMP previous = method_getImplementation(method);
        method_setImplementation(method, imp_implementationWithBlock(^(id receiver) {
            if (RCQuiet()) {
                RCLog(@"Silenced flash method: %@", name);
                return;
            }
            ((void (*)(id, SEL))previous)(receiver, selector);
        }));
    }
}

__attribute__((constructor)) static void RCWatchPingStart(void) {
    @autoreleasepool {
        Class remote = objc_getClass("NFMRemoteFindLocally");
        if (!remote) {
            RCLog(@"companionfindlocallyd: NFMRemoteFindLocally not found on this iOS");
            return;
        }

        // On iOS 17, sound/flash player was moved to NFMPlayCommands. On iOS 14-15, it is on NFMRemoteFindLocally itself.
        Class player = objc_getClass("NFMPlayCommands") ?: remote;

        // Sound and flash methods (with/without leading underscore, BOOL or void)
        for (NSString *name in @[
            @"playFindLocallySound", @"_playFindLocallySound",
            @"playSoundAndFlash", @"_playSoundAndFlash",
            @"flashLEDIfAppropriate", @"flashLights", @"flashLED"
        ]) {
            RCQuietWhenArmed(player, name);
            if (player != remote) {
                RCQuietWhenArmed(remote, name);
            }
        }

        // Hook playSound: (tap on all iOS, and hold with protobuf flash flag on iOS 17)
        SEL ping = NSSelectorFromString(@"playSound:");
        Method pingMethod = class_getInstanceMethod(remote, ping);
        if (pingMethod) {
            IMP previous = method_getImplementation(pingMethod);
            method_setImplementation(pingMethod, imp_implementationWithBlock(^(id receiver, id protobuf) {
                @try { RCHandlePing(protobuf); } @catch (NSException *e) {}
                ((void (*)(id, SEL, id))previous)(receiver, ping, protobuf);
            }));
            RCLog(@"companionfindlocallyd: playSound: hooked");
        }

        // Hook playSoundAndFlash: (hold on iOS 14-15)
        SEL pingFlash = NSSelectorFromString(@"playSoundAndFlash:");
        Method pingFlashMethod = class_getInstanceMethod(remote, pingFlash);
        if (pingFlashMethod) {
            IMP previousFlash = method_getImplementation(pingFlashMethod);
            method_setImplementation(pingFlashMethod, imp_implementationWithBlock(^(id receiver, id protobuf) {
                @try { RCHandlePingWithKind(2); } @catch (NSException *e) {}
                ((void (*)(id, SEL, id))previousFlash)(receiver, pingFlash, protobuf);
            }));
            RCLog(@"companionfindlocallyd: playSoundAndFlash: hooked");
        }

        RCLog(@"companionfindlocallyd: Ping iPhone hooks installed successfully");
    }
}
