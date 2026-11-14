#import "RCAppDelegate.h"
#import "RCTriggersViewController.h"
#import "RCSettingsViewController.h"
#import "RCIntegrationsViewController.h"
#import "RCHASettingsViewController.h"
#import "RCKMSettingsViewController.h"
#import "RCMQTTSettingsViewController.h"
#import "RCAdvancedSettingsViewController.h"
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
    } @catch (NSException *exception) {
        RCLog(@"CRASH: %@ - %@", exception.name, exception.reason);
    }
    
    return YES;
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

    if ([destination isEqualToString:@"advanced"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            [settingsNav pushViewController:[[RCAdvancedSettingsViewController alloc] init] animated:NO];
        }];
        return;
    }
    
    if ([destination isEqualToString:@"excluded"] || [destination isEqualToString:@"excludedapps"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            [settingsNav pushViewController:[[RCAdvancedSettingsViewController alloc] init] animated:NO];
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
    
    if ([destination isEqualToString:@"webui"]) {
        [rootNav presentViewController:settingsNav animated:NO completion:^{
            [settingsNav pushViewController:[[RCWebUIAccessViewController alloc] init] animated:NO];
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
