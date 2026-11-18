// Loaded into bulletindistributord, which forwards iOS notifications to a paired Apple Watch.
// When an RC notification carries userInfo[@"rcWatch"] ("always" or "only"), this lets it
// alert the Watch even while the iPhone is unlocked or in use, without changing any other app's
// notifications.
//
// Compatible with iOS 14 through iOS 17+. Classes and methods are looked up at run time.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>

#define kRCAppBundleID @"com.saihgupr.remotecompanion"

static __thread int t_rcForceWatchDepth = 0;

static void RCLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log(OS_LOG_DEFAULT, "[RemoteCompanion] %{public}@", msg);

    NSString *logLine = [NSString stringWithFormat:@"%@ [WatchNotifyDaemon] %@\n", [NSDate date], msg];
    const char *paths[] = { "/var/jb/tmp/remotecommand.log", "/tmp/remotecommand.log", NULL };
    for (int i = 0; paths[i]; i++) {
        int fd = open(paths[i], O_WRONLY | O_APPEND | O_CREAT, 0666);
        if (fd >= 0) {
            fchmod(fd, 0666);
            write(fd, logLine.UTF8String, strlen(logLine.UTF8String));
            close(fd);
            break;
        }
    }
}

static NSString *RCWatchModeForBulletin(id bulletin) {
    if (!bulletin) return nil;
    SEL sectionSel = NSSelectorFromString(@"sectionID");
    NSString *sectionID = [bulletin respondsToSelector:sectionSel] ? ((id (*)(id, SEL))objc_msgSend)(bulletin, sectionSel) : nil;
    if (![sectionID isKindOfClass:[NSString class]] || ![sectionID isEqualToString:kRCAppBundleID]) {
        SEL univSel = NSSelectorFromString(@"universalSectionID");
        NSString *univ = [bulletin respondsToSelector:univSel] ? ((id (*)(id, SEL))objc_msgSend)(bulletin, univSel) : nil;
        if (![univ isKindOfClass:[NSString class]] || ![univ isEqualToString:kRCAppBundleID]) return nil;
    }
    SEL contextSel = NSSelectorFromString(@"context");
    NSDictionary *context = [bulletin respondsToSelector:contextSel] ? ((id (*)(id, SEL))objc_msgSend)(bulletin, contextSel) : nil;
    if (![context isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *userInfo = context[@"userInfo"];
    if (![userInfo isKindOfClass:[NSDictionary class]]) return nil;
    id mode = userInfo[@"rcWatch"];
    if ([mode isKindOfClass:[NSString class]] && ([mode isEqualToString:@"always"] || [mode isEqualToString:@"only"])) {
        return mode;
    }
    return nil;
}

static BOOL RCBulletinIsUrgent(id bulletin) {
    if (!bulletin) return NO;
    SEL ignoresSel = NSSelectorFromString(@"ignoresQuietMode");
    if ([bulletin respondsToSelector:ignoresSel] && ((BOOL (*)(id, SEL))objc_msgSend)(bulletin, ignoresSel)) return YES;
    SEL levelSel = NSSelectorFromString(@"interruptionLevel");
    if ([bulletin respondsToSelector:levelSel]) {
        NSUInteger level = ((NSUInteger (*)(id, SEL))objc_msgSend)(bulletin, levelSel);
        if (level >= 2) return YES; // Time Sensitive (2) or Critical (3)
    }
    return NO;
}

static Method RCExactMethodWithSignature(Class cls, NSString *name, unsigned int expectedArgs, char expectedRet) {
    if (!cls) return NULL;
    SEL sel = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return NULL;
    if (method_getNumberOfArguments(method) != expectedArgs) return NULL;
    char ret[8] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    if (ret[0] != expectedRet) return NULL;
    return method;
}

__attribute__((constructor)) static void RCWatchNotifyStart(void) {
    @autoreleasepool {
        Class cls = objc_getClass("BLTBulletinDistributor");
        if (!cls) {
            RCLog(@"bulletindistributord: BLTBulletinDistributor not found");
            return;
        }

        // 1) observer:addBulletin:forFeed:playLightsAndSirens:withReply: (5 args -> 7 objc args)
        SEL add5Sel = NSSelectorFromString(@"observer:addBulletin:forFeed:playLightsAndSirens:withReply:");
        Method add5 = RCExactMethodWithSignature(cls, @"observer:addBulletin:forFeed:playLightsAndSirens:withReply:", 7, 'v');
        if (add5) {
            IMP prev = method_getImplementation(add5);
            method_setImplementation(add5, imp_implementationWithBlock(^(id receiver, id observer, id bulletin, NSUInteger feed, BOOL playLightsAndSirens, id reply) {
                NSString *mode = nil;
                @try { mode = RCWatchModeForBulletin(bulletin); } @catch (NSException *e) {}
                if (mode) {
                    t_rcForceWatchDepth++;
                    @try {
                        ((void (*)(id, SEL, id, id, NSUInteger, BOOL, id))prev)(receiver, add5Sel, observer, bulletin, feed, YES, reply);
                    } @finally {
                        t_rcForceWatchDepth--;
                    }
                    return;
                }
                ((void (*)(id, SEL, id, id, NSUInteger, BOOL, id))prev)(receiver, add5Sel, observer, bulletin, feed, playLightsAndSirens, reply);
            }));
        }

        // 2) observer:addBulletin:forFeed:playLightsAndSirens:attachment:attachmentType:alwaysSend:withReply: (8 args -> 10 objc args)
        SEL add8Sel = NSSelectorFromString(@"observer:addBulletin:forFeed:playLightsAndSirens:attachment:attachmentType:alwaysSend:withReply:");
        Method add8 = RCExactMethodWithSignature(cls, @"observer:addBulletin:forFeed:playLightsAndSirens:attachment:attachmentType:alwaysSend:withReply:", 10, 'v');
        if (add8) {
            IMP prev = method_getImplementation(add8);
            method_setImplementation(add8, imp_implementationWithBlock(^(id receiver, id observer, id bulletin, NSUInteger feed, BOOL playLightsAndSirens, id attachment, NSInteger attachmentType, BOOL alwaysSend, id reply) {
                NSString *mode = nil;
                @try { mode = RCWatchModeForBulletin(bulletin); } @catch (NSException *e) {}
                if (mode) {
                    t_rcForceWatchDepth++;
                    @try {
                        ((void (*)(id, SEL, id, id, NSUInteger, BOOL, id, NSInteger, BOOL, id))prev)(receiver, add8Sel, observer, bulletin, feed, YES, attachment, attachmentType, YES, reply);
                    } @finally {
                        t_rcForceWatchDepth--;
                    }
                    return;
                }
                ((void (*)(id, SEL, id, id, NSUInteger, BOOL, id, NSInteger, BOOL, id))prev)(receiver, add8Sel, observer, bulletin, feed, playLightsAndSirens, attachment, attachmentType, alwaysSend, reply);
            }));
        }

        // 3) _addBulletin:forFeed:playLightsAndSirens:attachment:attachmentType:alwaysSend:completion: (7 args -> 9 objc args)
        SEL internalAddSel = NSSelectorFromString(@"_addBulletin:forFeed:playLightsAndSirens:attachment:attachmentType:alwaysSend:completion:");
        Method internalAdd = RCExactMethodWithSignature(cls, @"_addBulletin:forFeed:playLightsAndSirens:attachment:attachmentType:alwaysSend:completion:", 9, 'v');
        if (internalAdd) {
            IMP prev = method_getImplementation(internalAdd);
            method_setImplementation(internalAdd, imp_implementationWithBlock(^(id receiver, id bulletin, NSUInteger feed, BOOL playLightsAndSirens, id attachment, NSInteger attachmentType, BOOL alwaysSend, id completion) {
                NSString *mode = nil;
                @try { mode = RCWatchModeForBulletin(bulletin); } @catch (NSException *e) {}
                if (mode) {
                    t_rcForceWatchDepth++;
                    @try {
                        ((void (*)(id, SEL, id, NSUInteger, BOOL, id, NSInteger, BOOL, id))prev)(receiver, internalAddSel, bulletin, feed, YES, attachment, attachmentType, YES, completion);
                    } @finally {
                        t_rcForceWatchDepth--;
                    }
                    return;
                }
                ((void (*)(id, SEL, id, NSUInteger, BOOL, id, NSInteger, BOOL, id))prev)(receiver, internalAddSel, bulletin, feed, playLightsAndSirens, attachment, attachmentType, alwaysSend, completion);
            }));
        }

        // 4) _willNanoPresent:forBulletin:feed:
        SEL willPresent3Sel = NSSelectorFromString(@"_willNanoPresent:forBulletin:feed:");
        Method willPresent3 = RCExactMethodWithSignature(cls, @"_willNanoPresent:forBulletin:feed:", 5, 'B');
        if (willPresent3) {
            IMP prev = method_getImplementation(willPresent3);
            method_setImplementation(willPresent3, imp_implementationWithBlock(^BOOL(id receiver, NSUInteger feed, id bulletin, NSUInteger otherFeed) {
                if (t_rcForceWatchDepth > 0 || RCWatchModeForBulletin(bulletin) != nil) return YES;
                return ((BOOL (*)(id, SEL, NSUInteger, id, NSUInteger))prev)(receiver, willPresent3Sel, feed, bulletin, otherFeed);
            }));
        }

        // 5) _willNanoPresent:
        SEL willPresent1Sel = NSSelectorFromString(@"_willNanoPresent:");
        Method willPresent1 = RCExactMethodWithSignature(cls, @"_willNanoPresent:", 3, 'B');
        if (willPresent1) {
            IMP prev = method_getImplementation(willPresent1);
            method_setImplementation(willPresent1, imp_implementationWithBlock(^BOOL(id receiver, NSUInteger feed) {
                if (t_rcForceWatchDepth > 0) return YES;
                return ((BOOL (*)(id, SEL, NSUInteger))prev)(receiver, willPresent1Sel, feed);
            }));
        }

        // 6) shouldSuppressLightsAndSirensNow
        SEL suppressSel = NSSelectorFromString(@"shouldSuppressLightsAndSirensNow");
        Method suppress = RCExactMethodWithSignature(cls, @"shouldSuppressLightsAndSirensNow", 2, 'B');
        if (suppress) {
            IMP prev = method_getImplementation(suppress);
            method_setImplementation(suppress, imp_implementationWithBlock(^BOOL(id receiver) {
                if (t_rcForceWatchDepth > 0) return NO;
                return ((BOOL (*)(id, SEL))prev)(receiver, suppressSel);
            }));
        }

        // 7) _notifyGizmoOfBulletin:forFeed:updateType:playLightsAndSirens:shouldSendReplyIfNeeded:attachment:attachmentType:replyToken:
        SEL notifySel = NSSelectorFromString(@"_notifyGizmoOfBulletin:forFeed:updateType:playLightsAndSirens:shouldSendReplyIfNeeded:attachment:attachmentType:replyToken:");
        Method notifyM = RCExactMethodWithSignature(cls, @"_notifyGizmoOfBulletin:forFeed:updateType:playLightsAndSirens:shouldSendReplyIfNeeded:attachment:attachmentType:replyToken:", 10, 'B');
        if (notifyM) {
            IMP prev = method_getImplementation(notifyM);
            method_setImplementation(notifyM, imp_implementationWithBlock(^BOOL(id receiver, id bulletin, NSUInteger feed, NSUInteger updateType, BOOL playLightsAndSirens, BOOL shouldReply, id attachment, NSInteger attachmentType, id replyToken) {
                NSString *mode = nil;
                @try { mode = RCWatchModeForBulletin(bulletin); } @catch (NSException *e) {}
                if (mode) {
                    BOOL sent = ((BOOL (*)(id, SEL, id, NSUInteger, NSUInteger, BOOL, BOOL, id, NSInteger, id))prev)(receiver, notifySel, bulletin, feed, updateType, YES, shouldReply, attachment, attachmentType, replyToken);
                    RCLog(@"Forwarded Watch notification (%@): sent=%d", mode, sent);
                    return sent;
                }
                return ((BOOL (*)(id, SEL, id, NSUInteger, NSUInteger, BOOL, BOOL, id, NSInteger, id))prev)(receiver, notifySel, bulletin, feed, updateType, playLightsAndSirens, shouldReply, attachment, attachmentType, replyToken);
            }));
        }

        // 8) _sendPBBulletin:forBulletin:feed:updateType:playLightsAndSirens:shouldSendReplyIfNeeded:
        SEL sendPBSel = NSSelectorFromString(@"_sendPBBulletin:forBulletin:feed:updateType:playLightsAndSirens:shouldSendReplyIfNeeded:");
        Method sendPB = RCExactMethodWithSignature(cls, @"_sendPBBulletin:forBulletin:feed:updateType:playLightsAndSirens:shouldSendReplyIfNeeded:", 8, 'v');
        if (sendPB) {
            IMP prev = method_getImplementation(sendPB);
            method_setImplementation(sendPB, imp_implementationWithBlock(^(id receiver, id pbBulletin, id bulletin, NSUInteger feed, NSUInteger updateType, BOOL playLightsAndSirens, BOOL shouldReply) {
                NSString *mode = nil;
                @try { mode = RCWatchModeForBulletin(bulletin); } @catch (NSException *e) {}
                if (mode) {
                    SEL noDelaySel = NSSelectorFromString(@"setSuppressDelayForForwardedBulletins:");
                    if ([pbBulletin respondsToSelector:noDelaySel]) {
                        ((void (*)(id, SEL, BOOL))objc_msgSend)(pbBulletin, noDelaySel, YES);
                    }
                    SEL includesSoundSel = NSSelectorFromString(@"setIncludesSound:");
                    if ([pbBulletin respondsToSelector:includesSoundSel]) {
                        ((void (*)(id, SEL, BOOL))objc_msgSend)(pbBulletin, includesSoundSel, YES);
                    }
                    if (RCBulletinIsUrgent(bulletin)) {
                        SEL ignoresQuietSel = NSSelectorFromString(@"setIgnoresQuietMode:");
                        if ([pbBulletin respondsToSelector:ignoresQuietSel]) {
                            ((void (*)(id, SEL, BOOL))objc_msgSend)(pbBulletin, ignoresQuietSel, YES);
                        }
                    }
                    ((void (*)(id, SEL, id, id, NSUInteger, NSUInteger, BOOL, BOOL))prev)(receiver, sendPBSel, pbBulletin, bulletin, feed, updateType, YES, shouldReply);
                    return;
                }
                ((void (*)(id, SEL, id, id, NSUInteger, NSUInteger, BOOL, BOOL))prev)(receiver, sendPBSel, pbBulletin, bulletin, feed, updateType, playLightsAndSirens, shouldReply);
            }));
        }

        RCLog(@"bulletindistributord: Watch notification hooks installed");
    }
}
