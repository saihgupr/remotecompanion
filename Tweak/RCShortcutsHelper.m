// RCShortcutsHelper - loaded into siriactionsd, where shortcuts run.
//
// - Runs shortcuts for RemoteCompanion (rc_run_shortcut): looks the shortcut up by name in the
//   Shortcuts database and starts it with WFWidgetWorkflowRunnerClient, as a widget does. The
//   same calls SpringCuts makes, so RemoteCompanion no longer needs SpringCuts.
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

// Running shortcuts. Everything here runs on the main queue.

@interface RCShortcutRun : NSObject
@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *identifier; // set while its input or silent run is in place
@property (nonatomic, retain) id client;
@end

@implementation RCShortcutRun
- (void)dealloc {
    [_requestID release];
    [_name release];
    [_identifier release];
    [_client release];
    [super dealloc];
}
@end

static NSMutableArray *g_runs; // kept until each shortcut ends: the runner client only keeps a weak delegate

static id rc_send(id obj, const char *name) {
    SEL sel = sel_registerName(name);
    return [obj respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static void rc_reply(NSString *requestID, NSString *state, NSString *error) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:requestID ?: @"", @"id", state, @"state", nil];
    if (error) [info setObject:error forKey:@"error"];
    id center = [objc_getClass("NSDistributedNotificationCenter") defaultCenter];
    ((void (*)(id, SEL, id, id, id, BOOL))objc_msgSend)(center, sel_registerName("postNotificationName:object:userInfo:deliverImmediately:"),
        kRCShortcutsRunReply, nil, info, YES);
}

// The visible shortcut with this name (the first, if several share it)
static id rc_reference_named(NSString *name) {
    id database = rc_send(objc_getClass("WFDatabase"), "defaultDatabase");
    if (!database) return nil;
    SEL byName = sel_registerName("visibleReferencesForWorkflowName:");
    if ([database respondsToSelector:byName]) {
        NSArray *refs = ((id (*)(id, SEL, id))objc_msgSend)(database, byName, name);
        if ([refs count]) return [refs objectAtIndex:0];
    }
    for (id ref in rc_send(rc_send(database, "sortedVisibleWorkflowsByName"), "descriptors")) {
        if ([rc_send(ref, "name") isEqual:name]) return ref;
    }
    return nil;
}

static id rc_runner_client(NSString *identifier) {
    Class cls = objc_getClass("WFWidgetWorkflowRunnerClient");
    SEL withLocation = sel_registerName("initWithWorkflowIdentifier:location:"), plain = sel_registerName("initWithWorkflowIdentifier:");
    if (class_getInstanceMethod(cls, withLocation)) {
        return ((id (*)(id, SEL, id, long long))objc_msgSend)([cls alloc], withLocation, identifier, 0);
    }
    if (class_getInstanceMethod(cls, plain)) return ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], plain, identifier);
    return nil;
}

// Text input, passed the way SpringCuts does: a shortcut gets its input from its run request,
// which the runner client creates (initWithDescriptor:input:presentationMode:) and sends to the
// process that runs it (archivedInput). Both are changed to give the text while one of our runs
// with input is going: by workflow identifier for requests made from a descriptor, and on the
// client's own request.
static NSMutableDictionary *g_inputs; // workflow identifier -> text
static const char kRCInputKey = 0;     // the text, on a client's run request
static IMP g_origInitWithDescriptor, g_origArchivedInput;

static id rc_collection_with_text(NSString *text) {
    Class collectionClass = objc_getClass("WFContentCollection"), itemClass = objc_getClass("WFContentItem");
    id item = ((id (*)(id, SEL, id))objc_msgSend)(itemClass, sel_registerName("itemWithObject:"), text);
    if (!collectionClass || !item) return nil;
    id collection = [[[collectionClass alloc] init] autorelease];
    ((void (*)(id, SEL, id))objc_msgSend)(collection, sel_registerName("addItem:"), item);
    return collection;
}

static NSString *rc_input_for_identifier(id identifier) {
    if (!identifier) return nil;
    @synchronized (g_inputs) { return [[[g_inputs objectForKey:identifier] retain] autorelease]; }
}

// Silent runs (presentation mode 3, what SpringCuts uses for -i): no Shortcuts progress on
// screen. Set on the client's run request, and on requests made from a descriptor while it runs.
static const unsigned long kRCSilentPresentationMode = 3;
static NSMutableSet *g_silent; // workflow identifiers

static id rc_initWithDescriptor(id self, SEL _cmd, id descriptor, id input, unsigned long mode) {
    @synchronized (g_inputs) { if ([g_silent containsObject:rc_send(descriptor, "identifier") ?: @""]) mode = kRCSilentPresentationMode; }
    NSString *text = input ? nil : rc_input_for_identifier(rc_send(descriptor, "identifier"));
    if (text) input = rc_collection_with_text(text);
    return ((id (*)(id, SEL, id, id, unsigned long))g_origInitWithDescriptor)(self, _cmd, descriptor, input, mode);
}

static id rc_archivedInput(id self, SEL _cmd) {
    NSString *text = objc_getAssociatedObject(self, &kRCInputKey);
    id collection = text ? rc_collection_with_text(text) : nil;
    if (collection) {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:collection requiringSecureCoding:NO error:NULL];
        if (data) return data;
    }
    return ((id (*)(id, SEL))g_origArchivedInput)(self, _cmd);
}

