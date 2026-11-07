/*
 * rc-root - Setuid root helper for RemoteCommand
 * Executes shell commands as root when called by SpringBoard (RemoteCommand), and IOHID touch injection
 *
 * Must be installed with: chown root:wheel rc-root && chmod 4755 rc-root
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/wait.h>
#include <signal.h>
#include <CoreFoundation/CoreFoundation.h>

#include <dlfcn.h>
#include <mach/mach_time.h>

extern char **environ;

// proc_pidpath lives in libSystem but is not exposed in the iOS SDK headers
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

// rc-root is setuid root, so it must not run arbitrary shell commands for whichever process
// happens to call it. Shell commands are only honoured when the direct parent is SpringBoard,
// which is where RemoteCommand's tweak spawns this helper. The kernel sets the parent PID, so
// another app cannot fake it.
static int rc_parent_is_springboard(void) {
    pid_t ppid = getppid();
    if (ppid <= 1) return 0;
    char path[4096];
    if (proc_pidpath(ppid, path, sizeof(path)) <= 0) return 0;
    return strcmp(path, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 0;
}

// RemoteCommand's config, written by the app: Settings > Advanced Settings > Security
#define RC_CONFIG_PATH "/var/mobile/Documents/rc_triggers.plist"

// "Allow Direct Root Helper Calls", off unless the user turns it on. Reading this file is safe:
// a bad value just means the check below stays in force.
static int rc_direct_calls_allowed(void) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8 *)RC_CONFIG_PATH, strlen(RC_CONFIG_PATH), false);
    if (!url) return 0;
    CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
    CFRelease(url);
    if (!stream) return 0;
    int allowed = 0;
    if (CFReadStreamOpen(stream)) {
        CFPropertyListRef plist = CFPropertyListCreateWithStream(kCFAllocatorDefault, stream, 0, kCFPropertyListImmutable, NULL, NULL);
        if (plist) {
            if (CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
                CFTypeRef value = CFDictionaryGetValue((CFDictionaryRef)plist, CFSTR("allowDirectRootHelper"));
                if (value && CFGetTypeID(value) == CFBooleanGetTypeID()) {
                    allowed = CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
                }
            }
            CFRelease(plist);
        }
        CFReadStreamClose(stream);
    }
    CFRelease(stream);
    return allowed;
}

// IOHIDEvent types and private function pointers
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef uint32_t IOHIDEventOptionBits;

static IOHIDEventRef (*_IOHIDEventCreateDigitizerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits);
static IOHIDEventRef (*_IOHIDEventCreateDigitizerFingerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits);
static void (*_IOHIDEventAppendEvent)(IOHIDEventRef, IOHIDEventRef, IOHIDEventOptionBits);
static IOHIDEventSystemClientRef (*_IOHIDEventSystemClientCreate)(CFAllocatorRef);
static void (*_IOHIDEventSystemClientDispatchEvent)(IOHIDEventSystemClientRef, IOHIDEventRef);
static void (*_IOHIDEventSetSenderID)(IOHIDEventRef, uint64_t);
static void (*_IOHIDEventSetIntegerValueWithOptions)(IOHIDEventRef, uint32_t, uint32_t, uint32_t);
static void (*_IOHIDEventSetIntegerValue)(IOHIDEventRef, uint32_t, uint32_t);

static uint64_t rc_get_digitizer_sender_id(void) {
    void *ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!ioKit) return 0xDEFACEDBEEFFECE5ULL;

    CFArrayRef (*copyServices)(IOHIDEventSystemClientRef) = (CFArrayRef (*)(IOHIDEventSystemClientRef))dlsym(ioKit, "IOHIDEventSystemClientCopyServices");
    CFTypeRef (*copyProperty)(CFTypeRef, CFStringRef) = (CFTypeRef (*)(CFTypeRef, CFStringRef))dlsym(ioKit, "IOHIDServiceClientCopyProperty");
    uint64_t (*getRegistryID)(CFTypeRef) = (uint64_t (*)(CFTypeRef))dlsym(ioKit, "IOHIDServiceClientGetRegistryID");

    if (!copyServices || !copyProperty || !getRegistryID || !_IOHIDEventSystemClientCreate) {
        return 0xDEFACEDBEEFFECE5ULL;
    }

    IOHIDEventSystemClientRef client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return 0xDEFACEDBEEFFECE5ULL;

    uint64_t resolvedID = 0;
    CFArrayRef services = copyServices(client);
    if (services) {
        CFIndex count = CFArrayGetCount(services);
        for (CFIndex i = 0; i < count; i++) {
            CFTypeRef service = CFArrayGetValueAtIndex(services, i);
            CFTypeRef usagePageRef = copyProperty(service, CFSTR("PrimaryUsagePage"));
            CFTypeRef usageRef = copyProperty(service, CFSTR("PrimaryUsage"));

            if (usagePageRef && usageRef) {
                int usagePage = 0;
                int usage = 0;
                CFNumberGetValue((CFNumberRef)usagePageRef, kCFNumberIntType, &usagePage);
                CFNumberGetValue((CFNumberRef)usageRef, kCFNumberIntType, &usage);

                CFRelease(usagePageRef);
                CFRelease(usageRef);

                if (usagePage == 13 && usage == 4) {
                    uint64_t regID = getRegistryID(service);
                    if (regID != 0) {
                        resolvedID = regID;
                        break;
                    }
                }
            }
        }
        CFRelease(services);
    }
    CFRelease(client);

    return (resolvedID != 0) ? resolvedID : 0xDEFACEDBEEFFECE5ULL;
}

static void perform_digitizer_touch(double x, double y, int down, uint32_t contextID, double screenWidth, double screenHeight) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!handle) {
        handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    }
    if (!handle) return;

    _IOHIDEventCreateDigitizerEvent = dlsym(handle, "IOHIDEventCreateDigitizerEvent");
    _IOHIDEventCreateDigitizerFingerEvent = dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
    _IOHIDEventAppendEvent = dlsym(handle, "IOHIDEventAppendEvent");
    _IOHIDEventSystemClientCreate = dlsym(handle, "IOHIDEventSystemClientCreate");
    _IOHIDEventSystemClientDispatchEvent = dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
    _IOHIDEventSetSenderID = dlsym(handle, "IOHIDEventSetSenderID");
    _IOHIDEventSetIntegerValueWithOptions = dlsym(handle, "IOHIDEventSetIntegerValueWithOptions");
    _IOHIDEventSetIntegerValue = dlsym(handle, "IOHIDEventSetIntegerValue");

    if (!_IOHIDEventCreateDigitizerEvent || !_IOHIDEventCreateDigitizerFingerEvent ||
        !_IOHIDEventAppendEvent || !_IOHIDEventSystemClientCreate || !_IOHIDEventSystemClientDispatchEvent) {
        return;
    }

    double injectX = x;
    double injectY = y;
    if (contextID == 0) {
        if (screenWidth > 0) injectX = x / screenWidth;
        if (screenHeight > 0) injectY = y / screenHeight;
    }

    uint32_t transducerType = 3;
    uint32_t parentIndex = 0;
    uint32_t parentIdentity = 1;
    uint32_t parentEventMask = 0;
    uint32_t parentButtonMask = 0;
    uint64_t ts = mach_absolute_time();
    uint32_t fingerIndex = 1;
    uint32_t fingerIdentity = 2;
    uint32_t fingerEventMask = 0x3; // kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch
    double pressure = down ? 1.0 : 0.0;
    uint32_t handEventMask = 35;
    uint32_t handEventTouch = down ? 1 : 0;

    IOHIDEventRef parentGlobal = _IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, ts,
        transducerType, parentIndex, parentIdentity, parentEventMask, parentButtonMask,
        0.0, 0.0, 0.0, 0.0, 0.0,
        0, 0, 0);

    if (parentGlobal) {
        IOHIDEventRef fingerGlobal = _IOHIDEventCreateDigitizerFingerEvent(
            kCFAllocatorDefault, ts,
            fingerIndex, fingerIdentity, fingerEventMask,
            injectX, injectY, 0.0, pressure, 0.0,
            (boolean_t)down, (boolean_t)down, 0);

        if (fingerGlobal) {
            _IOHIDEventAppendEvent(parentGlobal, fingerGlobal, 0);
            CFRelease(fingerGlobal);
        }

        if (_IOHIDEventSetIntegerValueWithOptions) {
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720921, 1, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720925, 1, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 4, 1, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720903, handEventMask, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720904, handEventTouch, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720905, handEventTouch, 0xF0000000);
        } else if (_IOHIDEventSetIntegerValue) {
            _IOHIDEventSetIntegerValue(parentGlobal, 720921, 1);
            _IOHIDEventSetIntegerValue(parentGlobal, 720925, 1);
            _IOHIDEventSetIntegerValue(parentGlobal, 4, 1);
            _IOHIDEventSetIntegerValue(parentGlobal, 720903, handEventMask);
            _IOHIDEventSetIntegerValue(parentGlobal, 720904, handEventTouch);
            _IOHIDEventSetIntegerValue(parentGlobal, 720905, handEventTouch);
        }

        if (_IOHIDEventSetSenderID) {
            _IOHIDEventSetSenderID(parentGlobal, rc_get_digitizer_sender_id());
        }

        if (contextID > 0) {
            void *bbs = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
            if (bbs) {
                typedef void (*BKSHIDEventSetDigitizerInfoFn)(IOHIDEventRef, uint32_t, uint8_t, uint8_t, CFStringRef, CFTimeInterval, float);
                BKSHIDEventSetDigitizerInfoFn setDigitizerInfo = (BKSHIDEventSetDigitizerInfoFn)dlsym(bbs, "BKSHIDEventSetDigitizerInfo");
                if (setDigitizerInfo) {
                    setDigitizerInfo(parentGlobal, contextID, 0, 0, NULL, 0.0, 0.0);
                }
                dlclose(bbs);
            }
        }

        IOHIDEventSystemClientRef client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (client) {
            _IOHIDEventSystemClientDispatchEvent(client, parentGlobal);
            CFRelease(client);
        }
        CFRelease(parentGlobal);
    }
}

static void rc_simulate_tap(double px, double py, uint32_t contextID, double screenWidth, double screenHeight) {
    perform_digitizer_touch(px, py, 1, contextID, screenWidth, screenHeight);
    usleep(80000);
    perform_digitizer_touch(px, py, 0, contextID, screenWidth, screenHeight);
}

static void rc_simulate_hold(double px, double py, int durationMs, uint32_t contextID, double screenWidth, double screenHeight) {
    int clampedMs = durationMs < 50 ? 50 : (durationMs > 10000 ? 10000 : durationMs);
    perform_digitizer_touch(px, py, 1, contextID, screenWidth, screenHeight);
    usleep(clampedMs * 1000);
    perform_digitizer_touch(px, py, 0, contextID, screenWidth, screenHeight);
}

static void rc_simulate_swipe(double x1, double y1, double x2, double y2, uint32_t contextID, double screenWidth, double screenHeight) {
    const int steps = 40;
    const int stepDelayUs = 15000;
    perform_digitizer_touch(x1, y1, 1, contextID, screenWidth, screenHeight);
    usleep(16000);
    for (int i = 1; i <= steps; i++) {
        double t = (double)i / steps;
        double cx = x1 + (x2 - x1) * t;
        double cy = y1 + (y2 - y1) * t;
        perform_digitizer_touch(cx, cy, 1, contextID, screenWidth, screenHeight);
        usleep(stepDelayUs);
    }
    usleep(16000);
    perform_digitizer_touch(x2, y2, 0, contextID, screenWidth, screenHeight);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: rc-root <command> [args...]\n");
        return 1;
    }

    // Ensure we're running as root (setuid should handle this)
    if (setuid(0) != 0) {
        fprintf(stderr, "Error: Failed to setuid to root\n");
        return 1;
    }

    if (setgid(0) != 0) {
        fprintf(stderr, "Error: Failed to setgid to root\n");
        return 1;
    }

    // All privileged operations (shell and touch injection) are restricted to calls
    // made by SpringBoard (RemoteCommand's tweak), unless the user turned on
    // Allow Direct Root Helper Calls in Advanced Settings
    if (!rc_direct_calls_allowed() && !rc_parent_is_springboard()) {
        fprintf(stderr, "Error: rc-root may only be run by RemoteCommand (permission denied).\n");
        fprintf(stderr, "To allow scripts and other tools to call rc-root directly, turn on Allow Direct Root Helper Calls in Settings > Advanced Settings > Security.\n");
        return 1;
    }

    if (strcmp(argv[1], "iohid") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Usage: rc-root iohid <tap|hold|swipe> [args...]\n");
            return 1;
        }
        if (strcmp(argv[2], "tap") == 0 && argc >= 5) {
            uint32_t contextID = (argc >= 6) ? (uint32_t)strtoul(argv[5], NULL, 10) : 0;
            double sw = (argc >= 8) ? atof(argv[6]) : 0;
            double sh = (argc >= 8) ? atof(argv[7]) : 0;
            rc_simulate_tap(atof(argv[3]), atof(argv[4]), contextID, sw, sh);
            return 0;
        } else if (strcmp(argv[2], "hold") == 0 && argc >= 6) {
            int duration = atoi(argv[5]);
            uint32_t contextID = (argc >= 7) ? (uint32_t)strtoul(argv[6], NULL, 10) : 0;
            double sw = (argc >= 9) ? atof(argv[7]) : 0;
            double sh = (argc >= 9) ? atof(argv[8]) : 0;
            rc_simulate_hold(atof(argv[3]), atof(argv[4]), duration, contextID, sw, sh);
            return 0;
        } else if (strcmp(argv[2], "swipe") == 0 && argc >= 7) {
            uint32_t contextID = (argc >= 8) ? (uint32_t)strtoul(argv[7], NULL, 10) : 0;
            double sw = (argc >= 10) ? atof(argv[8]) : 0;
            double sh = (argc >= 10) ? atof(argv[9]) : 0;
            rc_simulate_swipe(atof(argv[3]), atof(argv[4]), atof(argv[5]), atof(argv[6]), contextID, sw, sh);
            return 0;
        }
        fprintf(stderr, "Invalid iohid subcommand or arguments\n");
        return 1;
    }

    if (strcmp(argv[1], "exec") == 0) {
        // Runs a program as root directly, without a shell:
        //   rc-root exec [--timeout <seconds>] /path/tool [args...]
        // With --timeout the program runs in a process group of its own, and the whole group (the
        // program and anything it started) is stopped when time runs out. SpringBoard can't stop a
        // root program itself, so this is how add-ons' root steps keep to their time limit.
        int first = 2;
        int timeout = 0;
        if (argc >= 4 && strcmp(argv[2], "--timeout") == 0) {
            timeout = atoi(argv[3]);
            first = 4;
        }
        if (argc <= first || argv[first][0] != '/') {
            fprintf(stderr, "Usage: rc-root exec [--timeout <seconds>] /full/path [args...]\n");
            return 1;
        }
        setenv("HOME", "/var/root", 1);
        if (timeout <= 0) {
            execv(argv[first], &argv[first]);
            perror("rc-root exec");
            return 127;
        }
        pid_t child = fork();
        if (child < 0) {
            perror("rc-root exec");
            return 127;
        }
        if (child == 0) {
            setpgid(0, 0);
            execv(argv[first], &argv[first]);
            perror("rc-root exec");
            _exit(127);
        }
        setpgid(child, child);   // also here, so the group exists whichever runs first
        uint64_t start = mach_absolute_time();
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        int status = 0;
        while (1) {
            pid_t done = waitpid(child, &status, WNOHANG);
            if (done == child) return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
            if (done < 0) return 127;
            double elapsed = (double)(mach_absolute_time() - start) * timebase.numer / timebase.denom / 1e9;
            if (elapsed >= timeout) break;
            usleep(20000);
        }
        killpg(child, SIGKILL);
        kill(child, SIGKILL);
        waitpid(child, &status, 0);
        fprintf(stderr, "rc-root exec: %s took longer than %d s and was stopped\n", argv[first], timeout);
        return 137;
    }

    // Build command string from all arguments for shell execution
    size_t total_len = 0;
    for (int i = 1; i < argc; i++) {
        total_len += strlen(argv[i]) + 1;
    }

    char *cmd = malloc(total_len + 1);
    if (!cmd) {
        fprintf(stderr, "Error: Memory allocation failed\n");
        return 1;
    }

    cmd[0] = '\0';
    for (int i = 1; i < argc; i++) {
        strcat(cmd, argv[i]);
        if (i < argc - 1) {
            strcat(cmd, " ");
        }
    }

    // Use posix_spawn to run sh -c "command"
    // Try rootless path first, fall back to standard path
    pid_t pid;
    const char *shell_path = "/var/jb/usr/bin/sh";

    // Check if rootless shell exists, otherwise use standard path
    if (access(shell_path, X_OK) != 0) {
        shell_path = "/bin/sh";
    }

    // Build PATH with custom paths prepended
    // Build PATH
    char *path_env = strdup("PATH=/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin");

    // Set up environment
    char *new_env[] = {
        path_env,
        "HOME=/var/root",
        NULL
    };

    char *shell_args[] = {(char *)shell_path, "-c", cmd, NULL};

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT);
#endif

    int status = posix_spawn(&pid, shell_path, NULL, &attr, shell_args, new_env);
    posix_spawnattr_destroy(&attr);

    if (status != 0) {
        fprintf(stderr, "Error: posix_spawn failed with status %d\n", status);
        free(cmd);
        free(path_env);
        return 1;
    }

    // Wait for child process
    int exit_status;
    waitpid(pid, &exit_status, 0);

    free(cmd);
    free(path_env);

    if (WIFEXITED(exit_status)) {
        return WEXITSTATUS(exit_status);
    }

    return 1;
}
