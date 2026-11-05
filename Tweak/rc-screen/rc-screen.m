// rc-screen: what's on the screen, as text, from the accessibility tree (what VoiceOver reads).
// For scripts and assistants that drive the phone: read the screen, find an element, press it,
// wait for something to appear.
//
//   rc-screen [--json|--outline]    the app in front and the elements on screen; --outline lays
//                                   them out for reading: alerts and keyboard first, top bar,
//                                   sections, side-by-side elements on one row, bottom bar
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
//   rc-screen watch [SECONDS] [--every S]  a line per change on the screen (and the outline when
//                                   the app or page changes), until stopped or for SECONDS
//   rc-screen notifications [--keep-open]  the notifications, a line each (opens Notification
//                                   Center for it and closes it after)
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
#import <poll.h>
#import "../RCSpawn.h"
#import <notify.h>

extern char **environ;

static Boolean (*AXSAutomationEnabled)(void);
static void (*AXSSetAutomationEnabled)(Boolean);
// Set while rc-screen has accessibility automation on. Any run that finds it turns automation
// back off when done, so a run that was killed (or overlapped another) can't leave it on.
static const char *kRCScreenMarker = "/tmp/rc-screen-automation";
// While a watcher runs (its pid in here), automation stays on whatever other runs do
static const char *kRCScreenWatching = "/tmp/rc-screen-watching";

static BOOL rc_watcher_running(void) {
    FILE *f = fopen(kRCScreenWatching, "r");
    if (!f) return NO;
    int pid = 0;
    BOOL ok = fscanf(f, "%d", &pid) == 1;
    fclose(f);
    return ok && pid > 0 && pid != getpid() && kill(pid, 0) == 0;
}

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
@property (nonatomic) BOOL web; // from a web page (rc_web_elements)
@end
@implementation RCScreenElement
@end

// --springboard: SpringBoard's own elements (banners, overlays) even with an app in front
static BOOL g_springboard = NO;

