// rc-notify: posts a standard iOS notification (banner, Notification Center, sound) as the
// RemoteCompanion app, so it shows even when the app isn't running. SpringBoard can't post for
// another app, so the notify command runs this; the entitlement lets it post for the app's
// bundle ID. The app needs SBAppUsesLocalNotifications in its Info.plist (or iOS has no
// notification section for it) and the user's permission, which the app asks for.
//
// usage: rc-notify "Title" ["Body"] [--urgent] [--id ID] [--tap TAP] [--button ID TITLE FLAGS]...
//        rc-notify --clear        removes all of the app's notifications
//        rc-notify --remove ID    removes one posted with --id ID
//        rc-notify --exists ID    exit 0 while it's still delivered, 4 once it's gone
//   --urgent  Time Sensitive: shows through Focus and scheduled summaries
//   --tap     tapping it runs the Notification Tap trigger with this ID (SpringBoard part)
//   --thread ID  its own group in Notification Center (not stacked with RC's others)
//   --icon SPEC  its icon in place of the app's: "app:BUNDLE" (that app's icon) or "sf:NAME" (a symbol)
//   --button ID TITLE FLAGS  a button in its long-press menu (up to 4; FLAGS: red, unlock, or
//             both with a comma, or -). Pressing one runs the trigger notifbtn_<ID>.
// exit: 0 done, 1 usage, 2 not allowed or failed, 3 timed out
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/message.h>

#define RC_APP_ID @"com.saihgupr.remotecompanion"

