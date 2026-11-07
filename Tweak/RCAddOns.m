#import "RCAddOns.h"
#import "RCAddOnsBuiltins.h"
#import "RCToastPill.h"
#import <UIKit/UIKit.h>
#import <notify.h>
#import <poll.h>
#import <spawn.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <sys/wait.h>

// From Tweak.x
void SRLog(NSString *format, ...);
void SRLogMin(NSString *format, ...);
NSString *RCHandleCommand(NSString *cmd);
void RCShowBanner(NSString *title, NSString *subtitle, NSString *iconSymbol, NSTimeInterval hold);
void RCExecuteTrigger(NSString *triggerKey);
BOOL RCBannerEnabled(NSString *bannerId);
BOOL RCEvaluateIfCondition(NSDictionary *ifAction);
BOOL RCRunWait(double seconds);
BOOL RCRunStopped(void);

extern char **environ;

static const NSTimeInterval kRCAOExecTimeout = 10.0;
static const NSTimeInterval kRCAOMaxDelay = 5.0;
static const NSTimeInterval kRCAOSettle = 0.5;    // a change is read this long after the last event (dpkg writes several)
static const int kRCAOMaxDepth = 4;                // add-on commands running add-on commands
static const NSTimeInterval kRCAOMaxCache = 3600; // a condition's "cache", at most
static const int kRCAOAPIVersion = 1;              // the add-on API this build implements ("api" in a file)

// Guarded by rcao_lock()
static NSArray<NSDictionary *> *rcao_addOns;      // offered add-ons, as validated
static NSArray<NSString *> *rcao_problems;         // "file: reason"
static NSArray<NSString *> *rcao_absent;           // names of add-ons whose app or tweak isn't installed
static NSArray<NSDictionary *> *rcao_disabled;     // installed and valid, but turned off by the user
static NSString *rcao_signature;                   // the folder's files and modification times
static NSArray<NSString *> *rcao_files;            // the .json files found
static NSMutableArray<NSNumber *> *rcao_eventTokens;

// What loaded, for the app (RCAddOnCatalog reads it): {"api", "addons", "absent", "problems"}.
// Rewritten on each change, then kRCAOChanged is posted.
static NSString *const kRCAOCatalogPath = @"/var/mobile/Documents/rc_addons.json";
static const char *kRCAOChanged = "com.saihgupr.remotecompanion.addons-changed";

// Ids of the add-ons the user turned off (addons disable <id>): a JSON list, kept by the tweak
static NSString *const kRCAOOffPath = @"/var/mobile/Documents/rc_addons_off.json";

static NSArray<NSString *> *rcao_off_ids(void) {
    NSData *data = [NSData dataWithContentsOfFile:kRCAOOffPath];
    NSArray *ids = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![ids isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id x in ids) if ([x isKindOfClass:[NSString class]]) [out addObject:x];
    return out;
}

// Values read within a condition's "cache" seconds: key -> @[value or NSNull, time read]. Emptied
// when the add-ons reload. Guarded by rcao_cache_lock() (not rcao_lock: an exec runs while it's held).
static NSMutableDictionary<NSString *, NSArray *> *rcao_conditionCache;

static id rcao_cache_lock(void) {
    static id lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static id rcao_lock(void) {
    static id lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static dispatch_queue_t rcao_queue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.saihgupr.remotecompanion.addons", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static NSArray<NSString *> *rcao_folders(void) {
    return @[@"/var/jb/Library/RemoteCompanion/AddOns", @"/Library/RemoteCompanion/AddOns"];
}

#pragma mark - Templates

// {jbroot}: the jailbreak's root folder, /var/jb on rootless and empty on rootful, so one file can
// name "{jbroot}/usr/bin/tool" on both
static NSString *rcao_jbroot(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ root = access("/var/jb", F_OK) == 0 ? @"/var/jb" : @""; });
    return root;
}

static NSString *rcao_var(NSString *name, NSDictionary<NSString *, NSString *> *vars) {
    return vars[name] ?: ([name isEqualToString:@"jbroot"] ? rcao_jbroot() : nil);
}

// A whole text as a number (leading and trailing spaces allowed); NO when it isn't one
static BOOL rcao_number(NSString *text, double *number) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    double value = 0;
    if (![scanner scanDouble:&value] || !scanner.isAtEnd) return NO;
    if (number) *number = value;
    return YES;
}

// Whether {text} names a variable: a letter or _, then letters, digits, _, - and . Anything else in
// braces ({}, {print $1}, {"on":1}) is plain text and kept as written.
static BOOL rcao_is_var_name(NSString *name) {
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pattern = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z_][A-Za-z0-9_.-]*$" options:0 error:nil]; });
    return name.length && [pattern firstMatchInString:name options:0 range:NSMakeRange(0, name.length)] != nil;
}

// The variable names a template uses, in order (braces around anything else are plain text)
static NSArray<NSString *> *rcao_template_names(NSString *template) {
    NSMutableArray *names = [NSMutableArray array];
    if (![template isKindOfClass:[NSString class]]) return names;
    NSScanner *scanner = [NSScanner scannerWithString:template];
    scanner.charactersToBeSkipped = nil;
    while (!scanner.isAtEnd) {
        [scanner scanUpToString:@"{" intoString:NULL];
        if (scanner.isAtEnd) break;
        scanner.scanLocation += 1;
        NSString *name = nil;
        [scanner scanUpToString:@"}" intoString:&name];
        if (scanner.isAtEnd) break;
        scanner.scanLocation += 1;
        if (rcao_is_var_name(name)) [names addObject:name];
    }
    return names;
}

// Replaces each {name} with vars[name]. nil when a name has no value (the step is skipped). Braces
// around anything that isn't a variable name, and an unclosed {, are kept as written.
static NSString *rcao_fill(NSString *template, NSDictionary<NSString *, NSString *> *vars) {
    if (![template isKindOfClass:[NSString class]]) return nil;
    NSMutableString *out = [NSMutableString string];
    NSScanner *scanner = [NSScanner scannerWithString:template];
    scanner.charactersToBeSkipped = nil;
    while (!scanner.isAtEnd) {
        NSString *text = nil;
        if ([scanner scanUpToString:@"{" intoString:&text]) [out appendString:text];
        if (scanner.isAtEnd) break;
        scanner.scanLocation += 1;
        NSString *name = nil;
        [scanner scanUpToString:@"}" intoString:&name];
        if (scanner.isAtEnd) {
            [out appendFormat:@"{%@", name ?: @""];
            break;
        }
        scanner.scanLocation += 1;
        if (!rcao_is_var_name(name)) {
            [out appendFormat:@"{%@}", name ?: @""];
            continue;
        }
        NSString *value = rcao_var(name, vars);
        if (!value) return nil;
        [out appendString:value];
    }
    return out;
}

// An icon a banner can show: one the toast can draw (it looks symbols up itself, with any older
// stand-ins RemoteCompanion has for symbols this iOS lacks). An image file name gives nil.
static NSString *rcao_banner_symbol(NSString *icon) {
    if (![icon isKindOfClass:[NSString class]] || !icon.length) return nil;
    if ([@[@"png", @"jpg", @"jpeg"] containsObject:icon.pathExtension.lowercaseString]) return nil;
    static NSMutableDictionary<NSString *, NSNumber *> *known;
    @synchronized (rcao_cache_lock()) {
        if (!known) known = [NSMutableDictionary dictionary];
        if (!known[icon]) known[icon] = @([RCToastPillView hasIconForName:icon]);
        return known[icon].boolValue ? icon : nil;
    }
}

// The banner's icon: the first of the banner's, the action's and the add-on's that the toast can
// draw, so it matches the icon the app shows for the action; none of them gives no icon
static NSString *rcao_banner_icon(NSDictionary *banner, NSDictionary *action, NSDictionary *addOn) {
    return rcao_banner_symbol(banner[@"icon"]) ?: rcao_banner_symbol(action[@"icon"]) ?: rcao_banner_symbol(addOn[@"icon"]);
}

// Output as text: UTF-8, allowing a character cut at the end (the output limit); otherwise read
// byte by byte (Latin-1), so nothing is lost
static NSString *rcao_decode(NSData *data) {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    for (NSUInteger cut = 1; !text && cut <= 3 && cut < data.length; cut++) {
        text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, data.length - cut)] encoding:NSUTF8StringEncoding];
    }
    return text ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] ?: @"";
}

#pragma mark - Loading

static BOOL rcao_is_string(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0;
}

static BOOL rcao_word_list(NSString *text) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-. "];
    return text.length && [text rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound
        && ![text hasPrefix:@" "] && ![text hasSuffix:@" "] && [text rangeOfString:@"  "].location == NSNotFound;
}