// NO when this iOS has neither way in
static BOOL rc_hook_input(void) {
    static BOOL hooked;
    if (hooked) return YES;
    Class requestClass = objc_getClass("WFWorkflowRunRequest");
    Method initMethod = class_getInstanceMethod(requestClass, sel_registerName("initWithDescriptor:input:presentationMode:"));
    Method archivedMethod = class_getInstanceMethod(requestClass, sel_registerName("archivedInput"));
    if (!archivedMethod && !initMethod) return NO;
    if (initMethod) g_origInitWithDescriptor = method_setImplementation(initMethod, (IMP)rc_initWithDescriptor);
    if (archivedMethod) g_origArchivedInput = method_setImplementation(archivedMethod, (IMP)rc_archivedInput);
    g_inputs = [[NSMutableDictionary alloc] init];
    hooked = YES;
    return YES;
}

// WFWorkflowRunnerClientDelegate, added to RCShortcutRun at load
static void rc_run_did_finish(RCShortcutRun *self, SEL _cmd, id client, NSError *error, BOOL cancelled) {
    if (self.identifier) {
        @synchronized (g_inputs) { [g_inputs removeObjectForKey:self.identifier]; [g_silent removeObject:self.identifier]; }
    }
    if (error) rc_reply(self.requestID, @"failed", [error localizedDescription] ?: [error description]);
    else rc_reply(self.requestID, cancelled ? @"cancelled" : @"finished", nil);
    [g_runs removeObjectIdenticalTo:self];
}

static void rc_run_shortcut(NSDictionary *request) {
    NSString *name = [request objectForKey:@"name"], *input = [request objectForKey:@"input"], *requestID = [request objectForKey:@"id"];
    if (![name isKindOfClass:[NSString class]] || ![name length]) return;
    id reference = rc_reference_named(name);
    if (!reference) {
        rc_reply(requestID, objc_getClass("WFDatabase") ? @"missing" : @"unsupported", objc_getClass("WFDatabase") ? nil : @"no Shortcuts database");
        return;
    }
    id client = rc_runner_client(rc_send(reference, "identifier"));
    if (!client) {
        rc_reply(requestID, @"unsupported", @"no widget runner");
        return;
    }
    BOOL withInput = [input isKindOfClass:[NSString class]] && [input length];
    BOOL silent = [[request objectForKey:@"silent"] boolValue];
    if ((withInput || silent) && !rc_hook_input()) {
        [client release];
        rc_reply(requestID, @"unsupported", @"no way to pass the input");
        return;
    }
    RCShortcutRun *run = [[RCShortcutRun alloc] init];
    run.requestID = requestID;
    run.name = name;
    run.client = client;
    if (silent) {
        NSString *identifier = rc_send(reference, "identifier");
        run.identifier = identifier;
        @synchronized (g_inputs) {
            if (!g_silent) g_silent = [[NSMutableSet alloc] init];
            if (identifier) [g_silent addObject:identifier];
        }
        id runRequest = rc_send(client, "runRequest");
        SEL setMode = sel_registerName("setPresentationMode:");
        if ([runRequest respondsToSelector:setMode]) ((void (*)(id, SEL, unsigned long))objc_msgSend)(runRequest, setMode, kRCSilentPresentationMode);
    }
    if (withInput) {
        NSString *identifier = rc_send(reference, "identifier");
        run.identifier = identifier;
        if (identifier) {
            @synchronized (g_inputs) { [g_inputs setObject:input forKey:identifier]; }
        }
        id runRequest = rc_send(client, "runRequest");
        if (runRequest) objc_setAssociatedObject(runRequest, &kRCInputKey, input, OBJC_ASSOCIATION_COPY);
    }
    [client release];
    if (!g_runs) g_runs = [[NSMutableArray alloc] init];
    [g_runs addObject:run];
    [run release];
    ((void (*)(id, SEL, id))objc_msgSend)(run.client, sel_registerName("setDelegate:"), run);
    ((void (*)(id, SEL))objc_msgSend)(run.client, sel_registerName("start"));
    rc_reply(requestID, @"started", nil);
}

static void rc_list_shortcuts(NSString *requestID) {
    id database = rc_send(objc_getClass("WFDatabase"), "defaultDatabase");
    if (!database) {
        rc_reply(requestID, @"unsupported", @"no Shortcuts database");
        return;
    }
    NSMutableArray *names = [NSMutableArray array];
    for (id ref in rc_send(rc_send(database, "sortedVisibleWorkflowsByName"), "descriptors")) {
        NSString *name = rc_send(ref, "name");
        if ([name isKindOfClass:[NSString class]] && [name length]) [names addObject:name];
    }
    id center = [objc_getClass("NSDistributedNotificationCenter") defaultCenter];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:requestID ?: @"", @"id", @"list", @"state", names, @"names", nil];
    ((void (*)(id, SEL, id, id, id, BOOL))objc_msgSend)(center, sel_registerName("postNotificationName:object:userInfo:deliverImmediately:"),
        kRCShortcutsRunReply, nil, info, YES);
}

static void rc_listen_for_runs(void) {
    class_addMethod([RCShortcutRun class], sel_registerName("workflowRunnerClient:didFinishRunningWorkflowWithError:cancelled:"),
                    (IMP)rc_run_did_finish, "v@:@@B");
    id center = [objc_getClass("NSDistributedNotificationCenter") defaultCenter];
    if (!center) return;
    // Kept for the life of the process
    [[center addObserverForName:kRCShortcutsRunRequest object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        @try {
            if ([[[note userInfo] objectForKey:@"action"] isEqual:@"list"]) rc_list_shortcuts([[note userInfo] objectForKey:@"id"]);
            else rc_run_shortcut([note userInfo]);
        } @catch (NSException *e) {
            rc_reply([[note userInfo] objectForKey:@"id"], @"failed", [e reason]);
        }
    }] retain];
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
        rc_listen_for_runs();
        rc_announce_ready();
        if (!added) rc_retry_add(120);
    });
}
