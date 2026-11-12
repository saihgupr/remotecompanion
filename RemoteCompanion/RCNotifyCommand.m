#import "RCNotifyCommand.h"

@implementation RCNotifyCommand

+ (BOOL)isNotifyCommand:(NSString *)command {
    return [command isKindOfClass:[NSString class]] && [command hasPrefix:@"notify "] && ![command isEqualToString:@"notify clear"];
}

+ (NSString *)newID {
    return [[[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:10].lowercaseString;
}

static NSString *RCTrim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+ (instancetype)commandWithString:(NSString *)command {
    RCNotifyCommand *c = [[RCNotifyCommand alloc] init];
    c.title = @""; c.message = @""; c.buttons = @[];
    if (![self isNotifyCommand:command]) return c;
    NSString *args = RCTrim([command substringFromIndex:7]);
    static NSRegularExpression *removeOption, *tapOption, *imageOption, *imageURLOption, *buttonOption, *waitOption;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        removeOption = [NSRegularExpression regularExpressionWithPattern:@"(^|\\s)--remove-after\\s+(\\d+(\\.\\d+)?)$" options:0 error:nil];
        tapOption = [NSRegularExpression regularExpressionWithPattern:@"(^|\\s)--tap\\s+([A-Za-z0-9_-]+)$" options:0 error:nil];
        imageOption = [NSRegularExpression regularExpressionWithPattern:@"(^|\\s)--image\\s+(?:\"([^\"]*)\"|(\\S+))$" options:0 error:nil];
        imageURLOption = [NSRegularExpression regularExpressionWithPattern:@"(^|\\s)--image-url\\s+(?:\"([^\"]*)\"|(\\S+))$" options:0 error:nil];
        waitOption = [NSRegularExpression regularExpressionWithPattern:@"(^|\\s)--wait\\s+(\\d+(\\.\\d+)?)$" options:0 error:nil];
        buttonOption = [NSRegularExpression regularExpressionWithPattern:@"(^|\\s)--button\\s+\"([^\"]*)\"$" options:0 error:nil];
    });
    NSMutableArray *buttons = [NSMutableArray array];
    // Options come after the text, in any order; read from the end
    for (BOOL found = YES; found; ) {
        found = NO;
        if ([args hasSuffix:@"--urgent"]) {
            c.urgent = YES;
            args = RCTrim([args substringToIndex:args.length - 8]);
            found = YES;
        }
        NSTextCheckingResult *m;
        if ((m = [removeOption firstMatchInString:args options:0 range:NSMakeRange(0, args.length)])) {
            c.removeAfter = (NSInteger)llround([[args substringWithRange:[m rangeAtIndex:2]] doubleValue]);
            args = RCTrim([args substringToIndex:m.range.location]); found = YES;
        }
        if ((m = [waitOption firstMatchInString:args options:0 range:NSMakeRange(0, args.length)])) {
            c.wait = (NSInteger)llround([[args substringWithRange:[m rangeAtIndex:2]] doubleValue]);
            args = RCTrim([args substringToIndex:m.range.location]); found = YES;
        }
        if ((m = [tapOption firstMatchInString:args options:0 range:NSMakeRange(0, args.length)])) {
            c.tapID = [args substringWithRange:[m rangeAtIndex:2]];
            args = RCTrim([args substringToIndex:m.range.location]); found = YES;
        }
        if ((m = [imageOption firstMatchInString:args options:0 range:NSMakeRange(0, args.length)])) {
            NSRange quoted = [m rangeAtIndex:2], plain = [m rangeAtIndex:3];
            NSString *image = quoted.location != NSNotFound ? [args substringWithRange:quoted] : [args substringWithRange:plain];
            c.image = image.length ? image : nil;
            args = RCTrim([args substringToIndex:m.range.location]); found = YES;
        }
        if ((m = [imageURLOption firstMatchInString:args options:0 range:NSMakeRange(0, args.length)])) {
            NSRange quoted = [m rangeAtIndex:2], plain = [m rangeAtIndex:3];
            NSString *imageURL = quoted.location != NSNotFound ? [args substringWithRange:quoted] : [args substringWithRange:plain];
            c.imageURL = imageURL.length ? imageURL : nil;
            args = RCTrim([args substringToIndex:m.range.location]); found = YES;
        }
        if ((m = [buttonOption firstMatchInString:args options:0 range:NSMakeRange(0, args.length)])) {
            // "ID|Name|flags": the ID ends at the first bar, the flags start after the last one (when
            // they are flags), and the name, between them, may hold bars of its own
            NSString *spec = [args substringWithRange:[m rangeAtIndex:2]];
            NSRange first = [spec rangeOfString:@"|"];
            if (first.location != NSNotFound && first.location > 0) {
                NSString *rest = [spec substringFromIndex:NSMaxRange(first)];
                NSArray *flags = @[];
                NSRange last = [rest rangeOfString:@"|" options:NSBackwardsSearch];
                if (last.location != NSNotFound) {
                    NSArray *tail = [[rest substringFromIndex:NSMaxRange(last)] componentsSeparatedByString:@","];
                    if ([[NSSet setWithArray:tail] isSubsetOfSet:[NSSet setWithArray:@[@"red", @"unlock", @""]]]) {
                        flags = tail;
                        rest = [rest substringToIndex:last.location];
                    }
                }
                [buttons insertObject:@{ @"id": [spec substringToIndex:first.location], @"title": rest, @"red": @([flags containsObject:@"red"]), @"unlock": @([flags containsObject:@"unlock"]) } atIndex:0];
            }
            args = RCTrim([args substringToIndex:m.range.location]); found = YES;
        }
    }
    c.buttons = buttons;
    if ([args hasPrefix:@"\""]) {
        NSRange end = [args rangeOfString:@"\"" options:0 range:NSMakeRange(1, args.length - 1)];
        c.title = end.location == NSNotFound ? [args substringFromIndex:1] : [args substringWithRange:NSMakeRange(1, end.location - 1)];
        NSString *rest = end.location == NSNotFound ? @"" : RCTrim([args substringFromIndex:end.location + 1]);
        if ([rest hasPrefix:@"\""]) rest = [rest substringFromIndex:1];
        if ([rest hasSuffix:@"\""]) rest = [rest substringToIndex:rest.length - 1];
        c.message = rest;
    } else if (args.length) {
        NSRange space = [args rangeOfString:@" "];
        c.title = space.location == NSNotFound ? args : [args substringToIndex:space.location];
        c.message = space.location == NSNotFound ? @"" : [args substringFromIndex:space.location + 1];
    }
    return c;
}

