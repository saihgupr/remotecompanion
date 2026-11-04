// rc-screen: what's on the screen, as text, from the accessibility tree (what VoiceOver reads).
// For scripts and assistants that drive the phone: read the screen, find an element, press it,
// wait for something to appear.
//
//   rc-screen [--json]              the app in front and the elements on screen
//   rc-screen find TEXT [--json]    elements whose label or value contains TEXT
//   rc-screen press TEXT|#N         presses the element (exact label first, then contains; #N by
//                                   its number in the list)
//   rc-screen wait TEXT [SECONDS]   waits until TEXT is on screen and settled (default 10 s)
//   rc-screen tap TEXT|#N           a real touch on the element's center (for what press can't reach)
//   rc-screen hold TEXT|#N [SECONDS] touches and holds it (default 1 s)
//   rc-screen menu TEXT|#N          opens the element's menu (as a long press does, without the touch)
//   rc-screen type TEXT             types into the text field being edited
//
// Exit status: 0 done, 1 not found or timed out, 2 error.
//
// Apps answer accessibility questions only once they've loaded their accessibility support,
// which they do while accessibility automation is on. It's turned on for the run and back off
// after (an app that loaded it keeps answering).

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/wait.h>
#import <fcntl.h>
#import <signal.h>

extern char **environ;

static Boolean (*AXSAutomationEnabled)(void);
static void (*AXSSetAutomationEnabled)(Boolean);
// Set while rc-screen has accessibility automation on. Any run that finds it turns automation
// back off when done, so a run that was killed (or overlapped another) can't leave it on.
static const char *kRCScreenMarker = "/tmp/rc-screen-automation";

static id rc_call(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, sel);
}

static CGRect rc_frame(id element) {
    SEL sel = NSSelectorFromString(@"frame");
    if (![element respondsToSelector:sel]) return CGRectZero;
    return ((CGRect (*)(id, SEL))objc_msgSend)(element, sel);
}

static uint64_t rc_traits(id element) {
    SEL sel = NSSelectorFromString(@"traits");
    if (![element respondsToSelector:sel]) return 0;
    return ((uint64_t (*)(id, SEL))objc_msgSend)(element, sel);
}

static NSString *rc_text(id value) {
    if (!value) return @"";
    NSString *text = [value isKindOfClass:[NSString class]] ? value : [value description];
    // One line per element
    text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    // Plain characters for look-alikes, so what's shown is what can be typed back ("Wi‑Fi" has a
    // non-breaking hyphen)
    static NSDictionary<NSString *, NSString *> *plain;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = @{ @"\u2010": @"-", @"\u2011": @"-", @"\u2012": @"-", @"\u2013": @"-", @"\u2212": @"-",
                   @"\u00a0": @" ", @"\u202f": @" ", @"\u2007": @" ", @"\u2009": @" ",
                   @"\u2018": @"'", @"\u2019": @"'", @"\u201c": @"\"", @"\u201d": @"\"" };
    });
    for (NSString *from in plain) text = [text stringByReplacingOccurrencesOfString:from withString:plain[from]];
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

// What kind of element, from its UIAccessibilityTraits
static NSString *rc_kind(uint64_t traits) {
    if (traits & 0x400) return @"search";       // search field
    if (traits & 0x20) return @"key";           // keyboard key
    if (traits & 0x2) return @"link";
    if (traits & 0x1) return @"button";
    if (traits & 0x1000) return @"adjustable";  // slider, picker
    if (traits & 0x10000) return @"header";
    if (traits & 0x4) return @"image";
    if (traits & 0x40) return @"text";
    return @"element";
}

@interface RCScreenElement : NSObject
@property (nonatomic, strong) id element;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic) CGRect frame;
@property (nonatomic) uint64_t traits;
@property (nonatomic) NSUInteger number;
@end
@implementation RCScreenElement
@end

// The app in front, or SpringBoard (home screen, lock screen) when there's none
static id rc_primary_app(void) {
    Class AXElement = NSClassFromString(@"AXElement");
    id app = rc_call(AXElement, @"primaryApp");
    if (rc_call(app, @"explorerElements")) return app;
    id system = rc_call(AXElement, @"systemApplication");
    return system ?: app;
}

