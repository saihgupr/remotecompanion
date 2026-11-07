#import "RCAddOnCatalog.h"
#import "RCAddOnOptionsViewController.h"
#import <notify.h>
#import <JavaScriptCore/JavaScriptCore.h>

// Written by the tweak (Tweak/RCAddOns.m) each time the add-ons change, then the notification is
// posted. Only add-ons that passed the tweak's checks are in it, so the app offers exactly what runs.
static NSString *const kRCAddOnCatalogPath = @"/var/mobile/Documents/rc_addons.json";
static const char *kRCAddOnsChanged = "com.saihgupr.remotecompanion.addons-changed";

@implementation RCAddOnCatalog

// An icon that names an image file rather than an SF Symbol
+ (BOOL)iconIsImage:(NSString *)icon {
    return [@[@"png", @"jpg", @"jpeg"] containsObject:icon.pathExtension.lowercaseString];
}

// A symbol name this iOS has, else nil. Many symbols are newer than iOS 14 (the puzzle piece
// "puzzlepiece.extension" is iOS 15), and an unknown name shows no icon at all.
+ (NSString *)availableSymbol:(NSString *)name {
    if (![name isKindOfClass:[NSString class]] || !name.length || [self iconIsImage:name]) return nil;
    static NSMutableDictionary<NSString *, NSNumber *> *known;
    @synchronized ([RCAddOnCatalog class]) {
        if (!known) known = [NSMutableDictionary dictionary];
        if (!known[name]) known[name] = @([UIImage systemImageNamed:name] != nil);
        return known[name].boolValue ? name : nil;
    }
}

// The icon of an add-on (and of its actions, conditions and triggers) that has none of its own
+ (NSString *)defaultSymbol {
    return [self availableSymbol:@"puzzlepiece.extension"] ?: @"puzzlepiece";
}

// The add-on's own icon as an SF Symbol name; the puzzle piece when it has none, uses an image, or
// names a symbol this iOS doesn't have
+ (NSString *)iconForAddOn:(NSDictionary *)addOn {
    return [self availableSymbol:addOn[@"icon"]] ?: [self defaultSymbol];
}

// An icon string (an add-on's, action's, trigger's or condition's) as a list-row image: the image
// file it names (beside the add-on's JSON file, or an absolute path), 26 pt and rounded; nil when
// it is a symbol, empty, or the file is missing or over 512 KB
+ (UIImage *)imageForIcon:(NSString *)icon inAddOn:(NSDictionary *)addOn {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    if (![icon isKindOfClass:[NSString class]] || ![self iconIsImage:icon]) return nil;
    NSString *path = [icon hasPrefix:@"/"] ? icon : [(addOn[@"_folder"] ?: @"") stringByAppendingPathComponent:icon];
    UIImage *cached = [cache objectForKey:path];
    if (cached) return cached;
    NSData *data = [NSData dataWithContentsOfFile:path];
    UIImage *image = data.length && data.length <= 512 * 1024 ? [UIImage imageWithData:data] : nil;
    if (!image) return nil;
    CGSize size = CGSizeMake(26, 26);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *rounded = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:6] addClip];
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
    rounded = [rounded imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [cache setObject:rounded forKey:path];
    return rounded;
}

// The symbol for an icon string: itself, or the fallback when it is an image or empty
+ (NSString *)symbolForIcon:(NSString *)icon fallback:(NSString *)fallback {
    return [self availableSymbol:icon] ?: fallback;
}

// A thing's own icon, else the add-on's: the image to show (nil when it shows a symbol)
+ (UIImage *)imageForOwnIcon:(NSString *)icon inAddOn:(NSDictionary *)addOn {
    if ([icon isKindOfClass:[NSString class]] && icon.length) return [self imageForIcon:icon inAddOn:addOn];
    return [self imageForIcon:addOn[@"icon"] inAddOn:addOn];
}

