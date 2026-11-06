#import "RCScreen.h"
#import "RCSpawn.h"
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <notify.h>
#import <dlfcn.h>
#import <mach/mach.h>

void RCScreenActivity(void) {
    static volatile double last = 0;
    double now = CFAbsoluteTimeGetCurrent();
    if (now - last < 0.25) return;
    last = now;
    notify_post("com.goldenappleguy.rc.screen-activity");
}

// UIKit's own screen grab: the whole screen as SpringBoard shows it (main thread only)
extern UIImage *_UICreateScreenUIImage(void) NS_RETURNS_RETAINED;

// The screen as a small JPEG at `path`: `scale` of its size in points, JPEG `quality`
static NSString *rc_screen_capture(NSString *path, double scale, double quality) {
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
            [shot drawInRect:CGRectMake(0, 0, size.width, size.height)];
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

void SRLog(NSString *format, ...);

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

// Runs rc-screen with these arguments; its exit status (-1 if it couldn't run or took longer
// than `timeout`), with what it printed in *output
static int rc_screen_run(NSArray<NSString *> *args, double timeout, NSString **output) {
    NSString *tool = rc_tool_path(@"rc-screen");
    if (!tool) {
        if (output) *output = @"rc-screen isn't installed";
        return -1;
    }
    NSDate *start = [NSDate date];
    int code = rc_run_tool(tool, args, timeout, output);
    if (code == -1 && output && !(*output).length) {
        *output = -[start timeIntervalSinceNow] >= timeout ? @"rc-screen took too long" : @"rc-screen couldn't start";
    }
    return code;
}

// "Text" or Text, then an optional number after the closing quote
static NSString *rc_screen_text(NSString *rest, double *number) {
    rest = [rest stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([rest hasPrefix:@"\""]) {
        NSRange close = [rest rangeOfString:@"\"" options:NSBackwardsSearch];
        if (close.location > 0) {
            NSString *after = [[rest substringFromIndex:close.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (number && after.length) *number = after.doubleValue;
            return [rest substringWithRange:NSMakeRange(1, close.location - 1)];
        }
    }
    return rest;
}

BOOL RCScreenShowsText(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || !text.length) return NO;
    if ([NSThread isMainThread]) {
        SRLog(@"[Screen] Screen Shows Text can't be checked on the main thread - false");
        return NO;
    }
    int code = rc_screen_run(@[@"find", text], 10, NULL);
    SRLog(@"[Screen] Screen shows \"%@\": %@", text, code == 0 ? @"yes" : @"no");
    return code == 0;
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
- (id)initWithTargetedCGImage:(CGImageRef)img options:(NSDictionary *)opts;
- (BOOL)performRequests:(NSArray *)requests error:(NSError **)error;
- (NSArray *)topCandidates:(NSUInteger)count;
- (void)setRecognitionLevel:(long)level;
- (void)setUsesLanguageCorrection:(BOOL)on;
- (void)setRecognitionLanguages:(NSArray *)langs;
- (NSArray *)results;
- (CGRect)boundingBox;
- (NSString *)string;
- (float)confidence;
- (CGAffineTransform)alignmentTransform;
@end

// `s` as a JSON string literal (quoted + escaped) - for the small replies here
static NSString *rc_json_str(NSString *s) {
    NSMutableString *out = [NSMutableString stringWithString:@"\""];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '"' || c == '\\') [out appendFormat:@"\\%C", c];
        else if (c < 0x20) [out appendFormat:@"\\u%04x", c];
        else [out appendFormat:@"%C", c];
    }
    [out appendString:@"\""];
    return out;
}

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
            [shot drawInRect:CGRectMake(0, 0, size.width, size.height)];
        }];
    };
    if ([NSThread isMainThread]) grab(); else dispatch_sync(dispatch_get_main_queue(), grab);
    return out;
}

// The key window's top safe-area inset in points - the status-bar band OCR shouldn't merge
static double rc_safe_top(void) {
    __block double top = 0;
    void (^grab)(void) = ^{
        UIWindow *key = nil;
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]] || sc.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) if (w.isKeyWindow) { key = w; break; }
            if (key) break;
        }
        if (!key) key = UIApplication.sharedApplication.windows.firstObject;
        top = key.safeAreaInsets.top;
    };
    if ([NSThread isMainThread]) grab(); else dispatch_sync(dispatch_get_main_queue(), grab);
    return top;
}

static long rc_footprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &n) != KERN_SUCCESS) return -1;
    return (long)(info.phys_footprint / 1048576);
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

