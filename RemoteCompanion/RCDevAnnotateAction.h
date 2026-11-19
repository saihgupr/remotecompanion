#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Developer Mode action: captures/annotates a screenshot with voice/text and sends it to an editor over SSH.
// Stored as: dev-annotate {"autoSend":true,"editor":"opencode","hostId":"<uuid>"}
@interface RCDevAnnotateAction : NSObject

+ (NSArray<NSDictionary *> *)presets;
+ (nullable NSDictionary *)presetForId:(nullable NSString *)presetId;
+ (NSString *)deliverPythonScriptBase64;

+ (BOOL)isDevAnnotateCommand:(nullable NSString *)command;
+ (nullable NSDictionary *)componentsFromActionString:(nullable NSString *)action;
+ (NSString *)actionStringWithHostId:(NSString *)hostId
                              editor:(NSString *)editor
                            autoSend:(BOOL)autoSend
                          projectDir:(nullable NSString *)projectDir
                          pauseMusic:(BOOL)pauseMusic;

+ (NSString *)editorDisplayNameForComponents:(nullable NSDictionary *)components;
+ (NSString *)displayTitleForActionString:(nullable NSString *)action;
+ (NSString *)displaySubtitleForActionString:(nullable NSString *)action
                                    hostName:(nullable NSString *)hostName;

@end

NS_ASSUME_NONNULL_END