// Why a step is invalid, or nil
static NSString *rcao_check_step(id step) {
    if (![step isKindOfClass:[NSDictionary class]]) return @"a step isn't an object";
    NSDictionary *s = step;
    NSArray *kinds = @[@"notify", @"defaults", @"exec", @"url", @"command", @"delay"];
    NSArray *modifiers = @[@"state", @"root", @"as", @"ifOptions", @"if", @"stopOnError"];
    NSString *kind = nil;
    for (NSString *key in s) {
        if ([kinds containsObject:key]) {
            if (kind) return [NSString stringWithFormat:@"a step has both %@ and %@", kind, key];
            kind = key;
        } else if (![modifiers containsObject:key]) {
            return [NSString stringWithFormat:@"unknown step key '%@'", key];
        }
    }
    if (!kind) return @"a step has no kind";
    // Kinds of the modifiers (a value of the wrong kind would throw when the step runs)
    for (NSString *flag in @[@"root", @"ifOptions", @"stopOnError"]) {
        if (s[flag] && ![s[flag] isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"%@ must be true or false", flag];
    }
    if (s[@"state"] && ![s[@"state"] isKindOfClass:[NSNumber class]]) return @"state must be a number";
    if ([s[@"if"] isKindOfClass:[NSDictionary class]] && s[@"if"][@"unset"] && ![s[@"if"][@"unset"] isKindOfClass:[NSNumber class]]) return @"if's unset must be true or false";
    if ([s[@"defaults"] isKindOfClass:[NSDictionary class]]) {
        for (NSString *flag in @[@"read", @"toggle"]) {
            if (s[@"defaults"][flag] && ![s[@"defaults"][flag] isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"defaults %@ must be true or false", flag];
        }
        if (s[@"defaults"][@"labels"] && ![s[@"defaults"][@"labels"] isKindOfClass:[NSDictionary class]]) return @"defaults labels must be an object";
        if (s[@"defaults"][@"type"] && ![@[@"string", @"bool", @"int"] containsObject:s[@"defaults"][@"type"]]) return @"defaults type must be string, bool or int";
    }
    if (s[@"if"] && (![s[@"if"] isKindOfClass:[NSDictionary class]] || !rcao_is_string(s[@"if"][@"var"]) ||
                     (!s[@"if"][@"is"] && !s[@"if"][@"isNot"] && ![s[@"if"][@"unset"] boolValue] && !s[@"if"][@"above"] && !s[@"if"][@"below"]))) {
        return @"if needs var and is, isNot, unset, above or below";
    }
    for (NSString *key in @[@"above", @"below"]) {
        id limit = [s[@"if"] isKindOfClass:[NSDictionary class]] ? s[@"if"][key] : nil;
        if (limit && ![limit isKindOfClass:[NSNumber class]] && !rcao_is_string(limit)) return [NSString stringWithFormat:@"if's %@ must be a number (or text that fills to one)", key];
    }
    if (s[@"state"] && ![kind isEqualToString:@"notify"]) return @"state only goes with notify";
    if (s[@"root"] && ![kind isEqualToString:@"exec"]) return @"root only goes with exec";
    if (s[@"stopOnError"] && ![kind isEqualToString:@"exec"] && ![kind isEqualToString:@"command"]) return @"stopOnError only goes with exec or command";
    if (s[@"as"] && (![kind isEqualToString:@"exec"] || !rcao_is_string(s[@"as"]))) return @"as (a name for the output) only goes with exec";
    for (id as in @[s[@"as"] ?: [NSNull null], [s[@"defaults"] isKindOfClass:[NSDictionary class]] ? (s[@"defaults"][@"as"] ?: [NSNull null]) : [NSNull null]]) {
        if (as != [NSNull null] && (![as isKindOfClass:[NSString class]] || !rcao_is_var_name(as))) return [NSString stringWithFormat:@"as '%@' must be a letter or _, then letters, digits, _, - and .", as];
    }
    for (NSString *reserved in @[@"jbroot", @"exit"]) {
        if ([s[@"as"] isEqual:reserved] || ([s[@"defaults"] isKindOfClass:[NSDictionary class]] && [s[@"defaults"][@"as"] isEqual:reserved])) {
            return [NSString stringWithFormat:@"as can't be %@ (that name is RemoteCompanion's)", reserved];
        }
    }
    id value = s[kind];
    if ([kind isEqualToString:@"exec"]) {
        if (![value isKindOfClass:[NSArray class]] || [value count] == 0) return @"exec needs a list";
        for (id arg in value) if (![arg isKindOfClass:[NSString class]]) return @"exec arguments must be strings";
        if (![[value firstObject] hasPrefix:@"/"] && ![[value firstObject] hasPrefix:@"{jbroot}/"]) return @"exec needs a full path (or one starting {jbroot}/)";
    } else if ([kind isEqualToString:@"defaults"]) {
        if (![value isKindOfClass:[NSDictionary class]] || !rcao_is_string(value[@"domain"]) || !rcao_is_string(value[@"key"])) return @"defaults needs domain and key";
        if ([value[@"read"] boolValue] && !rcao_is_string(value[@"as"])) return @"defaults read needs as";
        if (![value[@"toggle"] boolValue] && ![value[@"read"] boolValue] && !value[@"value"]) return @"defaults needs value, toggle or read";
    } else if ([kind isEqualToString:@"delay"]) {
        if (![value isKindOfClass:[NSNumber class]]) return @"delay needs a number";
    } else if (!rcao_is_string(value)) {
        return [NSString stringWithFormat:@"%@ needs text", kind];
    }
    return nil;
}

// A word of letters, digits, - and . (a choice's word, a trigger's id)
static BOOL rcao_is_word(id value) {
    if (!rcao_is_string(value)) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-."];
    return [(NSString *)value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

// An option id: lowercase letters, digits and _, starting with a letter; not a name the runtime fills in
static BOOL rcao_is_option_id(id value) {
    if (!rcao_is_string(value)) return NO;
    NSString *text = value;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
    if ([text rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return NO;
    if (![[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:[text characterAtIndex:0]]) return NO;
    if ([@[@"input", @"state", @"jbroot", @"exit"] containsObject:text]) return NO;
    if ([text hasPrefix:@"word"] && text.length > 4 && [[text substringFromIndex:4] rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet].invertedSet].location == NSNotFound) return NO;
    return YES;
}

// Why a banner is invalid, or nil
static NSString *rcao_check_banner(id banner, NSString *where) {
    if (![banner isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"%@: banner isn't an object", where];
    for (NSString *key in @[@"title", @"subtitle", @"icon", @"await", @"failed"]) {
        if (banner[key] && !rcao_is_string(banner[key])) return [NSString stringWithFormat:@"%@: banner %@ must be text", where, key];
    }
    for (NSString *key in @[@"hold", @"timeout"]) {
        if (banner[key] && ![banner[key] isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"%@: banner %@ must be a number", where, key];
    }
    if (banner[@"states"]) {
        if (![banner[@"states"] isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"%@: banner states must be an object", where];
        for (NSString *key in banner[@"states"]) if (![banner[@"states"][key] isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"%@: banner states must map to text", where];
    }
    return nil;
}

// Shorthands, written out before the checks: "banner": true is a banner with every default,
// "banner": false is none
static void rcao_normalize(NSMutableDictionary *addOn) {
    void (^fix)(id) = ^(id object) {
        if (![object isKindOfClass:[NSMutableDictionary class]]) return;
        id banner = object[@"banner"];
        if (banner && CFGetTypeID((__bridge CFTypeRef)banner) == CFBooleanGetTypeID()) {
            if ([banner boolValue]) object[@"banner"] = [NSMutableDictionary dictionary];
            else [object removeObjectForKey:@"banner"];
        }
    };
    for (id action in [addOn[@"actions"] isKindOfClass:[NSArray class]] ? addOn[@"actions"] : @[]) fix(action);
    for (id event in [addOn[@"events"] isKindOfClass:[NSArray class]] ? addOn[@"events"] : @[]) fix(event);
}

// A file's add-on, read and with its shorthands written out; nil (and *problem) when it isn't JSON
static NSMutableDictionary *rcao_read_file(NSString *path, NSString **problem) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) { if (problem) *problem = @"can't be read"; return nil; }
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (![json isKindOfClass:[NSMutableDictionary class]]) {
        if (problem) *problem = error ? [NSString stringWithFormat:@"not valid JSON (%@)", error.userInfo[@"NSDebugDescription"] ?: error.localizedDescription] : @"not a JSON object";
        return nil;
    }
    rcao_normalize(json);
    return json;
}

// The built-in command that takes "<id> <command>" before the add-on can (built-ins are tried first),
// or nil. *whole: it's a whole command, which takes the action only when nothing is added after it.
static NSString *rcao_builtin_taking(NSString *addOnId, NSString *command, BOOL *whole) {
    NSString *full = [NSString stringWithFormat:@"%@ %@", addOnId, command];
    NSString *spaced = [full stringByAppendingString:@" "];
    for (size_t i = 0; i < sizeof(kRCAOBuiltinPrefixes) / sizeof(kRCAOBuiltinPrefixes[0]); i++) {
        if ([spaced hasPrefix:kRCAOBuiltinPrefixes[i]]) {
            if (whole) *whole = NO;
            return [kRCAOBuiltinPrefixes[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }
    for (size_t i = 0; i < sizeof(kRCAOBuiltinCommands) / sizeof(kRCAOBuiltinCommands[0]); i++) {
        if ([full isEqualToString:kRCAOBuiltinCommands[i]]) {
            if (whole) *whole = YES;
            return kRCAOBuiltinCommands[i];
        }
    }
    return nil;
}

// Why an add-on's settings are invalid, or nil. A setting is a control on the add-on's page in the
// app, bound to one preference: { id, title, type: switch|choice|number|text, domain, key, default,
// note, notify, choices (choice: [{ value, label }]), min, max, step, unit (number) }.
static NSString *rcao_check_settings(id settings) {
    if (!settings) return nil;
    if (![settings isKindOfClass:[NSArray class]]) return @"settings must be a list";
    NSMutableSet *ids = [NSMutableSet set];
    for (NSDictionary *setting in settings) {
        if (![setting isKindOfClass:[NSDictionary class]]) return @"a setting isn't an object";
        if (!rcao_is_option_id(setting[@"id"])) return [NSString stringWithFormat:@"setting id '%@' must be lowercase letters, digits and _, starting with a letter", setting[@"id"]];
        NSString *sid = setting[@"id"];
        if ([ids containsObject:sid]) return [NSString stringWithFormat:@"two settings are '%@'", sid];
        [ids addObject:sid];
        if (!rcao_is_string(setting[@"title"])) return [NSString stringWithFormat:@"setting '%@' has no title", sid];
        NSString *type = setting[@"type"];
        if (![@[@"switch", @"choice", @"number", @"text"] containsObject:type ?: @""]) return [NSString stringWithFormat:@"setting '%@': type must be switch, choice, number or text", sid];
        if (!rcao_is_string(setting[@"domain"]) || !rcao_is_string(setting[@"key"])) return [NSString stringWithFormat:@"setting '%@' needs domain and key", sid];
        for (NSString *key in @[@"note", @"notify", @"unit"]) {
            if (setting[key] && !rcao_is_string(setting[key])) return [NSString stringWithFormat:@"setting '%@': %@ must be text", sid, key];
        }
        for (NSString *key in @[@"min", @"max", @"step"]) {
            if (setting[key] && ![setting[key] isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"setting '%@': %@ must be a number", sid, key];
        }
        id given = setting[@"default"];
        if ([type isEqualToString:@"switch"] && given && CFGetTypeID((__bridge CFTypeRef)given) != CFBooleanGetTypeID()) return [NSString stringWithFormat:@"setting '%@': a switch's default must be true or false", sid];
        if ([type isEqualToString:@"text"] && given && ![given isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"setting '%@': a text's default must be text", sid];
        if ([type isEqualToString:@"number"]) {
            if (given && ![given isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"setting '%@': a number's default must be a number", sid];
            if (setting[@"min"] && setting[@"max"] && [setting[@"min"] doubleValue] > [setting[@"max"] doubleValue]) return [NSString stringWithFormat:@"setting '%@': min is above max", sid];
            if (setting[@"step"] && [setting[@"step"] doubleValue] <= 0) return [NSString stringWithFormat:@"setting '%@': step must be above 0", sid];
        }
        if ([type isEqualToString:@"choice"]) {
            NSArray *choices = setting[@"choices"];
            if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) return [NSString stringWithFormat:@"setting '%@': a choice needs choices", sid];
            NSMutableSet *values = [NSMutableSet set];
            BOOL defaultFound = given == nil;
            for (NSDictionary *choice in choices) {
                if (![choice isKindOfClass:[NSDictionary class]] || !rcao_is_string(choice[@"label"]) ||
                    !([choice[@"value"] isKindOfClass:[NSString class]] || [choice[@"value"] isKindOfClass:[NSNumber class]])) {
                    return [NSString stringWithFormat:@"setting '%@': each choice needs a value (text or number) and a label", sid];
                }
                NSString *value = [choice[@"value"] description];
                if ([values containsObject:value]) return [NSString stringWithFormat:@"setting '%@': two choices have the value '%@'", sid, value];
                [values addObject:value];
                if ([value isEqualToString:[given description]]) defaultFound = YES;
            }
            if (!defaultFound) return [NSString stringWithFormat:@"setting '%@': the default isn't one of the choices' values", sid];
        }
    }
    return nil;
}

// Why an add-on is invalid, or nil
static NSString *rcao_check_addOn(NSDictionary *addOn) {
    NSString *pid = addOn[@"id"];
    if (!rcao_is_string(pid) || !rcao_word_list(pid) || [pid rangeOfString:@" "].location != NSNotFound || [pid containsString:@"."]) {
        return @"id must be lowercase letters, digits and -";
    }
    if ([pid isEqualToString:@"addons"]) return [NSString stringWithFormat:@"id '%@' is reserved", pid];
    if (addOn[@"api"]) {
        if (![addOn[@"api"] isKindOfClass:[NSNumber class]] || [addOn[@"api"] integerValue] < 1) return @"api must be a whole number from 1";
        if ([addOn[@"api"] integerValue] > kRCAOAPIVersion) return [NSString stringWithFormat:@"needs add-on API %@; this RemoteCompanion has %d", addOn[@"api"], kRCAOAPIVersion];
    }
    if (!rcao_is_string(addOn[@"name"])) return @"name is missing";
    if (addOn[@"icon"] && !rcao_is_string(addOn[@"icon"])) return @"icon must be text";
    if (addOn[@"requires"]) {
        if (![addOn[@"requires"] isKindOfClass:[NSArray class]]) return @"requires must be a list of paths";
        for (id path in addOn[@"requires"]) if (!rcao_is_string(path)) return @"requires must be a list of paths";
    }
    NSArray *actions = addOn[@"actions"];
    if (![actions isKindOfClass:[NSArray class]] || actions.count == 0) return @"actions are missing";
    NSMutableSet *commands = [NSMutableSet set];
    for (NSDictionary *action in actions) {
        if (![action isKindOfClass:[NSDictionary class]]) return @"an action isn't an object";
        NSString *command = action[@"command"];
        if (!rcao_is_string(command) || !rcao_word_list(command)) return @"an action's command must be lowercase words";
        if ([commands containsObject:command]) return [NSString stringWithFormat:@"two actions are '%@'", command];
        [commands addObject:command];
        // A built-in command that would always run instead (a whole one only matters when nothing can follow)
        BOOL whole = NO;
        NSString *taken = rcao_builtin_taking(pid, command, &whole);
        BOOL hasDetails = ([action[@"options"] isKindOfClass:[NSArray class]] && [action[@"options"] count]) || action[@"input"];
        if (taken && (!whole || !hasDetails)) return [NSString stringWithFormat:@"action '%@': '%@ %@' is taken by the built-in command '%@' and would never run (choose another id or command)", command, pid, command, taken];
        if (!rcao_is_string(action[@"name"])) return [NSString stringWithFormat:@"action '%@' has no name", command];
        if (action[@"icon"] && !rcao_is_string(action[@"icon"])) return [NSString stringWithFormat:@"action '%@': icon must be text", command];
        NSArray *run = action[@"run"];
        if (![run isKindOfClass:[NSArray class]] || run.count == 0) return [NSString stringWithFormat:@"action '%@' has no steps", command];
        for (id step in run) {
            NSString *problem = rcao_check_step(step);
            if (problem) return [NSString stringWithFormat:@"action '%@': %@", command, problem];
        }
        if (action[@"banner"]) {
            NSString *problem = rcao_check_banner(action[@"banner"], [NSString stringWithFormat:@"action '%@'", command]);
            if (problem) return problem;
        }
        if (action[@"input"]) {
            NSDictionary *input = action[@"input"];
            if (![input isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"action '%@': input isn't an object", command];
            for (NSString *key in @[@"title", @"placeholder"]) if (input[key] && ![input[key] isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"action '%@': input %@ must be text", command, key];
            if (input[@"number"] && ![input[@"number"] isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"action '%@': input number must be true or false", command];
        }
        NSMutableSet *optionIds = [NSMutableSet set], *words = [NSMutableSet set];
        NSArray *options = action[@"options"] ?: @[];
        if (![options isKindOfClass:[NSArray class]]) return [NSString stringWithFormat:@"action '%@': options must be a list", command];
        for (NSDictionary *option in options) {
            if (![option isKindOfClass:[NSDictionary class]] || ![option[@"choices"] isKindOfClass:[NSArray class]] || [option[@"choices"] count] == 0) {
                return [NSString stringWithFormat:@"action '%@' has an option without id or choices", command];
            }
            if (!rcao_is_option_id(option[@"id"])) return [NSString stringWithFormat:@"action '%@': option id '%@' must be lowercase letters, digits and _ (not input, state, jbroot, exit or wordN)", command, option[@"id"]];
            if ([optionIds containsObject:option[@"id"]]) return [NSString stringWithFormat:@"action '%@': two options are '%@'", command, option[@"id"]];
            if (option[@"title"] && ![option[@"title"] isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"action '%@': option '%@' title must be text", command, option[@"id"]];
            [optionIds addObject:option[@"id"]];
            for (NSDictionary *choice in option[@"choices"]) {
                if (![choice isKindOfClass:[NSDictionary class]] || !rcao_is_string(choice[@"word"])) {
                    return [NSString stringWithFormat:@"action '%@' has a choice without a word", command];
                }
                if (!rcao_is_word(choice[@"word"])) return [NSString stringWithFormat:@"action '%@': choice word '%@' must be one lowercase word", command, choice[@"word"]];
                if ([words containsObject:choice[@"word"]]) return [NSString stringWithFormat:@"action '%@': the word '%@' is used by two choices", command, choice[@"word"]];
                [words addObject:choice[@"word"]];
                if (choice[@"label"] && ![choice[@"label"] isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"action '%@': a choice's label must be text", command];
            }
        }
        for (NSDictionary *option in options) {
            NSDictionary *skipWhen = option[@"skipWhen"];
            if (!skipWhen) continue;
            if (![skipWhen isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"action '%@': skipWhen must be an object", command];
            for (NSString *other in skipWhen) {
                if (![optionIds containsObject:other] || [other isEqualToString:option[@"id"]]) return [NSString stringWithFormat:@"action '%@': skipWhen names '%@', which isn't another option", command, other];
            }
        }
    }
    // Lists (enumerating text or a number would throw)
    if (addOn[@"conditions"] && ![addOn[@"conditions"] isKindOfClass:[NSArray class]]) return @"conditions must be a list";
    if (addOn[@"events"] && ![addOn[@"events"] isKindOfClass:[NSArray class]]) return @"events must be a list";
    NSMutableSet *conditionIds = [NSMutableSet set];
    for (NSDictionary *condition in addOn[@"conditions"] ?: @[]) {
        if (![condition isKindOfClass:[NSDictionary class]] || !rcao_is_string(condition[@"id"]) || !rcao_is_string(condition[@"name"])) return @"a condition needs id and name";
        if ([conditionIds containsObject:condition[@"id"]]) return [NSString stringWithFormat:@"two conditions are '%@'", condition[@"id"]];
        [conditionIds addObject:condition[@"id"]];
        if (condition[@"root"] && ![condition[@"root"] isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"condition '%@': root must be true or false", condition[@"id"]];
        if (condition[@"icon"] && !rcao_is_string(condition[@"icon"])) return [NSString stringWithFormat:@"condition '%@': icon must be text", condition[@"id"]];
        if (![@[@"number", @"choice"] containsObject:condition[@"type"] ?: @""]) return [NSString stringWithFormat:@"condition '%@': type must be number or choice", condition[@"id"]];
        if (!condition[@"exec"] && !rcao_is_string(condition[@"notifyState"])) return [NSString stringWithFormat:@"condition '%@' needs exec or notifyState", condition[@"id"]];
        if (condition[@"exec"] && rcao_check_step(@{@"exec": condition[@"exec"]})) return [NSString stringWithFormat:@"condition '%@': exec needs a list starting with a full path", condition[@"id"]];
        for (NSString *arg in [condition[@"exec"] isKindOfClass:[NSArray class]] ? condition[@"exec"] : @[]) {
            for (NSString *name in rcao_template_names(arg)) if (![name isEqualToString:@"jbroot"]) return [NSString stringWithFormat:@"condition '%@': exec can only use {jbroot}", condition[@"id"]];
        }
        if (condition[@"cache"] && (![condition[@"cache"] isKindOfClass:[NSNumber class]] || [condition[@"cache"] doubleValue] < 0)) return [NSString stringWithFormat:@"condition '%@': cache must be a number of seconds", condition[@"id"]];
        if ([condition[@"type"] isEqualToString:@"choice"]) {
            NSDictionary *choices = condition[@"choices"];
            if (![choices isKindOfClass:[NSDictionary class]] || choices.count == 0) return [NSString stringWithFormat:@"condition '%@': a choice needs choices (value: label)", condition[@"id"]];
            for (NSString *key in choices) if (![choices[key] isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"condition '%@': choices must map to text", condition[@"id"]];
        }
    }
    NSMutableSet *triggerIds = [NSMutableSet set];
    for (NSDictionary *event in addOn[@"events"] ?: @[]) {
        if (![event isKindOfClass:[NSDictionary class]] || !rcao_is_string(event[@"notify"])) return @"an event needs notify";
        BOOL hasBanner = event[@"banner"] != nil;
        NSDictionary *trigger = event[@"trigger"];
        if (hasBanner) {
            NSString *problem = rcao_check_banner(event[@"banner"], [NSString stringWithFormat:@"event '%@'", event[@"notify"]]);
            if (problem) return problem;
        }
        if (trigger) {
            if (![trigger isKindOfClass:[NSDictionary class]] || !rcao_is_string(trigger[@"id"]) || !rcao_is_string(trigger[@"name"])) return @"an event's trigger needs id and name";
            if (trigger[@"icon"] && !rcao_is_string(trigger[@"icon"])) return @"a trigger's icon must be text";
            if (!rcao_is_word(trigger[@"id"])) return [NSString stringWithFormat:@"trigger id '%@' must be lowercase letters, digits, - and .", trigger[@"id"]];
            if ([triggerIds containsObject:trigger[@"id"]]) return [NSString stringWithFormat:@"two triggers are '%@'", trigger[@"id"]];
            [triggerIds addObject:trigger[@"id"]];
            id states = trigger[@"states"];
            if (states && ![states isEqual:@NO] && ![states isKindOfClass:[NSDictionary class]]) return @"a trigger's states must be an object or false";
        }
        if (!hasBanner && !trigger) return @"an event needs a banner or a trigger";
        if (event[@"action"] && (!rcao_is_string(event[@"action"]) || ![commands containsObject:event[@"action"]])) return [NSString stringWithFormat:@"event '%@': action '%@' isn't one of the actions", event[@"notify"], event[@"action"]];
    }
    return rcao_check_settings(addOn[@"settings"]);
}

// Keys that mean nothing here (ignored when loading, listed by "add-ons validate")
static NSArray<NSString *> *rcao_icons(NSDictionary *addOn);
static NSArray<NSString *> *rcao_warnings(NSDictionary *addOn, NSString *folder) {
    NSMutableArray *warnings = [NSMutableArray array];
    void (^check)(NSDictionary *, NSArray *, NSString *) = ^(NSDictionary *object, NSArray *known, NSString *where) {
        if (![object isKindOfClass:[NSDictionary class]]) return;
        for (NSString *key in object) if (![known containsObject:key]) [warnings addObject:[NSString stringWithFormat:@"%@: unknown key '%@' is ignored", where, key]];
    };
    check(addOn, @[@"$schema", @"api", @"id", @"name", @"icon", @"requires", @"actions", @"conditions", @"events", @"settings"], @"add-on");
    for (NSDictionary *setting in [addOn[@"settings"] isKindOfClass:[NSArray class]] ? addOn[@"settings"] : @[]) {
        NSString *where = [NSString stringWithFormat:@"setting '%@'", setting[@"id"]];
        check(setting, @[@"id", @"title", @"type", @"domain", @"key", @"default", @"note", @"notify", @"choices", @"min", @"max", @"step", @"unit"], where);
        for (NSDictionary *choice in [setting[@"choices"] isKindOfClass:[NSArray class]] ? setting[@"choices"] : @[]) check(choice, @[@"value", @"label"], [where stringByAppendingString:@" choice"]);
    }
    for (NSDictionary *action in addOn[@"actions"]) {
        NSString *where = [NSString stringWithFormat:@"action '%@'", action[@"command"]];
        check(action, @[@"command", @"name", @"icon", @"options", @"input", @"run", @"banner"], where);
        check(action[@"banner"], @[@"title", @"subtitle", @"icon", @"hold", @"await", @"states", @"timeout", @"failed"], [where stringByAppendingString:@" banner"]);
        check(action[@"input"], @[@"title", @"placeholder", @"number"], [where stringByAppendingString:@" input"]);
        for (NSDictionary *option in action[@"options"]) {
            check(option, @[@"id", @"title", @"choices", @"skipWhen"], [where stringByAppendingString:@" option"]);
            for (NSDictionary *choice in option[@"choices"]) check(choice, @[@"word", @"label", @"value"], [where stringByAppendingString:@" choice"]);
        }
    }
    for (NSDictionary *condition in addOn[@"conditions"]) check(condition, @[@"id", @"name", @"icon", @"type", @"exec", @"root", @"notifyState", @"choices", @"cache"], @"condition");
    for (NSDictionary *event in addOn[@"events"]) {
        check(event, @[@"notify", @"action", @"banner", @"trigger"], @"event");
        check(event[@"banner"], @[@"title", @"subtitle", @"icon", @"hold", @"states"], @"event banner");
        check(event[@"trigger"], @[@"id", @"name", @"icon", @"states"], @"event trigger");
    }
    // An exec path under /var/jb only exists on rootless: one warning per path, with how often it's used
    NSMutableArray<NSString *> *jbPaths = [NSMutableArray array];
    NSCountedSet<NSString *> *jbUses = [NSCountedSet set];
    void (^jbPath)(id) = ^(id exec) {
        NSString *path = [exec isKindOfClass:[NSArray class]] && [[exec firstObject] isKindOfClass:[NSString class]] ? [exec firstObject] : nil;
        if (![path hasPrefix:@"/var/jb/"]) return;
        if (![jbUses containsObject:path]) [jbPaths addObject:path];
        [jbUses addObject:path];
    };
    for (NSDictionary *action in addOn[@"actions"]) for (NSDictionary *step in action[@"run"]) jbPath(step[@"exec"]);
    for (NSDictionary *condition in addOn[@"conditions"]) jbPath(condition[@"exec"]);
    for (NSString *path in jbPaths) {
        NSUInteger uses = [jbUses countForObject:path];
        [warnings addObject:[NSString stringWithFormat:@"exec path %@ only works on rootless; write {jbroot}%@ (%lu place%@)", path, [path substringFromIndex:7], (unsigned long)uses, uses == 1 ? @"" : @"s"]];
    }
    for (NSDictionary *action in addOn[@"actions"]) {
        BOOL whole = NO;
        NSString *taken = rcao_builtin_taking(addOn[@"id"], action[@"command"], &whole);
        if (taken && whole) [warnings addObject:[NSString stringWithFormat:@"action '%@': with nothing after it, '%@' runs the built-in command instead", action[@"command"], taken]];
    }
    for (NSString *icon in rcao_icons(addOn)) {
        if (![@[@"png", @"jpg", @"jpeg"] containsObject:icon.pathExtension.lowercaseString]) continue;
        NSString *path = [icon hasPrefix:@"/"] ? icon : [folder stringByAppendingPathComponent:icon];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) [warnings addObject:[NSString stringWithFormat:@"icon: no image at %@", path]];
        else if (data.length > 512 * 1024) [warnings addObject:[NSString stringWithFormat:@"icon: %@ is over 512 KB and isn't used", icon]];
    }
    return warnings;
}

static BOOL rcao_installed(NSDictionary *addOn) {
    NSArray *paths = addOn[@"requires"];
    if (![paths isKindOfClass:[NSArray class]] || paths.count == 0) return YES;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *written in paths) {
        NSString *path = rcao_fill(written, @{});
        if (!path) continue;
        if ([fm fileExistsAtPath:path]) return YES;
        if (![path hasPrefix:@"/var/"] && [fm fileExistsAtPath:[@"/var/jb" stringByAppendingString:path]]) return YES;
    }
    return NO;
}

// The folders' .json files with their inode, size and change time: changes when one is added, removed,
// edited or replaced. (Not the modification time alone: dpkg sets that from the package, so an upgrade
// built in the same second as the old one would look the same.)
static NSString *rcao_folder_signature(NSArray<NSString *> **files) {
    NSMutableString *signature = [NSMutableString string];
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *folder in rcao_folders()) {
        NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *name in names) {
            if (![name.pathExtension isEqualToString:@"json"]) continue;
            NSString *path = [folder stringByAppendingPathComponent:name];
            struct stat st;
            if (stat(path.fileSystemRepresentation, &st) != 0) continue;
            [signature appendFormat:@"%@:%llu:%lld:%ld.%ld:%ld.%ld;", path, (unsigned long long)st.st_ino, (long long)st.st_size,
                (long)st.st_mtimespec.tv_sec, (long)st.st_mtimespec.tv_nsec, (long)st.st_ctimespec.tv_sec, (long)st.st_ctimespec.tv_nsec];
            [found addObject:path];
        }
    }
    if (files) *files = found;
    return signature;
}

static void rcao_register_events(NSArray<NSDictionary *> *addOns);

static void rcao_watch(void);

// Reads the folders again if a file was added, removed or changed (or always, when forced). The
// folders are watched (rcao_watch), so this runs on a change, not on a timer.
static void rcao_load(BOOL force) {
    @synchronized (rcao_lock()) {
        NSArray<NSString *> *files = nil;
        NSString *signature = rcao_folder_signature(&files);
        if (!force && rcao_addOns && [signature isEqualToString:rcao_signature]) return;
        rcao_signature = signature;
        rcao_files = files;
        @synchronized (rcao_cache_lock()) { [rcao_conditionCache removeAllObjects]; }

        NSMutableArray *addOns = [NSMutableArray array];
        NSMutableArray *problems = [NSMutableArray array];
        NSMutableArray *absent = [NSMutableArray array];
        NSMutableArray *disabled = [NSMutableArray array];
        NSSet *off = [NSSet setWithArray:rcao_off_ids()];
        NSMutableSet *ids = [NSMutableSet set];
        for (NSString *path in files) {
            NSString *problem = nil;
            NSMutableDictionary *json = rcao_read_file(path, &problem);
            if (json) problem = rcao_check_addOn(json);
            if (!problem && [ids containsObject:json[@"id"]]) problem = [NSString stringWithFormat:@"another add-on already uses id '%@'", json[@"id"]];
            if (problem) {
                [problems addObject:[NSString stringWithFormat:@"%@: %@", path.lastPathComponent, problem]];
                continue;
            }
            [ids addObject:json[@"id"]];
            NSMutableDictionary *loaded = json;
            loaded[@"_folder"] = path.stringByDeletingLastPathComponent;   // where the file is (its icon image sits beside it)
            loaded[@"_file"] = path.lastPathComponent;
            if (!rcao_installed(json)) [absent addObject:json[@"name"]];
            else if ([off containsObject:json[@"id"]]) [disabled addObject:loaded];   // offers nothing until turned on
            else [addOns addObject:loaded];
        }
        rcao_addOns = addOns;
        rcao_problems = problems;
        rcao_absent = absent;
        rcao_disabled = disabled;
        SRLog(@"[AddOns] Loaded %lu (%lu not installed, %lu with problems)", (unsigned long)addOns.count, (unsigned long)absent.count, (unsigned long)problems.count);
        for (NSString *problem in problems) SRLogMin(@"[AddOns] %@", problem);
        rcao_register_events(addOns);

        NSDictionary *catalog = @{ @"api": @(kRCAOAPIVersion), @"addons": addOns, @"disabled": disabled, @"absent": absent, @"problems": problems };
        NSData *data = [NSJSONSerialization dataWithJSONObject:catalog options:0 error:nil];
        if (![data writeToFile:kRCAOCatalogPath atomically:YES]) SRLogMin(@"[AddOns] Could not write %@", kRCAOCatalogPath);
        notify_post(kRCAOChanged);
    }
    // The file set may have changed: watch the new files
    dispatch_async(rcao_queue(), ^{ rcao_watch(); });
}

// The loaded add-ons. Read from disk only the first time; after that the folder watch keeps them current.
static NSArray<NSDictionary *> *rcao_current(void) {
    @synchronized (rcao_lock()) {
        if (!rcao_addOns) rcao_load(NO);
        return rcao_addOns;
    }
}

#pragma mark - Watching the folders

// Only touched on rcao_queue()
static NSMutableArray<dispatch_source_t> *rcao_watches;
static BOOL rcao_changePending;

static void rcao_changed(void) {
    if (rcao_changePending) return;
    rcao_changePending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRCAOSettle * NSEC_PER_SEC)), rcao_queue(), ^{
        rcao_changePending = NO;
        rcao_load(NO);
        rcao_watch();   // a folder may have been created or removed
    });
}

static void rcao_watch_path(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) return;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_LINK |
        DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE, rcao_queue());
    if (!source) {
        close(fd);
        return;
    }
    dispatch_source_set_event_handler(source, ^{ rcao_changed(); });
    dispatch_source_set_cancel_handler(source, ^{ close(fd); });
    dispatch_resume(source);
    [rcao_watches addObject:source];
}

// Watches each Add-ons folder (a file added, removed or renamed) and each add-on file in it (edited in
// place). A folder that doesn't exist yet is watched through the nearest folder above it, at most two
// up, so creating it is noticed. Runs on rcao_queue(); costs nothing until something changes.
static void rcao_watch(void) {
    for (dispatch_source_t source in rcao_watches) dispatch_source_cancel(source);
    rcao_watches = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableSet<NSString *> *watched = [NSMutableSet set];
    for (NSString *folder in rcao_folders()) {
        NSString *path = folder;
        for (int up = 0; up < 2 && ![fm fileExistsAtPath:path]; up++) path = path.stringByDeletingLastPathComponent;
        if ([watched containsObject:path] || ![fm fileExistsAtPath:path]) continue;
        [watched addObject:path];
        rcao_watch_path(path);
    }
    NSArray<NSString *> *files;
    @synchronized (rcao_lock()) { files = rcao_files; }
    for (NSString *file in files) rcao_watch_path(file);
}

#pragma mark - Running steps

// SpringBoard's environment with the jailbreak's tools on PATH (as RemoteCompanion's exec has)
static char **rcao_environment(void) {
    static char **env;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *vars = [NSMutableArray array];
        for (char **e = environ; *e; e++) {
            NSString *var = [NSString stringWithUTF8String:*e];
            if (var && ![var hasPrefix:@"PATH="]) [vars addObject:var];
        }
        [vars addObject:@"PATH=/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin"];
        env = calloc(vars.count + 1, sizeof(char *));
        for (NSUInteger i = 0; i < vars.count; i++) env[i] = strdup(vars[i].UTF8String);
    });
    return env;
}

static NSString *rcao_rc_root(void) {
    return access("/var/jb/usr/bin/rc-root", X_OK) == 0 ? @"/var/jb/usr/bin/rc-root" : @"/usr/bin/rc-root";
}

// Reads from a pipe into data (up to 64 KB kept): one read, or with drain all that's ready now.
// Closes it and sets *fd to -1 at its end.
static void rcao_read_pipe(int *fd, NSMutableData *data, BOOL drain) {
    char buffer[4096];
    while (*fd >= 0) {
        struct pollfd p = { .fd = *fd, .events = POLLIN };
        if (drain && poll(&p, 1, 0) <= 0) return;
        ssize_t n = read(*fd, buffer, sizeof(buffer));
        if (n <= 0) {
            close(*fd);
            *fd = -1;
            return;
        }
        if (data.length < 65536) [data appendBytes:buffer length:(NSUInteger)n];
        if (!drain) return;
    }
}

// Runs a program directly (no shell) and returns its output, or nil if it couldn't start. With
// errors, the output is stdout only and stderr goes to *errors; without, the two are one output. It
// runs in a process group of its own; after kRCAOExecTimeout the whole group (the program and anything
// it started) is stopped. A helper the program leaves running after it exits is left alone, even when
// it still holds the output open.
static NSString *rcao_exec(NSArray<NSString *> *arguments, BOOL root, int *exitStatus, NSString **errors) {
    // A root program goes through rc-root, which stops it (and what it started) at the time limit,
    // since SpringBoard can't; this side waits a little longer for that
    NSString *limit = [NSString stringWithFormat:@"%.0f", kRCAOExecTimeout];
    NSArray<NSString *> *argv = root ? [@[rcao_rc_root(), @"exec", @"--timeout", limit] arrayByAddingObjectsFromArray:arguments] : arguments;
    BOOL split = errors != NULL;
    int outPipe[2], errPipe[2] = { -1, -1 };
    if (pipe(outPipe) != 0) return nil;
    if (split && pipe(errPipe) != 0) {
        close(outPipe[0]);
        close(outPipe[1]);
        return nil;
    }
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1);
    posix_spawn_file_actions_adddup2(&actions, split ? errPipe[1] : outPipe[1], 2);
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);   // a new group, numbered like the program
    char **cargv = calloc(argv.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argv.count; i++) cargv[i] = (char *)argv[i].UTF8String;
    pid_t pid = 0;
    int err = posix_spawn(&pid, cargv[0], &actions, &attr, cargv, rcao_environment());
    free(cargv);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);
    close(outPipe[1]);
    if (split) close(errPipe[1]);
    if (err != 0) {
        close(outPipe[0]);
        if (split) close(errPipe[0]);
        SRLogMin(@"[AddOns] Could not run %@: %s", argv.firstObject, strerror(err));
        return nil;
    }
    // [0] stdout (or both), [1] stderr when split; -1 once closed
    int fds[2] = { outPipe[0], split ? errPipe[0] : -1 };
    NSMutableData *outData = [NSMutableData data], *errData = [NSMutableData data];
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + kRCAOExecTimeout + (root ? 2 : 0);
    BOOL exited = NO;
    int status = 0;
    // Read until the output closes; while it's quiet, check now and then whether the program has
    // exited (a helper it started may keep the output open)
    while (fds[0] >= 0 || fds[1] >= 0) {
        int left = (int)((deadline - CFAbsoluteTimeGetCurrent()) * 1000);
        if (left <= 0) break;
        struct pollfd p[2];
        int which[2], count = 0;
        for (int i = 0; i < 2; i++) if (fds[i] >= 0) { p[count] = (struct pollfd){ .fd = fds[i], .events = POLLIN }; which[count++] = i; }
        int ready = poll(p, count, MIN(left, 200));
        if (ready < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (ready == 0) {
            if (waitpid(pid, &status, WNOHANG) != pid) continue;
            exited = YES;
            rcao_read_pipe(&fds[0], outData, YES);   // whatever it wrote just before exiting
            rcao_read_pipe(&fds[1], errData, YES);
            break;
        }
        for (int k = 0; k < count; k++) if (p[k].revents) rcao_read_pipe(&fds[which[k]], which[k] ? errData : outData, NO);
    }
    for (int i = 0; i < 2; i++) if (fds[i] >= 0) close(fds[i]);
    // The output closed: wait for the program to exit, up to the same deadline
    while (!exited) {
        pid_t r = waitpid(pid, &status, WNOHANG);
        if (r == pid) { exited = YES; break; }
        if (r < 0 && errno != EINTR) break;
        if (CFAbsoluteTimeGetCurrent() >= deadline) break;
        usleep(20000);
    }
    if (!exited) {
        // Too long: stop the program and everything it started. A root program (rc-root) can't be
        // stopped by SpringBoard; it's reaped in the background whenever it ends.
        BOOL stopped = killpg(pid, SIGKILL) == 0 || kill(pid, SIGKILL) == 0;
        SRLogMin(@"[AddOns] %@ took longer than %.0f s and %@", arguments.firstObject, kRCAOExecTimeout,
                 stopped ? @"was stopped" : @"couldn't be stopped (it runs as root)");
        if (stopped) {
            waitpid(pid, &status, 0);
        } else {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                int ignored = 0;
                waitpid(pid, &ignored, 0);
            });
        }
        if (exitStatus) *exitStatus = -1;
    } else if (exitStatus) {
        *exitStatus = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    }
    if (errors) *errors = rcao_decode(errData);
    return rcao_decode(outData);
}

static id rcao_typed(NSString *value, NSString *type) {
    if ([type isEqualToString:@"bool"]) {
        NSString *v = value.lowercaseString;
        // A real boolean (@(a || b) would box the int that || gives, and write 1 or 0)
        BOOL on = [v isEqualToString:@"1"] || [v isEqualToString:@"true"] || [v isEqualToString:@"yes"] || [v isEqualToString:@"on"];
        return [NSNumber numberWithBool:on];
    }
    if ([type isEqualToString:@"int"]) return @(value.integerValue);
    return value;
}

// A boolean's label: labels {"true": ..., "false": ...}, default On/Off
static NSString *rcao_bool_label(NSDictionary *spec, BOOL value) {
    NSDictionary *labels = [spec[@"labels"] isKindOfClass:[NSDictionary class]] ? spec[@"labels"] : nil;
    NSString *label = labels[value ? @"true" : @"false"];
    return [label isKindOfClass:[NSString class]] ? label : (value ? @"On" : @"Off");
}

// read: saves the value in vars[as] (a boolean as its label). A toggle with "as" saves its new value.
#pragma mark - Settings

static id rcao_pref_read(NSString *domain, NSString *key) {
    if ([domain isEqualToString:@"com.apple.springboard"]) return [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain));
}

static void rcao_pref_write(NSString *domain, NSString *key, id value) {
    if ([domain isEqualToString:@"com.apple.springboard"]) {
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
        return;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}

// A setting's current value, as JSON can carry it: a boolean, number or text (the default, or the
// first choice / min / false / "", when the preference isn't set)
static id rcao_setting_value(NSDictionary *setting) {
    id value = rcao_pref_read(setting[@"domain"], setting[@"key"]);
    NSString *type = setting[@"type"];
    if ([type isEqualToString:@"switch"]) {
        if (!value) value = setting[@"default"] ?: @NO;
        return [value respondsToSelector:@selector(boolValue)] ? @([value boolValue]) : @NO;
    }
    if ([type isEqualToString:@"number"]) {
        if (!value) value = setting[@"default"] ?: setting[@"min"] ?: @0;
        double number = 0;
        if ([value isKindOfClass:[NSNumber class]]) return value;
        if (rcao_number([value description], &number)) return @(number);
        return setting[@"default"] ?: setting[@"min"] ?: @0;
    }
    if ([type isEqualToString:@"choice"]) {
        NSArray *choices = setting[@"choices"];
        for (NSDictionary *choice in choices) if (value && [[choice[@"value"] description] isEqualToString:[value description]]) return choice[@"value"];
        return setting[@"default"] ?: [choices.firstObject objectForKey:@"value"];
    }
    return [value isKindOfClass:[NSString class]] ? value : (value ? [value description] : setting[@"default"] ?: @"");
}

// Writes a setting from text (what a command carries); nil, or why it can't
static NSString *rcao_setting_write(NSDictionary *setting, NSString *text) {
    NSString *type = setting[@"type"];
    id value = nil;
    if ([type isEqualToString:@"switch"]) {
        NSString *v = text.lowercaseString;
        if ([@[@"1", @"true", @"yes", @"on"] containsObject:v]) value = @YES;
        else if ([@[@"0", @"false", @"no", @"off"] containsObject:v]) value = @NO;
        else return @"a switch takes on or off";
    } else if ([type isEqualToString:@"number"]) {
        double number = 0;
        if (!rcao_number(text, &number)) return @"that isn't a number";
        if (setting[@"min"] && number < [setting[@"min"] doubleValue]) return [NSString stringWithFormat:@"the lowest is %@", setting[@"min"]];
        if (setting[@"max"] && number > [setting[@"max"] doubleValue]) return [NSString stringWithFormat:@"the highest is %@", setting[@"max"]];
        // Whole numbers are written as whole numbers (what a tweak's integerForKey: expects)
        value = number == floor(number) && fabs(number) < 1e15 ? @((long long)number) : @(number);
    } else if ([type isEqualToString:@"choice"]) {
        for (NSDictionary *choice in setting[@"choices"]) {
            if ([[choice[@"value"] description] isEqualToString:text] || [[choice[@"label"] lowercaseString] isEqualToString:text.lowercaseString]) value = choice[@"value"];
        }
        if (!value) return @"that isn't one of its choices";
    } else {
        value = text;
    }
    rcao_pref_write(setting[@"domain"], setting[@"key"], value);
    if (rcao_is_string(setting[@"notify"])) notify_post([setting[@"notify"] UTF8String]);
    return nil;
}

static void rcao_write_default(NSDictionary *spec, NSMutableDictionary *vars) {
    NSString *domain = spec[@"domain"], *key = spec[@"key"];
    BOOL springboard = [domain isEqualToString:@"com.apple.springboard"];
    NSUserDefaults *standard = [NSUserDefaults standardUserDefaults];
    if ([spec[@"read"] boolValue]) {
        id value = springboard ? [standard objectForKey:key]
                               : CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain));
        if (!value || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) vars[spec[@"as"]] = rcao_bool_label(spec, [value boolValue]);
        else vars[spec[@"as"]] = [value description];
        return;
    }
    if ([spec[@"toggle"] boolValue]) {
        BOOL current = springboard ? [standard boolForKey:key]
                                   : CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain, NULL);
        if (springboard) [standard setBool:!current forKey:key];
        else CFPreferencesSetAppValue((__bridge CFStringRef)key, current ? kCFBooleanFalse : kCFBooleanTrue, (__bridge CFStringRef)domain);
        if (rcao_is_string(spec[@"as"])) vars[spec[@"as"]] = rcao_bool_label(spec, !current);
    } else {
        id raw = spec[@"value"];
        NSString *text = [raw isKindOfClass:[NSString class]] ? rcao_fill(raw, vars) : [raw description];
        id value = [raw isKindOfClass:[NSNumber class]] && !spec[@"type"] ? raw : rcao_typed(text, spec[@"type"]);
        if (springboard) [standard setObject:value forKey:key];
        else CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)domain);
    }
    if (!springboard) CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}

// The first variable a step uses that has no value (an option left as Keep Current skips the step), or nil
static NSString *rcao_step_missing(NSDictionary *step, NSDictionary *vars) {
    NSMutableArray *templates = [NSMutableArray array];
    for (NSString *key in @[@"notify", @"url", @"command"]) if (step[key]) [templates addObject:step[key]];
    for (NSString *arg in step[@"exec"] ?: @[]) [templates addObject:arg];
    id value = step[@"defaults"][@"value"];
    if ([value isKindOfClass:[NSString class]]) [templates addObject:value];
    for (NSString *template in templates) {
        for (NSString *name in rcao_template_names(template)) if (!rcao_var(name, vars)) return name;
    }
    return nil;
}

// A step in a few words, for a trace: its kind and what it names, filled in where it can be
static NSString *rcao_step_text(NSDictionary *step, NSDictionary *vars) {
    NSString *(^filled)(NSString *) = ^NSString *(NSString *t) { return rcao_fill(t, vars) ?: t; };
    if (step[@"notify"]) return [NSString stringWithFormat:@"notify %@%@", filled(step[@"notify"]), step[@"state"] ? [NSString stringWithFormat:@" (state %@)", step[@"state"]] : @""];
    if (step[@"exec"]) {
        NSMutableArray *args = [NSMutableArray array];
        for (NSString *arg in step[@"exec"]) [args addObject:filled(arg)];
        return [NSString stringWithFormat:@"exec%@ %@", [step[@"root"] boolValue] ? @" (root)" : @"", [args componentsJoinedByString:@" "]];
    }
    if (step[@"defaults"]) {
        NSDictionary *d = step[@"defaults"];
        NSString *what = [d[@"read"] boolValue] ? @"read" : [d[@"toggle"] boolValue] ? @"toggle" : [NSString stringWithFormat:@"= %@", [d[@"value"] isKindOfClass:[NSString class]] ? filled(d[@"value"]) : d[@"value"]];
        return [NSString stringWithFormat:@"defaults %@ %@ %@", d[@"domain"], d[@"key"], what];
    }
    if (step[@"url"]) return [@"url " stringByAppendingString:filled(step[@"url"])];
    if (step[@"command"]) return [@"command " stringByAppendingString:filled(step[@"command"])];
    if (step[@"delay"]) return [NSString stringWithFormat:@"delay %@ s", step[@"delay"]];
    return @"?";
}

// Output as one short line for a trace
static NSString *rcao_trace_output(NSString *text) {
    NSString *line = [[[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                       componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" / "];
    return line.length > 160 ? [[line substringToIndex:160] stringByAppendingString:@"…"] : line;
}

// Runs the steps; with a trace, adds a line per step saying what it did or why it was skipped
// *failed: a step with stopOnError failed, and the steps after it didn't run
static NSString *rcao_run_steps(NSArray<NSDictionary *> *steps, NSMutableDictionary *vars, BOOL optionsChosen, NSMutableArray<NSString *> *trace, BOOL *failed) {
    NSMutableString *output = [NSMutableString string];
    NSUInteger number = 0;
    for (NSDictionary *step in steps) {
        number++;
        void (^note)(NSString *) = ^(NSString *what) {
            if (trace) [trace addObject:[NSString stringWithFormat:@"%lu. %@ -> %@", (unsigned long)number, rcao_step_text(step, vars), what]];
        };
        // The trigger run this action is part of was stopped (Stop, or a Restart firing)
        if (RCRunStopped()) {
            note(@"not run: the trigger run was stopped");
            break;
        }
        if ([step[@"ifOptions"] boolValue] && !optionsChosen) {
            note(@"skipped: ifOptions, and no option was chosen");
            continue;
        }
        NSDictionary *condition = step[@"if"];
        if (condition) {
            NSString *value = vars[condition[@"var"]];
            NSString *shown = value ? [NSString stringWithFormat:@"'%@'", value] : @"unset";
            if ([condition[@"unset"] boolValue] && value) {
                note([NSString stringWithFormat:@"skipped: if %@ unset, but it is %@", condition[@"var"], shown]);
                continue;
            }
            if (condition[@"is"] && ![value isEqualToString:[condition[@"is"] description]]) {
                note([NSString stringWithFormat:@"skipped: if %@ is '%@', but it is %@", condition[@"var"], condition[@"is"], shown]);
                continue;
            }
            if (condition[@"isNot"] && [value isEqualToString:[condition[@"isNot"] description]]) {
                note([NSString stringWithFormat:@"skipped: if %@ isn't '%@', but it is", condition[@"var"], condition[@"isNot"]]);
                continue;
            }
            // above / below: compared as numbers; a value that isn't a number (or no value) skips the step
            BOOL compared = YES;
            for (NSString *key in @[@"above", @"below"]) {
                id written = condition[key];
                if (!written || !compared) continue;
                NSString *limitText = [written isKindOfClass:[NSString class]] ? rcao_fill(written, vars) : [written description];
                double number = 0, limit = 0;
                if (!rcao_number(limitText, &limit)) {
                    note([NSString stringWithFormat:@"skipped: if %@ %@ '%@', which isn't a number", condition[@"var"], key, limitText ?: written]);
                    compared = NO;
                } else if (!rcao_number(value, &number)) {
                    note([NSString stringWithFormat:@"skipped: if %@ %@ %@, but it is %@, not a number", condition[@"var"], key, limitText, shown]);
                    compared = NO;
                } else if ([key isEqualToString:@"above"] ? !(number > limit) : !(number < limit)) {
                    note([NSString stringWithFormat:@"skipped: if %@ %@ %@, but it is %@", condition[@"var"], key, limitText, value]);
                    compared = NO;
                }
            }
            if (!compared) continue;
        }
        NSString *missing = rcao_step_missing(step, vars);
        if (missing) {
            note([NSString stringWithFormat:@"skipped: {%@} has no value", missing]);
            continue;
        }
        if (step[@"notify"]) {
            NSString *name = rcao_fill(step[@"notify"], vars);
            if (step[@"state"]) {
                // The state lasts only while someone is registered for the name, so the
                // registration is kept (one per name)
                static NSMutableDictionary<NSString *, NSNumber *> *tokens;
                @synchronized (rcao_lock()) {
                    if (!tokens) tokens = [NSMutableDictionary dictionary];
                    int token = tokens[name].intValue;
                    if (!tokens[name] && notify_register_check(name.UTF8String, &token) == NOTIFY_STATUS_OK) tokens[name] = @(token);
                    if (tokens[name]) notify_set_state(token, [step[@"state"] unsignedLongLongValue]);
                }
            }
            notify_post(name.UTF8String);
            note(@"posted");
        } else if (step[@"defaults"]) {
            rcao_write_default(step[@"defaults"], vars);
            NSString *as = step[@"defaults"][@"as"];
            note(rcao_is_string(as) && vars[as] ? [NSString stringWithFormat:@"done, {%@} = '%@'", as, vars[as]] : @"done");
        } else if (step[@"exec"]) {
            NSMutableArray *args = [NSMutableArray array];
            for (NSString *arg in step[@"exec"]) [args addObject:rcao_fill(arg, vars)];
            int status = 0;
            CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
            // With "as", the variable gets stdout only: a warning on stderr doesn't end up in it
            BOOL keep = rcao_is_string(step[@"as"]);
            NSString *errors = nil;
            NSString *result = rcao_exec(args, [step[@"root"] boolValue], &status, keep ? &errors : NULL);
            if (!result) status = -1;
            vars[@"exit"] = [NSString stringWithFormat:@"%d", status];   // for the steps after it and the banner
            if (trace) {
                NSString *how = !result ? @"couldn't start" : status == -1 ? @"stopped or killed" : [NSString stringWithFormat:@"exit %d", status];
                NSString *what = [NSString stringWithFormat:@"%@, %.2f s", how, CFAbsoluteTimeGetCurrent() - started];
                if (result.length) what = [what stringByAppendingFormat:@", output: %@", rcao_trace_output(result)];
                if (errors.length) what = [what stringByAppendingFormat:@", stderr: %@", rcao_trace_output(errors)];
                note(what);
            }
            if (!result) {
                [output appendFormat:@"Error: Could not run %@\n", args.firstObject];
            } else if (rcao_is_string(step[@"as"])) {
                // Kept as a variable for the steps after it and the banner (lines joined), not added to the reply
                NSMutableArray *lines = [NSMutableArray array];
                for (NSString *line in [result componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
                    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (trimmed.length) [lines addObject:trimmed];
                }
                if (lines.count) vars[step[@"as"]] = [lines componentsJoinedByString:@" · "];
                if (trace) [trace addObject:[NSString stringWithFormat:@"   {%@} = %@", step[@"as"], vars[step[@"as"]] ? [NSString stringWithFormat:@"'%@'", vars[step[@"as"]]] : @"unset (no output)"]];
            } else {
                [output appendString:result];
            }
            if (status != 0 && [step[@"stopOnError"] boolValue]) {
                if (result) [output appendFormat:@"Error: %@ %@\n", args.firstObject, status == -1 ? @"was stopped" : [NSString stringWithFormat:@"exited with %d", status]];
                if (trace) [trace addObject:@"   stopOnError: the action stops here"];
                if (failed) *failed = YES;
                break;
            }
        } else if (step[@"url"]) {
            NSURL *url = [NSURL URLWithString:rcao_fill(step[@"url"], vars)];
            if (url) dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            });
            note(url ? @"opened" : @"not a URL");
        } else if (step[@"command"]) {
            NSString *result = RCHandleCommand(rcao_fill(step[@"command"], vars));
            if (result.length) [output appendString:result];
            // No reply at all (nil) means no command took it; an empty reply is a command that said nothing
            note(result.length ? [@"reply: " stringByAppendingString:rcao_trace_output(result)] : result ? @"done, no reply" : @"not a command");
            // A command fails when it isn't one, or its reply starts with "Error"
            if ([step[@"stopOnError"] boolValue] && (!result || [result hasPrefix:@"Error"])) {
                if (!result) [output appendFormat:@"Error: %@ isn't a command\n", rcao_fill(step[@"command"], vars)];
                if (trace) [trace addObject:@"   stopOnError: the action stops here"];
                if (failed) *failed = YES;
                break;
            }
        } else if (step[@"delay"]) {
            double seconds = MIN(MAX([step[@"delay"] doubleValue], 0), kRCAOMaxDelay);
            if (!RCRunWait(seconds)) {   // stopped while waiting
                note(@"cut short: the trigger run was stopped");
                break;
            }
            note([NSString stringWithFormat:@"waited %.1f s", seconds]);
        }
    }
    return output;
}

#pragma mark - Banners

// The text for a notification's state: states[state] when there's a map, else the number.
// nil when the map has no entry (no banner).
static NSString *rcao_state_text(NSDictionary *banner, uint64_t state) {
    NSDictionary *states = banner[@"states"];
    NSString *key = [NSString stringWithFormat:@"%llu", state];
    if ([states isKindOfClass:[NSDictionary class]]) return [states[key] isKindOfClass:[NSString class]] ? states[key] : nil;
    return key;
}

static void rcao_show_state_banner(NSDictionary *banner, NSString *title, NSString *icon, uint64_t state, NSDictionary *vars) {
    NSString *text = rcao_state_text(banner, state);
    if (!text) return;
    NSMutableDictionary *withState = [vars mutableCopy] ?: [NSMutableDictionary dictionary];
    withState[@"state"] = text;
    NSString *subtitle = banner[@"subtitle"] ? rcao_fill(banner[@"subtitle"], withState) : text;
    if (subtitle) RCShowBanner(title, subtitle, icon, [banner[@"hold"] doubleValue] ?: 2.0);
}

// Waits for the notification in banner.await and shows the text for its state, or nothing
// after the timeout. Armed before the steps run, so a quick reply isn't missed.
// Returns a block that stops waiting (nil when nothing was armed)
static dispatch_block_t rcao_await_banner(NSDictionary *banner, NSString *title, NSString *icon, NSDictionary *vars) {
    NSString *name = rcao_fill(banner[@"await"], vars);
    if (!name) return nil;
    double timeout = MIN(MAX([banner[@"timeout"] doubleValue] ?: 8.0, 1.0), 30.0);
    dispatch_queue_t queue = rcao_queue();
    __block int token = NOTIFY_TOKEN_INVALID;
    __block BOOL finished = NO;
    if (notify_register_dispatch(name.UTF8String, &token, queue, ^(int t) {
        if (finished) return;
        finished = YES;
        uint64_t state = 0;
        notify_get_state(t, &state);
        notify_cancel(t);
        rcao_show_state_banner(banner, title, icon, state, vars);
    }) != NOTIFY_STATUS_OK) return nil;
    dispatch_block_t stop = ^{
        if (finished) return;
        finished = YES;
        notify_cancel(token);
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), queue, stop);
    return ^{ dispatch_async(queue, stop); };
}

static NSString *rcao_banner_id(NSDictionary *addOn, NSString *command) {
    return [NSString stringWithFormat:@"%@ %@", addOn[@"id"], command];
}

static NSDictionary *rcao_action_named(NSDictionary *addOn, NSString *command) {
    for (NSDictionary *action in addOn[@"actions"]) if ([action[@"command"] isEqualToString:command]) return action;
    return nil;
}

// Banners for notifications an add-on's tweak posts by itself
static void rcao_register_events(NSArray<NSDictionary *> *addOns) {
    if (!rcao_eventTokens) rcao_eventTokens = [NSMutableArray array];
    for (NSNumber *token in rcao_eventTokens) notify_cancel(token.intValue);
    [rcao_eventTokens removeAllObjects];
    for (NSDictionary *addOn in addOns) {
        for (NSDictionary *event in addOn[@"events"] ?: @[]) {
            NSDictionary *banner = [event[@"banner"] isKindOfClass:[NSDictionary class]] ? event[@"banner"] : nil;
            NSDictionary *trigger = event[@"trigger"];
            // The trigger's key (RCAddOnCatalog builds the same ones): any state, and each state
            NSString *triggerKey = trigger ? [NSString stringWithFormat:@"addon_%@_%@", addOn[@"id"], trigger[@"id"]] : nil;
            NSString *actionCommand = event[@"action"];
            NSDictionary *action = rcao_is_string(actionCommand) ? rcao_action_named(addOn, actionCommand) : nil;
            NSString *title = banner[@"title"] ?: addOn[@"name"];
            NSString *icon = rcao_banner_icon(banner, action, addOn);
            int token = NOTIFY_TOKEN_INVALID;
            notify_register_dispatch([event[@"notify"] UTF8String], &token, rcao_queue(), ^(int t) {
                uint64_t state = 0;
                notify_get_state(t, &state);
                if (triggerKey) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        RCExecuteTrigger(triggerKey);
                        RCExecuteTrigger([NSString stringWithFormat:@"%@_%llu", triggerKey, state]);
                    });
                }
                // An event tied to an action shares that action's switch in Settings > Banners
                if (!banner || (action && !RCBannerEnabled(rcao_banner_id(addOn, actionCommand)))) return;
                rcao_show_state_banner(banner, title, icon, state, @{});
            });
            if (token != NOTIFY_TOKEN_INVALID) [rcao_eventTokens addObject:@(token)];
        }
    }
}

