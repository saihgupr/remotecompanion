// rc-screen: what's on the screen, as text, from the accessibility tree (what VoiceOver reads).
// For scripts and assistants that drive the phone: read the screen, find an element, press it,
// wait for something to appear.
//
//   rc-screen [--json]              the app in front and the elements on screen
//   rc-screen find TEXT [--json]    elements whose label or value contains TEXT
//   rc-screen press TEXT|#N         presses the element (exact label first, then contains; #N by
//                                   its number in the list)
//   rc-screen wait TEXT [SECONDS]   waits until TEXT is on screen and settled (default 10 s)
//   rc-screen scroll-to TEXT [up|left|right]
//                                   scrolls until TEXT is on screen: down first (or the way given),
//                                   then back the other way once the list ends
//   rc-screen tap TEXT|#N           a real touch on the element's center (for what press can't reach)
//   rc-screen hold TEXT|#N [SECONDS] touches and holds it (default 1 s)
//   rc-screen pinch TEXT|#N SCALE   two fingers on it, apart (2: zoom in) or together (0.5: zoom out)
//   rc-screen rotate TEXT|#N DEGREES two fingers turning on it (clockwise above 0)
//   rc-screen menu TEXT|#N          opens the element's menu (as a long press does, without the touch)
//   rc-screen type TEXT             types into the text field being edited (--replace: clears it first)
//   rc-screen clear                 empties the text field being edited
//   rc-screen set TEXT|#N on|off    turns a switch on or off (only presses it if it needs to)
//   rc-screen adjust TEXT|#N up|down [STEPS] | adjust TEXT|#N 30%
//                                   moves a slider, stepper or picker a step at a time (as
//                                   VoiceOver's swipe up/down does), or toward a percentage
//
// Web pages (Safari, in-app browsers) are read too: their text, links and buttons follow the
// app's own elements, in reading order.
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

