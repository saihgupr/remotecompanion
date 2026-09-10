#import "RCConfigManager.h"
#import <notify.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

// Use absolute path that both TrollStore app and tweak can access
#define kConfigPath @"/var/mobile/Documents/rc_triggers.plist"
#define kConfigChangedNotification "com.pizzaman.rc.configchanged"

NSString *const RCConfigChangedNotification = @"RCConfigChangedNotification";

@interface RCConfigManager ()
@property (nonatomic, strong) NSMutableDictionary *config;
@end

@implementation RCConfigManager

+ (instancetype)sharedManager {
    static RCConfigManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RCConfigManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadConfig];
        
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(handleAppDidBecomeActive:) 
                                                     name:UIApplicationDidBecomeActiveNotification 
                                                   object:nil];
    }
    return self;
}

- (void)handleAppDidBecomeActive:(NSNotification *)note {
    [self loadConfig];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCConfigChangedNotification object:nil];
}

- (void)loadConfig {
    NSDictionary *saved = nil;
    
    // 1. Try shared path first (persists across reinstalls)
    saved = [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
    if (saved) {
        NSLog(@"[RCConfigManager] Loaded from shared path: %@", kConfigPath);
    } else {
        // 2. Try app Documents (container)
        NSString *appDocsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *appConfigPath = [appDocsPath stringByAppendingPathComponent:@"rc_triggers.plist"];
        saved = [NSDictionary dictionaryWithContentsOfFile:appConfigPath];
        if (saved) {
            NSLog(@"[RCConfigManager] Loaded from app Documents: %@", appConfigPath);
        } else {
            NSLog(@"[RCConfigManager] No config file found at %@ or %@", kConfigPath, appConfigPath);
        }
    }
    
    if (saved) {
        _config = [saved mutableCopy];
        
        // Ensure triggers dict exists and is mutable
        if (!_config[@"triggers"]) {
            _config[@"triggers"] = [NSMutableDictionary dictionary];
        } else if (![_config[@"triggers"] isKindOfClass:[NSMutableDictionary class]]) {
            _config[@"triggers"] = [_config[@"triggers"] mutableCopy];
        }

        if (!_config[@"notificationTriggers"]) {
            _config[@"notificationTriggers"] = [NSMutableArray array];
        } else if (![_config[@"notificationTriggers"] isKindOfClass:[NSMutableArray class]]) {
            _config[@"notificationTriggers"] = [_config[@"notificationTriggers"] mutableCopy];
        }
        
        // Auto-add any missing triggers (for upgrades)
        NSMutableDictionary *triggers = _config[@"triggers"];
        NSArray *allKeys = @[@"volume_up_hold", @"volume_down_hold", @"power_double_tap", @"power_long_press", 
                             @"power_triple_click", @"power_quadruple_click", 
                             @"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", 
                             @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right",
                             @"trigger_statusbar_double_tap",
                             @"trigger_home_triple_click", @"trigger_home_quadruple_click", @"trigger_home_double_click",
                             @"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", 
                             @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down",
                             @"volume_both_press", @"volume_up_then_down", @"volume_down_then_up", @"touchid_tap",
                             @"power_volume_up", @"power_volume_down", @"shake",
                             @"trigger_ringer_mute", @"trigger_ringer_unmute", @"trigger_ringer_toggle",
                             @"trigger_device_lock", @"trigger_device_unlock",
                             @"trigger_media_play", @"trigger_media_pause", @"trigger_media_track_change"];
        
        BOOL needsSave = NO;
        for (NSString *key in allKeys) {
            if (!triggers[key]) {
                triggers[key] = [@{ @"enabled": @NO, @"actions": @[] } mutableCopy];
                NSLog(@"[RCConfigManager] Added missing trigger: %@", key);
                needsSave = YES;
            }
        }
        
        if (needsSave) {
            [self saveConfig];
        }
        
        // Auto-add tcpEnabled if missing
        if (_config[@"tcpEnabled"] == nil) {
            _config[@"tcpEnabled"] = @YES;
            [self saveConfig];
        }
        
        // Auto-add nfcEnabled if missing
        if (_config[@"nfcEnabled"] == nil) {
            _config[@"nfcEnabled"] = @YES;
            [self saveConfig];
        }

        // Auto-add rootEnabled if missing
        if (_config[@"rootEnabled"] == nil) {
            _config[@"rootEnabled"] = @YES;
            [self saveConfig];
        }

        // Auto-add hapticsEnabled
        if (_config[@"hapticsEnabled"] == nil) {
            _config[@"hapticsEnabled"] = @YES;
            [self saveConfig];
        }

        // Auto-add webUIEnabled (default to NO for new users/upgrades for security)
        if (_config[@"webUIEnabled"] == nil) {
            _config[@"webUIEnabled"] = @NO;
            [self saveConfig];
        }

        // Cleanup deprecated watch triggers
        BOOL didChange = NO;
        if (triggers[@"watch_near"]) { [triggers removeObjectForKey:@"watch_near"]; didChange = YES; }
        if (triggers[@"watch_far"]) { [triggers removeObjectForKey:@"watch_far"]; didChange = YES; }
        
        // Also cleanup unconfigured device state and media triggers so they don't show up in the main list unless created
        NSArray *deviceStateKeys = @[@"trigger_device_lock", @"trigger_device_unlock", @"trigger_media_play", @"trigger_media_pause", @"trigger_media_track_change"];
        for (NSString *key in deviceStateKeys) {
            NSDictionary *trig = triggers[key];
            if (trig && (!trig[@"actions"] || [trig[@"actions"] count] == 0)) {
                [triggers removeObjectForKey:key];
                didChange = YES;
            }
        }
        
        if (didChange) {
            _config[@"triggers"] = triggers;
            [self saveConfig];
        }
    } else {
        // Default config with all triggers (excluding system events which are added dynamically)
        NSLog(@"[RCConfigManager] Using default config");
        _config = [@{
            @"masterEnabled": @YES,
            @"tcpEnabled": @YES,
            @"webUIEnabled": @NO,
            @"nfcEnabled": @YES,
            @"rootEnabled": @YES,
            @"triggers": [@{
                @"volume_up_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"volume_down_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_double_tap": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_long_press": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_triple_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_quadruple_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_left_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_center_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_right_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_swipe_left": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_swipe_right": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_statusbar_double_tap": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_home_triple_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_home_quadruple_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_home_double_click": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"touchid_hold": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"touchid_tap": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_left_swipe_up": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_left_swipe_down": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_right_swipe_up": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_edge_right_swipe_down": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"volume_both_press": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"volume_up_then_down": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"volume_down_then_up": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_volume_up": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"power_volume_down": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_ringer_mute": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_ringer_unmute": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_ringer_toggle": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"shake": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_bottombar_swipe_left": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy],
                @"trigger_bottombar_swipe_right": [@{ @"enabled": @NO, @"actions": @[] } mutableCopy]
            } mutableCopy]
        } mutableCopy];
    }
}

- (BOOL)masterEnabled {
    return [_config[@"masterEnabled"] boolValue];
}

- (void)setMasterEnabled:(BOOL)masterEnabled {
    _config[@"masterEnabled"] = @(masterEnabled);
    [self saveConfig];
}

- (BOOL)tcpEnabled {
    // Default to YES for backward compatibility with existing configs
    if (!_config[@"tcpEnabled"]) {
        return YES;
    }
    return [_config[@"tcpEnabled"] boolValue];
}

- (void)setTcpEnabled:(BOOL)tcpEnabled {
    _config[@"tcpEnabled"] = @(tcpEnabled);
    [self saveConfig];
}

- (BOOL)webUIEnabled {
    if (!_config[@"webUIEnabled"]) {
        return NO;
    }
    return [_config[@"webUIEnabled"] boolValue];
}

- (void)setWebUIEnabled:(BOOL)webUIEnabled {
    _config[@"webUIEnabled"] = @(webUIEnabled);
    [self saveConfig];
}

- (void)setNfcEnabled:(BOOL)nfcEnabled {
    _config[@"nfcEnabled"] = @(nfcEnabled);
    if (!nfcEnabled) {
        [self stopBackgroundNFC];
    }
    [self saveConfig];
}

- (BOOL)rootEnabled {
    return [_config[@"rootEnabled"] boolValue];
}

- (void)setRootEnabled:(BOOL)rootEnabled {
    _config[@"rootEnabled"] = @(rootEnabled);
    [self saveConfig];
}

- (BOOL)nfcEnabled {
    // Default to YES if missing
    if (!_config[@"nfcEnabled"]) {
        return YES;
    }
    return [_config[@"nfcEnabled"] boolValue];
}

- (BOOL)hapticsEnabled {
    // Default to YES if missing
    if (!_config[@"hapticsEnabled"]) {
        return YES;
    }
    return [_config[@"hapticsEnabled"] boolValue];
}

- (void)setHapticsEnabled:(BOOL)hapticsEnabled {
    _config[@"hapticsEnabled"] = @(hapticsEnabled);
    [self saveConfig];
}

- (BOOL)haEnabled {
    return [_config[@"haEnabled"] boolValue];
}

- (void)setHaEnabled:(BOOL)haEnabled {
    _config[@"haEnabled"] = @(haEnabled);
    [self saveConfig];
}

- (NSString *)haUrl {
    return _config[@"haUrl"] ?: @"";
}

- (void)setHaUrl:(NSString *)haUrl {
    _config[@"haUrl"] = haUrl ?: @"";
    [self saveConfig];
}

- (NSString *)haToken {
    return _config[@"haToken"] ?: @"";
}

- (void)setHaToken:(NSString *)haToken {
    _config[@"haToken"] = haToken ?: @"";
    [self saveConfig];
}

- (BOOL)kmEnabled {
    return [_config[@"kmEnabled"] boolValue];
}

- (void)setKmEnabled:(BOOL)kmEnabled {
    _config[@"kmEnabled"] = @(kmEnabled);
    [self saveConfig];
}

- (NSString *)kmUrl {
    return _config[@"kmUrl"] ?: @"";
}

- (void)setKmUrl:(NSString *)kmUrl {
    _config[@"kmUrl"] = kmUrl ?: @"";
    [self saveConfig];
}

- (NSString *)kmUser {
    return _config[@"kmUser"] ?: @"";
}

- (void)setKmUser:(NSString *)kmUser {
    _config[@"kmUser"] = kmUser ?: @"";
    [self saveConfig];
}

- (NSString *)kmPassword {
    return _config[@"kmPassword"] ?: @"";
}

- (void)setKmPassword:(NSString *)kmPassword {
    _config[@"kmPassword"] = kmPassword ?: @"";
    [self saveConfig];
}

- (BOOL)mqttEnabled {
    return [_config[@"mqttEnabled"] boolValue];
}

- (void)setMqttEnabled:(BOOL)mqttEnabled {
    _config[@"mqttEnabled"] = @(mqttEnabled);
    [self saveConfig];
}

- (NSString *)mqttHost {
    return _config[@"mqttHost"] ?: @"192.168.1.50";
}

- (void)setMqttHost:(NSString *)mqttHost {
    _config[@"mqttHost"] = mqttHost ?: @"192.168.1.50";
    [self saveConfig];
}

- (NSInteger)mqttPort {
    if (_config[@"mqttPort"] == nil) return 1883;
    return [_config[@"mqttPort"] integerValue];
}

- (void)setMqttPort:(NSInteger)mqttPort {
    _config[@"mqttPort"] = @(mqttPort > 0 ? mqttPort : 1883);
    [self saveConfig];
}

- (NSString *)mqttUser {
    return _config[@"mqttUser"] ?: @"";
}

- (void)setMqttUser:(NSString *)mqttUser {
    _config[@"mqttUser"] = mqttUser ?: @"";
    [self saveConfig];
}

- (NSString *)mqttPassword {
    return _config[@"mqttPassword"] ?: @"";
}

- (void)setMqttPassword:(NSString *)mqttPassword {
    _config[@"mqttPassword"] = mqttPassword ?: @"";
    [self saveConfig];
}

- (NSString *)mqttClientId {
    return _config[@"mqttClientId"] ?: @"RemoteCompanion";
}

- (void)setMqttClientId:(NSString *)mqttClientId {
    _config[@"mqttClientId"] = mqttClientId ?: @"RemoteCompanion";
    [self saveConfig];
}

- (NSString *)mqttTopicPrefix {
    return _config[@"mqttTopicPrefix"] ?: @"remotecompanion";
}

- (void)setMqttTopicPrefix:(NSString *)mqttTopicPrefix {
    _config[@"mqttTopicPrefix"] = mqttTopicPrefix ?: @"remotecompanion";
    [self saveConfig];
}

- (NSDictionary *)triggerDataForKey:(NSString *)triggerKey {
    return _config[@"triggers"][triggerKey];
}

- (void)updateTrigger:(NSString *)triggerKey withData:(NSDictionary *)data {
    NSMutableDictionary *triggers = _config[@"triggers"];
    triggers[triggerKey] = [data mutableCopy];
    [self saveConfig];
}

- (void)removeTrigger:(NSString *)triggerKey {
    NSMutableDictionary *triggers = _config[@"triggers"];
    if (triggers[triggerKey]) {
        [triggers removeObjectForKey:triggerKey];
    }
    
    // Also clean up from notificationTriggers metadata if associated entry exists
    NSMutableArray *notifTriggers = [[self notificationTriggers] mutableCopy];
    BOOL changed = NO;
    for (NSInteger i = notifTriggers.count - 1; i >= 0; i--) {
        NSDictionary *notif = notifTriggers[i];
        if ([notif[@"triggerKey"] isEqualToString:triggerKey]) {
            [notifTriggers removeObjectAtIndex:i];
            changed = YES;
        }
    }
    if (changed) {
        [self setNotificationTriggers:notifTriggers];
    }
    
    [self saveConfig];
}

- (void)renameTrigger:(NSString *)triggerKey toName:(NSString *)newName {
    NSMutableDictionary *triggers = _config[@"triggers"];
    if (triggers[triggerKey]) {
        NSMutableDictionary *triggerData = [triggers[triggerKey] mutableCopy];
        triggerData[@"name"] = newName;
        triggers[triggerKey] = triggerData;
        
        NSLog(@"[RCConfigManager] Renamed trigger %@ to '%@'", triggerKey, newName);
        [self saveConfig];
    }
}

- (NSArray<NSString *> *)nfcTriggerKeys {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in _config[@"triggers"]) {
        if ([key hasPrefix:@"nfc_"]) {
            [keys addObject:key];
        }
    }
    return keys;
}

