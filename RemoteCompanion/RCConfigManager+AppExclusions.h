#import "RCConfigManager.h"

@interface RCConfigManager (AppExclusions)
- (NSArray<NSString *> *)assignedAppExclusionTriggerKeys;
- (NSArray<NSString *> *)excludedAppsForTrigger:(NSString *)triggerKey;
- (void)setExcludedApps:(NSArray<NSString *> *)bundleIDs forTrigger:(NSString *)triggerKey;
@end