static NSArray<RCScreenElement *> *rc_elements(id app) {
    NSMutableArray *list = [NSMutableArray array];
    NSUInteger number = 0;
    for (id element in rc_call(app, @"explorerElements")) {
        RCScreenElement *e = [RCScreenElement new];
        e.element = element;
        e.label = rc_text(rc_call(element, @"label"));
        e.value = rc_text(rc_call(element, @"value"));
        e.traits = rc_traits(element);
        e.kind = rc_kind(e.traits);
        e.frame = rc_frame(element);
        e.number = ++number;
        [list addObject:e];
    }
    return list;
}

static NSString *rc_quote(NSString *text) {
    return [NSString stringWithFormat:@"\"%@\"", [text stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
}

static NSString *rc_line(RCScreenElement *e) {
    NSMutableString *line = [NSMutableString stringWithFormat:@"%lu. %@ %@", (unsigned long)e.number, e.kind, rc_quote(e.label)];
    if (e.value.length) [line appendFormat:@" = %@", rc_quote(e.value)];
    if (e.traits & 0x100) [line appendString:@" (dimmed)"];
    if (e.traits & 0x8) [line appendString:@" (selected)"];
    CGRect f = e.frame;
    [line appendFormat:@" at %.0f,%.0f (%.0fx%.0f)", round(CGRectGetMidX(f)), round(CGRectGetMidY(f)), f.size.width, f.size.height];
    return line;
}

static NSDictionary *rc_json(RCScreenElement *e) {
    CGRect f = e.frame;
    return @{
        @"number": @(e.number),
        @"kind": e.kind,
        @"label": e.label,
        @"value": e.value,
        @"traits": @(e.traits),
        @"dimmed": (e.traits & 0x100) ? @YES : @NO,
        @"selected": (e.traits & 0x8) ? @YES : @NO,
        @"x": @(round(CGRectGetMidX(f))), @"y": @(round(CGRectGetMidY(f))),
        @"frame": @[@(round(f.origin.x)), @(round(f.origin.y)), @(round(f.size.width)), @(round(f.size.height))],
    };
}

static void rc_print_json(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    printf("\n");
}

static BOOL rc_matches(RCScreenElement *e, NSString *text) {
    text = rc_text(text);
    NSStringCompareOptions o = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    return [e.label rangeOfString:text options:o].location != NSNotFound || [e.value rangeOfString:text options:o].location != NSNotFound;
}

// #N, an exact label, or the first label or value that contains the text
static RCScreenElement *rc_pick(NSArray<RCScreenElement *> *list, NSString *text) {
    text = rc_text(text);
    if ([text hasPrefix:@"#"] && text.length > 1) {
        NSInteger n = [[text substringFromIndex:1] integerValue];
        return n >= 1 && n <= (NSInteger)list.count ? list[n - 1] : nil;
    }
    for (RCScreenElement *e in list) {
        if ([e.label compare:text options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch] == NSOrderedSame) return e;
    }
    for (RCScreenElement *e in list) if (rc_matches(e, text)) return e;
    return nil;
}

static void rc_restore(void) {
    if (access(kRCScreenMarker, F_OK) != 0 || !AXSSetAutomationEnabled) return;
    AXSSetAutomationEnabled(0);
    // The setting is saved by another process; wait until it reads back, or it's lost at exit
    for (int i = 0; i < 20 && AXSAutomationEnabled && AXSAutomationEnabled(); i++) usleep(25000);
    unlink(kRCScreenMarker);
}

static void rc_quit(int sig) {
    exit(130);
}

static int rc_usage(void) {
    fprintf(stderr, "Usage: rc-screen [--json] | find TEXT [--json] | press TEXT|#N | wait TEXT [SECONDS] | tap TEXT|#N | hold TEXT|#N [SECONDS] | menu TEXT|#N | type TEXT\n");
    return 2;
}

// Runs an RC command (tap and hold go through the tweak, which makes the touch); 0 when it worked
static int rc_command(NSString *command) {
    const char *paths[] = { "/var/jb/usr/bin/rc-client", "/usr/bin/rc-client" };
    for (int i = 0; i < 2; i++) {
        if (access(paths[i], X_OK) != 0) continue;
        int out[2];
        if (pipe(out) != 0) return 2;
        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO);
        posix_spawn_file_actions_addclose(&actions, out[0]);
        char *argv[] = { (char *)paths[i], (char *)command.UTF8String, NULL };
        pid_t pid;
        int err = posix_spawn(&pid, paths[i], &actions, NULL, argv, environ);
        posix_spawn_file_actions_destroy(&actions);
        close(out[1]);
        if (err != 0) { close(out[0]); return 2; }
        NSMutableData *reply = [NSMutableData data];
        char buffer[512];
        ssize_t n;
        while ((n = read(out[0], buffer, sizeof(buffer))) > 0) [reply appendBytes:buffer length:n];
        close(out[0]);
        int status = 0;
        waitpid(pid, &status, 0);
        NSString *text = [[NSString alloc] initWithData:reply encoding:NSUTF8StringEncoding] ?: @"";
        if ([text hasPrefix:@"Error"] || [text hasPrefix:@"Stopped"]) {
            fprintf(stderr, "%s", text.UTF8String);
            return 2;
        }
        return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 2;
    }
    fprintf(stderr, "Error: rc-client isn't installed\n");
    return 2;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        // Piped into head, or stopped with Ctrl-C: still clean up (rc_restore runs at exit)
        signal(SIGPIPE, SIG_IGN);
        signal(SIGINT, rc_quit);
        signal(SIGTERM, rc_quit);
        NSMutableArray<NSString *> *args = [NSMutableArray array];
        BOOL json = NO;
        for (int i = 1; i < argc; i++) {
            NSString *a = @(argv[i]);
            if ([a isEqualToString:@"--json"]) json = YES;
            else if ([a isEqualToString:@"-h"] || [a isEqualToString:@"--help"]) return rc_usage();
            else [args addObject:a];
        }
        NSString *verb = args.count ? args[0] : @"list";
        if (![@[@"list", @"find", @"press", @"wait", @"tap", @"hold", @"menu", @"type"] containsObject:verb]) return rc_usage();
        if (![verb isEqualToString:@"list"] && args.count < 2) return rc_usage();

        void *lib = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW);
        AXSAutomationEnabled = lib ? dlsym(lib, "_AXSAutomationEnabled") : NULL;
        AXSSetAutomationEnabled = lib ? dlsym(lib, "_AXSSetAutomationEnabled") : NULL;
        void *ax = dlopen("/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime", RTLD_NOW);
        if (!ax || !NSClassFromString(@"AXElement")) {
            fprintf(stderr, "Error: Accessibility isn't available\n");
            return 2;
        }
        void (*setTimeout)(float) = dlsym(ax, "AXUIElementSetGlobalTimeout");
        if (setTimeout) setTimeout(3); // an app that doesn't answer can't hang the run
        if (AXSAutomationEnabled && AXSSetAutomationEnabled && !AXSAutomationEnabled()) {
            close(open(kRCScreenMarker, O_CREAT | O_WRONLY, 0666));
            AXSSetAutomationEnabled(1);
        }
        atexit(rc_restore);

        id app = rc_primary_app();
        NSString *appName = rc_text(rc_call(app, @"label"));
        // No app in front: the home screen or lock screen, which SpringBoard shows
        SEL systemSel = NSSelectorFromString(@"isSystemApplication");
        BOOL system = [app respondsToSelector:systemSel] && ((BOOL (*)(id, SEL))objc_msgSend)(app, systemSel);
        if (system || !appName.length) appName = @"SpringBoard";

        if ([verb isEqualToString:@"wait"]) {
            NSString *text = args[1];
            double seconds = args.count > 2 ? [args[2] doubleValue] : 10;
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
            // Found, with the whole screen the same on two reads in a row, so a screen still
            // sliding in doesn't count (iOS ignores presses until it's done)
            NSString *last = nil;
            do {
                NSArray<RCScreenElement *> *list = rc_elements(rc_primary_app());
                RCScreenElement *found = nil;
                NSMutableString *screen = [NSMutableString string];
                for (RCScreenElement *e in list) {
                    if (!found && rc_matches(e, text)) found = e;
                    [screen appendFormat:@"%@\n", rc_line(e)];
                }
                if (found && [screen isEqualToString:last]) {
                    // The list settles a moment before the transition ends; a press then is lost
                    [NSThread sleepForTimeInterval:0.25];
                    if (json) rc_print_json(rc_json(found));
                    else printf("%s\n", rc_line(found).UTF8String);
                    return 0;
                }
                last = found ? screen : nil;
                [NSThread sleepForTimeInterval:found ? 0.15 : 0.25];
            } while ([until timeIntervalSinceNow] > 0);
            fprintf(stderr, "Not found after %g s: %s\n", seconds, args[1].UTF8String);
            return 1;
        }

        if ([verb isEqualToString:@"type"]) {
            // Into the field being edited, as if typed: any characters, at the cursor
            id field = rc_call(app, @"firstResponder");
            if (!field) {
                fprintf(stderr, "No text field is being edited\n");
                return 1;
            }
            NSString *text = [[args subarrayWithRange:NSMakeRange(1, args.count - 1)] componentsJoinedByString:@" "];
            NSString *before = rc_text(rc_call(field, @"value"));
            ((void (*)(id, SEL, id))objc_msgSend)(field, NSSelectorFromString(@"insertText:"), text);
            // The field shows it a moment later
            NSString *now = before;
            for (int i = 0; i < 10 && [now isEqualToString:before]; i++) {
                [NSThread sleepForTimeInterval:0.05];
                now = rc_text(rc_call(rc_call(rc_primary_app(), @"firstResponder") ?: field, @"value"));
            }
            printf("Typed into %s: now %s\n", rc_quote(rc_text(rc_call(field, @"label"))).UTF8String, rc_quote(now).UTF8String);
            return 0;
        }

        NSArray<RCScreenElement *> *list = rc_elements(app);

        if ([verb isEqualToString:@"tap"] || [verb isEqualToString:@"hold"]) {
            RCScreenElement *e = rc_pick(list, args[1]);
            if (!e) {
                fprintf(stderr, "Not on screen: %s\n", args[1].UTF8String);
                return 1;
            }
            CGRect f = e.frame;
            NSString *command = [NSString stringWithFormat:@"gesture %@ %.1f %.1f", verb, CGRectGetMidX(f), CGRectGetMidY(f)];
            if ([verb isEqualToString:@"hold"] && args.count > 2) command = [command stringByAppendingFormat:@" %g", [args[2] doubleValue]];
            int result = rc_command(command);
            if (result == 0) printf("%s %s\n", [verb isEqualToString:@"tap"] ? "Tapped" : "Held", rc_line(e).UTF8String);
            return result;
        }

        if ([verb isEqualToString:@"press"] || [verb isEqualToString:@"menu"]) {
            RCScreenElement *e = rc_pick(list, args[1]);
            if (!e) {
                fprintf(stderr, "Not on screen: %s\n", args[1].UTF8String);
                return 1;
            }
            BOOL menu = [verb isEqualToString:@"menu"];
            BOOL ok = YES;
            if (menu) ((void (*)(id, SEL))objc_msgSend)(e.element, NSSelectorFromString(@"showContextMenu"));
            else ok = ((BOOL (*)(id, SEL))objc_msgSend)(e.element, NSSelectorFromString(@"press"));
            if (!ok) {
                fprintf(stderr, "Couldn't press: %s\n", rc_line(e).UTF8String);
                return 2;
            }
            printf("%s %s\n", menu ? "Opened the menu of" : "Pressed", rc_line(e).UTF8String);
            return 0;
        }

        if ([verb isEqualToString:@"find"]) {
            NSMutableArray *found = [NSMutableArray array];
            for (RCScreenElement *e in list) if (rc_matches(e, args[1])) [found addObject:e];
            if (json) {
                NSMutableArray *out = [NSMutableArray array];
                for (RCScreenElement *e in found) [out addObject:rc_json(e)];
                rc_print_json(out);
            } else {
                for (RCScreenElement *e in found) printf("%s\n", rc_line(e).UTF8String);
            }
            return found.count ? 0 : 1;
        }

        if (json) {
            NSMutableArray *out = [NSMutableArray array];
            for (RCScreenElement *e in list) [out addObject:rc_json(e)];
            rc_print_json(@{ @"app": appName, @"elements": out });
        } else {
            printf("%s\n", appName.UTF8String);
            for (RCScreenElement *e in list) printf("%s\n", rc_line(e).UTF8String);
        }
        return 0;
    }
}
