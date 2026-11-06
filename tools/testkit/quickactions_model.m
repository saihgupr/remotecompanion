// Native API doubles exercise production lookup/identity/dispatch on macOS.
// This does not validate private selectors on iOS or actual app activation.
#import <Foundation/Foundation.h>
#import "../../Tweak/RCQuickActions.h"
#include <stdio.h>
#include <stdlib.h>

@interface SBSApplicationShortcutItem : NSObject
@property(copy) NSString *type, *localizedTitle, *localizedSubtitle;
@property(copy) NSString *bundleIdentifierToLaunch, *targetContentIdentifier;
@property(copy) NSDictionary *userInfo;
@property(copy) NSData *userInfoData;
@property unsigned long long activationMode;
@end
@implementation SBSApplicationShortcutItem
@end

@interface RCMockApp : NSObject
@property(copy) NSString *bundleIdentifier;
@property(copy) NSArray *staticApplicationShortcutItems, *dynamicApplicationShortcutItems;
@end
@implementation RCMockApp
@end
static RCMockApp *testApp;
static BOOL testLocked;
static id dispatched;

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (id)applicationWithBundleIdentifier:(NSString *)bundle;
@end
@implementation SBApplicationController
+ (instancetype)sharedInstance { static id object; if (!object) object = [self new]; return object; }
- (id)applicationWithBundleIdentifier:(NSString *)bundle { return [bundle isEqual:testApp.bundleIdentifier] ? testApp : nil; }
@end
@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end
@implementation SBLockScreenManager
+ (instancetype)sharedInstance { static id object; if (!object) object = [self new]; return object; }
- (BOOL)isUILocked { return testLocked; }
@end
@interface SBIconView : NSObject
+ (void)activateShortcut:(id)item withBundleIdentifier:(id)bundle forIconView:(id)view;
@end
@implementation SBIconView
+ (void)activateShortcut:(id)item withBundleIdentifier:(id)bundle forIconView:(id)view { dispatched = item; }
@end

static void expect(BOOL ok, const char *name) { if (!ok) { fprintf(stderr,"FAIL: %s\n", name); exit(1); } }
static NSString *run(NSString *identity) {
    NSMutableDictionary *request = [@{@"bundle":testApp.bundleIdentifier, @"type":@"action"} mutableCopy];
    if (identity) request[@"identity"] = identity;
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    return RCQACommandOnMain([@"quickactions run " stringByAppendingString:[data base64EncodedStringWithOptions:0]]);
}
int main(void) {
    @autoreleasepool {
        testApp = [RCMockApp new]; testApp.bundleIdentifier = @"test.example";
        SBSApplicationShortcutItem *first = [SBSApplicationShortcutItem new];
        first.type = @"action"; first.localizedTitle = @"Open"; first.userInfo = @{@"id":@1};
        testApp.staticApplicationShortcutItems = @[first]; testApp.dynamicApplicationShortcutItems = @[first];
        NSString *identity = RCQAIdentity(first);
        expect(identity.length == 67, "identity generated");
        NSString *listing = RCQACommandOnMain(@"quickactions list test.example");
        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:[listing dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        expect([result[@"items"] count] == 1, "duplicate static/dynamic item listed once");
        expect([run(identity) isEqual:@"Quick Shortcut dispatched"] && dispatched == first, "native object preserved and duplicate runs once");
        SBSApplicationShortcutItem *second = [SBSApplicationShortcutItem new];
        second.type = @"action"; second.localizedTitle = @"Open"; second.userInfo = @{@"id":@2};
        testApp.dynamicApplicationShortcutItems = @[second];
        expect([run(nil) hasPrefix:@"Ambiguous"], "legacy type-only command rejects distinct payloads");
        expect([run(identity) isEqual:@"Quick Shortcut dispatched"], "specific payload still resolves");
        first.targetContentIdentifier = @"";
        expect(![identity isEqual:RCQAIdentity(first)], "nil and empty target differ");
        expect([run(identity) containsString:@"no longer registered"], "stale identity does not launch changed item");
        first.targetContentIdentifier = nil;
        testLocked = YES; dispatched = nil;
        expect([run(identity) isEqual:@"Unlock the phone first"] && !dispatched, "lock blocks activation");
        testLocked = NO;
        testApp.staticApplicationShortcutItems = @[]; testApp.dynamicApplicationShortcutItems = @[];
        expect([run(identity) containsString:@"no longer registered"], "empty native list never uses stale cache");
        puts("PASS: Quick Shortcut production lookup/identity/dispatch with native API doubles");
    }
    return 0;
}
