#import "RCConfigManager+AppExclusions.h"
#import "RCTriggerAppExclusions.h"

@implementation RCConfigManager (AppExclusions)

- (NSArray<NSString *> *)assignedAppExclusionTriggerKeys {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in RCAppExclusionTriggerKeys()) {
        id trigger = [self triggerDataForKey:key];
        if (![trigger isKindOfClass:[NSDictionary class]]) continue;
        id actions = trigger[@"actions"];
        // Keep disabled-but-assigned behaviors editable too.
        if ([actions isKindOfClass:[NSArray class]] && [actions count]) [keys addObject:key];
    }
    return keys;
}

- (NSArray<NSString *> *)excludedAppsForTrigger:(NSString *)triggerKey {
    if (!RCTriggerSupportsAppExclusions(triggerKey)) return @[];
    id trigger = [self triggerDataForKey:triggerKey];
    return [trigger isKindOfClass:[NSDictionary class]] ? RCNormalizedExcludedApps(trigger[@"excludedApps"]) : @[];
}

- (void)setExcludedApps:(NSArray<NSString *> *)bundleIDs forTrigger:(NSString *)triggerKey {
    if (!RCTriggerSupportsAppExclusions(triggerKey)) return;
    id existing = [self triggerDataForKey:triggerKey];
    // A picker left open must never resurrect a trigger removed elsewhere.
    if (![existing isKindOfClass:[NSDictionary class]]) return;
    NSMutableDictionary *trigger = [existing mutableCopy];
    NSArray *ids = RCNormalizedExcludedApps(bundleIDs);
    if (ids.count) trigger[@"excludedApps"] = ids;
    else [trigger removeObjectForKey:@"excludedApps"];
    // updateTrigger uses the same config persistence, export/import and Darwin
    // refresh path as action edits; all unrelated trigger fields are preserved.
    [self updateTrigger:triggerKey withData:trigger];
}

@end
