// macOS: clang -fobjc-arc -framework Foundation tools/testkit/app_exclusions_model.m -o /tmp/rc-exclusions && /tmp/rc-exclusions
#import "../../RemoteCompanion/RCTriggerAppExclusions.h"
#include <stdio.h>
#include <stdlib.h>

static void expect(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        NSString *left = @"trigger_statusbar_swipe_left";
        NSString *right = @"trigger_statusbar_swipe_right";
        expect(RCTriggerSupportsAppExclusions(left), "status bar triggers are supported");
        expect(RCTriggerSupportsAppExclusions(@"volume_up_hold"), "button triggers are supported");
        expect(RCTriggerSupportsAppExclusions(@"trigger_bottombar_swipe_left"), "bottom bar triggers are supported");
        expect(RCTriggerSupportsAppExclusions(@"trigger_statusbar_unknown"), "any string key is supported");
        expect(!RCTriggerSupportsAppExclusions(@42), "invalid key type");
        expect(RCNormalizedExcludedApps(nil).count == 0, "missing list");
        expect(RCNormalizedExcludedApps(@"com.example.game").count == 0, "scalar list rejected");
        expect(RCNormalizedExcludedApps(@{ @"app": @"com.example.game" }).count == 0, "dictionary list rejected");
        NSArray *ids = RCNormalizedExcludedApps(@[@" COM.Example.Game\n", @42, [NSNull null], @"",
                                                  @"com.example.game", @"com.apple.MobileSMS"]);
        expect([ids isEqual:@[@"com.example.game", @"com.apple.mobilesms"]], "trim/case/dedupe/type normalization");
        NSDictionary *excluded = @{ @"excludedApps": ids, @"actions": @[@"home"], @"enabled": @YES };
        NSDictionary *unrestricted = @{ @"actions": @[@"flashlight"], @"enabled": @YES };
        NSDictionary *triggers = @{ left: excluded, right: unrestricted };
        expect(RCTriggerExcludesBundleID(left, triggers[left], @"COM.EXAMPLE.GAME"), "exact foreground match");
        expect(RCTriggerExcludesBundleID(left, triggers[left], @"com.apple.MobileSMS"), "mixed-case system app");
        expect(!RCTriggerExcludesBundleID(right, triggers[right], @"com.example.game"), "other behavior still works in same app");
        expect(!RCTriggerExcludesBundleID(left, triggers[left], @"com.example.other"), "same behavior works in other app");
        expect(!RCTriggerExcludesBundleID(left, triggers[left], @"com.example.game.child"), "no prefix matching");
        expect(!RCTriggerExcludesBundleID(left, triggers[left], nil), "unknown foreground fails open");
        expect(!RCTriggerExcludesBundleID(left, triggers[left], @42), "invalid foreground fails open");
        expect(!RCTriggerExcludesBundleID(left, @[], @"com.example.game"), "malformed trigger rejected");
        expect(!RCTriggerExcludesBundleID(left, @{ @"excludedApps": @[@42, [NSNull null]] }, @"com.example.game"), "malformed entries rejected");
        expect(RCTriggerExcludesBundleID(@"volume_up_hold", excluded, @"com.example.game"), "any assigned trigger honors its own field");
        expect(!RCTriggerExcludesBundleID(left, @{ @"excludedApps": @[] }, @"com.example.game"), "cleared list permits behavior");
        puts("PASS: app exclusion model");
    }
    return 0;
}
