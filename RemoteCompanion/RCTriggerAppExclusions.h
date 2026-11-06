#import <Foundation/Foundation.h>

// Shared by Settings and SpringBoard. Any configured trigger can carry exclusions;
// enforcement is generic in the central dispatch and actionable checks.
static inline BOOL RCTriggerSupportsAppExclusions(id key) {
    return [key isKindOfClass:[NSString class]];
}

// Imported plists/JSON may contain arbitrary types. Only nonempty bundle IDs are
// accepted; matching is case-insensitive, exact (never prefixes or wildcards).
static inline NSArray<NSString *> *RCNormalizedExcludedApps(id raw) {
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableOrderedSet<NSString *> *ids = [NSMutableOrderedSet orderedSet];
    for (id value in raw) {
        if (![value isKindOfClass:[NSString class]]) continue;
        NSString *bundleID = [[value stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        if (bundleID.length) [ids addObject:bundleID];
    }
    return [ids array];
}

static inline BOOL RCTriggerExcludesBundleID(id key, id trigger, id bundleID) {
    if (!RCTriggerSupportsAppExclusions(key) ||
        ![trigger isKindOfClass:[NSDictionary class]] ||
        ![bundleID isKindOfClass:[NSString class]] || ![bundleID length]) return NO;
    return [RCNormalizedExcludedApps(trigger[@"excludedApps"]) containsObject:[bundleID lowercaseString]];
}