// A thing's own icon, else the add-on's: the symbol to show
+ (NSString *)symbolForOwnIcon:(NSString *)icon inAddOn:(NSDictionary *)addOn {
    if ([icon isKindOfClass:[NSString class]] && icon.length) return [self symbolForIcon:icon fallback:[self iconForAddOn:addOn]];
    return [self iconForAddOn:addOn];
}

+ (UIImage *)iconImageForAddOn:(NSDictionary *)addOn {
    return [self imageForIcon:addOn[@"icon"] inAddOn:addOn];
}

+ (NSString *)iconForAddOnNamed:(NSString *)name {
    for (NSDictionary *addOn in [self addOns]) if ([addOn[@"name"] isEqualToString:name]) return [self iconForAddOn:addOn];
    return [self defaultSymbol];
}

+ (UIImage *)iconImageForAddOnNamed:(NSString *)name {
    for (NSDictionary *addOn in [self addOns]) if ([addOn[@"name"] isEqualToString:name]) return [self iconImageForAddOn:addOn];
    return nil;
}

// The catalog and everything built from it, rebuilt only after the tweak posts a change. Lists
// below are built once per change through +cached:build:.
+ (NSMutableDictionary *)cache {
    static NSMutableDictionary *cache;
    static int token = NOTIFY_TOKEN_INVALID;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ notify_register_check(kRCAddOnsChanged, &token); });
    @synchronized (self) {
        int changed = 1;
        if (token != NOTIFY_TOKEN_INVALID) notify_check(token, &changed);
        if (cache && !changed) return cache;
        NSData *data = [NSData dataWithContentsOfFile:kRCAddOnCatalogPath];
        NSDictionary *catalog = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *addOns = [catalog isKindOfClass:[NSDictionary class]] && [catalog[@"addons"] isKindOfClass:[NSArray class]] ? catalog[@"addons"] : @[];
        cache = [@{ @"addons": addOns } mutableCopy];
        if ([catalog isKindOfClass:[NSDictionary class]]) cache[@"catalog"] = catalog;
        return cache;
    }
}

+ (id)cached:(NSString *)name build:(id (^)(void))build {
    @synchronized (self) {
        NSMutableDictionary *cache = [self cache];
        id value = cache[name];
        if (!value) {
            value = build();
            cache[name] = value;
        }
        return value;
    }
}

// The valid, installed add-ons
+ (NSArray<NSDictionary *> *)addOns {
    return [self cache][@"addons"];
}

+ (BOOL)catalogAvailable {
    return [self cache][@"catalog"] != nil;
}

// The catalog's list under key, kept to the strings in it
+ (NSArray<NSString *> *)catalogStrings:(NSString *)key {
    NSArray *list = [self cache][@"catalog"][key];
    NSMutableArray *strings = [NSMutableArray array];
    if ([list isKindOfClass:[NSArray class]]) for (id item in list) if ([item isKindOfClass:[NSString class]]) [strings addObject:item];
    return strings;
}

// Installed, valid add-ons the user turned off (they offer nothing until turned on again)
+ (NSArray<NSDictionary *> *)disabledAddOns {
    NSArray *list = [self cache][@"catalog"][@"disabled"];
    return [list isKindOfClass:[NSArray class]] ? list : @[];
}

// An add-on by its id, on or off; nil when there's none
+ (NSDictionary *)addOnWithId:(NSString *)identifier {
    for (NSDictionary *addOn in [[self addOns] arrayByAddingObjectsFromArray:[self disabledAddOns]]) {
        if ([addOn isKindOfClass:[NSDictionary class]] && [addOn[@"id"] isEqual:identifier]) return addOn;
    }
    return nil;
}

+ (BOOL)isAddOnEnabled:(NSString *)identifier {
    for (NSDictionary *addOn in [self addOns]) if ([addOn[@"id"] isEqual:identifier]) return YES;
    return NO;
}

