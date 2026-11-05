#import <Foundation/Foundation.h>

// Shared by Settings and SpringBoard. This first version deliberately covers only
// status-bar gestures: other trigger families have their own native-event policies.
static inline NSArray<NSString *> *RCAppExclusionTriggerKeys(void) {
    return @[@"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold",
             @"trigger_statusbar_right_hold", @"trigger_statusbar_swipe_left",
             @"trigger_statusbar_swipe_right", @"trigger_statusbar_double_tap"];
}

static inline BOOL RCTriggerSupportsAppExclusions(id key) {
    return [key isKindOfClass:[NSString class]] && [RCAppExclusionTriggerKeys() containsObject:key];
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
