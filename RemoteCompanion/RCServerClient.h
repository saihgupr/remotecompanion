#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCServerClient : NSObject

+ (instancetype)sharedClient;

- (void)executeCommand:(NSString *)command completion:(void (^)(NSString * _Nullable output, NSError * _Nullable error))completion;
// A command that may take longer than the usual 5 s, such as an SSH connection test
- (void)executeCommand:(NSString *)command timeout:(NSTimeInterval)timeout completion:(void (^)(NSString * _Nullable output, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