#pragma mark - Commands

static NSString *rcao_usage(NSDictionary *addOn) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"%@:\n", addOn[@"name"]];
    for (NSDictionary *action in addOn[@"actions"]) {
        NSMutableString *line = [NSMutableString stringWithFormat:@"%@ %@", addOn[@"id"], action[@"command"]];
        for (NSDictionary *option in action[@"options"] ?: @[]) {
            NSMutableArray *words = [NSMutableArray array];
            for (NSDictionary *choice in option[@"choices"]) [words addObject:choice[@"word"]];
            [line appendFormat:@" [%@]", [words componentsJoinedByString:@"|"]];
        }
        if (action[@"input"]) [line appendFormat:@" <%@>", action[@"input"][@"title"] ?: @"text"];
        [out appendFormat:@"  %@\n", line];
    }
    return out;
}

static NSString *rcao_list(void) {
    NSArray *addOns, *problems, *absent, *disabled;
    @synchronized (rcao_lock()) {
        addOns = rcao_addOns;
        problems = rcao_problems;
        absent = rcao_absent;
        disabled = rcao_disabled;
    }
    NSMutableString *out = [NSMutableString string];
    if (addOns.count == 0 && absent.count == 0 && problems.count == 0 && disabled.count == 0) return @"No add-ons\n";
    for (NSDictionary *addOn in addOns) {
        [out appendFormat:@"%@ (%@): %lu action%@\n", addOn[@"name"], addOn[@"id"], (unsigned long)[addOn[@"actions"] count], [addOn[@"actions"] count] == 1 ? @"" : @"s"];
    }
    for (NSDictionary *addOn in disabled) [out appendFormat:@"%@ (%@): off\n", addOn[@"name"], addOn[@"id"]];
    for (NSString *name in absent) [out appendFormat:@"%@: not installed\n", name];
    for (NSString *problem in problems) [out appendFormat:@"Problem: %@\n", problem];
    return out;
}