+ (NSArray<NSString *> *)absentAddOnNames {
    return [self catalogStrings:@"absent"];
}

+ (NSArray<NSString *> *)problems {
    return [self catalogStrings:@"problems"];
}

+ (const char *)changedNotification {
    return kRCAddOnsChanged;
}

#pragma mark - Reading commands (rc_addon_commands.js)

// The rules for reading an add-on command live in rc_addon_commands.js, which the Web UI uses too and
// tools/addon-lint-parity.py checks against the tweak, so the app keeps no copy of its own
+ (JSValue *)commandsScript {
    static JSContext *context;
    static JSValue *commands;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        context = [[JSContext alloc] init];
        for (NSString *path in @[@"/var/jb/Library/Application Support/RemoteCompanion/rc_addon_commands.js",
                                 @"/Library/Application Support/RemoteCompanion/rc_addon_commands.js"]) {
            NSString *script = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (!script) continue;
            [context evaluateScript:script withSourceURL:[NSURL fileURLWithPath:path]];
            break;
        }
        JSValue *value = context[@"RCAddOnCommands"];
        if (!value.isUndefined) commands = value;
        else NSLog(@"[RemoteCompanion] rc_addon_commands.js didn't load: add-on commands can't be read");
    });
    return commands;
}

+ (BOOL)commandsScriptLoaded {
    return [self commandsScript] != nil;
}

// An action as the JS value inside scriptAddOns (made once per catalog change), so reading a
// command doesn't copy the action into JavaScript again; a copy when it isn't one of the catalog's
+ (id)scriptAction:(NSDictionary *)action {
    NSArray *all = [self addOns];
    for (NSUInteger a = 0; a < all.count; a++) {
        NSArray *actions = [all[a][@"actions"] isKindOfClass:[NSArray class]] ? all[a][@"actions"] : @[];
        for (NSUInteger i = 0; i < actions.count; i++) {
            if (actions[i] == action) return [self scriptAddOns][a][@"actions"][i];
        }
    }
    return action;
}

// The catalog's add-ons as a JS value, made once per catalog change
+ (JSValue *)scriptAddOns {
    JSValue *commands = [self commandsScript];
    if (!commands) return nil;
    return [self cached:@"scriptAddOns" build:^id{ return [JSValue valueWithObject:[self addOns] inContext:commands.context]; }];
}

// The add-on and action a command runs, and the words after the action's own
+ (BOOL)match:(NSString *)command addOn:(NSDictionary **)addOnOut action:(NSDictionary **)actionOut rest:(NSArray<NSString *> **)restOut {
    if (![command isKindOfClass:[NSString class]]) return NO;
    @synchronized (self) {
        JSValue *addOns = [self scriptAddOns];
        if (!addOns) return NO;
        NSDictionary *found = [[[self commandsScript] invokeMethod:@"match" withArguments:@[addOns, command]] toDictionary];
        if (![found isKindOfClass:[NSDictionary class]] || !found[@"addOn"]) return NO;
        NSArray *all = [self addOns];
        NSUInteger a = [found[@"addOn"] unsignedIntegerValue], i = [found[@"action"] unsignedIntegerValue];
        if (a >= all.count || i >= [all[a][@"actions"] count]) return NO;
        if (addOnOut) *addOnOut = all[a];
        if (actionOut) *actionOut = all[a][@"actions"][i];
        if (restOut) *restOut = [found[@"rest"] isKindOfClass:[NSArray class]] ? found[@"rest"] : @[];
        return YES;
    }
}

+ (NSString *)titleForAddOn:(NSDictionary *)addOn action:(NSDictionary *)action {
    return [NSString stringWithFormat:@"%@: %@", addOn[@"name"], action[@"name"]];
}

+ (NSArray<NSDictionary *> *)pickerSections {
    return [self cached:@"pickerSections" build:^id{ return [self buildPickerSections]; }];
}

