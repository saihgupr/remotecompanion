#import "RCScreen.h"
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <limits.h>
#import <stdlib.h>
#import <dlfcn.h>
#import "RCGestures.h"
#import "RCSpawn.h"
#import "RCScreenSelect.h"

void SRLog(NSString *format, ...);

// UIKit's own screen grab: the whole screen as SpringBoard shows it (main thread only)
extern UIImage *_UICreateScreenUIImage(void) NS_RETURNS_RETAINED;

// Draws the screen grab the way the screen is turned now, `scale` times its size in points. The grab
// is always upright (portrait), so in landscape it's turned with the same mapping touches use.
void RCScreenDrawShot(UIImage *shot, double scale) {
    UIScreen *screen = [UIScreen mainScreen];
    id<UICoordinateSpace> fixed = screen.fixedCoordinateSpace, now = screen.coordinateSpace;
    CGPoint o = [fixed convertPoint:CGPointZero toCoordinateSpace:now];
    CGPoint x = [fixed convertPoint:CGPointMake(1, 0) toCoordinateSpace:now];
    CGPoint y = [fixed convertPoint:CGPointMake(0, 1) toCoordinateSpace:now];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    CGContextScaleCTM(ctx, scale, scale);
    CGContextConcatCTM(ctx, CGAffineTransformMake(x.x - o.x, x.y - o.y, y.x - o.x, y.y - o.y, o.x, o.y));
    [shot drawInRect:fixed.bounds];
    CGContextRestoreGState(ctx);
}

// Lines every `spacing` points with their positions, so a point can be read off the picture
static void rc_screen_draw_grid(CGSize points, double scale, double spacing) {
    UIColor *line = [UIColor colorWithRed:1 green:0.2 blue:0.4 alpha:0.55];
    NSDictionary *label = @{ NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:MAX(8, 22 * scale) weight:UIFontWeightBold],
                             NSForegroundColorAttributeName: [UIColor whiteColor],
                             NSBackgroundColorAttributeName: [UIColor colorWithRed:0.8 green:0.1 blue:0.3 alpha:0.8] };
    [line setFill];
    for (double x = spacing; x < points.width; x += spacing) {
        UIRectFill(CGRectMake(round(x * scale), 0, 1, points.height * scale));
        [[NSString stringWithFormat:@"%.0f", x] drawAtPoint:CGPointMake(round(x * scale) + 2, 2) withAttributes:label];
    }
    for (double y = spacing; y < points.height; y += spacing) {
        UIRectFill(CGRectMake(0, round(y * scale), points.width * scale, 1));
        [[NSString stringWithFormat:@"%.0f", y] drawAtPoint:CGPointMake(2, round(y * scale) + 2) withAttributes:label];
    }
}

// The screen as a small JPEG at `path`: `scale` of its size in points, JPEG `quality`, with a grid
// every `grid` points when that's above 0
static NSString *rc_screen_capture(NSString *path, double scale, double quality, double grid) {
    __block NSData *jpeg = nil;
    __block CGSize size = CGSizeZero;
    void (^grab)(void) = ^{
        UIImage *shot = _UICreateScreenUIImage();
        if (!shot) return;
        CGSize points = [UIScreen mainScreen].bounds.size;
        size = CGSizeMake(round(points.width * scale), round(points.height * scale));
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        UIImage *small = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            RCScreenDrawShot(shot, scale);
            if (grid > 0) rc_screen_draw_grid(points, scale, grid);
        }];
        jpeg = UIImageJPEGRepresentation(small, quality);
    };
    if ([NSThread isMainThread]) grab(); else dispatch_sync(dispatch_get_main_queue(), grab);
    if (!jpeg) return @"Error: Couldn't capture the screen\n";
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    if (![jpeg writeToFile:path atomically:YES]) return [NSString stringWithFormat:@"Error: Couldn't write %@\n", path];
    chmod(path.fileSystemRepresentation, 0644);
    return [NSString stringWithFormat:@"%@ %.0fx%.0f %lu bytes\n", path, size.width, size.height, (unsigned long)jpeg.length];
}

