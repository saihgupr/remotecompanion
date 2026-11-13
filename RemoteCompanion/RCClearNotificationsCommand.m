#import "RCClearNotificationsCommand.h"

NSString *const kRCRemoteCompanionBundleId = @"com.saihgupr.remotecompanion";

static NSString *RCTrimWhitespace(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return @"";
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSArray<NSString *> *RCClearUniqueStrings(NSArray *items, BOOL normalizeBundleId) {
    if (![items isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id raw in items) {
        if (![raw isKindOfClass:[NSString class]]) continue;
        NSString *item = [(NSString *)raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        if (normalizeBundleId) {
            item = RCTrimWhitespace(item);
        } else {
            // Skip blank/whitespace-only entries while preserving intentional phrase spacing
            if (RCTrimWhitespace(item).length == 0) continue;
        }
        if (item.length == 0) continue;
        NSString *dedupKey = normalizeBundleId ? [item lowercaseString] : item;
        if ([seen containsObject:dedupKey]) continue;
        [seen addObject:dedupKey];
        [result addObject:item];
    }
    return [result copy];
}

// Extract remaining argument text after a known command prefix, or nil if not a clear command.
static BOOL RCClearExtractPayload(NSString *command, NSString **payloadOut, BOOL *isLegacyBareNotifyClear) {
    if (payloadOut) *payloadOut = nil;
    if (isLegacyBareNotifyClear) *isLegacyBareNotifyClear = NO;
    if (![command isKindOfClass:[NSString class]]) return NO;

    NSString *trimmed = RCTrimWhitespace(command);
    NSString *lower = [trimmed lowercaseString];

    NSArray<NSString *> *prefixes = @[
        @"notify clear",
        @"clear notifications",
        @"clear notification",
        @"clear-notifications",
        @"clear-notification"
    ];

    for (NSString *prefix in prefixes) {
        if (![lower hasPrefix:prefix]) continue;
        if (trimmed.length == prefix.length) {
            if (payloadOut) *payloadOut = @"";
            if (isLegacyBareNotifyClear) *isLegacyBareNotifyClear = [prefix isEqualToString:@"notify clear"];
            return YES;
        }
        unichar next = [trimmed characterAtIndex:prefix.length];
        if (![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:next]) continue;
        if (payloadOut) {
            *payloadOut = RCTrimWhitespace([trimmed substringFromIndex:prefix.length]);
        }
        return YES;
    }
    return NO;
}

static NSArray<NSString *> *RCTokenizeClearArgs(NSString *input) {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL inDoubleQuote = NO;
    BOOL inSingleQuote = NO;
    BOOL hasToken = NO;

    for (NSUInteger i = 0; i < input.length; i++) {
        unichar c = [input characterAtIndex:i];
        if ((inDoubleQuote || c != '\'') && !inSingleQuote && c == '\\' && i + 1 < input.length) {
            unichar next = [input characterAtIndex:i + 1];
            [current appendFormat:@"%C", next];
            hasToken = YES;
            i++;
            continue;
        }
        if (c == '"' && !inSingleQuote) {
            inDoubleQuote = !inDoubleQuote;
            hasToken = YES;
            continue;
        }
        if (c == '\'' && !inDoubleQuote) {
            inSingleQuote = !inSingleQuote;
            hasToken = YES;
            continue;
        }
        if (!inDoubleQuote && !inSingleQuote && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) {
            if (hasToken) {
                [tokens addObject:[current copy]];
                [current setString:@""];
                hasToken = NO;
            }
            continue;
        }
        [current appendFormat:@"%C", c];
        hasToken = YES;
    }
    if (hasToken) {
        [tokens addObject:[current copy]];
    }
    return [tokens copy];
}

static NSString *RCNormalizeAppToken(NSString *value) {
    NSString *trimmed = RCTrimWhitespace(value);
    NSString *lower = [trimmed lowercaseString];
    if ([lower isEqualToString:@"rc"] || [lower isEqualToString:@"remotecompanion"]) {
        return kRCRemoteCompanionBundleId;
    }
    if ([lower isEqualToString:@"all"] || [lower isEqualToString:@"any"] || [lower isEqualToString:@"*"]) {
        return nil;
    }
    return trimmed.length > 0 ? trimmed : nil;
}

@implementation RCClearNotificationsCommand

+ (BOOL)isClearCommand:(NSString *)command {
    return RCClearExtractPayload(command, NULL, NULL);
}

+ (instancetype)commandWithString:(NSString *)command {
    NSString *payload = nil;
    BOOL isLegacyBare = NO;
    if (!RCClearExtractPayload(command, &payload, &isLegacyBare)) return nil;

    if (payload.length == 0) {
        NSArray<NSString *> *defaultApps = isLegacyBare ? @[kRCRemoteCompanionBundleId] : @[];
        return [[self alloc] initWithApps:defaultApps texts:@[]];
    }

    if ([payload hasPrefix:@"{"]) {
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)parsed;
            NSMutableArray *rawApps = [NSMutableArray array];
            if ([dict[@"apps"] isKindOfClass:[NSArray class]]) {
                [rawApps addObjectsFromArray:dict[@"apps"]];
            } else if ([dict[@"app"] isKindOfClass:[NSString class]]) {
                [rawApps addObject:dict[@"app"]];
            }

            NSMutableArray *rawTexts = [NSMutableArray array];
            if ([dict[@"texts"] isKindOfClass:[NSArray class]]) {
                [rawTexts addObjectsFromArray:dict[@"texts"]];
            } else if ([dict[@"text"] isKindOfClass:[NSString class]]) {
                [rawTexts addObject:dict[@"text"]];
            }

            NSMutableArray<NSString *> *normalizedApps = [NSMutableArray array];
            for (id item in rawApps) {
                if (![item isKindOfClass:[NSString class]]) continue;
                NSString *norm = RCNormalizeAppToken((NSString *)item);
                if (norm.length > 0) [normalizedApps addObject:norm];
            }
            return [[self alloc] initWithApps:normalizedApps texts:rawTexts];
        }
    }

    // CLI / flag syntax: [--all] [--app BUNDLE_OR_RC] [--text PHRASE] [PHRASE...]
    NSArray<NSString *> *tokens = RCTokenizeClearArgs(payload);
    NSMutableArray<NSString *> *apps = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];

    for (NSUInteger i = 0; i < tokens.count; i++) {
        NSString *tok = tokens[i];
        NSString *lower = [tok lowercaseString];
        if ([lower isEqualToString:@"--all"] || [lower isEqualToString:@"-a"]) {
            [apps removeAllObjects];
        } else if (([lower isEqualToString:@"--app"] || [lower isEqualToString:@"-A"]) && i + 1 < tokens.count) {
            NSString *val = tokens[++i];
            NSString *norm = RCNormalizeAppToken(val);
            if (norm) [apps addObject:norm];
            else [apps removeAllObjects];
        } else if ([lower hasPrefix:@"--app="]) {
            NSString *val = [tok substringFromIndex:6];
            NSString *norm = RCNormalizeAppToken(val);
            if (norm) [apps addObject:norm];
            else [apps removeAllObjects];
        } else if (([lower isEqualToString:@"--text"] || [lower isEqualToString:@"-t"]) && i + 1 < tokens.count) {
            NSString *val = tokens[++i];
            if (RCTrimWhitespace(val).length > 0) [texts addObject:val];
        } else if ([lower hasPrefix:@"--text="]) {
            NSString *val = [tok substringFromIndex:7];
            if (RCTrimWhitespace(val).length > 0) [texts addObject:val];
        } else if (RCTrimWhitespace(tok).length > 0) {
            [texts addObject:tok];
        }
    }

    return [[self alloc] initWithApps:apps texts:texts];
}