// A switch: iOS 17's toggle trait (1 << 53), or (iOS 14) a button reading 0 or 1 with the
// trait switches carry there too (0x400000000)
static BOOL rc_is_switch(uint64_t traits, NSString *value) {
    if (traits & (1ULL << 53)) return YES;
    return (traits & 0x1) && (traits & 0x400000000ULL) && ([value isEqualToString:@"0"] || [value isEqualToString:@"1"]);
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

static RCScreenElement *rc_element_from(id element) {
    RCScreenElement *e = [RCScreenElement new];
    e.element = element;
    e.label = rc_text(rc_call(element, @"label"));
    e.value = rc_text(rc_call(element, @"value"));
    e.traits = rc_traits(element);
    e.kind = rc_is_switch(e.traits, e.value) ? @"switch" : rc_kind(e.traits);
    e.frame = rc_frame(element);
    return e;
}

// Web content (Safari, in-app browsers) lives in another process, so the app's own list stops at
// the browser's buttons. Hit-testing a point reaches into it; from there the page's root (the
// highest ancestor still marked as web content, trait 0x20000) lists the whole page.
static const uint64_t kRCWebTrait = 0x20000;

static void rc_web_collect(id node, int depth, CGRect screen, NSMutableArray<RCScreenElement *> *out, int *budget) {
    if (!node || depth > 40 || *budget <= 0) return;
    (*budget)--;
    RCScreenElement *e = rc_element_from(node);
    NSArray *kids = rc_call(node, @"children");
    BOOL hasText = e.label.length || e.value.length;
    BOOL actionable = (e.traits & (0x1 | 0x2 | 0x400 | 0x1000)) != 0 || (e.traits & 0x40000); // button, link, search, adjustable, text entry
    // A leaf with text, or anything that can be acted on (a link keeps its text, its parts aren't listed)
    if ((hasText && kids.count == 0) || (actionable && (hasText || kids.count == 0))) {
        if (CGRectIntersectsRect(e.frame, screen) && !CGRectIsEmpty(e.frame)) [out addObject:e];
        if (actionable) return;
    }
    for (id kid in kids) rc_web_collect(kid, depth + 1, screen, out, budget);
}

static NSArray<RCScreenElement *> *rc_web_elements(id app) {
    CGRect screen = rc_frame(app);
    if (CGRectIsEmpty(screen)) return @[];
    Class AXElement = NSClassFromString(@"AXElement");
    SEL hitSel = NSSelectorFromString(@"elementAtCoordinate:withVisualPadding:");
    if (![AXElement respondsToSelector:hitSel]) return @[];
    NSMutableArray<RCScreenElement *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *roots = [NSMutableSet set];
    int budget = 600;
    for (int row = 1; row <= 6; row++) {
        CGPoint pt = CGPointMake(CGRectGetMidX(screen), screen.origin.y + screen.size.height * row / 7.0);
        id hit = ((id (*)(id, SEL, CGPoint, BOOL))objc_msgSend)(AXElement, hitSel, pt, NO);
        if (!hit || !(rc_traits(hit) & kRCWebTrait)) continue;
        id root = hit;
        for (int k = 0; k < 40; k++) {
            id parent = rc_call(root, @"elementParent");
            if (!parent || !(rc_traits(parent) & kRCWebTrait)) break;
            root = parent;
        }
        CGRect rf = rc_frame(root);
        NSString *key = [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f", rf.origin.x, rf.origin.y, rf.size.width, rf.size.height];
        if ([roots containsObject:key]) continue;
        [roots addObject:key];
        rc_web_collect(root, 0, screen, out, &budget);
    }
    // In the page's own order, which is the reading order (a phrase wrapping over two lines has a
    // box covering both, so sorting by position jumbles sentences)
    return out;
}

static NSArray<RCScreenElement *> *rc_elements(id app) {
    NSMutableArray *list = [NSMutableArray array];
    NSUInteger number = 0;
    for (id element in rc_call(app, @"explorerElements")) {
        RCScreenElement *e = rc_element_from(element);
        e.number = ++number;
        [list addObject:e];
    }
    for (RCScreenElement *e in rc_web_elements(app)) {
        e.number = ++number;
        [list addObject:e];
    }
    return list;
}

static NSString *rc_line(RCScreenElement *e);

// The screen once it has stopped changing (the same on two reads in a row), or as it is after
// `seconds`
static NSArray<RCScreenElement *> *rc_settled_elements(double seconds) {
    NSString *last = nil;
    NSArray<RCScreenElement *> *list = @[];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    do {
        list = rc_elements(rc_primary_app());
        NSMutableString *screen = [NSMutableString string];
        for (RCScreenElement *e in list) [screen appendFormat:@"%@\n", rc_line(e)];
        if ([screen isEqualToString:last]) return list;
        last = screen;
        [NSThread sleepForTimeInterval:0.15];
    } while ([until timeIntervalSinceNow] > 0);
    return list;
}

// What's on screen, ignoring where: a list bouncing at its end moves but shows nothing new
static NSSet<NSString *> *rc_screen_items(NSArray<RCScreenElement *> *list) {
    NSMutableSet *items = [NSMutableSet set];
    for (RCScreenElement *e in list) [items addObject:[NSString stringWithFormat:@"%@|%@|%@", e.kind, e.label, e.value]];
    return items;
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
    // An exact label, then a partial match; something that can be acted on (a link, button,
    // switch, field) before plain text
    NSSet *acting = [NSSet setWithArray:@[@"button", @"link", @"switch", @"key", @"search", @"adjustable"]];
    for (int pass = 0; pass < 4; pass++) {
        BOOL exact = pass < 2, needsActing = pass % 2 == 0;
        for (RCScreenElement *e in list) {
            if (needsActing && ![acting containsObject:e.kind]) continue;
            BOOL match = exact ? [e.label compare:text options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch] == NSOrderedSame : rc_matches(e, text);
            if (match) return e;
        }
    }
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
    fprintf(stderr, "Usage: rc-screen [--json] | find TEXT [--json] | press TEXT|#N | wait TEXT [SECONDS] | tap TEXT|#N | hold TEXT|#N [SECONDS] | menu TEXT|#N | type TEXT | scroll-to TEXT [up|left|right] | adjust TEXT|#N up|down [STEPS] | adjust TEXT|#N PERCENT%% | set TEXT|#N on|off | clear | pinch TEXT|#N SCALE | rotate TEXT|#N DEGREES\n");
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
        BOOL json = NO, replace = NO;
        for (int i = 1; i < argc; i++) {
            NSString *a = @(argv[i]);
            if ([a isEqualToString:@"--json"]) json = YES;
            else if ([a isEqualToString:@"--replace"]) replace = YES;
            else if ([a isEqualToString:@"-h"] || [a isEqualToString:@"--help"]) return rc_usage();
            else [args addObject:a];
        }
        NSString *verb = args.count ? args[0] : @"list";
        if (![@[@"list", @"find", @"press", @"wait", @"tap", @"hold", @"menu", @"type", @"scroll-to", @"adjust", @"set", @"clear", @"pinch", @"rotate"] containsObject:verb]) return rc_usage();
        if (![verb isEqualToString:@"list"] && ![verb isEqualToString:@"clear"] && args.count < 2) return rc_usage();

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
        NSString *bundleID = rc_text(rc_call(app, @"bundleId"));
        if (!bundleID.length && [appName isEqualToString:@"SpringBoard"]) bundleID = @"com.apple.springboard";

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

        if ([verb isEqualToString:@"type"] || [verb isEqualToString:@"clear"]) {
            // Into the field being edited, as if typed: any characters, at the cursor
            id field = rc_call(app, @"firstResponder");
            if (!field) {
                fprintf(stderr, "No text field is being edited\n");
                return 1;
            }
            if (replace || [verb isEqualToString:@"clear"]) {
                // Setting the value empties a text field (a slider ignores it)
                ((void (*)(id, SEL, id))objc_msgSend)(field, NSSelectorFromString(@"setValue:"), @"");
                [NSThread sleepForTimeInterval:0.15];
                if ([verb isEqualToString:@"clear"]) {
                    printf("Cleared %s\n", rc_quote(rc_text(rc_call(field, @"label"))).UTF8String);
                    return 0;
                }
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

        if ([verb isEqualToString:@"scroll-to"]) {
            // Swipes the list in the middle of the screen, gently enough not to fling past, until
            // the text shows; a swipe that brings in nothing new is the end of the list
            NSString *text = args[1];
            // Which way to look: down (the default), up, left or right; "down" brings in what's below
            NSString *way = args.count > 2 ? args[2].lowercaseString : @"down";
            if (![@[@"down", @"up", @"left", @"right"] containsObject:way]) return rc_usage();
            BOOL sideways = [way isEqualToString:@"left"] || [way isEqualToString:@"right"];
            BOOL down = [way isEqualToString:@"down"] || [way isEqualToString:@"right"]; // toward the end
            CGRect screen = rc_frame(app);
            if (CGRectIsEmpty(screen)) screen = CGRectMake(0, 0, 390, 844);
            // 60% of the screen per swipe: less than a screen, so nothing is skipped
            double x = CGRectGetMidX(screen), high = screen.origin.y + screen.size.height * 0.2, low = screen.origin.y + screen.size.height * 0.8;
            double y = CGRectGetMidY(screen), leftX = screen.origin.x + screen.size.width * 0.2, rightX = screen.origin.x + screen.size.width * 0.8;
            NSArray<RCScreenElement *> *list = rc_settled_elements(2);
            int turns = 0, swipes = 0;
            NSString *mention = nil; // text that only mentions it, kept scrolling past
            NSSet *acting = [NSSet setWithArray:@[@"button", @"link", @"switch", @"key", @"search", @"adjustable"]];
            // Pages run sideways, and are few; the home screen's live edges (Today View, App
            // Library) never look like an end, so a sideways search stops sooner
            while (swipes < (sideways ? 12 : 24)) {
                RCScreenElement *found = rc_pick(list, text); // an exact label first, as press does
                // Only an exact label or something to act on ends the search
                if (found && [found.label compare:rc_text(text) options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch] != NSOrderedSame && ![acting containsObject:found.kind]) {
                    if (!mention) mention = rc_line(found);
                    found = nil;
                }
                if (found) {
                    // Fully on screen, if it's cut off at an edge
                    CGRect f = found.frame;
                    if (CGRectGetMinY(f) < CGRectGetMinY(screen) || CGRectGetMaxY(f) > CGRectGetMaxY(screen)) {
                        ((void (*)(id, SEL))objc_msgSend)(found.element, NSSelectorFromString(@"scrollToVisible"));
                        list = rc_settled_elements(2);
                        found = rc_pick(list, text) ?: found;
                    }
                    if (json) rc_print_json(rc_json(found));
                    else printf("%s\n", rc_line(found).UTF8String);
                    return 0;
                }
                NSSet<NSString *> *before = rc_screen_items(list);
                NSString *swipe;
                if (sideways) {
                    // Seeing what's to the right drags the content left
                    swipe = down ? [NSString stringWithFormat:@"gesture swipe %.0f %.0f %.0f %.0f 0.5", rightX, y, leftX, y]
                                 : [NSString stringWithFormat:@"gesture swipe %.0f %.0f %.0f %.0f 0.5", leftX, y, rightX, y];
                } else {
                    swipe = down ? [NSString stringWithFormat:@"gesture swipe %.0f %.0f %.0f %.0f 0.5", x, low, x, high]
                                 : [NSString stringWithFormat:@"gesture swipe %.0f %.0f %.0f %.0f 0.5", x, high, x, low];
                }
                if (rc_command(swipe) != 0) return 2;
                swipes++;
                list = rc_settled_elements(2);
                if ([rc_screen_items(list) isSubsetOfSet:before]) {
                    // The end of the list: the other way, once
                    if (++turns > 1) break;
                    down = !down;
                }
            }
            if (mention) fprintf(stderr, "Not found after scrolling: %s (only mentioned in: %s)\n", text.UTF8String, mention.UTF8String);
            else fprintf(stderr, "Not found after scrolling: %s\n", text.UTF8String);
            return 1;
        }

        NSArray<RCScreenElement *> *list = rc_elements(app);

        if ([verb isEqualToString:@"set"]) {
            // The switch itself (its text row beside it has the same label): by #N, or the
            // pressable switch with this label (an exact label first)
            if (args.count < 3 || ![@[@"on", @"off"] containsObject:args[2].lowercaseString]) return rc_usage();
            BOOL wantOn = [args[2].lowercaseString isEqualToString:@"on"];
            RCScreenElement *e = nil;
            if ([args[1] hasPrefix:@"#"]) e = rc_pick(list, args[1]);
            NSArray<NSNumber *> *passes = @[@YES, @NO]; // exact label, then contains
            for (NSNumber *exact in passes) {
                for (RCScreenElement *x in list) {
                    if (e) break;
                    if (![x.kind isEqualToString:@"switch"] || !(x.traits & 0x1)) continue;
                    BOOL match = exact.boolValue ? [x.label compare:rc_text(args[1]) options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch] == NSOrderedSame : rc_matches(x, args[1]);
                    if (match) e = x;
                }
            }
            if (!e || ![e.kind isEqualToString:@"switch"]) {
                fprintf(stderr, "No switch on screen: %s\n", args[1].UTF8String);
                return 1;
            }
            BOOL isOn = [e.value isEqualToString:@"1"];
            if (isOn == wantOn) {
                printf("Already %s: %s\n", wantOn ? "on" : "off", rc_line(e).UTF8String);
                return 0;
            }
            ((BOOL (*)(id, SEL))objc_msgSend)(e.element, NSSelectorFromString(@"press"));
            // Read back (a switch can refuse, or ask first)
            RCScreenElement *now = nil;
            for (int i = 0; i < 10; i++) {
                [NSThread sleepForTimeInterval:0.1];
                for (RCScreenElement *x in rc_elements(rc_primary_app())) {
                    if ([x.label isEqualToString:e.label] && CGRectEqualToRect(x.frame, e.frame)) { now = x; break; }
                }
                if (now && [now.value isEqualToString:wantOn ? @"1" : @"0"]) break;
            }
            if (!now || ![now.value isEqualToString:wantOn ? @"1" : @"0"]) {
                fprintf(stderr, "Pressed it, but it reads %s now: %s\n", now ? now.value.UTF8String : "nothing", rc_line(now ?: e).UTF8String);
                return 2;
            }
            printf("Turned %s: %s\n", wantOn ? "on" : "off", rc_line(now).UTF8String);
            return 0;
        }

        if ([verb isEqualToString:@"adjust"]) {
            // Accessibility's increment (2004) and decrement (2005) actions: the step is the
            // element's own (a volume slider moves 10%)
            if (args.count < 3) return rc_usage();
            RCScreenElement *e = rc_pick(list, args[1]);
            if (!e) {
                fprintf(stderr, "Not on screen: %s\n", args[1].UTF8String);
                return 1;
            }
            if (!(e.traits & 0x1000)) {
                fprintf(stderr, "Not adjustable (a slider, stepper or picker is): %s\n", rc_line(e).UTF8String);
                return 1;
            }
            NSString *how = args[2].lowercaseString;
            SEL perform = NSSelectorFromString(@"performAction:");
            BOOL (*act)(id, SEL, int) = (BOOL (*)(id, SEL, int))objc_msgSend;
            // Re-reads the element (its value changes; the object may not)
            RCScreenElement *(^again)(void) = ^RCScreenElement *{
                NSArray<RCScreenElement *> *now = rc_elements(rc_primary_app());
                for (RCScreenElement *n in now) {
                    if ([n.label isEqualToString:e.label] && CGRectEqualToRect(n.frame, e.frame)) return n;
                }
                return rc_pick(now, args[1]);
            };
            if ([how isEqualToString:@"up"] || [how isEqualToString:@"down"]) {
                int steps = args.count > 3 ? MAX(1, MIN([args[3] intValue], 100)) : 1;
                int code = [how isEqualToString:@"up"] ? 2004 : 2005;
                for (int i = 0; i < steps; i++) {
                    if (!act(e.element, perform, code)) {
                        fprintf(stderr, "Couldn't adjust: %s\n", rc_line(e).UTF8String);
                        return 2;
                    }
                    [NSThread sleepForTimeInterval:0.08];
                }
                [NSThread sleepForTimeInterval:0.2];
                printf("Adjusted %s\n", rc_line(again() ?: e).UTF8String);
                return 0;
            }
            if (![how hasSuffix:@"%"]) return rc_usage();
            // Toward a percentage: a step at a time while that gets closer
            double target = [[how substringToIndex:how.length - 1] doubleValue];
            double (^percent)(RCScreenElement *) = ^double(RCScreenElement *x) {
                NSScanner *scan = [NSScanner scannerWithString:x.value ?: @""];
                [scan scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:NULL];
                double v = -1;
                return [scan scanDouble:&v] ? v : -1;
            };
            double value = percent(e);
            if (value < 0) {
                fprintf(stderr, "Its value isn't a percentage (%s); use up or down\n", e.value.UTF8String);
                return 1;
            }
            for (int i = 0; i < 100; i++) {
                if (fabs(value - target) < 0.5) break;
                int code = value < target ? 2004 : 2005;
                if (!act(e.element, perform, code)) break;
                [NSThread sleepForTimeInterval:0.12];
                RCScreenElement *now = again();
                double next = now ? percent(now) : -1;
                if (next < 0 || fabs(next - target) >= fabs(value - target)) {
                    // Overshot or stuck: go back if that was closer, and stop
                    if (next >= 0 && fabs(next - target) > fabs(value - target)) act(e.element, perform, code == 2004 ? 2005 : 2004);
                    break;
                }
                value = next;
                if (now) e = now;
            }
            [NSThread sleepForTimeInterval:0.15];
            printf("Adjusted %s\n", rc_line(again() ?: e).UTF8String);
            return 0;
        }

        if ([verb isEqualToString:@"pinch"] || [verb isEqualToString:@"rotate"]) {
            if (args.count < 3) return rc_usage();
            RCScreenElement *e = rc_pick(list, args[1]);
            if (!e) {
                fprintf(stderr, "Not on screen: %s\n", args[1].UTF8String);
                return 1;
            }
            CGRect f = e.frame;
            NSString *command = [NSString stringWithFormat:@"gesture %@ %.1f %.1f %g", verb, CGRectGetMidX(f), CGRectGetMidY(f), [args[2] doubleValue]];
            if (args.count > 3) command = [command stringByAppendingFormat:@" %g", [args[3] doubleValue]];
            int result = rc_command(command);
            if (result == 0) printf("%s %s\n", [verb isEqualToString:@"pinch"] ? "Pinched" : "Rotated", rc_line(e).UTF8String);
            return result;
        }

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
            rc_print_json(@{ @"app": appName, @"bundleID": bundleID, @"elements": out });
        } else {
            if (bundleID.length) printf("%s (%s)\n", appName.UTF8String, bundleID.UTF8String);
            else printf("%s\n", appName.UTF8String);
            for (RCScreenElement *e in list) printf("%s\n", rc_line(e).UTF8String);
        }
        return 0;
    }
}