// The choice a word picks, and its option (*option), or nil
static NSDictionary *rcao_choice_for_word(NSDictionary *action, NSString *word, NSDictionary **optionOut) {
    for (NSDictionary *option in action[@"options"] ?: @[]) {
        for (NSDictionary *choice in option[@"choices"]) {
            if ([[choice[@"word"] lowercaseString] isEqualToString:word.lowercaseString]) {
                if (optionOut) *optionOut = option;
                return choice;
            }
        }
    }
    return nil;
}

// The words after an action's own, read as rc_addon_commands.js reads them for the app and the Web UI:
// choice words first, at most one per option; the input starts at the first other word, or after "--"
// (*inputStart: its index). An option that another option's choice skips (skipWhen) is dropped, as
// the app hides it (*skipped: their ids). Returns { option id: choice }.
static NSDictionary<NSString *, NSDictionary *> *rcao_split_words(NSDictionary *action, NSArray<NSString *> *words, NSUInteger *inputStart, NSArray<NSString *> **skippedOut) {
    NSMutableDictionary<NSString *, NSDictionary *> *chosen = [NSMutableDictionary dictionary];
    NSUInteger next = 0;
    for (; next < words.count; next++) {
        if ([words[next] isEqualToString:@"--"]) {
            next++;
            break;
        }
        NSDictionary *option = nil;
        NSDictionary *choice = rcao_choice_for_word(action, words[next], &option);
        if (!choice || chosen[option[@"id"]]) break;
        chosen[option[@"id"]] = choice;
    }
    NSMutableArray<NSString *> *skipped = [NSMutableArray array];
    for (NSDictionary *option in action[@"options"] ?: @[]) {
        NSDictionary *skipWhen = option[@"skipWhen"];
        if (!chosen[option[@"id"]] || ![skipWhen isKindOfClass:[NSDictionary class]]) continue;
        for (NSString *other in skipWhen) {
            if ([[chosen[other][@"word"] lowercaseString] isEqualToString:[[skipWhen[other] description] lowercaseString]]) {
                [skipped addObject:option[@"id"]];
                break;
            }
        }
    }
    [chosen removeObjectsForKeys:skipped];
    if (inputStart) *inputStart = next;
    if (skippedOut) *skippedOut = skipped;
    return chosen;
}

