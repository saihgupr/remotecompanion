#import "RCScreen.h"
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <limits.h>
#import <stdlib.h>

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
    if (![verb isEqualToString:@"capture"]) return @"Usage: screen capture [PATH] [SCALE] [QUALITY] [grid [SPACING]] | screen settle [MAX]\n";
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