// A small gray thumbnail of the screen, to tell whether it's still changing
static NSData *rc_screen_thumb(void) {
    __block NSData *out = nil;
    void (^grab)(void) = ^{
        UIImage *shot = _UICreateScreenUIImage();
        if (!shot.CGImage) return;
        const size_t w = 48, h = 104;
        NSMutableData *pixels = [NSMutableData dataWithLength:w * h];
        CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
        CGContextRef ctx = CGBitmapContextCreate(pixels.mutableBytes, w, h, 8, w, gray, (CGBitmapInfo)kCGImageAlphaNone);
        CGColorSpaceRelease(gray);
        if (!ctx) return;
        CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), shot.CGImage);
        CGContextRelease(ctx);
        out = pixels;
    };
    if ([NSThread isMainThread]) grab(); else dispatch_sync(dispatch_get_main_queue(), grab);
    return out;
}

// How many thumbnail pixels differ noticeably: a clock or a blinking cursor changes only a few
static NSUInteger rc_screen_changed(NSData *a, NSData *b) {
    if (a.length != b.length) return NSUIntegerMax;
    const uint8_t *p = a.bytes, *q = b.bytes;
    NSUInteger changed = 0;
    for (NSUInteger i = 0; i < a.length; i++) if (abs((int)p[i] - (int)q[i]) > 10) changed++;
    return changed;
}

BOOL RCScreenSettle(double maxSeconds, double *waited) {
    double start = CFAbsoluteTimeGetCurrent();
    if ([NSThread isMainThread]) { if (waited) *waited = 0; return NO; }
    // A moment first, so a change just set off (a tap opening a page) has begun. Then settled
    // means three thumbnails in a row, 0.15 s apart, nearly the same.
    [NSThread sleepForTimeInterval:0.12];
    NSData *last = rc_screen_thumb();
    int still = 0;
    BOOL settled = NO;
    while (CFAbsoluteTimeGetCurrent() - start < maxSeconds) {
        [NSThread sleepForTimeInterval:0.15];
        NSData *now = rc_screen_thumb();
        still = (last && now && rc_screen_changed(last, now) <= 6) ? still + 1 : 0;
        last = now;
        if (still >= 2) { settled = YES; break; }
    }
    if (waited) *waited = CFAbsoluteTimeGetCurrent() - start;
    return settled;
}

// Screenshots go only into the phone's temporary folders: no "..", and the folder it lands in
// (or the nearest one that exists) must still be one of them with symlinks followed
static BOOL rc_capture_path_ok(NSString *path) {
    if (![path hasPrefix:@"/var/mobile/tmp/"] && ![path hasPrefix:@"/tmp/"]) return NO;
    if ([path.pathComponents containsObject:@".."]) return NO;
    NSString *dir = path.stringByDeletingLastPathComponent;
    while (dir.length > 1 && ![[NSFileManager defaultManager] fileExistsAtPath:dir]) dir = dir.stringByDeletingLastPathComponent;
    char real[PATH_MAX];
    if (!realpath(dir.fileSystemRepresentation, real)) return NO;
    NSString *resolved = @(real);
    for (NSString *root in @[@"/private/var/tmp", @"/private/var/mobile/tmp", @"/var/tmp", @"/var/mobile/tmp", @"/tmp"]) {
        if ([resolved isEqualToString:root] || [resolved hasPrefix:[root stringByAppendingString:@"/"]]) return YES;
    }
    return NO;
}

// ---- Vision probe (screen ocr / screen shift) ----
// A mobile CLI can't make IOSurfaces, so Vision dies there (probes/ocr-probe); in SpringBoard
// it works. Vision itself is dlopened on first use so SpringBoard only loads it when asked.
static void *rc_vision(void) {
    static void *v;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ v = dlopen("/System/Library/Frameworks/Vision.framework/Vision", RTLD_LAZY); });
    return v;
}

