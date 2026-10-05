#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface RCConfigManager : NSObject

@property (nonatomic, assign) BOOL masterEnabled;
@property (nonatomic, assign) BOOL tcpEnabled;
@property (nonatomic, assign) BOOL webUIEnabled;
// The tweak's log: @"off", @"minimal" (the default: triggers, actions, conditions, errors)
// or @"full" (every step, for chasing a bug)
@property (nonatomic, copy) NSString *logLevel;
// Settings > Banners: actions that show a banner when a trigger runs them (built by RCBannersViewController)
@property (nonatomic, copy) NSArray<NSDictionary *> *bannerActions;
// Actions with a banner of their own that have been switched off in Settings > Banners
@property (nonatomic, copy) NSArray<NSString *> *bannerOptOut;
@property (nonatomic, assign) BOOL nfcEnabled;
@property (nonatomic, assign) BOOL rootEnabled;
@property (nonatomic, assign) BOOL haEnabled;
@property (nonatomic, copy) NSString *haUrl;
@property (nonatomic, copy) NSString *haToken;
@property (nonatomic, assign) BOOL kmEnabled;
@property (nonatomic, copy) NSString *kmUrl;
@property (nonatomic, copy) NSString *kmUser;
@property (nonatomic, copy) NSString *kmPassword;
@property (nonatomic, assign) BOOL mqttEnabled;
@property (nonatomic, copy) NSString *mqttHost;
@property (nonatomic, assign) NSInteger mqttPort;
@property (nonatomic, copy) NSString *mqttUser;
@property (nonatomic, copy) NSString *mqttPassword;
@property (nonatomic, copy) NSString *mqttClientId;
@property (nonatomic, copy) NSString *mqttTopicPrefix;


+ (instancetype)sharedManager;

- (NSArray<NSString *> *)allTriggerKeys;
- (NSArray<NSString *> *)allConfiguredTriggerKeys;
- (NSString *)displayNameForTrigger:(NSString *)triggerKey;
- (BOOL)isTriggerEnabled:(NSString *)triggerKey;
- (void)setTriggerEnabled:(BOOL)enabled forTrigger:(NSString *)triggerKey;
- (BOOL)isTriggerFavorite:(NSString *)triggerKey;
- (void)setTriggerFavorite:(BOOL)favorite forTrigger:(NSString *)triggerKey;
- (NSArray<NSString *> *)orderedFavorites;
- (void)setOrderedFavorites:(NSArray<NSString *> *)favorites;
- (NSArray *)actionsForTrigger:(NSString *)triggerKey;
- (void)setActions:(NSArray *)actions forTrigger:(NSString *)triggerKey;
- (NSDictionary *)triggerDataForKey:(NSString *)triggerKey;
- (void)updateTrigger:(NSString *)triggerKey withData:(NSDictionary *)data;
- (void)removeTrigger:(NSString *)triggerKey;
- (void)renameTrigger:(NSString *)triggerKey toName:(NSString *)newName;
- (NSArray<NSString *> *)nfcTriggerKeys;
- (NSArray<NSDictionary *> *)notificationTriggers;
- (void)setNotificationTriggers:(NSArray<NSDictionary *> *)triggers;
- (void)saveConfig;
- (void)loadConfig;
- (void)stopBackgroundNFC;

// UI Color Tweaks
- (NSDictionary *)colorTweaks;
- (void)setColorTweaks:(NSDictionary *)tweaks;
- (CGFloat)tweakValueForKey:(NSString *)key defaultVal:(CGFloat)defaultVal;
- (UIColor *)tweakColorForKey:(NSString *)key defaultVal:(CGFloat)defaultVal;

// Command Helpers
- (NSString *)nameForCommand:(id)cmd truncate:(BOOL)shouldTruncate;
- (NSString *)nameForBundleId:(NSString *)bundleId;
- (NSString *)iconForCommand:(id)cmd;
- (NSDictionary *)toggleInfoForCommand:(NSString *)cmd;
// Vibration settings, the way this iOS version's Settings shows them: one Haptics menu from
// iOS 17 (over the same two on/off values), the two switches by their names before that
+ (BOOL)hasHomeButton;
+ (BOOL)usesHapticsMenu;
+ (NSString *)vibrationNameForSilentMode:(BOOL)silent;
- (BOOL)isActionDisabled:(id)actionItem;
- (id)toggleActionDisabled:(id)actionItem;
- (void)registerKMMacroName:(NSString *)name forUid:(NSString *)uid;
- (void)registerKMMacroNamesBatch:(NSDictionary<NSString *, NSString *> *)map;
- (NSString *)nameForKMMacroUid:(NSString *)uid;

// Backup/Restore
- (NSData *)exportConfigAsJSON;
- (BOOL)importConfigFromJSON:(NSData *)jsonData error:(NSError **)error;

extern NSString *const RCConfigChangedNotification;

@end
