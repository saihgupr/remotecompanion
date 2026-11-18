// Dynamic Control Center buttons for Control Center Button triggers (via CCSupport's CCSModuleProvider).
//
// RCCCButtonProvider is loaded by CCSupport into both SpringBoard and Settings (Preferences).
// It exposes one module per trigger_cc_button_<id> entry in rc_triggers.plist under the
// identifier com.saihgupr.remotecompanion.ccbutton<id>, using the trigger's RemoteCompanion name.
// Each RCCCButton runs in SpringBoard, draws the trigger's SF Symbol, and posts an in-process
// NSNotification on tap so RemoteCommand.dylib executes that trigger.
// Keep it small and defensive: a crash here crashes SpringBoard or Settings.
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <sys/stat.h>
#import <ControlCenterUIKit/CCUIToggleModule.h>

@protocol CCSModuleProvider
@required
- (NSUInteger)numberOfProvidedModules;
- (NSString *)identifierForModuleAtIndex:(NSUInteger)index;
- (id)moduleInstanceForModuleIdentifier:(NSString *)identifier;
- (NSString *)displayNameForModuleIdentifier:(NSString *)identifier;
@optional
- (NSSet *)supportedDeviceFamiliesForModuleWithIdentifier:(NSString *)identifier;
- (NSSet *)requiredDeviceCapabilitiesForModuleWithIdentifier:(NSString *)identifier;
- (NSSet *)requiredDeviceIncapabilitiesForModuleWithIdentifier:(NSString *)identifier;
- (NSString *)associatedBundleIdentifierForModuleWithIdentifier:(NSString *)identifier;
- (NSString *)associatedBundleMinimumVersionForModuleWithIdentifier:(NSString *)identifier;
- (NSUInteger)visibilityPreferenceForModuleWithIdentifier:(NSString *)identifier;
- (UIImage *)settingsIconForModuleIdentifier:(NSString *)identifier;
- (BOOL)providesListControllerForModuleIdentifier:(NSString *)identifier;
- (id)listControllerForModuleIdentifier:(NSString *)identifier;
@end

static NSString *const kRCCCConfigPath = @"/var/mobile/Documents/rc_triggers.plist";
static NSString *const kRCCCTriggerPrefix = @"trigger_cc_button_";
static NSString *const kRCCCModuleIdPrefix = @"com.saihgupr.remotecompanion.ccbutton";
static NSString *const kRCCCDefaultSymbol = @"bolt.fill";
static NSString *const kRCCCTapNotification = @"com.saihgupr.remotecompanion.ccbutton.tap";
static NSString *const kRCCCRefreshNotification = @"com.saihgupr.remotecompanion.ccbutton.refresh";

typedef struct {
    BOOL valid;
    ino_t ino;
    off_t size;
    struct timespec mtime;
} RCCCFileStat;

static RCCCFileStat RCCCReadFileStat(NSString *path) {
    RCCCFileStat info = {0};
    struct stat st;
    if (stat([path fileSystemRepresentation], &st) == 0) {
        info.valid = YES;
        info.ino = st.st_ino;
        info.size = st.st_size;
        info.mtime = st.st_mtimespec;
    }
    return info;
}

static BOOL RCCCFileStatEqual(RCCCFileStat a, RCCCFileStat b) {
    return a.valid && b.valid &&
           a.ino == b.ino &&
           a.size == b.size &&
           a.mtime.tv_sec == b.mtime.tv_sec &&
           a.mtime.tv_nsec == b.mtime.tv_nsec;
}

static NSString *RCCCModuleIdentifierForTriggerKey(NSString *triggerKey) {
    if (![triggerKey hasPrefix:kRCCCTriggerPrefix] || triggerKey.length <= kRCCCTriggerPrefix.length) return nil;
    return [kRCCCModuleIdPrefix stringByAppendingString:[triggerKey substringFromIndex:kRCCCTriggerPrefix.length]];
}

