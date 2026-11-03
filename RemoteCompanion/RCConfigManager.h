#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface RCConfigManager : NSObject

@property (nonatomic, assign) BOOL masterEnabled;
@property (nonatomic, assign) BOOL tcpEnabled;
@property (nonatomic, assign) BOOL webUIEnabled;
// Who can reach the Web UI: @"any" (the default), @"networks" (only on webUINetworks) or @"local" (this iPhone only)
@property (nonatomic, copy) NSString *webUIAccess;
// Wi-Fi network names the Web UI can be reached on when webUIAccess is @"networks"
@property (nonatomic, copy) NSArray<NSString *> *webUINetworks;
// Hold lists (and row swipe actions) still while a status bar, bottom bar,
// or edge swipe gesture is being executed. Off by default.
@property (nonatomic, assign) BOOL freezeListsDuringGestures;
// The tweak's log: @"off", @"minimal" (the default: triggers, actions, conditions, errors)
// or @"full" (every step, for chasing a bug)
@property (nonatomic, copy) NSString *logLevel;
// Seconds after a volume press within which the other volume button completes an Up then Down
// (or Down then Up) sequence: 0.15 to 0.8, default 0.38
@property (nonatomic, assign) double volumeSequenceWindow;
// Seconds a Power press waits for the next click before the clicks count (a double, triple or
// quadruple click): 0.10 to 0.8, default 0.4
@property (nonatomic, assign) double powerClickWindow;
// Seconds a Home press waits for the next click (double, triple or quadruple): 0.25 to 0.8, default 0.35
@property (nonatomic, assign) double homeClickWindow;
// Seconds a Volume Up or Down press is held before it counts as a hold: 0.2 to 0.8, default 0.35
@property (nonatomic, assign) double volumeHoldTime;
// Seconds a Power press is held before it counts as a long press: 0.3 to 0.75, default 0.5
@property (nonatomic, assign) double powerHoldTime;
// Settings > Banners: actions that show a banner when a trigger runs them (built by RCBannersViewController)
@property (nonatomic, copy) NSArray<NSDictionary *> *bannerActions;
// Actions with a banner of their own that have been switched off in Settings > Banners
@property (nonatomic, copy) NSArray<NSString *> *bannerOptOut;
@property (nonatomic, assign) BOOL nfcEnabled;
// Seconds the NFC scan keeps going after the screen turns off (0: only while the screen is on)
@property (nonatomic, assign) double nfcScreenOffSeconds;
// Experimental NFC: the system's own background reader reads tags while the screen is on (iPhone XS and later)
@property (nonatomic, assign) BOOL nfcBackgroundReading;
+ (BOOL)nfcBackgroundReadingSupported;
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

// Saves an App Launch ("app_launch_") or App Exit ("app_exit_") trigger for these apps and
// returns its key, which is the first app's. The actions of the trigger it replaces (oldKey),
// or of one that already exists for the first app, are kept. Two or more apps are stored
// in the trigger's "apps" list.
- (NSString *)saveAppTriggerWithPrefix:(NSString *)prefix names:(NSArray<NSString *> *)names bundleIds:(NSArray<NSString *> *)bundleIds replacing:(NSString *)oldKey;
- (void)renameTrigger:(NSString *)triggerKey toName:(NSString *)newName;
- (NSArray<NSString *> *)nfcTriggerKeys;
- (NSArray<NSDictionary *> *)notificationTriggers;
- (void)setNotificationTriggers:(NSArray<NSDictionary *> *)triggers;
- (void)saveConfig;
- (void)loadConfig;
- (void)stopBackgroundNFC;
- (void)resumeBackgroundNFC;

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
// A "shortcut:" action: its shortcut name, whether it runs silently (-i) and its text input (-p);
// and an action from those (input nil for none)
+ (NSString *)shortcutNameForAction:(NSString *)action silent:(BOOL *)silent input:(NSString **)input;
+ (NSString *)shortcutActionWithName:(NSString *)name silent:(BOOL)silent input:(NSString *)input;
// Focus modes (the Set Focus action, the Focus condition) came with iOS 15
+ (BOOL)supportsFocus;
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