static NSString *rcao_run_action(NSDictionary *addOn, NSDictionary *action, NSArray<NSString *> *words, NSMutableArray<NSString *> *trace) {
    NSMutableDictionary<NSString *, NSString *> *vars = [NSMutableDictionary dictionary];
    BOOL optionsChosen = NO;
    // Choice words come first, at most one per option. The input starts at the first word that
    // isn't one, or after "--" (the app writes that when the input itself starts with a choice word),
    // so typed text that happens to contain "on" or "off" stays text.
    NSUInteger next = 0;
    NSArray<NSString *> *skipped = nil;
    NSDictionary<NSString *, NSDictionary *> *chosen = rcao_split_words(action, words, &next, &skipped);
    for (NSString *optionId in chosen) {
        vars[optionId] = [(chosen[optionId][@"value"] ?: chosen[optionId][@"word"]) description];
        optionsChosen = YES;
    }
    NSArray<NSString *> *rest = [words subarrayWithRange:NSMakeRange(next, words.count - next)];
    for (NSUInteger i = 0; i < rest.count; i++) vars[[NSString stringWithFormat:@"word%lu", (unsigned long)i + 1]] = rest[i];
    if (rest.count) vars[@"input"] = [rest componentsJoinedByString:@" "];

    NSDictionary *banner = [action[@"banner"] isKindOfClass:[NSDictionary class]] ? action[@"banner"] : nil;
    BOOL showBanner = banner && RCBannerEnabled(rcao_banner_id(addOn, action[@"command"]));
    NSString *title = banner[@"title"] ?: addOn[@"name"];
    NSString *icon = rcao_banner_icon(banner, action, addOn);
    dispatch_block_t stopAwaiting = showBanner && banner[@"await"] ? rcao_await_banner(banner, title, icon, vars) : nil;

    SRLog(@"[AddOns] %@ %@ %@", addOn[@"id"], action[@"command"], vars);
    if (trace) {
        [trace addObject:[NSString stringWithFormat:@"%@: %@ (%@ %@)", addOn[@"name"], action[@"name"], addOn[@"id"], action[@"command"]]];
        NSMutableArray *pairs = [NSMutableArray array];
        for (NSString *name in [vars.allKeys sortedArrayUsingSelector:@selector(compare:)]) [pairs addObject:[NSString stringWithFormat:@"%@='%@'", name, vars[name]]];
        [pairs addObject:[NSString stringWithFormat:@"jbroot='%@'", rcao_jbroot()]];
        [trace addObject:[@"Variables: " stringByAppendingString:[pairs componentsJoinedByString:@", "]]];
        for (NSDictionary *option in action[@"options"] ?: @[]) {
            if ([skipped containsObject:option[@"id"]]) [trace addObject:[NSString stringWithFormat:@"Option %@: ignored (skipWhen: another option's choice hides it)", option[@"id"]]];
            else if (!vars[option[@"id"]]) [trace addObject:[NSString stringWithFormat:@"Option %@: Keep Current (no value)", option[@"id"]]];
        }
    }
    BOOL failed = NO;
    NSString *output = rcao_run_steps(action[@"run"], vars, optionsChosen, trace, &failed);
    if (failed) {
        // A step with stopOnError failed: the banner says so (its "failed" text), and an awaited
        // reply is no longer waited for
        if (stopAwaiting) stopAwaiting();
        if (showBanner) {
            NSString *text = banner[@"failed"] ? rcao_fill(banner[@"failed"], vars) : nil;
            NSString *filledTitle = banner[@"title"] && !banner[@"await"] ? rcao_fill(banner[@"title"], vars) : nil;
            RCShowBanner(filledTitle ?: title, text ?: @"Failed", @"exclamationmark.triangle", [banner[@"hold"] doubleValue] ?: 2.0);
            if (trace) [trace addObject:[NSString stringWithFormat:@"Banner: %@ / %@ (failed)", filledTitle ?: title, text ?: @"Failed"]];
        } else if (trace) {
            [trace addObject:banner ? @"Banner: off in Settings > Banners" : @"Banner: none"];
        }
        return [output hasSuffix:@"\n"] ? output : [output stringByAppendingString:@"\n"];
    }
    if (trace) {
        if (!banner) [trace addObject:@"Banner: none"];
        else if (!showBanner) [trace addObject:@"Banner: off in Settings > Banners"];
        else if (banner[@"await"]) [trace addObject:[NSString stringWithFormat:@"Banner: waiting up to %.0f s for %@", MIN(MAX([banner[@"timeout"] doubleValue] ?: 8.0, 1.0), 30.0), rcao_fill(banner[@"await"], vars) ?: banner[@"await"]]];
    }

    if (showBanner && !banner[@"await"]) {
        NSString *subtitle = banner[@"subtitle"] ? rcao_fill(banner[@"subtitle"], vars) : nil;
        // The title can use variables too (an unset one falls back to the add-on's name)
        NSString *filledTitle = banner[@"title"] ? rcao_fill(banner[@"title"], vars) : nil;
        RCShowBanner(filledTitle ?: title, subtitle ?: action[@"name"], icon, [banner[@"hold"] doubleValue] ?: 2.0);
        if (trace) [trace addObject:[NSString stringWithFormat:@"Banner: %@ / %@", filledTitle ?: title, subtitle ?: action[@"name"]]];
    }
    if (output.length) return [output hasSuffix:@"\n"] ? output : [output stringByAppendingString:@"\n"];
    return [NSString stringWithFormat:@"%@: %@\n", addOn[@"name"], action[@"name"]];
}

