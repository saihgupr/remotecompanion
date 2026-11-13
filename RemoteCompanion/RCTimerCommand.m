#import "RCTimerCommand.h"

static NSArray<NSString *> *rc_timer_tokenize(NSString *raw) {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL inDouble = NO;
    BOOL inSingle = NO;
    BOOL hasToken = NO;

    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex:i];
        if (inDouble) {
            if (c == '\\' && i + 1 < raw.length) {
                unichar next = [raw characterAtIndex:i + 1];
                if (next == '"' || next == '\\') {
                    [current appendFormat:@"%C", next];
                    i++;
                    continue;
                }
            }
            if (c == '"') {
                inDouble = NO;
            } else {
                [current appendFormat:@"%C", c];
            }
            continue;
        }
        if (inSingle) {
            if (c == '\'') {
                inSingle = NO;
            } else {
                [current appendFormat:@"%C", c];
            }
            continue;
        }
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) {
            if (hasToken) {
                [tokens addObject:[current copy]];
                [current setString:@""];
                hasToken = NO;
            }
            continue;
        }
        hasToken = YES;
        if (c == '"') {
            inDouble = YES;
        } else if (c == '\'') {
            inSingle = YES;
        } else {
            [current appendFormat:@"%C", c];
        }
    }
    if (hasToken) {
        [tokens addObject:[current copy]];
    }
    return tokens;
}

