#import "RCBackup.h"
#import "RCConfigManager.h"
#include <fcntl.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static NSString *const kRCBackupSocketPath = @"/var/mobile/Documents/rc.sock";
static NSString *const kRCBackupRestorePath = @"/var/mobile/Documents/rc_restore.json";
static NSString *const kRCBackupFormat = @"rc-backup";

@implementation RCBackup

+ (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:@"RCBackup" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

+ (NSString *)sendTweakCommand:(NSString *)command {
    if (command.length == 0) return nil;

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return nil;

    struct timeval timeout = { .tv_sec = 10, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, kRCBackupSocketPath.UTF8String, sizeof(addr.sun_path));

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return nil;
    }

    NSData *commandData = [command dataUsingEncoding:NSUTF8StringEncoding];
    write(fd, commandData.bytes, commandData.length);

    NSMutableData *response = [NSMutableData data];
    uint8_t buffer[4096];
    ssize_t count;
    while ((count = read(fd, buffer, sizeof(buffer))) > 0) {
        [response appendBytes:buffer length:(NSUInteger)count];
    }
    close(fd);

    NSString *text = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSData *)fullBackupJSONDataWithError:(NSError **)error {
    NSString *response = [self sendTweakCommand:@"backup config"];
    if (response.length == 0) {
        if (error) *error = [self errorWithMessage:@"The tweak is not running. Respring and try again."];
        return nil;
    }
    if (![response hasPrefix:@"{"]) {
        if (error) *error = [self errorWithMessage:response];
        return nil;
    }
    return [response dataUsingEncoding:NSUTF8StringEncoding];
}

+ (BOOL)isFullBackupData:(NSData *)data {
    if (data.length == 0) return NO;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [parsed isKindOfClass:[NSDictionary class]] && [parsed[@"format"] isEqual:kRCBackupFormat];
}

+ (BOOL)restoreFullBackupData:(NSData *)data error:(NSError **)error {
    if (![self isFullBackupData:data]) {
        if (error) *error = [self errorWithMessage:@"Not a full backup file"];
        return NO;
    }

    // The payload is too large for one socket command, so leave it where the tweak
    // reads it and remove it there. 0600: it holds every password and token.
    int fd = open(kRCBackupRestorePath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        if (error) *error = [self errorWithMessage:[NSString stringWithFormat:@"Could not write %@", kRCBackupRestorePath]];
        return NO;
    }
    const uint8_t *bytes = data.bytes;
    size_t left = data.length;
    BOOL written = YES;
    while (left > 0) {
        ssize_t count = write(fd, bytes, left);
        if (count <= 0) { written = NO; break; }
        bytes += count;
        left -= (size_t)count;
    }
    close(fd);
    if (!written) {
        [[NSFileManager defaultManager] removeItemAtPath:kRCBackupRestorePath error:NULL];
        if (error) *error = [self errorWithMessage:@"Could not write the backup to the device"];
        return NO;
    }

    NSString *response = [self sendTweakCommand:@"restore backup"];
    if (response.length == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:kRCBackupRestorePath error:NULL];
        if (error) *error = [self errorWithMessage:@"The tweak is not running. Respring and try again."];
        return NO;
    }
    if ([response hasPrefix:@"Error"]) {
        if (error) *error = [self errorWithMessage:response];
        return NO;
    }

    [[RCConfigManager sharedManager] loadConfig];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCConfigChangedNotification object:nil];
    return YES;
}

+ (NSString *)defaultFileName {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyyMMdd_HHmm";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    NSString *stamp = [formatter stringFromDate:[NSDate date]] ?: @"backup";
    return [NSString stringWithFormat:@"rc_backup_%@.json", stamp];
}

@end