+ (NSArray<NSDictionary *> *)buildPickerSections {
    NSMutableArray *sections = [NSMutableArray array];
    for (NSDictionary *addOn in [self addOns]) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *action in addOn[@"actions"]) {
            if (![action isKindOfClass:[NSDictionary class]] || ![action[@"name"] isKindOfClass:[NSString class]]) continue;
            NSMutableDictionary *entry = [@{
                @"name": [self titleForAddOn:addOn action:action],
                @"command": [NSString stringWithFormat:@"%@ %@", addOn[@"id"], action[@"command"]],
                @"shortName": action[@"name"],
                @"icon": [self symbolForOwnIcon:action[@"icon"] inAddOn:addOn],
            } mutableCopy];
            // An image icon, the action's own or else the add-on's
            UIImage *image = [self imageForOwnIcon:action[@"icon"] inAddOn:addOn];
            if (image) entry[@"image"] = image;
            [items addObject:entry];
        }
        if (items.count) [sections addObject:@{ @"id": addOn[@"id"], @"title": addOn[@"name"], @"icon": [self iconForAddOn:addOn], @"image": [self iconImageForAddOn:addOn] ?: [NSNull null], @"actions": items }];
    }
    return sections;
}

+ (NSArray<NSDictionary *> *)addOnRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *section in [self pickerSections]) {
        NSArray *actions = section[@"actions"];
        [rows addObject:@{ @"name": section[@"title"], @"command": [@"__ADDON__" stringByAppendingString:section[@"id"]],
                           @"icon": section[@"icon"], @"image": section[@"image"], @"count": @(actions.count) }];
    }
    return rows;
}

+ (NSArray<NSDictionary *> *)actionsForAddOn:(NSString *)identifier {
    for (NSDictionary *section in [self pickerSections]) if ([section[@"id"] isEqualToString:identifier]) return section[@"actions"];
    return @[];
}

+ (NSArray<NSDictionary *> *)pickerActions {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *addOn in [self addOns]) {
        for (NSDictionary *action in addOn[@"actions"]) {
            if (![action isKindOfClass:[NSDictionary class]] || ![action[@"name"] isKindOfClass:[NSString class]]) continue;
            [items addObject:@{
                @"name": [self titleForAddOn:addOn action:action],
                @"command": [NSString stringWithFormat:@"%@ %@", addOn[@"id"], action[@"command"]],
                @"icon": [self symbolForOwnIcon:action[@"icon"] inAddOn:addOn],
            }];
        }
    }
    return items;
}

+ (NSString *)iconForCommand:(NSString *)command {
    NSDictionary *addOn = nil, *action = nil;
    if (![self match:command addOn:&addOn action:&action rest:NULL]) return nil;
    return [self symbolForOwnIcon:action[@"icon"] inAddOn:addOn];
}

+ (UIImage *)imageForCommand:(NSString *)command {
    NSDictionary *addOn = nil, *action = nil;
    if (![self match:command addOn:&addOn action:&action rest:NULL]) return nil;
    return [self imageForOwnIcon:action[@"icon"] inAddOn:addOn];
}

+ (NSString *)nameForCommand:(NSString *)command {
    NSDictionary *addOn = nil, *action = nil;
    return [self match:command addOn:&addOn action:&action rest:NULL] ? [self titleForAddOn:addOn action:action] : nil;
}

// The choice an option has in these words, or nil
+ (NSDictionary *)choiceForOption:(NSDictionary *)option inWords:(NSArray<NSString *> *)words {
    for (NSDictionary *choice in option[@"choices"]) {
        for (NSString *word in words) {
            if ([word.lowercaseString isEqualToString:[choice[@"word"] lowercaseString]]) return choice;
        }
    }
    return nil;
}