- (NSArray<NSString *> *)allTriggerKeys {
    return @[@"volume_up_hold", @"volume_down_hold", @"volume_both_press", @"volume_up_then_down", @"volume_down_then_up", @"power_double_tap", @"power_long_press", @"power_triple_click", @"power_quadruple_click", @"trigger_statusbar_left_hold", @"trigger_statusbar_center_hold", @"trigger_statusbar_right_hold", @"trigger_statusbar_swipe_left", @"trigger_statusbar_swipe_right", @"trigger_statusbar_double_tap", @"trigger_home_triple_click", @"trigger_home_quadruple_click", @"trigger_home_double_click", @"touchid_tap", @"touchid_hold", @"trigger_edge_left_swipe_up", @"trigger_edge_left_swipe_down", @"trigger_edge_right_swipe_up", @"trigger_edge_right_swipe_down", @"trigger_ringer_mute", @"trigger_ringer_unmute", @"trigger_ringer_toggle", @"trigger_bottombar_swipe_left", @"trigger_bottombar_swipe_right", @"power_volume_up", @"power_volume_down", @"shake", @"trigger_device_lock", @"trigger_device_unlock", @"trigger_media_play", @"trigger_media_pause", @"trigger_media_track_change"];
}

- (NSArray<NSDictionary *> *)notificationTriggers {
    return _config[@"notificationTriggers"] ?: @[];
}

- (void)setNotificationTriggers:(NSArray<NSDictionary *> *)triggers {
    _config[@"notificationTriggers"] = [triggers mutableCopy];
    [self saveConfig];
}

- (NSArray<NSString *> *)allConfiguredTriggerKeys {
    return [_config[@"triggers"] allKeys];
}

- (NSString *)displayNameForTrigger:(NSString *)triggerKey {
    NSDictionary *names = @{
        @"shake": @"Shake Device",
        @"trigger_device_lock": @"Device Locked",
        @"trigger_device_unlock": @"Device Unlocked",
        @"trigger_power_connect": @"Power Connected",
        @"trigger_power_disconnect": @"Power Disconnected",
        @"trigger_media_play": @"Media Playing",
        @"trigger_media_pause": @"Media Paused",
        @"trigger_media_track_change": @"Media Track Changed",
        @"volume_up_hold": @"Volume Up Hold",
        @"volume_down_hold": @"Volume Down Hold",
        @"volume_both_press": @"Volume Up + Down (Both)",
        @"volume_up_then_down": @"Volume Up then Down",
        @"volume_down_then_up": @"Volume Down then Up",
        @"power_double_tap": @"Power Double-Tap",
        @"power_long_press": @"Power Long Press",
        @"power_triple_click": @"Power Triple Click",
        @"power_quadruple_click": @"Power Quadruple Click",
        @"power_volume_up": @"Power + Volume Up",
        @"power_volume_down": @"Power + Volume Down",
        @"trigger_statusbar_left_hold": @"Status Bar Left Hold",
        @"trigger_statusbar_center_hold": @"Status Bar Center Hold",
        @"trigger_statusbar_right_hold": @"Status Bar Right Hold",
        @"trigger_statusbar_swipe_left": @"Status Bar Swipe Left",
        @"trigger_statusbar_swipe_right": @"Status Bar Swipe Right",
        @"trigger_statusbar_double_tap": @"Status Bar Double Tap",
        @"trigger_home_triple_click": @"Home Button (Triple Click)",
        @"trigger_home_quadruple_click": @"Home Button (Quadruple Click)",
        @"trigger_home_double_click": @"Home Button (Double Click)",
        @"touchid_hold": @"Touch ID Hold (Rest Finger)",
        @"touchid_tap": @"Touch ID Single Tap",
        @"trigger_edge_left_swipe_up": @"Left Edge Swipe Up",
        @"trigger_edge_left_swipe_down": @"Left Edge Swipe Down",
        @"trigger_edge_right_swipe_up": @"Right Edge Swipe Up",
        @"trigger_edge_right_swipe_down": @"Right Edge Swipe Down",
        @"trigger_ringer_mute": @"Ringer Muted (Silent Mode On)",
        @"trigger_ringer_unmute": @"Ringer Unmuted (Silent Mode Off)",
        @"trigger_ringer_toggle": @"Ringer Toggled (Any Change)",
        @"trigger_bottombar_swipe_left": @"Bottom Bar Swipe Left",
        @"trigger_bottombar_swipe_right": @"Bottom Bar Swipe Right"
    };
    
    if ([triggerKey hasPrefix:@"nfc_"]) {
        // Return custom name or default
        NSString *customName = _config[@"triggers"][triggerKey][@"name"];
        return customName ?: [NSString stringWithFormat:@"NFC Tag %@", [triggerKey substringFromIndex:4]];
    }

    if ([triggerKey hasPrefix:@"wifi_"] || [triggerKey hasPrefix:@"bt_"] || [triggerKey hasPrefix:@"app_launch_"] || [triggerKey hasPrefix:@"notif_"] || [triggerKey hasPrefix:@"notify_"] || [triggerKey hasPrefix:@"sched_"] || [triggerKey hasPrefix:@"mqtt_"] || [triggerKey hasPrefix:@"mqtt_sub_"]) {
        return _config[@"triggers"][triggerKey][@"name"] ?: triggerKey;
    }
    
    return names[triggerKey] ?: triggerKey;
}

