#import "RCScreen.h"
#import "RCSpawn.h"

void SRLog(NSString *format, ...);

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