// The words after an action's own, as rc_addon_commands.js reads them (choices first, one per option;
// skipped options dropped; the input from the first other word or after "--").
// { "choices": { option id: choice }, "input": text (absent when there's none) }
+ (NSDictionary *)splitWords:(NSArray<NSString *> *)words action:(NSDictionary *)action {
    NSMutableDictionary *choices = [NSMutableDictionary dictionary];
    NSMutableDictionary *split = [@{ @"choices": choices } mutableCopy];
    @synchronized (self) {
        JSValue *commands = [self commandsScript];
        if (!commands || !action) return split;
        NSDictionary *read = [[commands invokeMethod:@"split" withArguments:@[[self scriptAction:action], words ?: @[]]] toDictionary];
        NSDictionary *words = [read[@"choices"] isKindOfClass:[NSDictionary class]] ? read[@"choices"] : @{};
        for (NSDictionary *option in action[@"options"] ?: @[]) {
            NSString *word = words[option[@"id"]];
            NSDictionary *choice = word ? [self choiceForOption:option inWords:@[word]] : nil;
            if (choice) choices[option[@"id"]] = choice;
        }
        if ([read[@"input"] isKindOfClass:[NSString class]]) split[@"input"] = read[@"input"];
    }
    return split;
}

+ (NSString *)inputInWords:(NSArray<NSString *> *)words action:(NSDictionary *)action {
    return [self splitWords:words action:action][@"input"];
}

+ (NSString *)wordsForInput:(NSString *)input action:(NSDictionary *)action {
    @synchronized (self) {
        JSValue *commands = [self commandsScript];
        if (!commands || !action) return nil;
        JSValue *text = [commands invokeMethod:@"inputWords" withArguments:@[[self scriptAction:action], input ?: @""]];
        return text.isString ? text.toString : nil;
    }
}

+ (NSString *)summaryForCommand:(NSString *)command {
    NSDictionary *action = nil;
    NSArray *rest = nil;
    if (![self match:command addOn:NULL action:&action rest:&rest] || rest.count == 0) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    NSDictionary *split = [self splitWords:rest action:action];
    for (NSDictionary *option in action[@"options"] ?: @[]) {
        NSDictionary *choice = split[@"choices"][option[@"id"]];
        if (choice) [parts addObject:choice[@"label"] ?: choice[@"word"]];
    }
    NSString *input = split[@"input"];
    if (input) [parts addObject:input];
    return parts.count ? [parts componentsJoinedByString:@" · "] : nil;
}

+ (BOOL)commandAsksForDetails:(NSString *)command {
    NSDictionary *action = nil;
    if (![self match:command addOn:NULL action:&action rest:NULL]) return NO;
    return [action[@"options"] count] > 0 || [action[@"input"] isKindOfClass:[NSDictionary class]];
}

+ (void)presentDetailsFrom:(UIViewController *)controller command:(NSString *)command current:(NSString *)current completion:(void (^)(NSString *))completion {
    NSDictionary *addOn = nil, *action = nil;
    if (![self match:command addOn:&addOn action:&action rest:NULL]) {
        completion(command);
        return;
    }
    NSString *base = [NSString stringWithFormat:@"%@ %@", addOn[@"id"], action[@"command"]];
    NSArray *currentRest = nil;
    [self match:current addOn:NULL action:NULL rest:&currentRest];
    RCAddOnOptionsViewController *screen = [[RCAddOnOptionsViewController alloc] initWithAction:action base:base current:currentRest ?: @[] editing:current != nil];
    screen.onDone = completion;
    // The action list stays open after Save; the picker closes itself once the action is added
    screen.popsWhenDone = [NSStringFromClass([controller class]) isEqualToString:@"RCActionsViewController"];
    if (controller.navigationController) {
        [controller.navigationController pushViewController:screen animated:YES];
    } else {
        [controller presentViewController:[[UINavigationController alloc] initWithRootViewController:screen] animated:YES completion:nil];
    }
}