- (NSMutableDictionary *)triggerDict:(NSString *)triggerKey {
    NSMutableDictionary *triggers = _config[@"triggers"];
    if (!triggers) {
        triggers = [NSMutableDictionary dictionary];
        _config[@"triggers"] = triggers;
    }
    id trigger = triggers[triggerKey];
    if (!trigger) {
        trigger = [@{ @"enabled": @NO, @"actions": @[] } mutableCopy];
        triggers[triggerKey] = trigger;
    } else if (![trigger isKindOfClass:[NSMutableDictionary class]]) {
        trigger = [trigger mutableCopy];
        triggers[triggerKey] = trigger;
    }
    return trigger;
}

- (BOOL)isTriggerEnabled:(NSString *)triggerKey {
    return [[self triggerDict:triggerKey][@"enabled"] boolValue];
}

- (void)setTriggerEnabled:(BOOL)enabled forTrigger:(NSString *)triggerKey {
    [self triggerDict:triggerKey][@"enabled"] = @(enabled);
    [self saveConfig];
}

- (BOOL)isTriggerFavorite:(NSString *)triggerKey {
    NSArray *favorites = _config[@"favoriteTriggers"];
    return [favorites containsObject:triggerKey];
}

- (void)setTriggerFavorite:(BOOL)favorite forTrigger:(NSString *)triggerKey {
    NSMutableArray *favorites = [(_config[@"favoriteTriggers"] ?: @[]) mutableCopy];

    if (favorite) {
        if (![favorites containsObject:triggerKey]) {
            [favorites addObject:triggerKey];
        }
    } else {
        [favorites removeObject:triggerKey];
    }

    _config[@"favoriteTriggers"] = favorites;
    [self saveConfig];
}

- (NSArray<NSString *> *)orderedFavorites {
    return _config[@"favoriteTriggers"] ?: @[];
}

- (void)setOrderedFavorites:(NSArray<NSString *> *)favorites {
    _config[@"favoriteTriggers"] = [favorites mutableCopy];
    [self saveConfig];
}

- (NSArray *)actionsForTrigger:(NSString *)triggerKey {
    return [self triggerDict:triggerKey][@"actions"] ?: @[];
}

- (void)setActions:(NSArray *)actions forTrigger:(NSString *)triggerKey {
    NSMutableDictionary *trigger = [self triggerDict:triggerKey];
    trigger[@"actions"] = [actions mutableCopy];
    
    // Auto-enable trigger if it has actions, auto-disable if empty
    trigger[@"enabled"] = @(actions.count > 0);
    
    [self saveConfig];
}

- (void)saveConfig {
    // Serialize config to plist data
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:_config 
                                                               format:NSPropertyListXMLFormat_v1_0 
                                                              options:0 
                                                                error:&error];
    if (error) {
        NSLog(@"[RCConfigManager] ERROR serializing config: %@", error);
        return;
    }
    
    // 1. Save to app's own Documents folder (container - this always works)
    NSString *appDocsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *appConfigPath = [appDocsPath stringByAppendingPathComponent:@"rc_triggers.plist"];
    [data writeToFile:appConfigPath atomically:YES];
    NSLog(@"[RCConfigManager] Saved to app Documents: %@", appConfigPath);
    
    // 2. Also save to shared path using POSIX (bypasses sandbox)
    const char *sharedPath = [kConfigPath UTF8String];
    int fd = open(sharedPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        write(fd, [data bytes], [data length]);
        close(fd);
        NSLog(@"[RCConfigManager] Saved to shared path: %@", kConfigPath);
    } else {
        NSLog(@"[RCConfigManager] Could not open shared path (errno=%d): %@", errno, kConfigPath);
    }
    
    // Notify tweak of config change
    notify_post(kConfigChangedNotification);
    
    // Notify App UI
    [[NSNotificationCenter defaultCenter] postNotificationName:RCConfigChangedNotification object:nil];
    
    NSLog(@"[RCConfigManager] Notifications posted");
}

- (void)stopBackgroundNFC {
    NSLog(@"[RCConfigManager] Signaling to stop background NFC scanning");
    notify_post("com.pizzaman.rc.stop_nfc");
}

#pragma mark - UI Color Tweaks

- (NSDictionary *)colorTweaks {
    return _config[@"colorTweaks"] ?: @{};
}

- (void)setColorTweaks:(NSDictionary *)tweaks {
    _config[@"colorTweaks"] = [tweaks mutableCopy];
    [self saveConfig];
}

- (CGFloat)tweakValueForKey:(NSString *)key defaultVal:(CGFloat)defaultVal {
    NSDictionary *tweaks = [self colorTweaks];
    if (tweaks[key] != nil) {
        return [tweaks[key] floatValue];
    }
    
    // Fallback to mode-specific defaults if no user-defined tweak exists
    BOOL isDarkMode = YES;
    if (@available(iOS 13.0, *)) {
        if ([UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleLight) {
            isDarkMode = NO;
        }
    }
    
    if (!isDarkMode) {
        // Return light mode defaults
        if ([key isEqualToString:@"mainBackground"] ||
            [key isEqualToString:@"settingsBackground"] ||
            [key isEqualToString:@"actionPickerBackground"] ||
            [key isEqualToString:@"navBar"]) {
            return 0.94f;
        } else if ([key isEqualToString:@"blockBackground"]) {
            return 1.0f;
        } else if ([key isEqualToString:@"separators"]) {
            return 0.85f;
        } else if ([key isEqualToString:@"borders"]) {
            return 0.88f;
        } else if ([key isEqualToString:@"selectionHighlight"]) {
            return 0.90f;
        }
    }
    
    return defaultVal;
}

- (UIColor *)tweakColorForKey:(NSString *)key defaultVal:(CGFloat)defaultVal {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            BOOL isDarkMode = (traitCollection.userInterfaceStyle != UIUserInterfaceStyleLight);
            
            NSDictionary *tweaks = [self colorTweaks];
            if (tweaks[key] != nil) {
                CGFloat val = [tweaks[key] floatValue];
                return [UIColor colorWithWhite:val alpha:1.0];
            }
            
            if (!isDarkMode) {
                // Return light mode defaults
                if ([key isEqualToString:@"mainBackground"] ||
                    [key isEqualToString:@"settingsBackground"] ||
                    [key isEqualToString:@"actionPickerBackground"] ||
                    [key isEqualToString:@"navBar"]) {
                    return [UIColor colorWithWhite:0.94f alpha:1.0];
                } else if ([key isEqualToString:@"blockBackground"]) {
                    return [UIColor colorWithWhite:1.0f alpha:1.0];
                } else if ([key isEqualToString:@"separators"]) {
                    return [UIColor colorWithWhite:0.85f alpha:1.0];
                } else if ([key isEqualToString:@"borders"]) {
                    return [UIColor colorWithWhite:0.88f alpha:1.0];
                } else if ([key isEqualToString:@"selectionHighlight"]) {
                    return [UIColor colorWithWhite:0.90f alpha:1.0];
                }
            }
            
            // Return dark mode default (defaultVal)
            return [UIColor colorWithWhite:defaultVal alpha:1.0];
        }];
    } else {
        CGFloat val = [self tweakValueForKey:key defaultVal:defaultVal];
        return [UIColor colorWithWhite:val alpha:1.0];
    }
}


#pragma mark - Backup/Restore

- (NSData *)exportConfigAsJSON {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_config
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    if (error) {
        NSLog(@"[RCConfigManager] Export error: %@", error);
        return nil;
    }
    return jsonData;
}