- (instancetype)initWithApps:(NSArray<NSString *> *)apps texts:(NSArray<NSString *> *)texts {
    self = [super init];
    if (self) {
        _apps = RCClearUniqueStrings(apps ?: @[], YES);
        _texts = RCClearUniqueStrings(texts ?: @[], NO);
    }
    return self;
}

- (NSString *)string {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self.apps.count > 0) dict[@"apps"] = self.apps;
    if (self.texts.count > 0) dict[@"texts"] = self.texts;

    NSData *json = [NSJSONSerialization dataWithJSONObject:dict
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    NSString *jsonStr = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
    return [@"notify clear " stringByAppendingString:jsonStr ?: @"{}"];
}

- (BOOL)matchesSectionID:(NSString *)sectionID
         parentSectionID:(NSString *)parentSectionID
                   title:(NSString *)title
                subtitle:(NSString *)subtitle
                 message:(NSString *)message {
    if (self.apps.count > 0) {
        NSString *sec = [sectionID isKindOfClass:[NSString class]] ? [sectionID lowercaseString] : @"";
        NSString *parent = [parentSectionID isKindOfClass:[NSString class]] ? [parentSectionID lowercaseString] : @"";
        BOOL appMatched = NO;
        for (NSString *app in self.apps) {
            NSString *target = [app lowercaseString];
            if (target.length == 0) continue;
            if ([sec isEqualToString:target] || [parent isEqualToString:target]) {
                appMatched = YES;
                break;
            }
            if ([target isEqualToString:@"com.shazam.shazam"] &&
                ([sec isEqualToString:@"com.apple.shazamnotifications"] || [parent isEqualToString:@"com.apple.shazamnotifications"])) {
                appMatched = YES;
                break;
            }
        }
        if (!appMatched) return NO;
    }

    if (self.texts.count == 0) return YES;

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (id raw in @[title ?: @"", subtitle ?: @"", message ?: @""]) {
        if ([raw isKindOfClass:[NSString class]] && [(NSString *)raw length] > 0) {
            [parts addObject:raw];
        }
    }
    if (parts.count == 0) return NO;

    NSString *combined = [parts componentsJoinedByString:@" "];
    for (NSString *needle in self.texts) {
        if (needle.length == 0) continue;
        if ([combined rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)resolvedNameForBundleId:(NSString *)bundleId resolver:(NSString * _Nullable (^)(NSString *))resolver {
    if ([bundleId.lowercaseString isEqualToString:kRCRemoteCompanionBundleId]) {
        return @"RemoteCompanion";
    }
    NSString *name = resolver ? resolver(bundleId) : nil;
    return name.length > 0 ? name : bundleId;
}

- (NSString *)appsSummaryWithResolver:(NSString * _Nullable (^)(NSString *))resolver {
    if (self.apps.count == 0) return @"All Apps";
    if (self.apps.count == 1) return [self resolvedNameForBundleId:self.apps[0] resolver:resolver];
    if (self.apps.count == 2) {
        return [NSString stringWithFormat:@"%@, %@",
                [self resolvedNameForBundleId:self.apps[0] resolver:resolver],
                [self resolvedNameForBundleId:self.apps[1] resolver:resolver]];
    }
    return [NSString stringWithFormat:@"%lu Apps", (unsigned long)self.apps.count];
}

- (NSString *)actionAccentTextWithResolver:(NSString * _Nullable (^)(NSString *))resolver {
    if (self.apps.count > 0) {
        return [self appsSummaryWithResolver:resolver];
    }
    if (self.texts.count == 0) return @"All Apps";
    if (self.texts.count == 1) return [NSString stringWithFormat:@"\"%@\"", self.texts[0]];
    return [NSString stringWithFormat:@"%lu Text Filters", (unsigned long)self.texts.count];
}

- (NSString *)actionDetailText {
    if (self.apps.count > 0) {
        if (self.texts.count == 1) {
            return [NSString stringWithFormat:@"Matching \"%@\"", self.texts[0]];
        }
        if (self.texts.count > 1) {
            return [NSString stringWithFormat:@"Matching %lu filters (\"%@\", …)",
                    (unsigned long)self.texts.count, self.texts[0]];
        }
        return nil;
    }
    if (self.texts.count > 1) {
        return [NSString stringWithFormat:@"Any App · \"%@\", …", self.texts[0]];
    }
    return nil;
}

- (NSString *)singleLineSummaryWithResolver:(NSString * _Nullable (^)(NSString *))resolver {
    if (self.apps.count == 0 && self.texts.count == 0) {
        return @"Clear Notifications (All)";
    }
    if (self.apps.count > 0 && self.texts.count == 0) {
        return [NSString stringWithFormat:@"Clear Notifications (%@)", [self appsSummaryWithResolver:resolver]];
    }
    NSString *textDesc = self.texts.count == 1
        ? [NSString stringWithFormat:@"\"%@\"", self.texts[0]]
        : [NSString stringWithFormat:@"%lu Filters", (unsigned long)self.texts.count];
    if (self.apps.count == 0) {
        return [NSString stringWithFormat:@"Clear Notifications (%@)", textDesc];
    }
    return [NSString stringWithFormat:@"Clear Notifications (%@ · %@)",
            [self appsSummaryWithResolver:resolver], textDesc];
}

@end