+ (NSArray<NSDictionary *> *)bannerItems {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *addOn in [self addOns]) {
        for (NSDictionary *action in addOn[@"actions"]) {
            if (![action isKindOfClass:[NSDictionary class]] || ![action[@"banner"] isKindOfClass:[NSDictionary class]]) continue;
            [items addObject:@{
                @"id": [NSString stringWithFormat:@"%@ %@", addOn[@"id"], action[@"command"]],
                @"name": [self titleForAddOn:addOn action:action],
                @"icon": [self symbolForOwnIcon:action[@"icon"] inAddOn:addOn],
            }];
        }
    }
    return items;
}

+ (NSArray<NSDictionary *> *)triggerEvents {
    return [self cached:@"triggerEvents" build:^id{ return [self buildTriggerEvents]; }];
}

// Each trigger item by its key
+ (NSDictionary<NSString *, NSDictionary *> *)triggerEventsByKey {
    return [self cached:@"triggerEventsByKey" build:^id{
        NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
        for (NSDictionary *item in [self triggerEvents]) byKey[item[@"key"]] = item;
        return byKey;
    }];
}

+ (NSArray<NSDictionary *> *)buildTriggerEvents {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *addOn in [self addOns]) {
        for (NSDictionary *event in [addOn[@"events"] isKindOfClass:[NSArray class]] ? addOn[@"events"] : @[]) {
            NSDictionary *trigger = [event isKindOfClass:[NSDictionary class]] ? event[@"trigger"] : nil;
            if (![trigger isKindOfClass:[NSDictionary class]] || ![trigger[@"id"] isKindOfClass:[NSString class]] || ![trigger[@"name"] isKindOfClass:[NSString class]]) continue;
            NSString *key = [NSString stringWithFormat:@"addon_%@_%@", addOn[@"id"], trigger[@"id"]];
            NSString *icon = [self symbolForOwnIcon:trigger[@"icon"] inAddOn:addOn];
            UIImage *image = [self imageForOwnIcon:trigger[@"icon"] inAddOn:addOn];
            NSMutableDictionary *first = [@{ @"key": key, @"name": [NSString stringWithFormat:@"%@: %@", addOn[@"name"], trigger[@"name"]], @"icon": icon, @"section": addOn[@"name"] } mutableCopy];
            if (image) first[@"image"] = image;
            [items addObject:first];
            // The trigger's own states, else the banner's; "states": false offers none
            NSDictionary *states = @{};
            if ([trigger[@"states"] isKindOfClass:[NSDictionary class]]) states = trigger[@"states"];
            else if (![trigger[@"states"] isEqual:@NO] && [event[@"banner"] isKindOfClass:[NSDictionary class]] && [event[@"banner"][@"states"] isKindOfClass:[NSDictionary class]]) states = event[@"banner"][@"states"];
            for (NSString *state in [states.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [a compare:b options:NSNumericSearch]; }]) {
                NSMutableDictionary *perState = [@{ @"key": [NSString stringWithFormat:@"%@_%@", key, state],
                                                    @"name": [NSString stringWithFormat:@"%@: %@ (%@)", addOn[@"name"], trigger[@"name"], states[state]],
                                                    @"icon": icon, @"section": addOn[@"name"] } mutableCopy];
                if (image) perState[@"image"] = image;
                [items addObject:perState];
            }
        }
    }
    return items;
}

+ (BOOL)isAddOnTriggerKey:(NSString *)key {
    return [key hasPrefix:@"addon_"];
}

// A trigger key's name: the add-on's wording for it, or nil
+ (NSString *)nameForTriggerKey:(NSString *)key {
    return [self triggerEventsByKey][key][@"name"];
}

+ (NSArray<NSDictionary *> *)addOnTriggerGroups {
    return [self cached:@"addOnTriggerGroups" build:^id{ return [self buildAddOnTriggerGroups]; }];
}

