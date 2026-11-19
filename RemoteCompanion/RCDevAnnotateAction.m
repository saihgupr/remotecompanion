#import "RCDevAnnotateAction.h"
#import "RCDevEditorPresetsData.h"

static NSString *const kRCDevAnnotateName = @"dev-annotate";

static NSString *RCDevTrimmed(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return @"";
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@implementation RCDevAnnotateAction

+ (NSArray<NSDictionary *> *)presets {
    static NSArray<NSDictionary *> *cachedPresets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSData *data = [kRCDevEditorPresetsJSON dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([parsed isKindOfClass:[NSArray class]]) {
            cachedPresets = (NSArray<NSDictionary *> *)parsed;
        } else {
            cachedPresets = @[];
        }
    });
    return cachedPresets;
}

+ (nullable NSDictionary *)presetForId:(nullable NSString *)presetId {
    NSString *target = RCDevTrimmed(presetId ?: @"");
    if (target.length == 0) target = @"opencode";
    for (NSDictionary *preset in [self presets]) {
        if ([preset[@"id"] isEqualToString:target]) {
            return preset;
        }
    }
    return nil;
}

+ (NSString *)deliverPythonScriptBase64 {
    return kRCDevDeliverPythonScriptB64;
}

+ (BOOL)isDevAnnotateCommand:(nullable NSString *)command {
    if (![command isKindOfClass:[NSString class]]) return NO;
    NSString *trimmed = RCDevTrimmed(command);
    return [trimmed isEqualToString:kRCDevAnnotateName]
        || [trimmed hasPrefix:@"dev-annotate "]
        || [trimmed hasPrefix:@"dev-annotate\t"];
}

+ (nullable NSDictionary *)componentsFromActionString:(nullable NSString *)action {
    if (![self isDevAnnotateCommand:action]) return nil;
    NSString *trimmed = RCDevTrimmed(action);
    if (trimmed.length <= kRCDevAnnotateName.length) return nil;

    NSString *payload = RCDevTrimmed([trimmed substringFromIndex:kRCDevAnnotateName.length]);
    if (payload.length == 0) return nil;

    NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![parsed isKindOfClass:[NSDictionary class]]) return nil;

    NSDictionary *raw = (NSDictionary *)parsed;
    NSString *hostId = [raw[@"hostId"] isKindOfClass:[NSString class]] ? RCDevTrimmed(raw[@"hostId"]) : @"";
    NSString *editor = [raw[@"editor"] isKindOfClass:[NSString class]] ? RCDevTrimmed(raw[@"editor"]) : @"";
    if (editor.length == 0) editor = @"opencode";

    BOOL autoSend = YES;
    id rawAutoSend = raw[@"autoSend"];
    if ([rawAutoSend isKindOfClass:[NSNumber class]] || [rawAutoSend isKindOfClass:[NSString class]]) {
        autoSend = [rawAutoSend boolValue];
    }

    NSString *projectDir = [raw[@"projectDir"] isKindOfClass:[NSString class]] ? RCDevTrimmed(raw[@"projectDir"]) : @"";

    return @{
        @"hostId": hostId,
        @"editor": editor,
        @"autoSend": @(autoSend),
        @"projectDir": projectDir
    };
}

+ (NSString *)actionStringWithHostId:(NSString *)hostId
                              editor:(NSString *)editor
                            autoSend:(BOOL)autoSend
                          projectDir:(nullable NSString *)projectDir {
    NSString *cleanHost = RCDevTrimmed(hostId ?: @"");
    NSString *cleanEditor = RCDevTrimmed(editor ?: @"");
    if (cleanEditor.length == 0) cleanEditor = @"opencode";

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"autoSend"] = @(autoSend);
    dict[@"editor"] = cleanEditor;
    dict[@"hostId"] = cleanHost;

    NSString *cleanProject = RCDevTrimmed(projectDir ?: @"");
    NSDictionary *preset = [self presetForId:cleanEditor];
    if (cleanProject.length > 0 && [preset[@"supportsProjectDir"] boolValue]) {
        dict[@"projectDir"] = cleanProject;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:dict
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
    return [NSString stringWithFormat:@"%@ %@", kRCDevAnnotateName, text ?: @"{}"];
}

+ (NSString *)editorDisplayNameForComponents:(nullable NSDictionary *)components {
    if (![components isKindOfClass:[NSDictionary class]]) return @"Editor";
    NSString *editor = RCDevTrimmed(components[@"editor"] ?: @"");
    if (editor.length == 0) editor = @"opencode";

    NSDictionary *preset = [self presetForId:editor];
    NSString *name = preset[@"name"];
    if ([name isKindOfClass:[NSString class]] && name.length > 0) {
        return name;
    }
    return editor;
}

+ (NSString *)displayTitleForActionString:(nullable NSString *)action {
    NSDictionary *comp = [self componentsFromActionString:action];
    if (!comp) return @"Annotate & Send to Editor";
    NSString *editorName = [self editorDisplayNameForComponents:comp];
    return [NSString stringWithFormat:@"Annotate \u2192 %@", editorName];
}

+ (NSString *)displaySubtitleForActionString:(nullable NSString *)action
                                    hostName:(nullable NSString *)hostName {
    NSDictionary *comp = [self componentsFromActionString:action];
    if (!comp) return @"Developer Mode";
    BOOL autoSend = comp[@"autoSend"] ? [comp[@"autoSend"] boolValue] : YES;
    NSString *mode = autoSend ? @"Auto-send" : @"Paste only";
    NSString *cleanHost = RCDevTrimmed(hostName ?: @"");
    if (cleanHost.length > 0) {
        return [NSString stringWithFormat:@"%@ \u00b7 %@", cleanHost, mode];
    }
    return mode;
}

@end
