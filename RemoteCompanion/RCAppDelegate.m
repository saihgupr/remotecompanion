#import "RCAppDelegate.h"
#import "RCWhatsNew.h"
#import "RCServerClient.h"
#import "RCTriggersViewController.h"
#import "RCSettingsViewController.h"
#import "RCIntegrationsViewController.h"
#import "RCHASettingsViewController.h"
#import "RCKMSettingsViewController.h"
#import "RCMQTTSettingsViewController.h"
#import "RCSettingsPageViewController.h"
#import "RCExcludedAppsViewController.h"
#import "RCTestKitViewController.h"
#import "RCWebUIAccessViewController.h"
#import "RCActionsViewController.h"
#import "RCAddOnsViewController.h"
#import "RCAddOnDetailViewController.h"

#define RCLog(...) do { \
    NSString *msg__ = [NSString stringWithFormat:__VA_ARGS__]; \
    NSFileHandle *fh__ = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/Documents/rclog.txt"]; \
    if (!fh__) { \
        [@"" writeToFile:@"/var/mobile/Documents/rclog.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil]; \
        fh__ = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/Documents/rclog.txt"]; \
    } \
    [fh__ seekToEndOfFile]; \
    NSString *line__ = [NSString stringWithFormat:@"%@\n", msg__]; \
    [fh__ writeData:[line__ dataUsingEncoding:NSUTF8StringEncoding]]; \
    [fh__ closeFile]; \
    NSLog(@"%@", msg__); \
} while(0)

@implementation RCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [@"--- APP LAUNCH ---" writeToFile:@"/var/mobile/Documents/rclog.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    RCLog(@"App launched! starting didFinishLaunchingWithOptions");
    
    // Notification actions post as this app; show them while it's open too
    [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    // Ask at launch, not only in the action editor: `rc notify` and Notification
    // actions post from the tweak, so anyone who never opens that editor would
    // never be asked and iOS would drop every notification without a word.
    [RCAppDelegate requestNotificationPermission];

    @try {
        self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        RCLog(@"Window created");
        
        RCTriggersViewController *triggersVC = [[RCTriggersViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        RCLog(@"RCTriggersViewController created");
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:triggersVC];
        RCLog(@"Nav created");
        
        self.window.rootViewController = nav;
        [self.window makeKeyAndVisible];
        RCLog(@"makeKeyAndVisible done");
        // What's New (or the welcome, on a first install), once the Triggers screen is up
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [RCWhatsNew showIfNeededFrom:nav];
        });
    } @catch (NSException *exception) {
        RCLog(@"CRASH: %@ - %@", exception.name, exception.reason);
    }
    
    return YES;
}

+ (void)requestNotificationPermission {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) return;
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError *error) {
            RCLog(@"Notification permission: %d %@", granted, error);
        }];
    }];
}

// A tap or button press that reached RC: SpringBoard runs a notification's tap and button triggers
// itself and RC stays closed, so getting here means it didn't (no such trigger, a button that
// needed the passcode first, or an iOS version where SpringBoard's part isn't there). Run the
// trigger now; the tweak skips one that's off or empty.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    id tap = response.notification.request.content.userInfo[@"rcTap"];
    NSString *key = nil;
    if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier] && [tap isKindOfClass:[NSString class]] && [tap length]) {
        key = [@"notiftap_" stringByAppendingString:tap];
    } else if ([response.actionIdentifier hasPrefix:@"rcbtn-"] && response.actionIdentifier.length > 6) {
        // A long-press menu button (one that needed the phone unlocked comes here after the passcode)
        key = [@"notifbtn_" stringByAppendingString:[response.actionIdentifier substringFromIndex:6]];
    }
    if (!key) {
        completionHandler();
        return;
    }
    RCLog(@"Notification response reached the app: %@", key);
    RCServerClient *client = [RCServerClient sharedClient];
    NSString *trigger = [@"trigger " stringByAppendingString:key];
    void (^runTrigger)(void) = ^{
        // Done once the command is sent: a button press may have launched RC in the background
        [client executeCommand:trigger completion:^(__unused NSString *output, __unused NSError *error) {
            dispatch_async(dispatch_get_main_queue(), completionHandler);
        }];
    };
    if (![key hasPrefix:@"notifbtn_"]) {
        runTrigger();
        return;
    }
    // A button that needed the passcode: an action waiting on this notification takes its answer
    // now that the passcode was given
    NSString *confirm = [@"notify confirm " stringByAppendingString:response.notification.request.identifier ?: @""];
    [client executeCommand:confirm completion:^(__unused NSString *output, __unused NSError *error) { runTrigger(); }];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    RCLog(@"openURL received: %@", url);
    if (!url || ![url.scheme.lowercaseString isEqualToString:@"remotecompanion"]) {
        return NO;
    }
    
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *path = url.path.lowercaseString ?: @"";
    
    // Support remotecompanion://settings, remotecompanion://nav/settings, remotecompanion:///settings
    NSString *destination = host;
    if ([host isEqualToString:@"nav"] || host.length == 0) {
        if ([path hasPrefix:@"/"]) {
            destination = [path substringFromIndex:1];
        } else {
            destination = path;
        }
    }
    
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary *queryParams = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (item.name && item.value) {
            queryParams[item.name.lowercaseString] = item.value;
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleNavigationToDestination:destination queryParams:queryParams];
    });
    
    return YES;
}