static NSString *RCCCTriggerKeyForModuleIdentifier(NSString *identifier) {
    if (![identifier hasPrefix:kRCCCModuleIdPrefix] || identifier.length <= kRCCCModuleIdPrefix.length) return nil;
    return [kRCCCTriggerPrefix stringByAppendingString:[identifier substringFromIndex:kRCCCModuleIdPrefix.length]];
}

static void RCCCCollectSettingsControllersFromVC(UIViewController *vc, NSMutableArray<UIViewController *> *out, Class listCls, Class modulesCls) {
    if (!vc) return;
    if (((listCls && [vc isKindOfClass:listCls]) || (modulesCls && [vc isKindOfClass:modulesCls])) && ![out containsObject:vc]) {
        [out addObject:vc];
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *child in ((UINavigationController *)vc).viewControllers) {
            RCCCCollectSettingsControllersFromVC(child, out, listCls, modulesCls);
        }
    } else if ([vc isKindOfClass:[UISplitViewController class]]) {
        for (UIViewController *child in ((UISplitViewController *)vc).viewControllers) {
            RCCCCollectSettingsControllersFromVC(child, out, listCls, modulesCls);
        }
    } else if ([vc isKindOfClass:[UITabBarController class]]) {
        for (UIViewController *child in ((UITabBarController *)vc).viewControllers) {
            RCCCCollectSettingsControllersFromVC(child, out, listCls, modulesCls);
        }
    }
    for (UIViewController *child in vc.childViewControllers) {
        RCCCCollectSettingsControllersFromVC(child, out, listCls, modulesCls);
    }
    if (vc.presentedViewController) {
        RCCCCollectSettingsControllersFromVC(vc.presentedViewController, out, listCls, modulesCls);
    }
}

@interface RCCCButton : CCUIToggleModule
- (instancetype)initWithTriggerKey:(NSString *)triggerKey;
@end

@implementation RCCCButton {
    NSString *_triggerKey;
    UIImage *_glyph;
    RCCCFileStat _glyphStat;
}

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super init];
    if (self) {
        _triggerKey = [triggerKey copy];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleRefreshNotification:)
                                                     name:kRCCCRefreshNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_handleRefreshNotification:(NSNotification *)note {
    dispatch_block_t reset = ^{
        self->_glyph = nil;
        memset(&self->_glyphStat, 0, sizeof(self->_glyphStat));
        [self refreshState];
    };
    if ([NSThread isMainThread]) {
        reset();
    } else {
        dispatch_async(dispatch_get_main_queue(), reset);
    }
}

// The icon the trigger was given, as a template image the way Control Center draws its own
- (UIImage *)iconGlyph {
    RCCCFileStat current = RCCCReadFileStat(kRCCCConfigPath);
    if (_glyph && RCCCFileStatEqual(current, _glyphStat)) return _glyph;

    NSString *symbol = nil;
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:kRCCCConfigPath];
    NSDictionary *triggers = [config[@"triggers"] isKindOfClass:[NSDictionary class]] ? config[@"triggers"] : nil;
    NSDictionary *trigger = (_triggerKey.length && [triggers[_triggerKey] isKindOfClass:[NSDictionary class]]) ? triggers[_triggerKey] : nil;
    if ([trigger[@"icon"] isKindOfClass:[NSString class]]) symbol = trigger[@"icon"];

    UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
    UIImage *image = symbol.length ? [UIImage systemImageNamed:symbol withConfiguration:size] : nil;
    if (!image) image = [UIImage systemImageNamed:kRCCCDefaultSymbol withConfiguration:size];
    _glyph = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _glyphStat = current;
    return _glyph;
}

- (UIImage *)selectedIconGlyph {
    return [self iconGlyph];
}

- (UIColor *)selectedColor {
    return [UIColor systemBlueColor];
}