// screen ocr [fast|accurate] [SCALE]: every string Vision sees, with its box in points
static NSString *rc_screen_ocr(NSString *arg) {
    if (!rc_vision()) return @"Error: Vision couldn't load\n";
    dispatch_semaphore_t busy = rc_vision_busy();
    if (dispatch_semaphore_wait(busy, DISPATCH_TIME_NOW) != 0)
        return [arg containsString:@"--json"] ? @"{\"ok\":false,\"error\":\"busy\"}\n" : @"Error: busy - an OCR or shift is already running\n";
    NSArray *words = [arg componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    BOOL json = [words containsObject:@"--json"];
    BOOL accurate = ![words containsObject:@"fast"];
    double scale = [[UIScreen mainScreen] nativeScale];
    for (NSString *w in words) {
        double v = [w doubleValue];
        if (v > 0) { scale = MIN(MAX(v, 1), scale); break; }
    }
    double captureStart = CFAbsoluteTimeGetCurrent();
    UIImage *shot = rc_screen_grab(scale);
    double safeTop = rc_safe_top();
    double captureMs = (CFAbsoluteTimeGetCurrent() - captureStart) * 1000;
    if (!shot) { dispatch_semaphore_signal(busy); return json ? @"{\"ok\":false,\"error\":\"Couldn't capture the screen\"}\n" : @"Error: Couldn't capture the screen\n"; }
    long memBefore = rc_footprint();
    NSString *reply = rc_vision_run(busy, 15, ^{
        CGImageRef img = shot.CGImage; // the block retains `shot` itself - safe past a timeout
        double W = CGImageGetWidth(img), H = CGImageGetHeight(img);
        double t0 = CFAbsoluteTimeGetCurrent();
        Class ReqClass = NSClassFromString(@"VNRecognizeTextRequest"), HandlerClass = NSClassFromString(@"VNImageRequestHandler");
        id req = [[ReqClass alloc] init];
        [req setRecognitionLevel:accurate ? kRCOCRLevelAccurate : kRCOCRLevelFast];
        [req setUsesLanguageCorrection:NO];
        if (accurate) [req setRecognitionLanguages:@[@"en-US"]];
        id handler = [[HandlerClass alloc] initWithCGImage:img options:@{}];
        NSError *error = nil;
        [handler performRequests:@[req] error:&error];
        double ocrMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000;
        if (error) return json ? [NSString stringWithFormat:@"{\"ok\":false,\"error\":%@}\n", rc_json_str(error.localizedDescription)]
                               : [NSString stringWithFormat:@"Error: %@\n", error.localizedDescription];
        NSArray *results = [req results];
        NSMutableString *out = [NSMutableString string];
        NSMutableArray *items = [NSMutableArray array];
        for (id obs in results) {
            id text = [[obs topCandidates:1] firstObject];
            if (!text) continue;
            CGRect b = [obs boundingBox]; // Vision: normalized, bottom-left origin -> points, top-left
            CGRect box = CGRectMake(b.origin.x * W / scale, (1 - b.origin.y - b.size.height) * H / scale,
                                    b.size.width * W / scale, b.size.height * H / scale);
            [out appendFormat:@"\"%@\" conf %.2f box %.0f,%.0f %.0fx%.0f\n",
                [text string], [text confidence], box.origin.x, box.origin.y, box.size.width, box.size.height];
            [items addObject:@{ @"text": [text string], @"conf": @([text confidence]),
                                @"frame": @[@(box.origin.x), @(box.origin.y), @(box.size.width), @(box.size.height)] }];
        }
        if (json) {
            NSData *d = [NSJSONSerialization dataWithJSONObject:items options:0 error:nil];
            NSString *itemsJson = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"[]";
            return [NSString stringWithFormat:@"{\"ok\":true,\"captureMs\":%.0f,\"ocrMs\":%.0f,\"safeTop\":%.0f,\"items\":%@}\n",
                captureMs, ocrMs, safeTop, itemsJson];
        }
        return [NSString stringWithFormat:@"OCR %@ scale %g: capture %.0f ms, ocr %.0f ms, %.0fx%.0f px, %lu strings, mem %ld->%ld MB\n%@",
            accurate ? @"accurate" : @"fast", scale, captureMs, ocrMs, W, H, (unsigned long)results.count, memBefore, rc_footprint(), out];
    });
    if (!reply) return json ? @"{\"ok\":false,\"error\":\"OCR timed out after 15 s\"}\n" : [NSString stringWithFormat:@"Error: OCR timed out after 15 s (capture %.0f ms)\n", captureMs];
    return reply;
}

// A w x h grayscale thumbnail of `r` in `img` (for the residual below)
static void rc_gray_thumb(CGImageRef img, CGRect r, uint8_t *buf, size_t w, size_t h) {
    CGImageRef sub = CGImageCreateWithImageInRect(img, r);
    CGContextRef cx = CGBitmapContextCreate(buf, w, h, 8, w, CGColorSpaceCreateDeviceGray(), 0);
    CGContextDrawImage(cx, CGRectMake(0, 0, w, h), sub);
    CGContextRelease(cx);
    CGImageRelease(sub);
}

// Mean |old - new| over the band overlap after a shift of `dy` points (0-255; ~0 = the pair
// really moved, big = the registration matched things that don't actually line up)
static unsigned rc_shift_residual(CGImageRef oldImg, CGImageRef newImg, double dy) {
    const size_t W = 100, H = 300;
    static uint8_t a[100 * 300], b[100 * 300];
    size_t imgW = CGImageGetWidth(newImg), imgH = CGImageGetHeight(newImg);
    CGRect oldR = CGRectMake(0, imgH * 0.2, imgW, imgH * 0.6), newR = oldR;
    if (dy < 0) { oldR.origin.y += -dy; newR.size.height += dy; oldR.size.height += dy; }
    else { newR.origin.y += dy; newR.size.height -= dy; oldR.size.height -= dy; }
    if (oldR.size.height < 10 || newR.size.height < 10) return 255;
    rc_gray_thumb(oldImg, oldR, a, W, H);
    rc_gray_thumb(newImg, newR, b, W, H);
    unsigned long long sum = 0;
    for (size_t i = 0; i < W * H; i++) sum += a[i] > b[i] ? a[i] - b[i] : b[i] - a[i];
    return (unsigned)(sum / (W * H));
}

// screen shift [reset]: dx/dy the screen moved since the last capture (middle band only)
static NSString *rc_screen_shift(NSString *arg) {
    static UIImage *baseline;
    BOOL json = [arg containsString:@"--json"];
    if ([arg containsString:@"reset"]) { baseline = nil; return @"shift: baseline cleared\n"; }
    if (!rc_vision()) return @"Error: Vision couldn't load\n";
    dispatch_semaphore_t busy = rc_vision_busy();
    if (dispatch_semaphore_wait(busy, DISPATCH_TIME_NOW) != 0)
        return json ? @"{\"ok\":false,\"error\":\"busy\"}\n" : @"Error: busy - an OCR or shift is already running\n";
    UIImage *shot = rc_screen_grab(1);
    if (!shot) { dispatch_semaphore_signal(busy); return json ? @"{\"ok\":false,\"error\":\"Couldn't capture the screen\"}\n" : @"Error: Couldn't capture the screen\n"; }
    if (!baseline) {
        baseline = shot;
        dispatch_semaphore_signal(busy);
        return json ? @"{\"ok\":true,\"baseline\":true}\n"
                    : [NSString stringWithFormat:@"shift: baseline (%zux%zu px)\n", CGImageGetWidth(shot.CGImage), CGImageGetHeight(shot.CGImage)];
    }
    UIImage *base = baseline; // the block keeps both images - bands are made and freed inside it
    NSString *reply = rc_vision_run(busy, 15, ^{
        CGImageRef oldImg = base.CGImage, newImg = shot.CGImage;
        CGRect band = CGRectMake(0, CGImageGetHeight(newImg) * 0.2, CGImageGetWidth(newImg), CGImageGetHeight(newImg) * 0.6);
        CGImageRef oldBand = CGImageCreateWithImageInRect(oldImg, band);
        CGImageRef newBand = CGImageCreateWithImageInRect(newImg, band);
        double t0 = CFAbsoluteTimeGetCurrent();
        Class ReqClass = NSClassFromString(@"VNTranslationalImageRegistrationRequest"), HandlerClass = NSClassFromString(@"VNImageRequestHandler");
        id req = [[ReqClass alloc] initWithTargetedCGImage:newBand options:@{}];
        id handler = [[HandlerClass alloc] initWithCGImage:oldBand options:@{}];
        NSError *error = nil;
        [handler performRequests:@[req] error:&error];
        double ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000;
        CGImageRelease(oldBand);
        CGImageRelease(newBand);
        if (error) return json ? [NSString stringWithFormat:@"{\"ok\":false,\"error\":%@}\n", rc_json_str(error.localizedDescription)]
                               : [NSString stringWithFormat:@"Error: %@\n", error.localizedDescription];
        id obs = [[req results] firstObject];
        if (!obs) return json ? @"{\"ok\":false,\"error\":\"no registration result\"}\n" : @"Error: no registration result\n";
        CGAffineTransform t = [obs alignmentTransform];
        unsigned residual = rc_shift_residual(oldImg, newImg, t.ty);
        baseline = shot; // a good pair becomes the new baseline; a failed one doesn't
        if (json) return [NSString stringWithFormat:@"{\"ok\":true,\"dx\":%.1f,\"dy\":%.1f,\"residual\":%u,\"ms\":%.0f}\n", t.tx, t.ty, residual, ms];
        return [NSString stringWithFormat:@"shift: dx %.1f dy %.1f points (%.0f ms) residual %u\n", t.tx, t.ty, ms, residual];
    });
    if (!reply) return json ? @"{\"ok\":false,\"error\":\"registration timed out\"}\n" : @"Error: registration timed out after 15 s\n";
    return reply;
}

NSString *RCScreenCommand(NSString *cmd) {
    NSString *rest = [cmd substringFromIndex:MIN(cmd.length, (NSUInteger)7)]; // after "screen "
    NSRange space = [rest rangeOfString:@" "];
    NSString *verb = (space.location == NSNotFound ? rest : [rest substringToIndex:space.location]).lowercaseString;
    NSString *arg = space.location == NSNotFound ? @"" : [rest substringFromIndex:space.location + 1];
    if ([verb isEqualToString:@"capture"]) {
        // screen capture [PATH] [SCALE] [QUALITY]
        NSArray *words = [arg componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        NSString *path = words.count > 0 && [words[0] hasPrefix:@"/"] ? words[0] : @"/var/mobile/tmp/rc-screen.jpg";
        NSUInteger next = words.count > 0 && [words[0] hasPrefix:@"/"] ? 1 : 0;
        double scale = words.count > next ? MIN(MAX([words[next] doubleValue], 0.1), 1) : 0.5;
        double quality = words.count > next + 1 ? MIN(MAX([words[next + 1] doubleValue], 0.1), 1) : 0.6;
        if (!rc_capture_path_ok(path)) return @"Error: Use a path in /var/mobile/tmp or /tmp\n";
        return rc_screen_capture(path, scale, quality);
    }
    if ([verb isEqualToString:@"ocr"] || [verb isEqualToString:@"shift"]) {
        // Same as the reads below: never block the main thread on this
        if ([NSThread isMainThread]) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ RCScreenCommand(cmd); });
            return [NSString stringWithFormat:@"Started: screen %@ %@\n", verb, arg];
        }
        return [verb isEqualToString:@"ocr"] ? rc_screen_ocr(arg) : rc_screen_shift(arg);
    }
    double seconds = 10;
    NSString *text = rc_screen_text(arg, &seconds);
    if (![@[@"tap", @"wait", @"scroll-to"] containsObject:verb] || !text.length) {
        return @"Usage: screen tap \"Text\" | screen wait \"Text\" [SECONDS] | screen scroll-to \"Text\" | screen ocr [fast|accurate] [SCALE] [--json] | screen shift [reset] [--json]\n";
    }
    seconds = MIN(MAX(seconds, 0.5), 120);
    // rc-screen asks SpringBoard for the screen, which its main thread answers: waiting for it
    // there would never end. From the main thread it runs on its own and the reply is early.
    if ([NSThread isMainThread]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ RCScreenCommand(cmd); });
        return [NSString stringWithFormat:@"Started: screen %@ \"%@\"\n", verb, text];
    }
    NSString *output = nil;
    int code;
    if ([verb isEqualToString:@"tap"]) {
        // Pressed as VoiceOver does; a real touch if that doesn't work
        code = rc_screen_run(@[@"press", text], 15, &output);
        if (code == 2) code = rc_screen_run(@[@"tap", text], 15, &output);
    } else if ([verb isEqualToString:@"wait"]) {
        code = rc_screen_run(@[@"wait", text, [NSString stringWithFormat:@"%g", seconds]], seconds + 15, &output);
    } else {
        code = rc_screen_run(@[@"scroll-to", text], 90, &output);
    }
    SRLog(@"[Screen] screen %@ \"%@\": exit %d, %@", verb, text, code, output);
    if (code == 0) return [output stringByAppendingString:@"\n"];
    return [NSString stringWithFormat:@"Error: %@\n", output.length ? output : @"rc-screen failed"];
}