// One OCR or shift at a time
static dispatch_semaphore_t rc_vision_busy(void) {
    static dispatch_semaphore_t busy;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ busy = dispatch_semaphore_create(1); });
    return busy;
}

// VN* messages, declared on NSObject so ARC is happy with classes from NSClassFromString
@interface NSObject (RCVision)
- (id)initWithCGImage:(CGImageRef)img options:(NSDictionary *)opts;
- (BOOL)performRequests:(NSArray *)requests error:(NSError **)error;
- (NSArray *)topCandidates:(NSUInteger)count;
- (void)setRecognitionLevel:(long)level;
- (void)setUsesLanguageCorrection:(BOOL)on;
- (NSArray *)results;
- (CGRect)boundingBox;
- (NSString *)string;
- (float)confidence;
@end

// The screen at points * scale pixels (scale 1 = point resolution, native = full pixels)
static UIImage *rc_screen_grab(double scale) {
    __block UIImage *out = nil;
    void (^grab)(void) = ^{
        UIImage *shot = _UICreateScreenUIImage();
        if (!shot) return;
        CGSize points = [UIScreen mainScreen].bounds.size;
        CGSize size = CGSizeMake(round(points.width * scale), round(points.height * scale));
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        out = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            RCScreenDrawShot(shot, scale); // turned as the screen is, so boxes match touch points
        }];
    };
    if ([NSThread isMainThread]) grab(); else dispatch_sync(dispatch_get_main_queue(), grab);
    return out;
}

// Runs `block` off the main thread with at most `seconds`. `busy` and the reply live in the
// block, so on a timeout Vision keeps them until it really ends - the next request just sees
// busy. Returns nil on timeout (the reply is only read once the block finished).
static NSString *rc_vision_run(dispatch_semaphore_t busy, double seconds, NSString *(^block)(void)) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSString *reply = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool { reply = block(); }
        dispatch_semaphore_signal(done);
        dispatch_semaphore_signal(busy);
    });
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC))) != 0) return nil;
    return reply;
}

// VNRequestTextRecognitionLevel: Accurate is 0, Fast is 1 - named, so the mapping can't flip
static const long kRCOCRLevelAccurate = 0;
static const long kRCOCRLevelFast = 1;

// One line of text Vision found: its string and its box in screen points
@interface RCScreenText : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) float confidence;
@end
@implementation RCScreenText
@end

// The careful read in rc-ocr, a separate process, for where it fails inside SpringBoard (iOS 15).
// nil with *error set when that doesn't work either.
static NSArray<RCScreenText *> *rc_screen_read_helper(UIImage *shot, double scale, NSString **error) {
    NSString *tool = rc_tool_path(@"rc-ocr");
    if (!tool) { if (error) *error = @"rc-ocr isn't installed"; return nil; }
    NSString *path = [NSString stringWithFormat:@"/var/mobile/tmp/rc-ocr-%d.jpg", getpid()];
    NSData *jpeg = UIImageJPEGRepresentation(shot, 0.92);
    if (![jpeg writeToFile:path atomically:YES]) { if (error) *error = @"Couldn't save the screen for rc-ocr"; return nil; }
    NSString *output = nil;
    int code = rc_run_tool(tool, @[path], 10, &output);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    if (code != 0) { if (error) *error = [NSString stringWithFormat:@"rc-ocr: %@", output.length ? output : @"failed"]; return nil; }
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@"\t"];
        if (f.count < 6) continue;
        RCScreenText *t = [RCScreenText new];
        t.frame = CGRectMake([f[0] doubleValue] / scale, [f[1] doubleValue] / scale, [f[2] doubleValue] / scale, [f[3] doubleValue] / scale);
        t.confidence = [f[4] floatValue];
        t.text = [[f subarrayWithRange:NSMakeRange(5, f.count - 5)] componentsJoinedByString:@" "];
        [items addObject:t];
    }
    return items;
}