@interface UNUserNotificationCenter (Private)
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        BOOL urgent = NO, clear = NO;
        NSString *identifier = nil, *removeID = nil, *tap = nil, *existsID = nil;
        NSMutableArray<UNNotificationAction *> *buttons = [NSMutableArray array];
        NSString *icon = nil, *thread = nil;
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]] ?: @"";
            if ([arg isEqualToString:@"--urgent"]) urgent = YES;
            else if ([arg isEqualToString:@"--clear"]) clear = YES;
            else if ([arg isEqualToString:@"--id"] && i + 1 < argc) identifier = [NSString stringWithUTF8String:argv[++i]];
            else if ([arg isEqualToString:@"--remove"] && i + 1 < argc) removeID = [NSString stringWithUTF8String:argv[++i]];
            else if ([arg isEqualToString:@"--tap"] && i + 1 < argc) tap = [NSString stringWithUTF8String:argv[++i]];
            else if ([arg isEqualToString:@"--exists"] && i + 1 < argc) existsID = [NSString stringWithUTF8String:argv[++i]];
            else if ([arg isEqualToString:@"--icon"] && i + 1 < argc) icon = [NSString stringWithUTF8String:argv[++i]];
            else if ([arg isEqualToString:@"--thread"] && i + 1 < argc) thread = [NSString stringWithUTF8String:argv[++i]];
            else if ([arg isEqualToString:@"--button"] && i + 3 < argc) {
                NSString *buttonID = [NSString stringWithUTF8String:argv[++i]] ?: @"";
                NSString *title = [NSString stringWithUTF8String:argv[++i]] ?: @"";
                NSArray *flags = [([NSString stringWithUTF8String:argv[++i]] ?: @"") componentsSeparatedByString:@","];
                UNNotificationActionOptions options = UNNotificationActionOptionNone;
                if ([flags containsObject:@"red"]) options |= UNNotificationActionOptionDestructive;
                if ([flags containsObject:@"unlock"]) options |= UNNotificationActionOptionAuthenticationRequired;
                if (buttonID.length && title.length && buttons.count < 4) {
                    [buttons addObject:[UNNotificationAction actionWithIdentifier:[@"rcbtn-" stringByAppendingString:buttonID] title:title options:options]];
                }
            }
            else [texts addObject:arg];
        }

        UNUserNotificationCenter *center = [[UNUserNotificationCenter alloc] initWithBundleIdentifier:RC_APP_ID];
        if (existsID.length) {
            __block int found = 4;
            dispatch_semaphore_t listed = dispatch_semaphore_create(0);
            [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *delivered) {
                for (UNNotification *note in delivered) if ([note.request.identifier isEqualToString:existsID]) found = 0;
                dispatch_semaphore_signal(listed);
            }];
            return dispatch_semaphore_wait(listed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0 ? found : 3;
        }
        if (clear || removeID) {
            if (clear) [center removeAllDeliveredNotifications];
            else [center removeDeliveredNotificationsWithIdentifiers:@[removeID]];
            // The removal is sent asynchronously; a settings read afterwards waits for it
            dispatch_semaphore_t sent = dispatch_semaphore_create(0);
            [center getNotificationSettingsWithCompletionHandler:^(__unused UNNotificationSettings *settings) { dispatch_semaphore_signal(sent); }];
            return dispatch_semaphore_wait(sent, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0 ? 0 : 3;
        }
        if (texts.count == 0 || texts.count > 2) {
            fprintf(stderr, "usage: rc-notify \"Title\" [\"Body\"] [--urgent] [--id ID] [--tap TAP] [--icon SPEC] [--button ID TITLE FLAGS]... | --clear | --remove ID\n");
            return 1;
        }

        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = texts[0];
        if (texts.count > 1) content.body = texts[1];
        content.sound = [UNNotificationSound defaultSound];
        if (tap.length) content.userInfo = @{ @"rcTap": tap };
        if (thread.length) content.threadIdentifier = thread;
        if (urgent) {
            if (@available(iOS 15.0, *)) content.interruptionLevel = UNNotificationInterruptionLevelTimeSensitive;
        }
        // The buttons are the notification's category, registered for the app before it's posted.
        // A category of its own per notification (by tap ID), replaced each time it's posted.
        if (buttons.count) {
            NSString *categoryID = [@"rc-" stringByAppendingString:(tap.length ? tap : [NSUUID UUID].UUIDString)];
            UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:categoryID actions:buttons intentIdentifiers:@[] options:UNNotificationCategoryOptionNone];
            dispatch_semaphore_t registered = dispatch_semaphore_create(0);
            [center getNotificationCategoriesWithCompletionHandler:^(NSSet<UNNotificationCategory *> *existing) {
                NSMutableSet *categories = [NSMutableSet set];
                for (UNNotificationCategory *c in existing) if (![c.identifier isEqualToString:categoryID]) [categories addObject:c];
                [categories addObject:category];
                [center setNotificationCategories:categories];
                dispatch_semaphore_signal(registered);
            }];
            dispatch_semaphore_wait(registered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
            content.categoryIdentifier = categoryID;
        }

        // The notification's own icon in place of the app's, square like any app icon: an app's icon
        // ("app:BUNDLE") or a symbol ("sf:NAME"). The icon travels with the notification; nothing is
        // drawn here or in SpringBoard.
        Class iconClass = NSClassFromString(@"UNNotificationIcon");
        id notificationIcon = nil;
        if ([icon hasPrefix:@"app:"] && [iconClass respondsToSelector:NSSelectorFromString(@"iconForApplicationIdentifier:")]) {
            notificationIcon = ((id (*)(id, SEL, id))objc_msgSend)(iconClass, NSSelectorFromString(@"iconForApplicationIdentifier:"), [icon substringFromIndex:4]);
        } else if ([icon hasPrefix:@"sf:"] && [iconClass respondsToSelector:NSSelectorFromString(@"iconForSystemImageNamed:")]) {
            notificationIcon = ((id (*)(id, SEL, id))objc_msgSend)(iconClass, NSSelectorFromString(@"iconForSystemImageNamed:"), [icon substringFromIndex:3]);
        }
        if (notificationIcon && [content respondsToSelector:NSSelectorFromString(@"setIcon:")]) {
            ((void (*)(id, SEL, id))objc_msgSend)(content, NSSelectorFromString(@"setIcon:"), notificationIcon);
        }
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:(identifier.length ? identifier : [NSUUID UUID].UUIDString) content:content trigger:nil];

        __block int result = 2;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
            // iOS accepts a request it isn't allowed to show and then drops it, so say why
            if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined || settings.authorizationStatus == UNAuthorizationStatusDenied) {
                fprintf(stderr, "notifications are not allowed for RemoteCompanion (status %ld): open the app and allow them\n", (long)settings.authorizationStatus);
                dispatch_semaphore_signal(done);
                return;
            }
            [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
                if (error) fprintf(stderr, "error: %s\n", error.description.UTF8String);
                else result = 0;
                dispatch_semaphore_signal(done);
            }];
        }];
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0) {
            fprintf(stderr, "timed out\n");
            return 3;
        }
        return result;
    }
}