static NSArray<NSString *> *rcao_words(NSString *cmd) {
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *w in [cmd componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if (w.length) [words addObject:w];
    }
    return words;
}

// The action whose command words follow the add-on id (the longest one); *length: its word count
static NSDictionary *rcao_match_action(NSDictionary *addOn, NSArray<NSString *> *words, NSUInteger *length) {
    NSDictionary *match = nil;
    NSUInteger matchLength = 0;
    for (NSDictionary *action in addOn[@"actions"]) {
        NSArray *commandWords = [action[@"command"] componentsSeparatedByString:@" "];
        if (commandWords.count > words.count - 1 || commandWords.count <= matchLength) continue;
        BOOL same = YES;
        for (NSUInteger i = 0; i < commandWords.count && same; i++) same = [words[i + 1].lowercaseString isEqualToString:commandWords[i]];
        if (same) { match = action; matchLength = commandWords.count; }
    }
    if (length) *length = matchLength;
    return match;
}

static NSDictionary *rcao_addOn_for(NSArray<NSString *> *words) {
    if (words.count == 0) return nil;
    for (NSDictionary *p in rcao_current()) if ([p[@"id"] isEqualToString:words[0].lowercaseString]) return p;
    return nil;
}

static NSString *rcao_dispatch(NSDictionary *addOn, NSArray<NSString *> *words, NSMutableArray<NSString *> *trace);

