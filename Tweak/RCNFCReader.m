// Loaded into nfcd (Experimental NFC). iPhone XS and later read NFC tags on their own while the screen
// is on, the way NFC tag notifications work on a stock iPhone; nothing holds the NFC controller, so
// Apple Pay, Express cards and other apps use it as usual. This passes each tag that reader detects
// to SpringBoard, where RemoteCompanion runs its trigger.
//
// Off unless SpringBoard says Experimental NFC is on (state of kRCNFCBackgroundState). Every class,
// method and field is looked up by name and checked; nothing is called by address.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <os/log.h>

#define kRCNFCBackgroundState "com.pizzaman.rc.nfc_background"         // state 1: Experimental NFC is on
#define kRCNFCBackgroundTag   "com.pizzaman.rc.nfc_background_tag"     // posted per tag: state = ID length << 56 | ID bytes

static BOOL RCBackgroundOn(void) {
    static int token = NOTIFY_TOKEN_INVALID;
    if (token == NOTIFY_TOKEN_INVALID && notify_register_check(kRCNFCBackgroundState, &token) != NOTIFY_STATUS_OK) return NO;
    uint64_t state = 0;
    notify_get_state(token, &state);
    return state == 1;
}

static void RCAnnounceTag(NSArray *tags) {
    static int token = NOTIFY_TOKEN_INVALID;
    if (token == NOTIFY_TOKEN_INVALID) notify_register_check(kRCNFCBackgroundTag, &token);
    SEL tagIDSelector = NSSelectorFromString(@"tagID");
    for (id tag in tags) {
        NSData *uid = [tag respondsToSelector:tagIDSelector] ? ((id (*)(id, SEL))objc_msgSend)(tag, tagIDSelector) : nil;
        if (![uid isKindOfClass:[NSData class]] || uid.length == 0 || uid.length > 7) continue;
        const uint8_t *bytes = uid.bytes;
        uint64_t value = 0;
        for (NSUInteger i = 0; i < uid.length; i++) value = (value << 8) | bytes[i];
        notify_set_state(token, ((uint64_t)uid.length << 56) | value);
        notify_post(kRCNFCBackgroundTag);
        return; // one tag per detection
    }
}

// The camera monitor nfcd's background reader asks before reading, caught when nfcd makes it
static id g_cameraMonitor;

__attribute__((constructor)) static void RCNFCReaderStart(void) {
    @autoreleasepool {
        Class reader = objc_getClass("NFBackgroundTagReadingManager");
        if (!reader) {
            os_log(OS_LOG_DEFAULT, "[RemoteCompanion] nfcd: no background tag reader on this device");
            return;
        }

        // Each tag the background reader detects
        SEL detected = NSSelectorFromString(@"handleDetectedTags:");
        Method detectedMethod = class_getInstanceMethod(reader, detected);
        if (detectedMethod) {
            IMP previous = method_getImplementation(detectedMethod);
            method_setImplementation(detectedMethod, imp_implementationWithBlock(^(id receiver, NSArray *tags) {
                if (RCBackgroundOn() && [tags isKindOfClass:[NSArray class]]) {
                    @try { RCAnnounceTag(tags); } @catch (NSException *e) {}
                }
                ((void (*)(id, SEL, id))previous)(receiver, detected, tags);
            }));
        }

        // The background reader stops while the camera is in use, and the flashlight counts, so a tag
        // that turns the flashlight on couldn't turn it off. The flashlight alone (camera state 0x1;
        // the Camera app is 0x9) is passed on as no camera; the Camera app still stops it.
        Class monitorClass = objc_getClass("NFCameraStateMonitor");
        Method monitorInit = monitorClass ? class_getInstanceMethod(monitorClass, @selector(init)) : NULL;
        Ivar statesIvar = monitorClass ? class_getInstanceVariable(monitorClass, "_cameraStates") : NULL;
        SEL camera = NSSelectorFromString(@"didCameraStateChange:");
        Method cameraMethod = class_getInstanceMethod(reader, camera);
        if (monitorInit && statesIvar && cameraMethod && ivar_getTypeEncoding(statesIvar)[0] == 'i') {
            IMP previousInit = method_getImplementation(monitorInit);
            method_setImplementation(monitorInit, imp_implementationWithBlock(^id(id receiver) {
                id made = ((id (*)(id, SEL))previousInit)(receiver, @selector(init));
                if (made) g_cameraMonitor = made;
                return made;
            }));
            ptrdiff_t offset = ivar_getOffset(statesIvar);
            IMP previousCamera = method_getImplementation(cameraMethod);
            method_setImplementation(cameraMethod, imp_implementationWithBlock(^(id receiver, BOOL inUse) {
                id monitor = g_cameraMonitor;
                int32_t *states = monitor ? (int32_t *)((__bridge void *)monitor + offset) : NULL;
                BOOL flashlightOnly = RCBackgroundOn() && states && *states == 0x1;
                if (flashlightOnly) *states = 0;
                ((void (*)(id, SEL, BOOL))previousCamera)(receiver, camera, flashlightOnly ? NO : inUse);
            }));
        }
        os_log(OS_LOG_DEFAULT, "[RemoteCompanion] nfcd: background tag reader hooked");
    }
}
