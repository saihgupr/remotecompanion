#import <Foundation/Foundation.h>

// Full backup: one JSON file with the whole configuration and the files beside it
// (add-ons, gestures, notification filters, variables, blacklist), built by the
// tweak so the app and `rc backup` write the same thing.
@interface RCBackup : NSObject

// One command on the tweak's socket, nil when the tweak is not running. Also used
// to read picked files the app sandbox refuses.
+ (NSString *)sendTweakCommand:(NSString *)command;

// Ask the tweak for the full backup JSON.
+ (NSData *)fullBackupJSONDataWithError:(NSError **)error;

// YES for a full backup, NO for the old configuration JSON (triggers only).
+ (BOOL)isFullBackupData:(NSData *)data;

// Queue the bundle for the tweak and apply it: replaces all settings, triggers
// and add-ons on this device.
+ (BOOL)restoreFullBackupData:(NSData *)data error:(NSError **)error;

+ (NSString *)defaultFileName;

@end