- (BOOL)importConfigFromJSON:(NSData *)jsonData error:(NSError **)error {
    id parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:error];
    if (!parsed || ![parsed isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    
    NSMutableDictionary *importedConfig = (NSMutableDictionary *)parsed;
    
    // Robust Merge Logic
    // 1. Master Switch (if present)
    if (importedConfig[@"masterEnabled"]) {
        _config[@"masterEnabled"] = importedConfig[@"masterEnabled"];
    }
    
    if (importedConfig[@"nfcEnabled"]) {
        _config[@"nfcEnabled"] = importedConfig[@"nfcEnabled"];
    }
    // If missing in import, keep current local setting.
    
    // 2. Triggers (Merge)
    NSDictionary *importedTriggers = importedConfig[@"triggers"];
    if (importedTriggers && [importedTriggers isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *currentTriggers = _config[@"triggers"];
        if (!currentTriggers) {
            currentTriggers = [NSMutableDictionary dictionary];
            _config[@"triggers"] = currentTriggers;
        }
        
        [importedTriggers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            // Overwrite or add
            currentTriggers[key] = [obj mutableCopy];
        }];
    }
    
    [self saveConfig];
    NSLog(@"[RCConfigManager] Config merged successfully. Master: %@, Triggers Updated: %lu", 
          _config[@"masterEnabled"], (unsigned long)importedTriggers.count);
    return YES;
}

- (BOOL)isActionDisabled:(id)actionItem {
    if ([actionItem isKindOfClass:[NSDictionary class]]) {
        id dis = ((NSDictionary *)actionItem)[@"disabled"];
        if (dis && ([dis boolValue] || [dis isEqual:@1] || [[dis description] isEqualToString:@"1"])) {
            return YES;
        }
    }
    return NO;
}

- (id)toggleActionDisabled:(id)actionItem {
    if ([actionItem isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = [((NSDictionary *)actionItem) mutableCopy];
        BOOL currentlyDisabled = [self isActionDisabled:dict];
        if (currentlyDisabled) {
            [dict removeObjectForKey:@"disabled"];
            // If it only wrapped a command and has no other keys except command (or type=command), we can unwrap or keep as dict
            if (dict[@"command"] && dict.count == 1) {
                return dict[@"command"];
            }
            return dict;
        } else {
            dict[@"disabled"] = @YES;
            return dict;
        }
    } else if ([actionItem isKindOfClass:[NSString class]]) {
        return @{
            @"command": (NSString *)actionItem,
            @"disabled": @YES
        };
    }
    return actionItem;
}

- (NSString *)nameForCommand:(id)cmdId truncate:(BOOL)shouldTruncate {
    if ([cmdId isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)cmdId;
        if (dict[@"command"] && [dict[@"command"] isKindOfClass:[NSString class]]) {
            return [self nameForCommand:dict[@"command"] truncate:shouldTruncate];
        }
        NSString *type = [[dict[@"type"] description] lowercaseString];
        if ([type isEqualToString:@"if"] || [type isEqualToString:@"else_if"]) {
            NSString *conditionTitle = dict[@"conditionTitle"] ?: dict[@"conditionName"];
            NSString *expectedTitle = dict[@"expectedTitle"] ?: dict[@"expectedLabel"] ?: dict[@"expectedValue"];
            NSString *prefix = [type isEqualToString:@"else_if"] ? @"Else If" : @"If";
            NSString *condKey = dict[@"conditionKey"] ?: dict[@"conditionName"] ?: @"";
            if ([condKey isEqualToString:@"time_between"] || [conditionTitle.lowercaseString containsString:@"time"]) {
                return [NSString stringWithFormat:@"%@ Time is Between %@", prefix, expectedTitle ?: @"Time Range"];
            }
            if (conditionTitle.length > 0 && expectedTitle.length > 0) {
                return [NSString stringWithFormat:@"%@ %@ is %@", prefix, conditionTitle, expectedTitle];
            }
            NSString *legacy = dict[@"condition"] ?: @"Condition";
            return [NSString stringWithFormat:@"%@ %@", prefix, legacy];
        } else if ([type isEqualToString:@"else"]) {
            return @"Else";
        } else if ([type isEqualToString:@"repeat"]) {
            return [NSString stringWithFormat:@"Repeat %@", dict[@"count"] ?: @""];
        } else if ([type isEqualToString:@"end"] || [type isEqualToString:@"end_if"]) {
            return @"End If";
        }
        return @"Conditional Block";
    }
    
    if (![cmdId isKindOfClass:[NSString class]]) {
        return @"Unknown Action";
    }

    NSString *originalCmd = [(NSString *)cmdId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *cmd = [originalCmd lowercaseString];
    NSDictionary *names = @{
        @"play": @"Play",
        @"pause": @"Pause",
        @"playpause": @"Play/Pause",
        @"next": @"Next Track",
        @"prev": @"Previous Track",
        @"volume up": @"Volume Up",
        @"volume down": @"Volume Down",
        @"flashlight": @"Flashlight Toggle",
        @"flashlight on": @"Flashlight On",
        @"flashlight off": @"Flashlight Off",
        @"flashlight toggle": @"Flashlight Toggle",
        @"appearance dark": @"Appearance Dark",
        @"appearance light": @"Appearance Light",
        @"appearance toggle": @"Appearance Toggle",
        @"rotate lock": @"Rotate Lock",
        @"rotate unlock": @"Rotate Unlock",
        @"rotate toggle": @"Rotate Toggle",
        @"wifi on": @"WiFi On",
        @"wifi off": @"WiFi Off",
        @"wifi toggle": @"WiFi Toggle",
        @"cellular on": @"Cellular On",
        @"cellular off": @"Cellular Off",
        @"cellular toggle": @"Cellular Toggle",
        @"cell on": @"Cellular On",
        @"cell off": @"Cellular Off",
        @"cell toggle": @"Cellular Toggle",
        @"bluetooth on": @"Bluetooth On",
        @"bluetooth off": @"Bluetooth Off",
        @"bluetooth toggle": @"Bluetooth Toggle",
        @"bt toggle": @"Bluetooth Toggle",
        @"location on": @"Location Services On",
        @"location off": @"Location Services Off",
        @"location toggle": @"Location Services Toggle",
        @"location status": @"Location Services Status",
        @"gps on": @"Location Services On",
        @"gps off": @"Location Services Off",
        @"gps toggle": @"Location Services Toggle",
        @"haptic": @"Haptic Feedback",
        @"screenshot": @"Screenshot",
        @"screenrecord": @"Screen Recording Toggle",
        @"screenrecord toggle": @"Screen Recording Toggle",
        @"screenrecord start": @"Start Screen Recording",
        @"screenrecord stop": @"Stop Screen Recording",
        @"screenrecord status": @"Screen Recording Status",
        @"snapper": @"Snapper: Open Area",
        @"snapper open": @"Snapper: Open Area",
        @"snapper freeze": @"Snapper: Freeze Screen",
        @"snapper instant": @"Snapper: Instant Snap",
        @"snapper close": @"Snapper: Close All",
        @"lock": @"Lock Device",
        @"unlock": @"Unlock Device",
        @"lock toggle": @"Lock Toggle",
        @"lock status": @"Lock Status",
        @"dnd on": @"Do Not Disturb On",
        @"dnd off": @"Do Not Disturb Off",
        @"dnd toggle": @"Do Not Disturb Toggle",
        @"respring": @"Respring",
        @"safemode": @"Safe Mode",
        @"safe-mode": @"Safe Mode",
        @"safe_mode": @"Safe Mode",
        @"lpm on": @"Low Power Mode On",
        @"lpm off": @"Low Power Mode Off",
        @"lpm toggle": @"Low Power Mode Toggle",
        @"anc on": @"Noise Cancellation On",
        @"anc off": @"Noise Cancellation Off",
        @"anc transparency": @"Transparency Mode",
        @"airplay disconnect": @"Disconnect AirPlay",
        @"airplane on": @"Airplane On",
        @"airplane off": @"Airplane Off",
        @"airplane toggle": @"Airplane Toggle",
        @"audiomix on": @"AudioMix On",
        @"audiomix off": @"AudioMix Off",
        @"audiomix toggle": @"AudioMix Toggle",
        @"audiomix status": @"AudioMix Status",
        @"audiomix": @"AudioMix Toggle",
        @"low power on": @"Low Power Mode On",
        @"low power off": @"Low Power Mode Off",
        @"low power mode on": @"Low Power Mode On",
        @"low power mode off": @"Low Power Mode Off",
        @"low power toggle": @"Low Power Mode Toggle",
        @"low power mode toggle": @"Low Power Mode Toggle",
        @"mute toggle": @"Mute Toggle",
        @"mute on": @"Mute On",
        @"mute off": @"Mute Off",
        @"mute status": @"Mute Status",
        @"mute": @"Mute Toggle",
        @"siri": @"Activate Siri",
        @"home": @"Home Button",
        @"open control center": @"Open Control Center",
        @"control center": @"Open Control Center",
        @"ldrestart": @"Soft Reboot (ldrestart)",
        @"userspace-reboot": @"Userspace Reboot",
        @"uicache": @"Refresh Icon Cache",
        @"player status": @"Player Status",
        @"switcher": @"App Switcher",
        @"previous app": @"Previous App",
        @"last app": @"Previous App",
        // Touch gestures
        @"swipeU": @"Swipe Up",
        @"swipeUp": @"Swipe Up",
        @"swipeD": @"Swipe Down",
        @"swipeDown": @"Swipe Down",
        @"swipeL": @"Swipe Left",
        @"swipeLeft": @"Swipe Left",
        @"swipeR": @"Swipe Right",
        @"swipeRight": @"Swipe Right",
        // System Vibration
        @"vibration silent-on": @"Silent Vibrate On",
        @"vibration silent-off": @"Silent Vibrate Off",
        @"vibration silent-toggle": @"Silent Vibrate Toggle",
        @"vibration silent-status": @"Silent Vibrate Status",
        @"vibration ring-on": @"Ring Vibrate On",
        @"vibration ring-off": @"Ring Vibrate Off",
        @"vibration ring-toggle": @"Ring Vibrate Toggle",
        @"vibration ring-status": @"Ring Vibrate Status",
        @"queuealbum": @"Queue Current Album",
        @"queue album": @"Queue Current Album",
        @"queueartist": @"Queue Artist",
        @"queue artist": @"Queue Artist",
        @"shuffleall": @"Shuffle All Songs",
        @"shuffle all songs": @"Shuffle All Songs",
        @"suffle all songs": @"Shuffle All Songs",
        @"deletesong": @"Delete Currently Playing Song",
        @"delete song": @"Delete Currently Playing Song",
        @"delete current song": @"Delete Currently Playing Song",
        @"sneakycam photo": @"SneakyCam Photo",
        @"sneakycam takephoto": @"SneakyCam Photo",
        @"sneakycam video": @"SneakyCam Video",
        @"sneakycam record": @"SneakyCam Video",
        @"sneakycam startstopvideo": @"SneakyCam Video",
        @"camera video 2x flash": @"Open Video Camera (2x, Flash)",
        @"camera video 2x": @"Open Video Camera (2x)",
        @"camera video flash": @"Open Video Camera (2x, Flash)",
        @"camera video": @"Open Video Camera (2x)",
        @"open camera video 2x flash": @"Open Video Camera (2x, Flash)",
        @"open camera video 2x": @"Open Video Camera (2x)",
        @"open camera video flash": @"Open Video Camera (2x, Flash)",
        @"open camera video": @"Open Video Camera (2x)",
        @"camera 2x flash": @"Open Video Camera (2x, Flash)",
        @"camera 2x": @"Open Video Camera (2x)",
        @"open camera 2x flash": @"Open Video Camera (2x, Flash)",
        @"open camera 2x": @"Open Video Camera (2x)",
        @"camera photo 0.5x": @"Open Camera (Photo 0.5x)",
        @"camera photo 2x": @"Open Camera (Photo 2x)",
        @"camera photo": @"Open Camera (Photo)",
        @"camera portrait 2x": @"Open Camera (Portrait 2x)",
        @"camera portrait": @"Open Camera (Portrait)",
        @"camera front": @"Open Camera (Front Selfie)",
        @"camera selfie": @"Open Camera (Front Selfie)",
        @"camera slomo": @"Open Camera (Slo-Mo)",
        @"camera timelapse": @"Open Camera (Time-Lapse)",
        @"camera cinematic": @"Open Camera (Cinematic)",
        @"camera pano": @"Open Camera (Pano)",
        @"camera shutter": @"Camera Shutter / Snap",
        @"camera snap": @"Camera Shutter / Snap",
        @"camera record": @"Camera Record Toggle",
        @"camera record toggle": @"Camera Record Toggle"
    };
    
    NSString *result = names[cmd];
    
    if (!result) {
        if ([cmd hasPrefix:@"camera"] || [cmd hasPrefix:@"open camera"]) {
            NSString *low = [cmd lowercaseString];
            NSString *modeName = @"Photo";
            if ([low containsString:@"video"] || [low containsString:@"2x"]) modeName = @"Video";
            if ([low containsString:@"photo"]) modeName = @"Photo";
            if ([low containsString:@"portrait"]) modeName = @"Portrait";
            if ([low containsString:@"slomo"] || [low containsString:@"slo-mo"]) modeName = @"Slo-Mo";
            if ([low containsString:@"timelapse"] || [low containsString:@"time-lapse"]) modeName = @"Time-Lapse";
            if ([low containsString:@"pano"] || [low containsString:@"panorama"]) modeName = @"Pano";
            if ([low containsString:@"cinematic"]) modeName = @"Cinematic";
            
            NSMutableArray *details = [NSMutableArray array];
            if ([low containsString:@"front"] || [low containsString:@"selfie"]) [details addObject:@"Front"];
            
            NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:@"(\\d+(\\.\\d+)?)\\s*x" options:NSRegularExpressionCaseInsensitive error:nil];
            NSTextCheckingResult *m = [rx firstMatchInString:low options:0 range:NSMakeRange(0, low.length)];
            if (m) {
                [details addObject:[low substringWithRange:[m rangeAtIndex:0]]];
            } else if ([modeName isEqualToString:@"Video"] && ![low containsString:@"front"]) {
                [details addObject:@"2x"];
            }
            
            if ([low containsString:@"flash"] || [low containsString:@"torch"]) [details addObject:@"Flash"];
            if ([low containsString:@"record"]) [details addObject:@"Record"];
            if ([low containsString:@"snap"]) [details addObject:@"Snap"];
            
            NSString *detStr = (details.count > 0) ? [NSString stringWithFormat:@" (%@)", [details componentsJoinedByString:@", "]] : @"";
            result = [NSString stringWithFormat:@"Open Camera (%@%@)", modeName, detStr];
        } else if ([cmd hasPrefix:@"root "]) {
            result = [NSString stringWithFormat:@"[root] %@", [cmd substringFromIndex:5]];
        } else if ([cmd hasPrefix:@"exec-root "]) {
            result = [NSString stringWithFormat:@"[root] %@", [cmd substringFromIndex:10]];
        } else if ([cmd hasPrefix:@"exec "]) {
            result = [cmd substringFromIndex:5];
        } else if ([cmd hasPrefix:@"delay "]) {
            result = [NSString stringWithFormat:@"Delay %@s", [cmd substringFromIndex:6]];
        } else if ([cmd hasPrefix:@"bt connect "] || [cmd hasPrefix:@"bluetooth connect "]) {
            NSString *val = [cmd hasPrefix:@"bluetooth connect "] ? [cmd substringFromIndex:18] : [cmd substringFromIndex:11];
            result = [NSString stringWithFormat:@"Connect %@", val];
        } else if ([cmd hasPrefix:@"bt disconnect "] || [cmd hasPrefix:@"bluetooth disconnect "]) {
            NSString *val = [cmd hasPrefix:@"bluetooth disconnect "] ? [cmd substringFromIndex:21] : [cmd substringFromIndex:14];
            result = [NSString stringWithFormat:@"Disconnect %@", val];
        } else if ([cmd hasPrefix:@"airplay connect "]) {
            NSString *val = [cmd substringFromIndex:16];
            if ([val containsString:@" # "]) {
                val = [val componentsSeparatedByString:@" # "].lastObject;
            }
            result = [NSString stringWithFormat:@"Connect %@", val];
        } else if ([cmd hasPrefix:@"airplay disconnect"]) {
            result = @"Disconnect Airplay";
        } else if ([cmd hasPrefix:@"set-vol "]) {
            result = [NSString stringWithFormat:@"Set Volume %@", [cmd substringFromIndex:8]];
        } else if ([cmd hasPrefix:@"brightness "]) {
            result = [NSString stringWithFormat:@"Set Brightness %@", [cmd substringFromIndex:11]];
        } else if ([cmd hasPrefix:@"flashlight "] && ![[cmd lowercaseString] hasSuffix:@"on"] && ![[cmd lowercaseString] hasSuffix:@"off"] && ![[cmd lowercaseString] hasSuffix:@"toggle"]) {
            result = [NSString stringWithFormat:@"Flashlight %@%%", [cmd substringFromIndex:11]];
        } else if ([cmd hasPrefix:@"flash "] && ![[cmd lowercaseString] hasSuffix:@"on"] && ![[cmd lowercaseString] hasSuffix:@"off"] && ![[cmd lowercaseString] hasSuffix:@"toggle"]) {
            result = [NSString stringWithFormat:@"Flashlight %@%%", [cmd substringFromIndex:6]];
        } else if ([cmd hasPrefix:@"shortcut:"]) {
            result = [NSString stringWithFormat:@"Run %@", [cmd substringFromIndex:9]];
        } else if ([cmd hasPrefix:@"snapper "] || [cmd isEqualToString:@"snapper"]) {
            NSString *sub = [cmd hasPrefix:@"snapper "] ? [cmd substringFromIndex:8] : @"";
            if ([sub isEqualToString:@"freeze"]) result = @"Snapper: Freeze Screen";
            else if ([sub isEqualToString:@"instant"]) result = @"Snapper: Instant Snap";
            else if ([sub isEqualToString:@"close"]) result = @"Snapper: Close All";
            else result = @"Snapper: Open Area";
        } else if ([cmd hasPrefix:@"ha "] || [cmd isEqualToString:@"ha"]) {
            NSString *raw = [cmd hasPrefix:@"ha "] ? [cmd substringFromIndex:3] : @"";
            NSArray *parts = [raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSMutableArray *cleanParts = [NSMutableArray array];
            for (NSString *p in parts) {
                if (p.length > 0) [cleanParts addObject:p];
            }
            NSString *subCmd = cleanParts.firstObject ? [(NSString *)cleanParts.firstObject lowercaseString] : @"";
            
            NSString *(^formatEntity)(NSString *) = ^(NSString *eid) {
                if (!eid.length) return @"";
                NSArray *p = [eid componentsSeparatedByString:@"."];
                if (p.count > 1) {
                    NSString *name = [p[1] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
                    NSMutableArray *words = [NSMutableArray array];
                    for (NSString *w in [name componentsSeparatedByString:@" "]) {
                        if (w.length > 0) {
                            [words addObject:[NSString stringWithFormat:@"%@%@", [[w substringToIndex:1] uppercaseString], [w substringFromIndex:1]]];
                        }
                    }
                    return [words componentsJoinedByString:@" "];
                }
                return eid;
            };

            if ([subCmd isEqualToString:@"toggle"] && cleanParts.count > 1) {
                NSString *eid = cleanParts[1];
                result = [NSString stringWithFormat:@"HA Toggle: %@", formatEntity(eid)];
            } else if ([subCmd isEqualToString:@"turn_on"] && cleanParts.count > 1) {
                NSString *eid = cleanParts[1];
                result = [NSString stringWithFormat:@"HA Turn On: %@", formatEntity(eid)];
            } else if ([subCmd isEqualToString:@"turn_off"] && cleanParts.count > 1) {
                NSString *eid = cleanParts[1];
                result = [NSString stringWithFormat:@"HA Turn Off: %@", formatEntity(eid)];
            } else if ([subCmd isEqualToString:@"call"] && cleanParts.count > 1) {
                NSString *service = cleanParts[1];
                NSString *eid = cleanParts.count > 2 ? cleanParts[2] : @"";
                result = [NSString stringWithFormat:@"HA Call %@%@", service, eid.length ? [NSString stringWithFormat:@": %@", formatEntity(eid)] : @""];
            } else {
                result = [NSString stringWithFormat:@"HA: %@", raw.length ? raw : @"Control"];
            }
        } else if ([cmd hasPrefix:@"km "] || [cmd isEqualToString:@"km"]) {
            NSString *raw = [originalCmd length] >= 3 ? [[originalCmd substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
            if ([[raw lowercaseString] hasPrefix:@"trigger "]) {
                NSString *afterTrigger = [[raw substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSString *macro = nil;
                NSString *val = nil;
                if ([afterTrigger hasPrefix:@"\""]) {
                    NSRange endQuote = [afterTrigger rangeOfString:@"\"" options:0 range:NSMakeRange(1, afterTrigger.length - 1)];
                    if (endQuote.location != NSNotFound) {
                        macro = [afterTrigger substringWithRange:NSMakeRange(1, endQuote.location - 1)];
                        NSString *rem = [[afterTrigger substringFromIndex:endQuote.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        if (rem.length > 0) {
                            if ([rem hasPrefix:@"\""] && [rem hasSuffix:@"\""] && rem.length >= 2) {
                                val = [rem substringWithRange:NSMakeRange(1, rem.length - 2)];
                            } else {
                                val = rem;
                            }
                        }
                    }
                }
                if (!macro) {
                    NSArray *p = [afterTrigger componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSMutableArray *cp = [NSMutableArray array];
                    for (NSString *item in p) { if (item.length > 0) [cp addObject:item]; }
                    if (cp.count > 0) {
                        macro = cp[0];
                        if (cp.count > 1) {
                            val = [[cp subarrayWithRange:NSMakeRange(1, cp.count - 1)] componentsJoinedByString:@" "];
                        }
                    }
                }
                if (macro.length > 0) {
                    NSString *displayMacro = [self nameForKMMacroUid:macro] ?: macro;
                    result = val.length > 0 ? [NSString stringWithFormat:@"KM: %@ (%@)", displayMacro, val] : [NSString stringWithFormat:@"KM: %@", displayMacro];
                } else {
                    result = @"KM Trigger";
                }
            } else if ([[raw lowercaseString] hasPrefix:@"url "]) {
                result = [NSString stringWithFormat:@"KM URL: %@", [raw substringFromIndex:4]];
            } else if (raw.length > 0) {
                result = [NSString stringWithFormat:@"KM: %@", raw];
            } else {
                result = @"Keyboard Maestro";
            }
        } else if ([cmd hasPrefix:@"mqtt "] || [cmd isEqualToString:@"mqtt"]) {
            NSString *raw = [cmd hasPrefix:@"mqtt "] ? [cmd substringFromIndex:5] : @"";
            raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([raw hasPrefix:@"pub "] || [raw hasPrefix:@"publish "]) {
                NSString *args = [raw hasPrefix:@"publish "] ? [raw substringFromIndex:8] : [raw substringFromIndex:4];
                args = [args stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSArray *parts = [args componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSMutableArray *clean = [NSMutableArray array];
                for (NSString *p in parts) { if (p.length > 0) [clean addObject:p]; }
                if (clean.count > 0) {
                    NSString *topic = clean[0];
                    if (clean.count > 1) {
                        NSString *payload = [[clean subarrayWithRange:NSMakeRange(1, clean.count - 1)] componentsJoinedByString:@" "];
                        result = [NSString stringWithFormat:@"MQTT: %@ (%@)", topic, payload];
                    } else {
                        result = [NSString stringWithFormat:@"MQTT: %@", topic];
                    }
                } else {
                    result = @"MQTT Publish";
                }
            } else if (raw.length > 0) {
                result = [NSString stringWithFormat:@"MQTT: %@", raw];
            } else {
                result = @"MQTT";
            }
        } else if ([cmd hasPrefix:@"Lua "] || [cmd hasPrefix:@"lua_eval "] || [cmd hasPrefix:@"lua-eval "] || [cmd hasPrefix:@"lua "]) {
            result = @"Lua Script";
        } else if ([cmd hasPrefix:@"spotify "]) {
            result = @"Spotify";
        // Touch gestures with coordinates
        } else if ([cmd hasPrefix:@"tap "]) {
            NSString *coords = [[cmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            result = [NSString stringWithFormat:@"Tap at %@", coords];
        } else if ([cmd hasPrefix:@"hold "]) {
            NSString *coords = [[cmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            result = [NSString stringWithFormat:@"Hold at %@", coords];
        } else if ([cmd hasPrefix:@"swipe "]) {
            NSString *coords = [[cmd substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            result = [NSString stringWithFormat:@"Swipe %@", coords];
        } else if ([cmd hasPrefix:@"uiopen "]) {
            NSString *bundleId = [cmd substringFromIndex:7];
            Class LSProxy = NSClassFromString(@"LSApplicationProxy");
            if (LSProxy) {
                id app = [LSProxy performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleId];
                if (app) {
                    NSString *appName = [app performSelector:@selector(localizedName)];
                    if (appName) {
                        result = [NSString stringWithFormat:@"Open %@", appName];
                    } else {
                       result = [NSString stringWithFormat:@"Open %@", bundleId];
                    }
                } else {
                    result = [NSString stringWithFormat:@"Open %@", bundleId];
                }
            } else {
                result = [NSString stringWithFormat:@"Open %@", bundleId];
            }
        } else if ([cmd hasPrefix:@"kill "]) {
            NSString *bundleId = [cmd substringFromIndex:5];
            Class LSProxy = NSClassFromString(@"LSApplicationProxy");
            if (LSProxy) {
                id app = [LSProxy performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleId];
                if (app) {
                    NSString *appName = [app performSelector:@selector(localizedName)];
                    if (appName) {
                        result = [NSString stringWithFormat:@"Kill %@", appName];
                    } else {
                       result = [NSString stringWithFormat:@"Kill %@", bundleId];
                    }
                } else {
                    result = [NSString stringWithFormat:@"Kill %@", bundleId];
                }
            } else {
                result = [NSString stringWithFormat:@"Kill %@", bundleId];
            }
        } else {
            result = cmd;
        }
    }
    
    // Final truncation to keep the detail labels from overflowing
    // Use middle truncation: "Start...End"
    if (shouldTruncate && result.length > 40) {
        result = [[result substringToIndex:37] stringByAppendingString:@"..."];
    }
    
    return result;
}

- (NSString *)nameForBundleId:(NSString *)bundleId {
    if (!bundleId || bundleId.length == 0) return nil;
    
    Class LSProxy = NSClassFromString(@"LSApplicationProxy");
    if (LSProxy) {
        id app = [LSProxy performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleId];
        if (app) {
            return [app performSelector:@selector(localizedName)];
        }
    }
    return nil;
}

- (NSString *)iconForCommand:(id)cmdId {
    if ([cmdId isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)cmdId;
        if (dict[@"command"] && [dict[@"command"] isKindOfClass:[NSString class]]) {
            return [self iconForCommand:dict[@"command"]];
        }
        NSString *type = [[dict[@"type"] description] lowercaseString];
        if ([type isEqualToString:@"if"] || [type isEqualToString:@"else_if"] || [type isEqualToString:@"else"]) {
            return @"arrow.triangle.branch";
        } else if ([type isEqualToString:@"repeat"]) {
            return @"repeat";
        } else if ([type isEqualToString:@"end"] || [type isEqualToString:@"end_if"]) {
            return @"arrow.turn.up.left";
        }
        return @"square.grid.2x2";
    }

    NSString *cmd = [[(NSString *)cmdId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([cmd hasPrefix:@"camera"] || [cmd hasPrefix:@"open camera"]) {
        if ([cmd containsString:@"flash"] || [cmd containsString:@"torch"]) return @"bolt.fill";
        if ([cmd containsString:@"front"] || [cmd containsString:@"selfie"]) return @"person.fill";
        if ([cmd containsString:@"portrait"]) return @"person.crop.square";
        if ([cmd containsString:@"video"] || [cmd containsString:@"slomo"] || [cmd containsString:@"timelapse"] || [cmd containsString:@"cinematic"] || [cmd containsString:@"2x"]) return @"video.fill";
        return @"camera.fill";
    }
    if ([cmd hasPrefix:@"sneakycam photo"] || [cmd isEqualToString:@"sneakycam takephoto"]) return @"camera.aperture";
    if ([cmd hasPrefix:@"sneakycam video"] || [cmd isEqualToString:@"sneakycam record"] || [cmd isEqualToString:@"sneakycam startstopvideo"]) return @"video.fill";
    if ([cmd hasPrefix:@"snapper freeze"]) return @"snowflake";
    if ([cmd hasPrefix:@"snapper instant"]) return @"bolt.fill";
    if ([cmd hasPrefix:@"snapper close"]) return @"xmark.circle";
    if ([cmd hasPrefix:@"snapper"]) return @"crop";
    if ([cmd hasPrefix:@"ha "] || [cmd isEqualToString:@"ha"]) return @"house.fill";
    if ([cmd hasPrefix:@"km "] || [cmd isEqualToString:@"km"]) return @"command";
    if ([cmd hasPrefix:@"mqtt "] || [cmd isEqualToString:@"mqtt"]) return @"antenna.radiowaves.left.and.right";
    if ([cmd hasPrefix:@"toast"]) return @"text.bubble.fill";
    if ([cmd hasPrefix:@"root "] || [cmd hasPrefix:@"exec-root "]) return @"terminal.fill";
    if ([cmd hasPrefix:@"exec "]) return @"terminal.fill";
    if ([cmd hasPrefix:@"delay "]) return @"timer";
    if ([cmd hasPrefix:@"bt connect "] || [cmd hasPrefix:@"bluetooth connect "]) return @"link";
    if ([cmd hasPrefix:@"bt disconnect "] || [cmd hasPrefix:@"bluetooth disconnect "]) return @"xmark.circle";
    if ([cmd hasPrefix:@"airplay connect "]) return @"airplayaudio";
    if ([cmd hasPrefix:@"shortcut:"]) return @"command";
    if ([cmd hasPrefix:@"set-vol "]) return @"speaker.wave.3.fill";
    if ([cmd hasPrefix:@"brightness "]) return @"sun.max.fill";
    if ([cmd hasPrefix:@"flashlight "] || [cmd hasPrefix:@"flash "]) return @"flashlight.on.fill";
    if ([cmd hasPrefix:@"Lua "] || [cmd hasPrefix:@"lua_eval "] || [cmd hasPrefix:@"lua-eval "] || [cmd hasPrefix:@"lua "]) return @"scroll.fill";
    if ([cmd hasPrefix:@"spotify "]) return @"music.note";
    if ([cmd isEqualToString:@"home"]) return @"house.fill";
    if ([cmd hasPrefix:@"uiopen "]) return [NSString stringWithFormat:@"USER_APP:%@", [cmd substringFromIndex:7]];
    if ([cmd hasPrefix:@"kill "]) return [NSString stringWithFormat:@"USER_APP:%@", [cmd substringFromIndex:5]];
    // Touch gesture prefix icons
    if ([cmd hasPrefix:@"tap "]) return @"hand.tap.fill";
    if ([cmd hasPrefix:@"hold "]) return @"hand.point.up.left.fill";
    if ([cmd hasPrefix:@"swipe "]) return @"hand.draw.fill";
    
    NSDictionary *icons = @{
        @"play": @"play.fill",
        @"pause": @"pause.fill",
        @"playpause": @"playpause.fill",
        @"next": @"forward.fill",
        @"prev": @"backward.fill",
        @"volume up": @"speaker.wave.3.fill",
        @"volume down": @"speaker.wave.1.fill",
        @"flashlight": @"flashlight.on.fill",
        @"flashlight on": @"flashlight.on.fill",
        @"flashlight off": @"flashlight.off.fill",
        @"flashlight toggle": @"flashlight.on.fill",
        @"appearance dark": @"moon.fill",
        @"appearance light": @"sun.max.fill",
        @"appearance toggle": @"moon.fill",
        @"rotate lock": @"lock.rotation",
        @"rotate unlock": @"lock.rotation.open",
        @"rotate toggle": @"lock.rotation",
        @"wifi on": @"wifi",
        @"wifi off": @"wifi.slash",
        @"wifi toggle": @"wifi",
        @"cellular on": @"antenna.radiowaves.left.and.right",
        @"cellular off": @"antenna.radiowaves.left.and.right",
        @"cellular toggle": @"antenna.radiowaves.left.and.right",
        @"cell on": @"antenna.radiowaves.left.and.right",
        @"cell off": @"antenna.radiowaves.left.and.right",
        @"cell toggle": @"antenna.radiowaves.left.and.right",
        @"cellular": @"antenna.radiowaves.left.and.right",
        @"cell": @"antenna.radiowaves.left.and.right",
        @"bluetooth on": @"bolt.horizontal.fill",
        @"bluetooth off": @"bolt.horizontal",
        @"bluetooth toggle": @"bolt.horizontal.fill",
        @"bt toggle": @"bolt.horizontal.fill",
        @"location on": @"location.fill",
        @"location off": @"location.slash",
        @"location toggle": @"location.fill",
        @"location status": @"location.circle",
        @"gps on": @"location.fill",
        @"gps off": @"location.slash",
        @"gps toggle": @"location.fill",
        @"airplane on": @"airplane",
        @"airplane off": @"airplane",
        @"airplane toggle": @"airplane",
        @"haptic": @"hand.tap.fill",
        @"screenshot": @"camera.fill",
        @"screenrecord": @"record.circle.fill",
        @"screenrecord toggle": @"record.circle.fill",
        @"screenrecord start": @"record.circle.fill",
        @"screenrecord stop": @"stop.circle.fill",
        @"screenrecord status": @"record.circle",
        @"snapper": @"crop",
        @"snapper open": @"crop",
        @"snapper freeze": @"snowflake",
        @"snapper instant": @"bolt.fill",
        @"snapper close": @"xmark.circle",
        @"lock": @"lock.fill",
        @"unlock": @"lock.open.fill",
        @"lock toggle": @"lock.circle",
        @"lock status": @"lock.circle",
        @"dnd on": @"moon.fill",
        @"dnd off": @"moon",
        @"dnd toggle": @"moon.circle.fill",
        @"respring": @"memories",
        @"safemode": @"shield.slash.fill",
        @"safe-mode": @"shield.slash.fill",
        @"safe_mode": @"shield.slash.fill",
        @"lpm on": @"battery.25",
        @"lpm off": @"battery.100",
        @"lpm toggle": @"battery.25",
        @"low power on": @"battery.25",
        @"low power off": @"battery.100",
        @"low power toggle": @"battery.25",
        @"low power mode on": @"battery.25",
        @"low power mode off": @"battery.100",
        @"low power mode toggle": @"battery.25",
        @"anc on": @"ear.badge.checkmark",
        @"anc off": @"ear",
        @"anc transparency": @"waveform.circle.fill",
        @"audiomix on": @"music.note",
        @"audiomix off": @"music.note",
        @"audiomix toggle": @"music.note",
        @"audiomix status": @"music.note",
        @"audiomix": @"music.note",
        @"airplay disconnect": @"airplayaudio.badge.exclamationmark",
        @"mute toggle": @"speaker.slash.fill",
        @"mute on": @"speaker.slash.fill",
        @"mute off": @"speaker.wave.2.fill",
        @"mute status": @"speaker.slash.fill",
        @"mute": @"speaker.slash.fill",
        @"siri": @"mic.circle.fill",
        @"open control center": @"switch.2",
        @"control center": @"switch.2",
        @"ldrestart": @"arrow.clockwise",
        @"userspace-reboot": @"arrow.clockwise.circle",
        @"uicache": @"square.grid.2x2",
        @"player status": @"play.circle.fill",
        @"vibration silent-on": @"bell.slash",
        @"vibration silent-off": @"bell.slash",
        @"vibration silent-toggle": @"bell.slash",
        @"vibration silent-status": @"bell.slash.circle",
        @"vibration ring-on": @"bell",
        @"vibration ring-off": @"bell",
        @"vibration ring-toggle": @"bell",
        @"vibration ring-status": @"bell.circle",
        @"switcher": @"square.stack.3d.up.fill",
        @"previous app": @"arrow.uturn.backward",
        @"last app": @"arrow.uturn.backward",
        @"queuealbum": @"music.note.list",
        @"queue album": @"music.note.list",
        @"queueartist": @"music.mic",
        @"queue artist": @"music.mic",
        @"shuffleall": @"shuffle",
        @"shuffle all songs": @"shuffle",
        @"deletesong": @"trash",
        @"delete song": @"trash",
        @"delete current song": @"trash",
        // Touch gestures
        @"swipeU": @"arrow.up.circle.fill",
        @"swipeUp": @"arrow.up.circle.fill",
        @"swipeD": @"arrow.down.circle.fill",
        @"swipeDown": @"arrow.down.circle.fill",
        @"swipeL": @"arrow.left.circle.fill",
        @"swipeLeft": @"arrow.left.circle.fill",
        @"swipeR": @"arrow.right.circle.fill",
        @"swipeRight": @"arrow.right.circle.fill"
    };
    
    NSString *result = icons[cmd];
    
    if (!result) {
        if ([cmd hasPrefix:@"root "]) return @"command.square";
        if ([cmd hasPrefix:@"delay "]) return @"timer";
        if ([cmd hasPrefix:@"exec "]) return @"chevron.right.square";
        if ([cmd hasPrefix:@"flashlight "] || [cmd hasPrefix:@"flash "]) return @"flashlight.on.fill";
        if ([cmd hasPrefix:@"low power "]) return @"battery.100.bolt";
    }
    
    return result ?: @"circle.fill";
}

- (NSDictionary *)toggleInfoForCommand:(NSString *)cmd {
    if (![cmd isKindOfClass:[NSString class]]) return nil;
    
    NSString *lower = [cmd lowercaseString];
    
    NSArray *definitions = @[
        @{
            @"key": @"screenrecord",
            @"name": @"Screen Recording",
            @"icon": @"record.circle.fill",
            @"prefixes": @[@"screenrecord ", @"record screen "],
            @"suffixes": @[@"toggle", @"start", @"stop"],
            @"displaySuffixes": @[@"Toggle", @"Start", @"Stop"],
            @"exactMatches": @{ @"screenrecord": @"toggle" }
        },
        @{
            @"key": @"airplane",
            @"name": @"Airplane Mode",
            @"icon": @"airplane",
            @"prefixes": @[@"airplane "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"low_power",
            @"name": @"Low Power Mode",
            @"icon": @"battery.25",
            @"prefixes": @[@"low power ", @"lpm ", @"low power mode "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"dnd",
            @"name": @"Do Not Disturb",
            @"icon": @"moon.fill",
            @"prefixes": @[@"dnd "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"wifi",
            @"name": @"Wi-Fi",
            @"icon": @"wifi",
            @"prefixes": @[@"wifi "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"cellular",
            @"name": @"Cellular Data",
            @"icon": @"antenna.radiowaves.left.and.right",
            @"prefixes": @[@"cellular ", @"cell "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"bluetooth",
            @"name": @"Bluetooth",
            @"icon": @"bolt.horizontal.fill",
            @"prefixes": @[@"bluetooth ", @"bt "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"location",
            @"name": @"Location Services",
            @"icon": @"location.fill",
            @"prefixes": @[@"location ", @"locationservices ", @"location services ", @"gps "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"flashlight",
            @"name": @"Flashlight",
            @"icon": @"flashlight.on.fill",
            @"prefixes": @[@"flashlight ", @"flash "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"appearance",
            @"name": @"Appearance",
            @"icon": @"moon.fill",
            @"prefixes": @[@"appearance "],
            @"suffixes": @[@"dark", @"light", @"toggle"],
            @"displaySuffixes": @[@"Dark", @"Light", @"Toggle"]
        },
        @{
            @"key": @"audiomix",
            @"name": @"AudioMix",
            @"icon": @"music.note",
            @"prefixes": @[@"audiomix "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"],
            @"exactMatches": @{ @"audiomix": @"toggle" }
        },
        @{
            @"key": @"rotate",
            @"name": @"Rotation Lock",
            @"icon": @"lock.rotation",
            @"prefixes": @[@"rotate "],
            @"suffixes": @[@"lock", @"unlock", @"toggle"],
            @"displaySuffixes": @[@"Lock", @"Unlock", @"Toggle"]
        },
        @{
            @"key": @"vibration_silent",
            @"name": @"Silent Vibration",
            @"icon": @"bell.slash",
            @"prefixes": @[@"vibration silent-"],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"vibration_ring",
            @"name": @"Ring Vibration",
            @"icon": @"bell",
            @"prefixes": @[@"vibration ring-"],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"]
        },
        @{
            @"key": @"camera_video",
            @"name": @"Open Video Camera",
            @"icon": @"video.fill",
            @"prefixes": @[@"camera video "],
            @"suffixes": @[@"2x", @"2x flash", @"1x", @"flash", @"0.5x", @"front"],
            @"displaySuffixes": @[@"Video (2x)", @"Video (2x, Flash)", @"Video (1x)", @"Video (1x, Flash)", @"Video (0.5x)", @"Video (Front)"],
            @"exactMatches": @{
                @"camera video 2x": @"2x",
                @"camera video": @"2x",
                @"open camera video 2x": @"2x",
                @"open camera video": @"2x",
                @"camera video 2x flash": @"2x flash",
                @"open camera video 2x flash": @"2x flash",
                @"camera video 1x": @"1x",
                @"open camera video 1x": @"1x",
                @"camera video flash": @"flash",
                @"open camera video flash": @"flash",
                @"camera video 0.5x": @"0.5x",
                @"open camera video 0.5x": @"0.5x",
                @"camera video front": @"front",
                @"open camera video front": @"front"
            }
        },
        @{
            @"key": @"camera_photo",
            @"name": @"Open Camera",
            @"icon": @"camera.fill",
            @"prefixes": @[@"camera "],
            @"suffixes": @[@"photo", @"photo 0.5x", @"photo 2x", @"portrait", @"portrait 2x", @"front", @"slomo", @"timelapse", @"cinematic", @"pano"],
            @"displaySuffixes": @[@"Photo (1x)", @"Photo (0.5x)", @"Photo (2x)", @"Portrait (1x)", @"Portrait (2x)", @"Front Selfie", @"Slo-Mo", @"Time-Lapse", @"Cinematic", @"Pano"],
            @"exactMatches": @{
                @"camera photo": @"photo",
                @"camera": @"photo",
                @"open camera": @"photo",
                @"camera photo 0.5x": @"photo 0.5x",
                @"open camera photo 0.5x": @"photo 0.5x",
                @"camera photo 2x": @"photo 2x",
                @"open camera photo 2x": @"photo 2x",
                @"camera portrait": @"portrait",
                @"open camera portrait": @"portrait",
                @"camera portrait 2x": @"portrait 2x",
                @"open camera portrait 2x": @"portrait 2x",
                @"camera front": @"front",
                @"camera selfie": @"front",
                @"open camera front": @"front",
                @"open camera selfie": @"front",
                @"camera slomo": @"slomo",
                @"open camera slomo": @"slomo",
                @"camera timelapse": @"timelapse",
                @"open camera timelapse": @"timelapse",
                @"camera cinematic": @"cinematic",
                @"open camera cinematic": @"cinematic",
                @"camera pano": @"pano",
                @"open camera pano": @"pano"
            }
        },
        @{
            @"key": @"mute",
            @"name": @"Mute",
            @"icon": @"speaker.slash.fill",
            @"prefixes": @[@"mute "],
            @"suffixes": @[@"on", @"off", @"toggle"],
            @"displaySuffixes": @[@"On", @"Off", @"Toggle"],
            @"exactMatches": @{ @"mute": @"toggle" }
        }
    ];
    
    for (NSDictionary *def in definitions) {
        NSDictionary *exactMatches = def[@"exactMatches"];
        if (exactMatches && exactMatches[lower]) {
            NSString *suffix = exactMatches[lower];
            NSUInteger idx = [def[@"suffixes"] indexOfObject:suffix];
            NSString *displaySuffix = def[@"displaySuffixes"][idx];
            return @{
                @"key": def[@"key"],
                @"name": def[@"name"],
                @"icon": def[@"icon"],
                @"currentSuffix": suffix,
                @"currentDisplaySuffix": displaySuffix,
                @"suffixes": def[@"suffixes"],
                @"displaySuffixes": def[@"displaySuffixes"],
                @"matchedPrefix": @"",
                @"prefixes": def[@"prefixes"]
            };
        }
        
        for (NSString *prefix in def[@"prefixes"]) {
            if ([lower hasPrefix:prefix]) {
                NSString *suffix = [lower substringFromIndex:prefix.length];
                NSUInteger idx = [def[@"suffixes"] indexOfObject:suffix];
                if (idx != NSNotFound) {
                    NSString *displaySuffix = def[@"displaySuffixes"][idx];
                    return @{
                        @"key": def[@"key"],
                        @"name": def[@"name"],
                        @"icon": def[@"icon"],
                        @"currentSuffix": suffix,
                        @"currentDisplaySuffix": displaySuffix,
                        @"suffixes": def[@"suffixes"],
                        @"displaySuffixes": def[@"displaySuffixes"],
                        @"matchedPrefix": prefix,
                        @"prefixes": def[@"prefixes"]
                    };
                }
            }
        }
    }
    
    return nil;
}

- (void)registerKMMacroName:(NSString *)name forUid:(NSString *)uid {
    if (!name.length || !uid.length) return;
    NSMutableDictionary *dict = _config[@"kmNamesByUuid"];
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
        _config[@"kmNamesByUuid"] = dict;
    } else if (![dict isKindOfClass:[NSMutableDictionary class]]) {
        dict = [dict mutableCopy];
        _config[@"kmNamesByUuid"] = dict;
    }
    if ([dict[uid] isEqualToString:name]) return;
    dict[uid] = name;
    [self saveConfig];
}

- (void)registerKMMacroNamesBatch:(NSDictionary<NSString *, NSString *> *)map {
    if (!map || map.count == 0) return;
    NSMutableDictionary *dict = _config[@"kmNamesByUuid"];
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
        _config[@"kmNamesByUuid"] = dict;
    } else if (![dict isKindOfClass:[NSMutableDictionary class]]) {
        dict = [dict mutableCopy];
        _config[@"kmNamesByUuid"] = dict;
    }
    BOOL changed = NO;
    for (NSString *uid in map) {
        NSString *name = map[uid];
        if (uid.length > 0 && name.length > 0 && ![dict[uid] isEqualToString:name]) {
            dict[uid] = name;
            changed = YES;
        }
    }
    if (changed) {
        [self saveConfig];
    }
}

- (NSString *)nameForKMMacroUid:(NSString *)uid {
    if (!uid.length) return nil;
    return _config[@"kmNamesByUuid"][uid];
}

@end
