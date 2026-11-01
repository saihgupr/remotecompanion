// Loaded into findmydeviced, which runs Find My's commands from iCloud: Play Sound from the Find My
// app on another device or from iCloud.com. Each Play Sound is passed to SpringBoard as the Find My
// Sound trigger, so a phone can be set off from anywhere. The sound plays as usual, unless the
// trigger has actions and its Keep Default Action is switched off: then the command's sound,
// vibration and flash are turned off before iOS runs it, and its alert isn't shown (Find My still
// gets its reply).
//
// Which method receives the command differs between iOS versions, so several are watched; the
// first to see a command posts it, and the others within a few seconds are taken as the same one.
// Every class and method is looked up at run time: a missing one is skipped.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <notify.h>
#import <os/log.h>
#import <stdatomic.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <dlfcn.h>

// The daemon's sandbox keeps it from posting RC's notifications, so it tells SpringBoard through a
// file, one line each time ("ready <count>" once loaded, "ping <method>" per Play Sound), and
// SpringBoard watches it. Which folder the sandbox lets it write differs: /var/mobile/tmp on iOS 17,
// /var/tmp on iOS 14. Each file is tried in these folders in order; SpringBoard uses both.
static const char *kRCFindMyFolders[] = { "/var/mobile/tmp", "/var/tmp", NULL };
#define kRCFindMySignal "rc_findmy_signal"
#define kRCFindMyLog    "rc_findmy.log"   // the daemon's own log, started afresh each launch
#define kRCFindMyQuiet  "rc_findmy_quiet" // "1" when a Play Sound should be silent (written by SpringBoard)

// Opens a file in the first folder that allows it
static int RCOpen(const char *name, int flags, mode_t mode) {
    for (int i = 0; kRCFindMyFolders[i]; i++) {
        char path[256];
        snprintf(path, sizeof(path), "%s/%s", kRCFindMyFolders[i], name);
        int fd = open(path, flags, mode);
        if (fd >= 0) return fd;
    }
    return -1;
}

static BOOL RCQuiet(void) {
    char c = 0;
    int fd = RCOpen(kRCFindMyQuiet, O_RDONLY, 0);
    if (fd < 0) return NO;
    ssize_t n = read(fd, &c, 1);
    close(fd);
    return n == 1 && c == '1';
}

// Methods that start a Play Sound on this phone, by name; each is watched on whichever class has
// it (not executePlaySound: that one plays a sound on AirPods)
static NSArray *RCFindMyMethods(void) {
    return @[@"_handleSoundIntent:serverContext:", @"playSoundWithMessage:completion:",
             @"playSoundWithOptions:completion:", @"handleCommand"];
}

static void RCSignal(NSString *line) {
    int fd = RCOpen(kRCFindMySignal, O_WRONLY | O_TRUNC | O_CREAT, 0666);
    if (fd < 0) return;
    // A time at the end tells one signal from the next: SpringBoard can hear one write twice (iOS 14)
    NSString *text = [NSString stringWithFormat:@"%@ @%.3f\n", line, [NSDate timeIntervalSinceReferenceDate]];
    write(fd, text.UTF8String, strlen(text.UTF8String));
    close(fd);
}

static _Atomic double g_lastPost;
// A silenced Play Sound's alert is skipped until this time (seconds since reference date)
static _Atomic double g_noAlertUntil;

static void RCLog(NSString *format, ...);

// The alert is a CFUserNotification the daemon asks SpringBoard for: while a silenced Play Sound's
// window is open, none is made (the daemon takes it as an alert that couldn't be shown)
typedef void *RCUserNotificationRef;
static RCUserNotificationRef (*g_origUserNotificationCreate)(CFAllocatorRef, CFTimeInterval, CFOptionFlags, SInt32 *, CFDictionaryRef);
static RCUserNotificationRef RCUserNotificationCreate(CFAllocatorRef allocator, CFTimeInterval timeout, CFOptionFlags flags, SInt32 *error, CFDictionaryRef dictionary) {
    if ([NSDate timeIntervalSinceReferenceDate] < atomic_load(&g_noAlertUntil)) {
        RCLog(@"Skipped the Play Sound alert");
        if (error) *error = -1;
        return NULL;
    }
    return g_origUserNotificationCreate(allocator, timeout, flags, error, dictionary);
}