// Reads the text in a picture already taken, at `scale` times its size in points. The box math
// below divides the picture's pixels by `scale`, so the frames come out in screen points. Never on
// the main thread. nil with *error set when it couldn't read.
static NSArray<RCScreenText *> *rc_screen_ocr_image(UIImage *shot, double scale, BOOL accurate, NSString **error) {
    if ([NSThread isMainThread]) { if (error) *error = @"Can't read the screen from the main thread"; return nil; }
    if (!shot.CGImage) { if (error) *error = @"There's no picture to read"; return nil; }
    if (!rc_vision()) { if (error) *error = @"Vision couldn't load"; return nil; }
    dispatch_semaphore_t busy = rc_vision_busy();
    // Another read finishing first is fine: wait for it a little
    if (dispatch_semaphore_wait(busy, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC))) != 0) {
        if (error) *error = @"Busy reading the screen";
        return nil;
    }
    __block NSArray *found = nil;
    __block NSString *failure = nil;
    NSString *done = rc_vision_run(busy, 15, ^NSString *{
        CGImageRef img = shot.CGImage;
        double W = CGImageGetWidth(img), H = CGImageGetHeight(img);
        id handler = [[NSClassFromString(@"VNImageRequestHandler") alloc] initWithCGImage:img options:@{}];
        // The careful read fails in SpringBoard on some iOS versions ("Error computing NN outputs"
        // on iOS 15; on the CPU instead it hangs). Then rc-ocr does it in its own process, and if
        // that can't either, the quick read is used. What works is remembered.
        static int way = 0; // 0 careful here, 1 careful in rc-ocr, 2 quick here
        if (accurate && way == 1) {
            NSString *helperError = nil;
            NSArray *viaHelper = rc_screen_read_helper(shot, scale, &helperError);
            if (viaHelper) { found = viaHelper; return @""; }
            way = 2;
            SRLog(@"[Screen] Careful text recognition in rc-ocr failed (%@): using the quick one", helperError);
        }
        id req = nil;
        NSError *err = nil;
        for (int quick = (!accurate || way == 2) ? 1 : 0; quick <= 1; quick++) {
            req = [[NSClassFromString(@"VNRecognizeTextRequest") alloc] init];
            [req setRecognitionLevel:quick ? kRCOCRLevelFast : kRCOCRLevelAccurate];
            [req setUsesLanguageCorrection:NO];
            err = nil;
            [handler performRequests:@[req] error:&err];
            if (!err) break;
            if (!quick) {
                SRLog(@"[Screen] Careful text recognition failed in SpringBoard (%@): trying rc-ocr", err.localizedDescription);
                NSString *helperError = nil;
                NSArray *viaHelper = rc_screen_read_helper(shot, scale, &helperError);
                if (viaHelper) { way = 1; found = viaHelper; return @""; }
                way = 2;
                SRLog(@"[Screen] rc-ocr failed too (%@): using the quick read", helperError);
            }
        }
        if (err) { failure = err.localizedDescription; return @""; }
        NSMutableArray *items = [NSMutableArray array];
        for (id obs in [req results]) {
            id best = [[obs topCandidates:1] firstObject];
            if (!best) continue;
            CGRect b = [obs boundingBox]; // normalized, origin bottom-left
            RCScreenText *t = [RCScreenText new];
            t.text = [best string];
            t.confidence = [best confidence];
            t.frame = CGRectMake(b.origin.x * W / scale, (1 - b.origin.y - b.size.height) * H / scale,
                                 b.size.width * W / scale, b.size.height * H / scale);
            [items addObject:t];
        }
        found = items;
        return @"";
    });
    if (!done) { if (error) *error = @"Reading the screen took over 15 s"; return nil; }
    if (failure) { if (error) *error = failure; return nil; }
    return found;
}