// The command has no escapes: a double quote becomes a curly one
static NSString *RCQuotable(NSString *s) {
    return [(s ?: @"") stringByReplacingOccurrencesOfString:@"\"" withString:@"”"];
}

- (NSString *)string {
    NSMutableString *cmd = [NSMutableString stringWithFormat:@"notify \"%@\" \"%@\"", RCQuotable(self.title.length ? self.title : @"RemoteCompanion"), RCQuotable(self.message)];
    if (self.urgent) [cmd appendString:@" --urgent"];
    if (self.removeAfter > 0) [cmd appendFormat:@" --remove-after %ld", (long)self.removeAfter];
    if (self.image.length) [cmd appendFormat:@" --image \"%@\"", RCQuotable(self.image)];
    if (self.imageURL.length) [cmd appendFormat:@" --image-url \"%@\"", RCQuotable(self.imageURL)];
    if (self.tapID.length) [cmd appendFormat:@" --tap %@", self.tapID];
    NSUInteger count = 0;
    for (NSDictionary *button in self.buttons) {
        NSString *title = RCQuotable(button[@"title"]);
        if (![button[@"id"] length] || !title.length || count++ >= 4) continue;
        NSMutableArray *flags = [NSMutableArray array];
        if ([button[@"red"] boolValue]) [flags addObject:@"red"];
        if ([button[@"unlock"] boolValue]) [flags addObject:@"unlock"];
        [cmd appendFormat:@" --button \"%@|%@|%@\"", button[@"id"], title, [flags componentsJoinedByString:@","]];
    }
    if (self.wait > 0) [cmd appendFormat:@" --wait %ld", (long)self.wait];
    return cmd;
}

+ (NSString *)responseVariableIn:(NSArray *)actions {
    for (id item in actions ?: @[]) {
        NSString *command = [item isKindOfClass:[NSString class]] ? item : ([item isKindOfClass:[NSDictionary class]] ? item[@"command"] : nil);
        if ([self isNotifyCommand:command] && [self commandWithString:command].wait > 0) return @"notify_response";
    }
    return nil;
}

+ (id)copyOfActionWithNewIDs:(id)item {
    NSString *command = [item isKindOfClass:[NSString class]] ? item : ([item isKindOfClass:[NSDictionary class]] ? item[@"command"] : nil);
    if (![self isNotifyCommand:command]) return [item copy];
    RCNotifyCommand *notify = [self commandWithString:command];
    if (notify.tapID.length) notify.tapID = [self newID];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSDictionary *button in notify.buttons) {
        NSMutableDictionary *b = [button mutableCopy];
        b[@"id"] = [self newID];
        [buttons addObject:b];
    }
    notify.buttons = buttons;
    if ([item isKindOfClass:[NSString class]]) return notify.string;
    NSMutableDictionary *d = [item mutableCopy];
    d[@"command"] = notify.string;
    return d;
}

@end
