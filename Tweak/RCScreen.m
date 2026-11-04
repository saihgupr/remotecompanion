#import "RCScreen.h"
#import "RCSpawn.h"
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <notify.h>

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
    double seconds = 10;
    NSString *text = rc_screen_text(arg, &seconds);
    if (![@[@"tap", @"wait", @"scroll-to"] containsObject:verb] || !text.length) {
        return @"Usage: screen tap \"Text\" | screen wait \"Text\" [SECONDS] | screen scroll-to \"Text\"\n";
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
