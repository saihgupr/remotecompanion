#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kRCRemoteCompanionBundleId;

// Clear Notifications action: clears matching notifications from Notification Center
// (and RC's delivered notifications). Stored as a single command string:
//   notify clear {"apps":["com.saihgupr.remotecompanion"],"texts":["..."]}
// Empty apps = Any App; empty texts = all notifications from matching apps.
// Bare "notify clear" (legacy) targets RemoteCompanion only.
@interface RCClearNotificationsCommand : NSObject

@property (nonatomic, copy) NSArray<NSString *> *apps;
@property (nonatomic, copy) NSArray<NSString *> *texts;

+ (BOOL)isClearCommand:(nullable NSString *)command;
+ (nullable instancetype)commandWithString:(nullable NSString *)command;
- (instancetype)initWithApps:(nullable NSArray<NSString *> *)apps
                       texts:(nullable NSArray<NSString *> *)texts;

- (NSString *)string;

- (BOOL)matchesSectionID:(nullable NSString *)sectionID
         parentSectionID:(nullable NSString *)parentSectionID
                   title:(nullable NSString *)title
                subtitle:(nullable NSString *)subtitle
                 message:(nullable NSString *)message;

- (NSString *)appsSummaryWithResolver:(nullable NSString * _Nullable (^)(NSString *bundleId))resolver;
- (NSString *)actionAccentTextWithResolver:(nullable NSString * _Nullable (^)(NSString *bundleId))resolver;
- (nullable NSString *)actionDetailText;
- (NSString *)singleLineSummaryWithResolver:(nullable NSString * _Nullable (^)(NSString *bundleId))resolver;

@end

NS_ASSUME_NONNULL_END

