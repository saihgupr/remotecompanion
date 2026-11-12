#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface RCConfigManager : NSObject

@property (nonatomic, assign) BOOL masterEnabled;
@property (nonatomic, assign) BOOL tcpEnabled;
@property (nonatomic, assign) BOOL webUIEnabled;
// Allow other devices to start the AudioStream streaming server through
// /api/audiostream/start. Off by default.
@property (nonatomic, assign) BOOL audiostreamAutoStart;
// Who can reach the Web UI: @"any" (the default), @"networks" (only on webUINetworks) or @"local" (this iPhone only)
@property (nonatomic, copy) NSString *webUIAccess;
// Wi-Fi network names the Web UI can be reached on when webUIAccess is @"networks"
@property (nonatomic, copy) NSArray<NSString *> *webUINetworks;
// Optional API token for Web UI / remote HTTP access to privileged actions (root, sudo, exec)
@property (nonatomic, copy) NSString *webUIApiToken;
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
// A banner that comes while the screen is off turns it on (off: the banner waits for the screen to turn on)
@property (nonatomic, assign) BOOL toastsWakeScreen;
// Unlock Device and lock toggle skip unlocking while the proximity sensor is covered, such as
// in a pocket. Off by default (Settings > Advanced Settings > Options).
@property (nonatomic, assign) BOOL onlyUnlockOutOfPocket;
@property (nonatomic, assign) BOOL nfcEnabled;
// Seconds the NFC scan keeps going after the screen turns off (0: only while the screen is on)
@property (nonatomic, assign) double nfcScreenOffSeconds;
// Experimental NFC: the system's own background reader reads tags while the screen is on (iPhone XS and later)
@property (nonatomic, assign) BOOL nfcBackgroundReading;
+ (BOOL)nfcBackgroundReadingSupported;
// Run History: how many runs of each trigger are kept (0 for none; 10 unless set)
@property (nonatomic, assign) NSInteger runHistoryCount;
@property (nonatomic, assign) BOOL rootEnabled;
// The root helper only runs shell commands when SpringBoard asks it to. Turn this on to let
// scripts, terminals and other tools call it directly. Off by default (Settings > Advanced
// Settings > Security).
@property (nonatomic, assign) BOOL allowDirectRootHelper;
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
@property (nonatomic, strong) NSArray<NSDictionary *> *sshHosts;
- (void)addOrUpdateSSHHost:(NSDictionary *)host;
- (void)deleteSSHHostWithId:(NSString *)hostId;
- (NSDictionary *)sshHostForId:(NSString *)hostId;
// Other devices running the RemoteCompanion Web UI, for the Remote RC action
@property (nonatomic, strong) NSArray<NSDictionary *> *rcClients;
- (void)addOrUpdateRCClient:(NSDictionary *)client;
- (void)deleteRCClientWithId:(NSString *)clientId;
- (NSDictionary *)rcClientForId:(NSString *)clientId;


+ (instancetype)sharedManager;

- (NSArray<NSString *> *)allTriggerKeys;
+ (NSArray<NSString *> *)builtInTriggerKeys;
- (NSArray<NSString *> *)allConfiguredTriggerKeys;
- (NSString *)displayNameForTrigger:(NSString *)triggerKey;
// Whether a trigger can have a name of its own: the ones the user makes, not the built-in ones
+ (BOOL)canRenameTrigger:(NSString *)triggerKey;
// A name the user gave a trigger, or nil; setting nil or "" goes back to its default
- (NSString *)customNameForTrigger:(NSString *)triggerKey;
- (void)setCustomName:(NSString *)name forTrigger:(NSString *)triggerKey;
- (NSString *)defaultNameForTrigger:(NSString *)triggerKey;
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
+ (BOOL)defaultHapticsForTrigger:(NSString *)triggerKey;
- (BOOL)isHapticsEnabledForTrigger:(NSString *)triggerKey;
- (void)setHapticsEnabled:(BOOL)enabled forTrigger:(NSString *)triggerKey;
- (BOOL)isToastsEnabledForTrigger:(NSString *)triggerKey;
- (void)setToastsEnabled:(BOOL)enabled forTrigger:(NSString *)triggerKey;

// Saves an App Launch ("app_launch_") or App Exit ("app_exit_") trigger for these apps and
// returns its key, which is the first app's. The actions of the trigger it replaces (oldKey),
// or of one that already exists for the first app, are kept. Two or more apps are stored
// in the trigger's "apps" list.
- (NSString *)saveAppTriggerWithPrefix:(NSString *)prefix names:(NSArray<NSString *> *)names bundleIds:(NSArray<NSString *> *)bundleIds replacing:(NSString *)oldKey;
- (void)renameTrigger:(NSString *)triggerKey toName:(NSString *)newName;
- (NSArray<NSString *> *)nfcTriggerKeys;

// Notification triggers: tapping a Notification action's notification runs notiftap_<its tap ID>,
// a button of its long-press menu notifbtn_<the button's ID> (see RCNotifyCommand)
- (NSArray<NSString *> *)notificationTapTriggerKeys;   // both kinds
// Every Notification action, and each of its buttons: @{ kind: tap|button, trigger, index, title,
// key? (the trigger it runs), tap?, button?, buttonID?, buttonTitle? }
- (NSArray<NSDictionary *> *)notificationActionEntries;
- (NSDictionary *)notificationEntryForTriggerKey:(NSString *)triggerKey;
// The trigger an entry runs, giving a notification a tap ID (saved) when it has none
- (NSString *)triggerKeyForNotificationEntry:(NSDictionary *)entry;
// Links an entry (of the same kind) to that trigger; others linked to it lose the link
- (void)linkNotificationEntry:(NSDictionary *)entry toTriggerKey:(NSString *)triggerKey;
+ (NSString *)tapIDInNotifyCommand:(NSString *)command;
+ (NSString *)titleInNotifyCommand:(NSString *)command;
+ (NSString *)newNotificationTapID;
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

// API Token Generation
- (NSString *)generateRandomApiToken;

// Backup/Restore
- (BOOL)importConfigFromJSON:(NSData *)jsonData error:(NSError **)error;

extern NSString *const RCConfigChangedNotification;

@end

@interface RCConfigManager (SetVariableText)
+ (NSString *)setVariableText:(NSDictionary *)dict;
@end
