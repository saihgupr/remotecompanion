#import "RCHTTPAction.h"

static NSString *const kRCHTTPActionPrefix = @"http-request ";
static NSString *const kRCHTTPActionName = @"http-request";

static NSString *RCHTTPTrimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@implementation RCHTTPAction

+ (NSString *)actionStringWithMethod:(NSString *)method
                                 url:(NSString *)url
                             headers:(NSDictionary<NSString *,NSString *> *)headers
                                body:(NSString *)body {
    NSString *cleanMethod = [RCHTTPTrimmed(method ?: @"") uppercaseString];
    if (cleanMethod.length == 0) cleanMethod = @"GET";

    NSMutableDictionary *request = [NSMutableDictionary dictionary];
    request[@"method"] = cleanMethod;
    request[@"url"] = RCHTTPTrimmed(url ?: @"");

    if (headers.count > 0) {
        request[@"headers"] = headers;
    }
    NSString *cleanBody = body ?: @"";
    if (cleanBody.length > 0) {
        request[@"body"] = cleanBody;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:request
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"";
    return [kRCHTTPActionPrefix stringByAppendingString:text ?: @""];
}

+ (NSDictionary *)componentsFromActionString:(NSString *)action {
    if (![action isKindOfClass:[NSString class]]) return nil;
    NSString *text = RCHTTPTrimmed(action);
    if ([text isEqualToString:kRCHTTPActionName]) return nil;
    if (![text hasPrefix:kRCHTTPActionPrefix] && ![text hasPrefix:[kRCHTTPActionName stringByAppendingString:@"\t"]]) return nil;
    NSString *payload = RCHTTPTrimmed([text substringFromIndex:kRCHTTPActionName.length]);

    id parsed = nil;
    if ([payload hasPrefix:@"http://"] || [payload hasPrefix:@"https://"]) {
        parsed = @{ @"url": payload };
    } else {
        parsed = [NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding]
                                                 options:0
                                                   error:nil];
    }
    if (![parsed isKindOfClass:[NSDictionary class]]) return nil;

    NSDictionary *request = (NSDictionary *)parsed;
    NSString *url = [request[@"url"] description];
    if (url.length == 0) return nil;

    NSString *method = [[request[@"method"] description] uppercaseString];
    if (method.length == 0) method = @"GET";

    NSMutableDictionary *components = [NSMutableDictionary dictionary];
    components[@"method"] = method;
    components[@"url"] = RCHTTPTrimmed(url);

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if ([request[@"headers"] isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)request[@"headers"]) {
            id value = ((NSDictionary *)request[@"headers"])[key];
            if ([value isKindOfClass:[NSString class]]) {
                headers[[key description]] = value;
            } else if (value && ![value isKindOfClass:[NSNull class]]) {
                headers[[key description]] = [value description];
            }
        }
    }
    components[@"headers"] = headers;

    NSString *body = @"";
    id rawBody = request[@"body"];
    if ([rawBody isKindOfClass:[NSString class]]) {
        body = rawBody;
    } else if (rawBody && ![rawBody isKindOfClass:[NSNull class]]) {
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:rawBody
                                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                             error:nil];
        if (bodyData) body = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] ?: @"";
    }
    components[@"body"] = body;
    return components;
}

+ (NSDictionary<NSString *,NSString *> *)headersFromLines:(NSString *)text
                                              invalidLine:(NSString *__autoreleasing *)invalidLine {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (invalidLine) *invalidLine = nil;

    for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = RCHTTPTrimmed(rawLine);
        if (line.length == 0 || [line hasPrefix:@"#"]) continue;

        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            if (invalidLine) *invalidLine = line;
            return nil;
        }
        NSString *name = RCHTTPTrimmed([line substringToIndex:colon.location]);
        NSString *value = RCHTTPTrimmed([line substringFromIndex:colon.location + 1]);
        if (name.length == 0) {
            if (invalidLine) *invalidLine = line;
            return nil;
        }
        headers[name] = value;
    }
    return headers;
}

+ (NSString *)linesFromHeaders:(NSDictionary<NSString *,NSString *> *)headers {
    if (![headers isKindOfClass:[NSDictionary class]] || headers.count == 0) return @"";
    NSArray *names = [[headers allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *name in names) {
        [lines addObject:[NSString stringWithFormat:@"%@: %@", name, headers[name] ?: @""]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

@end