// The hooking library's MSHookFunction, from whichever install this is (rootless or rootful)
static void RCHookUserNotifications(void) {
    void (*hook)(void *, void *, void **) = (void (*)(void *, void *, void **))dlsym(RTLD_DEFAULT, "MSHookFunction");
    const char *libraries[] = { "/var/jb/usr/lib/libsubstrate.dylib", "/usr/lib/libsubstrate.dylib",
                                "/var/jb/usr/lib/libellekit.dylib", "/usr/lib/libellekit.dylib", NULL };
    for (int i = 0; !hook && libraries[i]; i++) {
        void *handle = dlopen(libraries[i], RTLD_NOW);
        if (handle) hook = (void (*)(void *, void *, void **))dlsym(handle, "MSHookFunction");
    }
    void *create = dlsym(RTLD_DEFAULT, "CFUserNotificationCreate");
    if (!hook || !create) {
        RCLog(@"Can't hook CFUserNotificationCreate (hook %p, function %p)", hook, create);
        return;
    }
    hook(create, (void *)RCUserNotificationCreate, (void **)&g_origUserNotificationCreate);
    RCLog(@"Watching CFUserNotificationCreate");
}

static void RCLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log(OS_LOG_DEFAULT, "[RemoteCompanion] %{public}@", msg);

    NSString *logLine = [NSString stringWithFormat:@"%@ [FindMyDaemon] %@\n", [NSDate date], msg];
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
    int fd = RCOpen(kRCFindMyLog, O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (fd >= 0) {
        write(fd, logLine.UTF8String, strlen(logLine.UTF8String));
        close(fd);
    }
}

// One Play Sound, seen by one of the watched methods
static void RCSoundCommand(NSString *where) {
    double now = [NSDate timeIntervalSinceReferenceDate];
    double last = atomic_load(&g_lastPost);
    if (now - last < 5.0) {
        RCLog(@"Play Sound also seen by %@", where);
        return;
    }
    atomic_store(&g_lastPost, now);
    RCLog(@"Play Sound received (%@)", where);
    RCSignal([@"ping " stringByAppendingString:where]);
}

// Wraps a method that takes no arguments or one or two objects, and returns nothing
static BOOL RCWatch(Class cls, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count); // its own methods, not inherited ones
    Method method = NULL;
    for (unsigned int i = 0; i < count; i++) if (method_getName(methods[i]) == selector) { method = methods[i]; break; }
    free(methods);
    if (!method) return NO;

    NSString *where = [NSString stringWithFormat:@"-[%s %@]", class_getName(cls), name];
    const char *encoding = method_getTypeEncoding(method) ?: "";
    unsigned int args = method_getNumberOfArguments(method);
    char returnType[8] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != 'v') {
        RCLog(@"Skipped %@: returns %s (%s)", where, returnType, encoding);
        return NO;
    }
    for (unsigned int i = 2; i < args; i++) {
        char type[8] = {0};
        method_getArgumentType(method, i, type, sizeof(type));
        if (type[0] != '@') {
            RCLog(@"Skipped %@: argument %u is %s (%s)", where, i - 2, type, encoding);
            return NO;
        }
    }

    IMP previous = method_getImplementation(method);
    if (args == 2) {
        method_setImplementation(method, imp_implementationWithBlock(^(id receiver) {
            @try {
                if ([name isEqualToString:@"handleCommand"]) {
                    // The message handler runs every message command (a Lost Mode message too): it
                    // counts only when the command asks for a sound. Logs the command's field names,
                    // and the values of the ones about sound, never the message itself.
                    SEL paramsSel = NSSelectorFromString(@"commandParams");
                    NSDictionary *params = [receiver respondsToSelector:paramsSel] ? ((id (*)(id, SEL))objc_msgSend)(receiver, paramsSel) : nil;
                    BOOL sound = [params isKindOfClass:[NSDictionary class]] && [params[@"sound"] respondsToSelector:@selector(boolValue)] && [params[@"sound"] boolValue];
                    NSMutableArray *about = [NSMutableArray array];
                    if ([params isKindOfClass:[NSDictionary class]]) {
                        for (id key in params) {
                            NSString *k = [key description];
                            if ([k.lowercaseString containsString:@"sound"]) {
                                [about addObject:[NSString stringWithFormat:@"%@=%@", k, params[key]]];
                            }
                        }
                    }
                    RCLog(@"%@: fields %@; sound fields %@", where, [params isKindOfClass:[NSDictionary class]] ? [[params allKeys] componentsJoinedByString:@","] : @"(none)", about);
                    if (sound) {
                        RCSoundCommand(where);
                        SEL setSel = NSSelectorFromString(@"setCommandParams:");
                        if (RCQuiet() && [receiver respondsToSelector:setSel]) {
                            NSMutableDictionary *silent = [params mutableCopy];
                            for (NSString *key in @[@"sound", @"vibrate", @"strobe"]) {
                                if (silent[key]) silent[key] = @NO;
                            }
                            ((void (*)(id, SEL, id))objc_msgSend)(receiver, setSel, silent);
                            atomic_store(&g_noAlertUntil, [NSDate timeIntervalSinceReferenceDate] + 5.0);
                            RCLog(@"Keep Default Action is off: sound, vibration, flash and alert skipped");
                        }
                    }
                } else {
                    RCSoundCommand(where);
                }
            } @catch (NSException *e) {}
            ((void (*)(id, SEL))previous)(receiver, selector);
        }));
    } else if (args == 3) {
        method_setImplementation(method, imp_implementationWithBlock(^(id receiver, id a) {
            @try { RCSoundCommand(where); } @catch (NSException *e) {}
            ((void (*)(id, SEL, id))previous)(receiver, selector, a);
        }));
    } else if (args == 4) {
        method_setImplementation(method, imp_implementationWithBlock(^(id receiver, id a, id b) {
            @try { RCSoundCommand(where); } @catch (NSException *e) {}
            ((void (*)(id, SEL, id, id))previous)(receiver, selector, a, b);
        }));
    } else {
        return NO;
    }
    RCLog(@"Watching %@ (%s)", where, encoding);
    return YES;
}

