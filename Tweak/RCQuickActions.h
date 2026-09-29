// Native Quick Shortcut catalog and activation. No diagnostic recording.
#import <substrate.h>
static id RCQAGet(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *e) { return nil; }
}
static NSString *RCQAString(id value) {
    return [value isKindOfClass:NSString.class] ? [value substringToIndex:MIN([value length], 200)] : @"";
}
static NSArray *RCQAItems(id items) {
    if (![items isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *rows = [NSMutableArray array];
    for (id item in items) {
        if (rows.count >= 32) break;
        NSString *type = RCQAString([item isKindOfClass:NSDictionary.class] ? item[@"UIApplicationShortcutItemType"] : RCQAGet(item, @"type"));
        NSString *title = RCQAString([item isKindOfClass:NSDictionary.class] ? item[@"UIApplicationShortcutItemTitle"] : RCQAGet(item, @"localizedTitle"));
        if (type.length) [rows addObject:@{@"type":type, @"title":title}];
    }
    return rows;
}
static NSString *RCQAJSON(id data) {
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil];
    return bytes ? [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] : @"{}";
}
static NSMutableDictionary *RCQACatalog;
static NSMapTable *RCQAViews;
static NSMutableDictionary *RCQASaved;
static NSString *const RCQAPath = @"/var/mobile/Library/Preferences/com.saihgupr.remotecompanion.quickshortcuts.plist";
static dispatch_queue_t RCQASaveQueue;
static void RCQALoad(void) {
    if (RCQASaved) return;
    id saved = [NSDictionary dictionaryWithContentsOfFile:RCQAPath];
    RCQASaved = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    RCQASaveQueue = dispatch_queue_create("remotecompanion.quickshortcuts.save", DISPATCH_QUEUE_SERIAL);
}
// Persist property-list values, not private framework object archives.
// A private shortcut class may implement NSCoding but not NSSecureCoding.
static NSDictionary *RCQASnapshot(id item) {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"type", @"localizedTitle", @"localizedSubtitle", @"bundleIdentifierToLaunch", @"targetContentIdentifier", @"userInfo"]) {
        id value = RCQAGet(item,key);
        if (!value) continue;
        if ([key isEqualToString:@"userInfo"]) {
            if (![value isKindOfClass:NSDictionary.class]) return nil;
        } else if (![value isKindOfClass:NSString.class]) return nil;
        if (![NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0]) return nil;
        row[key] = value;
    }
    if (![row[@"type"] length]) return nil;
    NSData *bytes = [NSPropertyListSerialization dataWithPropertyList:row format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!bytes || bytes.length > 65536) return nil;
    return row;
}
static BOOL RCQASet(id item, NSString *key, id value) {
    NSString *name = [NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = [item methodSignatureForSelector:selector];
    if (!sig || sig.numberOfArguments != 3 || sig.methodReturnType[0] != 'v' || [sig getArgumentTypeAtIndex:2][0] != '@') return NO;
    @try { ((void (*)(id,SEL,id))objc_msgSend)(item,selector,value); return YES; }
    @catch (__unused NSException *e) { return NO; }
}
static void RCQAPersist(NSString *bundle, NSArray *items) {
    RCQALoad();
    NSMutableArray *rows = [NSMutableArray array];
    for (id item in items) {
        NSDictionary *row = RCQASnapshot(item);
        if (!row) { SRLog(@"Quick Shortcut: payload cannot be saved; previous cache retained"); return; }
        [rows addObject:row];
    }
    if ([RCQASaved[bundle] isEqual:rows]) return;
    RCQASaved[bundle] = rows;
    NSDictionary *snapshot = [RCQASaved copy];
    dispatch_async(RCQASaveQueue, ^{
        NSError *error = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
        BOOL ok = data && [data writeToFile:RCQAPath options:NSDataWritingAtomic error:&error];
        if (ok) [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:RCQAPath error:nil];
        else SRLog(@"Quick Shortcut: save failed domain=%@ code=%ld", error.domain, (long)error.code);
    });
}
static NSArray *RCQARestore(NSString *bundle) {
    RCQALoad();
    id rows = RCQASaved[bundle];
    if (![rows isKindOfClass:NSArray.class]) return @[];
    Class cls = NSClassFromString(@"SBSApplicationShortcutItem");
    if (!cls) return @[];
    NSMutableArray *items = [NSMutableArray array];
    for (id row in rows) {
        if (![row isKindOfClass:NSDictionary.class] || ![row[@"type"] isKindOfClass:NSString.class]) continue;
        @try {
            id item = [[cls alloc] init];
            BOOL valid = YES;
            for (NSString *key in @[@"type", @"localizedTitle", @"localizedSubtitle", @"bundleIdentifierToLaunch", @"targetContentIdentifier", @"userInfo"]) {
                id value = row[key];
                if (!value) continue;
                if ([key isEqualToString:@"userInfo"] ? ![value isKindOfClass:NSDictionary.class] : ![value isKindOfClass:NSString.class]) { valid=NO; break; }
                if (!RCQASet(item,key,value)) { valid=NO; break; }
            }
            if (valid && item) [items addObject:item];
        } @catch (__unused NSException *e) {}
        if (items.count >= 32) break;
    }
    return items;
}

static BOOL RCQAExcludedType(NSString *type) {
    return [type hasPrefix:@"com.apple.springboardhome.application-shortcut-item."] ||
        [type isEqualToString:@"CustomAddToFolderItem"] ||
        [type hasPrefix:@"com.opa334.choicy."] || [type hasPrefix:@"com.sergy.immortalizer."];
}
static void RCQARemember(id view, id raw) {
    NSString *bundle = RCQAString(RCQAGet(RCQAGet(view,@"icon"),@"applicationBundleID"));
    if (!bundle.length || ![raw isKindOfClass:NSArray.class]) return;
    if (!RCQACatalog) RCQACatalog = [NSMutableDictionary dictionary];
    if (!RCQAViews) RCQAViews = [NSMapTable strongToWeakObjectsMapTable];
    NSMutableArray *items = [NSMutableArray array];
    for (id item in raw) {
        NSString *type = RCQAString(RCQAGet(item,@"type"));
        if (type.length && !RCQAExcludedType(type) && items.count < 32) [items addObject:item];
    }
    if (RCQACatalog.count >= 512 && !RCQACatalog[bundle]) return;
    RCQACatalog[bundle] = items;
    RCQAPersist(bundle, items);
    [RCQAViews setObject:view forKey:bundle];
}
static NSString *RCQARun(NSString *encoded) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    id request = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![request isKindOfClass:NSDictionary.class]) return @"Invalid Quick Shortcut request";
    NSString *bundle = RCQAString(request[@"bundle"]), *type = RCQAString(request[@"type"]);
    id view = [RCQAViews objectForKey:bundle];
    if (view && ![RCQAString(RCQAGet(RCQAGet(view,@"icon"),@"applicationBundleID")) isEqual:bundle]) view = nil;
    id lock = RCQAGet(NSClassFromString(@"SBLockScreenManager"),@"sharedInstance");
    SEL locked = NSSelectorFromString(@"isUILocked");
    NSMethodSignature *ls = [lock methodSignatureForSelector:locked];
    if (!ls || ls.numberOfArguments != 2 || (ls.methodReturnType[0] != 'B' && ls.methodReturnType[0] != 'c')) return @"Lock status unavailable";
    if (((BOOL (*)(id,SEL))objc_msgSend)(lock,locked)) return @"Unlock the phone first";
    if (view) RCQARemember(view,RCQAGet(view,@"applicationShortcutItems"));
    id selected = nil;
    NSArray *currentItems = RCQACatalog[bundle] ?: RCQARestore(bundle);
    for (id item in currentItems) if ([RCQAString(RCQAGet(item,@"type")) isEqual:type]) { selected=item; break; }
    if (!selected) return @"Quick Shortcut no longer available";
    Class cls = NSClassFromString(@"SBIconView");
    SEL action = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
    NSMethodSignature *sig = [cls methodSignatureForSelector:action];
    if (!sig || sig.numberOfArguments != 5 || sig.methodReturnType[0] != 'v') return @"Native Quick Shortcut activation unavailable";
    for (NSUInteger i=2;i<5;i++) if ([sig getArgumentTypeAtIndex:i][0]!='@') return @"Unsupported activation signature";
    @try {
        ((void (*)(id,SEL,id,id,id))objc_msgSend)(cls,action,selected,bundle,view);
        return @"Quick Shortcut dispatched";
    } @catch (__unused NSException *e) { return @"Quick Shortcut activation failed"; }
}
static id (*RCQAOriginalItems)(id, SEL);
static id RCQAObservedItems(id object, SEL selector) {
    id result = RCQAOriginalItems(object, selector);
    RCQARemember(object, result);
    return result;
}
static void RCQAInstallCatalog(void) {
    static BOOL installed;
    if (installed) return;
    Class cls = NSClassFromString(@"SBIconView");
    SEL selector = NSSelectorFromString(@"applicationShortcutItems");
    Method method = class_getInstanceMethod(cls, selector);
    char *type = method ? method_copyReturnType(method) : NULL;
    BOOL valid = method && method_getNumberOfArguments(method)==2 && type && type[0]=='@';
    if (type) free(type);
    if (valid) {
        MSHookMessageEx(cls, selector, (IMP)RCQAObservedItems, (IMP *)&RCQAOriginalItems);
        installed = YES;
    }
}
static NSString *RCQACommand(NSString *command) {
    if ([command hasPrefix:@"quickactions list "]) {
        NSString *bundle = [command substringFromIndex:18];
        return RCQAJSON(@{@"items":RCQAItems(RCQACatalog[bundle] ?: RCQARestore(bundle))});
    }
    if ([command hasPrefix:@"quickactions run "]) return RCQARun([command substringFromIndex:17]);

    return @"Unknown Quick Shortcut command";
}