BOOL RCAddOnsCommandShowsOwnBanner(NSString *cmd) {
    NSArray<NSString *> *words = rcao_words(cmd);
    NSDictionary *addOn = rcao_addOn_for(words);
    NSDictionary *action = addOn ? rcao_match_action(addOn, words, NULL) : nil;
    return [action[@"banner"] isKindOfClass:[NSDictionary class]];
}

NSString *RCAddOnsHandleCommand(NSString *cmd) {
    NSArray<NSString *> *words = rcao_words(cmd);
    if (words.count == 0) return nil;
    NSString *first = words[0].lowercaseString;

    if ([first isEqualToString:@"addons"]) {
        if (words.count == 2 && [words[1].lowercaseString isEqualToString:@"reload"]) {
            rcao_load(YES);
            return rcao_list();
        }
        if (words.count == 1) {
            rcao_load(NO);
            return rcao_list();
        }
        // "addons settings <id>": its settings' current values, as JSON ({"<setting id>": value})
        // "addons set <id> <setting> <value>": changes one (the value is the rest of the command; a
        // text setting can be set to nothing by leaving it out)
        if ((words.count == 3 && [words[1].lowercaseString isEqualToString:@"settings"]) ||
            (words.count >= 4 && [words[1].lowercaseString isEqualToString:@"set"])) {
            NSString *addOnId = words[2].lowercaseString;
            NSDictionary *addOn = nil;
            @synchronized (rcao_lock()) {
                for (NSDictionary *a in [rcao_addOns arrayByAddingObjectsFromArray:rcao_disabled ?: @[]]) if ([a[@"id"] isEqualToString:addOnId]) addOn = a;
            }
            if (!addOn) return [NSString stringWithFormat:@"Error: No add-on '%@' (see addons)\n", addOnId];
            NSArray *settings = [addOn[@"settings"] isKindOfClass:[NSArray class]] ? addOn[@"settings"] : @[];
            if ([words[1].lowercaseString isEqualToString:@"set"]) {
                NSDictionary *setting = nil;
                for (NSDictionary *s in settings) if ([s[@"id"] isEqualToString:words[3].lowercaseString]) setting = s;
                if (!setting) return [NSString stringWithFormat:@"Error: %@ has no setting '%@'\n", addOn[@"name"], words[3]];
                // The value as typed (text can have spaces and capitals): everything after the setting id
                NSRange at = [cmd rangeOfString:words[3] options:0 range:NSMakeRange(NSMaxRange([cmd rangeOfString:words[2]]), cmd.length - NSMaxRange([cmd rangeOfString:words[2]]))];
                NSString *text = [[cmd substringFromIndex:NSMaxRange(at)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSString *problem = rcao_setting_write(setting, text);
                if (problem) return [NSString stringWithFormat:@"Error: %@: %@\n", setting[@"title"], problem];
                // The new value as the page shows it: On/Off, a choice's label, a number with its unit
                id now = rcao_setting_value(setting);
                NSString *shown = [now description];
                if ([setting[@"type"] isEqualToString:@"switch"]) shown = [now boolValue] ? @"On" : @"Off";
                if ([setting[@"type"] isEqualToString:@"choice"]) for (NSDictionary *c in setting[@"choices"]) if ([[c[@"value"] description] isEqualToString:shown]) shown = c[@"label"];
                if ([setting[@"type"] isEqualToString:@"number"] && rcao_is_string(setting[@"unit"])) shown = [NSString stringWithFormat:@"%@ %@", shown, setting[@"unit"]];
                return [NSString stringWithFormat:@"%@: %@ is %@\n", addOn[@"name"], setting[@"title"], shown];
            }
            NSMutableDictionary *values = [NSMutableDictionary dictionary];
            for (NSDictionary *s in settings) values[s[@"id"]] = rcao_setting_value(s);
            NSData *json = [NSJSONSerialization dataWithJSONObject:values options:NSJSONWritingSortedKeys error:nil];
            return [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] stringByAppendingString:@"\n"];
        }
        // "addons enable <id>" / "addons disable <id>": turns an add-on on or off. Off, it offers no
        // actions, conditions or triggers and its events stop, without uninstalling it.
        if (words.count == 3 && ([words[1].lowercaseString isEqualToString:@"enable"] || [words[1].lowercaseString isEqualToString:@"disable"])) {
            NSString *addOnId = words[2].lowercaseString;
            BOOL enable = [words[1].lowercaseString isEqualToString:@"enable"];
            BOOL known = NO;
            @synchronized (rcao_lock()) {
                for (NSDictionary *addOn in [rcao_addOns arrayByAddingObjectsFromArray:rcao_disabled ?: @[]]) if ([addOn[@"id"] isEqualToString:addOnId]) known = YES;
            }
            if (!known) return [NSString stringWithFormat:@"Error: No add-on '%@' (see addons)\n", addOnId];
            NSMutableArray *off = [rcao_off_ids() mutableCopy];
            [off removeObject:addOnId];
            if (!enable) [off addObject:addOnId];
            NSData *data = [NSJSONSerialization dataWithJSONObject:off options:0 error:nil];
            if (![data writeToFile:kRCAOOffPath atomically:YES]) return [NSString stringWithFormat:@"Error: Could not write %@\n", kRCAOOffPath];
            rcao_load(YES);
            return [NSString stringWithFormat:@"%@ is %@\n", addOnId, enable ? @"on" : @"off"];
        }
        // "add-ons check add-on:<id>:<condition> [expected]": the value, and whether it matches
        if (words.count >= 3 && [words[1].lowercaseString isEqualToString:@"check"]) {
            BOOL isNumber = NO;
            NSString *value = RCAddOnsConditionValue(words[2], &isNumber);
            if (!value) return @"Error: No such condition, or no value\n";
            if (words.count == 3) return [NSString stringWithFormat:@"%@\n", value];
            NSString *expected = [[words subarrayWithRange:NSMakeRange(3, words.count - 3)] componentsJoinedByString:@" "];
            BOOL matches = RCEvaluateIfCondition(@{ @"conditionKey": words[2], @"expectedValue": expected });
            return [NSString stringWithFormat:@"%@ (%@ %@)\n", value, matches ? @"matches" : @"doesn't match", expected];
        }
        // "add-ons validate <file>": whether a file is a valid add-on, with warnings
        if (words.count >= 3 && [words[1].lowercaseString isEqualToString:@"validate"]) {
            // The path is everything after "validate" (it can have spaces), from the command as typed
            NSRange at = [cmd rangeOfString:words[1]];
            NSString *path = [[cmd substringFromIndex:NSMaxRange(at)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *problem = nil;
            NSMutableDictionary *json = rcao_read_file(path, &problem);
            if (!json) return [NSString stringWithFormat:@"Problem: %@\n", problem];
            problem = rcao_check_addOn(json);
            if (problem) return [NSString stringWithFormat:@"Problem: %@\n", problem];
            NSMutableString *out = [NSMutableString stringWithFormat:@"OK: %@ (%@), %lu action%@\n", json[@"name"], json[@"id"], (unsigned long)[json[@"actions"] count], [json[@"actions"] count] == 1 ? @"" : @"s"];
            for (NSString *warning in rcao_warnings(json, [path stringByDeletingLastPathComponent])) [out appendFormat:@"Warning: %@\n", warning];
            return out;
        }
        // "addons parse <add-on command>": how the command reads, as JSON, without running it
        // ({"addon", "action", "choices": {option id: word}, "input"}); the parity check compares it
        // with rc_addon_commands.js
        if (words.count >= 3 && [words[1].lowercaseString isEqualToString:@"parse"]) {
            NSArray *command = [words subarrayWithRange:NSMakeRange(2, words.count - 2)];
            NSDictionary *addOn = rcao_addOn_for(command);
            NSUInteger matchLength = 0;
            NSDictionary *match = addOn ? rcao_match_action(addOn, command, &matchLength) : nil;
            NSMutableDictionary *parsed = [NSMutableDictionary dictionary];
            if (match) {
                NSArray *rest = [command subarrayWithRange:NSMakeRange(1 + matchLength, command.count - 1 - matchLength)];
                NSUInteger next = 0;
                NSDictionary *chosen = rcao_split_words(match, rest, &next, NULL);
                NSMutableDictionary *choices = [NSMutableDictionary dictionary];
                for (NSString *optionId in chosen) choices[optionId] = chosen[optionId][@"word"];
                parsed[@"addon"] = addOn[@"id"];
                parsed[@"action"] = match[@"command"];
                parsed[@"choices"] = choices;
                if (next < rest.count) parsed[@"input"] = [[rest subarrayWithRange:NSMakeRange(next, rest.count - next)] componentsJoinedByString:@" "];
            }
            NSData *json = [NSJSONSerialization dataWithJSONObject:parsed options:NSJSONWritingSortedKeys error:nil];
            return [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] stringByAppendingString:@"\n"];
        }
        // "addons trace <add-on command>": runs it, and says what each step did or why it was skipped
        if (words.count >= 3 && [words[1].lowercaseString isEqualToString:@"trace"]) {
            NSArray *command = [words subarrayWithRange:NSMakeRange(2, words.count - 2)];
            NSDictionary *addOn = rcao_addOn_for(command);
            if (!addOn) return [NSString stringWithFormat:@"Error: No add-on '%@' (see addons)\n", command[0]];
            NSMutableArray<NSString *> *trace = [NSMutableArray array];
            NSString *reply = rcao_dispatch(addOn, command, trace);
            if (trace.count == 0) return reply;   // no such action: the add-on's list
            return [NSString stringWithFormat:@"%@\nReply: %@", [trace componentsJoinedByString:@"\n"], reply];
        }
        return @"Error: Use addons, addons reload, addons validate <file>, addons trace <command>, addons parse <command>, addons enable|disable <id>, addons settings <id>, addons set <id> <setting> <value> or addons check <condition> [expected]\n";
    }

    NSDictionary *addOn = rcao_addOn_for(words);
    if (!addOn) return nil;
    return rcao_dispatch(addOn, words, nil);
}

// Runs the action a command names (its words, starting with the add-on's id), or lists the add-on's actions
static NSString *rcao_dispatch(NSDictionary *addOn, NSArray<NSString *> *words, NSMutableArray<NSString *> *trace) {
    // An add-on command running add-on commands: limited, so two can't call each other forever
    static __thread int depth = 0;
    if (depth >= kRCAOMaxDepth) return @"Error: Add-on commands nested too deeply\n";

    NSUInteger matchLength = 0;
    NSDictionary *match = rcao_match_action(addOn, words, &matchLength);
    // No such action: an error (so stopOnError and scripts can tell), then what the add-on has
    if (!match) {
        NSString *asked = words.count > 1 ? [[words subarrayWithRange:NSMakeRange(1, words.count - 1)] componentsJoinedByString:@" "] : nil;
        NSString *error = asked ? [NSString stringWithFormat:@"Error: %@ has no action '%@'\n", addOn[@"name"], asked] : @"";
        return [error stringByAppendingString:rcao_usage(addOn)];
    }

    depth++;
    NSArray<NSString *> *rest = [words subarrayWithRange:NSMakeRange(1, words.count - 1)];
    NSString *result = rcao_run_action(addOn, match, [rest subarrayWithRange:NSMakeRange(matchLength, rest.count - matchLength)], trace);
    depth--;
    return result;
}

// The condition a key ("addon:<add-on id>:<condition id>") names, or nil
static NSDictionary *rcao_condition_for_key(NSString *key) {
    NSArray *parts = [key componentsSeparatedByString:@":"];
    if (parts.count != 3 || ![parts[0] isEqualToString:@"addon"]) return nil;
    for (NSDictionary *addOn in rcao_current()) {
        if (![addOn[@"id"] isEqualToString:parts[1]]) continue;
        for (NSDictionary *condition in addOn[@"conditions"] ?: @[]) {
            if ([condition[@"id"] isEqualToString:parts[2]]) return condition;
        }
    }
    return nil;
}


// A condition's raw value (before choices map it to a label), or nil when unknown
static NSString *rcao_condition_raw(NSDictionary *condition) {
    if (condition[@"exec"]) {
        NSMutableArray *args = [NSMutableArray array];
        for (NSString *arg in condition[@"exec"]) [args addObject:rcao_fill(arg, @{}) ?: arg];
        int status = 0;
        NSString *errors = nil;   // stdout only: a warning on stderr would spoil the value
        NSString *output = [rcao_exec(args, [condition[@"root"] boolValue], &status, &errors)
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return status == 0 ? output : nil;
    }
    int token = 0;
    uint64_t state = 0;
    if (notify_register_check([condition[@"notifyState"] UTF8String], &token) != NOTIFY_STATUS_OK) return nil;
    notify_get_state(token, &state);
    notify_cancel(token);
    return [NSString stringWithFormat:@"%llu", state];
}

NSString *RCAddOnsConditionValue(NSString *key, BOOL *isNumber) {
    NSDictionary *condition = rcao_condition_for_key(key);
    if (!condition) return nil;
    if (isNumber) *isNumber = [condition[@"type"] isEqualToString:@"number"];
    double cache = MIN(MAX([condition[@"cache"] doubleValue], 0), kRCAOMaxCache);
    NSString *raw = nil;
    BOOL cached = NO;
    if (cache > 0) {
        @synchronized (rcao_cache_lock()) {
            NSArray *entry = rcao_conditionCache[key];
            if (entry && CFAbsoluteTimeGetCurrent() - [entry[1] doubleValue] < cache) {
                raw = [entry[0] isKindOfClass:[NSString class]] ? entry[0] : nil;
                cached = YES;
            }
        }
    }
    if (!cached) {
        raw = rcao_condition_raw(condition);
        if (cache > 0) {
            @synchronized (rcao_cache_lock()) {
                if (!rcao_conditionCache) rcao_conditionCache = [NSMutableDictionary dictionary];
                rcao_conditionCache[key] = @[raw ?: [NSNull null], @(CFAbsoluteTimeGetCurrent())];
            }
        }
    }
    if (!raw) return nil;
    // A number condition whose value isn't a number is unknown, like a failed program (not 0)
    if ([condition[@"type"] isEqualToString:@"number"] && !rcao_number(raw, NULL)) return nil;
    // A choice condition's raw value maps to its label
    NSDictionary *choices = condition[@"choices"];
    if ([choices isKindOfClass:[NSDictionary class]] && [choices[raw] isKindOfClass:[NSString class]]) return choices[raw];
    return raw;
}

int RCAddOnsConditionWatch(NSString *key, dispatch_block_t changed) {
    NSDictionary *condition = rcao_condition_for_key(key);
    if (!rcao_is_string(condition[@"notifyState"]) || !changed) return -1;
    int token = NOTIFY_TOKEN_INVALID;
    NSString *cacheKey = [key copy];
    if (notify_register_dispatch([condition[@"notifyState"] UTF8String], &token, rcao_queue(), ^(int t) {
        // The value just changed: a cached one is out of date (else the wait it wakes would read it)
        @synchronized (rcao_cache_lock()) { [rcao_conditionCache removeObjectForKey:cacheKey]; }
        changed();
    }) != NOTIFY_STATUS_OK) return -1;
    return token;
}

void RCAddOnsConditionStopWatching(int token) {
    if (token < 0) return;
    // On the queue the handler runs on, so no call is still on its way once this returns
    dispatch_sync(rcao_queue(), ^{ notify_cancel(token); });
}

// An icon naming an image file (png, jpg or jpeg) in place of an SF Symbol
static BOOL rcao_icon_is_image(NSString *icon) {
    NSString *ext = icon.pathExtension.lowercaseString;
    return [@[@"png", @"jpg", @"jpeg"] containsObject:ext];
}

// Every icon string in an add-on: its own, its actions', its triggers' and its conditions'
static NSArray<NSString *> *rcao_icons(NSDictionary *addOn) {
    NSMutableArray *icons = [NSMutableArray array];
    void (^add)(id) = ^(id icon) { if (rcao_is_string(icon)) [icons addObject:icon]; };
    add(addOn[@"icon"]);
    for (NSDictionary *action in addOn[@"actions"] ?: @[]) if ([action isKindOfClass:[NSDictionary class]]) add(action[@"icon"]);
    for (NSDictionary *condition in addOn[@"conditions"] ?: @[]) if ([condition isKindOfClass:[NSDictionary class]]) add(condition[@"icon"]);
    for (NSDictionary *event in addOn[@"events"] ?: @[]) if ([event isKindOfClass:[NSDictionary class]] && [event[@"trigger"] isKindOfClass:[NSDictionary class]]) add(event[@"trigger"][@"icon"]);
    return icons;
}

// The image file an icon string names: beside the add-on's JSON file, or an absolute path. nil when
// it is an SF Symbol or the file isn't there.
static NSString *rcao_icon_path(NSString *icon, NSString *folder) {
    if (!rcao_is_string(icon) || !rcao_icon_is_image(icon)) return nil;
    NSString *path = [icon hasPrefix:@"/"] ? icon : [folder stringByAppendingPathComponent:icon];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

// The image an add-on's icon names (name nil), or one of its other icons (an action's, trigger's or
// condition's), with its content type. Only icons the add-on itself lists are served.
NSData *RCAddOnsIconData(NSString *addOnId, NSString *name, NSString **contentType) {
    for (NSDictionary *addOn in rcao_current()) {
        if (![addOn[@"id"] isEqualToString:addOnId]) continue;
        NSString *icon = name.length ? name : addOn[@"icon"];
        if (!icon || ![rcao_icons(addOn) containsObject:icon]) return nil;
        NSString *path = rcao_icon_path(icon, addOn[@"_folder"]);
        NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
        if (!data || data.length > 512 * 1024) return nil;
        if (contentType) *contentType = [path.pathExtension.lowercaseString isEqualToString:@"png"] ? @"image/png" : @"image/jpeg";
        return data;
    }
    return nil;
}

NSString *RCAddOnsCatalogJSON(void) {
    NSArray *addOns, *problems;
    rcao_current();
    @synchronized (rcao_lock()) {
        addOns = rcao_addOns ?: @[];
        problems = rcao_problems ?: @[];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"addons": addOns, @"problems": problems} options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{\"addons\":[],\"problems\":[]}";
}

void RCAddOnsStart(void) {
    dispatch_async(rcao_queue(), ^{ rcao_load(YES); });
}
