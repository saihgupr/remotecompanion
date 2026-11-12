// SpringBoard-owned native Quick Actions. No Home Screen observation or payload cache.
#pragma once
#import <CommonCrypto/CommonDigest.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const char *RCQAType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}

// Validate the actual runtime method before every private objc_msgSend cast.
static Method RCQAMethod(id receiver, SEL selector, char result, NSUInteger arguments) {
    if (!receiver || ![receiver respondsToSelector:selector]) return NULL;
    Method method = class_getInstanceMethod(object_getClass(receiver), selector);
    if (!method || method_getNumberOfArguments(method) != arguments + 2) return NULL;
    char *type = method_copyReturnType(method);
    BOOL valid = RCQAType(type)[0] == result;
    free(type);
    for (NSUInteger i = 2; valid && i < arguments + 2; i++) {
        type = method_copyArgumentType(method, (unsigned int)i);
        const char *argument = RCQAType(type);
        valid = argument[0] == '@' && argument[1] != '?';
        free(type);
    }
    return valid ? method : NULL;
}

static id RCQAGet(id object, NSString *name, NSString **status) {
    SEL selector = NSSelectorFromString(name);
    if (!RCQAMethod(object, selector, '@', 0)) {
        if (status) *status = @"unavailable_or_unsupported_abi";
        return nil;
    }
    @try {
        id result = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if (status) *status = @"ok";
        return result;
    } @catch (__unused NSException *exception) {
        if (status) *status = @"exception";
        return nil;
    }
}

static NSString *RCQAString(id value, NSUInteger limit) {
    return [value isKindOfClass:NSString.class] && [value length] <= limit ? value : @"";
}

// Canonical, bounded identity only; never reconstruct an activation object from it.
// Sorting dictionaries prevents userInfo ordering changes from changing the identity.
static id RCQACanonical(id value, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth > 12) return nil;
    (*budget)--;
    if (!value) return @[@"nil"];
    if ([value isKindOfClass:NSString.class]) return [value length] <= 65536 ? @[@"string", value] : nil;
    if ([value isKindOfClass:NSData.class]) return [value length] <= 65536 ? @[@"data", value] : nil;
    if ([value isKindOfClass:NSNumber.class]) return @[@"number", @([value objCType]), [value stringValue]];
    if ([value isKindOfClass:NSDate.class]) return @[@"date", value];
    if ([value isKindOfClass:NSURL.class]) return @[@"url", [value absoluteString] ?: @""];
    if ([value isKindOfClass:NSUUID.class]) return @[@"uuid", [value UUIDString]];
    if ([value isKindOfClass:NSArray.class]) {
        if ([value count] > 256) return nil;
        NSMutableArray *array = [NSMutableArray arrayWithObject:@"array"];
        for (id element in value) {
            id normalized = RCQACanonical(element, depth + 1, budget);
            if (!normalized) return nil;
            [array addObject:normalized];
        }
        return array;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        if ([value count] > 256) return nil;
        for (id key in value) if (![key isKindOfClass:NSString.class]) return nil;
        NSMutableArray *array = [NSMutableArray arrayWithObject:@"dictionary"];
        for (NSString *key in [[value allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            id normalized = RCQACanonical(value[key], depth + 1, budget);
            if (!normalized || key.length > 4096) return nil;
            [array addObject:@[key, normalized]];
        }
        return array;
    }
    return nil; // Unknown userInfo classes cannot be identified losslessly.
}

static NSString *RCQAIdentity(id item) {
    NSMutableArray *fields = [NSMutableArray array];
    for (NSString *key in @[@"type", @"localizedTitle", @"localizedSubtitle", @"bundleIdentifierToLaunch", @"targetContentIdentifier"]) {
        NSString *status = nil;
        id value = RCQAGet(item, key, &status);
        if (![status isEqualToString:@"ok"] || (value && ![value isKindOfClass:NSString.class])) return nil;
        [fields addObject:value ? @[@"string", value] : @[@"nil"]];
    }
    SEL modeSelector = NSSelectorFromString(@"activationMode");
    if (!RCQAMethod(item, modeSelector, 'Q', 0)) return nil;
    unsigned long long mode = ((unsigned long long (*)(id, SEL))objc_msgSend)(item, modeSelector);
    [fields addObject:@(mode)];
    NSString *status = nil;
    id payload = RCQAGet(item, @"userInfoData", &status);
    if (payload && ![payload isKindOfClass:NSData.class]) return nil;
    // Prefer the native opaque bytes (including custom securely-coded userInfo).
    // If unavailable, canonicalize only supported userInfo types; never guess.
    if (!payload) {
        payload = RCQAGet(item, @"userInfo", &status);
        if (![status isEqualToString:@"ok"] || (payload && ![payload isKindOfClass:NSDictionary.class])) return nil;
    }
    NSUInteger budget = 1024;
    id normalized = RCQACanonical(payload, 0, &budget);
    if (!normalized) return nil;
    [fields addObject:normalized];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:fields format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!data || data.length > 262144) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *identity = [NSMutableString stringWithString:@"v1:"];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [identity appendFormat:@"%02x", digest[i]];
    return identity;
}