// The app in front, or SpringBoard (home screen, lock screen) when there's none
static id rc_primary_app(void) {
    Class AXElement = NSClassFromString(@"AXElement");
    if (g_springboard) return rc_call(AXElement, @"systemApplication");
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

// The watcher skips the web page walk (the slowest part of a read) when there's no page to walk
static BOOL g_skipWeb = NO;
// Whether the last read left out elements that aren't laid out yet (see rc_elements)
static BOOL g_unplaced = NO;

static NSString *rc_box(CGRect f) {
    return [NSString stringWithFormat:@"%.1f,%.1f,%.1f,%.1f", f.origin.x, f.origin.y, f.size.width, f.size.height];
}

static NSArray<RCScreenElement *> *rc_elements(id app) {
    NSMutableArray *list = [NSMutableArray array];
    NSUInteger number = 0;
    NSMutableArray *all = [NSMutableArray array];
    NSCountedSet *boxes = [NSCountedSet set];
    for (id element in rc_call(app, @"explorerElements")) {
        RCScreenElement *e = rc_element_from(element);
        [all addObject:e];
        [boxes addObject:rc_box(e.frame)];
    }
    // iOS 14 gives elements not laid out yet (further down a list) one made-up box: three or more
    // different elements in exactly the same box aren't on screen, so they're left out (and
    // scroll-to scrolls to them rather than "finding" them there)
    g_unplaced = NO;
    for (RCScreenElement *e in all) {
        if (!CGRectIsEmpty(e.frame) && [boxes countForObject:rc_box(e.frame)] >= 3) { g_unplaced = YES; continue; }
        e.number = ++number;
        [list addObject:e];
    }
    for (RCScreenElement *e in (g_skipWeb ? @[] : rc_web_elements(app))) {
        e.web = YES;
        e.number = ++number;
        [list addObject:e];
    }
    return list;
}

// The whole element tree: a list's children include rows that haven't scrolled in yet, with
// labels and virtual frames, so the target can often be found without scanning a screen at a
// time. Caps: a huge or lazy tree can't stall the run
static void rc_tree_walk(id node, int depth, NSMutableArray<RCScreenElement *> *out, int *budget, NSDate *until, BOOL *truncated) {
    if (!node || depth > 40) return;
    if (*budget <= 0 || [until timeIntervalSinceNow] <= 0) { *truncated = YES; return; }
    (*budget)--;
    [out addObject:rc_element_from(node)];
    for (id kid in rc_call(node, @"children")) rc_tree_walk(kid, depth + 1, out, budget, until, truncated);
}
static NSArray<RCScreenElement *> *rc_tree_elements(id app, BOOL *truncated) {
    NSMutableArray<RCScreenElement *> *out = [NSMutableArray array];
    int budget = 3000;
    *truncated = NO;
    rc_tree_walk(app, 0, out, &budget, [NSDate dateWithTimeIntervalSinceNow:3], truncated);
    return out;
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

// A change rc-screen made itself (press, type, set, adjust…) isn't a touch, so the tweak doesn't
// see it: tell a running watcher to look, as the tweak does for touches
static BOOL g_acted = NO;
static void rc_tell_watcher(void) {
    if (g_acted) notify_post("com.goldenappleguy.rc.screen-activity");
}

static void rc_restore(void) {
    rc_tell_watcher();
    if (access(kRCScreenMarker, F_OK) != 0 || !AXSSetAutomationEnabled) return;
    if (rc_watcher_running()) return; // the watcher needs it; it turns it off when it stops
    AXSSetAutomationEnabled(0);
    // The setting is saved by another process; wait until it reads back, or it's lost at exit
    for (int i = 0; i < 20 && AXSAutomationEnabled && AXSAutomationEnabled(); i++) usleep(25000);
    unlink(kRCScreenMarker);
}

// Stopped (Ctrl-C, a timeout): out at once. Cleaning up isn't safe inside a signal handler (it
// would call into accessibility and the allocator); the next rc-screen run finds the marker and
// turns accessibility automation back off
static void rc_quit(int sig) {
    _exit(130);
}

static int rc_usage(void) {
    fprintf(stderr, "Usage: rc-screen [--json|--outline] | find TEXT [--json] | press TEXT|#N | wait TEXT [SECONDS] | tap TEXT|#N | hold TEXT|#N [SECONDS] | menu TEXT|#N | type TEXT | scroll-to TEXT [up|left|right] | adjust TEXT|#N up|down [STEPS] | adjust TEXT|#N PERCENT%% | set TEXT|#N on|off | clear | pinch TEXT|#N SCALE | rotate TEXT|#N DEGREES | watch [SECONDS] [--every S] | notifications [--keep-open]\n");
    return 2;
}

// Runs an RC command (tap and hold go through the tweak, which makes the touch); 0 when it worked
static int rc_command(NSString *command) {
    NSString *client = rc_tool_path(@"rc-client");
    if (!client) {
        fprintf(stderr, "Error: rc-client isn't installed\n");
        return 2;
    }
    NSString *text = nil;
    int code = rc_run_tool(client, @[command], 60, &text);
    if (code != 0 || [text hasPrefix:@"Error"] || [text hasPrefix:@"Stopped"]) {
        fprintf(stderr, "%s\n", text.length ? text.UTF8String : (code == -1 ? "Error: RemoteCompanion didn't answer" : "Error"));
        return 2;
    }
    return 0;
}

#pragma mark - Outline

// The screen as an outline an assistant can read at a glance: what's in the way first (an alert,
// the keyboard), then the top bar, the content by section, with side-by-side elements on one
// row, and the bottom bar. Elements keep their #N for press/tap/set. No positions: actions go by
// #N or text.

static NSString *rc_ol_text(RCScreenElement *e) {
    NSString *label = e.label.length ? e.label : @"";
    if ([e.kind isEqualToString:@"switch"]) {
        NSString *state = [e.value isEqualToString:@"1"] ? @"on" : [e.value isEqualToString:@"0"] ? @"off" : e.value;
        return label.length ? [NSString stringWithFormat:@"%@: %@", label, state] : [NSString stringWithFormat:@"switch: %@", state];
    }
    if ([e.kind isEqualToString:@"adjustable"]) {
        NSString *value = e.value.length ? e.value : @"?";
        return label.length ? [NSString stringWithFormat:@"%@: %@ (adjustable)", label, value] : [NSString stringWithFormat:@"%@ (adjustable)", value];
    }
    if ([e.kind isEqualToString:@"search"] || (e.traits & 0x40000)) return [NSString stringWithFormat:@"<%@%@>", label.length ? label : @"field", e.value.length && ![e.value isEqualToString:label] ? [NSString stringWithFormat:@": %@", e.value] : @""];
    if ([e.kind isEqualToString:@"button"] || [e.kind isEqualToString:@"link"] || [e.kind isEqualToString:@"key"]) {
        NSString *inner = label.length ? label : @"unlabeled";
        if (e.value.length) inner = [inner stringByAppendingFormat:@" › %@", e.value];
        return [e.kind isEqualToString:@"link"] ? [NSString stringWithFormat:@"[%@](link)", inner] : [NSString stringWithFormat:@"[%@]", inner];
    }
    if ([e.kind isEqualToString:@"image"]) return [NSString stringWithFormat:@"(image%@)", label.length ? [@" " stringByAppendingString:label] : @""];
    if (e.value.length && label.length) return [NSString stringWithFormat:@"%@: %@", label, e.value];
    return label.length ? label : e.value;
}

static NSString *rc_ol_item(RCScreenElement *e) {
    NSMutableString *s = [NSMutableString stringWithString:rc_ol_text(e)];
    if (e.traits & 0x100) [s appendString:@" (dimmed)"];
    if (e.traits & 0x8) [s appendString:@" ✓"];
    [s appendFormat:@" #%lu", (unsigned long)e.number];
    return s;
}

static BOOL rc_ol_shown(RCScreenElement *e) {
    if (CGRectIsEmpty(e.frame)) return NO;
    // Unlabeled plain elements are layout, not content
    if (!e.label.length && !e.value.length && ([e.kind isEqualToString:@"element"] || [e.kind isEqualToString:@"text"])) return NO;
    return YES;
}

// A switch is listed twice (its row, then the switch itself); a link's text often again as text
static NSArray<RCScreenElement *> *rc_ol_merge(NSArray<RCScreenElement *> *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (RCScreenElement *e in list) {
        RCScreenElement *last = out.lastObject;
        if (last && [last.label isEqualToString:e.label] && [last.value isEqualToString:e.value] && (CGRectContainsRect(last.frame, e.frame) || CGRectContainsRect(e.frame, last.frame))) {
            // Keep the one to act on (the switch, the button), with its number, laid out as the
            // whole row (the switch alone is small, and would look like a bar button)
            BOOL eActs = (e.traits & 0x1) != 0, lastActs = (last.traits & 0x1) != 0;
            CGRect row = CGRectUnion(last.frame, e.frame);
            RCScreenElement *keep = (eActs && !lastActs) ? e : last;
            keep.frame = row;
            [out replaceObjectAtIndex:out.count - 1 withObject:keep];
            continue;
        }
        [out addObject:e];
    }
    return out;
}

// Rows: elements whose vertical middles fall within each other's height, left to right
static NSArray<NSArray<RCScreenElement *> *> *rc_ol_rows(NSArray<RCScreenElement *> *list) {
    NSArray *sorted = [list sortedArrayUsingComparator:^NSComparisonResult(RCScreenElement *a, RCScreenElement *b) {
        if (CGRectGetMidY(a.frame) == CGRectGetMidY(b.frame)) return CGRectGetMinX(a.frame) < CGRectGetMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending;
        return CGRectGetMidY(a.frame) < CGRectGetMidY(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray *rows = [NSMutableArray array];
    for (RCScreenElement *e in sorted) {
        NSMutableArray *row = rows.lastObject;
        RCScreenElement *first = row.firstObject;
        double band = MIN(first.frame.size.height, e.frame.size.height) / 2;
        if (row && fabs(CGRectGetMidY(first.frame) - CGRectGetMidY(e.frame)) <= MAX(band, 4)) [row addObject:e];
        else [rows addObject:[NSMutableArray arrayWithObject:e]];
    }
    for (NSMutableArray *row in rows) [row sortUsingComparator:^NSComparisonResult(RCScreenElement *a, RCScreenElement *b) {
        return CGRectGetMinX(a.frame) < CGRectGetMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];
    return rows;
}

static NSString *rc_ol_row(NSArray<RCScreenElement *> *row) {
    NSMutableArray *items = [NSMutableArray array];
    for (RCScreenElement *e in row) [items addObject:rc_ol_item(e)];
    return [items componentsJoinedByString:@"   "];
}

// Web text reads as paragraphs: runs of text and links on the page, links marked where they are
static NSArray<NSString *> *rc_ol_web(NSArray<RCScreenElement *> *list) {
    NSMutableArray *lines = [NSMutableArray array];
    NSMutableString *para = nil;
    CGFloat lastBottom = -1000;
    for (RCScreenElement *e in list) {
        BOOL flows = [e.kind isEqualToString:@"text"] || [e.kind isEqualToString:@"link"] || [e.kind isEqualToString:@"element"];
        BOOL near = CGRectGetMinY(e.frame) - lastBottom < 30;
        if (flows && para && near) {
            [para appendFormat:@" %@", [e.kind isEqualToString:@"link"] ? rc_ol_item(e) : (e.label.length ? e.label : e.value)];
        } else {
            if (para) [lines addObject:para];
            para = nil;
            if ([e.kind isEqualToString:@"header"]) [lines addObject:[NSString stringWithFormat:@"## %@ #%lu", e.label, (unsigned long)e.number]];
            else if (flows) para = [NSMutableString stringWithString:[e.kind isEqualToString:@"link"] ? rc_ol_item(e) : (e.label.length ? e.label : e.value)];
            else [lines addObject:rc_ol_item(e)];
        }
        lastBottom = MAX(lastBottom, CGRectGetMaxY(e.frame));
        if (!near) lastBottom = CGRectGetMaxY(e.frame);
    }
    if (para) [lines addObject:para];
    return lines;
}

static NSString *rc_outline(id app, NSString *appName, NSString *bundleID, NSArray<RCScreenElement *> *all) {
    CGRect screen = rc_frame(app);
    if (CGRectIsEmpty(screen)) screen = CGRectMake(0, 0, 390, 844);
    double h = screen.size.height, top = screen.origin.y + h * 0.12, bottom = screen.origin.y + h * 0.86;
    NSMutableArray<NSString *> *out = [NSMutableArray array];

    NSMutableArray<RCScreenElement *> *keys = [NSMutableArray array], *web = [NSMutableArray array], *native = [NSMutableArray array];
    // A keyboard (26 keys or more) is one line; a keypad (a phone's, a PIN pad) is laid out
    NSUInteger keyCount = 0;
    for (RCScreenElement *e in all) if ([e.kind isEqualToString:@"key"]) keyCount++;
    BOOL keyboard = keyCount >= 20;
    for (RCScreenElement *e in all) {
        if (keyboard && [e.kind isEqualToString:@"key"]) [keys addObject:e];
        else if (!rc_ol_shown(e)) continue;
        else if (e.web) [web addObject:e];
        else [native addObject:e];
    }
    native = [rc_ol_merge(native) mutableCopy];
    BOOL unplaced = g_unplaced;

    // The page title: the top bar's header, or a large header near the top
    NSString *title = nil;
    for (RCScreenElement *e in native) {
        if ([e.kind isEqualToString:@"header"] && CGRectGetMidY(e.frame) < screen.origin.y + h * 0.2) { title = e.label; break; }
    }
    NSMutableString *head = [NSMutableString stringWithString:appName];
    if (title.length && ![title isEqualToString:appName]) [head appendFormat:@" › %@", title];
    if (bundleID.length) [head appendFormat:@"   [%@]", bundleID];
    [out addObject:head];

    // What's in the way: a modal view (alert, sheet) is all that can be used
    SEL modalSel = NSSelectorFromString(@"applicationIsModal");
    BOOL modal = [app respondsToSelector:modalSel] && ((BOOL (*)(id, SEL))objc_msgSend)(app, modalSel);
    // An alert hides everything else from accessibility, leaving one box centered on the screen,
    // narrower than it, with a button
    if (!modal && native.count && native.count <= 14) {
        CGRect box = CGRectNull;
        BOOL button = NO;
        for (RCScreenElement *e in native) { box = CGRectUnion(box, e.frame); if (e.traits & 0x1) button = YES; }
        modal = button && box.size.width < screen.size.width * 0.8 && box.size.height < h * 0.7 &&
                fabs(CGRectGetMidX(box) - CGRectGetMidX(screen)) < 24;
    }
    if (modal) {
        NSMutableArray *texts = [NSMutableArray array], *controls = [NSMutableArray array];
        for (RCScreenElement *e in native) {
            if ([e.kind isEqualToString:@"text"] && e.label.length) [texts addObject:e.label];
            else [controls addObject:rc_ol_item(e)];
        }
        [out addObject:[NSString stringWithFormat:@"ALERT%@: %@", texts.count ? [NSString stringWithFormat:@" “%@”", texts.firstObject] : @"",
                        [[(texts.count > 1 ? @[[[texts subarrayWithRange:NSMakeRange(1, texts.count - 1)] componentsJoinedByString:@" "]] : @[]) arrayByAddingObjectsFromArray:controls] componentsJoinedByString:@"   "]]];
    }
    if (keys.count) {
        NSString *ret = nil;
        for (RCScreenElement *k in keys) {
            if ([@[@"return", @"search", @"go", @"done", @"send", @"next", @"join", @"route", @"continue"] containsObject:k.label.lowercaseString]) ret = k.label;
        }
        [out addObject:[NSString stringWithFormat:@"keyboard: up%@ (press its keys by name, or type)", ret ? [NSString stringWithFormat:@", return key “%@”", ret] : @""]];
    }
    if (modal) return [out componentsJoinedByString:@"\n"];

    // Bars: rows wholly at the top or bottom that aren't list rows (a list row is nearly as wide
    // as the screen and alone on its line); a tab bar or toolbar has several items side by side
    NSMutableArray *topBar = [NSMutableArray array], *bottomBar = [NSMutableArray array], *content = [NSMutableArray array];
    BOOL above = NO, below = NO;
    for (RCScreenElement *e in native) {
        if (CGRectGetMaxY(e.frame) > CGRectGetMaxY(screen) + 1) below = YES;
        if (CGRectGetMinY(e.frame) < screen.origin.y - 1) above = YES;
    }
    for (NSArray<RCScreenElement *> *row in rc_ol_rows(native)) {
        // A list row (nearly screen-wide) and what sits on it (an info button) stay content, even
        // under a see-through bar; the rest of a band at the very top or bottom is a bar
        NSMutableArray<RCScreenElement *> *wide = [NSMutableArray array], *rest = [NSMutableArray array];
        for (RCScreenElement *e in row) {
            if (e.frame.size.width > screen.size.width * 0.85) [wide addObject:e];
            else [rest addObject:e];
        }
        // One small control on a list row is its accessory (an info button, a switch); three or
        // more side by side are a bar. A header or text isn't an accessory: under a see-through
        // bar it's the bar's title over a row scrolled beneath it
        if (wide.count && rest.count < 3) {
            NSSet *controls = [NSSet setWithArray:@[@"button", @"switch", @"link", @"adjustable", @"key"]];
            for (RCScreenElement *e in [rest copy]) {
                if (![controls containsObject:e.kind]) continue;
                for (RCScreenElement *w in [wide copy]) {
                    if (CGRectIntersectsRect(w.frame, e.frame)) { [wide addObject:e]; [rest removeObject:e]; break; }
                }
            }
        }
        // By the band's middle, so a bar a little taller than the edge region still counts
        double mid = 0, tallest = 0;
        for (RCScreenElement *e in rest) { mid += CGRectGetMidY(e.frame); tallest = MAX(tallest, e.frame.size.height); }
        if (rest.count) mid /= rest.count;
        [content addObjectsFromArray:wide];
        if (rest.count && mid <= top && tallest < h * 0.12) [topBar addObjectsFromArray:rest];
        else if (rest.count && mid >= bottom && tallest < h * 0.12) [bottomBar addObjectsFromArray:rest];
        else [content addObjectsFromArray:rest];
    }
    for (RCScreenElement *e in web) if (CGRectGetMaxY(e.frame) > CGRectGetMaxY(screen) + 1) below = YES;
    if (unplaced) below = YES;

    for (NSArray *row in rc_ol_rows(topBar)) [out addObject:[@"top: " stringByAppendingString:rc_ol_row(row)]];
    if (above) [out addObject:@"↑ more above"];
    for (NSArray<RCScreenElement *> *row in rc_ol_rows(content)) {
        if (row.count == 1 && [row[0].kind isEqualToString:@"header"]) {
            if ([row[0].label isEqualToString:title]) continue; // already the page title
            [out addObject:[NSString stringWithFormat:@"## %@", row[0].label]];
        } else {
            [out addObject:[@"  " stringByAppendingString:rc_ol_row(row)]];
        }
    }
    if (web.count) {
        [out addObject:@"web page:"];
        for (NSString *line in rc_ol_web(web)) [out addObject:[@"  " stringByAppendingString:line]];
    }
    if (below) [out addObject:@"↓ more below"];
    for (NSArray *row in rc_ol_rows(bottomBar)) [out addObject:[@"bottom: " stringByAppendingString:rc_ol_row(row)]];
    // A big area with nothing readable (a map, a game, a camera, a canvas)
    for (RCScreenElement *e in all) {
        if (!e.label.length && !e.value.length && e.frame.size.width * e.frame.size.height > screen.size.width * h * 0.35 && ![e.kind isEqualToString:@"key"]) {
            // A container with readable things in it (a web view, a list) isn't opaque
            NSUInteger inside = 0;
            for (RCScreenElement *o in all) {
                if (o != e && (o.label.length || o.value.length) && CGRectContainsPoint(e.frame, CGPointMake(CGRectGetMidX(o.frame), CGRectGetMidY(o.frame)))) inside++;
            }
            if (inside >= 3) continue;
            [out addObject:[NSString stringWithFormat:@"(an area of %.0fx%.0f with nothing readable at %.0f,%.0f: a map, game or canvas? Use touches there, or a screenshot)",
                            e.frame.size.width, e.frame.size.height, CGRectGetMidX(e.frame), CGRectGetMidY(e.frame)]];
            break;
        }
    }
    return [out componentsJoinedByString:@"\n"];
}

#pragma mark - Notifications

// The notifications in Notification Center (or on the lock screen), a line each: app, when,
// title and text, as iOS reads them out. Opens Notification Center if it isn't showing, and
// closes it again after, unless keepOpen.
static double g_screenWidth = 390;

static BOOL rc_notification_item(RCScreenElement *e) {
    if (![e.kind isEqualToString:@"button"] || ![e.label containsString:@", "]) return NO;
    if ([e.label hasPrefix:@"Clear"] || [e.value isEqualToString:@"Notification Center"]) return NO;
    // A notification is a card nearly as wide as the screen (widgets and buttons are narrower), or
    // reads "APP, when, …" with the app's name in capitals; its label starts with when it came
    // ("20 minutes ago, …") or the app, depending on where iOS lists it
    if (e.frame.size.width > g_screenWidth * 0.85) return YES;
    NSString *first = [e.label componentsSeparatedByString:@", "].firstObject;
    return first.length > 1 && [first isEqualToString:first.uppercaseString] && ![first isEqualToString:first.lowercaseString];
}

// Notification Center shows in SpringBoard's own elements on iOS 17 (with an app in front), and
// in the front app's reading on iOS 14: whichever has it
static NSArray<RCScreenElement *> *rc_notification_elements(void) {
    BOOL was = g_springboard;
    NSArray<RCScreenElement *> *best = @[];
    for (int pass = 0; pass < 2; pass++) {
        g_springboard = pass == 0;
        id app = rc_primary_app();
        if (pass == 1) {
            // Only while SpringBoard itself is in front: an app's own wide rows (Settings' Apple
            // ID row) aren't notifications
            SEL systemSel = NSSelectorFromString(@"isSystemApplication");
            BOOL system = [app respondsToSelector:systemSel] && ((BOOL (*)(id, SEL))objc_msgSend)(app, systemSel);
            if (!system && rc_text(rc_call(app, @"label")).length) break;
        }
        CGRect screen = rc_frame(app);
        if (!CGRectIsEmpty(screen)) g_screenWidth = screen.size.width;
        NSArray<RCScreenElement *> *list = rc_elements(app);
        for (RCScreenElement *e in list) {
            if (rc_notification_item(e) || ([e.kind isEqualToString:@"header"] && [e.label isEqualToString:@"Notification Center"])) { best = list; break; }
        }
        if (best.count) break;
    }
    g_springboard = was;
    return best;
}

static NSArray<RCScreenElement *> *rc_notifications_now(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (RCScreenElement *e in rc_notification_elements()) if (rc_notification_item(e)) [out addObject:e];
    return out;
}

static BOOL rc_notification_center_open(void) {
    for (RCScreenElement *e in rc_notification_elements()) {
        if ([e.kind isEqualToString:@"header"] && [e.label isEqualToString:@"Notification Center"]) return YES;
    }
    return NO;
}

static int rc_command(NSString *command);

static int rc_notifications(BOOL json, BOOL keepOpen) {
    id app = rc_primary_app();
    CGRect screen = rc_frame(app);
    if (CGRectIsEmpty(screen)) screen = CGRectMake(0, 0, 390, 844);
    BOOL opened = NO;
    if (!rc_notification_center_open() && rc_notifications_now().count == 0) {
        // Down from the top edge, left of the middle (the right side is Control Center)
        double x = screen.origin.x + screen.size.width * 0.2;
        if (rc_command([NSString stringWithFormat:@"gesture swipe %.0f 0 %.0f %.0f 0.4", x, x, screen.size.height * 0.7]) != 0) return 2;
        opened = YES;
        // Open once its header or its first card shows
        for (int i = 0; i < 15 && !rc_notification_center_open() && rc_notifications_now().count == 0; i++) [NSThread sleepForTimeInterval:0.2];
        [NSThread sleepForTimeInterval:0.3];
    }
    NSArray<RCScreenElement *> *items = rc_notifications_now();
    if (json) {
        NSMutableArray *list = [NSMutableArray array];
        for (RCScreenElement *e in items) {
            NSArray *parts = [e.label componentsSeparatedByString:@", "];
            [list addObject:@{ @"number": @(e.number), @"app": parts.firstObject ?: @"", @"when": parts.count > 1 ? parts[1] : @"",
                               @"text": parts.count > 2 ? [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@", "] : @"" }];
        }
        rc_print_json(list);
    } else if (!items.count) {
        printf("No notifications\n");
    } else {
        for (RCScreenElement *e in items) printf("#%lu %s\n", (unsigned long)e.number, e.label.UTF8String);
    }
    if (opened && !keepOpen) {
        // Up from the bottom edge closes it
        rc_command([NSString stringWithFormat:@"gesture swipe %.0f %.0f %.0f %.0f 0.25", CGRectGetMidX(screen), CGRectGetMaxY(screen), CGRectGetMidX(screen), screen.size.height * 0.45]);
        // Back where it was before returning, so the next read sees the app again
        for (int i = 0; i < 15 && (rc_notification_center_open() || rc_notifications_now().count); i++) [NSThread sleepForTimeInterval:0.15];
        [NSThread sleepForTimeInterval:0.4];
    }
    return 0;
}

#pragma mark - Watch

// rc-screen watch: a running log of what changes on the screen, a line per change once the screen
// has settled, and the whole outline when the app or page changes. For assistants that follow
// the phone as it goes, and for logs.

@interface RCWatchState : NSObject
@property (nonatomic, copy) NSString *outline;
@property (nonatomic, copy) NSString *head;     // the outline's first line: app, page, bundle
@property (nonatomic, copy) NSString *bundle;
@property (nonatomic, copy) NSString *alert;    // the ALERT line, if any
@property (nonatomic) BOOL keyboard;
@property (nonatomic, copy) NSString *headers;  // the page's section headers, joined
@property (nonatomic, strong) NSDictionary<NSString *, RCScreenElement *> *items; // by kind|label
@property (nonatomic, strong) NSArray<NSString *> *order; // item keys, top to bottom
@end
@implementation RCWatchState
@end

static RCWatchState *rc_watch_state(void) {
    id app = rc_primary_app();
    NSString *appName = rc_text(rc_call(app, @"label"));
    SEL systemSel = NSSelectorFromString(@"isSystemApplication");
    BOOL system = [app respondsToSelector:systemSel] && ((BOOL (*)(id, SEL))objc_msgSend)(app, systemSel);
    if (system || !appName.length) appName = @"SpringBoard";
    NSString *bundle = rc_text(rc_call(app, @"bundleId"));
    if (!bundle.length && [appName isEqualToString:@"SpringBoard"]) bundle = @"com.apple.springboard";
    NSArray<RCScreenElement *> *list = rc_elements(app);
    RCWatchState *st = [RCWatchState new];
    st.outline = rc_outline(app, appName, bundle, list);
    st.bundle = bundle;
    NSArray *lines = [st.outline componentsSeparatedByString:@"\n"];
    st.head = lines.firstObject ?: appName;
    NSMutableArray *headers = [NSMutableArray array];
    for (NSString *line in lines) {
        if ([line hasPrefix:@"ALERT"]) st.alert = line;
        if ([line hasPrefix:@"keyboard:"]) st.keyboard = YES;
        if ([line hasPrefix:@"## "]) [headers addObject:line];
    }
    st.headers = [headers componentsJoinedByString:@"|"];
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    NSMutableArray *order = [NSMutableArray array];
    for (RCScreenElement *e in list) {
        if ([e.kind isEqualToString:@"key"] || !rc_ol_shown(e)) continue;
        // A search field reads as its placeholder while empty: the same field either way
        BOOL field = [e.kind isEqualToString:@"search"] || (e.traits & 0x40000);
        NSString *key = [NSString stringWithFormat:@"%@|%@", e.kind, field && !e.label.length ? e.value : e.label];
        if (items[key]) continue;
        items[key] = e;
        [order addObject:key];
    }
    st.items = items;
    st.order = order;
    return st;
}

static void rc_watch_say(NSString *line) {
    static NSDateFormatter *clock;
    if (!clock) {
        clock = [NSDateFormatter new];
        clock.dateFormat = @"HH:mm:ss";
    }
    printf("%s %s\n", [clock stringFromDate:[NSDate date]].UTF8String, line.UTF8String);
    fflush(stdout);
}

static void rc_watch_outline(RCWatchState *st) {
    for (NSString *line in [st.outline componentsSeparatedByString:@"\n"]) printf("    %s\n", line.UTF8String);
    fflush(stdout);
}

// What changed from `was` to `now`, as lines
static void rc_watch_report(RCWatchState *was, RCWatchState *now) {
    if (!was || ![was.bundle isEqualToString:now.bundle]) {
        rc_watch_say([@"app → " stringByAppendingString:now.head]);
        rc_watch_outline(now);
        return;
    }
    if (![was.head isEqualToString:now.head] || ![was.headers isEqualToString:now.headers]) {
        // The same page scrolled keeps its title; new section headers alone are a scroll
        BOOL titleChanged = ![was.head isEqualToString:now.head];
        NSUInteger shared = 0;
        for (NSString *key in now.order) if (was.items[key]) shared++;
        if (titleChanged || shared * 3 < MIN(was.order.count, now.order.count)) {
            rc_watch_say([@"page → " stringByAppendingString:now.head]);
            rc_watch_outline(now);
            return;
        }
    }
    if (!was.alert && now.alert) rc_watch_say(now.alert);
    else if (was.alert && !now.alert) rc_watch_say(@"alert gone");
    else if (was.alert && now.alert && ![was.alert isEqualToString:now.alert]) rc_watch_say(now.alert);
    if (!was.keyboard && now.keyboard) rc_watch_say(@"keyboard up");
    if (was.keyboard && !now.keyboard) rc_watch_say(@"keyboard down");
    // Values that changed (a switch, a slider, a field, a row's detail)
    for (NSString *key in now.order) {
        RCScreenElement *a = was.items[key], *b = now.items[key];
        if (a && ![a.value isEqualToString:b.value]) {
            // "Lock Sound: on → off": the label once, then the old and new value as the outline writes them
            NSString *from = rc_ol_text(a), *to = rc_ol_text(b), *prefix = [b.label stringByAppendingString:@": "];
            if (b.label.length && [from hasPrefix:prefix] && [to hasPrefix:prefix]) {
                rc_watch_say([NSString stringWithFormat:@"#%lu %@%@ \u2192 %@", (unsigned long)b.number, prefix,
                              [from substringFromIndex:prefix.length], [to substringFromIndex:prefix.length]]);
            } else {
                rc_watch_say([NSString stringWithFormat:@"#%lu %@ \u2192 %@", (unsigned long)b.number, from, to]);
            }
        }
    }
    NSMutableArray *added = [NSMutableArray array], *gone = [NSMutableArray array];
    for (NSString *key in now.order) if (!was.items[key]) [added addObject:now.items[key]];
    for (NSString *key in was.order) if (!now.items[key]) [gone addObject:was.items[key]];
    // The same kind of element in the same place with new text (a timer, a counter) changed,
    // rather than one going and another coming
    for (RCScreenElement *b in [added copy]) {
        for (RCScreenElement *a in [gone copy]) {
            if (![a.kind isEqualToString:b.kind] || fabs(CGRectGetMidX(a.frame) - CGRectGetMidX(b.frame)) > 4 ||
                fabs(CGRectGetMidY(a.frame) - CGRectGetMidY(b.frame)) > 4) continue;
            rc_watch_say([NSString stringWithFormat:@"#%lu %@ \u2192 %@", (unsigned long)b.number, rc_ol_text(a), rc_ol_text(b)]);
            [added removeObject:b];
            [gone removeObject:a];
            break;
        }
    }
    if (added.count + gone.count == 0) return;
    if (added.count + gone.count <= 6) {
        for (RCScreenElement *e in added) rc_watch_say([@"+ " stringByAppendingString:rc_ol_item(e)]);
        for (RCScreenElement *e in gone) rc_watch_say([@"- " stringByAppendingString:rc_ol_text(e)]);
    } else {
        // Most often a scroll: say what's showing now
        RCScreenElement *first = now.items[now.order.firstObject], *last = now.items[now.order.lastObject];
        rc_watch_say([NSString stringWithFormat:@"content changed: +%lu −%lu (now “%@” … “%@”)",
                      (unsigned long)added.count, (unsigned long)gone.count, rc_ol_text(first), rc_ol_text(last)]);
    }
}

// Wakes the watcher: RemoteCompanion's tweak posts this on a touch, a button or an app coming
// to the front; iOS posts the other when the screen goes dark or lights up
static const char *kRCActivity = "com.goldenappleguy.rc.screen-activity";
static const char *kRCBlanked = "com.apple.springboard.hasBlankedScreen";

static int rc_watch(double interval, double duration) {
    NSDate *until = duration > 0 ? [NSDate dateWithTimeIntervalSinceNow:duration] : nil;
    RCWatchState *shown = nil;  // what was last reported
    NSString *last = nil;       // the previous read, to know when the screen has settled
    // Reads follow activity, not a clock: after a touch, a button or an app switch, a short burst
    // (until the screen settles, at least 2.5 s); then one every 15 s for changes nobody caused.
    // Nothing while the screen is dark.
    dispatch_semaphore_t wake = dispatch_semaphore_create(0);
    __block volatile double activityAt = CFAbsoluteTimeGetCurrent();
    int activityToken = 0, blankToken = 0;
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    notify_register_dispatch(kRCActivity, &activityToken, q, ^(int t) { activityAt = CFAbsoluteTimeGetCurrent(); dispatch_semaphore_signal(wake); });
    notify_register_dispatch(kRCBlanked, &blankToken, q, ^(int t) { activityAt = CFAbsoluteTimeGetCurrent(); dispatch_semaphore_signal(wake); });
    // Stopped (Ctrl-C, kill, the terminal closing): finish the current read and leave the usual
    // way, so accessibility automation goes back off; a second signal leaves at once
    __block volatile BOOL stop = NO;
    NSMutableArray *signalSources = [NSMutableArray array];
    const int signals[] = { SIGINT, SIGTERM, SIGHUP };
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
        int sig = signals[i];
        signal(sig, SIG_IGN);
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, (uintptr_t)sig, 0, q);
        dispatch_source_set_event_handler(source, ^{
            if (stop) _exit(130);
            stop = YES;
            dispatch_semaphore_signal(wake);
        });
        dispatch_resume(source);
        [signalSources addObject:source];
    }
    int reads = 0;
    BOOL webSeen = YES, settled = NO;
    double lastRead = 0;
    // A screen that never settles (a stopwatch, a video's time, an animation) is reported as it
    // is after 5 s, and read every 3 s while it keeps changing
    double unsettledSince = 0;
    rc_watch_say(@"watching (a line per change; the outline when the app or page changes)");
    FILE *mark = fopen(kRCScreenWatching, "w");
    if (mark) { fprintf(mark, "%d\n", getpid()); fclose(mark); }
    while (!stop && (!until || [until timeIntervalSinceNow] > 0)) {
        // Whoever was reading is gone (an SSH session that ends without a terminal sends no
        // hangup, and with a shared connection the parent lives on): stop, so accessibility
        // automation goes back off
        struct pollfd out = { .fd = STDOUT_FILENO, .events = 0 };
        if (getppid() == 1 || ferror(stdout) || (poll(&out, 1, 0) > 0 && (out.revents & (POLLHUP | POLLERR | POLLNVAL)))) break;
        uint64_t blanked = 0;
        notify_get_state(blankToken, &blanked);
        double now = CFAbsoluteTimeGetCurrent();
        BOOL busy = !settled || now - activityAt < 2.5;
        if (blanked) {
            // Dark: no reads; wake for the screen lighting up (or every 5 s to see if the reader left)
            dispatch_semaphore_wait(wake, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
            continue;
        }
        if (!busy && now - lastRead < 15) {
            double left = MIN(15 - (now - lastRead), 5); // 5 s at most, to notice the reader leaving
            dispatch_semaphore_wait(wake, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(left * NSEC_PER_SEC)));
            continue;
        }
        // On, in case something switched it off (apps opened meanwhile only answer while it's on);
        // every 10 s, since this process's own reading of the setting can be out of date
        static double lastOn = 0;
        if (AXSSetAutomationEnabled && now - lastOn > 10) {
            close(open(kRCScreenMarker, O_CREAT | O_WRONLY, 0666));
            AXSSetAutomationEnabled(1);
            lastOn = now;
        }
        @autoreleasepool {
            // The page walk only when a page was there last time, or every 5th read to find a new one
            g_skipWeb = !webSeen && reads % 5 != 0;
            reads++;
            RCWatchState *nowState = rc_watch_state();
            lastRead = CFAbsoluteTimeGetCurrent();
            if (!g_skipWeb) webSeen = [nowState.outline rangeOfString:@"\nweb page:"].location != NSNotFound;
            settled = [nowState.outline isEqualToString:last];
            if (settled) unsettledSince = 0;
            else if (!unsettledSince) unsettledSince = lastRead;
            BOOL restless = unsettledSince && lastRead - unsettledSince > 5;
            if ((settled || restless) && ![nowState.outline isEqualToString:shown.outline]) {
                rc_watch_report(shown, nowState);
                shown = nowState;
            }
            last = nowState.outline;
        }
        double since = CFAbsoluteTimeGetCurrent();
        if (unsettledSince && since - unsettledSince > 5 && since - activityAt > 2.5) {
            // Still changing on its own: every 3 s (a touch makes it quick again)
            dispatch_semaphore_wait(wake, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
        } else if (!settled || since - activityAt < 2.5) {
            [NSThread sleepForTimeInterval:interval];
        }
    }
    for (dispatch_source_t source in signalSources) dispatch_source_cancel(source);
    notify_cancel(activityToken);
    notify_cancel(blankToken);
    unlink(kRCScreenWatching);
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        // Piped into head, or stopped with Ctrl-C: still clean up (rc_restore runs at exit)
        signal(SIGPIPE, SIG_IGN);
        signal(SIGINT, rc_quit);
        signal(SIGTERM, rc_quit);
        NSMutableArray<NSString *> *args = [NSMutableArray array];
        BOOL json = NO, replace = NO, outline = NO;
        for (int i = 1; i < argc; i++) {
            NSString *a = @(argv[i]);
            if ([a isEqualToString:@"--json"]) json = YES;
            else if ([a isEqualToString:@"--replace"]) replace = YES;
            else if ([a isEqualToString:@"--outline"]) outline = YES;
            else if ([a isEqualToString:@"--springboard"]) g_springboard = YES;
            else if ([a isEqualToString:@"-h"] || [a isEqualToString:@"--help"]) return rc_usage();
            else [args addObject:a];
        }
        NSString *verb = args.count ? args[0] : @"list";
        g_acted = [@[@"press", @"tap", @"hold", @"menu", @"type", @"clear", @"set", @"adjust", @"scroll-to", @"pinch", @"rotate"] containsObject:verb];
        if (![@[@"list", @"find", @"press", @"wait", @"tap", @"hold", @"menu", @"type", @"scroll-to", @"adjust", @"set", @"clear", @"pinch", @"rotate", @"watch", @"notifications"] containsObject:verb]) return rc_usage();
        if (![verb isEqualToString:@"list"] && ![verb isEqualToString:@"clear"] && ![verb isEqualToString:@"watch"] && ![verb isEqualToString:@"notifications"] && args.count < 2) return rc_usage();

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

        if ([verb isEqualToString:@"notifications"]) {
            g_springboard = YES; // Notification Center is SpringBoard's, whatever app is in front
            return rc_notifications(json, [args containsObject:@"--keep-open"]);
        }
        if ([verb isEqualToString:@"watch"]) {
            // watch [SECONDS] [--every SECONDS]: forever (until stopped) or for SECONDS
            double duration = args.count > 1 ? [args[1] doubleValue] : 0, interval = 0.5;
            NSUInteger every = [args indexOfObject:@"--every"];
            if (every != NSNotFound && every + 1 < args.count) interval = MIN(MAX([args[every + 1] doubleValue], 0.2), 10);
            return rc_watch(interval, duration);
        }

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
            // Finds the text by pulling the list, gently enough not to overshoot. The element
            // tree usually knows the off-screen rows, so the target can be steered to directly;
            // lists that don't expose them get a scan that steps and checks each screen
            NSString *text = args[1];
            // Which way to look: down (the default), up, left or right; "down" brings in what's below
            NSString *way = args.count > 2 ? args[2].lowercaseString : @"down";
            if (![@[@"down", @"up", @"left", @"right"] containsObject:way]) return rc_usage();
            BOOL sideways = [way isEqualToString:@"left"] || [way isEqualToString:@"right"];
            BOOL down = [way isEqualToString:@"down"] || [way isEqualToString:@"right"]; // toward the end
            CGRect screen = rc_frame(app);
            if (CGRectIsEmpty(screen)) screen = CGRectMake(0, 0, 390, 844);
            double x = CGRectGetMidX(screen), y = CGRectGetMidY(screen);
            NSArray<RCScreenElement *> *list = rc_settled_elements(2);
            // Reads during the search can skip the web hit-tests when there's no web content
            BOOL anyWeb = NO;
            for (RCScreenElement *e in list) if (e.web) { anyWeb = YES; break; }
            if (!anyWeb) g_skipWeb = YES;
            int turns = 0, swipes = 0;
            NSString *mention = nil; // text that only mentions it, kept scrolling past
            NSSet *acting = [NSSet setWithArray:@[@"button", @"link", @"switch", @"key", @"search", @"adjustable"]];
            double band = (sideways ? screen.size.width : screen.size.height) * 0.14;
            // Only an exact label or something to act on counts as found
            RCScreenElement *found = nil;
            NSString *match = rc_text(text);
            RCScreenElement *(^pick)(NSArray<RCScreenElement *> *) = ^RCScreenElement *(NSArray<RCScreenElement *> *cands) {
                RCScreenElement *f = rc_pick(cands, text);
                if (f && [f.label compare:match options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch] != NSOrderedSame && ![acting containsObject:f.kind]) return nil;
                return f;
            };

            // Steer: the target may already be in the tree off screen, and the walk says which
            // way it is (frames between walks update too slowly to track mid-search). Then
            // it's a directed scan: 60% drags that way, the same gap guard as the scan, until
            // the target shows on screen
            {
                BOOL truncated = NO;
                NSArray<RCScreenElement *> *tree = rc_tree_elements(app, &truncated);
                RCScreenElement *hit = pick(tree);
                // An untruncated walk that puts at least 20 labeled rows past the edge the
                // search looks toward and still has no match settles it without a scan; a
                // sparse or cut-off tree (lazy lists, web pages) falls through to the scan
                if (!hit && !truncated) {
                    NSUInteger off = 0;
                    for (RCScreenElement *e in tree) {
                        CGRect f = e.frame;
                        if (!e.label.length || CGRectIsEmpty(f)) continue;
                        BOOL offDir = sideways
                            ? (down ? CGRectGetMinX(f) >= CGRectGetMaxX(screen) : CGRectGetMaxX(f) <= CGRectGetMinX(screen))
                            : (down ? CGRectGetMinY(f) >= CGRectGetMaxY(screen) : CGRectGetMaxY(f) <= CGRectGetMinY(screen));
                        if (offDir) off++;
                    }
                    if (off >= 20) {
                        RCScreenElement *m = rc_pick(tree, text);
                        if (m) fprintf(stderr, "Not found in the list (%lu rows checked): %s (only mentioned in: %s)\n",
                            (unsigned long)off, text.UTF8String, rc_line(m).UTF8String);
                        else fprintf(stderr, "Not found in the list (%lu rows checked): %s\n", (unsigned long)off, text.UTF8String);
                        return 1;
                    }
                }
                CGRect tf = hit ? rc_frame(hit.element) : CGRectZero;
                if (hit && !CGRectIsEmpty(tf) && !CGRectIntersectsRect(tf, screen)) {
                    BOOL towardEnd = (sideways ? CGRectGetMidX(tf) : CGRectGetMidY(tf))
                        > (sideways ? CGRectGetMidX(screen) : CGRectGetMidY(screen));
                    double span = (sideways ? screen.size.width : screen.size.height) * 0.6;
                    int stuck = 0;
                    for (int t = 0; !found && t < 24 && stuck < 2; t++) {
                        NSMutableDictionary<NSString *, NSString *> *beforeFrames = [NSMutableDictionary dictionary];
                        for (RCScreenElement *e in list) {
                            NSString *k = [NSString stringWithFormat:@"%@|%@|%@", e.kind, e.label, e.value];
                            if (!beforeFrames[k]) beforeFrames[k] = rc_box(e.frame);
                        }
                        NSString *drag;
                        if (sideways) drag = [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62",
                            x + (towardEnd ? span / 2 : -span / 2), y, x - (towardEnd ? span / 2 : -span / 2), y];
                        else drag = [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62",
                            x, y + (towardEnd ? span / 2 : -span / 2), x, y - (towardEnd ? span / 2 : -span / 2)];
                        if (rc_command(drag) != 0) return 2;
                        list = rc_settled_elements(1.2);
                        found = pick(list);
                        if (found) break;
                        if ([rc_screen_items(list) isSubsetOfSet:[NSSet setWithArray:beforeFrames.allKeys]]) { stuck++; continue; }
                        BOOL moved = NO;
                        for (RCScreenElement *e in list) {
                            NSString *bf = beforeFrames[[NSString stringWithFormat:@"%@|%@|%@", e.kind, e.label, e.value]];
                            if (bf && ![bf isEqualToString:rc_box(e.frame)]) { moved = YES; break; }
                        }
                        if (!moved) {
                            // A step that left nothing of the last screen where it was skipped a
                            // screen of rows: back off half a step and look again
                            NSString *back;
                            if (sideways) back = [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62",
                                x + (towardEnd ? -span / 4 : span / 4), y, x - (towardEnd ? -span / 4 : span / 4), y];
                            else back = [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62",
                                x, y + (towardEnd ? -span / 4 : span / 4), x, y - (towardEnd ? -span / 4 : span / 4)];
                            if (rc_command(back) != 0) return 2;
                            list = rc_settled_elements(1.2);
                            found = pick(list);
                            if (found) break;
                            continue;
                        }
                        stuck = 0;
                    }
                }
            }

            // Pages run sideways, and are few; the home screen's live edges (Today View, App
            // Library) never look like an end, so a sideways search stops sooner
            while (!found && swipes < (sideways ? 12 : 24)) {
                found = pick(list);
                if (!found) {
                    RCScreenElement *m = rc_pick(list, text);
                    if (m && !mention && ![acting containsObject:m.kind]) mention = rc_line(m);
                }
                if (found) break;
                // The screen keyed kind|label|value -> frame, so after the step a shared item
                // that moved proves the scroll kept the last screen's content in view
                NSMutableDictionary<NSString *, NSString *> *beforeFrames = [NSMutableDictionary dictionary];
                for (RCScreenElement *e in list) {
                    NSString *k = [NSString stringWithFormat:@"%@|%@|%@", e.kind, e.label, e.value];
                    if (!beforeFrames[k]) beforeFrames[k] = rc_box(e.frame);
                }
                NSSet<NSString *> *before = [NSSet setWithArray:beforeFrames.allKeys];
                // 40% drags: the list can't coast past the next screen
                double h = screen.size.height, w = screen.size.width;
                NSString *drag;
                if (sideways) {
                    double lx = screen.origin.x + w * 0.3, rx = screen.origin.x + w * 0.7;
                    drag = down ? [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62", rx, y, lx, y]
                                : [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62", lx, y, rx, y];
                } else {
                    double hi = screen.origin.y + h * 0.3, lo = screen.origin.y + h * 0.7;
                    drag = down ? [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62", x, lo, x, hi]
                                : [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62", x, hi, x, lo];
                }
                if (rc_command(drag) != 0) return 2;
                swipes++;
                list = rc_settled_elements(2);
                if ([rc_screen_items(list) isSubsetOfSet:before]) {
                    // The end of the list: the other way, once (checked first, so a list stopped
                    // at its end doesn't look like a gap)
                    if (++turns > 1) break;
                    down = !down;
                } else {
                    // Nothing of the last screen is still moving on this one: the step skipped a
                    // screen of rows, so back off halfway and look again before going on. Static
                    // chrome (nav bar, tab bar) doesn't count - it never moves
                    BOOL moved = NO;
                    for (RCScreenElement *e in list) {
                        NSString *bf = beforeFrames[[NSString stringWithFormat:@"%@|%@|%@", e.kind, e.label, e.value]];
                        if (bf && ![bf isEqualToString:rc_box(e.frame)]) { moved = YES; break; }
                    }
                    if (!moved) {
                        NSString *back;
                        if (sideways) {
                            double lx = screen.origin.x + w * 0.4, rx = screen.origin.x + w * 0.6;
                            back = down ? [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62", lx, y, rx, y]
                                        : [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62", rx, y, lx, y];
                        } else {
                            double hi = screen.origin.y + h * 0.4, lo = screen.origin.y + h * 0.6;
                            back = down ? [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62", x, hi, x, lo]
                                        : [NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62", x, lo, x, hi];
                        }
                        if (rc_command(back) != 0) return 2;
                        list = rc_settled_elements(2);
                    }
                }
            }
            if (found) {
                // Fully on screen, if it's cut off at an edge
                CGRect f = found.frame;
                if (CGRectGetMinY(f) < CGRectGetMinY(screen) || CGRectGetMaxY(f) > CGRectGetMaxY(screen)) {
                    ((void (*)(id, SEL))objc_msgSend)(found.element, NSSelectorFromString(@"scrollToVisible"));
                    list = rc_settled_elements(2);
                    found = pick(list) ?: found;
                }
                // Not under a bar: in the top or bottom band (a see-through nav bar, a tab
                // bar) a press or tap lands on the bar, so drag it toward the middle
                CGRect fr = found.frame;
                if (!sideways && (CGRectGetMinY(fr) < screen.origin.y + band || CGRectGetMaxY(fr) > CGRectGetMaxY(screen) - band)) {
                    double shift = CGRectGetMidY(screen) - CGRectGetMidY(fr), from = CGRectGetMidY(screen) - shift / 2;
                    rc_command([NSString stringWithFormat:@"gesture drag %.0f %.0f %.0f %.0f 0.62", x, from, x, from + shift]);
                    list = rc_settled_elements(2);
                    found = pick(list) ?: found;
                }
                if (json) rc_print_json(rc_json(found));
                else printf("%s\n", rc_line(found).UTF8String);
                return 0;
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

        if (outline) {
            printf("%s\n", rc_outline(app, appName, bundleID, list).UTF8String);
        } else if (json) {
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