// A press, not a switch: never stays on
- (BOOL)isSelected {
    return NO;
}

- (void)setSelected:(BOOL)selected {
    if (selected && _triggerKey.length) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kRCCCTapNotification
                                                            object:nil
                                                          userInfo:@{ @"triggerKey": _triggerKey }];
    }
    [self refreshState];
}

@end

@interface RCCCButtonProvider : NSObject <CCSModuleProvider>
- (void)_handleReloadProvidersDarwinNotification;
@end

static void RCCCProvidersReloadCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    RCCCButtonProvider *provider = (__bridge RCCCButtonProvider *)observer;
    [provider _handleReloadProvidersDarwinNotification];
}

@implementation RCCCButtonProvider {
    NSArray<NSString *> *_orderedModuleIds;
    NSDictionary<NSString *, NSDictionary *> *_triggersByModuleId;
    RCCCFileStat _configStat;
    BOOL _dirty;
    UIImage *_settingsIcon;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dirty = YES;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        RCCCProvidersReloadCallback,
                                        CFSTR("com.opa334.ccsupport/ReloadProviders"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       CFSTR("com.opa334.ccsupport/ReloadProviders"),
                                       NULL);
}

- (void)_handleReloadProvidersDarwinNotification {
    @synchronized (self) {
        _dirty = YES;
    }
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.Preferences"]) return;
    // Let CCSupport finish [CCSModuleProviderManager reload] first, then refresh any open Settings > Control Center page.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self _refreshSettingsControllers];
    });
}

- (void)_refreshSettingsControllers {
    Class listCls = NSClassFromString(@"CCUISettingsListController");
    Class modulesCls = NSClassFromString(@"CCUISettingsModulesController");
    if (!listCls && !modulesCls) return;

    NSMutableArray<UIViewController *> *controllers = [NSMutableArray array];
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(connectedScenes)]) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                RCCCCollectSettingsControllersFromVC(window.rootViewController, controllers, listCls, modulesCls);
            }
        }
    }
    if (controllers.count == 0) {
        for (UIWindow *window in app.windows) {
            RCCCCollectSettingsControllersFromVC(window.rootViewController, controllers, listCls, modulesCls);
        }
    }

    SEL updateQueueSel = NSSelectorFromString(@"_queue_updateAllModuleMetadata");
    SEL updateSel = NSSelectorFromString(@"_updateAllModuleMetadata");
    SEL repopulateSel = NSSelectorFromString(@"_repopulateModuleData");
    SEL reloadSpecifiersSel = NSSelectorFromString(@"reloadSpecifiers");

    for (UIViewController *vc in controllers) {
        @try {
            id repo = [vc valueForKey:@"_moduleRepository"];
            void (^applyUIUpdate)(void) = ^{
                @try {
                    if ([vc respondsToSelector:repopulateSel]) {
                        ((void (*)(id, SEL))objc_msgSend)(vc, repopulateSel);
                    }
                    if ([vc respondsToSelector:reloadSpecifiersSel]) {
                        ((void (*)(id, SEL))objc_msgSend)(vc, reloadSpecifiersSel);
                    } else if ([vc isKindOfClass:[UITableViewController class]]) {
                        [((UITableViewController *)vc).tableView reloadData];
                    }
                } @catch (NSException *e) {
                }
            };
            if (repo && [repo respondsToSelector:updateQueueSel]) {
                dispatch_queue_t queue = [repo valueForKey:@"_queue"];
                if (queue) {
                    dispatch_async(queue, ^{
                        @try {
                            ((void (*)(id, SEL))objc_msgSend)(repo, updateQueueSel);
                        } @catch (NSException *e) {
                        }
                        dispatch_async(dispatch_get_main_queue(), applyUIUpdate);
                    });
                } else {
                    ((void (*)(id, SEL))objc_msgSend)(repo, updateQueueSel);
                    applyUIUpdate();
                }
            } else if (repo && [repo respondsToSelector:updateSel]) {
                ((void (*)(id, SEL))objc_msgSend)(repo, updateSel);
                applyUIUpdate();
            } else {
                applyUIUpdate();
            }
        } @catch (NSException *e) {
        }
    }
}