static NSString *RCQALockError(void) {
    id manager = RCQAGet(NSClassFromString(@"SBLockScreenManager"), @"sharedInstance", NULL);
    SEL selector = NSSelectorFromString(@"isUILocked");
    if (!RCQAMethod(manager, selector, 'B', 0) && !RCQAMethod(manager, selector, 'c', 0)) return @"Lock status unavailable";
    return ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector) ? @"Unlock the phone first" : nil;
}

static NSArray *RCQAReadItems(id owner, NSString *name, NSMutableDictionary *diagnostic) {
    NSString *status = nil;
    id result = RCQAGet(owner, name, &status);
    if ([status isEqualToString:@"ok"] && result && ![result isKindOfClass:NSArray.class]) status = @"invalid_result_type";
    diagnostic[@"status"] = status;
    diagnostic[@"owner"] = owner ? NSStringFromClass([owner class]) : @"missing";
    Method method = owner ? class_getInstanceMethod(object_getClass(owner), NSSelectorFromString(name)) : NULL;
    if (method) diagnostic[@"encoding"] = @(method_getTypeEncoding(method));
    if (![status isEqualToString:@"ok"]) return @[];
    diagnostic[@"count"] = @([result count]);
    return result ?: @[]; // nil/empty is authoritative, not a reason to use stale data.
}

static NSArray *RCQALiveItems(NSString *bundle, NSMutableDictionary *diagnostics, NSString **error) {
    id controller = RCQAGet(NSClassFromString(@"SBApplicationController"), @"sharedInstance", NULL);
    SEL lookup = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (!RCQAMethod(controller, lookup, '@', 1)) { *error = @"Application lookup unavailable or unsupported ABI"; return @[]; }
    id app = ((id (*)(id, SEL, id))objc_msgSend)(controller, lookup, bundle);
    if (!app) { *error = @"Application not installed or unavailable"; return @[]; }
    if (![RCQAString(RCQAGet(app, @"bundleIdentifier", NULL), 512) isEqualToString:bundle]) {
        *error = @"Application identity mismatch"; return @[];
    }
    NSMutableDictionary *staticInfo = [NSMutableDictionary dictionary], *dynamicInfo = [NSMutableDictionary dictionary];
    id staticOwner = app;
    // iOS 17 moved the static getter to SBApplicationInfo. Fall back only for
    // an absent method, never for an empty successful response or bad ABI.
    if (![app respondsToSelector:NSSelectorFromString(@"staticApplicationShortcutItems")]) staticOwner = RCQAGet(app, @"info", NULL);
    NSArray *staticItems = RCQAReadItems(staticOwner, @"staticApplicationShortcutItems", staticInfo);
    NSArray *dynamicItems = RCQAReadItems(app, @"dynamicApplicationShortcutItems", dynamicInfo);
    diagnostics[@"static"] = staticInfo;
    diagnostics[@"dynamic"] = dynamicInfo;
    if (![staticInfo[@"status"] isEqualToString:@"ok"] || ![dynamicInfo[@"status"] isEqualToString:@"ok"]) {
        *error = @"Some native Quick Shortcut sources are unavailable (see diagnostics)";
    }
    NSMutableArray *items = [NSMutableArray array];
    Class nativeClass = NSClassFromString(@"SBSApplicationShortcutItem");
    NSUInteger scanned = 0, rejected = 0;
    for (NSArray *source in @[staticItems, dynamicItems]) {
        for (id item in source) {
            if (++scanned > 256) break;
            if (!nativeClass || ![item isKindOfClass:nativeClass] || !RCQAString(RCQAGet(item, @"type", NULL), 4096).length) { rejected++; continue; }
            [items addObject:item]; // Preserve the full native activation payload.
        }
    }
    diagnostics[@"rejected"] = @(rejected);
    diagnostics[@"truncated"] = @(staticItems.count + dynamicItems.count > 256);
    return items;
}