// Every line of text on the screen, read at full pixels (`accurate`) or quicker. Never on the main
// thread (the grab needs it). nil with *error set when it couldn't read.
static NSArray<RCScreenText *> *rc_screen_read(BOOL accurate, NSString **error) {
    if ([NSThread isMainThread]) { if (error) *error = @"Can't read the screen from the main thread"; return nil; }
    double scale = [[UIScreen mainScreen] nativeScale];
    if (!accurate) scale = MIN(scale, 2);
    UIImage *shot = rc_screen_grab(scale);
    if (!shot) { if (error) *error = @"Couldn't capture the screen"; return nil; }
    return rc_screen_ocr_image(shot, scale, accurate, error);
}

// The screen as a picture at full pixels, for reading after someone has picked an area. Main thread.
UIImage *RCScreenGrabImage(void) {
    return rc_screen_grab([[UIScreen mainScreen] nativeScale]);
}

// Lines top to bottom, left to right within a row, one per line
static NSString *rc_screen_join(NSArray<RCScreenText *> *items) {
    NSArray<RCScreenText *> *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(RCScreenText *a, RCScreenText *b) {
        double ay = CGRectGetMidY(a.frame), by = CGRectGetMidY(b.frame);
        // Within a few points of each other is the same row: left to right
        if (fabs(ay - by) > 6) return ay < by ? NSOrderedAscending : NSOrderedDescending;
        double ax = CGRectGetMinX(a.frame), bx = CGRectGetMinX(b.frame);
        if (fabs(ax - bx) < 0.5) return NSOrderedSame;
        return ax < bx ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (RCScreenText *t in sorted) {
        NSString *line = [t.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length) [lines addObject:line];
    }
    return [lines componentsJoinedByString:@"\n"];
}

NSString *RCScreenAllText(NSString **error) {
    NSArray<RCScreenText *> *items = rc_screen_read(YES, error);
    if (!items) return nil;
    return rc_screen_join(items);
}

// The area of `shot` in screen points, cut out and made bigger when it's small, so text in a photo
// that the whole screen was too big to see counts. *zoom says how much bigger it was made.
static UIImage *rc_screen_crop(UIImage *shot, CGRect rect, double scale, double *zoom) {
    CGImageRef img = shot.CGImage;
    if (!img) return nil;
    CGRect pixels = CGRectMake(rect.origin.x * scale, rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale);
    pixels = CGRectIntegral(pixels);
    CGRect bounds = CGRectMake(0, 0, CGImageGetWidth(img), CGImageGetHeight(img));
    pixels = CGRectIntersection(bounds, pixels);
    if (CGRectIsNull(pixels) || pixels.size.width < 2 || pixels.size.height < 2) return nil;
    CGImageRef cut = CGImageCreateWithImageInRect(img, pixels);
    if (!cut) return nil;
    // A small area goes to Vision at up to three times its size; a full screen stays as it is
    double factor = MIN(3.0, MAX(1.0, 900.0 / MAX(pixels.size.width, pixels.size.height)));
    if (zoom) *zoom = factor;
    UIImage *piece = [UIImage imageWithCGImage:cut scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(cut);
    if (factor <= 1.001) return piece;
    CGSize size = CGSizeMake(round(pixels.size.width * factor), round(pixels.size.height * factor));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
        [piece drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

NSString *RCScreenTextInRect(UIImage *shot, CGRect rect, NSString **error) {
    rect = CGRectStandardize(rect);
    if (!shot.CGImage) { if (error) *error = @"There's no picture to read"; return nil; }
    if (rect.size.width < 1 || rect.size.height < 1) { if (error) *error = @"The area is too small"; return nil; }
    if ([NSThread isMainThread]) { if (error) *error = @"Can't read the screen from the main thread"; return nil; }
    double scale = [[UIScreen mainScreen] nativeScale];
    NSString *failure = nil;
    NSArray<RCScreenText *> *items = rc_screen_ocr_image(shot, scale, YES, &failure);
    if (!items) { if (error) *error = failure ?: @"Couldn't read the screen"; return nil; }
    NSMutableArray<RCScreenText *> *inside = [NSMutableArray array];
    for (RCScreenText *t in items) {
        CGRect hit = CGRectIntersection(t.frame, rect);
        // Any real part of a line counts, so a corner of the area still copies the whole line
        if (!CGRectIsNull(hit) && hit.size.width >= 4 && hit.size.height >= 4) [inside addObject:t];
    }
    NSString *text = rc_screen_join(inside);
    if (text.length) return text;
    // No line was picked: read just the area, enlarged, for small text the full read passed over
    double zoom = 1;
    UIImage *crop = rc_screen_crop(shot, rect, scale, &zoom);
    if (!crop) return @"";
    NSString *cropError = nil;
    NSArray<RCScreenText *> *found = rc_screen_ocr_image(crop, scale * zoom, YES, &cropError);
    if (!found) { if (error) *error = cropError ?: @"Couldn't read the area"; return nil; }
    return rc_screen_join(found);
}

// Lowercased with runs of spaces made one, for matching
static NSString *rc_screen_norm(NSString *s) {
    NSArray *parts = [[s lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
}

// The line that best matches `query` (case doesn't matter): the same text, then one starting with
// it, then one containing it; the shortest wins, then the highest. nil when none has it.
static RCScreenText *rc_screen_match(NSArray<RCScreenText *> *items, NSString *query) {
    NSString *q = rc_screen_norm(query);
    if (!q.length) return nil;
    RCScreenText *best = nil;
    int bestRank = 9;
    for (RCScreenText *t in items) {
        NSString *n = rc_screen_norm(t.text);
        int rank = [n isEqualToString:q] ? 0 : [n hasPrefix:q] ? 1 : [n containsString:q] ? 2 : 9;
        if (rank == 9) continue;
        BOOL better = rank < bestRank ||
            (rank == bestRank && (t.text.length < best.text.length ||
                                  (t.text.length == best.text.length && CGRectGetMinY(t.frame) < CGRectGetMinY(best.frame))));
        if (better) { best = t; bestRank = rank; }
    }
    return best;
}

// Where the query's own words sit inside a longer line: the line's box narrowed in proportion, so
// "Wi-Fi" in "Wi-Fi  Home Network" is tapped on "Wi-Fi", not the middle of the line
static CGPoint rc_screen_target(RCScreenText *t, NSString *query) {
    CGRect f = t.frame;
    NSRange r = [t.text rangeOfString:query options:NSCaseInsensitiveSearch];
    if (r.location != NSNotFound && t.text.length > 0) {
        double per = f.size.width / t.text.length;
        return CGPointMake(f.origin.x + per * (r.location + r.length / 2.0), CGRectGetMidY(f));
    }
    return CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
}

BOOL RCScreenShowsText(NSString *text) {
    NSString *error = nil;
    NSArray *items = rc_screen_read(YES, &error);
    if (!items) { SRLog(@"[Screen] Text on Screen \"%@\": %@", text, error); return NO; }
    return rc_screen_match(items, text) != nil;
}

// The text in quotes after the verb (to the last quote, so quotes inside are kept), else the rest;
// a number after the closing quote goes to *number
static NSString *rc_screen_quoted(NSString *arg, double *number) {
    arg = [arg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([arg hasPrefix:@"\""]) {
        NSRange close = [arg rangeOfString:@"\"" options:NSBackwardsSearch];
        if (close.location > 0) {
            NSString *after = [[arg substringFromIndex:close.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (after.length && number) *number = after.doubleValue;
            return [arg substringWithRange:NSMakeRange(1, close.location - 1)];
        }
    }
    return arg;
}

static NSString *rc_screen_text_command(NSString *verb, NSString *arg) {
    if ([verb isEqualToString:@"ocr"]) {
        NSString *error = nil;
        double t0 = CFAbsoluteTimeGetCurrent();
        NSArray<RCScreenText *> *items = rc_screen_read(![arg containsString:@"fast"], &error);
        if (!items) return [NSString stringWithFormat:@"Error: %@\n", error];
        BOOL json = [arg containsString:@"--json"];
        if (json) {
            NSMutableArray *out = [NSMutableArray array];
            for (RCScreenText *t in items) {
                CGRect f = t.frame;
                [out addObject:@{ @"text": t.text, @"conf": @(round(t.confidence * 100) / 100),
                                  @"frame": @[@(round(f.origin.x)), @(round(f.origin.y)), @(round(f.size.width)), @(round(f.size.height))] }];
            }
            NSData *d = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
            return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByAppendingString:@"\n"];
        }
        NSMutableString *out = [NSMutableString string];
        for (RCScreenText *t in items) {
            CGRect f = t.frame;
            [out appendFormat:@"%.0f,%.0f %.0fx%.0f  %@\n", f.origin.x, f.origin.y, f.size.width, f.size.height, t.text];
        }
        [out appendFormat:@"(%lu lines, %.0f ms)\n", (unsigned long)items.count, (CFAbsoluteTimeGetCurrent() - t0) * 1000];
        return out;
    }
    double seconds = 10;
    NSString *query = rc_screen_quoted(arg, &seconds);
    if (!query.length) return nil;
    if ([verb isEqualToString:@"find"] || [verb isEqualToString:@"tap"]) {
        // Text still sliding in would be tapped where it was: let the screen settle first
        if ([verb isEqualToString:@"tap"]) RCScreenSettle(2, NULL);
        NSString *error = nil;
        NSArray *items = rc_screen_read(YES, &error);
        if (!items) return [NSString stringWithFormat:@"Error: %@\n", error];
        RCScreenText *t = rc_screen_match(items, query);
        if (!t) return [NSString stringWithFormat:@"Error: \"%@\" isn't on the screen\n", query];
        CGPoint p = rc_screen_target(t, query);
        if ([verb isEqualToString:@"find"]) {
            return [NSString stringWithFormat:@"\"%@\" at %.0f %.0f (box %.0f,%.0f %.0fx%.0f)\n", t.text, p.x, p.y,
                    t.frame.origin.x, t.frame.origin.y, t.frame.size.width, t.frame.size.height];
        }
        NSString *tap = RCGestureCommand([NSString stringWithFormat:@"gesture tap %.1f %.1f", p.x, p.y]);
        if ([tap hasPrefix:@"Error"]) return tap;
        return [NSString stringWithFormat:@"Tapped \"%@\" at %.0f %.0f\n", t.text, p.x, p.y];
    }
    if ([verb isEqualToString:@"wait"]) {
        seconds = MIN(MAX(seconds, 0.5), 120);
        double until = CFAbsoluteTimeGetCurrent() + seconds;
        NSString *lastError = nil;
        do {
            NSString *error = nil;
            NSArray *items = rc_screen_read(YES, &error);
            if (items) {
                RCScreenText *t = rc_screen_match(items, query);
                if (t) {
                    // Found as soon as it shows, which can be mid-slide: done once the screen is still,
                    // so a touch right after lands where it should
                    RCScreenSettle(2, NULL);
                    return [NSString stringWithFormat:@"Found \"%@\"\n", t.text];
                }
            } else lastError = error;
            [NSThread sleepForTimeInterval:0.4];
        } while (CFAbsoluteTimeGetCurrent() < until);
        return lastError ? [NSString stringWithFormat:@"Error: %@\n", lastError]
                         : [NSString stringWithFormat:@"Error: \"%@\" didn't show within %g s\n", query, seconds];
    }
    return nil;
}

NSString *RCScreenCommand(NSString *cmd) {
    NSString *rest = [cmd substringFromIndex:MIN(cmd.length, (NSUInteger)7)]; // after "screen "
    NSArray *words = [rest componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    NSString *verb = [words.firstObject lowercaseString] ?: @"";
    if ([verb isEqualToString:@"settle"]) {
        // screen settle [MAX]: waits until the screen stops changing, at most MAX seconds (default 3)
        if ([NSThread isMainThread]) return @"Error: screen settle can't wait on the main thread\n";
        double max = words.count > 1 ? MIN(MAX([words[1] doubleValue], 0.3), 15) : 3;
        double waited = 0;
        BOOL settled = RCScreenSettle(max, &waited);
        return [NSString stringWithFormat:settled ? @"Settled after %.0f ms\n" : @"Still changing after %.0f ms\n", waited * 1000];
    }
    if ([verb isEqualToString:@"copy"]) {
        // screen copy [rect [SECONDS]]: all text on screen, or draw a selection box first
        if (words.count > 1) {
            if (![[words[1] lowercaseString] isEqualToString:@"rect"] || words.count > 3) {
                return @"Usage: screen copy [rect [SECONDS]]\n";
            }
            if (words.count == 3) {
                double parsed = 0;
                NSScanner *scanner = [NSScanner scannerWithString:words[2]];
                if (![scanner scanDouble:&parsed] || !scanner.isAtEnd || !isfinite(parsed) || parsed <= 0) {
                    return @"Usage: screen copy [rect [SECONDS]]\n";
                }
            }
        }
        NSString *arg = words.count > 1
            ? [[words subarrayWithRange:NSMakeRange(1, words.count - 1)] componentsJoinedByString:@" "]
            : @"";
        if ([NSThread isMainThread]) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSString *reply = RCScreenCopyCommand(arg);
                SRLog(@"[Screen] screen copy%@: %@",
                      arg.length ? [@" " stringByAppendingString:arg] : @"",
                      [reply stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
            });
            return arg.length
                ? [NSString stringWithFormat:@"Started: screen copy %@\n", arg]
                : @"Started: screen copy\n";
        }
        return RCScreenCopyCommand(arg);
    }
    if ([@[@"ocr", @"find", @"tap", @"wait"] containsObject:verb]) {
        NSRange space = [rest rangeOfString:@" "];
        NSString *arg = space.location == NSNotFound ? @"" : [rest substringFromIndex:space.location + 1];
        // Reading the screen needs the main thread free: from it (the Web UI) this runs on its own
        if ([NSThread isMainThread]) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSString *reply = rc_screen_text_command(verb, arg);
                SRLog(@"[Screen] screen %@ %@: %@", verb, arg, [reply stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
            });
            return [NSString stringWithFormat:@"Started: screen %@ %@\n", verb, arg];
        }
        NSString *reply = rc_screen_text_command(verb, arg);
        if (reply) return reply;
    }
    if (![verb isEqualToString:@"capture"]) return @"Usage: screen capture [PATH] [SCALE] [QUALITY] [grid [SPACING]] | screen settle [MAX] | screen ocr [fast] [--json] | screen copy [rect [SECONDS]] | screen find \"Text\" | screen tap \"Text\" | screen wait \"Text\" [SECONDS]\n";
    // screen capture [PATH] [SCALE] [QUALITY] [grid [SPACING]]
    double grid = 0;
    NSUInteger gridAt = [words indexOfObject:@"grid"];
    if (gridAt != NSNotFound) {
        grid = words.count > gridAt + 1 ? MIN(MAX([words[gridAt + 1] doubleValue], 20), 400) : 100;
        words = [words subarrayWithRange:NSMakeRange(0, gridAt)];
    }
    NSUInteger at = 1;
    NSString *path = @"/var/mobile/tmp/rc-screen.jpg";
    if (words.count > at && [words[at] hasPrefix:@"/"]) path = words[at++];
    double scale = words.count > at ? MIN(MAX([words[at] doubleValue], 0.1), 1) : 0.5;
    double quality = words.count > at + 1 ? MIN(MAX([words[at + 1] doubleValue], 0.1), 1) : 0.6;
    if (!rc_capture_path_ok(path)) return @"Error: Use a path in /var/mobile/tmp or /tmp\n";
    return rc_screen_capture(path, scale, quality, grid);
}