- (void)_reloadConfigForce:(BOOL)force {
    RCCCFileStat current = RCCCReadFileStat(kRCCCConfigPath);
    if (!force && !_dirty && _orderedModuleIds && RCCCFileStatEqual(current, _configStat)) {
        return;
    }

    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:kRCCCConfigPath];
    NSDictionary *triggers = [config[@"triggers"] isKindOfClass:[NSDictionary class]] ? config[@"triggers"] : nil;
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (id rawKey in triggers) {
        if (![rawKey isKindOfClass:[NSString class]]) continue;
        NSString *key = rawKey;
        if (![key hasPrefix:kRCCCTriggerPrefix] || key.length <= kRCCCTriggerPrefix.length) continue;
        if (![triggers[key] isKindOfClass:[NSDictionary class]]) continue;
        [keys addObject:key];
    }
    [keys sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSNumericSearch];
    }];

    NSMutableArray<NSString *> *moduleIds = [NSMutableArray arrayWithCapacity:keys.count];
    NSMutableDictionary<NSString *, NSDictionary *> *byId = [NSMutableDictionary dictionaryWithCapacity:keys.count];
    for (NSString *key in keys) {
        NSString *moduleId = RCCCModuleIdentifierForTriggerKey(key);
        if (!moduleId.length) continue;
        [moduleIds addObject:moduleId];
        byId[moduleId] = triggers[key];
    }

    _orderedModuleIds = [moduleIds copy];
    _triggersByModuleId = [byId copy];
    _configStat = current;
    _dirty = NO;
}

#pragma mark - CCSModuleProvider

- (NSUInteger)numberOfProvidedModules {
    @synchronized (self) {
        [self _reloadConfigForce:YES];
        return _orderedModuleIds.count;
    }
}

- (NSString *)identifierForModuleAtIndex:(NSUInteger)index {
    @synchronized (self) {
        if (index >= _orderedModuleIds.count) return nil;
        return _orderedModuleIds[index];
    }
}

- (id)moduleInstanceForModuleIdentifier:(NSString *)identifier {
    NSString *triggerKey = RCCCTriggerKeyForModuleIdentifier(identifier);
    if (!triggerKey.length) return nil;
    return [[RCCCButton alloc] initWithTriggerKey:triggerKey];
}

- (NSString *)displayNameForModuleIdentifier:(NSString *)identifier {
    NSDictionary *trigger = nil;
    @synchronized (self) {
        [self _reloadConfigForce:NO];
        trigger = _triggersByModuleId[identifier];
    }
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *custom = [trigger[@"customName"] isKindOfClass:[NSString class]]
        ? [trigger[@"customName"] stringByTrimmingCharactersInSet:ws]
        : nil;
    if (custom.length) return custom;
    NSString *name = [trigger[@"name"] isKindOfClass:[NSString class]]
        ? [trigger[@"name"] stringByTrimmingCharactersInSet:ws]
        : nil;
    if (name.length) return name;
    NSString *suffix = [identifier hasPrefix:kRCCCModuleIdPrefix]
        ? [identifier substringFromIndex:kRCCCModuleIdPrefix.length]
        : identifier;
    return [NSString stringWithFormat:@"Control Center Button %@", suffix];
}

- (UIImage *)settingsIconForModuleIdentifier:(NSString *)identifier {
    @synchronized (self) {
        if (!_settingsIcon) {
            NSBundle *bundle = [NSBundle bundleForClass:[self class]];
            _settingsIcon = [UIImage imageNamed:@"SettingsIcon" inBundle:bundle compatibleWithTraitCollection:nil];
        }
        return _settingsIcon;
    }
}

@end