static NSDictionary *RCQARequest(NSString *encoded) {
    if (encoded.length > 32768) return nil;
    NSData *bytes = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    id value = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSString *RCQAJSON(id value) {
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return bytes ? [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] : @"{\"status\":\"error\",\"error\":\"Serialization failed\",\"items\":[]}";
}

static NSString *RCQACommandOnMain(NSString *command) {
    BOOL listing = [command hasPrefix:@"quickactions list "];
    BOOL running = [command hasPrefix:@"quickactions run "];
    if (!listing && !running) return @"Unknown Quick Shortcut command";
    NSDictionary *request = running ? RCQARequest([command substringFromIndex:17]) : nil;
    NSString *bundle = RCQAString(listing ? [command substringFromIndex:18] : request[@"bundle"], 512);
    NSString *type = running ? RCQAString(request[@"type"], 4096) : @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    NSString *error = nil;
    NSMutableDictionary *diagnostics = [NSMutableDictionary dictionaryWithObject:@"live_application" forKey:@"source"];
    NSArray *items = @[];
    if (!bundle.length || [bundle rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound || (running && !type.length)) error = @"Invalid Quick Shortcut request";
    else error = RCQALockError();
    if (!error) items = RCQALiveItems(bundle, diagnostics, &error);
    if (listing) {
        NSMutableArray *rows = [NSMutableArray array];
        NSMutableSet *identities = [NSMutableSet set];
        NSUInteger rejected = 0;
        for (id item in items) {
            NSString *identity = RCQAIdentity(item);
            if (!identity) { rejected++; continue; }
            if ([identities containsObject:identity]) continue;
            [identities addObject:identity];
            NSString *itemType = RCQAString(RCQAGet(item, @"type", NULL), 4096);
            [rows addObject:@{@"type": itemType, @"identity": identity,
                @"title": RCQAString(RCQAGet(item, @"localizedTitle", NULL), 1024),
                @"subtitle": RCQAString(RCQAGet(item, @"localizedSubtitle", NULL), 1024)}];
        }
        diagnostics[@"unidentifiable"] = @(rejected);
        if (rejected && !error) error = @"Some shortcuts have unsupported payload identities";
        return RCQAJSON(@{@"status": error ? (rows.count ? @"partial" : @"error") : @"ok", @"error": error ?: @"", @"items": rows, @"diagnostics": diagnostics});
    }
    NSString *identity = RCQAString(request[@"identity"], 67);
    if (request[@"identity"] && (identity.length != 67 || ![identity hasPrefix:@"v1:"])) return @"Invalid Quick Shortcut identity";
    id selected = nil;
    NSUInteger matches = 0;
    NSMutableSet *matchedIdentities = [NSMutableSet set];
    for (id item in items) {
        if (![RCQAString(RCQAGet(item, @"type", NULL), 4096) isEqualToString:type]) continue;
        NSString *candidateIdentity = RCQAIdentity(item);
        if (!candidateIdentity) continue;
        if (identity.length && ![candidateIdentity isEqualToString:identity]) continue;
        // Static and dynamic sources may contain the same native action. Use
        // the same identity deduplication as listing, not the raw source count.
        if ([matchedIdentities containsObject:candidateIdentity]) continue;
        [matchedIdentities addObject:candidateIdentity];
        selected = item; matches++;
    }
    if (!selected) return error ?: @"Quick Shortcut changed or is no longer registered; choose it again";
    if (matches != 1) return @"Ambiguous Quick Shortcut; choose it again";
    // iOS 26 moved this class method from SBIconView to the shortcuts menu provider
    SEL action = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
    Class cls = NSClassFromString(@"SBIconView");
    if (!RCQAMethod(cls, action, 'v', 3)) cls = NSClassFromString(@"SBHIconViewApplicationShortcutsContextMenuProvider");
    if (!RCQAMethod(cls, action, 'v', 3)) return @"Native Quick Shortcut activation unavailable or unsupported ABI";
    // No menu/view is needed for registered application items. Native code owns
    // activation; dispatch does not prove the target app handled the shortcut.
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(cls, action, selected, bundle, nil);
    return @"Quick Shortcut dispatched";
}

static NSString *RCQACommand(NSString *command) {
    __block NSString *output = nil;
    void (^work)(void) = ^{
        @try { output = RCQACommandOnMain(command); }
        @catch (__unused NSException *exception) {
            output = [command hasPrefix:@"quickactions list "] ? RCQAJSON(@{@"status": @"error", @"error": @"Native Quick Shortcut query failed", @"items": @[]}) : @"Native Quick Shortcut activation failed";
        }
    };
    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
    return output;
}