- (void)handleNavigationToDestination:(NSString *)destination queryParams:(NSDictionary *)queryParams {
    UINavigationController *rootNav = (UINavigationController *)self.window.rootViewController;
    if (![rootNav isKindOfClass:[UINavigationController class]]) return;
    
    RCTriggersViewController *triggersVC = (RCTriggersViewController *)rootNav.viewControllers.firstObject;
    
    // Dismiss any presented modal on root
    if (rootNav.presentedViewController) {
        [rootNav dismissViewControllerAnimated:NO completion:nil];
    }
    [rootNav popToRootViewControllerAnimated:NO];
    
    if ([destination isEqualToString:@"home"] || [destination isEqualToString:@"triggers"] || destination.length == 0) {
        return;
    }
    
    if ([destination isEqualToString:@"add"] || [destination isEqualToString:@"new-trigger"] || [destination isEqualToString:@"new"]) {
        [triggersVC addNewItem];
        return;
    }
    
    if ([destination isEqualToString:@"trigger"]) {
        NSString *key = queryParams[@"key"];
        if (key.length) {
            [triggersVC openTriggerWithKey:key];
        }
        return;
    }
    
    RCSettingsViewController *settingsVC = [[RCSettingsViewController alloc] init];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.modalPresentationStyle = UIModalPresentationFullScreen;
    
    if ([destination isEqualToString:@"settings"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:nil];
        return;
    }
    
    if ([destination isEqualToString:@"integrations"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            [settingsNav pushViewController:[[RCIntegrationsViewController alloc] init] animated:NO];
        }];
        return;
    }
    
    if ([destination isEqualToString:@"ha"] || [destination isEqualToString:@"homeassistant"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            RCIntegrationsViewController *intVC = [[RCIntegrationsViewController alloc] init];
            RCHASettingsViewController *haVC = [[RCHASettingsViewController alloc] init];
            [settingsNav setViewControllers:@[settingsVC, intVC, haVC] animated:NO];
        }];
        return;
    }
    
    if ([destination isEqualToString:@"km"] || [destination isEqualToString:@"keyboardmaestro"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            RCIntegrationsViewController *intVC = [[RCIntegrationsViewController alloc] init];
            RCKMSettingsViewController *kmVC = [[RCKMSettingsViewController alloc] init];
            [settingsNav setViewControllers:@[settingsVC, intVC, kmVC] animated:NO];
        }];
        return;
    }
    
    if ([destination isEqualToString:@"mqtt"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            RCIntegrationsViewController *intVC = [[RCIntegrationsViewController alloc] init];
            RCMQTTSettingsViewController *mqttVC = [[RCMQTTSettingsViewController alloc] init];
            [settingsNav setViewControllers:@[settingsVC, intVC, mqttVC] animated:NO];
        }];
        return;
    }
    
    // remotecompanion://addons (Settings > Add-ons), remotecompanion://addon?id=<add-on> (its page),
    // and &setting=<setting> to open one of its settings too
    if ([destination isEqualToString:@"addons"] || [destination isEqualToString:@"addon"]) {
        NSString *addOnId = [queryParams[@"id"] lowercaseString];
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            RCAddOnsViewController *list = [[RCAddOnsViewController alloc] initShowing:RCAddOnsListAll];
            if (!addOnId.length) {
                [settingsNav setViewControllers:@[settingsVC, list] animated:NO];
                return;
            }
            RCAddOnDetailViewController *page = [[RCAddOnDetailViewController alloc] initWithAddOnId:addOnId];
            page.openSettingId = queryParams[@"setting"];
            [settingsNav setViewControllers:@[settingsVC, list, page] animated:NO];
        }];
        return;
    }

    // remotecompanion://layout, banners, buttons, swipes, nfc, security or diagnostics (developer
    // until 4.7): that Settings page.
    // remotecompanion://advanced (Advanced Settings until 4.7) opens Settings.
    NSDictionary<NSString *, NSNumber *> *pages = @{ @"layout": @(RCSettingsPageLayout), @"banners": @(RCSettingsPageBanners),
        @"buttons": @(RCSettingsPageButtons), @"swipes": @(RCSettingsPageSwipeTriggers), @"swipetriggers": @(RCSettingsPageSwipeTriggers),
        @"nfc": @(RCSettingsPageNFC), @"developer": @(RCSettingsPageDiagnostics), @"diagnostics": @(RCSettingsPageDiagnostics),
        @"security": @(RCSettingsPageSecurity) };
    if (pages[destination] || [destination isEqualToString:@"advanced"]) {
        NSNumber *page = pages[destination];
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            if (page) [settingsNav pushViewController:[RCSettingsPageViewController viewControllerForPage:page.integerValue highlightRowID:nil] animated:NO];
        }];
        return;
    }
    
    if ([destination isEqualToString:@"excluded"] || [destination isEqualToString:@"excludedapps"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            [settingsNav pushViewController:[[RCExcludedAppsViewController alloc] init] animated:NO];
        }];
        return;
    }

    if ([destination isEqualToString:@"testkit"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            [settingsNav pushViewController:[[RCTestKitViewController alloc] init] animated:NO];
        }];
        return;
    }
    
    // remotecompanion://webui and backup: those Settings pages
    if ([destination isEqualToString:@"webui"] || [destination isEqualToString:@"backup"]) {
        NSString *subpage = [destination isEqualToString:@"webui"] ? RCSettingsSubpageWebUI : RCSettingsSubpageBackup;
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            [settingsNav pushViewController:[RCSettingsViewController subpage:subpage] animated:NO];
        }];
        return;
    }
    
    if ([destination isEqualToString:@"scroll"]) {
        UIViewController *visibleVC = rootNav.presentedViewController ?: rootNav.topViewController;
        if ([visibleVC isKindOfClass:[UINavigationController class]]) {
            visibleVC = ((UINavigationController *)visibleVC).topViewController;
        }
        
        UITableView *tv = [self findTableViewInView:visibleVC.view];
        if (tv) {
            NSString *pos = queryParams[@"to"] ?: queryParams[@"pos"];
            NSString *offsetStr = queryParams[@"offset"] ?: queryParams[@"y"];
            if ([pos isEqualToString:@"bottom"]) {
                CGPoint bottomOffset = CGPointMake(0, MAX(0, tv.contentSize.height - tv.bounds.size.height + tv.adjustedContentInset.bottom));
                [tv setContentOffset:bottomOffset animated:NO];
            } else if ([pos isEqualToString:@"top"]) {
                [tv setContentOffset:CGPointMake(0, -tv.adjustedContentInset.top) animated:NO];
            } else if (offsetStr.length) {
                CGFloat y = [offsetStr doubleValue];
                [tv setContentOffset:CGPointMake(0, y) animated:NO];
            }
        }
        return;
    }
}

- (UITableView *)findTableViewInView:(UIView *)view {
    if ([view isKindOfClass:[UITableView class]]) {
        return (UITableView *)view;
    }
    for (UIView *subview in view.subviews) {
        UITableView *tv = [self findTableViewInView:subview];
        if (tv) return tv;
    }
    return nil;
}

@end
