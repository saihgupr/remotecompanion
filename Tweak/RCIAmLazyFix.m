// Loaded into /var/jb/usr/local/bin/ial (me.lightmann.iamlazy-cli v2.6.2).
// Upstream ial registers NSNotificationCenter observers for "updateItemStatus"
// and "updateItemProgress" on [NSOperationQueue mainQueue] while main() parks
// the main thread in dispatch_semaphore_wait(..., DISPATCH_TIME_FOREVER),
// causing postNotificationName:object: to deadlock on the first status update.
// Passing queue: nil runs the observer blocks on the posting thread instead.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdio.h>

__attribute__((constructor)) static void RCIAmLazyFixInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        setvbuf(stdout, NULL, _IOLBF, 0);
        setvbuf(stderr, NULL, _IONBF, 0);

        Class cls = [NSNotificationCenter class];
        SEL sel = @selector(addObserverForName:object:queue:usingBlock:);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) return;
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^id(id self, NSNotificationName name, id obj, NSOperationQueue *queue, void (^block)(NSNotification *)) {
            if (queue == [NSOperationQueue mainQueue]) {
                queue = nil;
            }
            return ((id (*)(id, SEL, NSNotificationName, id, NSOperationQueue *, void (^)(NSNotification *)))orig)(self, sel, name, obj, queue, block);
        }));
    });
}