+ (NSArray<NSDictionary *> *)buildAddOnTriggerGroups {
    NSMutableArray *groups = [NSMutableArray array];
    for (NSDictionary *addOn in [self addOns]) {
        NSMutableArray *triggers = [NSMutableArray array];
        for (NSDictionary *event in [addOn[@"events"] isKindOfClass:[NSArray class]] ? addOn[@"events"] : @[]) {
            NSDictionary *trigger = [event isKindOfClass:[NSDictionary class]] ? event[@"trigger"] : nil;
            if (![trigger isKindOfClass:[NSDictionary class]] || ![trigger[@"id"] isKindOfClass:[NSString class]] || ![trigger[@"name"] isKindOfClass:[NSString class]]) continue;
            NSString *key = [NSString stringWithFormat:@"addon_%@_%@", addOn[@"id"], trigger[@"id"]];
            NSDictionary *states = @{};
            if ([trigger[@"states"] isKindOfClass:[NSDictionary class]]) states = trigger[@"states"];
            else if (![trigger[@"states"] isEqual:@NO] && [event[@"banner"] isKindOfClass:[NSDictionary class]] && [event[@"banner"][@"states"] isKindOfClass:[NSDictionary class]]) states = event[@"banner"][@"states"];
            NSMutableArray *choices = [NSMutableArray array];
            for (NSString *state in [states.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [a compare:b options:NSNumericSearch]; }]) {
                [choices addObject:@{ @"key": [NSString stringWithFormat:@"%@_%@", key, state], @"label": states[state],
                                      @"name": [NSString stringWithFormat:@"%@: %@ (%@)", addOn[@"name"], trigger[@"name"], states[state]] }];
            }
            [triggers addObject:@{ @"key": key, @"title": trigger[@"name"], @"name": [NSString stringWithFormat:@"%@: %@", addOn[@"name"], trigger[@"name"]],
                                   @"states": choices }];
        }
        if (triggers.count) {
            [groups addObject:@{ @"id": addOn[@"id"], @"title": addOn[@"name"], @"icon": [self iconForAddOn:addOn],
                                 @"image": [self iconImageForAddOn:addOn] ?: [NSNull null], @"triggers": triggers }];
        }
    }
    return groups;
}

+ (UIImage *)imageForTriggerKey:(NSString *)key {
    return [self triggerEventsByKey][key][@"image"];
}

+ (NSString *)iconForTriggerKey:(NSString *)key {
    return [self triggerEventsByKey][key][@"icon"];
}

+ (NSArray<NSDictionary *> *)conditions {
    return [self cached:@"conditions" build:^id{ return [self buildConditions]; }];
}

+ (NSArray<NSDictionary *> *)buildConditions {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *addOn in [self addOns]) {
        NSArray *conditions = [addOn[@"conditions"] isKindOfClass:[NSArray class]] ? addOn[@"conditions"] : @[];
        for (NSDictionary *condition in conditions) {
            if (![condition isKindOfClass:[NSDictionary class]] || ![condition[@"id"] isKindOfClass:[NSString class]]) continue;
            NSDictionary *choiceMap = [condition[@"choices"] isKindOfClass:[NSDictionary class]] ? condition[@"choices"] : @{};
            NSArray *keys = [choiceMap.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
                return [a compare:b options:NSNumericSearch];
            }];
            NSMutableArray *labels = [NSMutableArray array];
            for (NSString *key in keys) [labels addObject:[choiceMap[key] description]];
            [items addObject:@{
                @"key": [NSString stringWithFormat:@"addon:%@:%@", addOn[@"id"], condition[@"id"]],
                @"name": [NSString stringWithFormat:@"%@: %@", addOn[@"name"], condition[@"name"]],
                @"type": [condition[@"type"] isEqual:@"number"] ? @"number" : @"choice",
                @"icon": [self symbolForOwnIcon:condition[@"icon"] inAddOn:addOn],
                @"image": [self imageForOwnIcon:condition[@"icon"] inAddOn:addOn] ?: [NSNull null],
                @"choices": labels,
            }];
        }
    }
    return items;
}

@end