static NSString *rc_timer_quote_arg(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

static NSString *rc_timer_action_keyword(RCTimerActionType action) {
    switch (action) {
        case RCTimerActionStop: return @"stop";
        case RCTimerActionPause: return @"pause";
        case RCTimerActionResume: return @"resume";
        case RCTimerActionStatus: return @"status";
        case RCTimerActionStart:
        default: return @"start";
    }
}

static BOOL rc_timer_parse_nonneg_double(NSString *s, double *outVal) {
    if (s.length == 0) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
    if ([[s stringByTrimmingCharactersInSet:allowed] length] > 0) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    double val = 0;
    if (![scanner scanDouble:&val] || !scanner.isAtEnd || !isfinite(val) || val < 0) return NO;
    if (outVal) *outVal = val;
    return YES;
}

@implementation RCTimerCommand

+ (BOOL)isTimerCommand:(NSString *)command {
    if (![command isKindOfClass:[NSString class]]) return NO;
    NSString *low = [[command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [low isEqualToString:@"timer"] || [low hasPrefix:@"timer "];
}

+ (BOOL)containsVariable:(NSString *)expr {
    if (![expr isKindOfClass:[NSString class]]) return NO;
    return [expr rangeOfString:@"{"].location != NSNotFound && [expr rangeOfString:@"}"].location != NSNotFound;
}

+ (double)parseDurationSeconds:(NSString *)expr {
    if (![expr isKindOfClass:[NSString class]]) return -1;
    NSString *trimmed = [[expr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (trimmed.length == 0 || [trimmed rangeOfString:@"{"].location != NSNotFound) return -1;

    // Colon notation: MM:SS or HH:MM:SS
    if ([trimmed rangeOfString:@":"].location != NSNotFound) {
        if ([trimmed rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) return -1;
        NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@":"];
        if (parts.count == 2) {
            double mins = 0, secs = 0;
            if (!rc_timer_parse_nonneg_double(parts[0], &mins) || floor(mins) != mins) return -1;
            if (!rc_timer_parse_nonneg_double(parts[1], &secs) || secs >= 60.0) return -1;
            double total = mins * 60.0 + secs;
            return total > 0 ? total : -1;
        }
        if (parts.count == 3) {
            double hrs = 0, mins = 0, secs = 0;
            if (!rc_timer_parse_nonneg_double(parts[0], &hrs) || floor(hrs) != hrs) return -1;
            if (!rc_timer_parse_nonneg_double(parts[1], &mins) || floor(mins) != mins || mins >= 60.0) return -1;
            if (!rc_timer_parse_nonneg_double(parts[2], &secs) || secs >= 60.0) return -1;
            double total = hrs * 3600.0 + mins * 60.0 + secs;
            return total > 0 ? total : -1;
        }
        return -1;
    }

    // Remove whitespace between components so "1h 30m" and "1h30m" parse identically
    NSString *compact = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    if (compact.length == 0) return -1;

    // Plain numeric seconds
    double plainSecs = 0;
    if (rc_timer_parse_nonneg_double(compact, &plainSecs)) {
        return plainSecs > 0 ? plainSecs : -1;
    }

    // Unit sequence: e.g. 1h30m, 20m, 45s, 1.5h, 20min
    static NSRegularExpression *partRegex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        partRegex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+(?:\\.\\d+)?)(hours|hour|hrs|hr|h|minutes|minute|mins|min|m|seconds|second|secs|sec|s)" options:0 error:nil];
    });

    NSArray<NSTextCheckingResult *> *matches = [partRegex matchesInString:compact options:0 range:NSMakeRange(0, compact.length)];
    if (matches.count == 0) return -1;

    NSUInteger cursor = 0;
    double total = 0;
    for (NSTextCheckingResult *m in matches) {
        if (m.range.location != cursor) return -1;
        cursor = NSMaxRange(m.range);
        NSString *numStr = [compact substringWithRange:[m rangeAtIndex:1]];
        NSString *unit = [compact substringWithRange:[m rangeAtIndex:2]];
        double val = 0;
        if (!rc_timer_parse_nonneg_double(numStr, &val)) return -1;
        if ([unit hasPrefix:@"h"]) {
            total += val * 3600.0;
        } else if ([unit hasPrefix:@"m"]) {
            total += val * 60.0;
        } else {
            total += val;
        }
    }
    if (cursor != compact.length) return -1;
    return total > 0 ? total : -1;
}

+ (NSString *)compactTokenForSeconds:(NSInteger)seconds {
    NSInteger clamped = MAX(1, seconds);
    NSInteger h = clamped / 3600;
    NSInteger m = (clamped % 3600) / 60;
    NSInteger s = clamped % 60;
    NSMutableString *out = [NSMutableString string];
    if (h > 0) [out appendFormat:@"%ldh", (long)h];
    if (m > 0) [out appendFormat:@"%ldm", (long)m];
    if (s > 0 || out.length == 0) [out appendFormat:@"%lds", (long)s];
    return out;
}

+ (NSString *)displayDurationForSeconds:(double)seconds {
    if (seconds > 0 && seconds < 1.0) {
        return [NSString stringWithFormat:@"%.1fs", seconds];
    }
    NSInteger total = (NSInteger)llround(seconds);
    if (total <= 0) return @"0s";
    NSInteger h = total / 3600;
    NSInteger m = (total % 3600) / 60;
    NSInteger s = total % 60;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (h > 0) [parts addObject:[NSString stringWithFormat:@"%ldh", (long)h]];
    if (m > 0) [parts addObject:[NSString stringWithFormat:@"%ldm", (long)m]];
    if (s > 0 || parts.count == 0) [parts addObject:[NSString stringWithFormat:@"%lds", (long)s]];
    return [parts componentsJoinedByString:@" "];
}

+ (instancetype)commandWithString:(NSString *)command {
    if (![self isTimerCommand:command]) return nil;
    NSString *trimmed = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *tokens = rc_timer_tokenize(trimmed);
    if (tokens.count == 0 || ![[tokens[0] lowercaseString] isEqualToString:@"timer"]) return nil;

    if (tokens.count == 1) {
        return [[self alloc] initWithAction:RCTimerActionStatus durationExpression:nil label:nil];
    }

    RCTimerActionType action = RCTimerActionStart;
    NSUInteger idx = 1;
    NSString *firstLow = [tokens[1] lowercaseString];
    if ([firstLow isEqualToString:@"start"] || [firstLow isEqualToString:@"set"]) {
        action = RCTimerActionStart;
        idx = 2;
    } else if ([firstLow isEqualToString:@"stop"] || [firstLow isEqualToString:@"cancel"] ||
               [firstLow isEqualToString:@"off"] || [firstLow isEqualToString:@"dismiss"]) {
        action = RCTimerActionStop;
        idx = 2;
    } else if ([firstLow isEqualToString:@"pause"]) {
        action = RCTimerActionPause;
        idx = 2;
    } else if ([firstLow isEqualToString:@"resume"]) {
        action = RCTimerActionResume;
        idx = 2;
    } else if ([firstLow isEqualToString:@"status"]) {
        action = RCTimerActionStatus;
        idx = 2;
    }

    NSMutableArray<NSString *> *positional = [NSMutableArray array];
    NSString *label = nil;
    NSString *parseError = nil;

    while (idx < tokens.count) {
        NSString *tok = tokens[idx];
        NSString *low = [tok lowercaseString];
        if ([low isEqualToString:@"--label"] || [low isEqualToString:@"-l"] || [low isEqualToString:@"--title"] || [low isEqualToString:@"-t"]) {
            if (idx + 1 >= tokens.count) {
                parseError = @"Missing value after --label";
                break;
            }
            label = tokens[idx + 1];
            idx += 2;
            continue;
        }
        if ([low hasPrefix:@"--label="]) {
            label = [tok substringFromIndex:8];
            idx++;
            continue;
        }
        if ([low hasPrefix:@"--title="]) {
            label = [tok substringFromIndex:8];
            idx++;
            continue;
        }
        [positional addObject:tok];
        idx++;
    }

    NSString *durationExpr = nil;
    if (action == RCTimerActionStart) {
        if (positional.count == 0) {
            parseError = parseError ?: @"Missing timer duration";
        } else {
            // Join multi-token duration phrases like "1h" "30m" before any unknown args
            durationExpr = [positional componentsJoinedByString:@" "];
            if (![self containsVariable:durationExpr] && [self parseDurationSeconds:durationExpr] <= 0) {
                parseError = parseError ?: [NSString stringWithFormat:@"Invalid timer duration: %@", durationExpr];
            }
        }
    } else if (positional.count > 0 && label.length == 0) {
        label = [positional componentsJoinedByString:@" "];
    } else if (positional.count > 0) {
        parseError = parseError ?: [NSString stringWithFormat:@"Unexpected argument: %@", positional.firstObject];
    }

    RCTimerCommand *cmd = [[self alloc] initWithAction:action durationExpression:durationExpr label:label];
    cmd.parseError = parseError;
    return cmd;
}

- (instancetype)initWithAction:(RCTimerActionType)action
            durationExpression:(NSString *)durationExpression
                         label:(NSString *)label {
    self = [super init];
    if (self) {
        _action = action;
        NSString *trimDur = [durationExpression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _durationExpression = trimDur.length > 0 ? [trimDur copy] : nil;
        NSString *trimLbl = [label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _label = trimLbl.length > 0 ? [trimLbl copy] : nil;
    }
    return self;
}

- (NSString *)string {
    NSMutableString *out = [NSMutableString stringWithString:@"timer"];
    if (self.action == RCTimerActionStart) {
        NSString *expr = self.durationExpression ?: @"5m";
        if (![RCTimerCommand containsVariable:expr]) {
            double secs = [RCTimerCommand parseDurationSeconds:expr];
            if (secs > 0) {
                if (fabs(secs - round(secs)) < 0.001) {
                    expr = [RCTimerCommand compactTokenForSeconds:(NSInteger)llround(secs)];
                } else {
                    expr = [NSString stringWithFormat:@"%gs", secs];
                }
            }
        }
        if ([expr rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location != NSNotFound) {
            [out appendFormat:@" %@", rc_timer_quote_arg(expr)];
        } else {
            [out appendFormat:@" %@", expr];
        }
    } else {
        [out appendFormat:@" %@", rc_timer_action_keyword(self.action)];
    }

    if (self.label.length > 0) {
        [out appendFormat:@" --label %@", rc_timer_quote_arg(self.label)];
    }
    return out;
}

- (NSString *)displayDuration {
    if (self.durationExpression.length == 0) return @"";
    if ([RCTimerCommand containsVariable:self.durationExpression]) {
        return self.durationExpression;
    }
    double secs = [RCTimerCommand parseDurationSeconds:self.durationExpression];
    if (secs > 0) return [RCTimerCommand displayDurationForSeconds:secs];
    return self.durationExpression;
}

- (NSString *)actionTitle {
    switch (self.action) {
        case RCTimerActionStop: return @"Stop Timer";
        case RCTimerActionPause: return @"Pause Timer";
        case RCTimerActionResume: return @"Resume Timer";
        case RCTimerActionStatus: return @"Timer Status";
        case RCTimerActionStart:
        default: return @"Start Timer";
    }
}

- (NSString *)actionAccentText {
    if (self.action == RCTimerActionStart) {
        NSString *dur = [self displayDuration];
        return dur.length > 0 ? dur : nil;
    }
    return self.label.length > 0 ? self.label : nil;
}

- (NSString *)actionDetailText {
    if (self.action == RCTimerActionStart && self.label.length > 0) {
        return [NSString stringWithFormat:@"Label: %@", self.label];
    }
    return nil;
}

- (NSString *)singleLineSummary {
    if (self.action == RCTimerActionStart) {
        NSString *dur = [self displayDuration];
        if (dur.length > 0 && self.label.length > 0) {
            return [NSString stringWithFormat:@"Start Timer %@ (%@)", dur, self.label];
        }
        if (dur.length > 0) {
            return [NSString stringWithFormat:@"Start Timer %@", dur];
        }
        return @"Start Timer";
    }
    NSString *title = [self actionTitle];
    if (self.label.length > 0) {
        return [NSString stringWithFormat:@"%@ (%@)", title, self.label];
    }
    return title;
}

- (NSString *)bannerSubtitle {
    if (self.action == RCTimerActionStart) {
        NSString *dur = [self displayDuration];
        if (dur.length > 0 && self.label.length > 0) {
            return [NSString stringWithFormat:@"%@ · %@", dur, self.label];
        }
        return dur.length > 0 ? dur : self.label;
    }
    NSString *verb = nil;
    switch (self.action) {
        case RCTimerActionStop: verb = @"Stopped"; break;
        case RCTimerActionPause: verb = @"Paused"; break;
        case RCTimerActionResume: verb = @"Resumed"; break;
        case RCTimerActionStatus: verb = @"Status"; break;
        default: break;
    }
    if (self.label.length > 0 && verb) {
        return [NSString stringWithFormat:@"%@ · %@", verb, self.label];
    }
    return verb;
}

@end