__attribute__((constructor)) static void RCFindMyPingStart(void) {
    @autoreleasepool {
        for (int i = 0; kRCFindMyFolders[i]; i++) unlink([NSString stringWithFormat:@"%s/%s", kRCFindMyFolders[i], kRCFindMyLog].fileSystemRepresentation);
        RCHookUserNotifications();

        // The alert a silenced Play Sound would show
        Class alerts = objc_getClass("FMAlertManager");
        SEL activate = NSSelectorFromString(@"activateAlert:");
        Method activateMethod = alerts ? class_getInstanceMethod(alerts, activate) : NULL;
        if (activateMethod) {
            IMP previousActivate = method_getImplementation(activateMethod);
            method_setImplementation(activateMethod, imp_implementationWithBlock(^(id receiver, id alert) {
                if ([NSDate timeIntervalSinceReferenceDate] < atomic_load(&g_noAlertUntil)) {
                    RCLog(@"Skipped the Play Sound alert");
                    return;
                }
                ((void (*)(id, SEL, id))previousActivate)(receiver, activate, alert);
            }));
            RCLog(@"Watching -[FMAlertManager activateAlert:]");
        }

        NSArray *names = RCFindMyMethods();
        NSUInteger watched = 0;

        // The classes of findmydeviced itself and the Find My frameworks it runs on
        uint32_t images = _dyld_image_count();
        for (uint32_t i = 0; i < images; i++) {
            const char *path = _dyld_get_image_name(i);
            if (!path || !(strstr(path, "findmydeviced") || strstr(path, "FindMyDevice") || strstr(path, "FMIPCore"))) continue;
            unsigned int classCount = 0;
            const char **classNames = objc_copyClassNamesForImage(path, &classCount);
            for (unsigned int c = 0; c < classCount; c++) {
                Class cls = objc_getClass(classNames[c]);
                if (!cls) continue;
                for (NSString *name in names) {
                    // handleCommand runs every command: only the message handler's, which carries Play Sound
                    if ([name isEqualToString:@"handleCommand"] && strcmp(classNames[c], "FMDCommandHandlerMessage") != 0) continue;
                    if (RCWatch(cls, name)) watched++;
                }
            }
            free(classNames);
        }
        RCLog(@"findmydeviced: watching %lu methods for Play Sound", (unsigned long)watched);
        RCSignal([NSString stringWithFormat:@"ready %lu", (unsigned long)watched]);
    }
}
