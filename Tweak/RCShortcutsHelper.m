// RCShortcutsHelper - loaded into siriactionsd, where SpringCuts runs shortcuts.
//
// - SpringCuts starts a shortcut with -[WFWidgetWorkflowRunnerClient initWithWorkflowIdentifier:],
//   which iOS 17 replaced with initWithWorkflowIdentifier:location:. Without it no shortcut
//   starts, so it's added back, calling the new one.
// - SpringCuts sends its requests to siriactionsd with notifications, which can't start a
//   process, so RemoteCompanion starts siriactionsd itself when it isn't running and waits for
//   this helper to say it's ready (kRCShortcutsHelperNotification, its state = this pid).
//
// Built without ARC: the added method is an initializer, which takes ownership of self and
// returns an owned object.

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <notify.h>
#include <unistd.h>
#include "RCShortcutsHelper.h"

static id rc_initWithWorkflowIdentifier(id self, SEL _cmd, id identifier) {
    SEL newSel = sel_registerName("initWithWorkflowIdentifier:location:");
    if (![self respondsToSelector:newSel]) {
        [self release];
        return nil;
    }
    return ((id (*)(id, SEL, id, long long))objc_msgSend)(self, newSel, identifier, 0);
}

// YES once WFWidgetWorkflowRunnerClient has the method (added, or it has its own)
static BOOL rc_add_initWithWorkflowIdentifier(void) {
    Class cls = objc_getClass("WFWidgetWorkflowRunnerClient");
    if (!cls) return NO;
    SEL oldSel = sel_registerName("initWithWorkflowIdentifier:");
    if (!class_getInstanceMethod(cls, oldSel)) {
        class_addMethod(cls, oldSel, (IMP)rc_initWithWorkflowIdentifier, "@@:@");
    }
    return YES;
}

static void rc_announce_ready(void) {
    // The registration is kept so the state stays while this process runs
    static int token = NOTIFY_TOKEN_INVALID;
    if (token == NOTIFY_TOKEN_INVALID && notify_register_check(kRCShortcutsHelperNotification, &token) != NOTIFY_STATUS_OK) {
        token = NOTIFY_TOKEN_INVALID;
    }
    if (token != NOTIFY_TOKEN_INVALID) notify_set_state(token, (uint64_t)getpid());
    notify_post(kRCShortcutsHelperNotification);
}

// The class comes with a framework siriactionsd links, so it's normally there already
static void rc_retry_add(int attemptsLeft) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!rc_add_initWithWorkflowIdentifier() && attemptsLeft > 1) rc_retry_add(attemptsLeft - 1);
    });
}

__attribute__((constructor))
static void rc_shortcuts_helper_init(void) {
    BOOL added = rc_add_initWithWorkflowIdentifier();
    // Ready once siriactionsd's main queue runs: every tweak (SpringCuts' runner too) has loaded.
    // Without the class (another iOS, or SpringCuts not using it) there's nothing to add, but
    // RemoteCompanion still waits for this
    dispatch_async(dispatch_get_main_queue(), ^{
        rc_announce_ready();
        if (!added) rc_retry_add(120);
    });
}
