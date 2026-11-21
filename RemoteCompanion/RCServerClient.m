#import "RCServerClient.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

@implementation RCServerClient

+ (instancetype)sharedClient {
    static RCServerClient *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[RCServerClient alloc] init];
    });
    return sharedInstance;
}

- (void)executeCommand:(NSString *)command completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    [self executeCommand:command timeout:5.0 completion:completion];
}

- (void)executeCommand:(NSString *)command timeout:(NSTimeInterval)timeout completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (sockfd < 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, [NSError errorWithDomain:@"RCServerClientError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create UNIX socket"}]);
            });
            return;
        }
        
        NSString *socketPath = @"/var/mobile/Documents/rc.sock";
        struct sockaddr_un serv_addr;
        memset(&serv_addr, 0, sizeof(serv_addr));
        serv_addr.sun_family = AF_UNIX;
        strncpy(serv_addr.sun_path, [socketPath UTF8String], sizeof(serv_addr.sun_path) - 1);
        
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 500000; // 500ms timeout for connect
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
        setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof tv);
        
        if (connect(sockfd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
            close(sockfd);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, [NSError errorWithDomain:@"RCServerClientError" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Could not connect to RemoteCompanion tweak (UNIX socket)"}]);
            });
            return;
        }
        
        // Send command
        const char *cmd = [command UTF8String];
        if (write(sockfd, cmd, strlen(cmd)) < 0) {
            close(sockfd);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, [NSError errorWithDomain:@"RCServerClientError" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to send command"}]);
            });
            return;
        }
        
        // Read response
        NSMutableData *receivedData = [NSMutableData data];
        char buffer[1024];
        ssize_t n;
        
        // Increase timeout for reading data (5 seconds by default, longer for a slow command)
        tv.tv_sec = (time_t)MAX(1.0, timeout);
        tv.tv_usec = 0;
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
        
        while ((n = read(sockfd, buffer, sizeof(buffer) - 1)) > 0) {
            [receivedData appendBytes:buffer length:n];
        }
        
        close(sockfd);
        
        NSString *output = [[NSString alloc] initWithData:receivedData encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(output, nil);
        });
    });
}

@end
