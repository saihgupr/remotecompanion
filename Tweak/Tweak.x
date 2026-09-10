#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/un.h>
#include <sys/stat.h>
#import <unistd.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netdb.h>
#import <spawn.h>
#import <notify.h>
#import <sys/wait.h>
#import <sys/utsname.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <GraphicsServices/GraphicsServices.h>
#import "native_curl.h"
#import <CoreFoundation/CoreFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/message.h>

@interface CLLocationManager (RemoteCompanionPrivate)
+ (BOOL)locationServicesEnabled;
+ (void)setLocationServicesEnabled:(BOOL)enabled;
+ (void)_setLocationServicesEnabled:(BOOL)enabled;
@end

@class SBProximitySensorManager;

static void trigger_haptic();
static void toggle_system_vibration(BOOL silentMode, BOOL enable);
static BOOL get_system_vibration(BOOL silentMode);
static void toggle_location_services(BOOL state);
static BOOL get_location_services_state(void);

static NSString *g_currentAppBundleId = nil;
static NSString *g_previousAppBundleId = nil;
static SBProximitySensorManager *g_proximitySensorManager = nil;
static BOOL g_forceProximityDetection = NO;
static int g_latestHIDProximityState = -1;

// WorkflowKit interfaces
@interface WFWorkflowDescriptor : NSObject
- (instancetype)initWithName:(NSString *)name;
@end

@interface WFWorkflowRunnerClient : NSObject
- (instancetype)initWithWorkflowDescriptor:(WFWorkflowDescriptor *)descriptor input:(id)input parseInput:(BOOL)parse output:(id)output completion:(void (^)(id output, NSError *error))completion;
- (void)start;
@end

@interface SiriPresentationOptions : NSObject
- (void)setWakeScreen:(BOOL)arg1;
- (void)setHideOtherWindowsDuringAppearance:(BOOL)arg1;
@end

@interface SBAssistantController : NSObject
+ (id)sharedInstance;
- (BOOL)isVisible;
- (void)handleVoiceAssistantButtonWithSource:(long long)arg1;
- (void)handleVoiceAssistantButtonWithSource:(long long)arg1 direct:(BOOL)arg2;
- (void)_presentForMainScreenAnimated:(BOOL)arg1 options:(id)arg2 completion:(id)arg3;
- (void)handleSiriButtonDownWithSource:(long long)arg1;
- (void)handleSiriButtonUpWithSource:(long long)arg1;
@end

// Lua interpreter
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

// IOKit / HID Stuff
typedef struct __IOHIDEvent * IOHIDEventRef;
typedef struct __IOHIDEventSystemClient * IOHIDEventSystemClientRef;
typedef uint32_t IOHIDEventOptionBits;
typedef uint32_t IOOptionBits;

@interface UIWindow (Private)
- (uint32_t)_contextId;
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)includeInternal onlyVisibleWindows:(BOOL)onlyVisible;
@end

@interface UIApplication (Private)
- (void)_enqueueHIDEvent:(IOHIDEventRef)event;
@end

extern void BKSHIDEventSetDigitizerInfo(IOHIDEventRef digitizerEvent, uint32_t contextID, uint8_t systemGestureisPossible, uint8_t isSystemGestureStateChangeEvent, CFStringRef displayUUID, CFTimeInterval initialTouchTimestamp, float maxForce);
static UIWindow *g_rcTapTestWindow;
static UIWindow *g_rcTapRecordWindow = nil;

void SRLog(NSString *format, ...);
#import <objc/message.h>

static IOHIDEventSystemClientRef (*_IOHIDEventSystemClientCreate)(CFAllocatorRef allocator);
static IOHIDEventRef (*_IOHIDEventCreateKeyboardEvent)(CFAllocatorRef allocator, uint64_t timestamp, uint32_t usagePage, uint32_t usage, boolean_t down, IOHIDEventOptionBits flags);
static void (*_IOHIDEventSystemClientDispatchEvent)(IOHIDEventSystemClientRef client, IOHIDEventRef event);

// Forward declarations for Siri interaction
@interface SBVoiceControlController : NSObject
- (void)handleHomeButtonHeld;
@end

@interface SBSiriHardwareButtonInteraction : NSObject
- (instancetype)initWithSiriButton:(id)arg1;
- (void)consumeInitialPressDown;
- (void)consumeSinglePressUp;
- (void)consumeLongPress;
@end

// Global captured instances
static SBVoiceControlController *sharedVoiceControl = nil;
static NSHashTable *siriInteractions = nil;

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(id)arg1;
- (NSArray *)allInstalledApplications;
@end

@interface SBControlCenterController : NSObject
+ (id)sharedInstanceIfExists;
+ (id)sharedInstance;
- (BOOL)isVisible;
- (void)presentAnimated:(BOOL)animated;
- (void)presentAnimated:(BOOL)animated completion:(id)completion;
@end

@interface NCNotificationContent : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *subtitle;
@property (nonatomic, copy, readonly) NSString *message;
@end

@interface NCNotificationRequest : NSObject
@property (nonatomic, copy, readonly) NSString *sectionIdentifier;
@property (nonatomic, strong, readonly) NCNotificationContent *content;
@end

@interface NCNotificationDispatcher : NSObject
- (void)postNotificationRequest:(id)arg1 forDestination:(id)arg2;
@end

%hook SBVoiceControlController
- (id)init {
    id r = %orig;
    sharedVoiceControl = r;
    SRLog(@"Captured SBVoiceControlController init: %@", r);
    return r;
}
%end

%hook SBSiriHardwareButtonInteraction
- (id)initWithSiriButton:(id)arg1 {
    id r = %orig;
    if (!siriInteractions) {
        siriInteractions = [NSHashTable weakObjectsHashTable];
    }
    [siriInteractions addObject:r];
    SRLog(@"Captured SBSiriHardwareButtonInteraction init: %@", r);
    return r;
}
%end

// Touch/Digitizer event creation
static IOHIDEventRef (*_IOHIDEventCreateDigitizerEvent)(CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t transducerType, uint32_t index, uint32_t identity, uint32_t eventMask, uint32_t buttonMask,
    double x, double y, double z, double tipPressure, double twist,
    boolean_t range, boolean_t touch, IOHIDEventOptionBits options);
static IOHIDEventRef (*_IOHIDEventCreateDigitizerFingerEvent)(CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t index, uint32_t identity, uint32_t eventMask,
    double x, double y, double z, double tipPressure, double twist,
    boolean_t range, boolean_t touch, IOHIDEventOptionBits options);
static void (*_IOHIDEventAppendEvent)(IOHIDEventRef parent, IOHIDEventRef child, IOHIDEventOptionBits options);
static void (*_IOHIDEventSetIntegerValue)(IOHIDEventRef event, uint32_t field, int32_t value);
static void (*_IOHIDEventSetIntegerValueWithOptions)(IOHIDEventRef event, uint32_t field, int32_t value, uint32_t options);
static void (*_IOHIDEventSetSenderID)(IOHIDEventRef event, uint64_t senderID);

// Usage Pages / Usages
#define kHIDPage_GenericDesktop 0x01
#define kHIDPage_Consumer       0x0C
#define kHIDUsage_GD_SystemSleep 0x82
#define kHIDUsage_Csmr_Power     0x30
#define kHIDUsage_Csmr_Menu      0x40 // Home button usually
#define kHIDUsage_Csmr_VoiceCommand 0xCF
#define kHIDPage_KeyboardOrKeypad 0x07
#define kHIDUsage_Csmr_VolumeIncrement 0xE9
#define kHIDUsage_Csmr_VolumeDecrement 0xEA
#define kHIDUsage_Csmr_Mute      0xE2
#define kHIDUsage_Csmr_PlayOrPause 0xCD

// Keyboard number keys (Usage Page 0x07)
#define kHIDUsage_Keypad_1 0x1E
#define kHIDUsage_Keypad_2 0x1F
#define kHIDUsage_Keypad_3 0x20
#define kHIDUsage_Keypad_4 0x21
#define kHIDUsage_Keypad_5 0x22
#define kHIDUsage_Keypad_6 0x23
#define kHIDUsage_Keypad_7 0x24
#define kHIDUsage_Keypad_8 0x25
#define kHIDUsage_Keypad_9 0x26
#define kHIDUsage_Keypad_0 0x27

// Private MediaRemote Declarations
// Derived from internet search for targeting specific apps
typedef unsigned int MRMediaRemoteCommand;
extern Boolean MRMediaRemoteSendCommandToApp(MRMediaRemoteCommand command, NSDictionary *userInfo, id origin, NSString *bundleIdentifier, unsigned int options, dispatch_queue_t queue, void (^completion)(NSError *));


// Passcode UI interfaces for direct interaction
@interface SBUIPasscodeLockViewBase : UIView
- (void)_noteStringEntered:(NSString *)string;
- (void)resetForFailedPasscode;
- (void)_sendDelegateKeypadKeyDown;
@end

@interface SBUIPasscodeLockViewWithKeypad : SBUIPasscodeLockViewBase
- (void)_noteStringEntered:(NSString *)string;
- (void)passcodeLockNumberPadKeyPressed:(id)key;
@end

@interface SBUINumericPasscodeEntryField : UIView
- (void)appendCharacter:(NSString *)character;
- (void)setString:(NSString *)string;
@end

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)attemptUnlockWithPasscode:(NSString *)passcode;
- (BOOL)_attemptUnlockWithPasscode:(NSString *)passcode mesa:(BOOL)mesa finishUIUnlock:(BOOL)finishUI;
- (void)lockUIFromSource:(int)source withOptions:(id)options;
- (void)unlockUIFromSource:(int)source withOptions:(id)options;
- (void)_setUILocked:(BOOL)locked animated:(BOOL)animated withReason:(id)reason;
- (BOOL)isUILocked;
- (id)lockScreenViewController;
@end

@interface SBBacklightController : NSObject
+ (id)sharedInstance;
- (BOOL)screenIsOn;
- (float)backlightLevel;
@end

@interface BKOperation : NSObject
@end

@interface SBFUserAuthenticationController : NSObject
- (BOOL)authenticateUsingBiometricAuthSourceWithCompletion:(id)completion;
@end

@interface SBSystemGestureManager : NSObject
+ (instancetype)mainDisplayManager;
- (void)addGestureRecognizer:(UIGestureRecognizer *)recognizer withType:(NSUInteger)type;
@end

@interface SREdgeGestureRecognizer : UIPanGestureRecognizer
@property (nonatomic, assign) BOOL isLeftEdge;
@property (nonatomic, assign) BOOL isRightEdge;
@property (nonatomic, assign) BOOL hasTriggered;
@end



@interface SBReachabilityManager : NSObject
+ (id)sharedInstance;
- (UIGestureRecognizer *)reachabilityGestureRecognizer;
- (void)toggleReachability;
@end


// BluetoothManager APIs
@interface BluetoothManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)enabled;
- (void)setEnabled:(BOOL)enabled;
- (void)setPowered:(BOOL)powered;
- (BOOL)powered;
- (NSArray *)pairedDevices;
- (void)connectDevice:(id)device;
@end

// BluetoothDevice APIs
@interface BluetoothDevice : NSObject
- (NSString *)name;
- (NSString *)address;
- (BOOL)connected;
- (void)connect;
- (void)disconnect;
@end

// WiFiManager APIs
@interface WiFiManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)wiFiEnabled;
- (void)setWiFiEnabled:(BOOL)enabled;
@end

// Airplane Mode APIs (AppSupport)
@interface RadiosPreferences : NSObject
- (BOOL)airplaneMode;
- (void)setAirplaneMode:(BOOL)enabled;
- (void)synchronize;
@end

// SBWiFiManager API
@interface SBWiFiManager : NSObject
+ (instancetype)sharedInstance;
- (void)setWiFiEnabled:(BOOL)enabled;
- (BOOL)wiFiEnabled;
- (id)currentNetworkName;
@end

@interface SBTelephonyManager : NSObject
+ (id)sharedTelephonyManager;
- (id)_serverConnection;
@end


// MediaRemote APIs - these are stable and work on iOS 15.8
typedef enum {
    kMRPlay = 0,
    kMRTogglePlayPause = 1,
    kMRPause = 2,
    kMRNextTrack = 4,
    kMRPreviousTrack = 5
} MRCommand;

extern void MRMediaRemoteSendCommand(MRCommand command, NSDictionary *options);
extern void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t queue, void (^completion)(Boolean isPlaying));
extern void MRMediaRemoteGetNowPlayingApplicationPlaybackState(dispatch_queue_t queue, void (^completion)(unsigned int state));
extern void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, void (^completion)(CFDictionaryRef information));
extern void MRMediaRemoteGetNowPlayingClient(dispatch_queue_t queue, void (^completion)(void *clientObj));
extern CFStringRef MRNowPlayingClientGetBundleIdentifier(void *clientObj);

extern CFStringRef kMRMediaRemoteNowPlayingInfoTitle;
extern CFStringRef kMRMediaRemoteNowPlayingInfoArtist;

// AVOutputDevice for ANC control (used by Sonitus)
@interface AVOutputDevice : NSObject
@property (readonly, nonatomic) NSString *name;
- (NSArray *)availableBluetoothListeningModes;
- (BOOL)setCurrentBluetoothListeningMode:(NSString *)mode error:(NSError **)error;
- (NSString *)currentBluetoothListeningMode;
@end

// MPAVRoutingController (MediaPlayer)
@interface MPAVRoute : NSObject
@property (nonatomic, readonly) NSString *routeName;
@property (nonatomic, readonly) NSString *routeUID;
@property (nonatomic, readonly) BOOL isDeviceRoute;
@property (nonatomic, readonly) BOOL isPickable;
@property (nonatomic, readonly, getter=isPicked) BOOL picked;
@end

@interface MPAVRoutingController : NSObject
@property (nonatomic, weak) id delegate;
@property (nonatomic, readonly) NSArray<MPAVRoute *> *availableRoutes;
@property (nonatomic, assign) NSInteger discoveryMode;
- (void)fetchAvailableRoutesWithCompletionHandler:(void(^)(NSArray<MPAVRoute *> *routes))completion;
- (BOOL)pickRoute:(MPAVRoute *)route;
@end

// AVOutputContext for getting current output device
@interface AVOutputContext : NSObject
+ (instancetype)sharedSystemAudioContext;
- (NSArray *)outputDevices;
@end

// FrontBoardServices for fast app launching
@interface FBSOpenApplicationOptions : NSObject
+ (instancetype)optionsWithDictionary:(NSDictionary *)dictionary;
@end

@interface FBSOpenApplicationService : NSObject
+ (instancetype)serviceWithDefaultShellEndpoint;
- (void)openApplication:(NSString *)bundleID withOptions:(FBSOpenApplicationOptions *)options completion:(id)completion;
@end

// DoNotDisturb Interfaces
@interface DNDModeAssertionLifetime : NSObject
+ (instancetype)lifetimeUntilEndOfScheduleWithIdentifier:(NSString *)identifier;
@end

@interface DNDModeAssertionDetails : NSObject
+ (instancetype)detailsWithIdentifier:(NSString *)identifier modeIdentifier:(NSString *)modeIdentifier lifetime:(DNDModeAssertionLifetime *)lifetime;
+ (instancetype)userRequestedAssertionDetails; // Helper for simple toggle
@end

@interface DNDModeAssertion : NSObject
@end

@interface DNDModeAssertionService : NSObject
+ (instancetype)serviceForClientIdentifier:(NSString *)clientIdentifier;
- (DNDModeAssertion *)takeModeAssertionWithDetails:(DNDModeAssertionDetails *)details error:(NSError **)error;
- (BOOL)invalidateAllActiveModeAssertionsWithError:(NSError **)error;
- (id)activeModeAssertionWithError:(NSError **)error;
@end

// CoreDuet - Low Power Mode
@interface _CDBatterySaver : NSObject
+ (instancetype)batterySaver;
- (long long)getPowerMode;
- (BOOL)setPowerMode:(long long)mode error:(NSError **)error;
@end

// BackBoardServices for killing apps
extern void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleID, int reason, bool report, NSString *description);

// SpringBoard Interfaces
@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
@end

@interface SBVolumeHardwareButton : NSObject
- (id)volumeIncreaseSequenceObserver;
- (id)volumeDecreaseSequenceObserver;
@end

@interface SBVolumeHardwareButtonActions : NSObject
- (void)volumeIncreasePressDownWithModifiers:(long long)arg1;
- (void)volumeIncreasePressUp;
- (void)volumeDecreasePressDownWithModifiers:(long long)arg1;
- (void)volumeDecreasePressUp;
@end

@interface SBLockHardwareButtonActions : NSObject
- (void)performInitialButtonDownActions;
- (void)performButtonUpPreActions;
- (void)performLongPressActions;
- (void)performDoublePressActions;
@end

@interface SBUIBiometricResource : NSObject
+ (id)sharedInstance;
- (void)addObserver:(id)arg1;
- (void)removeObserver:(id)arg1;
- (BOOL)isFingerOn;
- (BOOL)hasBiometricAuthenticationCapabilityEnabled;
@end

@interface SpringBoard : UIApplication
- (UIInterfaceOrientation)activeInterfaceOrientation;
- (SBApplication *)_accessibilityFrontMostApplication;
- (void)_simulateHomeButtonPress;
- (void)_menuButtonDown:(id)arg1;
- (void)_menuButtonUp:(id)arg1;
- (void)_accessibilityHandleAppSwitcherEvent;
@end

@interface SBOrientationLockManager : NSObject
+ (instancetype)sharedInstance;
- (void)lock;
- (void)unlock;
- (BOOL)isUserLocked;
@end

@interface SBProximitySensorManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isObjectInProximity;
- (BOOL)isProximityDetectionEnabled;
- (void)setProximityDetectionEnabled:(BOOL)enabled;
- (void)_enableProx;
- (void)_disableProx;
- (void)_setProximityDetectionEnabled:(BOOL)enabled;
@end

@interface SBScreenshotManager : NSObject
+ (instancetype)sharedInstance;
- (void)saveScreenshotToCameraRollWithCompletion:(id)completion;
@end

@interface SBUIController : NSObject
+ (instancetype)sharedInstance;
- (void)handleHomeButtonTap;
- (void)handleHomeButtonTap:(id)arg1;
- (void)clickedMenuButton;
- (void)handleScreenshotGestureFired:(id)arg1;
- (BOOL)isACPowerConnected;
- (BOOL)isOnAC;
- (void)ACPowerChanged;
- (void)updateBatteryState:(id)arg1;
- (void)setIsACPowerConnected:(BOOL)arg1;
@end

@interface UISUserInterfaceStyleMode : NSObject
- (void)setModeValue:(NSInteger)value;
- (NSInteger)modeValue;
@end

@interface SBRingerControl : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isRingerMuted;
- (void)setRingerMuted:(BOOL)muted;
@end

@interface SBMainSwitcherViewController : UIViewController
+ (instancetype)sharedInstance;
- (void)_toggleSwitcher;
- (void)toggleSwitcherNoninteractively;
@end

@interface SBMainSwitcherController : NSObject
+ (instancetype)sharedInstance;
- (void)toggleSwitcherNoninteractively;
@end

@interface AVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
- (BOOL)setActiveCategoryVolumeTo:(float)volume;
- (BOOL)getActiveCategoryMuted:(BOOL *)muted;
- (BOOL)setVolumeTo:(float)volume forCategory:(NSString *)category;
@end

static float sr_previous_volume = -1.0f;





// Rootless-compatible log path helper
static NSString *rc_get_log_file_path(void) {
    static NSString *cachedLogPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:@"/var/jb/tmp"]) {
            cachedLogPath = @"/var/jb/tmp/remotecommand.log";
        } else if ([fm fileExistsAtPath:@"/var/jb"]) {
            if ([fm createDirectoryAtPath:@"/var/jb/tmp" withIntermediateDirectories:YES attributes:nil error:nil]) {
                cachedLogPath = @"/var/jb/tmp/remotecommand.log";
            }
        }
        
        if (!cachedLogPath) {
            if ([fm fileExistsAtPath:@"/tmp"]) {
                cachedLogPath = @"/tmp/remotecommand.log";
            } else {
                NSString *logsDir = @"/var/mobile/Library/Logs/RemoteCompanion";
                [fm createDirectoryAtPath:logsDir withIntermediateDirectories:YES attributes:nil error:nil];
                cachedLogPath = [logsDir stringByAppendingPathComponent:@"remotecompanion.log"];
            }
        }
    });
    return cachedLogPath ?: @"/tmp/remotecommand.log";
}

// File-based logging helper
void SRLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // Log to console (stderr) for syslog capture if available
    NSLog(@"[RemoteCommand] %@", message);
    
    // Write to file with synchronization
    @synchronized([NSFileManager defaultManager]) {
        NSString *logPath = rc_get_log_file_path();
        NSString *logMsg = [NSString stringWithFormat:@"%@ [RemoteCommand] %@\n", [NSDate date], message];
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fileHandle) {
            @try {
                [fileHandle seekToEndOfFile];
                [fileHandle writeData:[logMsg dataUsingEncoding:NSUTF8StringEncoding]];
                [fileHandle synchronizeFile]; // Force flush to disk
                [fileHandle closeFile];
            } @catch (NSException *e) {}
        } else {
            [logMsg writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            chmod([logPath UTF8String], 0666);
        }
    }
}

// Add DND Toggle Helper
// Helper to inspect current state

#import <objc/runtime.h>






__attribute__((unused))
static void toggle_dnd(BOOL state) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class ServiceClass = objc_getClass("DNDModeAssertionService");
            Class DetailsClass = objc_getClass("DNDModeAssertionDetails");
            Class StateServiceClass = objc_getClass("DNDStateService");
            
            if (!ServiceClass || !DetailsClass) {
                // Fallback for iOS 14
                if (StateServiceClass) {
                    SRLog(@"Using iOS 14 DND fallback");
                    id service = [StateServiceClass serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
                    (void)service;
                    if (state) {
                        // On iOS 14, DND is often handled via specialized controllers or assertions
                        // but a quick way is often through the SBDoNotDisturbController if we can find it
                        // or just failing gracefully if private APIs changed too much.
                        // For now, we'll try to find the shared instance of the DND service.
                        // NOTE: Proper iOS 14 DND implementation usually involves SpringBoard hooks.
                    }
                }
                SRLog(@"DND toggle not fully supported on this iOS version yet");
                return;
            }

            // Use the SAME client identifier as Control Center (from Assertions.json)
            id service = [ServiceClass serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
            
            // Always invalidate existing assertions first to prevent stacking/errors (Idempotency)
            NSError *invalidateErr = nil;
            [service invalidateAllActiveModeAssertionsWithError:&invalidateErr];
            
            if (state) {
                // Turn ON
                // Try to use a more robust identifier or userRequested approach if possible.
                // For now, let's stick to explicit default but log heavily.
                 id details = [DetailsClass detailsWithIdentifier:@"com.apple.control-center.manual-toggle"
                                                                     modeIdentifier:@"com.apple.donotdisturb.mode.default"
                                                                           lifetime:nil];
                NSError *err = nil;
                id assertion = [service takeModeAssertionWithDetails:details error:&err];
                if (err) SRLog(@"Failed to enable DND: %@", err);
                else SRLog(@"DND Enabled. Assertion: %@", assertion);
            } else {
                SRLog(@"DND Disabled");
            }
        } @catch (NSException *e) {
            SRLog(@"EXCEPTION in toggle_dnd: %@", e);
        }
    });
}

static void toggle_lpm(BOOL state) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class BatterySaverClass = objc_getClass("_CDBatterySaver");
            if (!BatterySaverClass) {
                SRLog(@"_CDBatterySaver class not found");
                return;
            }
            
            id saver = [BatterySaverClass batterySaver];
            if (!saver) {
                SRLog(@"Failed to get batterySaver instance");
                return;
            }
            
            NSError *err = nil;
            // Power mode: 0 = normal, 1 = low power
            BOOL result = [saver setPowerMode:(state ? 1 : 0) error:&err];
            
            if (err) {
                SRLog(@"Failed to set LPM: %@", err);
            } else {
                SRLog(@"LPM %@. Result: %d", state ? @"Enabled" : @"Disabled", result);
            }
        } @catch (NSException *e) {
            SRLog(@"EXCEPTION in toggle_lpm: %@", e);
        }
    });
}

// State detection helpers
static BOOL get_lpm_state() {
    Class BatterySaverClass = objc_getClass("_CDBatterySaver");
    if (BatterySaverClass) {
        id saver = [BatterySaverClass batterySaver];
        if (saver && [saver respondsToSelector:@selector(getPowerMode)]) {
            return [saver getPowerMode] != 0;
        }
    }
    return NO;
}

static BOOL get_location_services_state() {
    Class LocationManagerClass = objc_getClass("CLLocationManager");
    if (!LocationManagerClass) {
        dlopen("/System/Library/Frameworks/CoreLocation.framework/CoreLocation", RTLD_NOW);
        LocationManagerClass = objc_getClass("CLLocationManager");
    }
    if (LocationManagerClass && [LocationManagerClass respondsToSelector:@selector(locationServicesEnabled)]) {
        return [LocationManagerClass locationServicesEnabled];
    }
    return NO;
}

static void toggle_location_services(BOOL state) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class LocationManagerClass = objc_getClass("CLLocationManager");
            if (!LocationManagerClass) {
                dlopen("/System/Library/Frameworks/CoreLocation.framework/CoreLocation", RTLD_NOW);
                LocationManagerClass = objc_getClass("CLLocationManager");
            }
            if (LocationManagerClass) {
                if ([LocationManagerClass respondsToSelector:@selector(setLocationServicesEnabled:)]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(LocationManagerClass, @selector(setLocationServicesEnabled:), state);
                    SRLog(@"Location Services set to: %d", state);
                } else if ([LocationManagerClass respondsToSelector:@selector(_setLocationServicesEnabled:)]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(LocationManagerClass, @selector(_setLocationServicesEnabled:), state);
                    SRLog(@"Location Services set to: %d via _setLocationServicesEnabled", state);
                } else {
                    SRLog(@"CLLocationManager does not respond to setLocationServicesEnabled:");
                }
            } else {
                SRLog(@"CLLocationManager class not found");
            }
        } @catch (NSException *e) {
            SRLog(@"EXCEPTION in toggle_location_services: %@", e);
        }
    });
}

static BOOL get_dnd_state() {
    Class ServiceClass = objc_getClass("DNDModeAssertionService");
    if (ServiceClass) {
        id service = [ServiceClass serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
        NSError *err = nil;
        id assertion = [service activeModeAssertionWithError:&err];
        return (assertion != nil);
    }
    return NO;
}

typedef struct __CTServerConnection *CTServerConnectionRef;
typedef CTServerConnectionRef (*CTServerConnectionCreateType)(CFAllocatorRef, void *, int *);
typedef int (*CTServerConnectionGetCellularDataIsEnabledType)(CTServerConnectionRef, uint8_t *);
typedef int (*CTServerConnectionSetCellularDataIsEnabledType)(CTServerConnectionRef, uint8_t);

static BOOL get_cellular_state() {
    BOOL isEnabled = NO;
    id telephonyManager = [(id)objc_getClass("SBTelephonyManager") sharedTelephonyManager];
    if (telephonyManager) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        SEL connSel = @selector(_serverConnection);
        if ([telephonyManager respondsToSelector:connSel]) {
            CTServerConnectionRef conn = (__bridge CTServerConnectionRef)[telephonyManager performSelector:connSel];
            if (conn) {
                void *ctHandle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
                if (ctHandle) {
                    CTServerConnectionGetCellularDataIsEnabledType getFunc = (CTServerConnectionGetCellularDataIsEnabledType)dlsym(ctHandle, "_CTServerConnectionGetCellularDataIsEnabled");
                    if (getFunc) {
                        uint8_t enabled = 0;
                        getFunc(conn, &enabled);
                        isEnabled = (enabled != 0);
                    }
                    dlclose(ctHandle);
                }
            }
        }
        #pragma clang diagnostic pop
    }
    return isEnabled;
}

static BOOL set_cellular_state(BOOL state) {
    BOOL success = NO;
    id telephonyManager = [(id)objc_getClass("SBTelephonyManager") sharedTelephonyManager];
    if (telephonyManager) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        SEL connSel = @selector(_serverConnection);
        if ([telephonyManager respondsToSelector:connSel]) {
            CTServerConnectionRef conn = (__bridge CTServerConnectionRef)[telephonyManager performSelector:connSel];
            if (conn) {
                void *ctHandle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
                if (ctHandle) {
                    CTServerConnectionSetCellularDataIsEnabledType setFunc = (CTServerConnectionSetCellularDataIsEnabledType)dlsym(ctHandle, "_CTServerConnectionSetCellularDataIsEnabled");
                    if (setFunc) {
                        setFunc(conn, state ? 1 : 0);
                        success = YES;
                    }
                    dlclose(ctHandle);
                }
            }
        }
        #pragma clang diagnostic pop
    }
    return success;
}

static UIWindow *g_rcHUDWindow = nil;

static NSArray<NSString *> *rc_parse_quoted_arguments(NSString *argString) {
    NSMutableArray *arguments = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:argString];
    [scanner setCharactersToBeSkipped:nil]; // Do not skip whitespace automatically
    
    while (![scanner isAtEnd]) {
        // Skip whitespace
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
        if ([scanner isAtEnd]) break;
        
        NSString *arg = nil;
        if ([scanner scanString:@"\"" intoString:NULL]) {
            // Scan until closing quote
            [scanner scanUpToString:@"\"" intoString:&arg];
            [scanner scanString:@"\"" intoString:NULL];
            if (!arg) arg = @"";
        } else {
            // Scan until next space
            [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&arg];
        }
        
        if (arg) {
            [arguments addObject:arg];
        }
    }
    return arguments;
}

static void rc_show_hud_toast(NSString *title, NSString *subtitle, NSString *iconSymbol) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_rcHUDWindow) {
            [g_rcHUDWindow.layer removeAllAnimations];
            g_rcHUDWindow.hidden = YES;
            g_rcHUDWindow = nil;
        }
        
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat screenWidth = screenBounds.size.width;
        
        // Define fonts matching native iOS 15 Ringer HUD
        UIFont *titleFont = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        UIFont *subtitleFont = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
        
        // Measure text to determine dynamic width
        CGFloat maxTextWidth = 0;
        if (title) {
            CGSize titleSize = [title sizeWithAttributes:@{NSFontAttributeName: titleFont}];
            maxTextWidth = titleSize.width;
        }
        if (subtitle) {
            CGSize subSize = [subtitle sizeWithAttributes:@{NSFontAttributeName: subtitleFont}];
            if (subSize.width > maxTextWidth) {
                maxTextWidth = subSize.width;
            }
        }
        
        // Check if icon exists and is a valid symbol image
        BOOL hasIcon = NO;
        if (iconSymbol && ![iconSymbol isEqualToString:@""] && ![iconSymbol isEqualToString:@"none"]) {
            if ([UIImage systemImageNamed:iconSymbol]) {
                hasIcon = YES;
            }
        }
        
        CGFloat leftPadding = 16.0;
        CGFloat iconWidth = hasIcon ? 20.0 : 0.0;
        CGFloat iconGap = hasIcon ? 10.0 : 0.0;
        CGFloat leftMargin = leftPadding + iconWidth + iconGap;
        
        CGFloat pillWidth = maxTextWidth + 2 * leftMargin;
        // Enforce native-looking bounds (min 140, max screenWidth - 32)
        pillWidth = MAX(140.0, MIN(pillWidth, screenWidth - 32.0));
        
        // Determine height based on whether we have a subtitle
        BOOL hasSubtitle = (subtitle && ![subtitle isEqualToString:@""]);
        CGFloat pillHeight = hasSubtitle ? 50.0 : 40.0;
        
        CGFloat pillX = (screenWidth - pillWidth) / 2.0;
        CGFloat startY = -pillHeight - 20.0;
        
        // Query status bar height for target Y
        CGFloat statusBarHeight = 20.0;
        if (@available(iOS 13.0, *)) {
            UIWindow *keyWin = nil;
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWin = [UIApplication sharedApplication].keyWindow;
            #pragma clang diagnostic pop
            if (keyWin && keyWin.windowScene && keyWin.windowScene.statusBarManager) {
                statusBarHeight = keyWin.windowScene.statusBarManager.statusBarFrame.size.height;
            }
        }
        if (statusBarHeight == 0) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            statusBarHeight = [UIApplication sharedApplication].statusBarFrame.size.height;
            #pragma clang diagnostic pop
        }
        
        // targetY places it right in status bar overlay position (matching native iOS ringer HUD)
        CGFloat targetY = (statusBarHeight > 24.0) ? 15.0 : 12.0;
        
        UIWindow *hudWindow = [[UIWindow alloc] initWithFrame:CGRectMake(pillX, startY, pillWidth, pillHeight)];
        g_rcHUDWindow = hudWindow;
        hudWindow.windowLevel = UIWindowLevelAlert + 3000.0;
        hudWindow.backgroundColor = [UIColor clearColor];
        hudWindow.userInteractionEnabled = NO;
        
        UIViewController *rootVC = [[UIViewController alloc] init];
        rootVC.view.frame = CGRectMake(0, 0, pillWidth, pillHeight);
        rootVC.view.backgroundColor = [UIColor clearColor];
        hudWindow.rootViewController = rootVC;
        
        BOOL isDarkMode = YES;
        if (@available(iOS 12.0, *)) {
            if ([UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) {
                isDarkMode = NO;
            }
        }
        
        UIBlurEffectStyle blurStyle = isDarkMode ? UIBlurEffectStyleSystemMaterialDark : UIBlurEffectStyleSystemMaterialLight;
        UIColor *titleColor = isDarkMode ? [UIColor whiteColor] : [UIColor colorWithWhite:0.0 alpha:0.8];
        UIColor *subColor = isDarkMode ? [UIColor colorWithWhite:1.0 alpha:0.6] : [UIColor colorWithWhite:0.0 alpha:0.48];
        UIColor *iconColor = isDarkMode ? [UIColor whiteColor] : [UIColor colorWithWhite:0.0 alpha:0.7];
        
        // Blur background (matching native ringer HUD pill - no border)
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        blurView.frame = CGRectMake(0, 0, pillWidth, pillHeight);
        blurView.layer.cornerRadius = pillHeight / 2.0;
        blurView.layer.masksToBounds = YES;
        [rootVC.view addSubview:blurView];
        
        if (hasIcon) {
            UIImage *iconImage = nil;
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
                iconImage = [UIImage systemImageNamed:iconSymbol withConfiguration:config];
            } else {
                iconImage = [UIImage systemImageNamed:iconSymbol];
            }
            
            if (iconImage) {
                UIImageView *iconView = [[UIImageView alloc] initWithImage:iconImage];
                iconView.tintColor = iconColor;
                iconView.contentMode = UIViewContentModeScaleAspectFit;
                iconView.frame = CGRectMake(leftPadding, (pillHeight - 20) / 2.0, 20, 20);
                [rootVC.view addSubview:iconView];
            }
        }
        
        // Text alignment: Center relative to the entire bubble
        NSTextAlignment alignment = NSTextAlignmentCenter;
        
        if (hasSubtitle) {
            UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 8.0, pillWidth, 18.0)];
            titleLabel.text = title;
            titleLabel.textColor = titleColor;
            titleLabel.font = titleFont;
            titleLabel.textAlignment = alignment;
            [rootVC.view addSubview:titleLabel];
            
            UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 26.0, pillWidth, 16.0)];
            subLabel.text = subtitle;
            subLabel.textColor = subColor;
            subLabel.font = subtitleFont;
            subLabel.textAlignment = alignment;
            [rootVC.view addSubview:subLabel];
        } else {
            UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, pillWidth, pillHeight)];
            titleLabel.text = title;
            titleLabel.textColor = titleColor;
            titleLabel.font = titleFont;
            titleLabel.textAlignment = alignment;
            [rootVC.view addSubview:titleLabel];
        }
        
        hudWindow.hidden = NO;
        
        [UIView animateWithDuration:0.5
                              delay:0.0
             usingSpringWithDamping:0.75
              initialSpringVelocity:1.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
                             hudWindow.frame = CGRectMake(pillX, targetY, pillWidth, pillHeight);
                         }
                         completion:^(BOOL finished) {
                             if (g_rcHUDWindow != hudWindow) {
                                 hudWindow.hidden = YES;
                                 return;
                             }
                             [UIView animateWithDuration:0.4
                                                   delay:2.0
                                                 options:UIViewAnimationOptionCurveEaseInOut
                                              animations:^{
                                                  hudWindow.frame = CGRectMake(pillX, startY, pillWidth, pillHeight);
                                              }
                                              completion:^(BOOL finished2) {
                                                  hudWindow.hidden = YES;
                                                  if (g_rcHUDWindow == hudWindow) {
                                                      g_rcHUDWindow = nil;
                                                  }
                                              }];
                         }];
    });
}

static void toggle_audiomix(BOOL state) {
    @try {
        CFStringRef appID = CFSTR("com.kingpuffdaddi.audiomixprefs");
        CFPreferencesSetAppValue(CFSTR("isEnabled"), (__bridge CFNumberRef)@(state), appID);
        CFPreferencesAppSynchronize(appID);

        // Write directly to plist file paths as fallback/synchronization
        NSString *prefix = @"";
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/nc"]) {
            prefix = @"/var/jb";
        }
        NSArray *paths = @[
            @"/var/mobile/Library/Preferences/com.kingpuffdaddi.audiomixprefs.plist",
            [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/com.kingpuffdaddi.audiomixprefs.plist", prefix]
        ];
        for (NSString *path in paths) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path];
            if (!dict) {
                dict = [NSMutableDictionary dictionary];
            }
            dict[@"isEnabled"] = @(state);
            [dict writeToFile:path atomically:YES];
        }

        // Post Darwin notification
        notify_post("com.kingpuffdaddi.audiomixprefs/settingschanged");

        SRLog(@"AudioMix Enabled toggled to: %@", state ? @"YES" : @"NO");

        rc_show_hud_toast(@"AudioMix", state ? @"Enabled" : @"Disabled", @"music.note");
    } @catch (NSException *e) {
        SRLog(@"EXCEPTION in toggle_audiomix: %@", e);
    }
}

static BOOL get_audiomix_state() {
    @try {
        Boolean valid;
        Boolean val = CFPreferencesGetAppBooleanValue(CFSTR("isEnabled"), CFSTR("com.kingpuffdaddi.audiomixprefs"), &valid);
        if (valid) return val;

        // Fallback to reading file
        NSString *prefix = @"";
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/nc"]) {
            prefix = @"/var/jb";
        }
        NSArray *paths = @[
            @"/var/mobile/Library/Preferences/com.kingpuffdaddi.audiomixprefs.plist",
            [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/com.kingpuffdaddi.audiomixprefs.plist", prefix]
        ];
        for (NSString *path in paths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
                if (dict && dict[@"isEnabled"]) {
                    return [dict[@"isEnabled"] boolValue];
                }
            }
        }
    } @catch (NSException *e) {
        SRLog(@"EXCEPTION in get_audiomix_state: %@", e);
    }
    return YES; // Default to YES if not found/error
}

static void inject_hid_event(uint32_t page, uint32_t usage, uint64_t durationNs, IOOptionBits flags) {
    static dispatch_queue_t hidQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hidQueue = dispatch_queue_create("com.pizzaman.remotecommand.hid", DISPATCH_QUEUE_SERIAL);
        void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (handle) {
            _IOHIDEventSystemClientCreate = (IOHIDEventSystemClientRef (*)(CFAllocatorRef))dlsym(handle, "IOHIDEventSystemClientCreate");
            _IOHIDEventCreateKeyboardEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateKeyboardEvent");
            _IOHIDEventSystemClientDispatchEvent = (void (*)(IOHIDEventSystemClientRef, IOHIDEventRef))dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
            
            // Touch/Digitizer symbols
            _IOHIDEventCreateDigitizerEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateDigitizerEvent");
            _IOHIDEventCreateDigitizerFingerEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
            _IOHIDEventAppendEvent = (void (*)(IOHIDEventRef, IOHIDEventRef, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventAppendEvent");
            _IOHIDEventSetIntegerValue = (void (*)(IOHIDEventRef, uint32_t, int32_t))dlsym(handle, "IOHIDEventSetIntegerValue");
            _IOHIDEventSetSenderID = (void (*)(IOHIDEventRef, uint64_t))dlsym(handle, "IOHIDEventSetSenderID");
        }
    });

    dispatch_async(hidQueue, ^{
        IOHIDEventSystemClientRef client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!client) {
            SRLog(@"ERROR: Could not create HID event system client");
            return;
        }

        uint64_t now = mach_absolute_time();
        
        // Key Down
        IOHIDEventRef eventDown = _IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, now, page, usage, true, flags);
        if (eventDown) {
            _IOHIDEventSystemClientDispatchEvent(client, eventDown);
            CFRelease(eventDown);
        }
        
        // Wait for usage duration
        uint64_t waitNs = (durationNs == 0) ? 50000000 : durationNs; // Default 50ms
        usleep((useconds_t)(waitNs / 1000));
        
        uint64_t later = mach_absolute_time();
        
        // Key Up
        IOHIDEventRef eventUp = _IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, later, page, usage, false, flags);
        if (eventUp) {
            _IOHIDEventSystemClientDispatchEvent(client, eventUp);
            CFRelease(eventUp);
        }
        
        if (client) CFRelease(client);
    });
}

static void toggle_system_vibration(BOOL silentMode, BOOL enable) {
    NSString *key = silentMode ? @"silent-vibrate" : @"ring-vibrate";
    CFStringRef appID = CFSTR("com.apple.springboard");
    
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFNumberRef)@(enable), appID);
    CFPreferencesAppSynchronize(appID);
    
    // Notify SpringBoard to reload prefs
    notify_post("com.apple.springboard.silent-vibrate.changed");
    notify_post("com.apple.springboard.ring-vibrate.changed");
    
    SRLog(@"Set system vibration (%@) to: %@", key, enable ? @"YES" : @"NO");
}

static BOOL get_system_vibration(BOOL silentMode) {
    NSString *key = silentMode ? @"silent-vibrate" : @"ring-vibrate";
    Boolean valid;
    Boolean val = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, CFSTR("com.apple.springboard"), &valid);
    if (!valid) return YES;
    return val;
}

// Helper to detect rootless vs rootful
static NSString* root_prefix() {
    static NSString *prefix = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
            prefix = @"/var/jb";
        } else {
            prefix = @"";
        }
    });
    return prefix;
}

// Helper to inject a HID Consumer Page event (wrapper)
static void inject_consumer_key(int usage) {
    inject_hid_event(kHIDPage_Consumer, usage, 50000000, 0); // 50ms hold
}


static void simulate_home_press() {
    dispatch_async(dispatch_get_main_queue(), ^{
        SRLog(@"Executing Home simulation...");
        
        // 1. Try SBUIController (Modern Home Tap)
        id uiCtrl = [objc_getClass("SBUIController") sharedInstance];
        if ([uiCtrl respondsToSelector:@selector(handleHomeButtonTap)]) {
            [uiCtrl handleHomeButtonTap];
            SRLog(@"Triggered handleHomeButtonTap");
        } else if ([uiCtrl respondsToSelector:@selector(handleHomeButtonTap:)]) {
            [uiCtrl handleHomeButtonTap:nil];
            SRLog(@"Triggered handleHomeButtonTap:");
        } else if ([uiCtrl respondsToSelector:@selector(clickedMenuButton)]) {
            [uiCtrl clickedMenuButton];
            SRLog(@"Triggered clickedMenuButton");
        }
        
        // 2. Fallback: SpringBoard simulation
        SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
        if ([sb respondsToSelector:@selector(_simulateHomeButtonPress)]) {
            [sb _simulateHomeButtonPress];
            SRLog(@"Triggered _simulateHomeButtonPress");
        } else if ([sb respondsToSelector:@selector(_menuButtonDown:)]) {
            [sb _menuButtonDown:nil];
            [sb _menuButtonUp:nil];
            SRLog(@"Triggered _menuButtonDown/Up");
        }
        
        // 3. HID Event (Last resort)
        inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Menu, 50000000, 0);
    });
}

// MediaRemote Helper Declarations
typedef void (^MRMediaRemoteGetNowPlayingApplicationPIDCompletion)(int pid);
extern void MRMediaRemoteGetNowPlayingApplicationPID(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationPIDCompletion completion);

typedef void (^MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion)(Boolean isPlaying);
extern void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion completion);
        

// Maps ASCII characters to HID usage codes
static void type_character(char c) {
    uint32_t usage = 0;
    IOOptionBits flags = 0; // 0x20000 = Shift (kIOHIDEventOptionIsShift not always available, but 131072 is standard)
    
    // Usage ID ref: https://usb.org/sites/default/files/hut1_2.pdf
    if (c >= 'a' && c <= 'z') { usage = 0x04 + (c - 'a'); } // a-z
    else if (c >= 'A' && c <= 'Z') { usage = 0x04 + (c - 'A'); flags = 0x20000; } // A-Z (Shift)
    else if (c >= '1' && c <= '9') { usage = 0x1E + (c - '1'); } // 1-9
    else if (c == '0') { usage = 0x27; }
    else if (c == '!') { usage = 0x1E; flags = 0x20000; } // Shift+1
    else if (c == '@') { usage = 0x1F; flags = 0x20000; } // Shift+2
    else if (c == '#') { usage = 0x20; flags = 0x20000; } // Shift+3
    else if (c == '$') { usage = 0x21; flags = 0x20000; } // Shift+4
    else if (c == '%') { usage = 0x22; flags = 0x20000; } // Shift+5
    else if (c == '^') { usage = 0x23; flags = 0x20000; } // Shift+6
    else if (c == '&') { usage = 0x24; flags = 0x20000; } // Shift+7
    else if (c == '*') { usage = 0x25; flags = 0x20000; } // Shift+8
    else if (c == '(') { usage = 0x26; flags = 0x20000; } // Shift+9
    else if (c == ')') { usage = 0x27; flags = 0x20000; } // Shift+0
    
    else if (c == ' ') usage = 0x2C; // Space
    else if (c == '\n' || c == '\r') usage = 0x28; // Enter
    else if (c == '-') usage = 0x2D; // Hyphen
    else if (c == '_') { usage = 0x2D; flags = 0x20000; } // Shift+Hyphen
    else if (c == '=') usage = 0x2E; // Equal
    else if (c == '+') { usage = 0x2E; flags = 0x20000; } // Shift+Equal
    else if (c == '[') usage = 0x2F;
    else if (c == '{') { usage = 0x2F; flags = 0x20000; }
    else if (c == ']') usage = 0x30;
    else if (c == '}') { usage = 0x30; flags = 0x20000; }
    else if (c == '\\') usage = 0x31;
    else if (c == '|') { usage = 0x31; flags = 0x20000; }
    else if (c == ';') usage = 0x33;
    else if (c == ':') { usage = 0x33; flags = 0x20000; }
    else if (c == '\'') usage = 0x34;
    else if (c == '"') { usage = 0x34; flags = 0x20000; }
    else if (c == ',') usage = 0x36; // Comma
    else if (c == '<') { usage = 0x36; flags = 0x20000; }
    else if (c == '.') usage = 0x37; // Period
    else if (c == '>') { usage = 0x37; flags = 0x20000; }
    else if (c == '/') usage = 0x38; // Slash
    else if (c == '?') { usage = 0x38; flags = 0x20000; }
    
    if (usage != 0) {
        inject_hid_event(0x07, usage, 0, flags); 
    }
}

// Helper to map common names to Bundle IDs
static NSString *resolve_bundle_id(NSString *input) {
    if ([input containsString:@"."]) return input; // Already a bundle ID
    
    NSDictionary *map = @{
        @"youtube": @"com.google.ios.youtube",
        @"spotify": @"com.spotify.client",
        @"settings": @"com.apple.Preferences",
        @"safari": @"com.apple.mobilesafari",
        @"messages": @"com.apple.MobileSMS",
        @"imessage": @"com.apple.MobileSMS",
        @"home": @"com.apple.Home",
        @"photos": @"com.apple.mobileslideshow",
        @"camera": @"com.apple.camera",
        @"clock": @"com.apple.mobiletimer",
        @"maps": @"com.apple.Maps",
        @"calendar": @"com.apple.mobilecal",
        @"weather": @"com.apple.weather",
        @"notes": @"com.apple.mobilenotes",
        @"reminders": @"com.apple.reminders",
        @"appstore": @"com.apple.AppStore",
        @"mail": @"com.apple.mobilemail",
        @"music": @"com.apple.Music",
        @"phone": @"com.apple.mobilephone",
        @"stocks": @"com.apple.stocks",
        @"calculator": @"com.apple.calculator",
        @"tv": @"com.apple.tv",
        @"videos": @"com.apple.videos",
        @"wallet": @"com.apple.Passbook",
        @"watch": @"com.apple.Bridge",
        @"facetime": @"com.apple.facetime",
        @"files": @"com.apple.DocumentsApp"
    };
    
    NSString *mapped = map[[input lowercaseString]];
    return mapped ? mapped : input; // Return mapped ID or original input if not found
}

// IPC for RemoteCompanion app notifications (use Documents for TrollStore access)
#define kIPCPath @"/var/mobile/Documents/rc_notify.plist"
#define kNotifyName "com.pizzaman.show_banner"

static void send_notification(NSString *title, NSString *message, BOOL urgent) {
    NSDictionary *payload = @{
        @"title": title ?: @"RemoteCommand",
        @"message": message ?: @"",
        @"urgent": @(urgent)
    };
    [payload writeToFile:kIPCPath atomically:YES];
    
    // Post Darwin notification to wake companion app
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(kNotifyName),
        NULL, NULL, true);
    
    SRLog(@"Sent notification IPC: %@ - %@", title, message);
}

// ============ TRIGGER CONFIG SYSTEM ============
#define kTriggerConfigFilename @"rc_triggers.plist"
#define kTriggerConfigPath @"/var/mobile/Documents/rc_triggers.plist"
#define kConfigChangedNotification "com.pizzaman.rc.configchanged"

static NSDictionary *g_triggerConfig = nil;
static NSString *g_resolvedConfigPath = nil;

// Find config file - check shared path first, then search app containers
static NSString *find_config_path() {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // First try the shared path
    if ([fm fileExistsAtPath:kTriggerConfigPath]) {
        return kTriggerConfigPath;
    }
    
    // Search for RemoteCompanion app container
    NSString *containersPath = @"/var/mobile/Containers/Data/Application";
    NSArray *uuids = [fm contentsOfDirectoryAtPath:containersPath error:nil];
    
    for (NSString *uuid in uuids) {
        NSString *configPath = [NSString stringWithFormat:@"%@/%@/Documents/%@", 
                                containersPath, uuid, kTriggerConfigFilename];
        if ([fm fileExistsAtPath:configPath]) {
            SRLog(@"Found config in container: %@", configPath);
            return configPath;
        }
    }
    
    return nil;
}
// ============ BLACKLIST SYSTEM ============

static NSArray *g_blacklist = nil;
static NSTimeInterval g_lastBlacklistLoad = 0;

static void load_blacklist() {
    NSString *path = @"/var/mobile/Library/Preferences/com.saihgupr.remotecompanion.blacklist.plist";
    g_blacklist = [NSArray arrayWithContentsOfFile:path];
    if (!g_blacklist) {
        // Empty by default for new users
        g_blacklist = @[];
    }
    g_lastBlacklistLoad = [[NSDate date] timeIntervalSince1970];
}

static BOOL save_blacklist(NSArray *list) {
    NSString *path = @"/var/mobile/Library/Preferences/com.saihgupr.remotecompanion.blacklist.plist";
    g_blacklist = [list copy];
    g_lastBlacklistLoad = [[NSDate date] timeIntervalSince1970];
    return [g_blacklist writeToFile:path atomically:YES];
}

static BOOL RC_IsForegroundAppExcluded() {
    static BOOL cachedResult = NO;
    static NSTimeInterval lastCheck = 0;
    static NSString *lastBundleID = nil;
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastCheck < 0.5) {
        return cachedResult;
    }
    
    @autoreleasepool {
        // Reload blacklist every 10 seconds or if never loaded
        if (!g_blacklist || now - g_lastBlacklistLoad > 10.0) {
            load_blacklist();
        }

        __block NSString *frontBundleID = nil;
        void (^getBlock)(void) = ^{
            SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
            if (sb && [sb respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
                SBApplication *frontApp = [sb _accessibilityFrontMostApplication];
                frontBundleID = [frontApp bundleIdentifier];
            }
        };

        if ([NSThread isMainThread]) getBlock();
        else dispatch_sync(dispatch_get_main_queue(), getBlock);

        BOOL result = NO;
        if (frontBundleID) {
            if (![frontBundleID isEqualToString:lastBundleID]) {
                SRLog(@"Foreground App: %@", frontBundleID);
                lastBundleID = frontBundleID;
            }
            
            NSString *lowerID = [frontBundleID lowercaseString];
            for (NSString *excluded in g_blacklist) {
                if ([lowerID isEqualToString:[excluded lowercaseString]]) {
                    result = YES;
                    break;
                }
            }
        }
        
        lastCheck = now;
        cachedResult = result;
        return result;
    }
}

static NSString *get_human_name_for_trigger(NSString *key, NSDictionary *triggerData) {
    if (!key) return @"Unknown";
    
    // 1. Check for custom user-defined name first
    if ([triggerData isKindOfClass:[NSDictionary class]] && triggerData[@"name"]) {
        return triggerData[@"name"];
    }
    if ([triggerData isKindOfClass:[NSDictionary class]] && triggerData[@"title"]) {
        return triggerData[@"title"];
    }
    
    // 2. Built-in mappings
    static NSDictionary *builtInNames = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        builtInNames = @{
            @"shake": @"Shake Device",
            @"volume_up_hold": @"Volume Up Hold",
            @"volume_down_hold": @"Volume Down Hold",
            @"volume_both_press": @"Volume Up + Down (Both)",
            @"volume_up_then_down": @"Volume Up then Down",
            @"volume_down_then_up": @"Volume Down then Up",
            @"power_double_tap": @"Power Double-Tap",
            @"power_long_press": @"Power Long Press",
            @"power_triple_click": @"Power Triple Click",
            @"power_quadruple_click": @"Power Quadruple Click",
            @"power_volume_up": @"Power + Volume Up",
            @"power_volume_down": @"Power + Volume Down",
            @"trigger_statusbar_left_hold": @"Status Bar Left Hold",
            @"trigger_statusbar_center_hold": @"Status Bar Center Hold",
            @"trigger_statusbar_right_hold": @"Status Bar Right Hold",
            @"trigger_statusbar_swipe_left": @"Status Bar Swipe Left",
            @"trigger_statusbar_swipe_right": @"Status Bar Swipe Right",
            @"trigger_statusbar_double_tap": @"Status Bar Double Tap",
            @"trigger_home_triple_click": @"Home Button (Triple Click)",
            @"trigger_home_quadruple_click": @"Home Button (Quadruple Click)",
            @"trigger_home_double_click": @"Home Button (Double Click)",
            @"touchid_hold": @"Touch ID Hold (Rest Finger)",
            @"touchid_tap": @"Touch ID Single Tap",
            @"trigger_edge_left_swipe_up": @"Left Edge Swipe Up",
            @"trigger_edge_left_swipe_down": @"Left Edge Swipe Down",
            @"trigger_edge_right_swipe_up": @"Right Edge Swipe Up",
            @"trigger_edge_right_swipe_down": @"Right Edge Swipe Down",
            @"trigger_ringer_mute": @"Ringer Muted",
            @"trigger_ringer_unmute": @"Ringer Unmuted",
            @"trigger_ringer_toggle": @"Ringer Toggled",
            @"trigger_bottombar_swipe_left": @"Bottom Bar Swipe Left",
            @"trigger_bottombar_swipe_right": @"Bottom Bar Swipe Right"
        };
    });
    
    NSString *builtIn = builtInNames[key];
    if (builtIn) return builtIn;
    
    // 3. Prefix-based fallback
    if ([key hasPrefix:@"nfc_"]) return [NSString stringWithFormat:@"NFC Tag %@", [key substringFromIndex:4]];
    if ([key hasPrefix:@"wifi_connect_"]) return [NSString stringWithFormat:@"WiFi Connected: %@", [key substringFromIndex:13]];
    if ([key hasPrefix:@"wifi_disconnect_"]) return [NSString stringWithFormat:@"WiFi Disconnected: %@", [key substringFromIndex:16]];
    if ([key hasPrefix:@"bt_connect_"]) return [NSString stringWithFormat:@"Bluetooth Connected: %@", [key substringFromIndex:11]];
    if ([key hasPrefix:@"bt_disconnect_"]) return [NSString stringWithFormat:@"Bluetooth Disconnected: %@", [key substringFromIndex:14]];
    if ([key hasPrefix:@"app_launch_"]) return [NSString stringWithFormat:@"App Launched: %@", [key substringFromIndex:11]];
    if ([key hasPrefix:@"notif_"] || [key hasPrefix:@"notify_"]) return @"Notification Trigger";
    if ([key hasPrefix:@"sched_"]) return @"Scheduled Automation";
    
    return key;
}

static void load_trigger_config() {
    @autoreleasepool {
        // Find the config file
        NSString *path = find_config_path();
        
        if (path) {
            NSDictionary *newConfig = [NSDictionary dictionaryWithContentsOfFile:path];
            if (newConfig) {
                // Thread-safe update: replace the pointer
                g_triggerConfig = newConfig;
                g_resolvedConfigPath = path;
                SRLog(@"Loaded trigger config from %@: triggers=%lu",
                      path,
                      (unsigned long)[g_triggerConfig[@"triggers"] count]);
            } else {
                SRLog(@"Failed to parse config at %@", path);
            }
        } else {
            SRLog(@"No trigger config found at shared path or in app containers");
        }
    }
}

static void update_simulation_observers();

static float get_flash_brightness() {
    return 1.0f;
}

// Forward declarations for gesture management functions
static BOOL should_register_edge_gestures();
static void register_edge_gestures();
static void unregister_edge_gestures();
static void update_edge_gestures();
static void start_schedule_timer();
static void start_mqtt_subscriber();
static void stop_mqtt_subscriber();

static void config_changed_callback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    SRLog(@"Config changed notification received.");
    
    // Ensure config loading and UI/Gesture updates happen on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            SRLog(@"Reloading config on main thread...");
            load_trigger_config();
            SRLog(@"Config loaded. Updating simulation observers...");
            update_simulation_observers();
            SRLog(@"Simulation observers updated. Updating edge gestures...");
            update_edge_gestures(); 
            SRLog(@"Edge gestures updated. Checking schedule timer...");
            start_schedule_timer();
            SRLog(@"Checking MQTT subscriber...");
            start_mqtt_subscriber();
            SRLog(@"Config reload complete.");
        } @catch (NSException *e) {
            SRLog(@"CRITICAL ERROR in config_changed_callback: %@\nStack: %@", e, e.callStackSymbols);
        }
    });
}

static void save_trigger_config() {
    if (!g_triggerConfig) return;
    NSString *sharedPath = @"/var/mobile/Documents/rc_triggers.plist";
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:g_triggerConfig
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (data && !error) {
        // 1. Try atomic write to shared path
        BOOL success = [data writeToFile:sharedPath atomically:YES];
        if (!success) {
            // 2. Fallback to POSIX open/write
            int fd = open([sharedPath UTF8String], O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) {
                write(fd, [data bytes], [data length]);
                close(fd);
                success = YES;
                SRLog(@"[WebUI] Saved config to shared path via POSIX: %@", sharedPath);
            } else {
                SRLog(@"[WebUI] Failed to save to shared path (errno: %d)", errno);
            }
        } else {
            SRLog(@"[WebUI] Saved config to shared path: %@", sharedPath);
        }
        
        // 3. If we have a resolved container path, try saving there too
        if (g_resolvedConfigPath && ![g_resolvedConfigPath isEqualToString:sharedPath]) {
            [data writeToFile:g_resolvedConfigPath atomically:YES];
            SRLog(@"[WebUI] Also saved to container path: %@", g_resolvedConfigPath);
        }

        if (success) {
            notify_post("com.pizzaman.rc.configchanged");
        }
    } else {
        SRLog(@"[WebUI] Failed to serialize config: %@", error);
    }
    }

    static void register_config_observer() {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        config_changed_callback,
        CFSTR(kConfigChangedNotification),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    SRLog(@"Registered for config change notifications");
}

// ============ SIMULATION SYSTEM (for testing from app) ============
#define kSimulateNotificationPrefix "com.pizzaman.rc.simulate."

// Forward declaration
static NSString *handle_command(NSString *cmd);

static BOOL rc_is_if_action_item(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = [[((NSDictionary *)item)[@"type"] description] lowercaseString];
    return [type isEqualToString:@"if"];
}

static BOOL rc_is_else_action_item(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = [[((NSDictionary *)item)[@"type"] description] lowercaseString];
    return [type isEqualToString:@"else"];
}

static BOOL rc_is_else_if_action_item(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = [[((NSDictionary *)item)[@"type"] description] lowercaseString];
    return [type isEqualToString:@"else_if"];
}

static BOOL rc_is_end_if_action_item(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = [[((NSDictionary *)item)[@"type"] description] lowercaseString];
    return [type isEqualToString:@"end_if"] || [type isEqualToString:@"end"];
}



static NSString *rc_trimmed_uppercase_string(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
}

static NSString *rc_status_command_for_condition_key(NSString *conditionKey) {
    if (![conditionKey isKindOfClass:[NSString class]]) return nil;
    NSDictionary *map = @{
        @"lock": @"lock status",
        @"player": @"player status",
        @"wifi": @"wifi status",
        @"cellular": @"cell status",
        @"bluetooth": @"bluetooth status",
        @"airplane": @"airplane status",
        @"silent_vibration": @"vibration silent-status",
        @"ring_vibration": @"vibration ring-status",
        @"orientation": @"orientation status",
        @"location": @"location status",
        @"location_services": @"location status",
        @"gps": @"location status",
        @"screenrecord": @"screenrecord status",
        @"screen_recording": @"screenrecord status"
    };
    return map[conditionKey];
}

static NSString *rc_canonical_status_value_for_condition_key(NSString *conditionKey, NSString *statusOutput) {
    NSString *upper = rc_trimmed_uppercase_string(statusOutput);
    if (upper.length == 0) return nil;
    
    if ([conditionKey isEqualToString:@"lock"]) {
        if ([upper containsString:@"UNLOCKED"]) return @"UNLOCKED";
        if ([upper containsString:@"LOCKED"]) return @"LOCKED";
        return nil;
    }
    
    if ([conditionKey isEqualToString:@"player"]) {
        if ([upper containsString:@"PLAYING"]) return @"PLAYING";
        if ([upper containsString:@"PAUSED"]) return @"PAUSED";
        if ([upper containsString:@"STOPPED"]) return @"STOPPED";
        return nil;
    }
    
    if ([conditionKey isEqualToString:@"orientation"]) {
        if ([upper containsString:@"PORTRAIT"]) return @"PORTRAIT";
        if ([upper containsString:@"LANDSCAPE"]) return @"LANDSCAPE";
        return nil;
    }
    
    if ([conditionKey isEqualToString:@"screenrecord"] || [conditionKey isEqualToString:@"screen_recording"]) {
        if ([upper containsString:@"ACTIVE"]) return @"ACTIVE";
        if ([upper containsString:@"INACTIVE"]) return @"INACTIVE";
        if ([upper containsString:@"ON"]) return @"ACTIVE";
        if ([upper containsString:@"OFF"]) return @"INACTIVE";
        return nil;
    }
    
    if ([upper containsString:@" OFF"]) return @"OFF";
    if ([upper hasSuffix:@"OFF"]) return @"OFF";
    if ([upper containsString:@" ON"]) return @"ON";
    if ([upper hasSuffix:@"ON"]) return @"ON";
    
    return nil;
}

static NSInteger rc_parse_time_to_minutes(NSString *timeStr) {
    if (![timeStr isKindOfClass:[NSString class]] || timeStr.length == 0) return -1;
    
    NSString *clean = [[timeStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    BOOL isPM = [clean containsString:@"PM"];
    BOOL isAM = [clean containsString:@"AM"];
    
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789:"];
    NSMutableString *digitsAndColons = [NSMutableString string];
    for (NSUInteger i = 0; i < clean.length; i++) {
        unichar c = [clean characterAtIndex:i];
        if ([allowed characterIsMember:c]) {
            [digitsAndColons appendFormat:@"%C", c];
        }
    }
    
    NSArray *parts = [digitsAndColons componentsSeparatedByString:@":"];
    if (parts.count == 0 || [parts[0] length] == 0) return -1;
    
    NSInteger hour = [parts[0] integerValue];
    NSInteger min = (parts.count > 1) ? [parts[1] integerValue] : 0;
    
    if (isPM) {
        if (hour < 12) hour += 12;
    } else if (isAM) {
        if (hour == 12) hour = 0;
    }
    
    if (hour < 0) hour = 0;
    if (hour > 23) hour = 23;
    if (min < 0) min = 0;
    if (min > 59) min = 59;
    
    return hour * 60 + min;
}

static BOOL rc_is_current_time_in_range(NSString *rangeString) {
    if (![rangeString isKindOfClass:[NSString class]] || rangeString.length == 0) return NO;
    
    NSString *s = rangeString;
    s = [s stringByReplacingOccurrencesOfString:@"–" withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@"—" withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@" to " withString:@"-" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    s = [s stringByReplacingOccurrencesOfString:@" and " withString:@"-" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    s = [s stringByReplacingOccurrencesOfString:@"," withString:@"-"];
    
    NSArray *comps = [s componentsSeparatedByString:@"-"];
    if (comps.count < 2) return NO;
    
    NSInteger startMin = rc_parse_time_to_minutes(comps[0]);
    NSInteger endMin = rc_parse_time_to_minutes(comps[1]);
    if (startMin < 0 || endMin < 0) return NO;
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *nowComps = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
    NSInteger currentMin = nowComps.hour * 60 + nowComps.minute;
    
    if (startMin <= endMin) {
        return (currentMin >= startMin && currentMin <= endMin);
    } else {
        // Crosses midnight (e.g. 22:00 to 06:00)
        return (currentMin >= startMin || currentMin <= endMin);
    }
}

static BOOL rc_evaluate_if_condition(NSDictionary *ifAction) {
    if (![ifAction isKindOfClass:[NSDictionary class]]) return NO;
    
    NSString *conditionKey = ifAction[@"conditionKey"] ?: ifAction[@"conditionName"];
    NSString *expectedValue = rc_trimmed_uppercase_string(ifAction[@"expectedValue"] ?: ifAction[@"expected"] ?: ifAction[@"expectedLabel"]);
    
    if (conditionKey.length == 0) {
        // Backward compatibility for older formats where "condition" contained a command or key:value.
        NSString *legacyCondition = ifAction[@"condition"];
        if (legacyCondition.length == 0) return NO;
        NSRange colon = [legacyCondition rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            conditionKey = [legacyCondition substringToIndex:colon.location];
            NSString *rawExpected = [legacyCondition substringFromIndex:colon.location + 1];
            if ([conditionKey isEqualToString:@"time_between"] || [conditionKey isEqualToString:@"time"] || [conditionKey isEqualToString:@"time_range"] || [conditionKey isEqualToString:@"time_of_day"]) {
                return rc_is_current_time_in_range(rawExpected);
            }
            expectedValue = rc_trimmed_uppercase_string(rawExpected);
        } else {
            NSString *legacyOutput = handle_command(legacyCondition);
            NSString *legacyUpper = rc_trimmed_uppercase_string(legacyOutput);
            return [legacyUpper isEqualToString:@"YES"] ||
                   [legacyUpper isEqualToString:@"TRUE"] ||
                   [legacyUpper isEqualToString:@"1"] ||
                   [legacyUpper hasPrefix:@"ON"] ||
                   [legacyUpper hasPrefix:@"LOCKED"] ||
                   [legacyUpper hasPrefix:@"PLAYING"];
        }
    }
    
    if ([conditionKey isEqualToString:@"time_between"] || [conditionKey isEqualToString:@"time"] || [conditionKey isEqualToString:@"time_range"] || [conditionKey isEqualToString:@"time_of_day"]) {
        NSString *rawRange = ifAction[@"expectedValue"] ?: ifAction[@"expected"] ?: ifAction[@"expectedLabel"] ?: ifAction[@"expectedTitle"];
        if (rawRange.length == 0) return NO;
        return rc_is_current_time_in_range(rawRange);
    }
    
    if ([conditionKey isEqualToString:@"front_app"]) {
        NSString *expectedValue = ifAction[@"expectedValue"] ?: ifAction[@"expected"];
        if (expectedValue.length == 0) return NO;
        
        __block NSString *actualBundleId = nil;
        void (^getBlock)(void) = ^{
            SBApplication *frontApp = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication];
            actualBundleId = [frontApp bundleIdentifier];
        };
        
        if ([NSThread isMainThread]) getBlock();
        else dispatch_sync(dispatch_get_main_queue(), getBlock);
        
        return [actualBundleId isEqualToString:expectedValue];
    }
    
    if ([conditionKey isEqualToString:@"proximity"] || [conditionKey isEqualToString:@"pocket"] || [conditionKey isEqualToString:@"device_in_pocket"]) {
        NSString *statusOutput = handle_command(@"proximity");
        NSString *upperOutput = rc_trimmed_uppercase_string(statusOutput);
        BOOL isNear = ([upperOutput containsString:@"OBJECTINPROXIMITY=1"] || 
                       [upperOutput containsString:@"PROXIMITYSTATE=1"] || 
                       [upperOutput containsString:@"NEAR"]);
        
        BOOL expectedBool = [expectedValue isEqualToString:@"YES"] || 
                            [expectedValue isEqualToString:@"TRUE"] || 
                            [expectedValue isEqualToString:@"1"] || 
                            [expectedValue isEqualToString:@"NEAR"] || 
                            [expectedValue isEqualToString:@"ON"];
        return (isNear == expectedBool);
    }
    
    NSString *statusCommand = rc_status_command_for_condition_key(conditionKey);
    if (statusCommand.length == 0) return NO;
    
    NSString *statusOutput = handle_command(statusCommand);
    NSString *actualValue = rc_canonical_status_value_for_condition_key(conditionKey, statusOutput);
    if (actualValue.length == 0 || expectedValue.length == 0) return NO;
    
    return [actualValue isEqualToString:expectedValue];
}

static BOOL rc_is_action_item_disabled(id item) {
    if ([item isKindOfClass:[NSDictionary class]]) {
        id dis = ((NSDictionary *)item)[@"disabled"];
        if (dis && ([dis boolValue] || [dis isEqual:@1] || [[dis description] isEqualToString:@"1"])) {
            return YES;
        }
    }
    return NO;
}

static void rc_execute_action_sequence(NSArray *actions, NSString *triggerKey, BOOL simulationMode) {
    if (![actions isKindOfClass:[NSArray class]] || actions.count == 0) return;
    
    for (NSInteger idx = 0; idx < (NSInteger)actions.count; idx++) {
        id actionItem = actions[idx];

        if (rc_is_action_item_disabled(actionItem)) {
            SRLog(@"[%@] Skipping disabled action: %@", triggerKey, actionItem);
            continue;
        }
        
        if ([actionItem isKindOfClass:[NSString class]]) {
            NSString *action = (NSString *)actionItem;
            SRLog(@"[%@] -> %@", triggerKey, action);
            handle_command(action);
            usleep(simulationMode ? 50000 : 10000);
            continue;
        }
        
        if (![actionItem isKindOfClass:[NSDictionary class]]) {
            SRLog(@"[%@] Skipping unsupported action item: %@", triggerKey, actionItem);
            continue;
        }
        
        NSDictionary *dictAction = (NSDictionary *)actionItem;
        NSString *type = [[dictAction[@"type"] description] lowercaseString];
        
        if ([type isEqualToString:@"if"]) {
            BOOL shouldRunBlock = rc_evaluate_if_condition(dictAction);
            SRLog(@"[%@] If %@ == %@ -> %@", triggerKey, dictAction[@"conditionKey"], dictAction[@"expectedValue"], shouldRunBlock ? @"TRUE" : @"FALSE");
            
            if (shouldRunBlock) {
                // TRUE branch: just continue to next item. 
            } else {
                // FALSE branch: scan ahead at current nesting depth for next sibling branch (else_if, else, or end_if).
                NSInteger depth = 0;
                BOOL foundNextBranch = NO;
                for (NSInteger skipIdx = idx + 1; skipIdx < (NSInteger)actions.count; skipIdx++) {
                    id item = actions[skipIdx];
                    if (rc_is_if_action_item(item)) {
                        depth++;
                    } else if (rc_is_end_if_action_item(item)) {
                        depth--;
                        if (depth < 0) {
                            idx = skipIdx;
                            foundNextBranch = YES;
                            break;
                        }
                    } else if (depth == 0) {
                        if (rc_is_else_if_action_item(item)) {
                            NSDictionary *elseIfDict = (NSDictionary *)item;
                            BOOL elseIfVal = rc_evaluate_if_condition(elseIfDict);
                            SRLog(@"[%@] Else If %@ == %@ -> %@", triggerKey, elseIfDict[@"conditionKey"], elseIfDict[@"expectedValue"], elseIfVal ? @"TRUE" : @"FALSE");
                            if (elseIfVal) {
                                idx = skipIdx;
                                foundNextBranch = YES;
                                break;
                            }
                        } else if (rc_is_else_action_item(item)) {
                            idx = skipIdx;
                            foundNextBranch = YES;
                            break;
                        }
                    }
                }
                if (!foundNextBranch) {
                    SRLog(@"[%@] Missing End If marker; stopping action execution.", triggerKey);
                    break;
                }
            }
        } else if ([type isEqualToString:@"else"] || [type isEqualToString:@"else_if"]) {
            // If we reached an 'else' or 'else_if' directly, it means we were executing the TRUE branch of a preceding conditional.
            // Now we must skip the remaining branches (until the matching end_if).
            NSInteger depth = 1;
            for (NSInteger skipIdx = idx + 1; skipIdx < (NSInteger)actions.count; skipIdx++) {
                id item = actions[skipIdx];
                if (rc_is_if_action_item(item)) {
                    depth++;
                } else if (rc_is_end_if_action_item(item)) {
                    depth--;
                    if (depth == 0) {
                        idx = skipIdx;
                        break;
                    }
                }
            }
        } else if ([type isEqualToString:@"end_if"] || [type isEqualToString:@"end"]) {
            continue;
        } else {
            SRLog(@"[%@] Skipping unsupported dictionary action type: %@", triggerKey, type);
        }
    }
}

// Execute actions for simulation (bypasses master/enabled checks for testing)
static void execute_actions_for_simulation(NSString *triggerKey) {
    // Reload config to get fresh data
    load_trigger_config();
    
    if (!g_triggerConfig) {
        SRLog(@"SIMULATE: No trigger config loaded");
        return;
    }
    
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    NSDictionary *trigger = triggers[triggerKey];
    
    if (!trigger) {
        SRLog(@"SIMULATE: Trigger '%@' not found in config", triggerKey);
        return;
    }
    
    NSArray *actions = trigger[@"actions"];
    if (!actions || actions.count == 0) {
        SRLog(@"SIMULATE: No actions configured for '%@'", triggerKey);
        return;
    }
    
    SRLog(@"SIMULATE: Executing %lu actions for '%@'", (unsigned long)actions.count, triggerKey);
    rc_execute_action_sequence(actions, [NSString stringWithFormat:@"SIMULATE:%@", triggerKey], YES);
}

// Callback for simulation notifications
static void simulate_trigger_callback(CFNotificationCenterRef center, void *observer,
                                       CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    NSString *prefix = @kSimulateNotificationPrefix;
    
    if ([notificationName hasPrefix:prefix]) {
        NSString *triggerKey = [notificationName substringFromIndex:prefix.length];
        SRLog(@"[SIMULATE] Received request for trigger: %@", triggerKey);
        
        // Execute off-main so status checks using dispatch_sync(main) never deadlock.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            execute_actions_for_simulation(triggerKey);
        });
    }
}

static void update_simulation_observers() {
    @try {
        static NSMutableSet *g_registeredTriggers = nil;
        if (!g_registeredTriggers) g_registeredTriggers = [[NSMutableSet alloc] init];
        
        if (!g_triggerConfig) load_trigger_config();
        if (!g_triggerConfig) return;
        
        NSDictionary *triggers = g_triggerConfig[@"triggers"];
        int count = 0;
        for (NSString *key in triggers) {
            if (![g_registeredTriggers containsObject:key]) {
                NSString *notificationName = [NSString stringWithFormat:@"%s%@", kSimulateNotificationPrefix, key];
                CFNotificationCenterAddObserver(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    NULL,
                    simulate_trigger_callback,
                    (__bridge CFStringRef)notificationName,
                    NULL,
                    CFNotificationSuspensionBehaviorDeliverImmediately
                );
                [g_registeredTriggers addObject:key];
                count++;
            }
        }
        if (count > 0) {
            SRLog(@"Registered %d NEW simulation observers (Total: %lu)", count, (unsigned long)g_registeredTriggers.count);
        }
    } @catch (NSException *e) {
         SRLog(@"ERROR in update_simulation_observers: %@", e);
    }
}

static void register_simulation_observers() {
    update_simulation_observers();
}

// Execute all actions for a trigger
void RCExecuteTrigger(NSString *triggerKey) {
    // Check for foreground exclusions (Safety/Blacklist)
    if (RC_IsForegroundAppExcluded()) {
        SRLog(@"Triggers SUPPRESSED for frontmost application (Excluded/Blacklisted)");
        return;
    }

    if (!g_triggerConfig) {
        SRLog(@"Config missing, attempting to load...");
        load_trigger_config();
        if (!g_triggerConfig) {
            SRLog(@"ERROR: Could not load trigger config for '%@'", triggerKey);
            return;
        }
    }
    
    // Check master toggle
    if (![g_triggerConfig[@"masterEnabled"] boolValue]) {
        SRLog(@"Master toggle is OFF, skipping trigger '%@'", triggerKey);
        return;
    }
    
    id triggers = g_triggerConfig[@"triggers"];
    if (!triggers || ![triggers isKindOfClass:[NSDictionary class]]) {
        SRLog(@"ERROR: Triggers dictionary is missing or invalid");
        return;
    }
    
    id trigger = ((NSDictionary *)triggers)[triggerKey];
    if (!trigger || ![trigger isKindOfClass:[NSDictionary class]]) {
        SRLog(@"TRIGGER NOT FOUND or INVALID: '%@'", triggerKey);
        return;
    }
    
    if (![trigger[@"enabled"] boolValue]) {
        SRLog(@"Trigger '%@' is DISABLED in config", triggerKey);
        return;
    }
    
    NSArray *actions = trigger[@"actions"];
    if (!actions || actions.count == 0) {
        SRLog(@"No actions configured for '%@'", triggerKey);
        return;
    }
    
    SRLog(@"TRIGGER FIRED: '%@' -> Executing %lu actions", triggerKey, (unsigned long)actions.count);
    
    // Execute on background queue to allow for delays and blocking operations
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        rc_execute_action_sequence(actions, triggerKey, NO);
    });
}

// ============ SCHEDULING SYSTEM ============
static NSInteger g_lastScheduledCheckMinute = -1;
static dispatch_source_t g_scheduleTimer = nil;

static void stop_schedule_timer() {
    if (g_scheduleTimer) {
        dispatch_source_cancel(g_scheduleTimer);
        g_scheduleTimer = nil;
        SRLog(@"[Schedule] Timer stopped (No active schedules)");
    }
}

static void check_scheduled_triggers() {
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitWeekday) fromDate:now];
    
    NSInteger currentHour = components.hour;
    NSInteger currentMinute = components.minute;
    NSInteger currentWeekday = components.weekday;
    
    // Prevent double firing within the same minute
    if (g_lastScheduledCheckMinute == currentMinute) {
        return;
    }
    
    if (!g_triggerConfig) {
        load_trigger_config();
    }
    
    if (!g_triggerConfig) return;
    
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    for (NSString *key in triggers) {
        if ([key hasPrefix:@"sched_"]) {
            NSDictionary *trigger = triggers[key];
            if (![trigger[@"enabled"] boolValue]) continue;
            
            NSDictionary *sched = trigger[@"schedule"];
            if (!sched) continue;
            
            NSInteger schedHour = [sched[@"hour"] integerValue];
            NSInteger schedMinute = [sched[@"minute"] integerValue];
            NSArray *schedDays = sched[@"days"];
            
            if (schedHour == currentHour && schedMinute == currentMinute) {
                if ([schedDays containsObject:@(currentWeekday)]) {
                    SRLog(@"[Schedule] FIRE: %@", key);
                    RCExecuteTrigger(key);
                }
            }
        }
    }
    
    g_lastScheduledCheckMinute = currentMinute;
}

static void start_schedule_timer() {
    // Check if any scheduled triggers actually exist before starting
    if (!g_triggerConfig) load_trigger_config();
    if (!g_triggerConfig) return;

    BOOL hasSchedules = NO;
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    for (NSString *key in triggers) {
        if ([key hasPrefix:@"sched_"]) {
            NSDictionary *trigger = triggers[key];
            if ([trigger[@"enabled"] boolValue]) {
                hasSchedules = YES;
                break;
            }
        }
    }

    if (!hasSchedules) {
        stop_schedule_timer();
        return;
    }

    // If we already have a timer running, don't start a second one.
    // The self-correcting nature of the existing timer will pick up any config changes
    // on its next tick, or the manual reload will handle it.
    if (g_scheduleTimer) return;

    SRLog(@"[Schedule] Starting self-correcting background timer...");
    
    g_scheduleTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    
    // Define the scheduling logic
    __block void (^scheduleNext)(void) = ^ {
        if (!g_scheduleTimer) return;

        NSDate *now = [NSDate date];
        NSTimeInterval currentTime = [now timeIntervalSince1970];
        
        // Calculate the next minute boundary (e.g., if it's 1:00:10, target 1:01:00)
        NSTimeInterval nextMinute = ceil(currentTime / 60.0) * 60.0;
        
        // If we are extremely close to the next minute (due to processing time), target the minute after
        if (nextMinute - currentTime < 0.1) {
            nextMinute += 60.0;
        }
        
        // Add a tiny 100ms delay to ensure the system clock has definitely rolled over the minute
        NSTimeInterval delay = (nextMinute - currentTime) + 0.1;
        dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
        
        SRLog(@"[Schedule] Next precision check in %.2f seconds", delay);
        
        // Use DISPATCH_TIME_FOREVER for interval to make it a one-shot
        dispatch_source_set_timer(g_scheduleTimer, start, DISPATCH_TIME_FOREVER, 0.1 * NSEC_PER_SEC);
    };

    dispatch_source_set_event_handler(g_scheduleTimer, ^{
        check_scheduled_triggers();
        
        // Re-schedule itself for the next minute
        scheduleNext();
    });
    
    // Initial schedule
    scheduleNext();
    dispatch_resume(g_scheduleTimer);
}

// ============ MQTT BACKGROUND SUBSCRIBER ============
static int g_mqttSubscriberSock = -1;
static BOOL g_mqttSubscriberRunning = NO;
static dispatch_queue_t g_mqttSubscriberQueue = NULL;
static uint64_t g_mqttSubscriberGeneration = 0;

static void rc_mqtt_append_rem_len(NSMutableData *data, NSUInteger length) {
    do {
        uint8_t d = length % 128;
        length /= 128;
        if (length > 0) d |= 128;
        [data appendBytes:&d length:1];
    } while (length > 0);
}

static void rc_mqtt_append_utf8(NSMutableData *data, NSString *str) {
    if (!str) str = @"";
    NSData *strData = [str dataUsingEncoding:NSUTF8StringEncoding];
    uint16_t len = htons((uint16_t)strData.length);
    [data appendBytes:&len length:2];
    if (strData.length > 0) [data appendData:strData];
}

static void stop_mqtt_subscriber() {
    g_mqttSubscriberGeneration++;
    if (g_mqttSubscriberSock >= 0) {
        shutdown(g_mqttSubscriberSock, SHUT_RDWR);
        close(g_mqttSubscriberSock);
        g_mqttSubscriberSock = -1;
    }
    g_mqttSubscriberRunning = NO;
}

static BOOL mqtt_topic_matches(NSString *subPattern, NSString *actualTopic) {
    if (!subPattern || !actualTopic) return NO;
    if ([subPattern isEqualToString:actualTopic] || [subPattern isEqualToString:@"#"]) return YES;
    
    NSArray *subParts = [subPattern componentsSeparatedByString:@"/"];
    NSArray *actualParts = [actualTopic componentsSeparatedByString:@"/"];
    
    NSUInteger i = 0;
    for (; i < subParts.count; i++) {
        NSString *sp = subParts[i];
        if ([sp isEqualToString:@"#"]) {
            return YES;
        }
        if (i >= actualParts.count) return NO;
        if (![sp isEqualToString:@"+"] && ![sp isEqualToString:actualParts[i]]) {
            return NO;
        }
    }
    return (i == actualParts.count);
}

static void start_mqtt_subscriber() {
    if (!g_triggerConfig) load_trigger_config();
    if (!g_triggerConfig) return;
    
    BOOL mqttEnabled = [g_triggerConfig[@"mqttEnabled"] boolValue];
    if (!mqttEnabled) {
        stop_mqtt_subscriber();
        return;
    }
    
    // Check if any active MQTT triggers exist
    NSMutableSet *subscribedTopics = [NSMutableSet set];
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    for (NSString *key in triggers) {
        if ([key hasPrefix:@"mqtt_sub_"] || [key hasPrefix:@"mqtt_"]) {
            NSDictionary *trig = triggers[key];
            if ([trig[@"enabled"] boolValue]) {
                NSString *topic = trig[@"topic"];
                if (topic.length > 0) {
                    [subscribedTopics addObject:topic];
                }
            }
        }
    }
    
    if (subscribedTopics.count == 0) {
        stop_mqtt_subscriber();
        return;
    }
    
    uint64_t currentGen = ++g_mqttSubscriberGeneration;
    
    if (g_mqttSubscriberSock >= 0) {
        shutdown(g_mqttSubscriberSock, SHUT_RDWR);
        close(g_mqttSubscriberSock);
        g_mqttSubscriberSock = -1;
    }
    
    if (!g_mqttSubscriberQueue) {
        g_mqttSubscriberQueue = dispatch_queue_create("com.pizzaman.rc.mqtt_sub", DISPATCH_QUEUE_SERIAL);
    }
    
    g_mqttSubscriberRunning = YES;
    
    NSString *host = g_triggerConfig[@"mqttHost"] ?: @"192.168.1.50";
    NSInteger port = [g_triggerConfig[@"mqttPort"] integerValue] > 0 ? [g_triggerConfig[@"mqttPort"] integerValue] : 1883;
    NSString *user = g_triggerConfig[@"mqttUser"];
    NSString *pass = g_triggerConfig[@"mqttPassword"];
    NSString *rawClientId = g_triggerConfig[@"mqttClientId"];
    NSString *clientId = rawClientId.length > 0 ? [NSString stringWithFormat:@"%@_sub", rawClientId] : @"RemoteCompanion_Sub";
    NSArray *topicsToSub = [subscribedTopics allObjects];
    
    dispatch_async(g_mqttSubscriberQueue, ^{
        while (g_mqttSubscriberRunning && currentGen == g_mqttSubscriberGeneration) {
            SRLog(@"[MQTT Sub] Connecting to %@:%ld...", host, (long)port);
            
            char portStr[16];
            snprintf(portStr, sizeof(portStr), "%ld", (long)port);
            
            struct addrinfo hints;
            memset(&hints, 0, sizeof(hints));
            hints.ai_family = AF_UNSPEC;
            hints.ai_socktype = SOCK_STREAM;
            hints.ai_protocol = IPPROTO_TCP;
            
            struct addrinfo *res = NULL;
            int gai_err = getaddrinfo([host UTF8String], portStr, &hints, &res);
            if (gai_err != 0 || !res) {
                SRLog(@"[MQTT Sub] Host resolve failed: %s. Retrying in 10s...", gai_strerror(gai_err));
                sleep(10);
                continue;
            }
            
            int sock = -1;
            for (struct addrinfo *rp = res; rp != NULL; rp = rp->ai_next) {
                sock = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
                if (sock == -1) continue;
                
                struct timeval tv = { 10, 0 };
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (const char *)&tv, sizeof(tv));
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (const char *)&tv, sizeof(tv));
                
                if (connect(sock, rp->ai_addr, rp->ai_addrlen) == 0) {
                    break;
                }
                close(sock);
                sock = -1;
            }
            freeaddrinfo(res);
            
            if (sock < 0 || currentGen != g_mqttSubscriberGeneration) {
                if (sock >= 0) close(sock);
                SRLog(@"[MQTT Sub] Connection failed. Retrying in 10s...");
                sleep(10);
                continue;
            }
            
            g_mqttSubscriberSock = sock;
            
            // Build CONNECT packet
            NSMutableData *varHeader = [NSMutableData data];
            uint16_t protoNameLen = htons(4);
            [varHeader appendBytes:&protoNameLen length:2];
            [varHeader appendBytes:"MQTT" length:4];
            uint8_t protoLevel = 4;
            [varHeader appendBytes:&protoLevel length:1];
            uint8_t connFlags = 0x02; // Clean session
            if (user.length > 0) connFlags |= 0x80;
            if (pass.length > 0) connFlags |= 0x40;
            [varHeader appendBytes:&connFlags length:1];
            uint16_t keepAlive = htons(60);
            [varHeader appendBytes:&keepAlive length:2];
            rc_mqtt_append_utf8(varHeader, clientId);
            if (user.length > 0) rc_mqtt_append_utf8(varHeader, user);
            if (pass.length > 0) rc_mqtt_append_utf8(varHeader, pass);
            
            NSMutableData *connPkt = [NSMutableData data];
            uint8_t connType = 0x10;
            [connPkt appendBytes:&connType length:1];
            rc_mqtt_append_rem_len(connPkt, varHeader.length);
            [connPkt appendData:varHeader];
            
            send(sock, connPkt.bytes, connPkt.length, 0);
            
            uint8_t connack[4];
            ssize_t n = recv(sock, connack, 4, 0);
            if (n < 4 || connack[0] != 0x20 || connack[3] != 0x00) {
                close(sock);
                g_mqttSubscriberSock = -1;
                SRLog(@"[MQTT Sub] Broker rejected connection. Retrying in 10s...");
                sleep(10);
                continue;
            }
            
            SRLog(@"[MQTT Sub] Connected! Subscribing to %lu topics...", (unsigned long)topicsToSub.count);
            
            // Send SUBSCRIBE packet for all configured topics
            NSMutableData *subPayload = [NSMutableData data];
            uint16_t packetId = htons(1);
            [subPayload appendBytes:&packetId length:2];
            for (NSString *t in topicsToSub) {
                rc_mqtt_append_utf8(subPayload, t);
                uint8_t qos = 0;
                [subPayload appendBytes:&qos length:1];
            }
            
            NSMutableData *subPkt = [NSMutableData data];
            uint8_t subType = 0x82; // SUBSCRIBE QoS 1
            [subPkt appendBytes:&subType length:1];
            rc_mqtt_append_rem_len(subPkt, subPayload.length);
            [subPkt appendData:subPayload];
            send(sock, subPkt.bytes, subPkt.length, 0);
            
            // Read SUBACK
            uint8_t suback[5];
            recv(sock, suback, sizeof(suback), 0);
            
            time_t lastPing = time(NULL);
            
            // Event loop: receive packets and send periodic keep-alive PINGREQ
            while (g_mqttSubscriberRunning && currentGen == g_mqttSubscriberGeneration) {
                uint8_t header[1];
                ssize_t r = recv(sock, header, 1, 0);
                if (r <= 0) {
                    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                        if (time(NULL) - lastPing >= 45) {
                            uint8_t pingreq[] = { 0xC0, 0x00 };
                            if (send(sock, pingreq, 2, 0) <= 0) {
                                break;
                            }
                            lastPing = time(NULL);
                        }
                        continue;
                    }
                    break;
                }
                
                uint8_t pktType = (header[0] >> 4) & 0x0F;
                
                NSUInteger remLen = 0;
                NSUInteger multiplier = 1;
                uint8_t digit = 0;
                do {
                    if (recv(sock, &digit, 1, 0) <= 0) break;
                    remLen += (digit & 127) * multiplier;
                    multiplier *= 128;
                } while ((digit & 128) != 0);
                
                if (pktType == 3) { // PUBLISH packet
                    NSMutableData *pktData = [NSMutableData data];
                    size_t bytesRead = 0;
                    while (bytesRead < remLen) {
                        char buf[1024];
                        size_t toRead = MIN(sizeof(buf), remLen - bytesRead);
                        ssize_t chunk = recv(sock, buf, toRead, 0);
                        if (chunk <= 0) break;
                        [pktData appendBytes:buf length:chunk];
                        bytesRead += chunk;
                    }
                    
                    if (pktData.length >= 2) {
                        const uint8_t *bytes = (const uint8_t *)pktData.bytes;
                        uint16_t tlen = (bytes[0] << 8) | bytes[1];
                        if (pktData.length >= 2 + tlen) {
                            NSString *inTopic = [[NSString alloc] initWithBytes:(bytes + 2) length:tlen encoding:NSUTF8StringEncoding];
                            size_t payloadOffset = 2 + tlen;
                            uint8_t qos = (header[0] >> 1) & 0x03;
                            if (qos > 0) payloadOffset += 2; // Skip Packet ID
                            
                            NSString *inPayload = @"";
                            if (pktData.length > payloadOffset) {
                                inPayload = [[NSString alloc] initWithBytes:(bytes + payloadOffset) length:(pktData.length - payloadOffset) encoding:NSUTF8StringEncoding] ?: @"";
                            }
                            
                            SRLog(@"[MQTT Sub] Received PUBLISH on '%@' (payload: '%@')", inTopic, inPayload);
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if (!g_triggerConfig) load_trigger_config();
                                NSDictionary *currentTriggers = g_triggerConfig[@"triggers"];
                                for (NSString *trigKey in currentTriggers) {
                                    if ([trigKey hasPrefix:@"mqtt_sub_"] || [trigKey hasPrefix:@"mqtt_"]) {
                                        NSDictionary *tDef = currentTriggers[trigKey];
                                        if ([tDef[@"enabled"] boolValue]) {
                                            NSString *pat = tDef[@"topic"];
                                            if (mqtt_topic_matches(pat, inTopic)) {
                                                NSString *matchPayload = tDef[@"matchPayload"];
                                                if (!matchPayload.length || [matchPayload isEqualToString:inPayload]) {
                                                    SRLog(@"[MQTT Sub] Triggering '%@' for topic '%@'", trigKey, inTopic);
                                                    RCExecuteTrigger(trigKey);
                                                }
                                            }
                                        }
                                    }
                                }
                            });
                        }
                    }
                } else if (pktType == 13) { // PINGRESP
                    lastPing = time(NULL);
                }
                
                if (time(NULL) - lastPing >= 45) {
                    uint8_t pingreq[] = { 0xC0, 0x00 };
                    if (send(sock, pingreq, 2, 0) <= 0) {
                        break;
                    }
                    lastPing = time(NULL);
                }
            }
            
            close(sock);
            g_mqttSubscriberSock = -1;
            
            if (g_mqttSubscriberRunning && currentGen == g_mqttSubscriberGeneration) {
                SRLog(@"[MQTT Sub] Connection lost. Reconnecting in 5s...");
                sleep(5);
            }
        }
    });
}

BOOL RCIsNFCEnabled() {
    if (!g_triggerConfig) {
        load_trigger_config();
    }
    // Default to YES if missing
    if (!g_triggerConfig[@"nfcEnabled"]) {
        return YES;
    }
    return [g_triggerConfig[@"nfcEnabled"] boolValue];
}

// ============ SYSTEM EVENT HANDLERS (WiFi/BT Triggers) ============
#import <notify.h>

static NSString *g_lastKnownSSID = nil;

static void handle_wifi_transition() {
    SBWiFiManager *wifiManager = [objc_getClass("SBWiFiManager") sharedInstance];
    NSString *currentSSID = [wifiManager currentNetworkName];
    
    SRLog(@"[RCWiFi] Transition detected. Current SSID: %@ (Previous: %@)", currentSSID, g_lastKnownSSID);
    
    if (currentSSID && ![currentSSID isEqualToString:g_lastKnownSSID]) {
        // Connected to a new network
        NSString *triggerKey = [NSString stringWithFormat:@"wifi_connect_%@", currentSSID];
        SRLog(@"[RCWiFi] Connection trigger: %@", triggerKey);
        RCExecuteTrigger(triggerKey);
    } else if (!currentSSID && g_lastKnownSSID) {
        // Disconnected from previous network
        NSString *triggerKey = [NSString stringWithFormat:@"wifi_disconnect_%@", g_lastKnownSSID];
        SRLog(@"[RCWiFi] Disconnection trigger: %@", triggerKey);
        RCExecuteTrigger(triggerKey);
    }
    
    g_lastKnownSSID = [currentSSID copy];
}

static void handle_bluetooth_transition(NSNotification *notification, BOOL connected) {
    BluetoothDevice *device = notification.object;
    if (![device isKindOfClass:objc_getClass("BluetoothDevice")]) return;
    
    NSString *address = [device address];
    NSString *name = [device name];
    SRLog(@"[RCBT] Device %@ (%@) %@", name, address, connected ? @"Connected" : @"Disconnected");
    
    // App now saves trigger keys by name not address!
    NSString *triggerKey = [NSString stringWithFormat:@"%@_%@", connected ? @"bt_connect" : @"bt_disconnect", name];
    RCExecuteTrigger(triggerKey);
}

static void handle_wifi_notification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        handle_wifi_transition();
    });
}

static BOOL is_sneakycam_installed() {
    NSArray *paths = @[
        @"/Library/MobileSubstrate/DynamicLibraries/SneakyCam.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/sneakycam.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/SneakyCam.plist",
        @"/Library/MobileSubstrate/DynamicLibraries/sneakycam.plist",
        @"/usr/lib/TweakInject/SneakyCam.dylib",
        @"/usr/lib/TweakInject/sneakycam.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/SneakyCam.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/sneakycam.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/SneakyCam.plist",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/sneakycam.plist",
        @"/var/jb/usr/lib/TweakInject/SneakyCam.dylib",
        @"/var/jb/usr/lib/TweakInject/sneakycam.dylib",
        @"/var/mobile/Library/Preferences/com.spark.sneakycam.plist",
        @"/var/mobile/Library/Preferences/com.spark.SneakyCam.plist",
        @"/var/jb/var/mobile/Library/Preferences/com.spark.sneakycam.plist"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) return YES;
    }
    return NO;
}

static BOOL is_snapper_installed() {
    NSArray *paths = @[
        @"/Library/MobileSubstrate/DynamicLibraries/Snapper3.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/snapper3.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/Snapper2.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/snapper2.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/Snapper3.plist",
        @"/Library/MobileSubstrate/DynamicLibraries/snapper3.plist",
        @"/Library/MobileSubstrate/DynamicLibraries/Snapper2.plist",
        @"/Library/MobileSubstrate/DynamicLibraries/snapper2.plist",
        @"/usr/lib/TweakInject/Snapper3.dylib",
        @"/usr/lib/TweakInject/snapper3.dylib",
        @"/usr/lib/TweakInject/Snapper2.dylib",
        @"/usr/lib/TweakInject/snapper2.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/Snapper3.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/snapper3.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/Snapper2.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/snapper2.dylib",
        @"/var/jb/usr/lib/TweakInject/Snapper3.dylib",
        @"/var/jb/usr/lib/TweakInject/snapper3.dylib",
        @"/var/jb/usr/lib/TweakInject/Snapper2.dylib",
        @"/var/jb/usr/lib/TweakInject/snapper2.dylib",
        @"/var/mobile/Library/Preferences/com.jontelang.snapper3preferences.plist",
        @"/var/jb/var/mobile/Library/Preferences/com.jontelang.snapper3preferences.plist",
        @"/var/mobile/Library/Preferences/com.jontelang.snapper2.plist",
        @"/var/jb/var/mobile/Library/Preferences/com.jontelang.snapper2.plist",
        @"/Library/PreferenceBundles/Snapper3Preferences.bundle",
        @"/var/jb/Library/PreferenceBundles/Snapper3Preferences.bundle"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) return YES;
    }
    return NO;
}

static BOOL is_audiostream_installed() {
    NSArray *paths = @[
        @"/Applications/AudioReceiver.app",
        @"/Applications/AudioStream.app",
        @"/var/jb/Applications/AudioReceiver.app",
        @"/var/jb/Applications/AudioStream.app"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) return YES;
    }
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (proxyClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:@"com.saihgupr.audiostream"];
        if (proxy) {
            NSString *name = [proxy performSelector:@selector(localizedName)];
            if (name.length > 0) return YES;
        }
#pragma clang diagnostic pop
    }
    return NO;
}

// Power State Globals & Helpers
static BOOL g_powerStateInitialized = NO;
static BOOL g_lastPowerConnectedState = NO;

static BOOL is_device_power_connected() {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
    if (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull) {
        return YES;
    }
    if (state == UIDeviceBatteryStateUnplugged) {
        return NO;
    }
    
    Class SBUIClass = objc_getClass("SBUIController");
    if (SBUIClass) {
        id uiCtrl = [SBUIClass respondsToSelector:@selector(sharedInstance)] ? [SBUIClass performSelector:@selector(sharedInstance)] : nil;
        if (uiCtrl) {
            if ([uiCtrl respondsToSelector:@selector(isACPowerConnected)]) {
                return [uiCtrl isACPowerConnected];
            } else if ([uiCtrl respondsToSelector:@selector(isOnAC)]) {
                return [uiCtrl isOnAC];
            }
        }
    }
    return NO;
}

static void initialize_power_state() {
    if (g_powerStateInitialized) return;
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    g_lastPowerConnectedState = is_device_power_connected();
    g_powerStateInitialized = YES;
    SRLog(@"⚡ [RCSystem] Power state successfully initialized to: %@", g_lastPowerConnectedState ? @"CONNECTED" : @"DISCONNECTED");
}

static void handle_power_state_transition(BOOL isConnected, NSString *source) {
    if (!g_powerStateInitialized) {
        initialize_power_state();
    }
    
    if (isConnected != g_lastPowerConnectedState) {
        g_lastPowerConnectedState = isConnected;
        if (isConnected) {
            SRLog(@"⚡ [RCSystem] Transition detected (%@): POWER CONNECTED. Executing trigger_power_connect.", source);
            RCExecuteTrigger(@"trigger_power_connect");
        } else {
            SRLog(@"⚡ [RCSystem] Transition detected (%@): POWER DISCONNECTED. Executing trigger_power_disconnect.", source);
            RCExecuteTrigger(@"trigger_power_disconnect");
        }
    }
}

static void handle_power_state_notification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notifName = (__bridge NSString *)name;
    SRLog(@"⚡ [RCSystem] Received Power State Notification: %@", notifName);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        handle_power_state_transition(is_device_power_connected(), @"Darwin Notification");
    });
}

// Biometric / Touch ID / Lock State Globals
static NSTimeInterval g_bioFingerDownTime = 0;
static BOOL g_bioHoldTriggered = NO;
static NSTimer *g_bioWatchdogTimer = nil;
static NSTimeInterval g_bioIgnoreUntil = 0;
static BOOL g_bioWasLocked = NO;
static BOOL g_lastLockedState = NO;
static BOOL g_lockStateInitialized = NO;

static void initialize_lock_state() {
    if (g_lockStateInitialized) return;
    
    Class LSMClass = objc_getClass("SBLockScreenManager");
    if (LSMClass) {
        SBLockScreenManager *lsm = [LSMClass sharedInstance];
        if (lsm) {
            g_lastLockedState = [lsm isUILocked];
            g_lockStateInitialized = YES;
            SRLog(@"🔒 [RCSystem] Lock state successfully initialized to: %@", g_lastLockedState ? @"LOCKED" : @"UNLOCKED");
        }
    }
}

static void handle_lock_state_transition(BOOL isLocked, NSString *source) {
    if (!g_lockStateInitialized) {
        initialize_lock_state();
        if (!g_lockStateInitialized) {
            g_lastLockedState = !isLocked; // Set opposite to force transition detection on fallback
            g_lockStateInitialized = YES;
            SRLog(@"🔒 [RCSystem] Lock state fallback initialized via %@ to: %@", source, g_lastLockedState ? @"LOCKED" : @"UNLOCKED");
        }
    }
    
    if (isLocked != g_lastLockedState) {
        g_lastLockedState = isLocked;
        if (isLocked) {
            SRLog(@"🔒 [RCSystem] Transition detected (%@): DEVICE LOCKED. Executing trigger_device_lock.", source);
            RCExecuteTrigger(@"trigger_device_lock");
        } else {
            SRLog(@"🔓 [RCSystem] Transition detected (%@): DEVICE UNLOCKED. Executing trigger_device_unlock.", source);
            RCExecuteTrigger(@"trigger_device_unlock");
            
            // Reset biometric / unlock-related side effects
            g_bioFingerDownTime = 0;
            g_bioHoldTriggered = NO;
            
            if (g_bioWatchdogTimer) {
                [g_bioWatchdogTimer invalidate];
                g_bioWatchdogTimer = nil;
                SRLog(@"🔐 [RCSystem] Cancelled pending Biometric trigger due to Unlock (%@)", source);
            }
            
            // Brief suppression after unlock (1.0s), without overwriting a larger existing suppression
            NSTimeInterval newIgnore = [[NSDate date] timeIntervalSince1970] + 1.0;
            if (g_bioIgnoreUntil < newIgnore) {
                g_bioIgnoreUntil = newIgnore;
            }
        }
    }
}

static void handle_lock_state_notification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class LSMClass = objc_getClass("SBLockScreenManager");
        if (!LSMClass) {
            SRLog(@"⚠️ [RCSystem] SBLockScreenManager class not found in notify handler");
            return;
        }
        
        SBLockScreenManager *lsm = [LSMClass sharedInstance];
        if (!lsm) {
            SRLog(@"⚠️ [RCSystem] SBLockScreenManager instance is nil in notify handler");
            return;
        }
        
        BOOL currentLocked = [lsm isUILocked];
        SRLog(@"🔒 [RCSystem] SBLockScreenManager.isUILocked = %@", currentLocked ? @"YES" : @"NO");
        handle_lock_state_transition(currentLocked, @"Darwin Notification");
    });
}

static BOOL g_mediaStateInitialized = NO;
static BOOL g_lastMediaPlayingState = NO;
static NSString *g_lastMediaTitle = nil;
static NSString *g_lastMediaArtist = nil;
static NSString *g_lastMediaBundleID = nil;

static void handle_media_state_change() {
    MRMediaRemoteGetNowPlayingClient(dispatch_get_main_queue(), ^(void *clientObj) {
        __block NSString *bundleID = @"";
        if (clientObj) {
            CFStringRef bundleIDRef = MRNowPlayingClientGetBundleIdentifier(clientObj);
            if (bundleIDRef) {
                bundleID = (__bridge NSString *)bundleIDRef;
            }
        }
        
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlayingNow) {
            MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
                NSDictionary *info = (__bridge NSDictionary *)information;
                NSString *title = info ? (info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle] ?: @"") : @"";
                NSString *artist = info ? (info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist] ?: @"") : @"";
                
                BOOL playingChanged = NO;
                BOOL trackChanged = NO;
                
                if (!g_mediaStateInitialized) {
                    g_lastMediaPlayingState = isPlayingNow;
                    g_lastMediaTitle = [title copy];
                    g_lastMediaArtist = [artist copy];
                    g_lastMediaBundleID = [bundleID copy];
                    g_mediaStateInitialized = YES;
                    SRLog(@"🎵 [RCSystem] Media state initialized: playing=%@, title='%@', artist='%@', bundleID='%@'", 
                          isPlayingNow ? @"YES" : @"NO", title, artist, bundleID);
                    return;
                }
                
                if (isPlayingNow != g_lastMediaPlayingState) {
                    playingChanged = YES;
                    g_lastMediaPlayingState = isPlayingNow;
                }
                
                if (![title isEqualToString:g_lastMediaTitle] || 
                    ![artist isEqualToString:g_lastMediaArtist] || 
                    ![bundleID isEqualToString:g_lastMediaBundleID]) {
                    trackChanged = YES;
                    g_lastMediaTitle = [title copy];
                    g_lastMediaArtist = [artist copy];
                    g_lastMediaBundleID = [bundleID copy];
                }
                
                if (playingChanged) {
                    if (isPlayingNow) {
                        SRLog(@"🎵 [RCSystem] Media Playback State -> PLAYING. Executing trigger_media_play.");
                        RCExecuteTrigger(@"trigger_media_play");
                    } else {
                        SRLog(@"🎵 [RCSystem] Media Playback State -> PAUSED. Executing trigger_media_pause.");
                        RCExecuteTrigger(@"trigger_media_pause");
                    }
                }
                
                if (trackChanged) {
                    SRLog(@"🎵 [RCSystem] Media Track Changed: %@ - %@ (%@). Executing trigger_media_track_change.", title, artist, bundleID);
                    RCExecuteTrigger(@"trigger_media_track_change");
                }
            });
        });
    });
}

static void handle_media_state_notification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notifName = (__bridge NSString *)name;
    SRLog(@"🎵 [RCSystem] Received Media State Notification: %@", notifName);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        handle_media_state_change();
    });
}

static void register_system_event_observers() {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    // Initialize initial lock state & power state
    initialize_lock_state();
    initialize_power_state();

    // Power State: Cocoa Touch observers
    [nc addObserverForName:UIDeviceBatteryStateDidChangeNotification 
                    object:nil 
                     queue:[NSOperationQueue mainQueue] 
                usingBlock:^(NSNotification *note) {
        handle_power_state_transition(is_device_power_connected(), @"UIDeviceBatteryStateDidChangeNotification");
    }];
    [nc addObserverForName:UIDeviceBatteryLevelDidChangeNotification 
                    object:nil 
                     queue:[NSOperationQueue mainQueue] 
                usingBlock:^(NSNotification *note) {
        handle_power_state_transition(is_device_power_connected(), @"UIDeviceBatteryLevelDidChangeNotification");
    }];

    // Power State: Darwin Notifications
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_power_state_notification, 
                                    CFSTR("com.apple.system.powersources.source"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_power_state_notification, 
                                    CFSTR("com.apple.system.powersources.timeremaining"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_power_state_notification, 
                                    CFSTR("com.apple.system.powersources.percent"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    // WiFi: Track network changes (Darwin Notification)
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_wifi_notification, 
                                    CFSTR("com.apple.system.config.network_change"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    
    // Device Lock / Unlock: Track screen transitions via Darwin Notifications
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_lock_state_notification, 
                                    CFSTR("com.apple.springboard.lockcomplete"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
                                    
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_lock_state_notification, 
                                    CFSTR("com.apple.springboard.lockstate"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    // Media State changes (Darwin Notifications)
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_media_state_notification, 
                                    CFSTR("com.apple.mediaremote.nowplayinginfochanged"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_media_state_notification, 
                                    CFSTR("com.apple.MediaRemote.nowPlayingApplicationIsPlayingDidChange"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    handle_media_state_notification, 
                                    CFSTR("com.apple.MediaRemote.nowPlayingApplicationPlaybackStateDidChange"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    // Initialize initial media state
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        handle_media_state_change();
    });

    // Bluetooth: Track connection/disconnection
    [nc addObserverForName:@"BluetoothDeviceConnectSuccessNotification" 
                    object:nil 
                     queue:[NSOperationQueue mainQueue] 
                usingBlock:^(NSNotification *note) {
        handle_bluetooth_transition(note, YES);
    }];
    
    [nc addObserverForName:@"BluetoothDeviceDisconnectSuccessNotification" 
                    object:nil 
                     queue:[NSOperationQueue mainQueue] 
                usingBlock:^(NSNotification *note) {
        handle_bluetooth_transition(note, NO);
    }];

    SRLog(@"[RCTweak] WiFi, Bluetooth and Media observers registered.");
}

// ============ LUA INTERPRETER ============

// ── Touch / Digitizer helper ──────────────────────────────────────────────────
// Dedicated serial queue for touch HID events (must NOT run on main thread).
static dispatch_queue_t rc_touch_queue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t qt;
    dispatch_once(&qt, ^{
        q = dispatch_queue_create("com.pizzaman.remotecommand.touch", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

// Ensures all IOHIDKit symbols needed for touch are loaded.
static void rc_load_touch_symbols(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_NOLOAD);
        if (!handle) handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (!handle) {
            SRLog(@"[Touch] Failed to open IOKit framework");
            return;
        }
        if (!_IOHIDEventSystemClientCreate)
            _IOHIDEventSystemClientCreate = (IOHIDEventSystemClientRef (*)(CFAllocatorRef))dlsym(handle, "IOHIDEventSystemClientCreate");
        if (!_IOHIDEventSystemClientDispatchEvent)
            _IOHIDEventSystemClientDispatchEvent = (void (*)(IOHIDEventSystemClientRef, IOHIDEventRef))dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
        if (!_IOHIDEventCreateDigitizerEvent)
            _IOHIDEventCreateDigitizerEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateDigitizerEvent");
        if (!_IOHIDEventCreateDigitizerFingerEvent)
            _IOHIDEventCreateDigitizerFingerEvent = (IOHIDEventRef (*)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
        if (!_IOHIDEventAppendEvent)
            _IOHIDEventAppendEvent = (void (*)(IOHIDEventRef, IOHIDEventRef, IOHIDEventOptionBits))dlsym(handle, "IOHIDEventAppendEvent");
        if (!_IOHIDEventSetIntegerValue)
            _IOHIDEventSetIntegerValue = (void (*)(IOHIDEventRef, uint32_t, int32_t))dlsym(handle, "IOHIDEventSetIntegerValue");
        if (!_IOHIDEventSetIntegerValueWithOptions)
            _IOHIDEventSetIntegerValueWithOptions = (void (*)(IOHIDEventRef, uint32_t, int32_t, uint32_t))dlsym(handle, "IOHIDEventSetIntegerValueWithOptions");
        if (!_IOHIDEventSetSenderID)
            _IOHIDEventSetSenderID = (void (*)(IOHIDEventRef, uint64_t))dlsym(handle, "IOHIDEventSetSenderID");
        SRLog(@"[Touch] IOHIDKit symbols loaded: create=%p dispatch=%p",
              _IOHIDEventCreateDigitizerEvent, _IOHIDEventSystemClientDispatchEvent);
    });
}

static void rc_dispatch_sync_main_safe(dispatch_block_t block);

static BOOL rc_is_springboard_context(uint32_t cid) {
    if (cid == 0) return NO;
    __block BOOL isSB = NO;
    rc_dispatch_sync_main_safe(^{
        if (g_rcTapTestWindow && !g_rcTapTestWindow.hidden) {
            if ([g_rcTapTestWindow _contextId] == cid) {
                isSB = YES;
                return;
            }
        }
        if (g_rcTapRecordWindow && !g_rcTapRecordWindow.hidden) {
            if ([g_rcTapRecordWindow _contextId] == cid) {
                isSB = YES;
                return;
            }
        }
        Class windowClass = NSClassFromString(@"UIWindow");
        if (windowClass && [windowClass respondsToSelector:@selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:)]) {
            NSArray *allWindows = [windowClass allWindowsIncludingInternalWindows:YES onlyVisibleWindows:YES];
            for (UIWindow *window in allWindows) {
                if ([window respondsToSelector:@selector(_contextId)]) {
                    if ([window _contextId] == cid) {
                        isSB = YES;
                        break;
                    }
                }
            }
        }
    });
    return isSB;
}

static uint64_t rc_get_digitizer_sender_id(void) {
    static uint64_t savedSenderID = 0;
    if (savedSenderID != 0) return savedSenderID;

    void *ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!ioKit) return 0xDEFACEDBEEFFECE5ULL;

    CFArrayRef (*copyServices)(IOHIDEventSystemClientRef) = (CFArrayRef (*)(IOHIDEventSystemClientRef))dlsym(ioKit, "IOHIDEventSystemClientCopyServices");
    CFTypeRef (*copyProperty)(id, CFStringRef) = (CFTypeRef (*)(id, CFStringRef))dlsym(ioKit, "IOHIDServiceClientCopyProperty");
    uint64_t (*getRegistryID)(id) = (uint64_t (*)(id))dlsym(ioKit, "IOHIDServiceClientGetRegistryID");

    if (!copyServices || !copyProperty || !getRegistryID) {
        return 0xDEFACEDBEEFFECE5ULL;
    }

    IOHIDEventSystemClientRef client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return 0xDEFACEDBEEFFECE5ULL;

    CFArrayRef services = copyServices(client);
    if (services) {
        CFIndex count = CFArrayGetCount(services);
        for (CFIndex i = 0; i < count; i++) {
            id service = (__bridge id)CFArrayGetValueAtIndex(services, i);
            CFTypeRef usagePageRef = copyProperty(service, CFSTR("PrimaryUsagePage"));
            CFTypeRef usageRef = copyProperty(service, CFSTR("PrimaryUsage"));

            if (usagePageRef && usageRef) {
                int usagePage = 0;
                int usage = 0;
                CFNumberGetValue((CFNumberRef)usagePageRef, kCFNumberIntType, &usagePage);
                CFNumberGetValue((CFNumberRef)usageRef, kCFNumberIntType, &usage);

                CFRelease(usagePageRef);
                CFRelease(usageRef);

                // Digitizer Usage Page = 0x0D (13), Touch Screen Usage = 0x04 (4)
                if (usagePage == 13 && usage == 4) {
                    uint64_t regID = getRegistryID(service);
                    if (regID != 0) {
                        savedSenderID = regID;
                        SRLog(@"[Touch] Dynamically resolved digitizer senderID: 0x%llX", regID);
                        break;
                    }
                }
            }
        }
        CFRelease(services);
    }
    CFRelease(client);

    if (savedSenderID == 0) {
        savedSenderID = 0xDEFACEDBEEFFECE5ULL; // Fallback
        SRLog(@"[Touch] Could not resolve digitizer senderID dynamically, using fallback: 0x%llX", savedSenderID);
    }
    return savedSenderID;
}

static uint32_t rc_resolve_target_context(double x, double y) {
    __block uint32_t contextID = 0;
    __block uint32_t testWindowContextID = 0;
    __block uint32_t recordWindowContextID = 0;
    rc_dispatch_sync_main_safe(^{
        if (g_rcTapTestWindow && !g_rcTapTestWindow.hidden) {
            testWindowContextID = [g_rcTapTestWindow _contextId];
            contextID = testWindowContextID;
        } else if (g_rcTapRecordWindow && !g_rcTapRecordWindow.hidden) {
            recordWindowContextID = [g_rcTapRecordWindow _contextId];
            contextID = recordWindowContextID;
        } else {
            // Resolve contextID via FBSceneManager from the frontmost application scene
            NSString *frontBundleID = nil;
            SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
            if (sb && [sb respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
                id frontApp = [sb _accessibilityFrontMostApplication];
                if (frontApp && [frontApp respondsToSelector:@selector(bundleIdentifier)]) {
                    frontBundleID = [frontApp bundleIdentifier];
                }
            }
            
            if (frontBundleID) {
                Class managerClass = NSClassFromString(@"FBSceneManager");
                id manager = nil;
                if (managerClass && [managerClass respondsToSelector:@selector(sharedInstance)]) {
                    manager = [managerClass performSelector:@selector(sharedInstance)];
                }
                
                if (manager) {
                    id workspace = nil;
                    @try {
                        workspace = [manager valueForKey:@"_workspace"];
                    } @catch (NSException *e) {}
                    
                    if (workspace) {
                        id scenes = nil;
                        if ([workspace respondsToSelector:@selector(scenes)]) {
                            scenes = [workspace performSelector:@selector(scenes)];
                        }
                        if (!scenes) {
                            @try { scenes = [workspace valueForKey:@"_scenes"]; } @catch (NSException *e) {}
                        }
                        if (!scenes) {
                            @try { scenes = [workspace valueForKey:@"_scenesByID"]; } @catch (NSException *e) {}
                        }
                        if (!scenes) {
                            @try { scenes = [workspace valueForKey:@"allScenes"]; } @catch (NSException *e) {}
                        }
                        
                        NSArray *sceneArray = nil;
                        if ([scenes isKindOfClass:[NSDictionary class]]) {
                            sceneArray = [scenes allValues];
                        } else if ([scenes isKindOfClass:[NSSet class]]) {
                            sceneArray = [scenes allObjects];
                        } else if ([scenes isKindOfClass:[NSArray class]]) {
                            sceneArray = scenes;
                        }
                        
                        for (id scene in sceneArray) {
                            @try {
                                id sceneID = nil;
                                if ([scene respondsToSelector:@selector(identifier)]) {
                                    sceneID = [scene performSelector:@selector(identifier)];
                                }
                                if (![sceneID isKindOfClass:[NSString class]]) {
                                    continue;
                                }
                                
                                // Check if the scene identifier contains the frontBundleID
                                if ([sceneID rangeOfString:frontBundleID options:NSCaseInsensitiveSearch].location != NSNotFound) {
                                    id layerManager = nil;
                                    if ([scene respondsToSelector:@selector(layerManager)]) {
                                        layerManager = [scene performSelector:@selector(layerManager)];
                                    }
                                    if (!layerManager) {
                                        @try { layerManager = [scene valueForKey:@"_layerManager"]; } @catch (NSException *e) {}
                                    }
                                    
                                    id layers = nil;
                                    if (layerManager && [layerManager respondsToSelector:@selector(layers)]) {
                                        layers = [layerManager performSelector:@selector(layers)];
                                    }
                                    if (!layers && layerManager) {
                                        @try { layers = [layerManager valueForKey:@"_layers"]; } @catch (NSException *e) {}
                                    }
                                    
                                    NSArray *layerArray = nil;
                                    if ([layers isKindOfClass:[NSSet class]]) {
                                        layerArray = [layers allObjects];
                                    } else if ([layers isKindOfClass:[NSArray class]]) {
                                        layerArray = layers;
                                    } else if ([layers isKindOfClass:[NSOrderedSet class]]) {
                                        layerArray = [layers array];
                                    }
                                    
                                    for (id layer in layerArray) {
                                        if ([layer respondsToSelector:@selector(contextID)]) {
                                            NSMethodSignature *sig = [layer methodSignatureForSelector:@selector(contextID)];
                                            if (sig) {
                                                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                                                [inv setSelector:@selector(contextID)];
                                                [inv setTarget:layer];
                                                [inv invoke];
                                                uint32_t cid = 0;
                                                [inv getReturnValue:&cid];
                                                if (cid > 0) {
                                                    contextID = cid;
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                }
                            } @catch (NSException *e) {}
                        }
                    }
                }
            }
            
            // Fallback 1: Local SpringBoard Windows
            if (contextID == 0) {
                Class windowClass = NSClassFromString(@"UIWindow");
                if (windowClass && [windowClass respondsToSelector:@selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:)]) {
                    NSArray *allWindows = [windowClass allWindowsIncludingInternalWindows:YES onlyVisibleWindows:YES];
                    for (UIWindow *window in [allWindows reverseObjectEnumerator]) {
                        if (window.userInteractionEnabled && !window.hidden) {
                            CGPoint localPt = [window convertPoint:CGPointMake(x, y) fromWindow:nil];
                            if ([window pointInside:localPt withEvent:nil]) {
                                uint32_t cid = 0;
                                if ([window respondsToSelector:@selector(_contextId)]) {
                                    cid = [window _contextId];
                                }
                                if (cid > 0) {
                                    contextID = cid;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            
            // Fallback 2: Any active foreground scene
            if (contextID == 0) {
                Class managerClass = NSClassFromString(@"FBSceneManager");
                id manager = nil;
                if (managerClass && [managerClass respondsToSelector:@selector(sharedInstance)]) {
                    manager = [managerClass performSelector:@selector(sharedInstance)];
                }
                if (manager) {
                    id workspace = nil;
                    @try { workspace = [manager valueForKey:@"_workspace"]; } @catch (NSException *e) {}
                    if (workspace) {
                        id scenes = nil;
                        if ([workspace respondsToSelector:@selector(scenes)]) {
                            scenes = [workspace performSelector:@selector(scenes)];
                        }
                        if (!scenes) {
                            @try { scenes = [workspace valueForKey:@"_scenes"]; } @catch (NSException *e) {}
                        }
                        if (!scenes) {
                            @try { scenes = [workspace valueForKey:@"allScenes"]; } @catch (NSException *e) {}
                        }
                        NSArray *sceneArray = nil;
                        if ([scenes isKindOfClass:[NSDictionary class]]) {
                            sceneArray = [scenes allValues];
                        } else if ([scenes isKindOfClass:[NSSet class]]) {
                            sceneArray = [scenes allObjects];
                        } else if ([scenes isKindOfClass:[NSArray class]]) {
                            sceneArray = scenes;
                        }
                        
                        for (id scene in sceneArray) {
                            @try {
                                id settings = nil;
                                if ([scene respondsToSelector:@selector(settings)]) {
                                    settings = [scene performSelector:@selector(settings)];
                                }
                                BOOL isForeground = NO;
                                if (settings && [settings respondsToSelector:NSSelectorFromString(@"isForeground")]) {
                                    SEL isFgSel = NSSelectorFromString(@"isForeground");
                                    NSMethodSignature *fgSig = [settings methodSignatureForSelector:isFgSel];
                                    if (fgSig) {
                                        NSInvocation *fgInv = [NSInvocation invocationWithMethodSignature:fgSig];
                                        [fgInv setSelector:isFgSel];
                                        [fgInv setTarget:settings];
                                        [fgInv invoke];
                                        [fgInv getReturnValue:&isForeground];
                                    }
                                }
                                if (isForeground) {
                                    id layerManager = nil;
                                    if ([scene respondsToSelector:@selector(layerManager)]) {
                                        layerManager = [scene performSelector:@selector(layerManager)];
                                    }
                                    if (!layerManager) {
                                        @try { layerManager = [scene valueForKey:@"_layerManager"]; } @catch (NSException *e) {}
                                    }
                                    id layers = nil;
                                    if (layerManager && [layerManager respondsToSelector:@selector(layers)]) {
                                        layers = [layerManager performSelector:@selector(layers)];
                                    }
                                    if (!layers && layerManager) {
                                        @try { layers = [layerManager valueForKey:@"_layers"]; } @catch (NSException *e) {}
                                    }
                                    NSArray *layerArray = nil;
                                    if ([layers isKindOfClass:[NSSet class]]) {
                                        layerArray = [layers allObjects];
                                    } else if ([layers isKindOfClass:[NSArray class]]) {
                                        layerArray = layers;
                                    }
                                    for (id layer in layerArray) {
                                        if ([layer respondsToSelector:@selector(contextID)]) {
                                            NSMethodSignature *sig = [layer methodSignatureForSelector:@selector(contextID)];
                                            if (sig) {
                                                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                                                [inv setSelector:@selector(contextID)];
                                                [inv setTarget:layer];
                                                [inv invoke];
                                                uint32_t cid = 0;
                                                [inv getReturnValue:&cid];
                                                if (cid > 0) {
                                                    contextID = cid;
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                    if (contextID > 0) break;
                                }
                            } @catch (NSException *e) {}
                        }
                    }
                }
            }
        }
    });
    return contextID;
}

#include <spawn.h>
#include <sys/wait.h>

static int rc_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions, const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    posix_spawnattr_t local_attr;
    posix_spawnattr_init(&local_attr);
#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
    posix_spawnattr_setflags(&local_attr, POSIX_SPAWN_CLOEXEC_DEFAULT);
#endif
    int ret = posix_spawn(pid, path, file_actions, &local_attr, argv, envp);
    posix_spawnattr_destroy(&local_attr);
    return ret;
}

static void rc_spawn_root_iohid(NSString *subcommand, NSArray *args) {
    extern char **environ;
    NSString *rcRootPath = @"/var/jb/usr/bin/rc-root";
    if (![[NSFileManager defaultManager] fileExistsAtPath:rcRootPath]) {
        rcRootPath = @"/usr/bin/rc-root";
    }
    
    int argc = (int)args.count + 3;
    char **argv = malloc((argc + 1) * sizeof(char *));
    argv[0] = (char *)[rcRootPath UTF8String];
    argv[1] = "iohid";
    argv[2] = (char *)[subcommand UTF8String];
    for (int i = 0; i < (int)args.count; i++) {
        argv[3 + i] = (char *)[args[i] UTF8String];
    }
    argv[argc] = NULL;
    
    pid_t pid;
    int status = rc_posix_spawn(&pid, [rcRootPath UTF8String], NULL, NULL, argv, environ);
    if (status == 0) {
        int exit_status;
        waitpid(pid, &exit_status, 0);
    } else {
        SRLog(@"[Touch] posix_spawn failed for rc-root: %d", status);
    }
    free(argv);
}

static void perform_digitizer_touch(double x, double y, BOOL down) {
    if (!_IOHIDEventCreateDigitizerEvent || !_IOHIDEventCreateDigitizerFingerEvent ||
        !_IOHIDEventAppendEvent || !_IOHIDEventSystemClientCreate || !_IOHIDEventSystemClientDispatchEvent) {
        SRLog(@"[Touch] Digitizer symbols not loaded – cannot simulate touch");
        return;
    }

    __block NSString *loggedBundleID = nil;
    __block CGSize s = CGSizeZero;
    __block CGFloat scale = 1.0;
    rc_dispatch_sync_main_safe(^{
        s = [UIScreen mainScreen].bounds.size;
        scale = [UIScreen mainScreen].scale;
        
        SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
        if (sb && [sb respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
            id frontApp = [sb _accessibilityFrontMostApplication];
            if (frontApp && [frontApp respondsToSelector:@selector(bundleIdentifier)]) {
                loggedBundleID = [frontApp bundleIdentifier];
            }
        }
    });

    double screenWidth = MIN(s.width, s.height);
    double screenHeight = MAX(s.width, s.height);
    if (screenWidth == 0) screenWidth = 375.0; // Fallback for safety
    if (screenHeight == 0) screenHeight = 667.0;

    // Normalised coordinates [0.0, 1.0] as expected by Apple's HID Digitizer APIs
    double rx = x / screenWidth;
    double ry = y / screenHeight;

    SRLog(@"[Touch] Simulated touch: raw(%.1f, %.1f) screen(%.1f, %.1f) scale=%.1f -> normalized(%.4f, %.4f) down=%d",
          x, y, screenWidth, screenHeight, scale, rx, ry, down);

    uint32_t contextID = rc_resolve_target_context(x, y);
    BOOL targetIsLocal = rc_is_springboard_context(contextID);

    uint32_t transducerType = 3;
    uint32_t parentIndex = 0;
    uint32_t parentIdentity = 1;
    uint32_t parentEventMask = 0;
    uint32_t parentButtonMask = 0;
    uint64_t ts = mach_absolute_time();
    uint32_t fingerIndex = 1;
    uint32_t fingerIdentity = 2;
    uint32_t fingerEventMask = 0x3; // kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch
    double pressure = down ? 1.0 : 0.0;
    uint32_t handEventMask = 35;
    uint32_t handEventTouch = down ? 1 : 0;

    // Path 1: System-wide global event
    IOHIDEventRef parentGlobal = _IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, ts,
        transducerType, parentIndex, parentIdentity, parentEventMask, parentButtonMask,
        0.0, 0.0, 0.0, 0.0, 0.0,
        0, 0, 0);

    if (parentGlobal) {
        // Path 1 system-wide event: BackBoard/IOHIDFamily expects absolute coordinates (x, y) in points.
        IOHIDEventRef fingerGlobal = _IOHIDEventCreateDigitizerFingerEvent(
            kCFAllocatorDefault, ts,
            fingerIndex, fingerIdentity, fingerEventMask,
            x, y, 0.0, pressure, 0.0,
            (boolean_t)down, (boolean_t)down, 0);

        if (fingerGlobal) {
            _IOHIDEventAppendEvent(parentGlobal, fingerGlobal, 0);
            CFRelease(fingerGlobal);
        }

        if (_IOHIDEventSetIntegerValueWithOptions) {
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720921, 1, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720925, 1, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 4, 1, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720903, handEventMask, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720904, handEventTouch, 0xF0000000);
            _IOHIDEventSetIntegerValueWithOptions(parentGlobal, 720905, handEventTouch, 0xF0000000);
        } else if (_IOHIDEventSetIntegerValue) {
            _IOHIDEventSetIntegerValue(parentGlobal, 720921, 1);
            _IOHIDEventSetIntegerValue(parentGlobal, 720925, 1);
            _IOHIDEventSetIntegerValue(parentGlobal, 4, 1);
            _IOHIDEventSetIntegerValue(parentGlobal, 720903, handEventMask);
            _IOHIDEventSetIntegerValue(parentGlobal, 720904, handEventTouch);
            _IOHIDEventSetIntegerValue(parentGlobal, 720905, handEventTouch);
        }

        if (_IOHIDEventSetSenderID) {
            _IOHIDEventSetSenderID(parentGlobal, rc_get_digitizer_sender_id());
        }

        if (contextID > 0) {
            BKSHIDEventSetDigitizerInfo(parentGlobal, contextID, false, false, NULL, 0, 0);
        }

        IOHIDEventSystemClientRef client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (client) {
            _IOHIDEventSystemClientDispatchEvent(client, parentGlobal);
            CFRelease(client);
            SRLog(@"[Touch] Dispatched global system-wide touch event.");
        }
        CFRelease(parentGlobal);
    }

    // Path 2: Local SpringBoard Window enqueue (Absolute Coordinates)

    if (targetIsLocal) {
        IOHIDEventRef parentLocal = _IOHIDEventCreateDigitizerEvent(
            kCFAllocatorDefault, ts,
            transducerType, parentIndex, parentIdentity, parentEventMask, parentButtonMask,
            0.0, 0.0, 0.0, 0.0, 0.0,
            0, 0, 0);

        if (parentLocal) {
            IOHIDEventRef fingerLocal = _IOHIDEventCreateDigitizerFingerEvent(
                kCFAllocatorDefault, ts,
                fingerIndex, fingerIdentity, fingerEventMask,
                x, y, 0.0, pressure, 0.0,
                (boolean_t)down, (boolean_t)down, 0);

            if (fingerLocal) {
                _IOHIDEventAppendEvent(parentLocal, fingerLocal, 0);
                CFRelease(fingerLocal);
            }

            if (_IOHIDEventSetIntegerValueWithOptions) {
                _IOHIDEventSetIntegerValueWithOptions(parentLocal, 720921, 1, 0xF0000000);
                _IOHIDEventSetIntegerValueWithOptions(parentLocal, 720925, 1, 0xF0000000);
                _IOHIDEventSetIntegerValueWithOptions(parentLocal, 4, 1, 0xF0000000);
                _IOHIDEventSetIntegerValueWithOptions(parentLocal, 720903, handEventMask, 0xF0000000);
                _IOHIDEventSetIntegerValueWithOptions(parentLocal, 720904, handEventTouch, 0xF0000000);
                _IOHIDEventSetIntegerValueWithOptions(parentLocal, 720905, handEventTouch, 0xF0000000);
            } else if (_IOHIDEventSetIntegerValue) {
                _IOHIDEventSetIntegerValue(parentLocal, 720921, 1);
                _IOHIDEventSetIntegerValue(parentLocal, 720925, 1);
                _IOHIDEventSetIntegerValue(parentLocal, 4, 1);
                _IOHIDEventSetIntegerValue(parentLocal, 720903, handEventMask);
                _IOHIDEventSetIntegerValue(parentLocal, 720904, handEventTouch);
                _IOHIDEventSetIntegerValue(parentLocal, 720905, handEventTouch);
            }

            if (_IOHIDEventSetSenderID) {
                _IOHIDEventSetSenderID(parentLocal, 0xDEFACEDBEEFFECE5ULL);
            }

            BKSHIDEventSetDigitizerInfo(parentLocal, contextID, false, false, NULL, 0, 0);

            rc_dispatch_sync_main_safe(^{
                [[UIApplication sharedApplication] _enqueueHIDEvent:parentLocal];
                SRLog(@"[Touch] Enqueued local touch event to UIApplication (absolute coords).");
            });
            CFRelease(parentLocal);
        }
    }
    
    SRLog(@"[Touch] Dispatched touch event (down=%d) to contextID=%u (frontApp: %@) at (%.1f, %.1f)", down, contextID, loggedBundleID, x, y);
}

// Simulate a tap at absolute pixel coordinates (x, y).
// MUST be called from rc_touch_queue.
static void rc_simulate_tap(double px, double py) {
    uint32_t contextID = rc_resolve_target_context(px, py);
    BOOL targetIsLocal = rc_is_springboard_context(contextID);
    SRLog(@"[Touch] tap at pixel (%.0f,%.0f) contextID=%u targetIsLocal=%d", px, py, contextID, targetIsLocal);
    
    if (targetIsLocal) {
        perform_digitizer_touch(px, py, YES);   // finger down
        usleep(80000);                          // 80 ms contact
        perform_digitizer_touch(px, py, NO);    // finger up
    } else {
        __block CGSize s = CGSizeZero;
        rc_dispatch_sync_main_safe(^{
            s = [UIScreen mainScreen].bounds.size;
        });
        double screenWidth = MIN(s.width, s.height);
        double screenHeight = MAX(s.width, s.height);
        if (screenWidth == 0) screenWidth = 375.0;
        if (screenHeight == 0) screenHeight = 667.0;

        SRLog(@"[Touch] non-local tap -> spawning rc-root iohid tap (%.1f, %.1f) contextID=%u screen=%.0fx%.0f", px, py, contextID, screenWidth, screenHeight);
        rc_spawn_root_iohid(@"tap", @[
            [NSString stringWithFormat:@"%.1f", px],
            [NSString stringWithFormat:@"%.1f", py],
            [NSString stringWithFormat:@"%u", contextID],
            [NSString stringWithFormat:@"%.1f", screenWidth],
            [NSString stringWithFormat:@"%.1f", screenHeight]
        ]);
    }
}

// Simulate a hold at absolute pixel coordinates for `durationMs` milliseconds.
// MUST be called from rc_touch_queue.
static void rc_simulate_hold(double px, double py, int durationMs) {
    uint32_t contextID = rc_resolve_target_context(px, py);
    BOOL targetIsLocal = rc_is_springboard_context(contextID);
    int clampedMs = MAX(50, MIN(durationMs, 10000));
    SRLog(@"[Touch] hold at pixel (%.0f,%.0f) for %d ms contextID=%u targetIsLocal=%d", px, py, clampedMs, contextID, targetIsLocal);

    if (targetIsLocal) {
        perform_digitizer_touch(px, py, YES);
        usleep((useconds_t)(clampedMs * 1000));
        perform_digitizer_touch(px, py, NO);
    } else {
        __block CGSize s = CGSizeZero;
        rc_dispatch_sync_main_safe(^{
            s = [UIScreen mainScreen].bounds.size;
        });
        double screenWidth = MIN(s.width, s.height);
        double screenHeight = MAX(s.width, s.height);
        if (screenWidth == 0) screenWidth = 375.0;
        if (screenHeight == 0) screenHeight = 667.0;

        SRLog(@"[Touch] non-local hold -> spawning rc-root iohid hold (%.1f, %.1f, %d) contextID=%u screen=%.0fx%.0f", px, py, clampedMs, contextID, screenWidth, screenHeight);
        rc_spawn_root_iohid(@"hold", @[
            [NSString stringWithFormat:@"%.1f", px],
            [NSString stringWithFormat:@"%.1f", py],
            [NSString stringWithFormat:@"%d", clampedMs],
            [NSString stringWithFormat:@"%u", contextID],
            [NSString stringWithFormat:@"%.1f", screenWidth],
            [NSString stringWithFormat:@"%.1f", screenHeight]
        ]);
    }
}

// Simulate a swipe from (x1,y1) to (x2,y2) over ~600ms with smooth interpolation.
// MUST be called from rc_touch_queue.
static void rc_simulate_swipe(double x1, double y1, double x2, double y2) {
    uint32_t contextID = rc_resolve_target_context(x1, y1);
    BOOL targetIsLocal = rc_is_springboard_context(contextID);
    SRLog(@"[Touch] swipe (%.0f,%.0f)→(%.0f,%.0f) contextID=%u targetIsLocal=%d", x1, y1, x2, y2, contextID, targetIsLocal);

    if (targetIsLocal) {
        const int steps = 40;
        const int stepDelayUs = 15000; // 15 ms per step → ~600 ms total

        perform_digitizer_touch(x1, y1, YES); // touch down
        usleep(16000); // brief settle

        for (int i = 1; i <= steps; i++) {
            double t = (double)i / steps;
            double cx = x1 + (x2 - x1) * t;
            double cy = y1 + (y2 - y1) * t;
            perform_digitizer_touch(cx, cy, YES); // move
            usleep((useconds_t)stepDelayUs);
        }

        usleep(16000);
        perform_digitizer_touch(x2, y2, NO); // touch up
    } else {
        __block CGSize s = CGSizeZero;
        rc_dispatch_sync_main_safe(^{
            s = [UIScreen mainScreen].bounds.size;
        });
        double screenWidth = MIN(s.width, s.height);
        double screenHeight = MAX(s.width, s.height);
        if (screenWidth == 0) screenWidth = 375.0;
        if (screenHeight == 0) screenHeight = 667.0;

        SRLog(@"[Touch] non-local swipe -> spawning rc-root iohid swipe (%.1f, %.1f)→(%.1f, %.1f) contextID=%u screen=%.0fx%.0f", x1, y1, x2, y2, contextID, screenWidth, screenHeight);
        rc_spawn_root_iohid(@"swipe", @[
            [NSString stringWithFormat:@"%.1f", x1],
            [NSString stringWithFormat:@"%.1f", y1],
            [NSString stringWithFormat:@"%.1f", x2],
            [NSString stringWithFormat:@"%.1f", y2],
            [NSString stringWithFormat:@"%u", contextID],
            [NSString stringWithFormat:@"%.1f", screenWidth],
            [NSString stringWithFormat:@"%.1f", screenHeight]
        ]);
    }
}

// ── Tap Recording Overlay ───────────────────────────────────────────────────
static NSString *g_tapRecordStatus = @"idle";
static int g_tapRecordCountdown = 0;
static CGPoint g_tapRecordPoint = {0, 0};
static UIViewController *g_rcTapRecordViewController = nil;
static UILabel *g_rcTapRecordLabel = nil;
static NSTimer *g_tapRecordTimeoutTimer = nil;

static void rc_taprecord_cleanup(void);

@interface RCTapRecordViewController : UIViewController
@end

@implementation RCTapRecordViewController
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (![g_tapRecordStatus isEqualToString:@"waiting"]) return;
    UITouch *touch = [touches anyObject];
    if (touch && g_rcTapRecordWindow) {
        CGPoint pt = [touch locationInView:self.view];
        g_tapRecordPoint = pt;
        g_tapRecordStatus = @"recorded";
        SRLog(@"[TapRecord] Touch captured at: %.1f, %.1f", pt.x, pt.y);
        
        // Play success haptic
        AudioServicesPlaySystemSound(1519); // Peak/Actuation haptic
        
        rc_taprecord_cleanup();
        
        // Open/Foreground the RemoteCompanion app
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                Class FBSOpenApplicationServiceClass = objc_getClass("FBSOpenApplicationService");
                if (FBSOpenApplicationServiceClass) {
                    FBSOpenApplicationService *service = [FBSOpenApplicationServiceClass serviceWithDefaultShellEndpoint];
                    [service openApplication:@"com.saihgupr.remotecompanion" withOptions:nil completion:nil];
                }
            } @catch (NSException *e) {
                SRLog(@"[TapRecord] Error relaunching app: %@", e);
            }
        });
    }
}

- (BOOL)shouldAutorotate {
    return NO;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}
@end

static void rc_taprecord_cleanup(void) {
    if (g_tapRecordTimeoutTimer) {
        [g_tapRecordTimeoutTimer invalidate];
        g_tapRecordTimeoutTimer = nil;
    }
    if (g_rcTapRecordWindow) {
        g_rcTapRecordWindow.hidden = YES;
        g_rcTapRecordWindow = nil;
        g_rcTapRecordViewController = nil;
        g_rcTapRecordLabel = nil;
    }
}

static void rc_taprecord_timeout(void) {
    if ([g_tapRecordStatus isEqualToString:@"waiting"]) {
        g_tapRecordStatus = @"timeout";
        SRLog(@"[TapRecord] Timeout reached, no touch received.");
        rc_taprecord_cleanup();
    }
}

static void rc_taprecord_update_countdown(int secondsLeft) {
    g_tapRecordCountdown = secondsLeft;
    if (secondsLeft > 0) {
        g_tapRecordStatus = @"counting";
        rc_dispatch_sync_main_safe(^{
            if (g_rcTapRecordLabel) {
                g_rcTapRecordLabel.text = [NSString stringWithFormat:@"Recording tap in %d...", secondsLeft];
            }
        });
        
        // Play click sound / haptic
        AudioServicesPlaySystemSound(1104);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([g_tapRecordStatus isEqualToString:@"counting"]) {
                rc_taprecord_update_countdown(secondsLeft - 1);
            }
        });
    } else {
        g_tapRecordStatus = @"waiting";
        rc_dispatch_sync_main_safe(^{
            if (g_rcTapRecordWindow) {
                g_rcTapRecordWindow.userInteractionEnabled = YES;
                g_rcTapRecordViewController.view.backgroundColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:0.12];
                g_rcTapRecordViewController.view.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0].CGColor;
                g_rcTapRecordViewController.view.layer.borderWidth = 4.0;
            }
            if (g_rcTapRecordLabel) {
                g_rcTapRecordLabel.text = @"TAP SCREEN NOW\nto record coordinates";
                g_rcTapRecordLabel.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:0.85];
            }
        });
        
        // Start 10 seconds timeout timer
        g_tapRecordTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:NO block:^(NSTimer *timer) {
            rc_taprecord_timeout();
        }];
    }
}

static void rc_taprecord_start(void) {
    rc_dispatch_sync_main_safe(^{
        rc_taprecord_cleanup();
        
        g_tapRecordStatus = @"counting";
        g_tapRecordCountdown = 3;
        g_tapRecordPoint = CGPointZero;
        
        CGRect bounds = [UIScreen mainScreen].bounds;
        g_rcTapRecordWindow = [[UIWindow alloc] initWithFrame:bounds];
        g_rcTapRecordWindow.windowLevel = UIWindowLevelAlert + 2590.0;
        g_rcTapRecordWindow.backgroundColor = [UIColor clearColor];
        g_rcTapRecordWindow.userInteractionEnabled = NO;
        
        g_rcTapRecordViewController = [[RCTapRecordViewController alloc] init];
        g_rcTapRecordViewController.view.frame = bounds;
        g_rcTapRecordViewController.view.backgroundColor = [UIColor clearColor];
        g_rcTapRecordWindow.rootViewController = g_rcTapRecordViewController;
        
        CGFloat labelWidth = bounds.size.width - 64.0;
        CGFloat labelHeight = 100.0;
        CGFloat labelX = (bounds.size.width - labelWidth) / 2.0;
        CGFloat labelY = (bounds.size.height - labelHeight) / 2.0;
        
        g_rcTapRecordLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, labelY, labelWidth, labelHeight)];
        g_rcTapRecordLabel.textAlignment = NSTextAlignmentCenter;
        g_rcTapRecordLabel.numberOfLines = 0;
        g_rcTapRecordLabel.font = [UIFont boldSystemFontOfSize:20.0];
        g_rcTapRecordLabel.textColor = [UIColor whiteColor];
        g_rcTapRecordLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
        g_rcTapRecordLabel.layer.cornerRadius = 16.0;
        g_rcTapRecordLabel.layer.masksToBounds = YES;
        g_rcTapRecordLabel.text = @"Recording tap in 3...";
        
        [g_rcTapRecordViewController.view addSubview:g_rcTapRecordLabel];
        
        g_rcTapRecordWindow.hidden = NO;
        [g_rcTapRecordWindow makeKeyAndVisible];
        
        SRLog(@"[TapRecord] Countdown started");
        
        rc_taprecord_update_countdown(3);
    });
}

// -- GraphicsServices tap beta -------------------------------------------------
// New candidate path for iOS 15 tap testing. This intentionally does not call
// the older IOHID digitizer helpers above.

static UIWindow *g_rcTapTestWindow = nil;
static UIViewController *g_rcTapTestViewController = nil;
static UIButton *g_rcTapTestButton = nil;
static UILabel *g_rcTapTestLabel = nil;
static id g_rcTapTestTarget = nil;
static NSInteger g_rcTapTestHitCount = 0;
static CGPoint g_rcTapTestLastHitPoint = {0, 0};
static CFAbsoluteTime g_rcTapTestLastHitTime = 0;
static CGRect g_rcTapTestButtonFrame = {{0, 0}, {0, 0}};

static void rc_taptest_update_label(void);

@interface RCTapTestButtonTarget : NSObject
- (void)buttonTapped:(UIButton *)sender forEvent:(UIEvent *)event;
@end

@implementation RCTapTestButtonTarget
- (void)buttonTapped:(UIButton *)sender forEvent:(UIEvent *)event {
    (void)sender;
    UITouch *touch = [[event allTouches] anyObject];
    if (touch && g_rcTapTestWindow) {
        g_rcTapTestLastHitPoint = [touch locationInView:g_rcTapTestWindow];
    } else {
        g_rcTapTestLastHitPoint = CGPointMake(CGRectGetMidX(g_rcTapTestButtonFrame),
                                              CGRectGetMidY(g_rcTapTestButtonFrame));
    }
    g_rcTapTestHitCount++;
    g_rcTapTestLastHitTime = CFAbsoluteTimeGetCurrent();
    SRLog(@"[TapTest] target received tap #%ld at %.1f, %.1f",
          (long)g_rcTapTestHitCount, g_rcTapTestLastHitPoint.x, g_rcTapTestLastHitPoint.y);
    rc_taptest_update_label();
}
@end

typedef mach_port_t (*RCGSGetPortFn)(void);
typedef void (*RCGSSendEventFn)(const GSEventRecord *record, mach_port_t port);
typedef void (*RCGSSendSystemEventFn)(const GSEventRecord *record);

static RCGSSendEventFn g_rcGSSendEvent = NULL;
static RCGSSendSystemEventFn g_rcGSSendSystemEvent = NULL;
static RCGSGetPortFn g_rcGSGetSystemEventPort = NULL;
static RCGSGetPortFn g_rcGSGetApplicationPort = NULL;
static NSString *g_rcGraphicsServicesLoadError = nil;

static dispatch_queue_t rc_gs_tap_queue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.pizzaman.remotecommand.gstap", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSArray<NSString *> *rc_split_whitespace(NSString *input) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [input componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (part.length > 0) [parts addObject:part];
    }
    return parts;
}

static void rc_dispatch_sync_main_safe(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static BOOL rc_load_graphics_services_symbols(NSString **errorOut) {
    static BOOL loaded = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW | RTLD_NOLOAD);
        if (!handle) {
            handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW);
        }
        if (!handle) {
            const char *err = dlerror();
            g_rcGraphicsServicesLoadError = [NSString stringWithFormat:@"dlopen GraphicsServices failed: %s", err ? err : "unknown"];
            SRLog(@"[GSTap] %@", g_rcGraphicsServicesLoadError);
            return;
        }

        g_rcGSSendEvent = (RCGSSendEventFn)dlsym(handle, "GSSendEvent");
        g_rcGSSendSystemEvent = (RCGSSendSystemEventFn)dlsym(handle, "GSSendSystemEvent");
        g_rcGSGetSystemEventPort = (RCGSGetPortFn)dlsym(handle, "GSGetPurpleSystemEventPort");
        g_rcGSGetApplicationPort = (RCGSGetPortFn)dlsym(handle, "GSGetPurpleApplicationPort");

        if ((!g_rcGSSendEvent && !g_rcGSSendSystemEvent) ||
            (!g_rcGSGetSystemEventPort && !g_rcGSGetApplicationPort)) {
            g_rcGraphicsServicesLoadError = [NSString stringWithFormat:
                @"missing symbols send=%p systemSend=%p systemPort=%p appPort=%p",
                g_rcGSSendEvent, g_rcGSSendSystemEvent,
                g_rcGSGetSystemEventPort, g_rcGSGetApplicationPort];
            SRLog(@"[GSTap] %@", g_rcGraphicsServicesLoadError);
            return;
        }

        loaded = YES;
        SRLog(@"[GSTap] GraphicsServices loaded send=%p systemSend=%p systemPort=%p appPort=%p",
              g_rcGSSendEvent, g_rcGSSendSystemEvent,
              g_rcGSGetSystemEventPort, g_rcGSGetApplicationPort);
    });

    if (!loaded && errorOut) *errorOut = g_rcGraphicsServicesLoadError ?: @"GraphicsServices unavailable";
    return loaded;
}

typedef struct {
    GSEventRecord record;
    GSHandInfo handInfo;
    GSPathInfo pathInfo;
} RCGSTouchEvent;

static BOOL rc_gs_send_hand_event(CGPoint point, GSHandInfoType type, NSString *mode, NSString **errorOut) {
    NSString *loadError = nil;
    if (!rc_load_graphics_services_symbols(&loadError)) {
        if (errorOut) *errorOut = loadError;
        return NO;
    }

    RCGSTouchEvent event;
    memset(&event, 0, sizeof(event));

    event.record.type = kGSEventHand;
    event.record.subtype = kGSEventSubTypeUnknown;
    event.record.location = point;
    event.record.windowLocation = point;
    event.record.windowContextId = 0;
    event.record.timestamp = mach_absolute_time();
    event.record.window = NULL;
    event.record.flags = 0;
    event.record.senderPID = (unsigned)getpid();
    event.record.infoSize = sizeof(GSHandInfo) + sizeof(GSPathInfo);

    event.handInfo.type = type;
    event.handInfo.deltaX = 0;
    event.handInfo.deltaY = 0;
    event.handInfo.width = 1.0f;
    event.handInfo.height = 1.0f;
    event.handInfo.pathInfosCount = 1;

    event.pathInfo.pathIndex = 1;
    event.pathInfo.pathIdentity = 2;
    event.pathInfo.pathProximity = (type == kGSHandInfoTypeTouchUp) ? 0 : 1;
    event.pathInfo.pathPressure = (type == kGSHandInfoTypeTouchUp) ? 0.0 : 1.0;
    event.pathInfo.pathMajorRadius = 4.0;
    event.pathInfo.pathLocation = point;
    event.pathInfo.pathWindow = NULL;

    BOOL useApplicationPort = [mode isEqualToString:@"app"] || [mode isEqualToString:@"springboard"];
    mach_port_t port = MACH_PORT_NULL;
    if (useApplicationPort && g_rcGSGetApplicationPort) {
        port = g_rcGSGetApplicationPort();
    } else if (g_rcGSGetSystemEventPort) {
        port = g_rcGSGetSystemEventPort();
    }

    if (g_rcGSSendEvent && port != MACH_PORT_NULL) {
        g_rcGSSendEvent(&event.record, port);
        return YES;
    }

    if (g_rcGSSendSystemEvent) {
        g_rcGSSendSystemEvent(&event.record);
        return YES;
    }

    if (errorOut) *errorOut = @"no GraphicsServices send port available";
    return NO;
}

static BOOL rc_gs_send_tap(CGPoint point, NSString *mode, NSString **errorOut) {
    NSString *downError = nil;
    if (!rc_gs_send_hand_event(point, kGSHandInfoTypeTouchDown, mode, &downError)) {
        if (errorOut) *errorOut = downError;
        return NO;
    }

    usleep(90000);

    NSString *upError = nil;
    if (!rc_gs_send_hand_event(point, kGSHandInfoTypeTouchUp, mode, &upError)) {
        if (errorOut) *errorOut = upError;
        return NO;
    }

    return YES;
}

static void rc_taptest_layout_locked(void) {
    if (!g_rcTapTestWindow || !g_rcTapTestButton || !g_rcTapTestLabel) return;

    CGRect bounds = [UIScreen mainScreen].bounds;
    g_rcTapTestWindow.frame = bounds;
    g_rcTapTestViewController.view.frame = bounds;

    CGFloat buttonWidth = MIN(220.0, MAX(160.0, bounds.size.width - 64.0));
    CGFloat buttonHeight = 84.0;
    CGFloat buttonX = round((bounds.size.width - buttonWidth) * 0.5);
    CGFloat buttonY = round((bounds.size.height - buttonHeight) * 0.5);
    g_rcTapTestButton.frame = CGRectMake(buttonX, buttonY, buttonWidth, buttonHeight);
    g_rcTapTestButtonFrame = g_rcTapTestButton.frame;

    g_rcTapTestLabel.frame = CGRectMake(18.0,
                                        CGRectGetMinY(g_rcTapTestButton.frame) - 112.0,
                                        bounds.size.width - 36.0,
                                        86.0);
}

static void rc_taptest_update_label(void) {
    if (!g_rcTapTestLabel || !g_rcTapTestButton) return;

    NSString *last = g_rcTapTestLastHitTime > 0
        ? [NSString stringWithFormat:@"last %.0f, %.0f", g_rcTapTestLastHitPoint.x, g_rcTapTestLastHitPoint.y]
        : @"last none";

    g_rcTapTestLabel.text = [NSString stringWithFormat:
        @"RemoteCompanion Tap Test\nhits %ld\n%@",
        (long)g_rcTapTestHitCount,
        last];
    [g_rcTapTestButton setTitle:[NSString stringWithFormat:@"Tap Target (%ld)", (long)g_rcTapTestHitCount]
                       forState:UIControlStateNormal];
}

static void rc_taptest_show_locked(BOOL reset) {
    if (reset) {
        g_rcTapTestHitCount = 0;
        g_rcTapTestLastHitPoint = CGPointZero;
        g_rcTapTestLastHitTime = 0;
    }

    if (!g_rcTapTestTarget) {
        g_rcTapTestTarget = [[RCTapTestButtonTarget alloc] init];
    }

    if (!g_rcTapTestWindow) {
        CGRect bounds = [UIScreen mainScreen].bounds;
        g_rcTapTestWindow = [[UIWindow alloc] initWithFrame:bounds];
        g_rcTapTestWindow.windowLevel = UIWindowLevelAlert + 2500.0;
        g_rcTapTestWindow.backgroundColor = [UIColor clearColor];
        g_rcTapTestWindow.userInteractionEnabled = YES;

        g_rcTapTestViewController = [[UIViewController alloc] init];
        g_rcTapTestViewController.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.18];
        g_rcTapTestWindow.rootViewController = g_rcTapTestViewController;

        g_rcTapTestLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        g_rcTapTestLabel.textAlignment = NSTextAlignmentCenter;
        g_rcTapTestLabel.numberOfLines = 0;
        g_rcTapTestLabel.font = [UIFont monospacedSystemFontOfSize:16.0 weight:UIFontWeightSemibold];
        g_rcTapTestLabel.textColor = [UIColor whiteColor];
        g_rcTapTestLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.68];
        g_rcTapTestLabel.layer.cornerRadius = 12.0;
        g_rcTapTestLabel.layer.masksToBounds = YES;
        [g_rcTapTestViewController.view addSubview:g_rcTapTestLabel];

        g_rcTapTestButton = [UIButton buttonWithType:UIButtonTypeSystem];
        g_rcTapTestButton.backgroundColor = [UIColor colorWithRed:0.10 green:0.72 blue:0.38 alpha:1.0];
        g_rcTapTestButton.tintColor = [UIColor whiteColor];
        g_rcTapTestButton.titleLabel.font = [UIFont boldSystemFontOfSize:22.0];
        g_rcTapTestButton.layer.cornerRadius = 12.0;
        g_rcTapTestButton.layer.borderColor = [UIColor whiteColor].CGColor;
        g_rcTapTestButton.layer.borderWidth = 2.0;
        g_rcTapTestButton.accessibilityIdentifier = @"remotecompanion.taptest.target";
        [g_rcTapTestButton addTarget:g_rcTapTestTarget
                              action:@selector(buttonTapped:forEvent:)
                    forControlEvents:UIControlEventTouchUpInside];
        [g_rcTapTestViewController.view addSubview:g_rcTapTestButton];
    }

    rc_taptest_layout_locked();
    rc_taptest_update_label();
    g_rcTapTestWindow.hidden = NO;
    [g_rcTapTestWindow makeKeyAndVisible];
    SRLog(@"[TapTest] shown target frame %.0f %.0f %.0f %.0f",
          g_rcTapTestButtonFrame.origin.x, g_rcTapTestButtonFrame.origin.y,
          g_rcTapTestButtonFrame.size.width, g_rcTapTestButtonFrame.size.height);
}

static void rc_taptest_hide_locked(void) {
    if (g_rcTapTestWindow) {
        g_rcTapTestWindow.hidden = YES;
        SRLog(@"[TapTest] hidden");
    }
}

static NSString *rc_taptest_status_string(void) {
    __block NSString *status = nil;
    rc_dispatch_sync_main_safe(^{
        BOOL visible = g_rcTapTestWindow && !g_rcTapTestWindow.hidden;
        CGPoint center = CGPointMake(CGRectGetMidX(g_rcTapTestButtonFrame), CGRectGetMidY(g_rcTapTestButtonFrame));
        NSString *last = g_rcTapTestLastHitTime > 0
            ? [NSString stringWithFormat:@"%.0f %.0f", g_rcTapTestLastHitPoint.x, g_rcTapTestLastHitPoint.y]
            : @"none";
        status = [NSString stringWithFormat:
            @"taptest visible=%@ hits=%ld button=%.0f %.0f %.0f %.0f center=%.0f %.0f last=%@ backend=IOHIDEvent\n",
            visible ? @"yes" : @"no",
            (long)g_rcTapTestHitCount,
            g_rcTapTestButtonFrame.origin.x,
            g_rcTapTestButtonFrame.origin.y,
            g_rcTapTestButtonFrame.size.width,
            g_rcTapTestButtonFrame.size.height,
            center.x,
            center.y,
            last];
    });
    return status ?: @"taptest unavailable\n";
}

static NSString *rc_handle_taptest_command(NSString *cleanCmd) {
    NSArray<NSString *> *parts = rc_split_whitespace(cleanCmd);
    NSString *subcommand = parts.count >= 2 ? [parts[1] lowercaseString] : @"status";

    if ([subcommand isEqualToString:@"show"]) {
        rc_dispatch_sync_main_safe(^{ rc_taptest_show_locked(NO); });
        return rc_taptest_status_string();
    }

    if ([subcommand isEqualToString:@"reset"]) {
        rc_dispatch_sync_main_safe(^{ rc_taptest_show_locked(YES); });
        return rc_taptest_status_string();
    }

    if ([subcommand isEqualToString:@"hide"]) {
        rc_dispatch_sync_main_safe(^{ rc_taptest_hide_locked(); });
        return @"taptest hidden\n";
    }

    if ([subcommand isEqualToString:@"status"]) {
        return rc_taptest_status_string();
    }

    if ([subcommand isEqualToString:@"run"]) {
        NSString *backend = @"iohid";
        NSString *mode = @"system";

        if (parts.count >= 3) {
            NSString *p2 = [parts[2] lowercaseString];
            if ([p2 isEqualToString:@"iohid"] || [p2 isEqualToString:@"gsevent"]) {
                backend = p2;
                if (parts.count >= 4) {
                    mode = [parts[3] lowercaseString];
                }
            } else {
                mode = p2;
            }
        }

        if (!([mode isEqualToString:@"system"] ||
              [mode isEqualToString:@"app"] ||
              [mode isEqualToString:@"springboard"])) {
            return @"Usage: taptest run [iohid|gsevent] [system|app]\n";
        }

        __block CGPoint center = CGPointZero;
        __block NSInteger startCount = 0;
        rc_dispatch_sync_main_safe(^{
            rc_taptest_show_locked(YES);
            center = CGPointMake(CGRectGetMidX(g_rcTapTestButtonFrame), CGRectGetMidY(g_rcTapTestButtonFrame));
            startCount = g_rcTapTestHitCount;
        });

        usleep(180000);

        __block BOOL sent = NO;
        __block NSString *sendError = nil;

        if ([backend isEqualToString:@"gsevent"]) {
            dispatch_sync(rc_gs_tap_queue(), ^{
                sent = rc_gs_send_tap(center, mode, &sendError);
            });
        } else {
            // IOHIDEvent backend
            rc_load_touch_symbols();
            dispatch_sync(rc_touch_queue(), ^{
                perform_digitizer_touch(center.x, center.y, YES);
                usleep(80000);
                perform_digitizer_touch(center.x, center.y, NO);
                sent = YES;
            });
        }

        if (!sent) {
            return [NSString stringWithFormat:@"taptest FAIL send-error=%@ backend=%@ mode=%@\n",
                    sendError ?: @"unknown", backend, mode];
        }

        BOOL passed = NO;
        for (int i = 0; i < 24; i++) {
            __block NSInteger count = 0;
            rc_dispatch_sync_main_safe(^{ count = g_rcTapTestHitCount; });
            if (count > startCount) {
                passed = YES;
                break;
            }
            usleep(50000);
        }

        NSString *status = rc_taptest_status_string();
        return [NSString stringWithFormat:@"taptest %@ backend=%@ mode=%@ target=%.0f %.0f\n%@",
                passed ? @"PASS" : @"FAIL",
                backend,
                mode,
                center.x,
                center.y,
                status];
    }

    return @"Usage: taptest show|hide|reset|status|run [iohid|gsevent] [system|app]\n";
}

// ── Lua-callable touch functions ──────────────────────────────────────────────

// tap(x, y)  — pixel coords, 0,0 = top-left
static int lua_tap_fn(lua_State *L) {
    double x = luaL_checknumber(L, 1);
    double y = luaL_checknumber(L, 2);
    rc_load_touch_symbols();
    dispatch_async(rc_touch_queue(), ^{
        rc_simulate_tap(x, y);
    });
    return 0;
}

// hold(x, y, ms)  — hold finger at (x,y) for ms milliseconds (default 500)
static int lua_hold_fn(lua_State *L) {
    double x = luaL_checknumber(L, 1);
    double y = luaL_checknumber(L, 2);
    int ms = (int)luaL_optinteger(L, 3, 500);
    rc_load_touch_symbols();
    dispatch_async(rc_touch_queue(), ^{
        rc_simulate_hold(x, y, ms);
    });
    return 0;
}

// swipe(x1, y1, x2, y2)  — swipe between two pixel coords
static int lua_swipe_fn(lua_State *L) {
    double x1 = luaL_checknumber(L, 1);
    double y1 = luaL_checknumber(L, 2);
    double x2 = luaL_checknumber(L, 3);
    double y2 = luaL_checknumber(L, 4);
    rc_load_touch_symbols();
    dispatch_async(rc_touch_queue(), ^{
        rc_simulate_swipe(x1, y1, x2, y2);
    });
    return 0;
}

// swipeUp()  — swipe upward from near bottom edge toward center-top
static int lua_swipe_up(lua_State *L) {
    (void)L;
    rc_load_touch_symbols();
    dispatch_async(rc_touch_queue(), ^{
        __block CGSize s;
        dispatch_sync(dispatch_get_main_queue(), ^{ s = [UIScreen mainScreen].bounds.size; });
        rc_simulate_swipe(s.width * 0.5, s.height * 0.92, s.width * 0.5, s.height * 0.15);
    });
    return 0;
}

// swipeDown()
static int lua_swipe_down(lua_State *L) {
    (void)L;
    rc_load_touch_symbols();
    dispatch_async(rc_touch_queue(), ^{
        __block CGSize s;
        dispatch_sync(dispatch_get_main_queue(), ^{ s = [UIScreen mainScreen].bounds.size; });
        rc_simulate_swipe(s.width * 0.5, s.height * 0.08, s.width * 0.5, s.height * 0.85);
    });
    return 0;
}

// swipeLeft()
static int lua_swipe_left(lua_State *L) {
    (void)L;
    rc_load_touch_symbols();
    dispatch_async(rc_touch_queue(), ^{
        __block CGSize s;
        dispatch_sync(dispatch_get_main_queue(), ^{ s = [UIScreen mainScreen].bounds.size; });
        rc_simulate_swipe(s.width * 0.9, s.height * 0.5, s.width * 0.1, s.height * 0.5);
    });
    return 0;
}

// swipeRight()
static int lua_swipe_right(lua_State *L) {
    (void)L;
    rc_load_touch_symbols();
    dispatch_async(rc_touch_queue(), ^{
        __block CGSize s;
        dispatch_sync(dispatch_get_main_queue(), ^{ s = [UIScreen mainScreen].bounds.size; });
        rc_simulate_swipe(s.width * 0.1, s.height * 0.5, s.width * 0.9, s.height * 0.5);
    });
    return 0;
}



// Lua binding: openURL(urlString)
static int lua_openURL(lua_State *L) {
    const char *urlStr = luaL_checkstring(L, 1);
    NSString *urlString = [NSString stringWithUTF8String:urlStr];
    
    SRLog(@"Lua openURL: %@", urlString);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    });
    
    return 0;
}

// Lua binding: curl(urlString) - synchronous HTTP GET
static int lua_curl(lua_State *L) {
    const char *urlStr = luaL_checkstring(L, 1);
    NSString *urlString = [NSString stringWithUTF8String:urlStr];
    
    SRLog(@"Lua curl: %@", urlString);
    
    // Use native curl implementation
    NSString *curlCmd = [NSString stringWithFormat:@"curl %@", urlString];
    perform_native_curl(curlCmd);
    
    return 0;
}

// Lua binding: delay(seconds)
static int lua_delay(lua_State *L) {
    double seconds = luaL_checknumber(L, 1);
    SRLog(@"Lua delay: %.2f seconds", seconds);
    usleep((useconds_t)(seconds * 1000000));
    return 0;
}

// Lua binding: haptic()
static int lua_haptic(lua_State *L) {
    trigger_haptic();
    return 0;
}

// Lua binding: log(message)
static int lua_log(lua_State *L) {
    const char *msg = luaL_checkstring(L, 1);
    SRLog(@"[Lua] %s", msg);
    return 0;
}

// Lua binding: setLocationServices(bool) / locationServices(bool)
static int lua_set_location_services(lua_State *L) {
    BOOL state = lua_toboolean(L, 1);
    toggle_location_services(state);
    return 0;
}

// Lua binding: getLocationServices() -> bool
static int lua_get_location_services(lua_State *L) {
    BOOL state = get_location_services_state();
    lua_pushboolean(L, state ? 1 : 0);
    return 1;
}

// Lua binding: dlopen(path)
static int lua_dlopen(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    void *handle = dlopen(path, RTLD_NOW);
    if (handle) {
        lua_pushboolean(L, 1);
        return 1;
    } else {
        lua_pushnil(L);
        lua_pushstring(L, dlerror());
        return 2;
    }
}

// Helper to convert Lua arg to ObjC object
static id lua_to_id(lua_State *L, int index) {
    int type = lua_type(L, index);
    if (type == LUA_TSTRING) {
        return [NSString stringWithUTF8String:lua_tostring(L, index)];
    } else if (type == LUA_TNUMBER) {
        return @(lua_tonumber(L, index));
    } else if (type == LUA_TBOOLEAN) {
        return @(lua_toboolean(L, index));
    } else if (type == LUA_TLIGHTUSERDATA || type == LUA_TUSERDATA) {
        return (__bridge id)lua_touserdata(L, index);
    } else if (type == LUA_TNIL) {
        return nil;
    }
    return nil;
}

// Lua binding: objc_call(className, selector, args...)
static int lua_objc_call(lua_State *L) {
    int top = lua_gettop(L);
    if (top < 2) {
        lua_pushnil(L);
        lua_pushstring(L, "Usage: objc_call(className, selector, ...)");
        return 2;
    }

    // 1. Target Class or Instance
    id target = nil;
    if (lua_type(L, 1) == LUA_TSTRING) {
        const char *clsName = lua_tostring(L, 1);
        target = objc_getClass(clsName);
        if (!target) {
             lua_pushnil(L);
             lua_pushstring(L, "Class not found");
             return 2;
        }
    } else if (lua_type(L, 1) == LUA_TLIGHTUSERDATA || lua_type(L, 1) == LUA_TUSERDATA) {
        target = (__bridge id)lua_touserdata(L, 1);
    } else {
        lua_pushnil(L);
        lua_pushstring(L, "Target must be class name (string) or object (userdata)");
        return 2;
    }

    // 2. Selector
    const char *selName = luaL_checkstring(L, 2);
    SEL selector = sel_registerName(selName);
    
    // 3. Signature
    NSMethodSignature *sig = [target methodSignatureForSelector:selector];
    if (!sig) {
        lua_pushnil(L);
        lua_pushstring(L, "Method signature not found");
        return 2;
    }
    
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:target];
    [inv setSelector:selector];
    
    // 4. Arguments
    NSUInteger numArgs = [sig numberOfArguments];
    // arg 0 is self, 1 is _cmd. Lua args start at index 3 (mapped to ObjC arg 2)
    for (NSUInteger i = 2; i < numArgs; i++) {
        int luaIdx = (int)i + 1; 
        if (luaIdx > top) break;
        
        const char *type = [sig getArgumentTypeAtIndex:i];
        // Basic type handling
        if (strcmp(type, "@") == 0 || strcmp(type, "#") == 0) { // Object or Class
            id obj = lua_to_id(L, luaIdx);
            [inv setArgument:&obj atIndex:i];
        } else if (type[0] == '^') { // Pointer
            void *ptr = NULL;
            if (lua_type(L, luaIdx) == LUA_TLIGHTUSERDATA || lua_type(L, luaIdx) == LUA_TUSERDATA) {
                ptr = lua_touserdata(L, luaIdx);
            }
            [inv setArgument:&ptr atIndex:i];
        } else if (strcmp(type, "i") == 0 || strcmp(type, "s") == 0 || strcmp(type, "l") == 0 || strcmp(type, "q") == 0 || strcmp(type, "Q") == 0 || strcmp(type, "I") == 0 || strcmp(type, "S") == 0 || strcmp(type, "L") == 0) { // Integers
             long long val = (long long)lua_tonumber(L, luaIdx);
             [inv setArgument:&val atIndex:i];
        } else if (strcmp(type, "f") == 0 || strcmp(type, "d") == 0) { // Floats
             double val = lua_tonumber(L, luaIdx);
             [inv setArgument:&val atIndex:i];
        } else if (strcmp(type, "B") == 0 || strcmp(type, "c") == 0) { // BOOL / char
             BOOL val = lua_toboolean(L, luaIdx);
             [inv setArgument:&val atIndex:i];
        } else if (strcmp(type, ":") == 0) { // Selector
             const char *s = lua_tostring(L, luaIdx);
             SEL sel = sel_registerName(s);
             [inv setArgument:&sel atIndex:i];
        }
    }
    
    [inv invoke];
    
    // 5. Return Value
    const char *retType = [sig methodReturnType];
    if (strcmp(retType, "@") == 0) {
        __unsafe_unretained id retVal;
        [inv getReturnValue:&retVal];
        if (retVal == nil) {
            lua_pushnil(L);
        } else if ([retVal isKindOfClass:[NSString class]]) {
            lua_pushstring(L, [retVal UTF8String]);
        } else if ([retVal isKindOfClass:[NSNumber class]]) {
            lua_pushnumber(L, [retVal doubleValue]);
        } else {
             lua_pushlightuserdata(L, (__bridge void *)retVal);
        }
        return 1;
    } else if (strcmp(retType, "v") == 0) {
        return 0;
    } else if (strcmp(retType, "B") == 0 || strcmp(retType, "c") == 0) {
        BOOL val;
        [inv getReturnValue:&val];
        lua_pushboolean(L, val);
        return 1;
    } else if (strcmp(retType, "i") == 0 || strcmp(retType, "s") == 0 || strcmp(retType, "l") == 0 || strcmp(retType, "q") == 0 || strcmp(retType, "Q") == 0) {
        long long val;
        [inv getReturnValue:&val];
        lua_pushnumber(L, (double)val);
        return 1;
    } else {
        // Unknown return type, return nil
        return 0;
    }
}

// Execute a Lua script file
static lua_State *setup_lua_environment() {
    lua_State *L = luaL_newstate();
    if (!L) return NULL;
    
    luaL_openlibs(L);
    lua_pushcfunction(L, lua_openURL);
    lua_setglobal(L, "openURL");
    lua_pushcfunction(L, lua_curl);
    lua_setglobal(L, "curl");
    lua_pushcfunction(L, lua_delay);
    lua_setglobal(L, "delay");
    lua_pushcfunction(L, lua_haptic);
    lua_setglobal(L, "haptic");
    lua_pushcfunction(L, lua_log);
    lua_setglobal(L, "log");
    lua_pushcfunction(L, lua_dlopen);
    lua_setglobal(L, "dlopen");
    lua_pushcfunction(L, lua_objc_call);
    lua_setglobal(L, "objc_call");
    lua_pushcfunction(L, lua_set_location_services);
    lua_setglobal(L, "setLocationServices");
    lua_pushcfunction(L, lua_set_location_services);
    lua_setglobal(L, "locationServices");
    lua_pushcfunction(L, lua_get_location_services);
    lua_setglobal(L, "getLocationServices");
    
    // Touch gesture functions
    lua_pushcfunction(L, lua_tap_fn);
    lua_setglobal(L, "tap");
    lua_pushcfunction(L, lua_hold_fn);
    lua_setglobal(L, "hold");
    lua_pushcfunction(L, lua_swipe_fn);
    lua_setglobal(L, "swipe");
    lua_pushcfunction(L, lua_swipe_up);
    lua_setglobal(L, "swipeU");
    lua_pushcfunction(L, lua_swipe_up);
    lua_setglobal(L, "swipeUp");
    lua_pushcfunction(L, lua_swipe_down);
    lua_setglobal(L, "swipeD");
    lua_pushcfunction(L, lua_swipe_down);
    lua_setglobal(L, "swipeDown");
    lua_pushcfunction(L, lua_swipe_left);
    lua_setglobal(L, "swipeL");
    lua_pushcfunction(L, lua_swipe_left);
    lua_setglobal(L, "swipeLeft");
    lua_pushcfunction(L, lua_swipe_right);
    lua_setglobal(L, "swipeR");
    lua_pushcfunction(L, lua_swipe_right);
    lua_setglobal(L, "swipeRight");
    
    return L;
}

static NSString *execute_lua_script(NSString *scriptPath) {
    lua_State *L = setup_lua_environment();
    if (!L) return @"Error: Could not create Lua state";
    
    SRLog(@"Executing Lua script: %@", scriptPath);
    
    int result = luaL_dofile(L, [scriptPath UTF8String]);
    NSString *output = nil;
    
    if (result != LUA_OK) {
        const char *error = lua_tostring(L, -1);
        SRLog(@"Lua error: %s", error);
        output = [NSString stringWithFormat:@"Lua Error: %s", error];
        lua_pop(L, 1);
    } else {
        SRLog(@"Lua script completed successfully");
    }
    
    lua_close(L);
    return output;
}

static NSString *evaluate_lua_code(NSString *code) {
    lua_State *L = setup_lua_environment();
    if (!L) return @"Error: Could not create Lua state";
    
    int result = luaL_dostring(L, [code UTF8String]);
    NSString *output = nil;
    
    if (result != LUA_OK) {
        const char *error = lua_tostring(L, -1);
        output = [NSString stringWithFormat:@"Lua Error: %s", error];
        lua_pop(L, 1);
    }
    
    lua_close(L);
    return output;
}

static NSArray* RCFetchAirPlayDeviceNames() {
    __block NSArray *deviceNames = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        MPAVRoutingController *ctrl = [[objc_getClass("MPAVRoutingController") alloc] init];
        ctrl.discoveryMode = 3; // Detailed discovery
        
        __block int attempts = 0;
        __block void (^fetch)(void) = nil;
        
        fetch = ^void(void) {
            [ctrl fetchAvailableRoutesWithCompletionHandler:^(NSArray<MPAVRoute *> *routes) {
                attempts++;
                
                // If we only found 1 device (local), try again up to 3 seconds for network devices
                if (routes.count <= 1 && attempts < 6) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (fetch) fetch();
                    });
                    return;
                }
                
                NSMutableArray *names = [NSMutableArray array];
                for (MPAVRoute *route in routes) {
                    NSString *name = route.routeName;
                    if (name && name.length > 0) {
                        [names addObject:name];
                    }
                }
                deviceNames = [names copy];
                dispatch_semaphore_signal(sema);
                fetch = nil;
            }];
        };
        fetch();
    });
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    return deviceNames ?: @[];
}

static NSString *formatIvarValue(id obj, Ivar ivar) {
    ptrdiff_t offset = ivar_getOffset(ivar);
    const char *type = ivar_getTypeEncoding(ivar);
    void *ptr = (void *)((uintptr_t)obj + offset);
    
    if (type == NULL) return @"nil";
    
    if (type[0] == '@') {
        // Object
        __unsafe_unretained id val = *(__unsafe_unretained id *)ptr;
        return val ? [val description] : @"nil";
    } else if (strcmp(type, "B") == 0 || strcmp(type, "c") == 0) {
        // BOOL or char
        BOOL val = *(BOOL *)ptr;
        return val ? @"YES" : @"NO";
    } else if (strcmp(type, "i") == 0) {
        int val = *(int *)ptr;
        return [NSString stringWithFormat:@"%d", val];
    } else if (strcmp(type, "I") == 0) {
        unsigned int val = *(unsigned int *)ptr;
        return [NSString stringWithFormat:@"%u", val];
    } else if (strcmp(type, "q") == 0) {
        long long val = *(long long *)ptr;
        return [NSString stringWithFormat:@"%lld", val];
    } else if (strcmp(type, "Q") == 0) {
        unsigned long long val = *(unsigned long long *)ptr;
        return [NSString stringWithFormat:@"%llu", val];
    } else if (strcmp(type, "f") == 0) {
        float val = *(float *)ptr;
        return [NSString stringWithFormat:@"%f", val];
    } else if (strcmp(type, "d") == 0) {
        double val = *(double *)ptr;
        return [NSString stringWithFormat:@"%f", val];
    }
    return [NSString stringWithFormat:@"<type %s at offset %td>", type, offset];
}

@interface RCInsecureSessionDelegate : NSObject <NSURLSessionDelegate>
+ (instancetype)sharedDelegate;
@end

@implementation RCInsecureSessionDelegate
+ (instancetype)sharedDelegate {
    static RCInsecureSessionDelegate *del = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        del = [[RCInsecureSessionDelegate alloc] init];
    });
    return del;
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        // Accept self-signed or local network certificates (-k mode)
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}
@end

static NSDictionary *rc_execute_ha_request(NSString *endpointPath, NSString *httpMethod, NSDictionary *bodyDict, NSString *overrideUrl, NSString *overrideToken) {
    if (!g_triggerConfig) load_trigger_config();
    NSString *baseUrl = overrideUrl.length > 0 ? overrideUrl : g_triggerConfig[@"haUrl"];
    NSString *token = overrideToken.length > 0 ? overrideToken : g_triggerConfig[@"haToken"];
    
    if (![baseUrl isKindOfClass:[NSString class]] || baseUrl.length == 0 || ![token isKindOfClass:[NSString class]] || token.length == 0) {
        return @{@"ok": @NO, @"error": @"Home Assistant URL and Access Token must be configured in Settings."};
    }
    
    if ([baseUrl hasSuffix:@"/"]) {
        baseUrl = [baseUrl substringToIndex:baseUrl.length - 1];
    }
    
    NSString *fullUrlStr = [NSString stringWithFormat:@"%@%@", baseUrl, endpointPath ?: @"/api/"];
    NSURL *url = [NSURL URLWithString:fullUrlStr];
    if (!url) {
        return @{@"ok": @NO, @"error": [NSString stringWithFormat:@"Invalid Home Assistant URL: %@", fullUrlStr]};
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
    [request setHTTPMethod:httpMethod ?: @"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    if (bodyDict) {
        NSError *err = nil;
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:&err];
        if (bodyData) {
            [request setHTTPBody:bodyData];
        }
    }
    
    __block NSDictionary *resultDict = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = 10.0;
    sessionConfig.timeoutIntervalForResource = 10.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:[RCInsecureSessionDelegate sharedDelegate] delegateQueue:nil];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            resultDict = @{@"ok": @NO, @"error": error.localizedDescription ?: @"Connection failed"};
        } else {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSInteger statusCode = httpResp.statusCode;
            id parsedData = nil;
            if (data && data.length > 0) {
                parsedData = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }
            
            if (statusCode >= 200 && statusCode < 300) {
                resultDict = @{
                    @"ok": @YES,
                    @"statusCode": @(statusCode),
                    @"data": parsedData ?: [NSNull null]
                };
            } else {
                NSString *errMsg = @"HTTP Error";
                if ([parsedData isKindOfClass:[NSDictionary class]] && parsedData[@"message"]) {
                    errMsg = parsedData[@"message"];
                } else if (data) {
                    errMsg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"HTTP Error";
                }
                resultDict = @{
                    @"ok": @NO,
                    @"statusCode": @(statusCode),
                    @"error": [NSString stringWithFormat:@"HTTP %ld: %@", (long)statusCode, errMsg]
                };
            }
        }
        dispatch_semaphore_signal(sema);
    }];
    [task resume];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC));
    
    return resultDict ?: @{@"ok": @NO, @"error": @"Request timed out"};
}

static NSString *rc_execute_ha_command(NSString *cmdArgs) {
    if (!g_triggerConfig) load_trigger_config();
    BOOL haEnabled = [g_triggerConfig[@"haEnabled"] boolValue];
    if (!haEnabled) {
        return @"Error: Home Assistant is disabled in settings\n";
    }
    
    NSString *cleanArgs = [cmdArgs stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleanArgs.length == 0) {
        return @"Error: Missing Home Assistant command parameters. Usage: 'ha toggle light.bedroom' or 'ha call light.turn_on light.bedroom'\n";
    }
    
    NSArray *parts = [cleanArgs componentsSeparatedByString:@" "];
    NSString *subCmd = parts[0];
    
    NSString *domain = nil;
    NSString *service = nil;
    NSDictionary *payload = nil;
    
    if ([subCmd isEqualToString:@"toggle"] || [subCmd isEqualToString:@"turn_on"] || [subCmd isEqualToString:@"turn_off"]) {
        if (parts.count < 2) return @"Error: Missing entity ID\n";
        NSString *entityId = parts[1];
        NSArray *entityParts = [entityId componentsSeparatedByString:@"."];
        if (entityParts.count < 2) return @"Error: Invalid entity ID (expected domain.name)\n";
        domain = entityParts[0];
        service = subCmd;
        payload = @{@"entity_id": entityId};
    } else if ([subCmd isEqualToString:@"call"]) {
        if (parts.count < 3) return @"Error: Usage: ha call <domain.service> <entity_id>\n";
        NSString *domainService = parts[1];
        NSString *entityId = parts[2];
        NSArray *dsParts = [domainService componentsSeparatedByString:@"."];
        if (dsParts.count < 2) return @"Error: Invalid service name (expected domain.service)\n";
        domain = dsParts[0];
        service = dsParts[1];
        payload = @{@"entity_id": entityId};
    } else if ([subCmd isEqualToString:@"raw"]) {
        if (parts.count < 3) return @"Error: Usage: ha raw <domain.service> <json_payload>\n";
        NSString *domainService = parts[1];
        NSArray *dsParts = [domainService componentsSeparatedByString:@"."];
        if (dsParts.count < 2) return @"Error: Invalid service name (expected domain.service)\n";
        domain = dsParts[0];
        service = dsParts[1];
        NSString *jsonStr = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@" "];
        NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        if (jsonData) {
            payload = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        }
        if (!payload) return @"Error: Invalid JSON payload\n";
    } else {
        if ([subCmd containsString:@"."]) {
            NSArray *dsParts = [subCmd componentsSeparatedByString:@"."];
            domain = dsParts[0];
            service = dsParts[1];
            if (parts.count > 1) {
                payload = @{@"entity_id": parts[1]};
            } else {
                payload = @{};
            }
        } else if (parts.count >= 2) {
            NSString *entityId = parts[1];
            NSArray *entityParts = [entityId componentsSeparatedByString:@"."];
            if (entityParts.count >= 2) {
                domain = entityParts[0];
                service = subCmd;
                payload = @{@"entity_id": entityId};
            }
        }
    }
    
    if (!domain || !service) {
        return @"Error: Unable to parse Home Assistant command. Examples: 'ha toggle light.bedroom', 'ha call light.turn_on light.bedroom'\n";
    }
    
    NSString *path = [NSString stringWithFormat:@"/api/services/%@/%@", domain, service];
    NSDictionary *res = rc_execute_ha_request(path, @"POST", payload, nil, nil);
    if ([res[@"ok"] boolValue]) {
        rc_show_hud_toast(@"Home Assistant", [NSString stringWithFormat:@"Executed %@.%@", domain, service], @"house.fill");
        return [NSString stringWithFormat:@"Home Assistant call succeeded: %@.%@\n", domain, service];
    } else {
        return [NSString stringWithFormat:@"Home Assistant call failed: %@\n", res[@"error"] ?: @"Unknown error"];
    }
}

static NSDictionary *rc_execute_km_request(NSString *endpointPath, NSString *httpMethod, NSDictionary *queryParams, NSString *overrideUrl, NSString *overrideUser, NSString *overridePass) {
    if (!g_triggerConfig) load_trigger_config();
    NSString *baseUrl = overrideUrl.length > 0 ? overrideUrl : g_triggerConfig[@"kmUrl"];
    NSString *user = overrideUser.length > 0 ? overrideUser : g_triggerConfig[@"kmUser"];
    NSString *pass = overridePass.length > 0 ? overridePass : g_triggerConfig[@"kmPassword"];
    
    if (![baseUrl isKindOfClass:[NSString class]] || baseUrl.length == 0) {
        return @{@"ok": @NO, @"error": @"Keyboard Maestro URL must be configured in Settings."};
    }
    
    if (![baseUrl hasPrefix:@"http://"] && ![baseUrl hasPrefix:@"https://"]) {
        baseUrl = [NSString stringWithFormat:@"http://%@", baseUrl];
    }
    
    if ([baseUrl hasSuffix:@"/"]) {
        baseUrl = [baseUrl substringToIndex:baseUrl.length - 1];
    }
    
    NSString *fullUrlStr = nil;
    if (endpointPath.length > 0) {
        NSString *cleanedBase = baseUrl;
        if ([cleanedBase hasSuffix:@"/action.html"]) {
            cleanedBase = [cleanedBase substringToIndex:cleanedBase.length - 12];
        } else if ([cleanedBase hasSuffix:@"/authenticatedaction.html"]) {
            cleanedBase = [cleanedBase substringToIndex:cleanedBase.length - 25];
        } else if ([cleanedBase hasSuffix:@"/authenticated.html"]) {
            cleanedBase = [cleanedBase substringToIndex:cleanedBase.length - 19];
        }
        if ([cleanedBase hasSuffix:@"/"]) {
            cleanedBase = [cleanedBase substringToIndex:cleanedBase.length - 1];
        }
        NSString *ep = endpointPath;
        if (![ep hasPrefix:@"/"] && ![ep hasPrefix:@"?"]) {
            ep = [NSString stringWithFormat:@"/%@", ep];
        }
        fullUrlStr = [NSString stringWithFormat:@"%@%@", cleanedBase, ep];
    } else if ([baseUrl containsString:@"/action.html"] || [baseUrl containsString:@"/authenticatedaction.html"]) {
        fullUrlStr = baseUrl;
    } else {
        NSString *ep = (user.length > 0 || pass.length > 0) ? @"/authenticatedaction.html" : @"/action.html";
        fullUrlStr = [NSString stringWithFormat:@"%@%@", baseUrl, ep];
    }
    
    if (queryParams.count > 0) {
        NSMutableArray *queryItems = [NSMutableArray array];
        NSCharacterSet *allowedChars = [NSCharacterSet URLQueryAllowedCharacterSet];
        for (NSString *key in queryParams) {
            NSString *val = [NSString stringWithFormat:@"%@", queryParams[key]];
            NSString *encKey = [key stringByAddingPercentEncodingWithAllowedCharacters:allowedChars];
            NSString *encVal = [val stringByAddingPercentEncodingWithAllowedCharacters:allowedChars];
            [queryItems addObject:[NSString stringWithFormat:@"%@=%@", encKey, encVal]];
        }
        NSString *delim = [fullUrlStr containsString:@"?"] ? @"&" : @"?";
        fullUrlStr = [NSString stringWithFormat:@"%@%@%@", fullUrlStr, delim, [queryItems componentsJoinedByString:@"&"]];
    }
    
    NSURL *url = [NSURL URLWithString:fullUrlStr];
    if (!url) {
        return @{@"ok": @NO, @"error": [NSString stringWithFormat:@"Invalid Keyboard Maestro URL: %@", fullUrlStr]};
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
    [request setHTTPMethod:httpMethod ?: @"GET"];
    
    if (user.length > 0 || pass.length > 0) {
        NSString *authStr = [NSString stringWithFormat:@"%@:%@", user ?: @"", pass ?: @""];
        NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64Auth = [authData base64EncodedStringWithOptions:0];
        [request setValue:[NSString stringWithFormat:@"Basic %@", base64Auth] forHTTPHeaderField:@"Authorization"];
    }
    
    __block NSDictionary *resultDict = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = 10.0;
    sessionConfig.timeoutIntervalForResource = 10.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:[RCInsecureSessionDelegate sharedDelegate] delegateQueue:nil];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            resultDict = @{@"ok": @NO, @"error": error.localizedDescription ?: @"Connection failed"};
        } else {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSInteger statusCode = httpResp.statusCode;
            NSString *respText = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            
            if (statusCode >= 200 && statusCode < 400) {
                resultDict = @{
                    @"ok": @YES,
                    @"statusCode": @(statusCode),
                    @"data": respText ?: @""
                };
            } else if (statusCode == 401) {
                resultDict = @{
                    @"ok": @NO,
                    @"statusCode": @(statusCode),
                    @"error": @"HTTP 401: Unauthorized (check Web Server username/password)"
                };
            } else if (statusCode == 400 || statusCode == 404) {
                // KM Web server returns 400/404 if macro name is not found, but connection itself succeeded
                resultDict = @{
                    @"ok": @YES,
                    @"statusCode": @(statusCode),
                    @"data": respText ?: @""
                };
            } else {
                resultDict = @{
                    @"ok": @NO,
                    @"statusCode": @(statusCode),
                    @"error": [NSString stringWithFormat:@"HTTP %ld: %@", (long)statusCode, respText.length > 0 ? respText : @"Server returned error"]
                };
            }
        }
        dispatch_semaphore_signal(sema);
    }];
    [task resume];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC));
    
    return resultDict ?: @{@"ok": @NO, @"error": @"Request timed out"};
}

static NSString *rc_decode_html_entities(NSString *str) {
    if (!str) return @"";
    NSString *decoded = [str stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    return decoded;
}

static NSArray<NSDictionary *> *rc_parse_km_html(NSString *html) {
    if (!html || html.length == 0) return @[];
    
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groupsMap = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *groupOrder = [NSMutableArray array];
    
    NSRegularExpression *optgroupRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)<optgroup\\s+[^>]*label=\"([^\"]+)\"[^>]*>([\\s\\S]*?)(?:</optgroup>|(?=<optgroup)|$)" options:0 error:nil];
    NSRegularExpression *optionRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)<option\\b([^>]+)>" options:0 error:nil];
    NSRegularExpression *labelAttrRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\blabel=\"([^\"]+)\"" options:0 error:nil];
    NSRegularExpression *valueAttrRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\bvalue=\"([^\"]+)\"" options:0 error:nil];
    
    NSArray<NSTextCheckingResult *> *groupMatches = [optgroupRegex matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    for (NSTextCheckingResult *gMatch in groupMatches) {
        if (gMatch.numberOfRanges < 3) continue;
        NSString *rawGroupName = [html substringWithRange:[gMatch rangeAtIndex:1]];
        NSString *groupName = rc_decode_html_entities([rawGroupName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
        if (groupName.length == 0) continue;
        
        NSRange contentRange = [gMatch rangeAtIndex:2];
        if (contentRange.location == NSNotFound || contentRange.length == 0) continue;
        NSString *groupContent = [html substringWithRange:contentRange];
        
        NSMutableArray *macros = [NSMutableArray array];
        NSArray<NSTextCheckingResult *> *optMatches = [optionRegex matchesInString:groupContent options:0 range:NSMakeRange(0, groupContent.length)];
        for (NSTextCheckingResult *oMatch in optMatches) {
            NSString *tagAttrs = [groupContent substringWithRange:[oMatch rangeAtIndex:1]];
            
            NSTextCheckingResult *lMatch = [labelAttrRegex firstMatchInString:tagAttrs options:0 range:NSMakeRange(0, tagAttrs.length)];
            NSTextCheckingResult *vMatch = [valueAttrRegex firstMatchInString:tagAttrs options:0 range:NSMakeRange(0, tagAttrs.length)];
            
            if (lMatch && lMatch.numberOfRanges >= 2 && vMatch && vMatch.numberOfRanges >= 2) {
                NSString *macroName = rc_decode_html_entities([[tagAttrs substringWithRange:[lMatch rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
                NSString *macroUid = [[tagAttrs substringWithRange:[vMatch rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (macroName.length > 0 && macroUid.length > 0) {
                    [macros addObject:@{
                        @"name": macroName,
                        @"uid": macroUid
                    }];
                }
            }
        }
        
        if (macros.count == 0) continue;
        
        NSString *groupKey = [groupName lowercaseString];
        NSMutableDictionary *existingGroup = groupsMap[groupKey];
        if (existingGroup) {
            NSMutableArray *existingMacros = existingGroup[@"macros"];
            NSMutableSet *existingUids = [NSMutableSet set];
            for (NSDictionary *m in existingMacros) {
                if (m[@"uid"]) [existingUids addObject:m[@"uid"]];
            }
            for (NSDictionary *m in macros) {
                if (![existingUids containsObject:m[@"uid"]]) {
                    [existingMacros addObject:m];
                    [existingUids addObject:m[@"uid"]];
                }
            }
        } else {
            NSMutableDictionary *newGroup = [NSMutableDictionary dictionaryWithDictionary:@{
                @"name": groupName,
                @"macros": macros
            }];
            groupsMap[groupKey] = newGroup;
            [groupOrder addObject:groupKey];
        }
    }
    
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in groupOrder) {
        if (groupsMap[key]) {
            [result addObject:groupsMap[key]];
        }
    }
    return result;
}

static NSString *rc_execute_km_command(NSString *cmdArgs) {
    if (!g_triggerConfig) load_trigger_config();
    BOOL kmEnabled = [g_triggerConfig[@"kmEnabled"] boolValue];
    if (!kmEnabled) {
        return @"Error: Keyboard Maestro is disabled in settings\n";
    }
    
    NSString *cleanArgs = [cmdArgs stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleanArgs.length == 0) {
        return @"Error: Missing Keyboard Maestro command parameters. Usage: 'km trigger <macro_name_or_uuid> [value]' or 'km <macro_name_or_uuid>'\n";
    }
    
    if ([cleanArgs hasPrefix:@"url "] || [cleanArgs hasPrefix:@"http://"] || [cleanArgs hasPrefix:@"https://"]) {
        NSString *urlStr = [cleanArgs hasPrefix:@"url "] ? [cleanArgs substringFromIndex:4] : cleanArgs;
        urlStr = [urlStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url) {
            return [NSString stringWithFormat:@"Error: Invalid URL: %@\n", urlStr];
        }
        
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
        [req setHTTPMethod:@"GET"];
        
        NSString *user = g_triggerConfig[@"kmUser"];
        NSString *pass = g_triggerConfig[@"kmPassword"];
        if (user.length > 0 || pass.length > 0) {
            NSString *authStr = [NSString stringWithFormat:@"%@:%@", user ?: @"", pass ?: @""];
            NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
            NSString *base64Auth = [authData base64EncodedStringWithOptions:0];
            [req setValue:[NSString stringWithFormat:@"Basic %@", base64Auth] forHTTPHeaderField:@"Authorization"];
        }
        
        __block NSString *respMsg = nil;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        sessionConfig.timeoutIntervalForRequest = 10.0;
        sessionConfig.timeoutIntervalForResource = 10.0;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:[RCInsecureSessionDelegate sharedDelegate] delegateQueue:nil];
        [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err) {
                respMsg = [NSString stringWithFormat:@"Error: %@\n", err.localizedDescription];
            } else {
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
                if (http.statusCode >= 200 && http.statusCode < 400) {
                    rc_show_hud_toast(@"Keyboard Maestro", @"Triggered URL Macro", @"command");
                    respMsg = [NSString stringWithFormat:@"Keyboard Maestro trigger succeeded (HTTP %ld)\n", (long)http.statusCode];
                } else if (http.statusCode == 401) {
                    respMsg = @"Keyboard Maestro error (HTTP 401: Unauthorized - Check Username/Password)\n";
                } else {
                    respMsg = [NSString stringWithFormat:@"Keyboard Maestro error (HTTP %ld)\n", (long)http.statusCode];
                }
            }
            dispatch_semaphore_signal(sema);
        }] resume];
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC));
        return respMsg ?: @"Keyboard Maestro URL request sent\n";
    }
    
    NSString *macroName = nil;
    NSString *triggerValue = nil;
    
    if ([cleanArgs hasPrefix:@"trigger "]) {
        NSString *afterTrigger = [[cleanArgs substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([afterTrigger hasPrefix:@"\""]) {
            NSRange endQuote = [afterTrigger rangeOfString:@"\"" options:0 range:NSMakeRange(1, afterTrigger.length - 1)];
            if (endQuote.location != NSNotFound) {
                macroName = [afterTrigger substringWithRange:NSMakeRange(1, endQuote.location - 1)];
                NSString *rem = [[afterTrigger substringFromIndex:endQuote.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (rem.length > 0) {
                    if ([rem hasPrefix:@"\""] && [rem hasSuffix:@"\""] && rem.length >= 2) {
                        triggerValue = [rem substringWithRange:NSMakeRange(1, rem.length - 2)];
                    } else {
                        triggerValue = rem;
                    }
                }
            }
        }
        if (!macroName) {
            NSArray *parts = [afterTrigger componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSMutableArray *cleanParts = [NSMutableArray array];
            for (NSString *p in parts) {
                if (p.length > 0) [cleanParts addObject:p];
            }
            if (cleanParts.count > 0) {
                macroName = cleanParts[0];
                if (cleanParts.count > 1) {
                    triggerValue = [[cleanParts subarrayWithRange:NSMakeRange(1, cleanParts.count - 1)] componentsJoinedByString:@" "];
                }
            }
        }
    } else {
        if ([cleanArgs hasPrefix:@"\""]) {
            NSRange endQuote = [cleanArgs rangeOfString:@"\"" options:0 range:NSMakeRange(1, cleanArgs.length - 1)];
            if (endQuote.location != NSNotFound) {
                macroName = [cleanArgs substringWithRange:NSMakeRange(1, endQuote.location - 1)];
                NSString *rem = [[cleanArgs substringFromIndex:endQuote.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (rem.length > 0) triggerValue = rem;
            }
        }
        if (!macroName) {
            macroName = cleanArgs;
        }
    }
    
    if (!macroName || macroName.length == 0) {
        return @"Error: Missing macro name or UUID\n";
    }
    
    NSString *macroToExecute = macroName;
    NSRegularExpression *uuidRegex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-fA-F-]{30,}$" options:0 error:nil];
    BOOL isUUID = [uuidRegex numberOfMatchesInString:macroName options:0 range:NSMakeRange(0, macroName.length)] > 0;
    
    if (!isUUID) {
        // Fetch macro list from KM Web Server to resolve friendly macroName to its UID
        NSDictionary *macrosRes = rc_execute_km_request(@"authenticated.html", @"GET", nil, nil, nil, nil);
        if (![macrosRes[@"ok"] boolValue]) {
            macrosRes = rc_execute_km_request(@"/", @"GET", nil, nil, nil, nil);
        }
        if ([macrosRes[@"ok"] boolValue] && [macrosRes[@"data"] isKindOfClass:[NSString class]]) {
            NSArray *groups = rc_parse_km_html(macrosRes[@"data"]);
            for (NSDictionary *group in groups) {
                NSArray *macros = group[@"macros"];
                for (NSDictionary *m in macros) {
                    if ([m[@"name"] localizedCaseInsensitiveCompare:macroName] == NSOrderedSame) {
                        macroToExecute = m[@"uid"];
                        break;
                    }
                }
                if (![macroToExecute isEqualToString:macroName]) break;
            }
        }
    }
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"macro"] = macroToExecute;
    if (triggerValue.length > 0) {
        params[@"value"] = triggerValue;
    }
    
    NSString *user = g_triggerConfig[@"kmUser"];
    NSString *pass = g_triggerConfig[@"kmPassword"];
    NSString *defaultEndpoint = (user.length > 0 || pass.length > 0) ? @"/authenticatedaction.html" : @"/action.html";
    
    NSDictionary *res = rc_execute_km_request(defaultEndpoint, @"GET", params, nil, nil, nil);
    if (![res[@"ok"] boolValue] && [defaultEndpoint isEqualToString:@"/authenticatedaction.html"]) {
        NSDictionary *fallbackRes = rc_execute_km_request(@"/action.html", @"GET", params, nil, nil, nil);
        if ([fallbackRes[@"ok"] boolValue]) {
            res = fallbackRes;
        }
    }
    if (![res[@"ok"] boolValue] && ![macroToExecute isEqualToString:macroName]) {
        // Fallback with original macroName if UID execution failed
        NSMutableDictionary *fallbackParams = [params mutableCopy];
        fallbackParams[@"macro"] = macroName;
        NSDictionary *nameRes = rc_execute_km_request(defaultEndpoint, @"GET", fallbackParams, nil, nil, nil);
        if ([nameRes[@"ok"] boolValue]) {
            res = nameRes;
        }
    }
    
    NSString *displayName = macroName;
    if (isUUID && g_triggerConfig[@"kmNamesByUuid"] && [g_triggerConfig[@"kmNamesByUuid"] isKindOfClass:[NSDictionary class]]) {
        NSString *resolved = g_triggerConfig[@"kmNamesByUuid"][macroName];
        if (resolved.length > 0) {
            displayName = resolved;
        }
    }
    
    if ([res[@"ok"] boolValue]) {
        NSString *toastMsg = [NSString stringWithFormat:@"Triggered %@", displayName];
        rc_show_hud_toast(@"Keyboard Maestro", toastMsg, @"command");
        return [NSString stringWithFormat:@"Keyboard Maestro macro triggered: %@\n", displayName];
    } else {
        return [NSString stringWithFormat:@"Keyboard Maestro trigger failed: %@\n", res[@"error"] ?: @"Unknown error"];
    }
}

static BOOL rc_mqtt_publish(NSString *host, NSInteger port, NSString *user, NSString *pass, NSString *clientId, NSString *topic, NSString *payload, NSInteger qos, BOOL retain, NSError **error) {
    if (!host.length) {
        if (error) *error = [NSError errorWithDomain:@"RCMQTT" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Host is empty"}];
        return NO;
    }
    
    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%ld", (long)(port > 0 ? port : 1883));
    
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    
    struct addrinfo *res = NULL;
    int gai_err = getaddrinfo([host UTF8String], portStr, &hints, &res);
    if (gai_err != 0 || !res) {
        if (error) *error = [NSError errorWithDomain:@"RCMQTT" code:-3 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not resolve host: %s", gai_strerror(gai_err)]}];
        return NO;
    }
    
    int sockfd = -1;
    for (struct addrinfo *rp = res; rp != NULL; rp = rp->ai_next) {
        sockfd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (sockfd == -1) continue;
        
        int flags = fcntl(sockfd, F_GETFL, 0);
        fcntl(sockfd, F_SETFL, flags | O_NONBLOCK);
        
        int conn = connect(sockfd, rp->ai_addr, rp->ai_addrlen);
        if (conn == 0) {
            fcntl(sockfd, F_SETFL, flags);
            break;
        }
        if (errno == EINPROGRESS) {
            fd_set fdset;
            FD_ZERO(&fdset);
            FD_SET(sockfd, &fdset);
            struct timeval tv = { 5, 0 };
            if (select(sockfd + 1, NULL, &fdset, NULL, &tv) == 1) {
                int so_error = 0;
                socklen_t len = sizeof(so_error);
                getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &so_error, &len);
                if (so_error == 0) {
                    fcntl(sockfd, F_SETFL, flags);
                    break;
                }
            }
        }
        close(sockfd);
        sockfd = -1;
    }
    freeaddrinfo(res);
    
    if (sockfd == -1) {
        if (error) *error = [NSError errorWithDomain:@"RCMQTT" code:-4 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not connect to %@:%ld", host, (long)port]}];
        return NO;
    }
    
    struct timeval rtv = { 5, 0 };
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, (const char *)&rtv, sizeof(rtv));
    setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, (const char *)&rtv, sizeof(rtv));
    
    // Build CONNECT packet
    NSMutableData *varHeader = [NSMutableData data];
    uint16_t protoNameLen = htons(4);
    [varHeader appendBytes:&protoNameLen length:2];
    [varHeader appendBytes:"MQTT" length:4];
    uint8_t protoLevel = 4;
    [varHeader appendBytes:&protoLevel length:1];
    uint8_t connFlags = 0x02; // Clean session
    if (user.length > 0) connFlags |= 0x80;
    if (pass.length > 0) connFlags |= 0x40;
    [varHeader appendBytes:&connFlags length:1];
    uint16_t keepAlive = htons(60);
    [varHeader appendBytes:&keepAlive length:2];
    rc_mqtt_append_utf8(varHeader, clientId.length > 0 ? clientId : @"RemoteCompanion");
    if (user.length > 0) rc_mqtt_append_utf8(varHeader, user);
    if (pass.length > 0) rc_mqtt_append_utf8(varHeader, pass);
    
    NSMutableData *connPkt = [NSMutableData data];
    uint8_t connType = 0x10;
    [connPkt appendBytes:&connType length:1];
    rc_mqtt_append_rem_len(connPkt, varHeader.length);
    [connPkt appendData:varHeader];
    
    send(sockfd, connPkt.bytes, connPkt.length, 0);
    
    uint8_t connack[4];
    ssize_t n = recv(sockfd, connack, 4, 0);
    if (n < 4 || connack[0] != 0x20 || connack[3] != 0x00) {
        close(sockfd);
        if (error) *error = [NSError errorWithDomain:@"RCMQTT" code:-5 userInfo:@{NSLocalizedDescriptionKey: (n >= 4 && connack[3] != 0) ? [NSString stringWithFormat:@"Broker rejected connection (code %d)", connack[3]] : @"Invalid CONNACK from broker"}];
        return NO;
    }
    
    if (topic.length > 0) {
        NSMutableData *pubPayload = [NSMutableData data];
        rc_mqtt_append_utf8(pubPayload, topic);
        if (qos > 0) {
            uint16_t pktId = htons(1);
            [pubPayload appendBytes:&pktId length:2];
        }
        if (payload.length > 0) {
            NSData *pData = [payload dataUsingEncoding:NSUTF8StringEncoding];
            if (pData) [pubPayload appendData:pData];
        }
        
        NSMutableData *pubPkt = [NSMutableData data];
        uint8_t pubType = 0x30;
        if (qos == 1) pubType |= 0x02;
        if (retain) pubType |= 0x01;
        [pubPkt appendBytes:&pubType length:1];
        rc_mqtt_append_rem_len(pubPkt, pubPayload.length);
        [pubPkt appendData:pubPayload];
        
        send(sockfd, pubPkt.bytes, pubPkt.length, 0);
    }
    
    uint8_t disconnectPacket[] = { 0xE0, 0x00 };
    send(sockfd, disconnectPacket, sizeof(disconnectPacket), 0);
    close(sockfd);
    return YES;
}

static NSString *rc_execute_mqtt_command(NSString *cmdArgs) {
    if (!g_triggerConfig) load_trigger_config();
    BOOL mqttEnabled = [g_triggerConfig[@"mqttEnabled"] boolValue];
    if (!mqttEnabled) {
        return @"Error: MQTT is disabled in settings\n";
    }
    
    NSString *cleanArgs = [cmdArgs stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleanArgs.length == 0) {
        return @"Error: Missing MQTT parameters. Usage: 'mqtt pub <topic> [payload]' or 'mqtt publish <topic> [payload]'\n";
    }
    
    NSString *host = g_triggerConfig[@"mqttHost"] ?: @"192.168.1.50";
    NSInteger port = [g_triggerConfig[@"mqttPort"] integerValue];
    if (port <= 0) port = 1883;
    NSString *user = g_triggerConfig[@"mqttUser"];
    NSString *pass = g_triggerConfig[@"mqttPassword"];
    NSString *clientId = g_triggerConfig[@"mqttClientId"] ?: @"RemoteCompanion";
    
    NSString *topic = nil;
    NSString *payload = nil;
    
    NSString *after = cleanArgs;
    if ([cleanArgs hasPrefix:@"publish "] || [cleanArgs hasPrefix:@"pub "]) {
        after = [cleanArgs hasPrefix:@"publish "] ? [cleanArgs substringFromIndex:8] : [cleanArgs substringFromIndex:4];
        after = [after stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    
    if ([after hasPrefix:@"\""]) {
        NSRange endQuote = [after rangeOfString:@"\"" options:0 range:NSMakeRange(1, after.length - 1)];
        if (endQuote.location != NSNotFound) {
            topic = [after substringWithRange:NSMakeRange(1, endQuote.location - 1)];
            NSString *rem = [[after substringFromIndex:endQuote.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (rem.length > 0) {
                if ([rem hasPrefix:@"\""] && [rem hasSuffix:@"\""] && rem.length >= 2) {
                    payload = [rem substringWithRange:NSMakeRange(1, rem.length - 2)];
                } else {
                    payload = rem;
                }
            }
        }
    }
    if (!topic) {
        NSArray *parts = [after componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *cleanParts = [NSMutableArray array];
        for (NSString *p in parts) { if (p.length > 0) [cleanParts addObject:p]; }
        if (cleanParts.count > 0) {
            topic = cleanParts[0];
            if (cleanParts.count > 1) {
                payload = [[cleanParts subarrayWithRange:NSMakeRange(1, cleanParts.count - 1)] componentsJoinedByString:@" "];
            }
        }
    }
    
    if (!topic || topic.length == 0) {
        return @"Error: Missing MQTT topic\n";
    }
    
    NSError *error = nil;
    BOOL success = rc_mqtt_publish(host, port, user, pass, clientId, topic, payload ?: @"", 0, NO, &error);
    if (success) {
        NSString *toastDetail = payload.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", topic, payload] : topic;
        rc_show_hud_toast(@"MQTT Published", toastDetail, @"antenna.radiowaves.left.and.right");
        return [NSString stringWithFormat:@"MQTT message published to '%@'\n", topic];
    } else {
        return [NSString stringWithFormat:@"MQTT publish failed: %@\n", error.localizedDescription ?: @"Connection error"];
    }
}

static void rc_execute_shortcut(NSString *shortcutName, NSString *inputArg) {
    if (!shortcutName || shortcutName.length == 0) return;
    
    NSString *cleanName = [shortcutName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([cleanName hasPrefix:@"\""] && [cleanName hasSuffix:@"\""] && cleanName.length >= 2) {
        cleanName = [cleanName substringWithRange:NSMakeRange(1, cleanName.length - 2)];
    }
    
    SRLog(@"[Shortcut] Attempting execution for: '%@'", cleanName);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            // 1. Try Native VoiceShortcutClient / WorkflowKit execution (iOS 15 / 16 / 17)
            dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient", RTLD_NOW);
            dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_NOW);
            
            Class WFSiriRunRequestClass = objc_getClass("WFSiriWorkflowRunRequest");
            Class WFSiriClientClass = objc_getClass("WFSiriWorkflowRunnerClient");
            if (WFSiriRunRequestClass && WFSiriClientClass) {
                id req = nil;
                if ([WFSiriRunRequestClass respondsToSelector:@selector(alloc)]) {
                    id allocReq = [WFSiriRunRequestClass alloc];
                    SEL initSel = NSSelectorFromString(@"initWithWorkflowName:input:");
                    if ([allocReq respondsToSelector:initSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        req = [allocReq performSelector:initSel withObject:cleanName withObject:inputArg];
#pragma clang diagnostic pop
                    }
                }
                if (req) {
                    id client = nil;
                    SEL initClientSel = NSSelectorFromString(@"initWithRunRequest:");
                    if ([WFSiriClientClass instancesRespondToSelector:initClientSel]) {
                        id allocClient = [WFSiriClientClass alloc];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        client = [allocClient performSelector:initClientSel withObject:req];
#pragma clang diagnostic pop
                    }
                    if (client && [client respondsToSelector:@selector(start)]) {
                        [client performSelector:@selector(start)];
                        SRLog(@"[Shortcut] Started via WFSiriWorkflowRunnerClient for '%@'", cleanName);
                        return;
                    }
                }
            }
            
            Class WFWorkflowDescriptorClass = objc_getClass("WFWorkflowDescriptor");
            Class WFWorkflowRunnerClientClass = objc_getClass("WFWorkflowRunnerClient");
            if (WFWorkflowDescriptorClass && WFWorkflowRunnerClientClass) {
                id descriptor = [WFWorkflowDescriptorClass alloc];
                if ([descriptor respondsToSelector:@selector(initWithName:)]) {
                    descriptor = [descriptor initWithName:cleanName];
                } else {
                    SEL sel = NSSelectorFromString(@"initWithIdentifier:");
                    if ([descriptor respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        descriptor = [descriptor performSelector:sel withObject:cleanName];
#pragma clang diagnostic pop
                    } else {
                        descriptor = nil;
                    }
                }
                if (descriptor) {
                    WFWorkflowRunnerClient *client = (WFWorkflowRunnerClient *)[[WFWorkflowRunnerClientClass alloc] initWithWorkflowDescriptor:descriptor input:inputArg parseInput:NO output:nil completion:^(id output, NSError *error) {
                        if (error) {
                            SRLog(@"[Shortcut] '%@' failed: %@", cleanName, error);
                        } else {
                            SRLog(@"[Shortcut] '%@' completed successfully", cleanName);
                        }
                    }];
                    if (client) {
                        [client start];
                        SRLog(@"[Shortcut] Started via WFWorkflowRunnerClient for '%@'", cleanName);
                        return;
                    }
                }
            }
            
            // 2. Fallback to springcuts binary via posix_spawn
            NSString *springcutsPath = [NSString stringWithFormat:@"%@/usr/bin/springcuts", root_prefix()];
            if (![[NSFileManager defaultManager] fileExistsAtPath:springcutsPath]) {
                springcutsPath = @"/var/jb/usr/bin/springcuts";
            }
            if (![[NSFileManager defaultManager] fileExistsAtPath:springcutsPath]) {
                springcutsPath = @"/usr/bin/springcuts";
            }
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:springcutsPath]) {
                NSMutableArray *args = [NSMutableArray array];
                [args addObject:springcutsPath];
                [args addObject:@"-r"];
                [args addObject:cleanName];
                if (inputArg && inputArg.length > 0) {
                    [args addObject:@"-p"];
                    [args addObject:inputArg];
                }
                
                char **argv = (char **)malloc((args.count + 1) * sizeof(char *));
                for (NSUInteger i = 0; i < args.count; i++) {
                    argv[i] = (char *)[args[i] UTF8String];
                }
                argv[args.count] = NULL;
                
                pid_t pid;
                extern char **environ;
                int result = rc_posix_spawn(&pid, [springcutsPath UTF8String], NULL, NULL, argv, environ);
                free(argv);
                
                if (result == 0) {
                    SRLog(@"[Shortcut] Spawned springcuts pid=%d for '%@'", pid, cleanName);
                    // Background watchdog reaper: monitor completion and terminate if stuck
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                        int status;
                        for (int i = 0; i < 30; i++) { // 30 x 500ms = 15s max
                            pid_t w = waitpid(pid, &status, WNOHANG);
                            if (w == pid || w < 0) {
                                return; // Exited cleanly
                            }
                            usleep(500000);
                        }
                        SRLog(@"[Shortcut] springcuts pid=%d timed out (15s limit) - terminating", pid);
                        kill(pid, SIGKILL);
                        waitpid(pid, &status, 0);
                    });
                    return;
                } else {
                    SRLog(@"[Shortcut] posix_spawn springcuts failed: %d (%s)", result, strerror(result));
                }
            }
            
            // 3. Fallback to shortcuts://run-shortcut URL Scheme
            NSString *encodedName = [cleanName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            NSMutableString *urlStr = [NSMutableString stringWithFormat:@"shortcuts://run-shortcut?name=%@", encodedName];
            if (inputArg && inputArg.length > 0) {
                NSString *encodedInput = [inputArg stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                [urlStr appendFormat:@"&input=text&text=%@", encodedInput];
            }
            NSURL *url = [NSURL URLWithString:urlStr];
            if (url) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    Class LSWorkspaceClass = objc_getClass("LSApplicationWorkspace");
                    if (LSWorkspaceClass && [LSWorkspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
                        id ws = [LSWorkspaceClass performSelector:@selector(defaultWorkspace)];
                        if ([ws respondsToSelector:@selector(openURL:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                            [ws performSelector:@selector(openURL:) withObject:url];
#pragma clang diagnostic pop
                            SRLog(@"[Shortcut] Invoked via LSApplicationWorkspace URL: %@", urlStr);
                            return;
                        }
                    }
                    if ([[UIApplication sharedApplication] respondsToSelector:@selector(openURL:options:completionHandler:)]) {
                        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                            SRLog(@"[Shortcut] UIApplication openURL success=%d: %@", success, urlStr);
                        }];
                    }
                });
                return;
            }
        } @catch (NSException *e) {
            SRLog(@"[Shortcut] Exception running shortcut '%@': %@", cleanName, e);
        }
    });
}

static NSString *rc_open_camera_unified(NSInteger mode, NSInteger device, double zoomFactor, NSInteger flashMode, BOOL autoShutter) {
    if (zoomFactor <= 0) zoomFactor = (mode == 1 && device == 0) ? 2.0 : 1.0;
    
    NSString *modeName = @"Photo";
    NSString *icon = @"camera.fill";
    if (mode == 1) { modeName = @"Video"; icon = @"video.fill"; }
    else if (mode == 2) { modeName = @"Slo-Mo"; icon = @"video.fill"; }
    else if (mode == 3) { modeName = @"Pano"; icon = @"camera.fill"; }
    else if (mode == 4 || mode == 5) { modeName = @"Time-Lapse"; icon = @"video.fill"; }
    else if (mode == 6) { modeName = @"Portrait"; icon = @"camera.fill"; }
    else if (mode == 7) { modeName = @"Cinematic"; icon = @"video.fill"; }
    
    if (flashMode == 1) icon = @"bolt.fill";
    
    SRLog(@"[Camera] Opening Camera: mode=%ld (%@), device=%ld, zoom=%.1fx, flash=%ld, autoShutter=%d", 
          (long)mode, modeName, (long)device, zoomFactor, (long)flashMode, autoShutter);
    
    // 1. Write camera intent payload for com.apple.camera hook
    @try {
        NSDictionary *intent = @{
            @"uuid": [[NSUUID UUID] UUIDString],
            @"mode": @(mode),
            @"device": @(device),
            @"zoom": @(zoomFactor),
            @"flash": @(flashMode),
            @"autoShutter": @(autoShutter),
            @"timestamp": @([[NSDate date] timeIntervalSince1970])
        };
        [intent writeToFile:@"/tmp/rc_camera_intent.plist" atomically:YES];
        notify_post("com.saihgupr.remotecompanion.camera_intent");
    } @catch (NSException *e) {
        SRLog(@"[Camera] Error writing camera intent: %@", e);
    }
    
    // 2. Configure Camera preferences in com.apple.camera
    @try {
        CFStringRef appID = CFSTR("com.apple.camera");
        CFPreferencesSetAppValue(CFSTR("UserPreferencesCaptureMode"), (CFPropertyListRef)@(mode), appID);
        CFPreferencesSetAppValue(CFSTR("CAMUserPreferencesCaptureModeKey"), (CFPropertyListRef)@(mode), appID);
        CFPreferencesSetAppValue(CFSTR("UserPreferencesExplicitCaptureModeKey"), (CFPropertyListRef)@(mode), appID);
        CFPreferencesSetAppValue(CFSTR("UserPreferencesPreserveCaptureModeKey"), (CFPropertyListRef)@YES, appID);
        CFPreferencesSetAppValue(CFSTR("CAMUserPreferencesPreserveCaptureModeKey"), (CFPropertyListRef)@YES, appID);
        CFPreferencesSetAppValue(CFSTR("CAMUserPreferencesCameraDeviceKey"), (CFPropertyListRef)@(device), appID);
        CFPreferencesSetAppValue(CFSTR("UserPreferencesCameraDeviceKey"), (CFPropertyListRef)@(device), appID);
        CFPreferencesSetAppValue(CFSTR("UserPreferencesZoomFactor"), (CFPropertyListRef)@(zoomFactor), appID);
        CFPreferencesSetAppValue(CFSTR("CAMUserPreferencesZoomFactor"), (CFPropertyListRef)@(zoomFactor), appID);
        if (mode == 1) {
            CFPreferencesSetAppValue(CFSTR("UserPreferencesVideoZoomFactor"), (CFPropertyListRef)@(zoomFactor), appID);
            CFPreferencesSetAppValue(CFSTR("CAMUserPreferencesBackCameraVideoZoomFactor"), (CFPropertyListRef)@(zoomFactor), appID);
        }
        if (flashMode == 1) {
            CFPreferencesSetAppValue(CFSTR("UserPreferencesTorchMode"), (CFPropertyListRef)@(1), appID);
            CFPreferencesSetAppValue(CFSTR("CAMUserPreferencesTorchModeKey"), (CFPropertyListRef)@(1), appID);
            CFPreferencesSetAppValue(CFSTR("UserPreferencesFlashMode"), (CFPropertyListRef)@(1), appID);
            CFPreferencesSetAppValue(CFSTR("CAMUserPreferencesFlashModeKey"), (CFPropertyListRef)@(1), appID);
        }
        CFPreferencesAppSynchronize(appID);
    } @catch (NSException *e) {
        SRLog(@"[Camera] Error writing camera preferences: %@", e);
    }
    
    // 3. Launch com.apple.camera via FBSOpenApplicationService on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        Class fbsOptionsClass = objc_getClass("FBSOpenApplicationOptions");
        Class fbsServiceClass = objc_getClass("FBSOpenApplicationService");
        
        NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:@{
            @"CAMUserPreferencesCaptureModeKey": @(mode),
            @"CAMCaptureMode": @(mode),
            @"CAMUserPreferencesCameraDeviceKey": @(device),
            @"UserPreferencesZoomFactor": @(zoomFactor),
            @"CAMUserPreferencesZoomFactor": @(zoomFactor)
        }];
        if (flashMode == 1) {
            payload[@"CAMUserPreferencesTorchModeKey"] = @(1);
            payload[@"CAMUserPreferencesFlashModeKey"] = @(1);
        }
        
        NSDictionary *optionsDict = @{
            @"__PayloadOptions": payload,
            @"__UnlockDevice": @YES,
            @"__PromptUnlockDevice": @YES
        };
        
        id options = nil;
        if (fbsOptionsClass && [fbsOptionsClass respondsToSelector:@selector(optionsWithDictionary:)]) {
            options = [fbsOptionsClass optionsWithDictionary:optionsDict];
        }
        
        if (fbsServiceClass) {
            FBSOpenApplicationService *service = [fbsServiceClass serviceWithDefaultShellEndpoint];
            [service openApplication:@"com.apple.camera" withOptions:options completion:^(id response, NSError *error) {
                if (error) {
                    SRLog(@"[Camera] FBS openApplication error: %@", error);
                } else {
                    SRLog(@"[Camera] Opened com.apple.camera with mode:%ld device:%ld zoom:%.1f", (long)mode, (long)device, zoomFactor);
                }
            }];
        } else {
            NSURL *url = [NSURL URLWithString:@"camera://"];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
        
        notify_post("com.saihgupr.remotecompanion.camera_intent");
    });
    
    // 4. Automated Touch Assistance Fallback for Zoom
    if (device == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            rc_load_touch_symbols();
            __block CGSize s = CGSizeZero;
            rc_dispatch_sync_main_safe(^{
                s = [UIScreen mainScreen].bounds.size;
            });
            double sw = MIN(s.width, s.height);
            double sh = MAX(s.width, s.height);
            if (sw <= 0) sw = 375.0;
            if (sh <= 0) sh = 667.0;
            
            if (zoomFactor >= 1.9 && zoomFactor <= 2.5) {
                rc_simulate_tap(sw * 0.61, sh * 0.71);
            } else if (zoomFactor >= 2.9) {
                rc_simulate_tap(sw * 0.72, sh * 0.71);
            } else if (zoomFactor >= 0.9 && zoomFactor <= 1.1) {
                rc_simulate_tap(sw * 0.50, sh * 0.71);
            } else if (zoomFactor < 0.9) {
                rc_simulate_tap(sw * 0.38, sh * 0.71);
            }
        });
    }
    
    NSString *zoomLabel = (zoomFactor == (int)zoomFactor)
        ? [NSString stringWithFormat:@"%dx", (int)zoomFactor]
        : [NSString stringWithFormat:@"%.1fx", zoomFactor];
    
    NSMutableArray *details = [NSMutableArray array];
    if (device == 1) [details addObject:@"Front"];
    if (zoomFactor != 1.0 || (mode == 1 && device == 0)) [details addObject:zoomLabel];
    if (flashMode == 1) [details addObject:@"Flash ON"];
    if (autoShutter) [details addObject:(mode == 1 || mode == 2) ? @"Recording" : @"Snapped"];
    
    NSString *detailStr = (details.count > 0) ? [NSString stringWithFormat:@" (%@)", [details componentsJoinedByString:@", "]] : @"";
    NSString *modeDesc = [NSString stringWithFormat:@"%@ Mode%@", modeName, detailStr];
    
    rc_show_hud_toast(@"Camera", modeDesc, icon);
    return [NSString stringWithFormat:@"Opened Camera in %@\n", modeDesc];
}

static NSString *rc_open_camera_video(double zoomFactor, NSInteger flashMode) {
    return rc_open_camera_unified(1, 0, zoomFactor, flashMode, NO);
}

static NSString *rc_handle_screenrecord(NSString *subcmd) {
    dlopen("/System/Library/Frameworks/ReplayKit.framework/ReplayKit", RTLD_NOW);
    Class RPC = objc_getClass("RPScreenRecorder");
    if (!RPC) {
        return @"Error: RPScreenRecorder class not found\n";
    }

    id recorder = nil;
    if ([RPC respondsToSelector:@selector(sharedRecorder)]) {
        recorder = [RPC performSelector:@selector(sharedRecorder)];
    }
    if (!recorder) {
        return @"Error: Could not obtain RPScreenRecorder shared instance\n";
    }

    BOOL isRecording = NO;
    if ([recorder respondsToSelector:@selector(isRecording)]) {
        isRecording = [recorder isRecording];
    } else if ([recorder respondsToSelector:@selector(systemRecording)]) {
        isRecording = ((BOOL (*)(id, SEL))objc_msgSend)(recorder, @selector(systemRecording));
    }

    NSString *action = [subcmd lowercaseString];
    if (action.length == 0 || [action isEqualToString:@"toggle"]) {
        action = isRecording ? @"stop" : @"start";
    }

    if ([action isEqualToString:@"status"]) {
        return isRecording ? @"Screen recording: active\n" : @"Screen recording: inactive\n";
    }

    if ([action isEqualToString:@"start"] || [action isEqualToString:@"on"]) {
        if (isRecording) {
            return @"Screen recording already active\n";
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                SEL s1 = NSSelectorFromString(@"startRecordingWithMicrophoneEnabled:windowToRecord:systemRecording:handler:");
                SEL s2 = NSSelectorFromString(@"startSystemRecordingWithMicrophoneEnabled:handler:");
                SEL s3 = NSSelectorFromString(@"startRecordingWithHandler:");

                if ([recorder respondsToSelector:s1]) {
                    void (*msg)(id, SEL, BOOL, id, BOOL, id) = (void (*)(id, SEL, BOOL, id, BOOL, id))objc_msgSend;
                    msg(recorder, s1, NO, nil, YES, nil);
                    SRLog(@"Screen recording started via startRecordingWithMicrophoneEnabled:windowToRecord:systemRecording:handler:");
                } else if ([recorder respondsToSelector:s2]) {
                    void (*msg)(id, SEL, BOOL, id) = (void (*)(id, SEL, BOOL, id))objc_msgSend;
                    msg(recorder, s2, NO, nil);
                    SRLog(@"Screen recording started via startSystemRecordingWithMicrophoneEnabled:handler:");
                } else if ([recorder respondsToSelector:s3]) {
                    void (*msg)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
                    msg(recorder, s3, nil);
                    SRLog(@"Screen recording started via startRecordingWithHandler:");
                } else {
                    SRLog(@"RPScreenRecorder: No matching start recording selector found");
                }
            } @catch (NSException *e) {
                SRLog(@"Exception starting screen recording: %@", e);
            }
        });
        return @"Screen recording started\n";
    } else if ([action isEqualToString:@"stop"] || [action isEqualToString:@"off"]) {
        if (!isRecording) {
            return @"Screen recording is not active\n";
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                SEL stop1 = NSSelectorFromString(@"stopSystemRecording:");
                SEL stop2 = NSSelectorFromString(@"stopRecordingWithHandler:");

                if ([recorder respondsToSelector:stop1]) {
                    void (*msg)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
                    msg(recorder, stop1, nil);
                    SRLog(@"Screen recording stopped via stopSystemRecording:");
                } else if ([recorder respondsToSelector:stop2]) {
                    void (*msg)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
                    msg(recorder, stop2, nil);
                    SRLog(@"Screen recording stopped via stopRecordingWithHandler:");
                } else {
                    SRLog(@"RPScreenRecorder: No matching stop recording selector found");
                }
            } @catch (NSException *e) {
                SRLog(@"Exception stopping screen recording: %@", e);
            }
        });
        return @"Screen recording stopped\n";
    }

    return @"Usage: rc screenrecord [toggle|start|stop|status]\n";
}

static NSString *rc_handle_snapper(NSString *arg) {
    NSString *sub = [[arg lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([sub isEqualToString:@"freeze"]) {
        SRLog(@"[Snapper] Posting freeze notifications...");
        notify_post("com.jontelang.snapper3.freeze");
        notify_post("com.jontelang.snapper2.freeze");
        return @"Snapper: Freeze triggered\n";
    } else if ([sub isEqualToString:@"instant"]) {
        SRLog(@"[Snapper] Posting instant notifications...");
        notify_post("com.jontelang.snapper3.instant");
        notify_post("com.jontelang.snapper2.instant");
        return @"Snapper: Instant triggered\n";
    } else if ([sub isEqualToString:@"close"] || [sub isEqualToString:@"closeall"] || [sub isEqualToString:@"close_all"] || [sub isEqualToString:@"close-all"]) {
        SRLog(@"[Snapper] Posting close notifications...");
        notify_post("com.jontelang.snapper3.close.all");
        notify_post("com.jontelang.snapper3.closecrop");
        notify_post("com.jontelang.snapper2.close");
        return @"Snapper: Closed\n";
    } else {
        // default or "open"
        SRLog(@"[Snapper] Posting open notifications...");
        notify_post("com.jontelang.snapper3.open");
        notify_post("com.jontelang.snapper2.open");
        return @"Snapper: Open triggered\n";
    }
}

static NSString *handle_command(NSString *cmd) {
    if (!cmd || ![cmd isKindOfClass:[NSString class]]) {
        SRLog(@"ERROR: handle_command received nil or invalid command string");
        return @"Error: Invalid command\n";
    }
    NSString *cleanCmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleanCmd.length == 0) return @"Error: Empty command\n";
    SRLog(@"Received command: %@", cleanCmd);
    
    if ([cleanCmd isEqualToString:@"ha"] || [cleanCmd hasPrefix:@"ha "]) {
        NSString *subArgs = [cleanCmd isEqualToString:@"ha"] ? @"" : [cleanCmd substringFromIndex:3];
        return rc_execute_ha_command(subArgs);
    }
    
    if ([cleanCmd isEqualToString:@"km"] || [cleanCmd hasPrefix:@"km "]) {
        NSString *subArgs = [cleanCmd isEqualToString:@"km"] ? @"" : [cleanCmd substringFromIndex:3];
        return rc_execute_km_command(subArgs);
    }
    
    if ([cleanCmd isEqualToString:@"mqtt"] || [cleanCmd hasPrefix:@"mqtt "]) {
        NSString *subArgs = [cleanCmd isEqualToString:@"mqtt"] ? @"" : [cleanCmd substringFromIndex:5];
        return rc_execute_mqtt_command(subArgs);
    }
    
    // Debug hex dump of command
    NSMutableString *hex = [NSMutableString string];
    const char *utf = [cleanCmd UTF8String];
    for (size_t i = 0; i < strlen(utf); i++) {
        [hex appendFormat:@"%02X ", (unsigned char)utf[i]];
    }
    SRLog(@"Command HEX: %@", hex);
    
    // Log file retrieval command
    if ([cleanCmd isEqualToString:@"log"]) {
        SRLog(@"Log request");
        return nil;
    } else if ([cleanCmd isEqualToString:@"proximity"] || [cleanCmd hasPrefix:@"proximity "]) {
        NSString *sub = nil;
        if ([cleanCmd hasPrefix:@"proximity "]) {
            sub = [[cleanCmd substringFromIndex:10] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        id manager = g_proximitySensorManager;
        if (!manager) {
            Class cls = objc_getClass("SBProximitySensorManager");
            if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
                manager = [cls performSelector:@selector(sharedInstance)];
            }
        }
        
        __block NSString *response = nil;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([sub isEqualToString:@"on"] || [sub isEqualToString:@"enable"]) {
                g_forceProximityDetection = YES;
                if (manager) {
                    if ([manager respondsToSelector:@selector(_enableProx)]) {
                        [manager _enableProx];
                    } else if ([manager respondsToSelector:@selector(_setProximityDetectionEnabled:)]) {
                        [manager _setProximityDetectionEnabled:YES];
                    }
                }
                [UIDevice currentDevice].proximityMonitoringEnabled = YES;
                response = @"Proximity sensor enabled permanently (for testing)\n";
                dispatch_semaphore_signal(sema);
            } else if ([sub isEqualToString:@"off"] || [sub isEqualToString:@"disable"]) {
                g_forceProximityDetection = NO;
                if (manager) {
                    if ([manager respondsToSelector:@selector(_disableProx)]) {
                        [manager _disableProx];
                    } else if ([manager respondsToSelector:@selector(_setProximityDetectionEnabled:)]) {
                        [manager _setProximityDetectionEnabled:NO];
                    }
                }
                [UIDevice currentDevice].proximityMonitoringEnabled = NO;
                response = @"Proximity sensor disabled\n";
                dispatch_semaphore_signal(sema);
            } else if ([sub isEqualToString:@"debug"] || [sub isEqualToString:@"inspect"]) {
                NSMutableString *debugInfo = [NSMutableString string];
                [debugInfo appendFormat:@"--- Proximity Debug Info ---\n"];
                [debugInfo appendFormat:@"g_proximitySensorManager: %@\n", g_proximitySensorManager];
                
                // 1. Find all classes with "Proximity" in their name
                [debugInfo appendString:@"\nRelated Classes:\n"];
                int numClasses = objc_getClassList(NULL, 0);
                if (numClasses > 0) {
                    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
                    numClasses = objc_getClassList(classes, numClasses);
                    for (int i = 0; i < numClasses; i++) {
                        NSString *className = NSStringFromClass(classes[i]);
                        if ([className rangeOfString:@"Proximity" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                            [debugInfo appendFormat:@"  %@\n", className];
                        }
                    }
                    free(classes);
                }
                
                id targetObj = manager;
                if (targetObj) {
                    Class cls = [targetObj class];
                    [debugInfo appendFormat:@"\nClass: %@\n", NSStringFromClass(cls)];
                    
                    // 2. Instance Variables
                    [debugInfo appendString:@"\nIvars:\n"];
                    unsigned int ivarCount = 0;
                    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
                    for (unsigned int i = 0; i < ivarCount; i++) {
                        [debugInfo appendFormat:@"  %s (%s) = %@\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]), formatIvarValue(targetObj, ivars[i])];
                    }
                    if (ivars) free(ivars);
                    
                    // 3. Properties
                    [debugInfo appendString:@"\nProperties:\n"];
                    unsigned int propCount = 0;
                    objc_property_t *properties = class_copyPropertyList(cls, &propCount);
                    for (unsigned int i = 0; i < propCount; i++) {
                        const char *name = property_getName(properties[i]);
                        NSString *nameStr = [NSString stringWithUTF8String:name];
                        id val = nil;
                        @try {
                            val = [targetObj valueForKey:nameStr];
                        } @catch (NSException *e) {
                            val = [NSString stringWithFormat:@"<KVC Error: %@>", e.reason];
                        }
                        [debugInfo appendFormat:@"  %s = %@\n", name, val];
                    }
                    if (properties) free(properties);
                    
                    // 4. Methods
                    [debugInfo appendString:@"\nMethods:\n"];
                    unsigned int methodCount = 0;
                    Method *methods = class_copyMethodList(cls, &methodCount);
                    for (unsigned int i = 0; i < methodCount; i++) {
                        SEL selector = method_getName(methods[i]);
                        NSString *methodName = NSStringFromSelector(selector);
                        [debugInfo appendFormat:@"  %@\n", methodName];
                    }
                    if (methods) free(methods);
                } else {
                    [debugInfo appendString:@"\nNo manager found to inspect.\n"];
                }
                response = debugInfo;
                dispatch_semaphore_signal(sema);
            } else {
                // Just query status
                BOOL isNearPrivate = NO;
                if (manager) {
                    if ([manager respondsToSelector:@selector(isObjectInProximity)]) {
                        isNearPrivate = [manager isObjectInProximity];
                    }
                }
                
                BOOL isNearPublic = [UIDevice currentDevice].proximityState;
                BOOL isNear = isNearPrivate || isNearPublic;
                
                if (g_latestHIDProximityState != -1) {
                    isNear = (g_latestHIDProximityState == 1);
                }
                
                // Both `rc proximity` (sub == nil/empty) and `rc proximity status` run the exact same logic.
                // We keep 'status' support purely as an undocumented legacy/fallback alias to avoid breaking scripts.
                if ([sub isEqualToString:@"status"] || sub == nil || sub.length == 0) {
                    response = isNear ? @"near\n" : @"far\n";
                } else {
                    BOOL isDetectionEnabled = NO;
                    if (manager && [manager respondsToSelector:@selector(isProximityDetectionEnabled)]) {
                        isDetectionEnabled = [manager isProximityDetectionEnabled];
                    }
                    BOOL isPublicEnabled = [UIDevice currentDevice].proximityMonitoringEnabled;
                    response = [NSString stringWithFormat:@"SBProximitySensorManager: objectInProximity=%d, detectionEnabled=%d\nUIDevice: proximityState=%d, monitoringEnabled=%d\n",
                                isNearPrivate, isDetectionEnabled, isNearPublic, isPublicEnabled];
                }
                dispatch_semaphore_signal(sema);
            }
        });
        
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        return response ?: @"Error: Timeout querying proximity sensor\n";
    }

    // Media commands - these work reliably via MediaRemote
    if ([cleanCmd isEqualToString:@"pause"]) {
        // Only pause if currently playing (prevents toggle behavior)
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            if (isPlaying) {
                MRMediaRemoteSendCommand(kMRPause, nil);
            }
        });
        return @"Pause sent\n";
    } else if ([cleanCmd isEqualToString:@"play"]) {
        // Only play if currently paused (prevents toggle behavior)
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            if (!isPlaying) {
                MRMediaRemoteSendCommand(kMRPlay, nil);
            }
        });
        return @"Play sent\n";
    } else if ([cleanCmd isEqualToString:@"playpause"] || [cleanCmd isEqualToString:@"toggle"]) {
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            if (isPlaying) {
                MRMediaRemoteSendCommand(kMRPause, nil);
            } else {
                MRMediaRemoteSendCommand(kMRPlay, nil);
            }
        });
        return @"Play/Pause toggled\n";
    } else if ([cleanCmd isEqualToString:@"debug-media"]) {
        // Introspect Media State
        MRMediaRemoteGetNowPlayingApplicationPID(dispatch_get_main_queue(), ^(int pid) {
            SRLog(@"DEBUG: Now Playing PID: %d", pid);
            if (pid > 0) {
                 // Try to get process name?
                 // Simple check if it's Spotify (we don't have proc_name here easily without more headers)
                 SRLog(@"DEBUG: System thinks an app is Now Playing (PID %d)", pid);
            } else {
                 SRLog(@"DEBUG: No Now Playing Application detected (PID 0)");
            }
        });
        
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
             SRLog(@"DEBUG: Is Playing Status: %@", isPlaying ? @"YES" : @"NO");
        });
        
        return @"Dumping generic media state to logs...\n";
    } else if ([cleanCmd hasPrefix:@"blacklist"]) {
        NSArray *parts = [cleanCmd componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (parts.count >= 2) {
            NSString *sub = parts[1];
            if (!g_blacklist) load_blacklist();
            
            if ([sub isEqualToString:@"list"]) {
                return [NSString stringWithFormat:@"Blacklisted Apps:\n%@\n", [g_blacklist componentsJoinedByString:@"\n"]];
            } else if ([sub isEqualToString:@"add"] && parts.count >= 3) {
                NSString *newID = parts[2];
                NSMutableArray *mList = [g_blacklist mutableCopy];
                if (![mList containsObject:newID]) {
                    [mList addObject:newID];
                    if (save_blacklist(mList)) return [NSString stringWithFormat:@"Added %@ to blacklist\n", newID];
                    return @"Error: Failed to save blacklist\n";
                }
                return [NSString stringWithFormat:@"%@ is already blacklisted\n", newID];
            } else if ([sub isEqualToString:@"remove"] && parts.count >= 3) {
                NSString *remID = parts[2];
                NSMutableArray *mList = [g_blacklist mutableCopy];
                if ([mList containsObject:remID]) {
                    [mList removeObject:remID];
                    if (save_blacklist(mList)) return [NSString stringWithFormat:@"Removed %@ from blacklist\n", remID];
                    return @"Error: Failed to save blacklist\n";
                }
                return [NSString stringWithFormat:@"%@ was not in blacklist\n", remID];
            } else if ([sub isEqualToString:@"reset"]) {
                [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Library/Preferences/com.saihgupr.remotecompanion.blacklist.plist" error:nil];
                load_blacklist();
                return @"Blacklist reset to factory defaults\n";
            }
        }
        return @"Usage: rc blacklist <list|add|remove|reset> [bundleID]\n";
    } else if ([cleanCmd isEqualToString:@"is-playing"] || [cleanCmd isEqualToString:@"player status"]) {
        __block NSString *status = @"Unknown";
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        
        MRMediaRemoteGetNowPlayingApplicationPlaybackState(dispatch_get_main_queue(), ^(unsigned int state) {
            switch (state) {
                case 0: status = @"Unknown"; break;
                case 1: status = @"Playing"; break;
                case 2: status = @"Paused"; break;
                case 3: status = @"Stopped"; break;
                case 4: status = @"Interrupted"; break;
                case 5: status = @"Seeking Forward"; break;
                case 6: status = @"Seeking Backward"; break;
                default: status = [NSString stringWithFormat:@"Other (%u)", state]; break;
            }
            dispatch_semaphore_signal(sema);
        });
        
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)));
        
        if ([cleanCmd isEqualToString:@"is-playing"]) {
            return [status isEqualToString:@"Playing"] ? @"YES\n" : @"NO\n";
        }
        return [NSString stringWithFormat:@"%@\n", status];
    } else if ([cleanCmd isEqualToString:@"next"]) {
        MRMediaRemoteSendCommand(kMRNextTrack, nil);
        return @"Next track\n";
    } else if ([cleanCmd isEqualToString:@"prev"]) {
        MRMediaRemoteSendCommand(kMRPreviousTrack, nil);
        return @"Previous track\n";
    } else if ([cleanCmd isEqualToString:@"flashlight"] || [cleanCmd isEqualToString:@"torch"] || [cleanCmd isEqualToString:@"flashlight toggle"]) {
        SRLog(@"Toggling flashlight");
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            if (device.torchMode == AVCaptureTorchModeOn) {
                [device setTorchMode:AVCaptureTorchModeOff];
            } else {
                float level = get_flash_brightness();
                [device setTorchModeOnWithLevel:level error:nil];
            }
            [device unlockForConfiguration];
        }
        return @"Flashlight toggled\n";
    } else if ([cleanCmd hasPrefix:@"flashlight on"] || [cleanCmd hasPrefix:@"flash on"]) {
        float level = get_flash_brightness();
        NSArray *parts = [cleanCmd componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (parts.count >= 3) {
            float customLevel = [parts[2] floatValue];
            if (customLevel > 0) level = customLevel;
            if (level > 1.0f) level /= 100.0f; // Handle percentage
        }
        
        SRLog(@"Flashlight ON at level: %f", level);
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            if (level < 0.01f) level = 0.01f;
            if (level > 1.0f) level = 1.0f;
            [device setTorchModeOnWithLevel:level error:nil];
            [device unlockForConfiguration];
        }
        return [NSString stringWithFormat:@"Flashlight ON (%.0f%%)\n", level * 100];
    } else if ([cleanCmd hasPrefix:@"flashlight "] || [cleanCmd hasPrefix:@"flash "]) {
        // Handle "flashlight 0.5" or "flashlight 50"
        NSString *valStr = [cleanCmd substringFromIndex:([cleanCmd hasPrefix:@"flashlight "] ? 11 : 6)];
        float level = [valStr floatValue];
        if (level > 1.0f) level /= 100.0f;
        
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            if (level <= 0) {
                [device setTorchMode:AVCaptureTorchModeOff];
                [device unlockForConfiguration];
                return @"Flashlight OFF\n";
            }
            if (level < 0.01f) level = 0.01f;
            if (level > 1.0f) level = 1.0f;
            [device setTorchModeOnWithLevel:level error:nil];
            [device unlockForConfiguration];
            return [NSString stringWithFormat:@"Flashlight set to %.0f%%\n", level * 100];
        }
        return @"Error: Flashlight not available\n";
    } else if ([cleanCmd isEqualToString:@"flashlight off"] || [cleanCmd isEqualToString:@"torch off"]) {
    } else if ([cleanCmd hasPrefix:@"notify "]) {
        // notify "Title" "Body" [--urgent]
        // Parse: notify "Title" "Message" OR notify Title Message
        NSString *args = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *title = @"RemoteCommand";
        NSString *body = @"";
        BOOL urgent = NO;
        
        // Check for --urgent flag
        if ([args hasSuffix:@" --urgent"]) {
            urgent = YES;
            args = [[args substringToIndex:args.length - 9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        
        // Parse quoted strings: "Title" "Body"
        if ([args hasPrefix:@"\""]) {
            NSRange endTitle = [args rangeOfString:@"\"" options:0 range:NSMakeRange(1, args.length - 1)];
            if (endTitle.location != NSNotFound) {
                title = [args substringWithRange:NSMakeRange(1, endTitle.location - 1)];
                NSString *rest = [[args substringFromIndex:endTitle.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([rest hasPrefix:@"\""]) {
                    NSRange endBody = [rest rangeOfString:@"\"" options:0 range:NSMakeRange(1, rest.length - 1)];
                    if (endBody.location != NSNotFound) {
                        body = [rest substringWithRange:NSMakeRange(1, endBody.location - 1)];
                    } else {
                        body = [rest substringFromIndex:1];
                    }
                } else {
                    body = rest;
                }
            }
        } else {
            // Simple split: notify Title Body
            NSArray *parts = [args componentsSeparatedByString:@" "];
            if (parts.count >= 1) title = parts[0];
            if (parts.count >= 2) body = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@" "];
        }
        
        send_notification(title, body, urgent);
        return @"OK\n";
    } else if ([cleanCmd hasPrefix:@"shortcut:"] || [cleanCmd hasPrefix:@"shortcut "] || [cleanCmd hasPrefix:@"springcut "] || [cleanCmd hasPrefix:@"shortcut-direct "] || [cleanCmd hasPrefix:@"sd "]) {
        NSString *argsString = nil;
        if ([cleanCmd hasPrefix:@"shortcut:"]) {
            argsString = [[cleanCmd substringFromIndex:9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if ([cleanCmd hasPrefix:@"shortcut "]) {
            argsString = [[cleanCmd substringFromIndex:9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if ([cleanCmd hasPrefix:@"springcut "]) {
            argsString = [[cleanCmd substringFromIndex:10] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if ([cleanCmd hasPrefix:@"shortcut-direct "]) {
            argsString = [[cleanCmd substringFromIndex:16] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if ([cleanCmd hasPrefix:@"sd "]) {
            argsString = [[cleanCmd substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        NSString *shortcutName = argsString;
        NSString *inputParam = nil;
        
        // Parse name and optional -p parameter
        if ([argsString hasPrefix:@"\""]) {
            NSRange endQuote = [argsString rangeOfString:@"\"" options:0 range:NSMakeRange(1, argsString.length - 1)];
            if (endQuote.location != NSNotFound) {
                shortcutName = [argsString substringWithRange:NSMakeRange(1, endQuote.location - 1)];
                NSString *remaining = [[argsString substringFromIndex:endQuote.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([remaining hasPrefix:@"-p "]) {
                    inputParam = [[remaining substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if ([inputParam hasPrefix:@"\""] && [inputParam hasSuffix:@"\""] && inputParam.length >= 2) {
                        inputParam = [inputParam substringWithRange:NSMakeRange(1, inputParam.length - 2)];
                    }
                }
            }
        } else {
            NSRange pRange = [argsString rangeOfString:@" -p "];
            if (pRange.location != NSNotFound) {
                shortcutName = [[argsString substringToIndex:pRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                inputParam = [[argsString substringFromIndex:pRange.location + 4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([inputParam hasPrefix:@"\""] && [inputParam hasSuffix:@"\""] && inputParam.length >= 2) {
                    inputParam = [inputParam substringWithRange:NSMakeRange(1, inputParam.length - 2)];
                }
            }
        }
        
        rc_execute_shortcut(shortcutName, inputParam);
        return [NSString stringWithFormat:@"Triggered shortcut: %@\n", shortcutName];
    } else if ([cleanCmd hasPrefix:@"anc "] || [cleanCmd isEqualToString:@"anc"]) {
        // ANC control - triggers Sonitus hooks
        NSString *mode = [cleanCmd length] > 4 ? [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
        NSString *listeningMode = nil;
        
        if ([mode isEqualToString:@"on"] || [mode isEqualToString:@"nc"]) {
            listeningMode = @"AVOutputDeviceBluetoothListeningModeActiveNoiseCancellation";
        } else if ([mode isEqualToString:@"off"]) {
            listeningMode = @"AVOutputDeviceBluetoothListeningModeNormal";
        } else if ([mode isEqualToString:@"transparency"] || [mode isEqualToString:@"ambient"]) {
            listeningMode = @"AVOutputDeviceBluetoothListeningModeAudioTransparency";
        } else {
            SRLog(@"Unknown ANC mode: %@. Use: on, off, transparency", mode);
            return nil;
        }
        
        SRLog(@"Setting ANC mode: %@ -> %@", mode, listeningMode);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            Class AVOutputContextClass = objc_getClass("AVOutputContext");
            if (!AVOutputContextClass) {
                SRLog(@"ERROR: AVOutputContext class not found");
                return;
            }
            
            AVOutputContext *context = [AVOutputContextClass sharedSystemAudioContext];
            NSArray *devices = [context outputDevices];
            SRLog(@"Found %lu output devices", (unsigned long)devices.count);
            
            for (AVOutputDevice *device in devices) {
                NSArray *modes = [device availableBluetoothListeningModes];
                if (modes.count > 0) {
                    SRLog(@"Device '%@' supports listening modes: %@", device.name, modes);
                    NSError *error = nil;
                    BOOL success = [device setCurrentBluetoothListeningMode:listeningMode error:&error];
                    if (success) {
                        SRLog(@"ANC mode set successfully on %@", device.name);
                    } else {
                        SRLog(@"Failed to set ANC mode: %@", error);
                    }
                    return;
                }
            }
            SRLog(@"No device with ANC support found");
        });
    } else if ([cleanCmd hasPrefix:@"button "]) {
        // Hardware button simulation
        NSString *btn = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([btn isEqualToString:@"power"] || [btn isEqualToString:@"lock"]) {
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
        } else if ([btn isEqualToString:@"home"]) {
            simulate_home_press();
        } else if ([btn isEqualToString:@"volup"]) {
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VolumeIncrement, 0, 0);
        } else if ([btn isEqualToString:@"voldown"]) {
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VolumeDecrement, 0, 0);
        } else if ([btn isEqualToString:@"mute"]) {
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Mute, 0, 0);
        } else if ([btn isEqualToString:@"siri"]) {

            
            // Use HID Voice Command (0xCF) - Acts like a headset button, typically no "Home" side-effects
            inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VoiceCommand, 600000000, 0); // 0.6s hold
            
            // Fallback: Bundle Launch (Reliable but loses context)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                Class SBAssistantControllerClass = objc_getClass("SBAssistantController");
                id assistant = [SBAssistantControllerClass sharedInstance];
                if ([assistant respondsToSelector:@selector(isVisible)] && ![assistant isVisible]) {

                    Class LSWorkspace = objc_getClass("LSApplicationWorkspace");
                    if (LSWorkspace) {
                        [[LSWorkspace defaultWorkspace] openApplicationWithBundleID:@"com.apple.SiriViewService"];
                    }
                }
            });
        } else {
            SRLog(@"Unknown button: %@. Supported: power, home, volup, voldown, mute, siri", btn);
        }
    } else if ([cleanCmd isEqualToString:@"siri"]) {
        return handle_command(@"button siri");
    } else if ([cleanCmd isEqualToString:@"open control center"] ||
               [cleanCmd isEqualToString:@"control center"] ||
               [cleanCmd isEqualToString:@"open-control-center"] ||
               [cleanCmd isEqualToString:@"control-center"]) {
        __block BOOL opened = NO;
        void (^ccBlock)(void) = ^{
            Class ccClass = objc_getClass("SBControlCenterController");
            if (!ccClass) {
                SRLog(@"Control Center class unavailable");
                return;
            }

            id controller = nil;
            if ([ccClass respondsToSelector:@selector(sharedInstanceIfExists)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                controller = [ccClass performSelector:@selector(sharedInstanceIfExists)];
#pragma clang diagnostic pop
            }

            if (controller && [controller respondsToSelector:@selector(isVisible)]) {
                if ([controller isVisible]) {
                    [controller dismissAnimated:YES];
                    opened = YES;
                } else {
                    [controller presentAnimated:YES];
                    opened = YES;
                }
            } else if (controller && [controller respondsToSelector:@selector(_presentControlCenterGestureBeganWithReason:)]) {
                 [controller performSelector:@selector(_presentControlCenterGestureBeganWithReason:) withObject:@"RemoteCompanion"];
                 opened = YES;
            }
        };

        if ([NSThread isMainThread]) {
            ccBlock();
        } else {
            dispatch_sync(dispatch_get_main_queue(), ccBlock);
        }
        return opened ? @"Control Center opened\n" : @"Failed to open Control Center\n";
    } else if ([cleanCmd isEqualToString:@"previous app"] || [cleanCmd isEqualToString:@"last app"]) {
        if (g_previousAppBundleId) {
            SRLog(@"[RemoteCommand] Returning to previous app: %@", g_previousAppBundleId);
            dispatch_async(dispatch_get_main_queue(), ^{
                Class fbsClass = objc_getClass("FBSOpenApplicationService");
                if (fbsClass) {
                    id service = [fbsClass serviceWithDefaultShellEndpoint];
                    [service openApplication:g_previousAppBundleId withOptions:nil completion:nil];
                }
            });
            return [NSString stringWithFormat:@"Switched to previous app: %@", g_previousAppBundleId];
        } else {
            return @"No previous app available.";
        }
    } else if ([cleanCmd isEqualToString:@"switcher"] || [cleanCmd isEqualToString:@"app switcher"]) {
        __block BOOL success = NO;
        SRLog(@"Attempting to toggle App Switcher...");
        void (^switcherBlock)(void) = ^{
            Class SBClass = objc_getClass("SpringBoard");
            id sb = [SBClass sharedApplication];
            
            // Method 1: SBMainSwitcherViewController (iOS 15/16 discovered methods)
            Class viewCtrlClass = objc_getClass("SBMainSwitcherViewController");
            if (viewCtrlClass) {
                id switcher = nil;
                if ([viewCtrlClass respondsToSelector:@selector(sharedInstance)]) {
                    switcher = [viewCtrlClass sharedInstance];
                }
                if (switcher && [switcher respondsToSelector:@selector(toggleSwitcher)]) {
                    [switcher performSelector:@selector(toggleSwitcher)];
                    success = YES;
                }
            }
            
            // Method 2: SBLockScreenManager (if on lockscreen)
            if (!success) {
                Class LSMClass = objc_getClass("SBLockScreenManager");
                if (LSMClass) {
                    id manager = [LSMClass sharedInstance];
                    if (manager && [manager respondsToSelector:@selector(isUILocked)] && [manager isUILocked]) {
                        SRLog(@"Device locked, cannot toggle switcher");
                    }
                }
            }

            // Method 3: Standard springboard toggle if available
            if (!success && [sb respondsToSelector:@selector(_toggleAppSwitcher)]) {
                [sb performSelector:@selector(_toggleAppSwitcher)];
                success = YES;
            }
            
            // Method 4: Accessibility
            if (!success && [sb respondsToSelector:@selector(_accessibilityHandleAppSwitcherEvent)]) {
                SRLog(@"Using Method 4: _accessibilityHandleAppSwitcherEvent");
                [sb _accessibilityHandleAppSwitcherEvent];
                success = YES;
            }
        };

        if ([NSThread isMainThread]) {
            switcherBlock();
        } else {
            dispatch_sync(dispatch_get_main_queue(), switcherBlock);
        }
        SRLog(@"App Switcher toggle final success: %d", success);
        return success ? @"Switcher toggled\n" : @"Failed to toggle switcher\n";
    } else if ([cleanCmd hasPrefix:@"unlock "]) {
        NSString *passcode = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        dispatch_async(dispatch_get_main_queue(), ^{
            SBLockScreenManager *manager = [objc_getClass("SBLockScreenManager") sharedInstance];
            if (manager && [manager isUILocked]) {
                simulate_home_press(); // Wake device
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [manager attemptUnlockWithPasscode:passcode];
                });
            }
        });
        return [NSString stringWithFormat:@"Attempting unlock with passcode: %@\n", passcode];
    } else if ([cleanCmd hasPrefix:@"debug-class "]) {
        NSString *className = [[cleanCmd substringFromIndex:12] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        SRLog(@"Debugging class: %@", className);
        Class cls = objc_getClass([className UTF8String]);
        if (!cls) {
            SRLog(@"Class not found: %@", className);
            return @"Class not found\n";
        }
        
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        SRLog(@"Class %@ has %u methods:", className, count);
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            SRLog(@"  - %@", NSStringFromSelector(sel));
        }
        free(methods);
        return [NSString stringWithFormat:@"Found %u methods for %@. Check logs.\n", count, className];
    } else if ([cleanCmd hasPrefix:@"debug-classes "]) {
        NSString *search = [[cleanCmd substringFromIndex:14] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        SRLog(@"Searching for classes containing: %@", search);
        
        int numClasses = objc_getClassList(NULL, 0);
        if (numClasses > 0) {
            Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
            numClasses = objc_getClassList(classes, numClasses);
            SRLog(@"Found %d total classes. Filtering...", numClasses);
            for (int i = 0; i < numClasses; i++) {
                NSString *className = NSStringFromClass(classes[i]);
                if ([className rangeOfString:search options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    SRLog(@"  * %@", className);
                }
            }
            free(classes);
        }
        return @"Search complete. Check logs.\n";
    } else if ([cleanCmd hasPrefix:@"debug-call "]) {
        // debug-call ClassName selectorName
        NSString *args = [cleanCmd substringFromIndex:11];
        NSArray *parts = [args componentsSeparatedByString:@" "];
        if (parts.count >= 2) {
            NSString *className = parts[0];
            NSString *selName = parts[1];
            Class cls = objc_getClass([className UTF8String]);
            if (cls) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    id target = nil;
                    if ([cls respondsToSelector:@selector(sharedInstance)]) {
                        target = [cls performSelector:@selector(sharedInstance)];
                    } else if ([cls respondsToSelector:@selector(sharedController)]) {
                        target = [cls performSelector:@selector(sharedController)];
                    }
                    
                    if (target) {
                        SEL sel = NSSelectorFromString(selName);
                        if ([target respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                            id result = [target performSelector:sel];
#pragma clang diagnostic pop
                            SRLog(@"debug-call [%@ %@] returned: %@", className, selName, result);
                        } else {
                            SRLog(@"debug-call: Target does not respond to %@", selName);
                        }
                    } else {
                        SRLog(@"debug-call: Could not get instance for %@", className);
                    }
                });
            }
        }
        return @"Call initiated. Check logs.\n";
    } else if ([cleanCmd isEqualToString:@"lock"]) {
        // Smart lock: Only lock if currently unlocked
        // ensure we run on main thread for UI/SB checks
        dispatch_async(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = nil;
            if (SBLockScreenManagerClass) {
                manager = [SBLockScreenManagerClass sharedInstance];
            }
            
            SRLog(@"[SmartLock] Debug: Manager=%@, Checking isUILocked...", manager);

            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                 BOOL locked = [manager isUILocked];
                 SRLog(@"[SmartLock] isUILocked returned: %@", locked ? @"YES" : @"NO");
                 
                 if (locked) {
                     SRLog(@"[SmartLock] Device already locked. Skipping power button.");
                 } else {
                     SRLog(@"[SmartLock] Device unlocked. Sending power button event...");
                     inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
                 }
            } else {
                SRLog(@"[SmartLock] ERROR: manager is nil or does not respond to isUILocked. Forcing lock.");
                 inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
            }
        });
        return @"Lock command sent\n";
    } else if ([cleanCmd isEqualToString:@"lock status"] || [cleanCmd isEqualToString:@"is-locked"]) {
        __block NSString *status = nil;
        void (^lockStatusBlock)(void) = ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = SBLockScreenManagerClass ? [SBLockScreenManagerClass sharedInstance] : nil;
            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                status = [manager isUILocked] ? @"locked\n" : @"unlocked\n";
            } else {
                status = @"unlocked\n";
            }
        };
        if ([NSThread isMainThread]) lockStatusBlock();
        else dispatch_sync(dispatch_get_main_queue(), lockStatusBlock);
        return status;
    } else if ([cleanCmd isEqualToString:@"unlock"] || [cleanCmd hasPrefix:@"unlock "]) {
        // Unlock phone: Only if currently locked!
        
        NSString *pin = @"2569";
        if ([cleanCmd hasPrefix:@"unlock "]) {
            pin = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        SRLog(@"[SmartUnlock] Unlock command received for PIN: %@", pin);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = (SBLockScreenManagerClass) ? [SBLockScreenManagerClass sharedInstance] : nil;
            
            BOOL isLocked = NO;
            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                 isLocked = [manager isUILocked];
            }
            
            if (!isLocked) {
                 SRLog(@"[SmartUnlock] Device already unlocked. Doing nothing.");
                 return;
            }
            
            SRLog(@"[SmartUnlock] Device is locked. Checking screen state...");

            // Check if screen is on before waking
            BOOL needsWake = YES;
            Class SBBacklightControllerClass = objc_getClass("SBBacklightController");
            if (SBBacklightControllerClass) {
                SBBacklightController *blController = [SBBacklightControllerClass sharedInstance];
                if (blController) {
                    if ([blController respondsToSelector:@selector(screenIsOn)]) {
                        needsWake = ![blController screenIsOn];
                        SRLog(@"[SmartUnlock] screenIsOn: %d", !needsWake);
                    } else if ([blController respondsToSelector:@selector(backlightLevel)]) {
                        float level = [blController backlightLevel];
                        needsWake = (level == 0);
                        SRLog(@"[SmartUnlock] backlightLevel: %f", level);
                    }
                }
            }

            if (needsWake) {
                SRLog(@"[SmartUnlock] Screen is OFF. Sending wake (power button)...");
                inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
            } else {
                SRLog(@"[SmartUnlock] Screen is already ON. Skipping wake.");
            }
            
            // Wait for screen to wake/process (0.5s delay for more reliability)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!manager) {
                    SRLog(@"[SmartUnlock] ERROR: Manager became nil!");
                    return;
                }
                
                // Try the direct unlock method
                if ([manager respondsToSelector:@selector(attemptUnlockWithPasscode:)]) {
                    SRLog(@"[SmartUnlock] Calling attemptUnlockWithPasscode...");
                    BOOL success = [manager attemptUnlockWithPasscode:pin];
                    SRLog(@"[SmartUnlock] attemptUnlockWithPasscode returned: %d", success);
                } else if ([manager respondsToSelector:@selector(unlockUIFromSource:withOptions:)]) {
                    SRLog(@"[SmartUnlock] Falling back to unlockUIFromSource...");
                    [manager unlockUIFromSource:0 withOptions:nil];
                    SRLog(@"[SmartUnlock] unlockUIFromSource called");
                } else {
                    SRLog(@"[SmartUnlock] ERROR: No supported unlock method found on manager!");
                }
            });
        });
        return @"unlocking_started\n";
    }

    else if ([cleanCmd hasPrefix:@"key "]) {
        // Keyboard event simulation
        // Usage: key <usage_in_hex_or_dec>
        NSString *usageStr = [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        unsigned int usage = 0;
        NSScanner *scanner = [NSScanner scannerWithString:usageStr];
        if ([usageStr hasPrefix:@"0x"]) {
            [scanner scanHexInt:&usage];
        } else {
            int val = 0;
            if ([scanner scanInt:&val]) usage = (unsigned int)val;
        }
        
        if (usage > 0) {
            inject_hid_event(kHIDPage_KeyboardOrKeypad, usage, 0, 0);
        } else {
            SRLog(@"Invalid key usage: %@", usageStr);
        }

    } else if ([cleanCmd isEqualToString:@"lock-toggle"] || [cleanCmd isEqualToString:@"lock toggle"]) {
        // Toggle Lock State
        dispatch_async(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = nil;
            if (SBLockScreenManagerClass) {
                manager = [SBLockScreenManagerClass sharedInstance];
            }
            BOOL isLocked = NO;
            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                isLocked = [manager isUILocked];
            }
            
            SRLog(@"[LockToggle] Current State: %@", isLocked ? @"Locked" : @"Unlocked");
            
            if (isLocked) {
                 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                     handle_command(@"unlock");
                 });
            } else {
                 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                     handle_command(@"lock");
                 });
            }
        });
        
        return @"lock_toggle_initiated\n";

    } else if ([cleanCmd hasPrefix:@"url "]) {
        NSString *urlString = [cleanCmd substringFromIndex:4];
        urlString = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
            SBLockScreenManager *manager = (SBLockScreenManagerClass) ? [SBLockScreenManagerClass sharedInstance] : nil;
            
            BOOL isLocked = NO;
            if (manager && [manager respondsToSelector:@selector(isUILocked)]) {
                isLocked = [manager isUILocked];
            }
            
            if (isLocked) {
                 SRLog(@"[SmartURL] Device locked. Initiating stable unlock sequence before opening URL...");
                 
                 // 1. Check Screen State
                 BOOL needsWake = YES;
                 Class SBBacklightControllerClass = objc_getClass("SBBacklightController");
                 if (SBBacklightControllerClass) {
                     SBBacklightController *blController = [SBBacklightControllerClass sharedInstance];
                     if (blController) {
                         if ([blController respondsToSelector:@selector(screenIsOn)]) {
                             needsWake = ![blController screenIsOn];
                         } else if ([blController respondsToSelector:@selector(backlightLevel)]) {
                             needsWake = ([blController backlightLevel] == 0);
                         }
                     }
                 }

                 if (needsWake) {
                     SRLog(@"[SmartURL] Screen is OFF. Sending wake...");
                     inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
                 }
                 
                 // 2. Wait 0.5s then Unlock AND Open URL
                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                     if (manager && [manager respondsToSelector:@selector(attemptUnlockWithPasscode:)]) {
                          SRLog(@"[SmartURL] Attempting unlock with default PIN...");
                          [manager attemptUnlockWithPasscode:@"2569"];
                     }
                     
                     // 3. Wait another short moment for unlock animation/transition to finish
                     dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                         NSURL *url = [NSURL URLWithString:urlString];
                         if (url) {
                             SRLog(@"[SmartURL] Opening URL after unlock attempt: %@", urlString);
                             [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                         }
                     });
                 });
            } else {
                 // Device already unlocked, open immediately
                 NSURL *url = [NSURL URLWithString:urlString];
                 if (url) {
                     SRLog(@"[SmartURL] Device already unlocked. Opening URL: %@", urlString);
                     [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                 }
            }
        });
        return @"url_opening_initiated\n";
    } else if ([cleanCmd hasPrefix:@"spotify playlist "] || 
               [cleanCmd hasPrefix:@"spotify album "] || 
               [cleanCmd hasPrefix:@"spotify artist "] || 
               [cleanCmd hasPrefix:@"spotify play "] || 
               [cleanCmd hasPrefix:@"spotify "]) {
        NSString *arg = nil;
        if ([cleanCmd hasPrefix:@"spotify playlist "]) arg = [cleanCmd substringFromIndex:17];
        else if ([cleanCmd hasPrefix:@"spotify album "]) arg = [cleanCmd substringFromIndex:14];
        else if ([cleanCmd hasPrefix:@"spotify artist "]) arg = [cleanCmd substringFromIndex:15];
        else if ([cleanCmd hasPrefix:@"spotify play "]) arg = [cleanCmd substringFromIndex:13];
        else arg = [cleanCmd substringFromIndex:8];
        
        arg = [arg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Support full URIs or just IDs with intelligent defaulting
        NSString *spotifyURI = nil;
        
        // Check for specific command prefixes to determine URI type
        if ([cleanCmd hasPrefix:@"spotify album "]) {
             if ([arg hasPrefix:@"spotify:"]) spotifyURI = arg;
             else spotifyURI = [NSString stringWithFormat:@"spotify:album:%@", arg];
        } else if ([cleanCmd hasPrefix:@"spotify artist "]) {
             if ([arg hasPrefix:@"spotify:"]) spotifyURI = arg;
             else spotifyURI = [NSString stringWithFormat:@"spotify:artist:%@", arg];
        } else if ([arg hasPrefix:@"spotify:"]) {
            spotifyURI = arg;
        } else {
            // Default to playlist if it's just an ID and command was generic "spotify" or "spotify playlist"
            spotifyURI = [NSString stringWithFormat:@"spotify:playlist:%@", arg];
        }
        
        // Append :play suffix to trigger autoplay (Spotify-specific feature)
        NSString *playableURI = [spotifyURI stringByAppendingString:@":play"];
        SRLog(@"Spotify Request: %@ (playable: %@)", spotifyURI, playableURI);
        
        // Forwarding to main queue for UI/URL operations
        void (^launchSpotify)(void) = ^{
            NSURL *url = [NSURL URLWithString:playableURI];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                if (success) {
                    // Aggressive play trigger with multiple attempts
                    // Strategy: Use explicit Play command (not toggle) with multiple fallbacks
                    
                    NSArray *delays = @[@0.5, @1.0, @1.5, @2.5];
                    for (NSNumber *delayNum in delays) {
                        float delay = [delayNum floatValue];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            SRLog(@"Spotify play attempt at %.1fs", delay);
                            
                            // Get MediaRemote handle
                            void *mrHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
                            if (mrHandle) {
                                Boolean (*SendCommandToApp)(unsigned int, NSDictionary *, id, NSString *, unsigned int, dispatch_queue_t, void (^)(NSError *)) = dlsym(mrHandle, "MRMediaRemoteSendCommandToApp");
                                if (SendCommandToApp) {
                                    // Send explicit PLAY command (kMRPlay = 0) to Spotify
                                    SRLog(@"Sending kMRPlay to com.spotify.client");
                                    SendCommandToApp(kMRPlay, nil, nil, @"com.spotify.client", 0, dispatch_get_main_queue(), ^(NSError *err){
                                         if (err) SRLog(@"MR Play Error: %@", err);
                                         else SRLog(@"MR Play sent successfully");
                                    });
                                }
                            }
                            
                            // Also try global Play command as fallback
                            MRMediaRemoteSendCommand(kMRPlay, nil);
                            
                            // And HID Play key (not toggle - use dedicated Play usage if available)
                            inject_consumer_key(kHIDUsage_Csmr_PlayOrPause);
                        });
                    }
                }
            }];
        };

        // Use same logic as 'url' for smart unlock
        Class SBLockScreenManagerClass = objc_getClass("SBLockScreenManager");
        SBLockScreenManager *manager = SBLockScreenManagerClass ? [SBLockScreenManagerClass sharedInstance] : nil;
        
        if (manager && [manager isUILocked]) {
            SRLog(@"Device locked, attempting smart unlock for Spotify");
            dispatch_async(dispatch_get_main_queue(), ^{
                // Wake screen using HID Power button (simulated)
                inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0, 0);
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if ([manager respondsToSelector:@selector(attemptUnlockWithPasscode:)]) {
                        [manager attemptUnlockWithPasscode:@"2569"];
                    }
                    
                    launchSpotify();
                });
            });
            return @"unlocking_and_playing_spotify\n";
        } else {
            dispatch_async(dispatch_get_main_queue(), launchSpotify);
            return @"playing_spotify\n";
        }
    } else if ([cleanCmd isEqualToString:@"audiomix"]) {
        BOOL current = get_audiomix_state();
        toggle_audiomix(!current);
        return [NSString stringWithFormat:@"AudioMix %@\n", !current ? @"Enabled" : @"Disabled"];
    } else if ([cleanCmd hasPrefix:@"audiomix "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([subCmd isEqualToString:@"on"]) {
            toggle_audiomix(YES);
            return @"AudioMix Enabled\n";
        } else if ([subCmd isEqualToString:@"off"]) {
            toggle_audiomix(NO);
            return @"AudioMix Disabled\n";
        } else if ([subCmd isEqualToString:@"status"]) {
            BOOL current = get_audiomix_state();
            return current ? @"AudioMix ON\n" : @"AudioMix OFF\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_audiomix_state();
            toggle_audiomix(!current);
            return [NSString stringWithFormat:@"AudioMix %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd isEqualToString:@"toast"]) {
        rc_show_hud_toast(@"Test Toast", nil, nil);
        return @"Toast displayed\n";
    } else if ([cleanCmd hasPrefix:@"toast "]) {
        NSString *argsStr = [[cleanCmd substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray *arguments = rc_parse_quoted_arguments(argsStr);
        
        NSString *title = nil;
        NSString *subtitle = nil;
        NSString *icon = nil;
        
        if (arguments.count >= 3) {
            title = arguments[0];
            subtitle = arguments[1];
            icon = arguments[2];
        } else if (arguments.count == 2) {
            title = arguments[0];
            // Check if second argument is a valid symbol image
            if ([UIImage systemImageNamed:arguments[1]]) {
                icon = arguments[1];
            } else {
                subtitle = arguments[1];
            }
        } else if (arguments.count == 1) {
            title = arguments[0];
        }
        
        rc_show_hud_toast(title, subtitle, icon);
        return [NSString stringWithFormat:@"Toast displayed: '%@' - '%@' (%@)\n", title ?: @"", subtitle ?: @"", icon ?: @"none"];
    } else if ([cleanCmd isEqualToString:@"queuealbum"] || [cleanCmd isEqualToString:@"queue album"]) {
        // Signal AudioReceiver app to queue the album of the currently playing song
        [@"queuealbum" writeToFile:@"/tmp/audiostream_pending_cmd" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
             FBSOpenApplicationService *service = [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
             [service openApplication:@"com.saihgupr.audiostream" withOptions:nil completion:nil];
        });
        notify_post("com.saihgupr.audiostream.queuealbum");
        rc_show_hud_toast(@"Album Queued", @"Queuing album of current song", @"music.note.list");
        return @"Queue album command sent to AudioReceiver\n";
    } else if ([cleanCmd isEqualToString:@"queueartist"] || [cleanCmd isEqualToString:@"queue artist"]) {
        // Signal AudioReceiver app to queue the artist of the currently playing song
        [@"queueartist" writeToFile:@"/tmp/audiostream_pending_cmd" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
             FBSOpenApplicationService *service = [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
             [service openApplication:@"com.saihgupr.audiostream" withOptions:nil completion:nil];
        });
        notify_post("com.saihgupr.audiostream.queueartist");
        rc_show_hud_toast(@"Artist Queued", @"Queuing artist of current song", @"music.mic");
        return @"Queue artist command sent to AudioReceiver\n";
    } else if ([cleanCmd isEqualToString:@"shuffleall"] || [cleanCmd isEqualToString:@"shuffle all songs"] || [cleanCmd isEqualToString:@"suffle all songs"]) {
        // Signal AudioReceiver app to shuffle all songs and play
        [@"shuffleall" writeToFile:@"/tmp/audiostream_pending_cmd" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
             FBSOpenApplicationService *service = [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
             [service openApplication:@"com.saihgupr.audiostream" withOptions:nil completion:nil];
        });
        notify_post("com.saihgupr.audiostream.shuffleall");
        rc_show_hud_toast(@"Shuffle All Songs", @"Shuffling all songs and playing", @"shuffle");
        return @"Shuffle all command sent to AudioReceiver\n";
    } else if ([cleanCmd isEqualToString:@"deletesong"] || [cleanCmd isEqualToString:@"delete song"] || [cleanCmd isEqualToString:@"delete current song"]) {
        // Signal AudioReceiver app to delete currently playing song
        [@"deletesong" writeToFile:@"/tmp/audiostream_pending_cmd" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
             FBSOpenApplicationService *service = [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
             [service openApplication:@"com.saihgupr.audiostream" withOptions:nil completion:nil];
        });
        notify_post("com.saihgupr.audiostream.deletesong");
        rc_show_hud_toast(@"Song Deleted", @"Deleting currently playing song", @"trash");
        return @"Delete song command sent to AudioReceiver\n";
    } else if ([cleanCmd hasPrefix:@"playlist "] || [cleanCmd hasPrefix:@"play playlist "] || [cleanCmd hasPrefix:@"shuffle playlist "] || [cleanCmd hasPrefix:@"suffle playlist "]) {
        NSString *playlistName = @"";
        if ([cleanCmd hasPrefix:@"play playlist "]) {
            playlistName = [[cleanCmd substringFromIndex:14] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if ([cleanCmd hasPrefix:@"shuffle playlist "]) {
            playlistName = [[cleanCmd substringFromIndex:17] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if ([cleanCmd hasPrefix:@"suffle playlist "]) {
            playlistName = [[cleanCmd substringFromIndex:16] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if ([cleanCmd hasPrefix:@"playlist "]) {
            playlistName = [[cleanCmd substringFromIndex:9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        playlistName = [playlistName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        playlistName = [playlistName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
        
        if (playlistName.length > 0) {
            NSString *cmdStr = [NSString stringWithFormat:@"playlist:%@", playlistName];
            [cmdStr writeToFile:@"/tmp/audiostream_pending_cmd" atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [playlistName writeToFile:@"/tmp/audiostream_pending_playlist" atomically:YES encoding:NSUTF8StringEncoding error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                 FBSOpenApplicationService *service = [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
                 [service openApplication:@"com.saihgupr.audiostream" withOptions:nil completion:nil];
            });
            notify_post("com.saihgupr.audiostream.playplaylist");
            rc_show_hud_toast(@"Playlist Queued", [NSString stringWithFormat:@"Shuffling '%@'", playlistName], @"music.note.list");
            return [NSString stringWithFormat:@"Play playlist '%@' command sent to AudioReceiver\n", playlistName];
        }
    } else if ([cleanCmd hasPrefix:@"dnd "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([subCmd isEqualToString:@"on"]) {
            toggle_dnd(YES);
            return @"DND Enabled\n";
        } else if ([subCmd isEqualToString:@"off"]) {
            toggle_dnd(NO);
            return @"DND Disabled\n";
        } else if ([subCmd isEqualToString:@"status"]) {
            BOOL current = get_dnd_state();
            return current ? @"DND ON\n" : @"DND OFF\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_dnd_state();
            toggle_dnd(!current);
            return [NSString stringWithFormat:@"DND %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd hasPrefix:@"location "] || [cleanCmd hasPrefix:@"location-"] ||
               [cleanCmd hasPrefix:@"locationservices "] || [cleanCmd hasPrefix:@"locationservices-"] ||
               [cleanCmd hasPrefix:@"location services "] ||
               [cleanCmd hasPrefix:@"gps "] || [cleanCmd hasPrefix:@"gps-"] ||
               [cleanCmd isEqualToString:@"location"] || [cleanCmd isEqualToString:@"locationservices"] || [cleanCmd isEqualToString:@"location services"] || [cleanCmd isEqualToString:@"gps"]) {
        NSString *subCmd = nil;
        if ([cleanCmd hasPrefix:@"location services "]) subCmd = [cleanCmd substringFromIndex:18];
        else if ([cleanCmd hasPrefix:@"locationservices "]) subCmd = [cleanCmd substringFromIndex:17];
        else if ([cleanCmd hasPrefix:@"locationservices-"]) subCmd = [cleanCmd substringFromIndex:17];
        else if ([cleanCmd hasPrefix:@"location "]) subCmd = [cleanCmd substringFromIndex:9];
        else if ([cleanCmd hasPrefix:@"location-"]) subCmd = [cleanCmd substringFromIndex:9];
        else if ([cleanCmd hasPrefix:@"gps "]) subCmd = [cleanCmd substringFromIndex:4];
        else if ([cleanCmd hasPrefix:@"gps-"]) subCmd = [cleanCmd substringFromIndex:4];
        else subCmd = @"toggle";
        
        subCmd = [subCmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([subCmd isEqualToString:@"on"] || [subCmd isEqualToString:@"enable"] || [subCmd isEqualToString:@"1"]) {
            toggle_location_services(YES);
            return @"Location Services Enabled\n";
        } else if ([subCmd isEqualToString:@"off"] || [subCmd isEqualToString:@"disable"] || [subCmd isEqualToString:@"0"]) {
            toggle_location_services(NO);
            return @"Location Services Disabled\n";
        } else if ([subCmd isEqualToString:@"status"]) {
            BOOL current = get_location_services_state();
            return current ? @"Location Services ON\n" : @"Location Services OFF\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_location_services_state();
            toggle_location_services(!current);
            return [NSString stringWithFormat:@"Location Services %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd hasPrefix:@"lpm "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([subCmd isEqualToString:@"on"]) {
            toggle_lpm(YES);
            return @"Low Power Mode Enabled\n";
        } else if ([subCmd isEqualToString:@"off"]) {
            toggle_lpm(NO);
            return @"Low Power Mode Disabled\n";
        } else if ([subCmd isEqualToString:@"status"]) {
            BOOL current = get_lpm_state();
            return current ? @"Low Power Mode ON\n" : @"Low Power Mode OFF\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_lpm_state();
            toggle_lpm(!current);
            return [NSString stringWithFormat:@"Low Power Mode %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd hasPrefix:@"low power mode "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:15] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([subCmd isEqualToString:@"on"]) {
            toggle_lpm(YES);
            return @"Low Power Mode Enabled\n";
        } else if ([subCmd isEqualToString:@"off"]) {
            toggle_lpm(NO);
            return @"Low Power Mode Disabled\n";
        } else if ([subCmd isEqualToString:@"status"]) {
            BOOL current = get_lpm_state();
            return current ? @"Low Power Mode ON\n" : @"Low Power Mode OFF\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_lpm_state();
            toggle_lpm(!current);
            return [NSString stringWithFormat:@"Low Power Mode %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd hasPrefix:@"low power "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:10] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([subCmd isEqualToString:@"on"]) {
            toggle_lpm(YES);
            return @"Low Power Mode Enabled\n";
        } else if ([subCmd isEqualToString:@"off"]) {
            toggle_lpm(NO);
            return @"Low Power Mode Disabled\n";
        } else if ([subCmd isEqualToString:@"status"]) {
            BOOL current = get_lpm_state();
            return current ? @"Low Power Mode ON\n" : @"Low Power Mode OFF\n";
        } else if ([subCmd isEqualToString:@"toggle"]) {
            BOOL current = get_lpm_state();
            toggle_lpm(!current);
            return [NSString stringWithFormat:@"Low Power Mode %@\n", !current ? @"Enabled" : @"Disabled"];
        }
    } else if ([cleanCmd isEqualToString:@"orientation status"]) {
        __block NSString *result = nil;
        void (^orientationBlock)(void) = ^{
            SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
            UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
            if ([sb respondsToSelector:@selector(activeInterfaceOrientation)]) {
                orientation = [sb activeInterfaceOrientation];
            }
            
            if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown) {
                result = @"PORTRAIT\n";
            } else {
                result = @"LANDSCAPE\n";
            }
        };
        
        if ([NSThread isMainThread]) orientationBlock();
        else dispatch_sync(dispatch_get_main_queue(), orientationBlock);
        return result;
    } else if ([cleanCmd isEqualToString:@"orientation lock"] || [cleanCmd isEqualToString:@"orientation"] || [cleanCmd isEqualToString:@"rotation"] || [cleanCmd isEqualToString:@"rotate"]) {
        return handle_command(@"orientation toggle");
    } else if ([cleanCmd hasPrefix:@"rotate "]) {
        NSString *arg = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        __block NSString *result = nil;
        void (^rotateBlock)(void) = ^{
            SBOrientationLockManager *manager = [objc_getClass("SBOrientationLockManager") sharedInstance];
            if ([arg isEqualToString:@"lock"]) {
                [manager lock];
                result = @"Orientation Locked\n";
            } else if ([arg isEqualToString:@"unlock"]) {
                [manager unlock];
                result = @"Orientation Unlocked\n";
            } else if ([arg isEqualToString:@"toggle"]) {
                if ([manager isUserLocked]) [manager unlock];
                else [manager lock];
                result = [NSString stringWithFormat:@"Orientation %@\n", ![manager isUserLocked] ? @"Locked" : @"Unlocked"];
            } else {
                BOOL isLocked = [manager isUserLocked];
                result = [NSString stringWithFormat:@"Orientation Lock Status: %@\n", isLocked ? @"Locked" : @"Unlocked"];
            }
        };
        
        if ([NSThread isMainThread]) rotateBlock();
        else dispatch_sync(dispatch_get_main_queue(), rotateBlock);
        return result;
    } else if ([cleanCmd isEqualToString:@"rotate"]) {
         __block NSString *result = nil;
         void (^statusBlock)(void) = ^{
             SBOrientationLockManager *manager = [objc_getClass("SBOrientationLockManager") sharedInstance];
             BOOL isLocked = [manager isUserLocked];
             result = [NSString stringWithFormat:@"Orientation Lock Status: %@\n", isLocked ? @"Locked" : @"Unlocked"];
         };
         
         if ([NSThread isMainThread]) statusBlock();
         else dispatch_sync(dispatch_get_main_queue(), statusBlock);
         return result;
    } else if ([cleanCmd isEqualToString:@"mute"]) {
        return @"Usage: rc mute [on|off|status]\n";
    } else if ([cleanCmd hasPrefix:@"mute "]) {
        NSString *subCmd = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Try AVSystemController first (Media State)
        void *celestialHandle = dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", RTLD_NOW);
        if (celestialHandle) {
             Class AVSystemControllerClass = objc_getClass("AVSystemController");
             if (AVSystemControllerClass) {
                 @try {
                     id controller = [AVSystemControllerClass sharedAVSystemController];
                     if (controller) {
                         if ([subCmd isEqualToString:@"status"]) {
                             float currentVol = 0;
                             if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                                 [controller getVolume:&currentVol forCategory:@"Audio/Video"];
                             }
                             
                             // Also check mute state
                             BOOL isMuted = NO;
                             if ([controller respondsToSelector:@selector(getActiveCategoryMuted:)]) {
                                 [controller getActiveCategoryMuted:&isMuted];
                             }
                             
                             if (isMuted || currentVol == 0.0f) {
                                 return @"Muted (Media)\n";
                             } else {
                                 return [NSString stringWithFormat:@"Unmuted (Media, Vol: %d%%)\n", (int)(currentVol * 100)];
                             }
                             
                         } else if ([subCmd isEqualToString:@"on"]) {
                             // Save current volume if we haven't already
                             float currentVol = 0;
                             if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                                 [controller getVolume:&currentVol forCategory:@"Audio/Video"];
                                 if (currentVol > 0) {
                                     sr_previous_volume = currentVol;
                                     SRLog(@"Saved previous volume: %f", sr_previous_volume);
                                 }
                             }
                             
                             // Set volume to 0
                             if ([controller respondsToSelector:@selector(setActiveCategoryVolumeTo:)]) {
                                 [controller setActiveCategoryVolumeTo:0.0f];
                                 return @"Muted (Media)\n";
                             }
                             
                         } else if ([subCmd isEqualToString:@"off"]) {
                             // Check if already unmuted (vol > 0)
                             float currentVol = 0;
                             if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                                 [controller getVolume:&currentVol forCategory:@"Audio/Video"];
                             }
                             
                             if (currentVol > 0) {
                                  return @"Already Unmuted\n";
                             }

                             // Restore volume
                             float targetVol = (sr_previous_volume > 0) ? sr_previous_volume : 0.5f; // Default 50%
                             
                             if ([controller respondsToSelector:@selector(setActiveCategoryVolumeTo:)]) {
                                 [controller setActiveCategoryVolumeTo:targetVol];
                                 sr_previous_volume = -1.0f; // Reset
                                 return @"Unmuted (Media)\n";
                             }
                         } else if ([subCmd isEqualToString:@"toggle"]) {
                             float currentVol = 0;
                             if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                                 [controller getVolume:&currentVol forCategory:@"Audio/Video"];
                             }
                             BOOL isMuted = NO;
                             if ([controller respondsToSelector:@selector(getActiveCategoryMuted:)]) {
                                 [controller getActiveCategoryMuted:&isMuted];
                             }
                             
                             if (isMuted || currentVol == 0.0f) {
                                 return handle_command(@"mute off");
                             } else {
                                 return handle_command(@"mute on");
                             }
                         }
                     }
                 } @catch (NSException *e) {
                     SRLog(@"Exception in mute: %@", e);
                 }
             }
        }
        
        return @"Error: AVSystemController failed. Cannot control media mute.\n";
    } else if ([cleanCmd isEqualToString:@"volume up"] || [cleanCmd isEqualToString:@"vol up"]) {
        inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VolumeIncrement, 0, 0);
        return @"OK\n";
    } else if ([cleanCmd isEqualToString:@"volume down"] || [cleanCmd isEqualToString:@"vol down"]) {
        inject_hid_event(kHIDPage_Consumer, kHIDUsage_Csmr_VolumeDecrement, 0, 0);
        return @"OK\n";
    } else if ([cleanCmd hasPrefix:@"volume "] || [cleanCmd hasPrefix:@"volume"]) { // Matches "volume" and "volume <N>"
        NSString *arg = nil;
        if (cleanCmd.length > 7) {
             arg = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if (cleanCmd.length > 6) {
             arg = [[cleanCmd substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        void *celestialHandle = dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", RTLD_NOW);
        if (celestialHandle) {
             Class AVSystemControllerClass = objc_getClass("AVSystemController");
             if (AVSystemControllerClass) {
                 @try {
                     id controller = [AVSystemControllerClass sharedAVSystemController];
                     if (controller) {
                         // Set Volume
                         if (arg && arg.length > 0) {
                             // Safety check: ensure arg starts with a digit before using floatValue
                             // as floatValue returns 0.0 for non-numeric strings like "up"
                             if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[arg characterAtIndex:0]]) {
                                 float target = [arg floatValue] / 100.0f;
                                 if (target < 0) target = 0;
                                 if (target > 1) target = 1;
                                 
                                 if ([controller respondsToSelector:@selector(setActiveCategoryVolumeTo:)]) {
                                     [controller setActiveCategoryVolumeTo:target];
                                     return [NSString stringWithFormat:@"Volume set to %d%%\n", (int)(target * 100)];
                                 }
                             } else {
                                 SRLog(@"Ignored non-numeric volume argument: %@", arg);
                                 return [NSString stringWithFormat:@"Error: Invalid volume level '%@'\n", arg];
                             }
                         }
                         
                         // Get Volume (default)
                         float volume = 0;
                         if ([controller respondsToSelector:@selector(getVolume:forCategory:)]) {
                             [controller getVolume:&volume forCategory:@"Audio/Video"];
                             int volumePercent = (int)(volume * 100);
                             return [NSString stringWithFormat:@"Volume: %d%%\n", volumePercent];
                         }
                     }
                 } @catch (NSException *e) {
                     SRLog(@"Exception volume: %@", e);
                 }
             }
        }
        return @"Error: AVSystemController failed.\n";
    } else if ([cleanCmd isEqualToString:@"camera"] || [cleanCmd hasPrefix:@"camera "] || 
               [cleanCmd isEqualToString:@"open camera"] || [cleanCmd hasPrefix:@"open camera "]) {
        NSString *lowCmd = [cleanCmd lowercaseString];
        
        // Mode detection
        NSInteger mode = 0; // 0 = Photo (default)
        if ([lowCmd containsString:@"video"] || [lowCmd containsString:@"movie"] || [lowCmd containsString:@"vid"] || [lowCmd containsString:@"2x"] || [lowCmd containsString:@"record"]) {
            mode = 1;
        }
        if ([lowCmd containsString:@"photo"] || [lowCmd containsString:@"still"] || [lowCmd containsString:@"pic"] || [lowCmd containsString:@"picture"]) {
            mode = 0;
        }
        if ([lowCmd containsString:@"portrait"] || [lowCmd containsString:@"port"]) {
            mode = 6;
        }
        if ([lowCmd containsString:@"slomo"] || [lowCmd containsString:@"slo-mo"] || [lowCmd containsString:@"slowmo"] || [lowCmd containsString:@"slow-mo"]) {
            mode = 2;
        }
        if ([lowCmd containsString:@"timelapse"] || [lowCmd containsString:@"time-lapse"] || [lowCmd containsString:@"lapse"]) {
            mode = 4;
        }
        if ([lowCmd containsString:@"pano"] || [lowCmd containsString:@"panorama"]) {
            mode = 3;
        }
        if ([lowCmd containsString:@"cinematic"] || [lowCmd containsString:@"cinema"]) {
            mode = 7;
        }
        
        // Device detection (0 = Back, 1 = Front)
        NSInteger device = 0;
        if ([lowCmd containsString:@"front"] || [lowCmd containsString:@"selfie"]) {
            device = 1;
        }
        
        // Flash / Torch
        BOOL hasFlash = ([lowCmd containsString:@"flash"] || [lowCmd containsString:@"torch"]);
        
        // Standalone Shutter / Record Toggle commands
        if ([lowCmd isEqualToString:@"camera shutter"] || [lowCmd isEqualToString:@"camera snap"] || 
            [lowCmd isEqualToString:@"camera capture"] || [lowCmd isEqualToString:@"camera record toggle"] || 
            [lowCmd isEqualToString:@"camera record-toggle"]) {
            notify_post("com.saihgupr.remotecompanion.camera_shutter");
            return [lowCmd containsString:@"record"] ? @"Toggled Camera Recording\n" : @"Triggered Camera Shutter\n";
        }
        
        // Auto Shutter on launch
        BOOL autoShutter = ([lowCmd containsString:@"record"] || [lowCmd containsString:@"snap"] || [lowCmd containsString:@"capture"] || [lowCmd containsString:@"shoot"]);
        
        // Zoom factor extraction
        double zoom = 0.0;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+(\\.\\d+)?)\\s*x" options:NSRegularExpressionCaseInsensitive error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:lowCmd options:0 range:NSMakeRange(0, lowCmd.length)];
        if (match) {
            NSString *zoomStr = [lowCmd substringWithRange:[match rangeAtIndex:1]];
            zoom = [zoomStr doubleValue];
        } else {
            NSArray *tokens = [lowCmd componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            for (NSString *tok in tokens) {
                if ([tok isEqualToString:@"camera"] || [tok isEqualToString:@"open"] || [tok isEqualToString:@"video"] || 
                    [tok isEqualToString:@"photo"] || [tok isEqualToString:@"portrait"] || [tok isEqualToString:@"slomo"] ||
                    [tok isEqualToString:@"timelapse"] || [tok isEqualToString:@"pano"] || [tok isEqualToString:@"cinematic"] ||
                    [tok isEqualToString:@"front"] || [tok isEqualToString:@"selfie"] || [tok isEqualToString:@"back"] ||
                    [tok isEqualToString:@"flash"] || [tok isEqualToString:@"torch"] || [tok isEqualToString:@"on"] || 
                    [tok isEqualToString:@"off"] || [tok isEqualToString:@"record"] || [tok isEqualToString:@"snap"] ||
                    [tok isEqualToString:@"capture"] || [tok isEqualToString:@"shoot"]) continue;
                double v = [tok doubleValue];
                if (v > 0) {
                    zoom = v;
                    break;
                }
            }
        }
        
        if (zoom <= 0) {
            zoom = (mode == 1 && device == 0) ? 2.0 : 1.0;
        }
        
        return rc_open_camera_unified(mode, device, zoom, hasFlash ? 1 : 0, autoShutter);
    } else if ([cleanCmd hasPrefix:@"uiopen "]) {
        NSString *bundleId = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSLog(@"[RemoteCommand] UIOPEN Bundle ID: %@", bundleId);
        dispatch_async(dispatch_get_main_queue(), ^{
             FBSOpenApplicationService *service = [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
             [service openApplication:bundleId withOptions:nil completion:nil];
        });
        return [NSString stringWithFormat:@"Opened %@", bundleId];
    } else if ([cleanCmd hasPrefix:@"open "]) {
        // Open app by name or Bundle ID
        NSString *appName = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // If it looks like a Bundle ID (contains dot), use FBSOpenApplicationService (faster)
        if ([appName containsString:@"."]) {
             NSLog(@"[RemoteCommand] Opening Bundle ID via FBS: %@", appName);
             dispatch_async(dispatch_get_main_queue(), ^{
                 FBSOpenApplicationService *service = [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
                 [service openApplication:appName withOptions:nil completion:nil];
             });
             return [NSString stringWithFormat:@"Opened %@", appName];
        }

        NSString *lowerName = [appName lowercaseString];
        NSString *urlString = nil;
        
        // Common app URL schemes
        if ([lowerName isEqualToString:@"spotify"]) urlString = @"spotify://";
        else if ([lowerName isEqualToString:@"music"]) urlString = @"music://";
        else if ([lowerName isEqualToString:@"youtube"]) urlString = @"youtube://";
        else if ([lowerName isEqualToString:@"safari"]) urlString = @"x-web-search://";
        else if ([lowerName isEqualToString:@"settings"]) urlString = @"App-prefs://";
        else if ([lowerName isEqualToString:@"camera"]) urlString = @"camera://";
        else if ([lowerName isEqualToString:@"photos"]) urlString = @"photos-redirect://";
        else if ([lowerName isEqualToString:@"maps"]) urlString = @"maps://";
        else if ([lowerName isEqualToString:@"messages"]) urlString = @"sms://";
        else if ([lowerName isEqualToString:@"phone"]) urlString = @"tel://";
        else if ([lowerName isEqualToString:@"mail"]) urlString = @"mailto://";
        else if ([lowerName isEqualToString:@"notes"]) urlString = @"mobilenotes://";
        else if ([lowerName isEqualToString:@"reminders"]) urlString = @"x-apple-reminderkit://";
        else if ([lowerName isEqualToString:@"calendar"]) urlString = @"calshow://";
        else if ([lowerName isEqualToString:@"clock"]) urlString = @"clock-alarm://";
        else if ([lowerName isEqualToString:@"weather"]) urlString = @"weather://";
        else if ([lowerName isEqualToString:@"shortcuts"]) urlString = @"shortcuts://";
        else urlString = [NSString stringWithFormat:@"%@://", lowerName]; // Try app name as scheme
        
        NSLog(@"[RemoteCommand] Opening app: %@ via %@", appName, urlString);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSURL *url = [NSURL URLWithString:urlString];
            if (url) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }
        });
    } else if ([cleanCmd isEqualToString:@"bluetooth-on"] || [cleanCmd isEqualToString:@"bt-on"] || [cleanCmd isEqualToString:@"bluetooth on"] || [cleanCmd isEqualToString:@"bt on"]) {
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                [btManager setEnabled:YES];
                [btManager setPowered:YES];
                SRLog(@"Bluetooth enabled");
                return @"Bluetooth Enabled\n";
            }
        }
        return @"Error: BluetoothManager not found\n";
    } else if ([cleanCmd isEqualToString:@"bluetooth status"] || [cleanCmd isEqualToString:@"bt status"]) {
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                BOOL isPowered = [btManager powered];
                return [NSString stringWithFormat:@"Bluetooth %@\n", isPowered ? @"ON" : @"OFF"];
            }
        }
        return @"Error: BluetoothManager not found\n";
    } else if ([cleanCmd isEqualToString:@"bluetooth-off"] || [cleanCmd isEqualToString:@"bt-off"] || [cleanCmd isEqualToString:@"bluetooth off"] || [cleanCmd isEqualToString:@"bt off"]) {
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                [btManager setEnabled:NO];
                [btManager setPowered:NO];
                SRLog(@"Bluetooth disabled");
                return @"Bluetooth Disabled\n";
            }
        }
        return @"Error: BluetoothManager not found\n";
    } else if ([cleanCmd isEqualToString:@"bluetooth list"] || [cleanCmd isEqualToString:@"bt list"]) {
        NSMutableString *output = [NSMutableString string];
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                for (BluetoothDevice *device in [btManager pairedDevices]) {
                    NSString *name = [device name] ?: @"Unknown Device";
                    [output appendFormat:@"%@\n", name];
                }
            }
        }
        return output.length > 0 ? output : @"No paired Bluetooth devices found\n";
    } else if ([cleanCmd hasPrefix:@"bt-connect "] || [cleanCmd hasPrefix:@"bt connect "] || [cleanCmd hasPrefix:@"bluetooth connect "]) {
        NSString *deviceName;
        if ([cleanCmd hasPrefix:@"bt connect "]) deviceName = [cleanCmd substringFromIndex:11];
        else if ([cleanCmd hasPrefix:@"bluetooth connect "]) deviceName = [cleanCmd substringFromIndex:18];
        else deviceName = [cleanCmd substringFromIndex:11];
        deviceName = [deviceName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                for (BluetoothDevice *device in [btManager pairedDevices]) {
                    if ([[device name] localizedCaseInsensitiveContainsString:deviceName]) {
                        [device connect];
                        SRLog(@"Connecting to BT device: %@", [device name]);
                        return [NSString stringWithFormat:@"Connecting to %@\n", [device name]];
                    }
                }
            }
        }
        return @"Error: Device not found or BluetoothManager failed\n";
    } else if ([cleanCmd hasPrefix:@"bt-disconnect "] || [cleanCmd hasPrefix:@"bt disconnect "] || [cleanCmd hasPrefix:@"bluetooth disconnect "]) {
        NSString *deviceName;
        if ([cleanCmd hasPrefix:@"bt disconnect "]) deviceName = [cleanCmd substringFromIndex:14];
        else if ([cleanCmd hasPrefix:@"bluetooth disconnect "]) deviceName = [cleanCmd substringFromIndex:21];
        else deviceName = [cleanCmd substringFromIndex:14];
        deviceName = [deviceName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
        if (btHandle) {
            Class BluetoothManagerClass = objc_getClass("BluetoothManager");
            if (BluetoothManagerClass) {
                BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                for (BluetoothDevice *device in [btManager pairedDevices]) {
                    if ([[device name] localizedCaseInsensitiveContainsString:deviceName]) {
                        [device disconnect];
                        SRLog(@"Disconnecting BT device: %@", [device name]);
                        return [NSString stringWithFormat:@"Disconnecting %@\n", [device name]];
                    }
                }
            }
        }
        return @"Error: Device not found or BluetoothManager failed\n";
    } else if ([cleanCmd hasPrefix:@"appearance "]) {
        NSString *arg = [[cleanCmd substringFromIndex:11] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        void *uikitHandle = dlopen("/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore", RTLD_NOW);
        if (uikitHandle) {
            Class StyleModeClass = objc_getClass("UISUserInterfaceStyleMode");
            if (StyleModeClass) {
                id styleMode = [[StyleModeClass alloc] init];
                if ([arg isEqualToString:@"dark"]) {
                    [styleMode setModeValue:2];
                    return @"Appearance set to Dark\n";
                } else if ([arg isEqualToString:@"light"]) {
                    [styleMode setModeValue:1];
                    return @"Appearance set to Light\n";
                } else if ([arg isEqualToString:@"toggle"]) {
                    NSInteger current = [styleMode modeValue];
                    NSInteger next = (current == 2) ? 1 : 2;
                    [styleMode setModeValue:next];
                    return [NSString stringWithFormat:@"Appearance toggled to %@\n", next == 2 ? @"Dark" : @"Light"];
                } else if ([arg isEqualToString:@"status"]) {
                    NSInteger current = [styleMode modeValue];
                    return [NSString stringWithFormat:@"Appearance: %@\n", current == 2 ? @"Dark" : @"Light"];
                }
            }
        }
        return @"Error: UISUserInterfaceStyleMode not found\n";
    } else if ([cleanCmd isEqualToString:@"wifi-on"] || [cleanCmd isEqualToString:@"wi-on"] || [cleanCmd isEqualToString:@"wifi on"]) {
        SBWiFiManager *manager = [objc_getClass("SBWiFiManager") sharedInstance];
        if (manager) {
            [manager setWiFiEnabled:YES];
            SRLog(@"WiFi enabled");
            return @"WiFi Enabled\n";
        }
        return @"Error: SBWiFiManager not found\n";
    } else if ([cleanCmd isEqualToString:@"wifi status"] || [cleanCmd isEqualToString:@"wi status"]) {
        SBWiFiManager *manager = [objc_getClass("SBWiFiManager") sharedInstance];
        if (manager) {
            BOOL isEnabled = [manager wiFiEnabled];
            return [NSString stringWithFormat:@"WiFi %@\n", isEnabled ? @"ON" : @"OFF"];
        }
        return @"Error: SBWiFiManager not found\n";
    } else if ([cleanCmd isEqualToString:@"wifi-off"] || [cleanCmd isEqualToString:@"wi-off"] || [cleanCmd isEqualToString:@"wifi off"]) {
        SBWiFiManager *manager = [objc_getClass("SBWiFiManager") sharedInstance];
        if (manager) {
            [manager setWiFiEnabled:NO];
            SRLog(@"WiFi disabled");
            return @"WiFi Disabled\n";
        }
        return @"Error: SBWiFiManager not found\n";
    } else if ([cleanCmd isEqualToString:@"cellular-on"] || [cleanCmd isEqualToString:@"cell-on"] || [cleanCmd isEqualToString:@"cellular on"] || [cleanCmd isEqualToString:@"cell on"]) {
        if (set_cellular_state(YES)) {
            SRLog(@"Cellular data enabled");
            return @"Cellular Data Enabled\n";
        }
        return @"Error: CoreTelephony call failed\n";
    } else if ([cleanCmd isEqualToString:@"cellular status"] || [cleanCmd isEqualToString:@"cell status"]) {
        BOOL isEnabled = get_cellular_state();
        return [NSString stringWithFormat:@"Cellular Data %@\n", isEnabled ? @"ON" : @"OFF"];
    } else if ([cleanCmd isEqualToString:@"cellular-off"] || [cleanCmd isEqualToString:@"cell-off"] || [cleanCmd isEqualToString:@"cellular off"] || [cleanCmd isEqualToString:@"cell off"]) {
        if (set_cellular_state(NO)) {
            SRLog(@"Cellular data disabled");
            return @"Cellular Data Disabled\n";
        }
        return @"Error: CoreTelephony call failed\n";
    } else if ([cleanCmd isEqualToString:@"cellular-toggle"] || [cleanCmd isEqualToString:@"cell-toggle"] || [cleanCmd isEqualToString:@"cellular toggle"] || [cleanCmd isEqualToString:@"cell toggle"] || [cleanCmd isEqualToString:@"cellular"] || [cleanCmd isEqualToString:@"cell"]) {
        BOOL current = get_cellular_state();
        if (set_cellular_state(!current)) {
            SRLog(@"Cellular data toggled: %d -> %d", current, !current);
            return [NSString stringWithFormat:@"Cellular Data Toggled: %@\n", !current ? @"ON" : @"OFF"];
        }
        return @"Error: CoreTelephony call failed\n";
    } else if ([cleanCmd isEqualToString:@"airplane on"]) {
        SRLog(@"Executing airplane ON...");
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        Class RPClass = objc_getClass("RadiosPreferences");
        if (RPClass) {
            RadiosPreferences *prefs = [[RPClass alloc] init];
            [prefs setAirplaneMode:YES];
            [prefs synchronize];
            SRLog(@"Airplane Mode ON");
            return @"Airplane Mode ON\n";
        }
        return @"Error: RadiosPreferences not found\n";
    } else if ([cleanCmd isEqualToString:@"airplane off"]) {
        SRLog(@"Executing airplane OFF...");
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        Class RPClass = objc_getClass("RadiosPreferences");
        if (RPClass) {
            RadiosPreferences *prefs = [[RPClass alloc] init];
            [prefs setAirplaneMode:NO];
            [prefs synchronize];
            SRLog(@"Airplane Mode OFF");
            return @"Airplane Mode OFF\n";
        }
        return @"Error: RadiosPreferences not found\n";
    } else if ([cleanCmd isEqualToString:@"airplane"] || [cleanCmd isEqualToString:@"airplane toggle"]) {
        SRLog(@"Executing airplane toggle...");
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        Class RPClass = objc_getClass("RadiosPreferences");
        if (RPClass) {
            RadiosPreferences *prefs = [[RPClass alloc] init];
            BOOL current = [prefs airplaneMode];
            [prefs setAirplaneMode:!current];
            [prefs synchronize];
            SRLog(@"Airplane Mode Toggled: %d -> %d", current, !current);
            return [NSString stringWithFormat:@"Airplane Mode Toggled: %@\n", !current ? @"ON" : @"OFF"];
        }
    } else if ([cleanCmd isEqualToString:@"airplane status"]) {
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        Class RPClass = objc_getClass("RadiosPreferences");
        if (RPClass) {
            RadiosPreferences *prefs = [[RPClass alloc] init];
            BOOL current = [prefs airplaneMode];
            return [NSString stringWithFormat:@"Airplane Mode %@\n", current ? @"ON" : @"OFF"];
        }
        return @"Error: RadiosPreferences not found\n";
    } else if ([cleanCmd hasPrefix:@"brightness "]) {
        // Set screen brightness (0-100) using BackBoardServices
        NSString *valueStr = [[cleanCmd substringFromIndex:11] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        float value = [valueStr floatValue];
        // Clamp to 0-100 and convert to 0.0-1.0
        value = fmaxf(0, fminf(100, value)) / 100.0f;
        
        void *bbHandle = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
        if (bbHandle) {
            void (*BKSDisplayBrightnessSet)(float, int) = dlsym(bbHandle, "BKSDisplayBrightnessSet");
            if (BKSDisplayBrightnessSet) {
                BKSDisplayBrightnessSet(value, 1);
                NSLog(@"[RemoteCommand] Brightness set to: %.0f%%", value * 100);
            }
        }

    } else if ([cleanCmd hasPrefix:@"set-vol "]) {
        NSString *valStr = [[cleanCmd substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        float val = [valStr floatValue];
        // Clamp 0-100 -> 0.0-1.0
        val = fmaxf(0, fminf(100, val)) / 100.0f;
        
        SRLog(@"Setting volume to %.2f", val);
        
        // Use AVSystemController
        AVSystemController *av = [objc_getClass("AVSystemController") sharedAVSystemController];
        if (av) {
            [av setVolumeTo:val forCategory:@"Audio/Video"];
            return [NSString stringWithFormat:@"Volume set to %.0f%%\n", val * 100];
        } else {
            return @"Error: AVSystemController not found\n";
        }    
    } else if ([cleanCmd hasPrefix:@"vibration "]) {
        NSString *subcheck = [cleanCmd substringFromIndex:10];
        
        // Silent Mode Vibration
        if ([subcheck isEqualToString:@"silent-on"]) {
            toggle_system_vibration(YES, YES);
            return @"Silent Vibrate: ON\n";
        } else if ([subcheck isEqualToString:@"silent-off"]) {
            toggle_system_vibration(YES, NO);
            return @"Silent Vibrate: OFF\n";
        } else if ([subcheck isEqualToString:@"silent-toggle"]) {
            BOOL current = get_system_vibration(YES);
            toggle_system_vibration(YES, !current);
            return current ? @"Silent Vibrate: OFF\n" : @"Silent Vibrate: ON\n";
        } else if ([subcheck isEqualToString:@"silent-status"]) {
             BOOL current = get_system_vibration(YES);
             return current ? @"Silent Vibrate: ON\n" : @"Silent Vibrate: OFF\n";
        }
        
        // Ring Mode Vibration
        else if ([subcheck isEqualToString:@"ring-on"]) {
            toggle_system_vibration(NO, YES);
            return @"Ring Vibrate: ON\n";
        } else if ([subcheck isEqualToString:@"ring-off"]) {
            toggle_system_vibration(NO, NO);
            return @"Ring Vibrate: OFF\n";
        } else if ([subcheck isEqualToString:@"ring-toggle"]) {
            BOOL current = get_system_vibration(NO);
            toggle_system_vibration(NO, !current);
            return current ? @"Ring Vibrate: OFF\n" : @"Ring Vibrate: ON\n";
        } else if ([subcheck isEqualToString:@"ring-status"]) {
             BOOL current = get_system_vibration(NO);
             return current ? @"Ring Vibrate: ON\n" : @"Ring Vibrate: OFF\n";
        }
    } else if ([cleanCmd isEqualToString:@"haptic"]) {
        // Haptic feedback using UIImpactFeedbackGenerator
        dispatch_async(dispatch_get_main_queue(), ^{
            // Respect global setting for this manual command too? 
            // The user might want this to FORCE a haptic, but let's respect the setting for consistency unless it's a "test".
            // Actually, "haptic" command is often used for testing. Let's make it respect the setting via trigger_haptic()
            trigger_haptic();
        });
        NSLog(@"[RemoteCommand] Haptic triggered");
        return @"Haptic triggered\n";
    } else if ([cleanCmd isEqualToString:@"ping"]) {
        AudioServicesPlaySystemSound(1005);
        NSLog(@"[RemoteCommand] Ping (Alert Sound) played");
        return @"Ping played\n";
    } else if ([cleanCmd isEqualToString:@"flash-on"] || [cleanCmd isEqualToString:@"flash on"]) {
        // Flashlight on using AVCaptureDevice
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch] && [device isTorchAvailable]) {
            [device lockForConfiguration:nil];
            [device setTorchMode:AVCaptureTorchModeOn];
            [device unlockForConfiguration];
            NSLog(@"[RemoteCommand] Flashlight on");
        }
        return @"Flashlight ON\n";
    } else if ([cleanCmd isEqualToString:@"flash-off"] || [cleanCmd isEqualToString:@"flash off"]) {
        // Flashlight off
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            [device setTorchMode:AVCaptureTorchModeOff];
            [device unlockForConfiguration];
            NSLog(@"[RemoteCommand] Flashlight off");
        }
    } else if ([cleanCmd isEqualToString:@"flashlight toggle"]) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch] && [device isTorchAvailable]) {
            [device lockForConfiguration:nil];
            if ([device torchMode] == AVCaptureTorchModeOn) {
                [device setTorchMode:AVCaptureTorchModeOff];
                NSLog(@"[RemoteCommand] Flashlight toggled OFF");
            } else {
                float level = get_flash_brightness();
                [device setTorchModeOnWithLevel:level error:nil];
                NSLog(@"[RemoteCommand] Flashlight toggled ON at level %f", level);
            }
            [device unlockForConfiguration];
        }
    } else if ([cleanCmd isEqualToString:@"flashlight on"]) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch] && [device isTorchAvailable]) {
            [device lockForConfiguration:nil];
            float level = get_flash_brightness();
            [device setTorchModeOnWithLevel:level error:nil];
            [device unlockForConfiguration];
        }
    } else if ([cleanCmd isEqualToString:@"flashlight off"]) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            [device setTorchMode:AVCaptureTorchModeOff];
            [device unlockForConfiguration];
        }
    } else if ([cleanCmd isEqualToString:@"flashlight status"]) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            return [NSString stringWithFormat:@"Flashlight %@\n", [device torchMode] == AVCaptureTorchModeOn ? @"ON" : @"OFF"];
        }
        return @"Error: Flashlight not found\n";
    } else if ([cleanCmd hasPrefix:@"kill "]) {
        NSString *arg = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *bundleID = resolve_bundle_id(arg);
        
        SRLog(@"Killing app: %@ (mapped from %@)", bundleID, arg);
        // Reason 5 = Quit via App Switcher (clean kill)
        BKSTerminateApplicationForReasonAndReportWithDescription(bundleID, 5, false, nil);
        return [NSString stringWithFormat:@"Killed %@\n", bundleID];
    } else if ([cleanCmd isEqualToString:@"app"]) {
        __block NSString *pid = nil;
        void (^getBlock)(void) = ^{
            SBApplication *frontApp = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication];
            pid = [frontApp bundleIdentifier];
        };
        
        if ([NSThread isMainThread]) getBlock();
        else dispatch_sync(dispatch_get_main_queue(), getBlock);
        
        if (pid) {
            return [NSString stringWithFormat:@"%@\n", pid];
        }
        return @"com.apple.springboard\n"; // Fallback
    } else if ([cleanCmd hasPrefix:@"rotate "]) {
        NSString *arg = [[cleanCmd substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        __block NSString *result = nil;
        void (^rotateBlock)(void) = ^{
            SBOrientationLockManager *manager = [objc_getClass("SBOrientationLockManager") sharedInstance];
            if ([arg isEqualToString:@"lock"]) {
                [manager lock];
                result = @"Orientation Locked\n";
            } else if ([arg isEqualToString:@"unlock"]) {
                [manager unlock];
                result = @"Orientation Unlocked\n";
            } else {
                BOOL isLocked = [manager isUserLocked];
                result = [NSString stringWithFormat:@"Orientation Lock Status: %@\n", isLocked ? @"Locked" : @"Unlocked"]; // Fallback to status
            }
        };
        
        if ([NSThread isMainThread]) rotateBlock();
        else dispatch_sync(dispatch_get_main_queue(), rotateBlock);
        return result;
    } else if ([cleanCmd isEqualToString:@"rotate"]) {
         __block NSString *result = nil;
         void (^statusBlock)(void) = ^{
             SBOrientationLockManager *manager = [objc_getClass("SBOrientationLockManager") sharedInstance];
             BOOL isLocked = [manager isUserLocked];
             result = [NSString stringWithFormat:@"Orientation Lock Status: %@\n", isLocked ? @"Locked" : @"Unlocked"];
         };
         
         if ([NSThread isMainThread]) statusBlock();
         else dispatch_sync(dispatch_get_main_queue(), statusBlock);
         return result;
    } else if ([cleanCmd hasPrefix:@"paste "]) {
        NSString *content = [[cleanCmd substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        dispatch_block_t pasteBlock = ^{
             UIPasteboard *pb = [UIPasteboard generalPasteboard];
             pb.string = content;
        };
        
        if ([NSThread isMainThread]) pasteBlock();
        else dispatch_sync(dispatch_get_main_queue(), pasteBlock);
        return [NSString stringWithFormat:@"Clipboard set to: %@\n", content];
    } else if ([cleanCmd hasPrefix:@"type "]) {
        NSString *text = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        SRLog(@"Typing text: %@", text);
        const char *utf8 = [text UTF8String];
        size_t len = strlen(utf8);
        for (size_t i = 0; i < len; i++) {
            type_character(utf8[i]);
            usleep(50000); // 50ms delay between keys
        }
        return @"Typing completed\n";
    } else if ([cleanCmd isEqualToString:@"home"]) {
         simulate_home_press();
         return @"Home Button Success\n";
    } else if ([cleanCmd isEqualToString:@"screenshot"]) {
         dispatch_async(dispatch_get_main_queue(), ^{
             @try {
                 SRLog(@"Attempting screenshot via SpringBoard takeScreenshot...");
                 SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
                 if ([sb respondsToSelector:@selector(takeScreenshot)]) {
                     [sb performSelector:@selector(takeScreenshot)];
                     SRLog(@"Screenshot triggered via [SpringBoard takeScreenshot]");
                 } else {
                     SRLog(@"[SpringBoard takeScreenshot] selector missing");
                     
                     // Fallback check for new screenshot manager location
                     if ([sb respondsToSelector:@selector(screenshotManager)]) {
                         id manager = [sb performSelector:@selector(screenshotManager)];
                         if (manager && [manager respondsToSelector:@selector(saveScreenshotToCameraRollWithCompletion:)]) {
                             [manager saveScreenshotToCameraRollWithCompletion:nil];
                             SRLog(@"Screenshot triggered via [SB screenshotManager]");
                         }
                     }
                 }
             } @catch (NSException *e) {
                 SRLog(@"Exception triggering screenshot: %@", e);
             }
         });
         return @"Screenshot triggered\n";
    } else if ([cleanCmd isEqualToString:@"screenrecord"] || [cleanCmd hasPrefix:@"screenrecord "]) {
        NSString *arg = @"";
        if ([cleanCmd hasPrefix:@"screenrecord "]) {
            arg = [[cleanCmd substringFromIndex:13] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        return rc_handle_screenrecord(arg);
    } else if ([cleanCmd isEqualToString:@"snapper"] || [cleanCmd hasPrefix:@"snapper "]) {
        NSString *arg = @"";
        if ([cleanCmd hasPrefix:@"snapper "]) {
            arg = [[cleanCmd substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        return rc_handle_snapper(arg);
    } else if ([cleanCmd hasPrefix:@"delay "]) {
        NSString *delayStr = [cleanCmd substringFromIndex:6];
        float seconds = [delayStr floatValue];
        if (seconds > 0) {
            SRLog(@"Delaying for %.2f seconds...", seconds);
            usleep((useconds_t)(seconds * 1000000));
        }
        return [NSString stringWithFormat:@"Delayed for %.2f seconds\n", seconds];
    } else if ([cleanCmd hasPrefix:@"root "] || [cleanCmd hasPrefix:@"sudo "]) {
        // Execute command as root via setuid helper
        NSString *shellCmd = [cleanCmd hasPrefix:@"root "]
            ? [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            : [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        SRLog(@"Executing as root: %@", shellCmd);

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // Use rc-root setuid helper with posix_spawn
            pid_t pid;
            const char *rcRootPath = "/var/jb/usr/bin/rc-root";
            char *args[] = {(char *)rcRootPath, (char *)[shellCmd UTF8String], NULL};

            extern char **environ;
            int spawn_result = rc_posix_spawn(&pid, rcRootPath, NULL, NULL, args, environ);

            int result = -1;
            if (spawn_result == 0) {
                int status;
                waitpid(pid, &status, 0);
                if (WIFEXITED(status)) {
                    result = WEXITSTATUS(status);
                }
            } else {
                SRLog(@"posix_spawn failed: %d", spawn_result);
            }
            SRLog(@"Root command finished with exit code: %d", result);
        });
        return [NSString stringWithFormat:@"Executing as root: %@\n", shellCmd];
    } else if ([cleanCmd hasPrefix:@"exec "]) {
        NSString *shellCmd = [[cleanCmd substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        SRLog(@"Processing command: %@", shellCmd);

        if ([shellCmd hasPrefix:@"rc "]) {
             NSString *internalCmd = [shellCmd substringFromIndex:3];
             SRLog(@"Intercepting 'rc' command, executing internally: %@", internalCmd);
             return handle_command(internalCmd);
        } else if ([shellCmd hasPrefix:@"curl "]) {
            SRLog(@"Detected curl command, using native implementation");
            perform_native_curl(shellCmd);
            return [NSString stringWithFormat:@"Executing via native curl: %@\n", shellCmd];
        } else {
            // Use posix_spawn with custom PATH
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSString *basePath = @"/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
                NSString *fullPath = basePath;

                // Setup environment with custom PATH
                extern char **environ;
                NSMutableArray *envArray = [NSMutableArray array];
                for (char **env = environ; *env != NULL; env++) {
                    NSString *envStr = [NSString stringWithUTF8String:*env];
                    if (![envStr hasPrefix:@"PATH="]) {
                        [envArray addObject:envStr];
                    }
                }
                [envArray addObject:[NSString stringWithFormat:@"PATH=%@", fullPath]];

                // Convert to char**
                char **newEnviron = malloc(sizeof(char*) * (envArray.count + 1));
                for (NSUInteger i = 0; i < envArray.count; i++) {
                    newEnviron[i] = strdup([envArray[i] UTF8String]);
                }
                newEnviron[envArray.count] = NULL;

                // Execute with sh -c
                pid_t pid;
                char *args[] = {"/bin/sh", "-c", (char*)[shellCmd UTF8String], NULL};
                int spawn_result = rc_posix_spawn(&pid, "/bin/sh", NULL, NULL, args, newEnviron);

                int result = -1;
                if (spawn_result == 0) {
                    int status;
                    waitpid(pid, &status, 0);
                    if (WIFEXITED(status)) {
                        result = WEXITSTATUS(status);
                    }
                }

                // Cleanup
                for (NSUInteger i = 0; i < envArray.count; i++) {
                    free(newEnviron[i]);
                }
                free(newEnviron);

                SRLog(@"Shell command finished with exit code: %d", result);
            });
            return [NSString stringWithFormat:@"Executing: %@\n", shellCmd];
        }
    } else if ([cleanCmd hasPrefix:@"lua_eval "] || [cleanCmd hasPrefix:@"Lua "]) {
        NSString *code = [cleanCmd substringFromIndex:([cleanCmd hasPrefix:@"Lua "] ? 4 : 9)];
        return evaluate_lua_code(code);
    } else if ([cleanCmd hasPrefix:@"lua "]) {
        NSString *scriptPath = [[cleanCmd substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return execute_lua_script(scriptPath);

    // -- Touch gesture commands ------------------------------------------------
    // taptest show|hide|reset|status|run [system|app]
    } else if ([cleanCmd isEqualToString:@"taptest"] || [cleanCmd hasPrefix:@"taptest "]) {
        return rc_handle_taptest_command(cleanCmd);

    // taprecord
    } else if ([cleanCmd isEqualToString:@"taprecord"]) {
        rc_taprecord_start();
        return @"Tap recording started\n";

    // taprecordstatus
    } else if ([cleanCmd isEqualToString:@"taprecordstatus"]) {
        __block NSDictionary *resp = nil;
        rc_dispatch_sync_main_safe(^{
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            [dict setObject:@YES forKey:@"ok"];
            [dict setObject:g_tapRecordStatus forKey:@"status"];
            if ([g_tapRecordStatus isEqualToString:@"counting"]) {
                [dict setObject:@(g_tapRecordCountdown) forKey:@"seconds"];
            } else if ([g_tapRecordStatus isEqualToString:@"recorded"]) {
                [dict setObject:@(g_tapRecordPoint.x) forKey:@"x"];
                [dict setObject:@(g_tapRecordPoint.y) forKey:@"y"];
                g_tapRecordStatus = @"idle";
            }
            resp = [dict copy];
        });
        NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
        return [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];

    // tap x y
    } else if ([cleanCmd hasPrefix:@"tap "]) {
        NSArray<NSString *> *parts = rc_split_whitespace([cleanCmd substringFromIndex:4]);
        if (parts.count >= 2) {
            double px = [parts[0] doubleValue];
            double py = [parts[1] doubleValue];
            rc_load_touch_symbols();
            dispatch_async(rc_touch_queue(), ^{
                rc_simulate_tap(px, py);
            });
            return @"Tap sent via IOHIDEvent\n";
        }
        return @"Usage: tap x y\n";

    // hold x y [ms]
    } else if ([cleanCmd hasPrefix:@"hold "]) {
        NSArray *parts = [[cleanCmd substringFromIndex:5] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (parts.count >= 2) {
            double px = [parts[0] doubleValue];
            double py = [parts[1] doubleValue];
            int ms = (parts.count >= 3) ? (int)[parts[2] integerValue] : 500;
            rc_load_touch_symbols();
            dispatch_async(rc_touch_queue(), ^{ rc_simulate_hold(px, py, ms); });
            return @"Hold sent\n";
        }
        return @"Usage: hold x y [ms]\n";

    // swipe x1 y1 x2 y2
    } else if ([cleanCmd hasPrefix:@"swipe "] &&
               !([cleanCmd isEqualToString:@"swipeU"] || [cleanCmd isEqualToString:@"swipeD"] ||
                 [cleanCmd isEqualToString:@"swipeL"] || [cleanCmd isEqualToString:@"swipeR"])) {
        NSArray *parts = [[cleanCmd substringFromIndex:6] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (parts.count >= 4) {
            double x1 = [parts[0] doubleValue];
            double y1 = [parts[1] doubleValue];
            double x2 = [parts[2] doubleValue];
            double y2 = [parts[3] doubleValue];
            rc_load_touch_symbols();
            dispatch_async(rc_touch_queue(), ^{ rc_simulate_swipe(x1, y1, x2, y2); });
            return @"Swipe sent\n";
        }
        return @"Usage: swipe x1 y1 x2 y2\n";

    // swipeU / swipeUp
    } else if ([cleanCmd isEqualToString:@"swipeU"] || [cleanCmd isEqualToString:@"swipeUp"]) {
        rc_load_touch_symbols();
        dispatch_async(rc_touch_queue(), ^{
            __block CGSize s;
            dispatch_sync(dispatch_get_main_queue(), ^{ s = [UIScreen mainScreen].bounds.size; });
            rc_simulate_swipe(s.width*0.5, s.height*0.92, s.width*0.5, s.height*0.15);
        });
        return @"Swipe Up sent\n";

    // swipeD / swipeDown
    } else if ([cleanCmd isEqualToString:@"swipeD"] || [cleanCmd isEqualToString:@"swipeDown"]) {
        rc_load_touch_symbols();
        dispatch_async(rc_touch_queue(), ^{
            __block CGSize s;
            dispatch_sync(dispatch_get_main_queue(), ^{ s = [UIScreen mainScreen].bounds.size; });
            rc_simulate_swipe(s.width*0.5, s.height*0.08, s.width*0.5, s.height*0.85);
        });
        return @"Swipe Down sent\n";

    // swipeL / swipeLeft
    } else if ([cleanCmd isEqualToString:@"swipeL"] || [cleanCmd isEqualToString:@"swipeLeft"]) {
        rc_load_touch_symbols();
        dispatch_async(rc_touch_queue(), ^{
            __block CGSize s;
            dispatch_sync(dispatch_get_main_queue(), ^{ s = [UIScreen mainScreen].bounds.size; });
            rc_simulate_swipe(s.width*0.9, s.height*0.5, s.width*0.1, s.height*0.5);
        });
        return @"Swipe Left sent\n";

    // swipeR / swipeRight
    } else if ([cleanCmd isEqualToString:@"swipeR"] || [cleanCmd isEqualToString:@"swipeRight"]) {
        rc_load_touch_symbols();
        dispatch_async(rc_touch_queue(), ^{
            __block CGSize s;
            dispatch_sync(dispatch_get_main_queue(), ^{ s = [UIScreen mainScreen].bounds.size; });
            rc_simulate_swipe(s.width*0.1, s.height*0.5, s.width*0.9, s.height*0.5);
        });
        return @"Swipe Right sent\n";

    } else if ([cleanCmd isEqualToString:@"airplay list"]) {

        NSArray *names = RCFetchAirPlayDeviceNames();
        NSMutableString *output = [NSMutableString string];
        if (names.count == 0) {
            [output appendString:@"No AirPlay devices found.\n"];
        } else {
            for (NSString *name in names) {
                [output appendFormat:@"  %@\n", name];
            }
        }
        return output;

    } else if ([cleanCmd hasPrefix:@"airplay connect "]) {
        NSString *target = [[cleanCmd substringFromIndex:16] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // Strip outer quotes if present
        if ([target hasPrefix:@"\""] && [target hasSuffix:@"\""] && target.length >= 2) {
            target = [target substringWithRange:NSMakeRange(1, target.length - 2)];
        }
        
        // Strip name suffix if present: "UID # Name"
        if ([target containsString:@" # "]) {
            target = [target componentsSeparatedByString:@" # "].firstObject;
        }

        __block NSString *result = nil;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            MPAVRoutingController *ctrl = [[objc_getClass("MPAVRoutingController") alloc] init];
            ctrl.discoveryMode = 3; // Detailed discovery
            
            // Recursive block for retrying
            __block int attempts = 0;
            __block void (^attemptConnection)(void) = nil;
            
            attemptConnection = ^void(void) {
                [ctrl fetchAvailableRoutesWithCompletionHandler:^(NSArray<MPAVRoute *> *routes) {
                    MPAVRoute *foundRoute = nil;
                    for (MPAVRoute *route in routes) {
                        if ([route.routeUID isEqualToString:target] || [route.routeName localizedCaseInsensitiveContainsString:target]) {
                            foundRoute = route;
                            break;
                        }
                    }
                    
                    if (foundRoute) {
                        if ([ctrl pickRoute:foundRoute]) {
                            result = [NSString stringWithFormat:@"Connected to %@\n", foundRoute.routeName];
                        } else {
                            result = [NSString stringWithFormat:@"Failed to connect to %@\n", foundRoute.routeName];
                        }
                        dispatch_semaphore_signal(sema);
                        attemptConnection = nil; // Break retain cycle
                    } else {
                        attempts++;
                        if (attempts < 10) { // Try for 5 seconds (10 * 0.5s)
                            SRLog(@"AirPlay target '%@' not found yet, retrying (%d/10)...", target, attempts);
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                if (attemptConnection) attemptConnection(); // Retry
                            });
                        } else {
                            // Final failure
                            NSMutableString *debugList = [NSMutableString string];
                            for (MPAVRoute *r in routes) {
                                [debugList appendFormat:@"- %@ [%@]\n", r.routeName, r.routeUID];
                            }
                            result = [NSString stringWithFormat:@"Device '%@' not found after 5s. Available:\n%@", target, debugList];
                            dispatch_semaphore_signal(sema);
                            attemptConnection = nil; // Break retain cycle
                        }
                    }
                }];
            };
            
            // Start the first attempt
            attemptConnection();
        });
        
        // Wait up to 6 seconds (allowing for the 5s retry loop + buffer)
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC));
        return result ?: @"Error: Timeout connecting to AirPlay device\n";

    } else if ([cleanCmd hasPrefix:@"webui "]) {
        NSString *sub = [[cleanCmd substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        load_trigger_config();
        NSMutableDictionary *mConfig = [g_triggerConfig mutableCopy] ?: [NSMutableDictionary dictionary];
        
        if ([sub isEqualToString:@"on"] || [sub isEqualToString:@"enable"]) {
            mConfig[@"webUIEnabled"] = @YES;
            g_triggerConfig = [mConfig copy];
            save_trigger_config();
            return @"Web UI Enabled\n";
        } else if ([sub isEqualToString:@"off"] || [sub isEqualToString:@"disable"]) {
            mConfig[@"webUIEnabled"] = @NO;
            g_triggerConfig = [mConfig copy];
            save_trigger_config();
            return @"Web UI Disabled\n";
        } else if ([sub isEqualToString:@"status"]) {
            BOOL enabled = [mConfig[@"webUIEnabled"] boolValue];
            return [NSString stringWithFormat:@"Web UI is %@\n", enabled ? @"ENABLED" : @"DISABLED"];
        }
        return @"Usage: rc webui <on|off|status>\n";
    } else if ([cleanCmd isEqualToString:@"respring"]) {
        SRLog(@"Triggering Respring");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // 1. Try sbreload (Rootless / Dopamine / Procursus)
            NSString *sbreload = [NSString stringWithFormat:@"%@/usr/bin/sbreload", root_prefix()];
            if (![[NSFileManager defaultManager] fileExistsAtPath:sbreload]) {
                sbreload = @"/var/jb/usr/bin/sbreload";
            }
            if (![[NSFileManager defaultManager] fileExistsAtPath:sbreload]) {
                sbreload = @"/usr/bin/sbreload";
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:sbreload]) {
                pid_t pid;
                const char* sbreload_args[] = { [sbreload UTF8String], NULL };
                extern char **environ;
                int res = rc_posix_spawn(&pid, [sbreload UTF8String], NULL, NULL, (char* const*)sbreload_args, environ);
                if (res == 0) {
                    SRLog(@"Respring spawned sbreload pid=%d", pid);
                    return;
                }
            }
            
            // 2. Direct SpringBoard relaunch API
            Class sbClass = objc_getClass("SpringBoard");
            if (sbClass && [sbClass respondsToSelector:@selector(sharedApplication)]) {
                id sb = [sbClass performSelector:@selector(sharedApplication)];
                SEL relaunchSel = NSSelectorFromString(@"_relaunchSpringBoardNow");
                if ([sb respondsToSelector:relaunchSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [sb performSelector:relaunchSel];
#pragma clang diagnostic pop
                    return;
                }
            }
            
            // 3. FBSystemService exitAndRelaunch
            Class fbServiceClass = objc_getClass("FBSystemService");
            if (fbServiceClass && [fbServiceClass respondsToSelector:@selector(sharedInstance)]) {
                id fbService = [fbServiceClass performSelector:@selector(sharedInstance)];
                if ([fbService respondsToSelector:@selector(exitAndRelaunch:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [fbService performSelector:@selector(exitAndRelaunch:) withObject:@YES];
#pragma clang diagnostic pop
                    return;
                }
            }
            
            // 4. SpringBoard exit(0)
            exit(0);
        });
        return @"Device Respringing...\n";
    } else if ([cleanCmd isEqualToString:@"safemode"] || [cleanCmd isEqualToString:@"safe-mode"] || [cleanCmd isEqualToString:@"safe_mode"]) {
        SRLog(@"Triggering Safe Mode");
        dispatch_async(dispatch_get_main_queue(), ^{
            // 1. Create safe mode flag file markers (Substrate, ElleKit, Substitute)
            NSString *safemodePath1 = @"/var/mobile/Library/SafeMode/safemode";
            NSString *safemodePath2 = [NSString stringWithFormat:@"%@/var/mobile/Library/SafeMode/safemode", root_prefix()];
            NSString *safemodePath3 = @"/var/mobile/Library/SafariSafeMode";
            
            [[NSFileManager defaultManager] createDirectoryAtPath:[safemodePath1 stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            [[NSFileManager defaultManager] createDirectoryAtPath:[safemodePath2 stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            
            [[NSFileManager defaultManager] createFileAtPath:safemodePath1 contents:[NSData data] attributes:nil];
            [[NSFileManager defaultManager] createFileAtPath:safemodePath2 contents:[NSData data] attributes:nil];
            [[NSFileManager defaultManager] createFileAtPath:safemodePath3 contents:[NSData data] attributes:nil];
            
            // 2. Kill SpringBoard with SIGSEGV to trigger Safe Mode handler
            kill(getpid(), SIGSEGV);
            
            // Fallback
            abort();
        });
        return @"Device entering Safe Mode...\n";
    } else if ([cleanCmd isEqualToString:@"ldrestart"]) {
        SRLog(@"Triggering ldrestart");
        dispatch_async(dispatch_get_main_queue(), ^{
            pid_t pid;
            NSString *binPath = [NSString stringWithFormat:@"%@/usr/bin/ldrestart", root_prefix()];
            if (![[NSFileManager defaultManager] fileExistsAtPath:binPath]) binPath = @"/usr/bin/ldrestart";
            const char* args[] = { [binPath UTF8String], NULL };
            rc_posix_spawn(&pid, [binPath UTF8String], NULL, NULL, (char* const*)args, NULL);
        });
        return @"Triggering ldrestart...\n";
    } else if ([cleanCmd isEqualToString:@"uicache"]) {
        SRLog(@"Triggering uicache");
        dispatch_async(dispatch_get_main_queue(), ^{
            pid_t pid;
            NSString *binPath = [NSString stringWithFormat:@"%@/usr/bin/uicache", root_prefix()];
            if (![[NSFileManager defaultManager] fileExistsAtPath:binPath]) binPath = @"/usr/bin/uicache";
            const char* args[] = { [binPath UTF8String], "-a", NULL };
            rc_posix_spawn(&pid, [binPath UTF8String], NULL, NULL, (char* const*)args, NULL);
        });
        return @"Triggering uicache...\n";
    } else if ([cleanCmd isEqualToString:@"userspace-reboot"]) {
        SRLog(@"Triggering userspace-reboot");
        dispatch_async(dispatch_get_main_queue(), ^{
            pid_t pid;
            NSString *binPath = [NSString stringWithFormat:@"%@/bin/launchctl", root_prefix()];
            if (![[NSFileManager defaultManager] fileExistsAtPath:binPath]) binPath = @"/bin/launchctl";
            const char* args[] = { [binPath UTF8String], "reboot", "userspace", NULL };
            rc_posix_spawn(&pid, [binPath UTF8String], NULL, NULL, (char* const*)args, NULL);
        });
        return @"Triggering userspace-reboot...\n";
    } else if ([cleanCmd isEqualToString:@"list-triggers"]) {
        load_trigger_config();
        if (!g_triggerConfig) return @"Error: No trigger config found\n";
        id triggers = g_triggerConfig[@"triggers"];
        if (!triggers || ![triggers isKindOfClass:[NSDictionary class]]) return @"Error: No triggers configured\n";
        
        NSMutableString *list = [NSMutableString stringWithString:@"Configured Automations:\n"];
        NSArray *allKeys = [(NSDictionary *)triggers allKeys];
        for (NSString *key in [allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSDictionary *trigger = triggers[key];
            if ([trigger isKindOfClass:[NSDictionary class]]) {
                // Skip watch triggers as they are deprecated/non-functional
                if ([key hasPrefix:@"watch_"]) continue;
                
                NSString *title = get_human_name_for_trigger(key, trigger);
                [list appendFormat:@"- %@: %@\n", key, title];
            }
        }
        return list;
        } else if ([cleanCmd isEqualToString:@"sneakycam photo"] || [cleanCmd isEqualToString:@"sneakycam takephoto"]) {
        SRLog(@"[SneakyCam] Triggering Photo Notification...");
        notify_post("com.spark.SneakyCam.takephoto");
        notify_post("com.spark.sneakycam.takephoto");
        notify_post("com.spark.SneakyCam.takePhoto");
        FILE *p = popen("/var/jb/usr/bin/notifyutil -p com.spark.SneakyCam.takephoto 2>/dev/null || /usr/bin/notifyutil -p com.spark.SneakyCam.takephoto 2>/dev/null || notifyutil -p com.spark.SneakyCam.takephoto 2>/dev/null", "r");
        if (p) pclose(p);
        rc_show_hud_toast(@"SneakyCam", @"Photo Triggered", @"camera.fill");
        return @"SneakyCam: Photo trigger sent\n";
    } else if ([cleanCmd isEqualToString:@"sneakycam video"] || [cleanCmd isEqualToString:@"sneakycam record"] || [cleanCmd isEqualToString:@"sneakycam startstopvideo"]) {
        SRLog(@"[SneakyCam] Triggering Video Notification...");
        notify_post("com.spark.SneakyCam.startstopvideo");
        notify_post("com.spark.sneakycam.startstopvideo");
        notify_post("com.spark.SneakyCam.startStopVideo");
        FILE *p = popen("/var/jb/usr/bin/notifyutil -p com.spark.SneakyCam.startstopvideo 2>/dev/null || /usr/bin/notifyutil -p com.spark.SneakyCam.startstopvideo 2>/dev/null || notifyutil -p com.spark.SneakyCam.startStopVideo 2>/dev/null", "r");
        if (p) pclose(p);
        rc_show_hud_toast(@"SneakyCam", @"Video Toggled", @"video.fill");
        return @"SneakyCam: Video trigger sent\n";
    } else if ([cleanCmd hasPrefix:@"trigger:"]) {
        NSString *trigKey = [[cleanCmd substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        RCExecuteTrigger(trigKey);
        return [NSString stringWithFormat:@"Trigger '%@' executed\n", trigKey];
    } else if (g_triggerConfig && g_triggerConfig[@"triggers"] && g_triggerConfig[@"triggers"][cleanCmd]) {
        RCExecuteTrigger(cleanCmd);
        return [NSString stringWithFormat:@"Trigger '%@' executed\n", cleanCmd];
    } else if ([cleanCmd hasPrefix:@"trigger "]) {
        NSString *key = [[cleanCmd substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        dispatch_async(dispatch_get_main_queue(), ^{
            RCExecuteTrigger(key);
        });
        return [NSString stringWithFormat:@"Executing trigger: %@\n", key];
    }
    return nil;
}

static const char* rc_shell_path(void) {
    if (access("/var/jb/bin/sh", X_OK) == 0) return "/var/jb/bin/sh";
    if (access("/var/jb/usr/bin/sh", X_OK) == 0) return "/var/jb/usr/bin/sh";
    return "/bin/sh";
}

static char** rc_shell_env(void) {
    static char *custom_env[] = {
        (char *)"PATH=/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        NULL
    };
    return custom_env;
}

static void execute_shell_command(const char *cmd) {
    const char *sh = rc_shell_path();
    pid_t pid;
    char *argv[] = {(char *)sh, "-c", (char *)cmd, NULL};
    rc_posix_spawn(&pid, sh, NULL, NULL, argv, rc_shell_env());
}

static int rc_execute_command_status(const char *cmd) {
    const char *sh = rc_shell_path();
    pid_t pid;
    char *argv[] = {(char *)sh, "-c", (char *)cmd, NULL};
    if (rc_posix_spawn(&pid, sh, NULL, NULL, argv, rc_shell_env()) == 0) {
        int status = 0;
        waitpid(pid, &status, 0);
        if (WIFEXITED(status)) {
            return WEXITSTATUS(status);
        }
    }
    return -1;
}

static BOOL is_audiostreamerd_running(void) {
    // Fast path: check if port 18080 is actively listening on localhost
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s >= 0) {
        struct sockaddr_in sin;
        memset(&sin, 0, sizeof(sin));
        sin.sin_family = AF_INET;
        sin.sin_port = htons(18080);
        sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 100000; // 100ms timeout
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        
        int res = connect(s, (struct sockaddr *)&sin, sizeof(sin));
        close(s);
        if (res == 0) {
            return YES;
        }
    }
    
    // Process table fallback
    int ret = rc_execute_command_status("ps aux 2>/dev/null | grep -i '[a]udiostreamerd' | grep -v ' Z ' >/dev/null 2>&1");
    return (ret == 0);
}

static NSString* get_local_ip_address(void) {
    NSString *address = @"Unavailable";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"] || [name isEqualToString:@"pdp_ip0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    if ([name isEqualToString:@"en0"]) break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    if (interfaces) freeifaddrs(interfaces);
    return address;
}

static int g_actualWebPort = 8080;

static NSDictionary* get_system_diagnostics(void) {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float batteryLevelVal = [UIDevice currentDevice].batteryLevel;
    int batteryPercent = (batteryLevelVal >= 0) ? (int)(batteryLevelVal * 100.0f) : -1;
    
    UIDeviceBatteryState bState = [UIDevice currentDevice].batteryState;
    NSString *chargingStatus = @"Unknown";
    if (bState == UIDeviceBatteryStateCharging) chargingStatus = @"Charging";
    else if (bState == UIDeviceBatteryStateFull) chargingStatus = @"Fully Charged";
    else if (bState == UIDeviceBatteryStateUnplugged) chargingStatus = @"Unplugged";

    BOOL isLowPowerMode = [[NSProcessInfo processInfo] isLowPowerModeEnabled];

    // Storage info
    uint64_t freeBytes = 0;
    uint64_t totalBytes = 0;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:@"/var/mobile" error:nil];
    if (!attrs) attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:@"/" error:nil];
    if (attrs) {
        totalBytes = [attrs[NSFileSystemSize] unsignedLongLongValue];
        freeBytes = [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
    }
    double totalGB = (double)totalBytes / (1024.0 * 1024.0 * 1024.0);
    double freeGB = (double)freeBytes / (1024.0 * 1024.0 * 1024.0);
    double usedGB = (totalGB > freeGB) ? (totalGB - freeGB) : 0;
    int storagePercentUsed = (totalBytes > 0) ? (int)((usedGB / totalGB) * 100.0) : 0;

    // RAM / Memory info
    uint64_t totalRam = [[NSProcessInfo processInfo] physicalMemory];
    uint64_t freeRam = 0;
    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics64_data_t) / sizeof(integer_t);
    vm_size_t pagesize = 4096;
    host_page_size(host_port, &pagesize);
    vm_statistics64_data_t vm_stat;
    if (host_statistics64(host_port, HOST_VM_INFO64, (host_info64_t)&vm_stat, &host_size) == KERN_SUCCESS) {
        freeRam = (uint64_t)(vm_stat.free_count + vm_stat.inactive_count) * (uint64_t)pagesize;
    }
    double totalRamGB = (double)totalRam / (1024.0 * 1024.0 * 1024.0);
    double freeRamGB = (double)freeRam / (1024.0 * 1024.0 * 1024.0);
    double usedRamGB = (totalRamGB > freeRamGB) ? (totalRamGB - freeRamGB) : 0;
    int ramPercentUsed = (totalRam > 0) ? (int)((usedRamGB / totalRamGB) * 100.0) : 0;

    // System Uptime & Thermal
    NSTimeInterval uptimeSecs = [[NSProcessInfo processInfo] systemUptime];
    int days = (int)(uptimeSecs / 86400);
    int hours = (int)((uptimeSecs - (days * 86400)) / 3600);
    int mins = (int)((uptimeSecs - (days * 86400) - (hours * 3600)) / 60);
    NSString *uptimeStr = (days > 0) 
        ? [NSString stringWithFormat:@"%dd %dh %dm", days, hours, mins]
        : [NSString stringWithFormat:@"%dh %dm", hours, mins];

    NSProcessInfoThermalState thermal = [[NSProcessInfo processInfo] thermalState];
    NSString *thermalStr = @"Normal";
    if (thermal == NSProcessInfoThermalStateFair) thermalStr = @"Fair";
    else if (thermal == NSProcessInfoThermalStateSerious) thermalStr = @"Warm";
    else if (thermal == NSProcessInfoThermalStateCritical) thermalStr = @"Hot";

    // Jailbreak & Process Info
    BOOL isRootless = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
    NSString *jbMode = isRootless ? @"Rootless (/var/jb)" : @"Rootful";
    int pid = getpid();

    // Display Info
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat scale = [UIScreen mainScreen].scale;
    int resW = (int)(bounds.size.width * scale);
    int resH = (int)(bounds.size.height * scale);
    NSString *resolutionStr = [NSString stringWithFormat:@"%d × %d (@%dx)", resW, resH, (int)scale];

    float brightnessVal = [UIScreen mainScreen].brightness;
    int brightnessPercent = (int)(brightnessVal * 100.0f);

    BOOL isDarkMode = NO;
    if (@available(iOS 13.0, *)) {
        isDarkMode = ([UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark);
    }

    // Network & Hostname
    char hostnameBuf[256] = {0};
    gethostname(hostnameBuf, sizeof(hostnameBuf) - 1);
    NSString *hostnameStr = [NSString stringWithUTF8String:hostnameBuf] ?: @"iPhone";

    NSString *deviceName = [UIDevice currentDevice].name ?: @"iPhone";
    NSString *systemVersion = [UIDevice currentDevice].systemVersion ?: @"iOS";
    NSString *modelName = [UIDevice currentDevice].model ?: @"iPhone";
    NSString *ipAddress = get_local_ip_address();
    NSString *webUIUrl = (![ipAddress isEqualToString:@"Unavailable"]) 
        ? [NSString stringWithFormat:@"http://%@:%d", ipAddress, g_actualWebPort]
        : [NSString stringWithFormat:@"http://127.0.0.1:%d", g_actualWebPort];

    // Log File Info
    NSString *logPath = rc_get_log_file_path();
    uint64_t logSizeBytes = 0;
    NSDictionary *logAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:logPath error:nil];
    if (logAttrs) {
        logSizeBytes = [logAttrs fileSize];
    }
    NSString *logSizeFormatted = @"0 KB";
    if (logSizeBytes >= 1024 * 1024) {
        logSizeFormatted = [NSString stringWithFormat:@"%.2f MB", (double)logSizeBytes / (1024.0 * 1024.0)];
    } else if (logSizeBytes > 0) {
        logSizeFormatted = [NSString stringWithFormat:@"%.1f KB", (double)logSizeBytes / 1024.0];
    }

    return @{
        @"device_name": deviceName,
        @"system_version": systemVersion,
        @"model": modelName,
        @"battery_level": @(batteryPercent),
        @"battery_status": chargingStatus,
        @"low_power_mode": @(isLowPowerMode),
        @"storage_total_gb": [NSString stringWithFormat:@"%.1f GB", totalGB],
        @"storage_free_gb": [NSString stringWithFormat:@"%.1f GB", freeGB],
        @"storage_used_gb": [NSString stringWithFormat:@"%.1f GB", usedGB],
        @"storage_percent_used": @(storagePercentUsed),
        @"ram_total_gb": [NSString stringWithFormat:@"%.1f GB", totalRamGB],
        @"ram_free_gb": [NSString stringWithFormat:@"%.1f GB", freeRamGB],
        @"ram_used_gb": [NSString stringWithFormat:@"%.1f GB", usedRamGB],
        @"ram_percent_used": @(ramPercentUsed),
        @"uptime": uptimeStr,
        @"thermal_state": thermalStr,
        @"ip_address": ipAddress ?: @"Unavailable",
        @"hostname": hostnameStr,
        @"webui_url": webUIUrl,
        @"jb_mode": jbMode,
        @"pid": @(pid),
        @"resolution": resolutionStr,
        @"brightness": [NSString stringWithFormat:@"%d%%", brightnessPercent],
        @"dark_mode": @(isDarkMode),
        @"log_size": logSizeFormatted
    };
}

static void start_web_server() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int server_fd, new_socket;
        struct sockaddr_in6 address;
        int opt = 1;
        int off = 0;
        
        // Use AF_INET6 with IPV6_V6ONLY=0 for seamless dual-stack IPv6/IPv4 listening
        if ((server_fd = socket(AF_INET6, SOCK_STREAM, 0)) < 0) {
            // Fallback to IPv4 socket if IPv6 creation fails
            if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
                SRLog(@"[WebUI] socket failed");
                return;
            }
        } else {
            setsockopt(server_fd, IPPROTO_IPV6, IPV6_V6ONLY, &off, sizeof(off));
        }
        
        // Prevent socket file descriptor inheritance to child processes
        fcntl(server_fd, F_SETFD, FD_CLOEXEC);
        
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#ifdef SO_REUSEPORT
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
#endif
        
        int port = 8080;
        memset(&address, 0, sizeof(address));
        address.sin6_family = AF_INET6;
        address.sin6_addr = in6addr_any;
        
        // Strongly prefer default port 8080; retry briefly in case a previous respring is releasing it
        BOOL bound = NO;
        for (int retry = 0; retry < 5; retry++) {
            address.sin6_port = htons(8080);
            if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) >= 0) {
                bound = YES;
                port = 8080;
                break;
            }
            if (retry < 4) {
                usleep(200000); // 200ms wait between retries on port 8080
            }
        }
        
        // If 8080 is still taken by another service, scan sequential fallback ports
        if (!bound) {
            port = 8081;
            while (port < 8100) {
                address.sin6_port = htons(port);
                if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) >= 0) {
                    bound = YES;
                    break;
                }
                port++;
            }
        }
        
        if (!bound || port >= 8100) {
            SRLog(@"[WebUI] bind failed (ports 8080-8099 all taken)");
            close(server_fd);
            return;
        }
        
        g_actualWebPort = port;
        
        if (listen(server_fd, 5) < 0) {
            SRLog(@"[WebUI] listen failed");
            close(server_fd);
            return;
        }

        SRLog(@"[WebUI] Server listening on port %d", port);

        while (1) {
            struct sockaddr_storage client_addr;
            socklen_t client_addrlen = sizeof(client_addr);
            if ((new_socket = accept(server_fd, (struct sockaddr *)&client_addr, &client_addrlen)) < 0) {
                continue;
            }
            
            // Prevent inheritance to child processes and prevent SIGPIPE
            fcntl(new_socket, F_SETFD, FD_CLOEXEC);
            int nosigpipe = 1;
            setsockopt(new_socket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, sizeof(nosigpipe));
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                struct timeval tv;
                tv.tv_sec = 2;
                tv.tv_usec = 0;
                setsockopt(new_socket, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
                setsockopt(new_socket, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof tv);

                char buffer[16384] = {0};
                ssize_t valread = read(new_socket, buffer, 16384 - 1);
                if (valread > 0) {
                    NSString *requestString = [[NSString alloc] initWithBytes:buffer length:valread encoding:NSUTF8StringEncoding];
                    NSArray *lines = [requestString componentsSeparatedByString:@"\r\n"];
                    if (lines.count > 0) {
                        NSArray *requestLine = [lines[0] componentsSeparatedByString:@" "];
                        if (requestLine.count >= 2) {
                            NSString *method = requestLine[0];
                            NSString *path = requestLine[1];
                            
                            // CORS headers
                            NSString *cors = @"Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n";
                            NSString *responseString = [NSString stringWithFormat:@"HTTP/1.1 404 Not Found\r\n%@Content-Length: 9\r\n\r\nNot Found", cors];
                            
                            if ([method isEqualToString:@"OPTIONS"]) {
                                responseString = [NSString stringWithFormat:@"HTTP/1.1 204 No Content\r\n%@Content-Length: 0\r\n\r\n", cors];
                            } else if ([path isEqualToString:@"/"]) {
                                load_trigger_config();
                                if (![g_triggerConfig[@"webUIEnabled"] boolValue]) {
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 403 Forbidden\r\n%@Content-Length: 17\r\n\r\nWeb UI is disabled", cors];
                                } else {
                                    NSString *htmlPath = [NSString stringWithFormat:@"%@/Library/Application Support/RemoteCompanion/rc_webui.html", root_prefix()];
                                    NSString *html = [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:nil];
                                    if (!html) {
                                        NSString *rootlessPath = @"/var/jb/Library/Application Support/RemoteCompanion/rc_webui.html";
                                        html = [NSString stringWithContentsOfFile:rootlessPath encoding:NSUTF8StringEncoding error:nil];
                                    }
                                    if (!html) {
                                        html = [NSString stringWithContentsOfFile:@"/Library/Application Support/RemoteCompanion/rc_webui.html" encoding:NSUTF8StringEncoding error:nil];
                                    }
                                    if (!html) {
                                        html = @"<html><body><h1>RemoteCompanion WebUI</h1><p>rc_webui.html not found. Please reinstall the tweak.</p></body></html>";
                                    }
                                    NSData *htmlData = [html dataUsingEncoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: text/html\r\nCache-Control: no-cache, no-store, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)htmlData.length, html];
                                }
                            } else if ([path isEqualToString:@"/favicon.ico"] || [path isEqualToString:@"/apple-touch-icon.png"] || [path hasPrefix:@"/favicon-"] || [path hasPrefix:@"/android-chrome-"] || [path isEqualToString:@"/site.webmanifest"]) {
                                NSString *filename = [path lastPathComponent];
                                NSString *assetPath = [NSString stringWithFormat:@"%@/Library/Application Support/RemoteCompanion/%@", root_prefix(), filename];
                                NSData *assetData = [NSData dataWithContentsOfFile:assetPath];
                                if (!assetData) {
                                    assetPath = [NSString stringWithFormat:@"/var/jb/Library/Application Support/RemoteCompanion/%@", filename];
                                    assetData = [NSData dataWithContentsOfFile:assetPath];
                                }
                                if (!assetData) {
                                    assetPath = [NSString stringWithFormat:@"/Library/Application Support/RemoteCompanion/%@", filename];
                                    assetData = [NSData dataWithContentsOfFile:assetPath];
                                }
                                
                                if (assetData) {
                                    NSString *contentType = @"application/octet-stream";
                                    if ([path hasSuffix:@".ico"]) contentType = @"image/x-icon";
                                    else if ([path hasSuffix:@".png"]) contentType = @"image/png";
                                    else if ([path hasSuffix:@".webmanifest"] || [path hasSuffix:@".json"]) contentType = @"application/manifest+json";
                                    
                                    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: %@\r\nContent-Length: %lu\r\n\r\n", cors, contentType, (unsigned long)assetData.length];
                                    write(new_socket, [header UTF8String], [header lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
                                    write(new_socket, [assetData bytes], [assetData length]);
                                    responseString = nil; // Skip default write
                                }
                            } else if ([path isEqualToString:@"/api/config"]) {
                                load_trigger_config();
                                // Allow GET/POST for config regardless of webUIEnabled to prevent lockout
                                if ([method isEqualToString:@"GET"]) {
                                        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:g_triggerConfig options:0 error:nil];
                                        if (jsonData) {
                                            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                            responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)jsonData.length, jsonString];
                                        }
                                    } else if ([method isEqualToString:@"POST"]) {
                                        NSRange clRange = [requestString rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
                                        int contentLength = 0;
                                        if (clRange.location != NSNotFound) {
                                            NSString *afterCl = [requestString substringFromIndex:clRange.location + clRange.length];
                                            contentLength = [afterCl intValue];
                                        }

                                        const char *headersEnd = strnstr(buffer, "\r\n\r\n", valread);
                                        if (headersEnd != NULL) {
                                            size_t headerBytesOffset = (headersEnd - buffer) + 4;
                                            size_t availableBodyLength = valread - headerBytesOffset;
                                            
                                            NSMutableData *bodyData = [NSMutableData data];
                                            if (availableBodyLength > 0) {
                                                [bodyData appendBytes:(buffer + headerBytesOffset) length:availableBodyLength];
                                            }
                                            
                                            // Ensure we read the complete body based on Content-Length
                                            while (bodyData.length < contentLength) {
                                                char chunk[4096];
                                                ssize_t chunkRead = read(new_socket, chunk, sizeof(chunk));
                                                if (chunkRead <= 0) break;
                                                [bodyData appendBytes:chunk length:chunkRead];
                                            }

                                            NSError *err;
                                            id jsonObj = [NSJSONSerialization JSONObjectWithData:bodyData options:NSJSONReadingMutableContainers error:&err];
                                            if (jsonObj && [jsonObj isKindOfClass:[NSDictionary class]]) {
                                                g_triggerConfig = [jsonObj mutableCopy];
                                                save_trigger_config();
                                                responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: 12\r\n\r\n{\"ok\": true}", cors];
                                            } else {
                                                responseString = [NSString stringWithFormat:@"HTTP/1.1 400 Bad Request\r\n%@Content-Type: application/json\r\nContent-Length: 17\r\n\r\n{\"error\":\"JSON\"}", cors];
                                            }
                                        }
                                    }
                                } else if ([path isEqualToString:@"/api/logs"] && [method isEqualToString:@"GET"]) {
                                    NSString *logPath = rc_get_log_file_path();
                                    NSString *logContent = @"";
                                    if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
                                        NSError *err = nil;
                                        NSString *fullLog = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:&err];
                                        if (fullLog) {
                                            NSArray<NSString *> *lines = [fullLog componentsSeparatedByString:@"\n"];
                                            NSUInteger count = lines.count;
                                            NSUInteger startIdx = (count > 150) ? (count - 150) : 0;
                                            NSArray<NSString *> *recentLines = [lines subarrayWithRange:NSMakeRange(startIdx, count - startIdx)];
                                            logContent = [recentLines componentsJoinedByString:@"\n"];
                                        }
                                    }
                                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"logs": logContent ?: @""} options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                } else if ([path isEqualToString:@"/api/capabilities"] && [method isEqualToString:@"GET"]) {
                                    NSDictionary *caps = @{
                                        @"sneakycam": @(is_sneakycam_installed()),
                                        @"snapper": @(is_snapper_installed()),
                                        @"audiostream": @(is_audiostream_installed()),
                                        @"audiostream_running": @(is_audiostreamerd_running())
                                    };
                                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:caps options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                } else if ([path isEqualToString:@"/api/audiostream/status"] && [method isEqualToString:@"GET"]) {
                                    BOOL running = is_audiostreamerd_running();
                                    NSDictionary *dict = @{@"running": @(running), @"port": @(18080)};
                                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                } else if ([path isEqualToString:@"/api/audiostream/start"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                    BOOL alreadyRunning = is_audiostreamerd_running();
                                    if (alreadyRunning) {
                                        NSDictionary *dict = @{@"status": @"already_running", @"port": @(18080)};
                                        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
                                        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                        responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                    } else {
                                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                            execute_shell_command("if [ -x /var/jb/usr/bin/audiostream ]; then /var/jb/usr/bin/audiostream start --auto-off; elif [ -x /usr/bin/audiostream ]; then /usr/bin/audiostream start --auto-off; else audiostream start --auto-off; fi");
                                        });
                                        NSDictionary *dict = @{@"status": @"started", @"port": @(18080)};
                                        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
                                        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                        responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                    }
                                } else if ([path isEqualToString:@"/api/audiostream/stop"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                        execute_shell_command("if [ -x /var/jb/usr/bin/audiostream ]; then /var/jb/usr/bin/audiostream stop; elif [ -x /usr/bin/audiostream ]; then /usr/bin/audiostream stop; else audiostream stop; fi");
                                    });
                                    NSDictionary *dict = @{@"status": @"stopped", @"port": @(18080)};
                                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                } else if ([path isEqualToString:@"/api/sysinfo"] && [method isEqualToString:@"GET"]) {
                                    NSDictionary *sysInfo = get_system_diagnostics();
                                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:sysInfo options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                } else if ([path isEqualToString:@"/api/sysaction/uicache"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                        execute_shell_command("uicache -a 2>/dev/null || /var/jb/usr/bin/uicache -a 2>/dev/null");
                                    });
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: 12\r\n\r\n{\"ok\": true}", cors];
                                } else if ([path isEqualToString:@"/api/sysaction/flushdns"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                        execute_shell_command("killall -HUP mDNSResponder 2>/dev/null");
                                    });
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: 12\r\n\r\n{\"ok\": true}", cors];
                                } else if ([path isEqualToString:@"/api/sysaction/clearlog"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                    NSString *logPath = rc_get_log_file_path();
                                    [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: 12\r\n\r\n{\"ok\": true}", cors];
                                } else if ([path isEqualToString:@"/api/sysaction/safemode"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        handle_command(@"safemode");
                                    });
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: 12\r\n\r\n{\"ok\": true}", cors];
                                } else if ([path isEqualToString:@"/api/ha/test"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                    load_trigger_config();
                                    NSString *overrideUrl = nil;
                                    NSString *overrideToken = nil;
                                    if ([method isEqualToString:@"POST"]) {
                                        NSRange clRange = [requestString rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
                                        int contentLength = 0;
                                        if (clRange.location != NSNotFound) {
                                            NSString *afterCl = [requestString substringFromIndex:clRange.location + clRange.length];
                                            contentLength = [afterCl intValue];
                                        }
                                        const char *headersEnd = strnstr(buffer, "\r\n\r\n", valread);
                                        if (headersEnd != NULL) {
                                            size_t headerBytesOffset = (headersEnd - buffer) + 4;
                                            size_t availableBodyLength = valread - headerBytesOffset;
                                            NSMutableData *bodyData = [NSMutableData data];
                                            if (availableBodyLength > 0) [bodyData appendBytes:(buffer + headerBytesOffset) length:availableBodyLength];
                                            while (bodyData.length < contentLength) {
                                                char chunk[4096];
                                                ssize_t chunkRead = read(new_socket, chunk, sizeof(chunk));
                                                if (chunkRead <= 0) break;
                                                [bodyData appendBytes:chunk length:chunkRead];
                                            }
                                            NSDictionary *jsonObj = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
                                            if ([jsonObj isKindOfClass:[NSDictionary class]]) {
                                                overrideUrl = jsonObj[@"haUrl"];
                                                overrideToken = jsonObj[@"haToken"];
                                            }
                                        }
                                    }
                                    NSDictionary *res = rc_execute_ha_request(@"/api/", @"GET", nil, overrideUrl, overrideToken);
                                    NSMutableDictionary *resp = [NSMutableDictionary dictionary];
                                    if ([res[@"ok"] boolValue]) {
                                        resp[@"ok"] = @YES;
                                        id dataObj = res[@"data"];
                                        if ([dataObj isKindOfClass:[NSDictionary class]] && dataObj[@"version"]) {
                                            resp[@"version"] = dataObj[@"version"];
                                        }
                                    } else {
                                        resp[@"ok"] = @NO;
                                        resp[@"error"] = res[@"error"] ?: @"Connection failed";
                                    }
                                    NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                } else if ([path isEqualToString:@"/api/ha/states"] && [method isEqualToString:@"GET"]) {
                                    load_trigger_config();
                                    NSDictionary *res = rc_execute_ha_request(@"/api/states", @"GET", nil, nil, nil);
                                    NSMutableDictionary *resp = [NSMutableDictionary dictionary];
                                    if ([res[@"ok"] boolValue]) {
                                        resp[@"ok"] = @YES;
                                        resp[@"states"] = res[@"data"] ?: @[];
                                    } else {
                                        resp[@"ok"] = @NO;
                                        resp[@"error"] = res[@"error"] ?: @"Failed to fetch states";
                                    }
                                    NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                } else if ([path isEqualToString:@"/api/ha/services"] && [method isEqualToString:@"GET"]) {
                                    load_trigger_config();
                                    NSDictionary *res = rc_execute_ha_request(@"/api/services", @"GET", nil, nil, nil);
                                    NSMutableDictionary *resp = [NSMutableDictionary dictionary];
                                    if ([res[@"ok"] boolValue]) {
                                        resp[@"ok"] = @YES;
                                        resp[@"services"] = res[@"data"] ?: @[];
                                    } else {
                                        resp[@"ok"] = @NO;
                                        resp[@"error"] = res[@"error"] ?: @"Failed to fetch services";
                                    }
                                    NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                } else if ([path isEqualToString:@"/api/km/test"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                     load_trigger_config();
                                     NSString *overrideUrl = nil;
                                     NSString *overrideUser = nil;
                                     NSString *overridePass = nil;
                                     if ([method isEqualToString:@"POST"]) {
                                         NSRange clRange = [requestString rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
                                         int contentLength = 0;
                                         if (clRange.location != NSNotFound) {
                                             NSString *afterCl = [requestString substringFromIndex:clRange.location + clRange.length];
                                             contentLength = [afterCl intValue];
                                         }
                                         const char *headersEnd = strnstr(buffer, "\r\n\r\n", valread);
                                         if (headersEnd != NULL) {
                                             size_t headerBytesOffset = (headersEnd - buffer) + 4;
                                             size_t availableBodyLength = valread - headerBytesOffset;
                                             NSMutableData *bodyData = [NSMutableData data];
                                             if (availableBodyLength > 0) [bodyData appendBytes:(buffer + headerBytesOffset) length:availableBodyLength];
                                             while (bodyData.length < contentLength) {
                                                 char chunk[4096];
                                                 ssize_t chunkRead = read(new_socket, chunk, sizeof(chunk));
                                                 if (chunkRead <= 0) break;
                                                 [bodyData appendBytes:chunk length:chunkRead];
                                             }
                                             NSDictionary *jsonObj = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
                                             if ([jsonObj isKindOfClass:[NSDictionary class]]) {
                                                 overrideUrl = jsonObj[@"kmUrl"];
                                                 overrideUser = jsonObj[@"kmUser"];
                                                 overridePass = jsonObj[@"kmPassword"];
                                             }
                                         }
                                     }
                                     NSDictionary *res = rc_execute_km_request(nil, @"GET", nil, overrideUrl, overrideUser, overridePass);
                                     NSMutableDictionary *resp = [NSMutableDictionary dictionary];
                                     if ([res[@"ok"] boolValue]) {
                                         resp[@"ok"] = @YES;
                                         resp[@"message"] = @"Connected to Keyboard Maestro Web Server";
                                     } else {
                                         resp[@"ok"] = @NO;
                                         resp[@"error"] = res[@"error"] ?: @"Connection failed";
                                     }
                                     NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                     NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                     responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                 } else if ([path isEqualToString:@"/api/mqtt/test"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                       load_trigger_config();
                                       NSString *overrideHost = nil;
                                       NSInteger overridePort = 0;
                                       NSString *overrideUser = nil;
                                       NSString *overridePass = nil;
                                       NSString *overrideClientId = nil;
                                       if ([method isEqualToString:@"POST"]) {
                                           NSRange clRange = [requestString rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
                                           int contentLength = 0;
                                           if (clRange.location != NSNotFound) {
                                               NSString *afterCl = [requestString substringFromIndex:clRange.location + clRange.length];
                                               contentLength = [afterCl intValue];
                                           }
                                           const char *headersEnd = strnstr(buffer, "\r\n\r\n", valread);
                                           if (headersEnd != NULL) {
                                               size_t headerBytesOffset = (headersEnd - buffer) + 4;
                                               size_t availableBodyLength = valread - headerBytesOffset;
                                               NSMutableData *bodyData = [NSMutableData data];
                                               if (availableBodyLength > 0) [bodyData appendBytes:(buffer + headerBytesOffset) length:availableBodyLength];
                                               while (bodyData.length < contentLength) {
                                                   char chunk[4096];
                                                   ssize_t chunkRead = read(new_socket, chunk, sizeof(chunk));
                                                   if (chunkRead <= 0) break;
                                                   [bodyData appendBytes:chunk length:chunkRead];
                                               }
                                               NSDictionary *jsonObj = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
                                               if ([jsonObj isKindOfClass:[NSDictionary class]]) {
                                                   overrideHost = jsonObj[@"mqttHost"];
                                                   if (jsonObj[@"mqttPort"]) overridePort = [jsonObj[@"mqttPort"] integerValue];
                                                   overrideUser = jsonObj[@"mqttUser"];
                                                   overridePass = jsonObj[@"mqttPassword"];
                                                   overrideClientId = jsonObj[@"mqttClientId"];
                                               }
                                           }
                                       }
                                       NSString *host = overrideHost.length > 0 ? overrideHost : (g_triggerConfig[@"mqttHost"] ?: @"192.168.1.50");
                                       NSInteger port = overridePort > 0 ? overridePort : ([g_triggerConfig[@"mqttPort"] integerValue] > 0 ? [g_triggerConfig[@"mqttPort"] integerValue] : 1883);
                                       NSString *user = overrideUser != nil ? overrideUser : g_triggerConfig[@"mqttUser"];
                                       NSString *pass = overridePass != nil ? overridePass : g_triggerConfig[@"mqttPassword"];
                                       NSString *clientId = overrideClientId.length > 0 ? overrideClientId : (g_triggerConfig[@"mqttClientId"] ?: @"RemoteCompanion");
                                       
                                       NSError *err = nil;
                                       BOOL ok = rc_mqtt_publish(host, port, user, pass, clientId, nil, nil, 0, NO, &err);
                                       NSMutableDictionary *resp = [NSMutableDictionary dictionary];
                                       if (ok) {
                                           resp[@"ok"] = @YES;
                                           resp[@"message"] = [NSString stringWithFormat:@"Connected to MQTT broker (%@:%ld)", host, (long)port];
                                       } else {
                                           resp[@"ok"] = @NO;
                                           resp[@"error"] = err.localizedDescription ?: @"Connection failed";
                                       }
                                       NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                       NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                       responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                   } else if ([path isEqualToString:@"/api/mqtt/publish"] && [method isEqualToString:@"POST"]) {
                                       load_trigger_config();
                                       NSRange clRange = [requestString rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
                                       int contentLength = 0;
                                       if (clRange.location != NSNotFound) {
                                           NSString *afterCl = [requestString substringFromIndex:clRange.location + clRange.length];
                                           contentLength = [afterCl intValue];
                                       }
                                       const char *headersEnd = strnstr(buffer, "\r\n\r\n", valread);
                                       NSString *topic = nil;
                                       NSString *payload = nil;
                                       if (headersEnd != NULL) {
                                           size_t headerBytesOffset = (headersEnd - buffer) + 4;
                                           size_t availableBodyLength = valread - headerBytesOffset;
                                           NSMutableData *bodyData = [NSMutableData data];
                                           if (availableBodyLength > 0) [bodyData appendBytes:(buffer + headerBytesOffset) length:availableBodyLength];
                                           while (bodyData.length < contentLength) {
                                               char chunk[4096];
                                               ssize_t chunkRead = read(new_socket, chunk, sizeof(chunk));
                                               if (chunkRead <= 0) break;
                                               [bodyData appendBytes:chunk length:chunkRead];
                                           }
                                           NSDictionary *jsonObj = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
                                           if ([jsonObj isKindOfClass:[NSDictionary class]]) {
                                               topic = jsonObj[@"topic"];
                                               payload = jsonObj[@"payload"];
                                           }
                                       }
                                       NSMutableDictionary *resp = [NSMutableDictionary dictionary];
                                       if (topic.length > 0) {
                                           NSString *cmdStr = payload.length > 0 ? [NSString stringWithFormat:@"publish %@ %@", topic, payload] : [NSString stringWithFormat:@"publish %@", topic];
                                           NSString *mqttRes = rc_execute_mqtt_command(cmdStr);
                                           resp[@"ok"] = [mqttRes containsString:@"Error:"] || [mqttRes containsString:@"failed:"] ? @NO : @YES;
                                           resp[@"output"] = mqttRes;
                                       } else {
                                           resp[@"ok"] = @NO;
                                           resp[@"error"] = @"Missing topic parameter";
                                       }
                                       NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                       NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                       responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                 } else if ([path isEqualToString:@"/api/km/trigger"] && [method isEqualToString:@"POST"]) {
                                     load_trigger_config();
                                     int contentLength = 0;
                                     NSRange clRange = [requestString rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
                                     if (clRange.location != NSNotFound) {
                                         NSString *afterCl = [requestString substringFromIndex:clRange.location + clRange.length];
                                         contentLength = [afterCl intValue];
                                     }
                                     const char *headersEnd = strnstr(buffer, "\r\n\r\n", valread);
                                     NSString *macro = nil;
                                     NSString *value = nil;
                                     NSString *fullUrl = nil;
                                     if (headersEnd != NULL) {
                                         size_t headerBytesOffset = (headersEnd - buffer) + 4;
                                         size_t availableBodyLength = valread - headerBytesOffset;
                                         NSMutableData *bodyData = [NSMutableData data];
                                         if (availableBodyLength > 0) [bodyData appendBytes:(buffer + headerBytesOffset) length:availableBodyLength];
                                         while (bodyData.length < contentLength) {
                                             char chunk[4096];
                                             ssize_t chunkRead = read(new_socket, chunk, sizeof(chunk));
                                             if (chunkRead <= 0) break;
                                             [bodyData appendBytes:chunk length:chunkRead];
                                         }
                                         NSDictionary *jsonObj = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
                                         if ([jsonObj isKindOfClass:[NSDictionary class]]) {
                                             macro = jsonObj[@"macro"];
                                             value = jsonObj[@"value"];
                                             fullUrl = jsonObj[@"url"];
                                         }
                                     }
                                     NSMutableDictionary *resp = [NSMutableDictionary dictionary];
                                     if (fullUrl.length > 0) {
                                         NSString *kmRes = rc_execute_km_command([NSString stringWithFormat:@"url %@", fullUrl]);
                                         resp[@"ok"] = [kmRes containsString:@"Error:"] ? @NO : @YES;
                                         resp[@"output"] = kmRes;
                                     } else if (macro.length > 0) {
                                         NSString *cmdStr = value.length > 0 ? [NSString stringWithFormat:@"trigger %@ %@", macro, value] : [NSString stringWithFormat:@"trigger %@", macro];
                                         NSString *kmRes = rc_execute_km_command(cmdStr);
                                         resp[@"ok"] = [kmRes containsString:@"Error:"] ? @NO : @YES;
                                         resp[@"output"] = kmRes;
                                     } else {
                                         resp[@"ok"] = @NO;
                                         resp[@"error"] = @"Missing macro parameter";
                                     }
                                     NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                     NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                     responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                  } else if ([path isEqualToString:@"/api/km/macros"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                      load_trigger_config();
                                      NSString *overrideUrl = nil;
                                      NSString *overrideUser = nil;
                                      NSString *overridePass = nil;
                                      if ([method isEqualToString:@"POST"]) {
                                          NSRange clRange = [requestString rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
                                          int contentLength = 0;
                                          if (clRange.location != NSNotFound) {
                                              NSString *afterCl = [requestString substringFromIndex:clRange.location + clRange.length];
                                              contentLength = [afterCl intValue];
                                          }
                                          const char *headersEnd = strnstr(buffer, "\r\n\r\n", valread);
                                          if (headersEnd != NULL) {
                                              size_t headerBytesOffset = (headersEnd - buffer) + 4;
                                              size_t availableBodyLength = valread - headerBytesOffset;
                                              NSMutableData *bodyData = [NSMutableData data];
                                              if (availableBodyLength > 0) [bodyData appendBytes:(buffer + headerBytesOffset) length:availableBodyLength];
                                              while (bodyData.length < contentLength) {
                                                  char chunk[4096];
                                                  ssize_t chunkRead = read(new_socket, chunk, sizeof(chunk));
                                                  if (chunkRead <= 0) break;
                                                  [bodyData appendBytes:chunk length:chunkRead];
                                              }
                                              NSDictionary *jsonObj = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
                                              if ([jsonObj isKindOfClass:[NSDictionary class]]) {
                                                  overrideUrl = jsonObj[@"kmUrl"];
                                                  overrideUser = jsonObj[@"kmUser"];
                                                  overridePass = jsonObj[@"kmPassword"];
                                              }
                                          }
                                      }
                                      
                                      NSDictionary *res = rc_execute_km_request(@"authenticated.html", @"GET", nil, overrideUrl, overrideUser, overridePass);
                                      if (![res[@"ok"] boolValue]) {
                                          // Fallback to / if authenticated.html was not accessible
                                          NSDictionary *fallbackRes = rc_execute_km_request(@"/", @"GET", nil, overrideUrl, overrideUser, overridePass);
                                          if ([fallbackRes[@"ok"] boolValue] && [fallbackRes[@"data"] length] > 0) {
                                              res = fallbackRes;
                                          }
                                      }
                                      
                                      NSMutableDictionary *resp = [NSMutableDictionary dictionary];
                                      if ([res[@"ok"] boolValue] && [res[@"data"] isKindOfClass:[NSString class]]) {
                                          NSArray *groups = rc_parse_km_html(res[@"data"]);
                                          resp[@"ok"] = @YES;
                                          resp[@"groups"] = groups ?: @[];
                                      } else {
                                          resp[@"ok"] = @NO;
                                          resp[@"error"] = res[@"error"] ?: @"Could not connect to Keyboard Maestro Web Server";
                                          resp[@"groups"] = @[];
                                      }
                                      
                                      NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                      NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                      responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
    } else if ([path isEqualToString:@"/api/version"] && [method isEqualToString:@"GET"]) {
                                NSString *plistPath = [NSString stringWithFormat:@"%@/Applications/RemoteCompanion.app/Info.plist", root_prefix()];
                                NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                                NSString *version = plist[@"CFBundleShortVersionString"] ?: @"3.3.0";
                                NSDictionary *resp = @{@"ok": @YES, @"version": version};
                                NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                            } else if ([path isEqualToString:@"/api/triggers"] && [method isEqualToString:@"GET"]) {
                                load_trigger_config();
                                if (![g_triggerConfig[@"webUIEnabled"] boolValue]) {
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 403 Forbidden\r\n%@Content-Length: 17\r\n\r\nWeb UI is disabled", cors];
                                } else {
                                    id triggers = g_triggerConfig[@"triggers"];
                                    NSMutableArray *triggerList = [NSMutableArray array];
                                    if (triggers && [triggers isKindOfClass:[NSDictionary class]]) {
                                        NSArray *allKeys = [(NSDictionary *)triggers allKeys];
                                        for (NSString *key in [allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                                            NSDictionary *trigger = triggers[key];
                                            if ([trigger isKindOfClass:[NSDictionary class]]) {
                                                if ([key hasPrefix:@"watch_"]) continue;
                                                NSString *title = get_human_name_for_trigger(key, trigger);
                                                NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
                                                [triggerList addObject:@{
                                                    @"id": key,
                                                    @"name": title,
                                                    @"url": [NSString stringWithFormat:@"/api/trigger/%@", encodedKey]
                                                }];
                                            }
                                        }
                                    }
                                    NSDictionary *resp = @{@"ok": @YES, @"triggers": triggerList};
                                    NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:NSJSONWritingPrettyPrinted error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                    // Remove backslash escaping for forward slashes
                                    jsonStr = [jsonStr stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                }
                            } else if ([path isEqualToString:@"/api/taprecordstatus"] && ([method isEqualToString:@"GET"] || [method isEqualToString:@"POST"])) {
                                load_trigger_config();
                                if (![g_triggerConfig[@"webUIEnabled"] boolValue]) {
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 403 Forbidden\r\n%@Content-Length: 17\r\n\r\nWeb UI is disabled", cors];
                                } else {
                                    __block NSDictionary *resp = nil;
                                    rc_dispatch_sync_main_safe(^{
                                        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
                                        [dict setObject:@YES forKey:@"ok"];
                                        [dict setObject:g_tapRecordStatus forKey:@"status"];
                                        if ([g_tapRecordStatus isEqualToString:@"counting"]) {
                                            [dict setObject:@(g_tapRecordCountdown) forKey:@"seconds"];
                                        } else if ([g_tapRecordStatus isEqualToString:@"recorded"]) {
                                            [dict setObject:@(g_tapRecordPoint.x) forKey:@"x"];
                                            [dict setObject:@(g_tapRecordPoint.y) forKey:@"y"];
                                            g_tapRecordStatus = @"idle";
                                        }
                                        resp = [dict copy];
                                    });
                                    
                                    NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                }
                            } else if ([path isEqualToString:@"/api/devices"] && [method isEqualToString:@"GET"]) {
                                load_trigger_config();
                                if (![g_triggerConfig[@"webUIEnabled"] boolValue]) {
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 403 Forbidden\r\n%@Content-Length: 17\r\n\r\nWeb UI is disabled", cors];
                                } else {
                                    NSMutableArray *btNames = [NSMutableArray array];
                                    void *btHandle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
                                    if (btHandle) {
                                        Class BluetoothManagerClass = objc_getClass("BluetoothManager");
                                        if (BluetoothManagerClass) {
                                            BluetoothManager *btManager = [BluetoothManagerClass sharedInstance];
                                            NSArray *devices = [btManager pairedDevices];
                                            for (id device in devices) {
                                                if ([device respondsToSelector:@selector(name)]) {
                                                    NSString *name = [device name];
                                                    if (name && name.length > 0) {
                                                        [btNames addObject:name];
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    NSMutableArray *wifiNames = [NSMutableArray array];
                                    SBWiFiManager *manager = [objc_getClass("SBWiFiManager") sharedInstance];
                                    if ([manager respondsToSelector:@selector(currentNetworkName)]) {
                                        NSString *ssid = [manager currentNetworkName];
                                        if (ssid && ssid.length > 0) {
                                            [wifiNames addObject:ssid];
                                        }
                                    }

                                    void *lsHandle = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_NOW);
                                    if (!lsHandle) {
                                        lsHandle = dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
                                    }

                                    NSMutableArray *appList = [NSMutableArray array];
                                    Class LSApplicationWorkspaceClass = objc_getClass("LSApplicationWorkspace");
                                    if (LSApplicationWorkspaceClass) {
                                        NSArray *apps = [[LSApplicationWorkspaceClass defaultWorkspace] allInstalledApplications];
                                        SRLog(@"API: Found %lu installed applications", (unsigned long)apps.count);
                                        for (LSApplicationProxy *proxy in apps) {
                                            NSString *name = nil;
                                            if ([proxy respondsToSelector:@selector(localizedName)]) {
                                                name = [proxy localizedName];
                                            }
                                            NSString *bid = nil;
                                            if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
                                                bid = [proxy applicationIdentifier];
                                            }
                                            
                                            if (name && bid) {
                                                [appList addObject:@{@"name": name, @"bundleId": bid}];
                                            }
                                        }
                                    } else {
                                        SRLog(@"API: LSApplicationWorkspace class NOT FOUND after dlopen");
                                    }

                                    // Sort by name
                                    [appList sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                                        return [obj1[@"name"] localizedCaseInsensitiveCompare:obj2[@"name"]];
                                    }];
                                    SRLog(@"API: returning %lu apps in device list", (unsigned long)appList.count);
                                    
                                    NSArray *airplayNames = RCFetchAirPlayDeviceNames();

                                    NSDictionary *resp = @{
                                        @"ok": @YES,
                                        @"bluetooth": btNames,
                                        @"wifi": wifiNames,
                                        @"apps": appList,
                                        @"airplay": airplayNames
                                    };
                                    NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                    NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                                }
                            } else if ([path isEqualToString:@"/api/commands"] && [method isEqualToString:@"GET"]) {
                                NSArray *commandList = @[
                                    // System Controls
                                    @{@"command": @"lock", @"desc": @"System: Lock the device screen"},
                                    @{@"command": @"unlock <passcode>", @"desc": @"Security: Unlock device screen (INSECURE: Passcode sent in plain text!)"},
                                    @{@"command": @"home", @"desc": @"System: Simulate a Home Button press"},
                                    @{@"command": @"screenshot", @"desc": @"System: Take a screenshot"},
                                    @{@"command": @"screenrecord [toggle|start|stop]", @"desc": @"System: Control system screen recording"},
                                    @{@"command": @"snapper [open|freeze|instant|close]", @"desc": @"Integrations: Control Snapper 2 / Snapper 3"},
                                    @{@"command": @"camera video [zoom] [flash]", @"desc": @"Camera: Open Camera in Video mode (e.g. 2x, 2x flash)"},
                                    @{@"command": @"open control center", @"desc": @"System: Open Control Center"},
                                    @{@"command": @"app switcher", @"desc": @"System: Open App Switcher"},
                                    @{@"command": @"open <bundleId>", @"desc": @"System: Launch an application by bundle identifier"},
                                    @{@"command": @"kill <bundleId>", @"desc": @"System: Force-close an application"},
                                    @{@"command": @"respring", @"desc": @"System: Restart SpringBoard"},
                                    @{@"command": @"safemode", @"desc": @"System: Enter Safe Mode (restart SpringBoard with tweaks disabled)"},
                                    @{@"command": @"ldrestart", @"desc": @"System: Soft-reboot the device"},

                                    // Media & Volume
                                    @{@"command": @"play", @"desc": @"Media: Start playback"},
                                    @{@"command": @"pause", @"desc": @"Media: Pause playback"},
                                    @{@"command": @"next", @"desc": @"Media: Skip to next track"},
                                    @{@"command": @"prev", @"desc": @"Media: Skip to previous track"},
                                    @{@"command": @"toggle", @"desc": @"Media: Toggle play/pause"},
                                    @{@"command": @"vol up", @"desc": @"Media: Increase volume"},
                                    @{@"command": @"vol down", @"desc": @"Media: Decrease volume"},
                                    @{@"command": @"volume <0-100>", @"desc": @"Media: Set volume to specific percentage"},

                                    // Hardware Toggles
                                    @{@"command": @"bt on/off", @"desc": @"Toggles: Bluetooth power"},
                                    @{@"command": @"wifi on/off", @"desc": @"Toggles: WiFi power"},
                                    @{@"command": @"cellular on/off", @"desc": @"Toggles: Cellular Data power"},
                                    @{@"command": @"location on/off/toggle/status", @"desc": @"Toggles: Location Services (GPS)"},
                                    @{@"command": @"airplane on/off", @"desc": @"Toggles: Airplane Mode power"},
                                    @{@"command": @"dnd on/off", @"desc": @"Toggles: Do Not Disturb Mode"},
                                    @{@"command": @"audiomix on/off", @"desc": @"Toggles: AudioMix simultaneous playback"},
                                    @{@"command": @"low power on/off", @"desc": @"Toggles: Low Power Mode"},
                                    @{@"command": @"mute", @"desc": @"Toggles: System mute/silent mode"},
                                    @{@"command": @"rotate lock/unlock", @"desc": @"Toggles: Orientation lock state"},
                                    @{@"command": @"haptic", @"desc": @"System: Play a subtle haptic feedback vibe"},

                                    // Automations & Discovery
                                    @{@"command": @"shortcut \"Name\"", @"desc": @"Automation: Run a Siri Shortcut"},
                                    @{@"command": @"trigger <ID>", @"desc": @"Automation: Fire a configured RemoteCompanion trigger"}
                                ];
                                NSDictionary *resp = @{@"ok": @YES, @"commands": commandList};
                                NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:NSJSONWritingPrettyPrinted error:nil];
                                NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                // Remove backslash escaping for forward slashes
                                jsonStr = [jsonStr stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
                                responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
                            } else if ([path hasPrefix:@"/api/command"]) {
                                load_trigger_config();
                                if (![g_triggerConfig[@"webUIEnabled"] boolValue]) {
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 403 Forbidden\r\n%@Content-Length: 17\r\n\r\nWeb UI is disabled", cors];
                                } else {
                                    __block NSString *command = nil;
                                    
                                    // 1. Try Query Parameters (Allow for both GET and POST)
                                    NSRange qMarkRange = [path rangeOfString:@"?"];
                                    if (qMarkRange.location != NSNotFound) {
                                        NSString *queryString = [path substringFromIndex:qMarkRange.location + 1];
                                        NSArray *pairs = [queryString componentsSeparatedByString:@"&"];
                                        for (NSString *pair in pairs) {
                                            NSArray *kv = [pair componentsSeparatedByString:@"="];
                                            if (kv.count == 2) {
                                                NSString *key = [kv[0] lowercaseString];
                                                if ([key isEqualToString:@"cmd"] || [key isEqualToString:@"command"]) {
                                                    command = [kv[1] stringByRemovingPercentEncoding];
                                                    break;
                                                }
                                            }
                                        }
                                    }

                                    // 2. If no query param found, and it's a POST, check the body
                                    if (!command && [method isEqualToString:@"POST"]) {
                                        NSRange clRange = [requestString rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
                                        int contentLength = 0;
                                        if (clRange.location != NSNotFound) {
                                            NSString *afterCl = [requestString substringFromIndex:clRange.location + clRange.length];
                                            contentLength = [afterCl intValue];
                                        }

                                        const char *headersEnd = strnstr(buffer, "\r\n\r\n", valread);
                                        if (headersEnd != NULL) {
                                            size_t headerBytesOffset = (headersEnd - buffer) + 4;
                                            size_t availableBodyLength = valread - headerBytesOffset;
                                            
                                            NSMutableData *bodyData = [NSMutableData data];
                                            if (availableBodyLength > 0) {
                                                [bodyData appendBytes:(buffer + headerBytesOffset) length:availableBodyLength];
                                            }
                                            
                                            // Ensure we read the complete body based on Content-Length
                                            while (bodyData.length < contentLength) {
                                                char chunk[4096];
                                                ssize_t chunkRead = read(new_socket, chunk, sizeof(chunk));
                                                if (chunkRead <= 0) break;
                                                [bodyData appendBytes:chunk length:chunkRead];
                                            }

                                            NSString *bodyText = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
                                            if (bodyText.length > 0) {
                                                if ([bodyText hasPrefix:@"{"]) {
                                                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
                                                    if (json && json[@"command"]) command = json[@"command"];
                                                } else {
                                                    command = [bodyText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                                }
                                            }
                                        }
                                    }

                                    if (command && command.length > 0) {
                                        // Action commands use async to avoid SpringBoard deadlocks
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            handle_command(command);
                                        });
                                        NSDictionary *resp = @{@"ok": @YES, @"command": command, @"status": @"Acknowledged"};
                                        NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
                                        NSString *jsonStr = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
                                        responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@", cors, (unsigned long)respData.length, jsonStr];
                                    } else {
                                        responseString = [NSString stringWithFormat:@"HTTP/1.1 400 Bad Request\r\n%@Content-Length: 15\r\n\r\nMissing command", cors];
                                    }
                                }
                            } else if ([path hasPrefix:@"/api/trigger/"] && ([method isEqualToString:@"POST"] || [method isEqualToString:@"GET"])) {
                                load_trigger_config();
                                if (![g_triggerConfig[@"webUIEnabled"] boolValue]) {
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 403 Forbidden\r\n%@Content-Length: 17\r\n\r\nWeb UI is disabled", cors];
                                } else {
                                    NSString *triggerKey = [path substringFromIndex:@"/api/trigger/".length];
                                    NSRange qRange = [triggerKey rangeOfString:@"?"];
                                    if (qRange.location != NSNotFound) {
                                        triggerKey = [triggerKey substringToIndex:qRange.location];
                                    }
                                    triggerKey = [triggerKey stringByRemovingPercentEncoding];
                                    
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        RCExecuteTrigger(triggerKey);
                                    });
                                    responseString = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\n%@Content-Type: application/json\r\nContent-Length: 12\r\n\r\n{\"ok\": true}", cors];
                                }
                            }
                            
                            if (responseString) {
                                write(new_socket, [responseString UTF8String], [responseString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
                            }
                        }
                    }
                }
                close(new_socket);
            });
        }
    });
}

static void start_server() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Server starts always, but will refuse commands if disabled in config
        
        int server_fd, new_socket;
        struct sockaddr_un address;
        int addrlen = sizeof(address);
        
        NSString *socketPath = @"/var/mobile/Documents/rc.sock";

        if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) < 0) {
            SRLog(@"[RemoteCommand] ERROR: Failed to create socket (errno: %d)", errno);
            return;
        }

        // Prevent socket file descriptor inheritance to child processes
        fcntl(server_fd, F_SETFD, FD_CLOEXEC);

        // Unlink any existing socket file
        unlink([socketPath UTF8String]);
        
        memset(&address, 0, sizeof(struct sockaddr_un));
        address.sun_family = AF_UNIX;
        strncpy(address.sun_path, [socketPath UTF8String], sizeof(address.sun_path) - 1);
        
        if (bind(server_fd, (struct sockaddr *)&address, sizeof(struct sockaddr_un)) < 0) {
            SRLog(@"[RemoteCommand] ERROR: Failed to bind to socket (errno: %d - %s)", errno, strerror(errno));
            close(server_fd);
            return;
        }
        
        // Allow mobile/root to read/write to the socket
        chmod([socketPath UTF8String], 0777);
        
        if (listen(server_fd, 5) < 0) {
            SRLog(@"[RemoteCommand] ERROR: Failed to listen (errno: %d)", errno);
            close(server_fd);
            return;
        }

        SRLog(@"[RemoteCommand] Server listening on UNIX socket %@... Waiting for connections.", socketPath);

        while (1) {
            addrlen = sizeof(address);
            
            if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
                 if (errno != EAGAIN && errno != EINTR) {
                     SRLog(@"[RemoteCommand] Accept failed: %d (%s)", errno, strerror(errno));
                 }
                 continue;
            }
            
            // Prevent inheritance to child processes and prevent SIGPIPE
            fcntl(new_socket, F_SETFD, FD_CLOEXEC);
            int nosigpipe = 1;
            setsockopt(new_socket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, sizeof(nosigpipe));
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                struct timeval tv;
                tv.tv_sec = 5;
                tv.tv_usec = 0;
                setsockopt(new_socket, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
                setsockopt(new_socket, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof tv);

                char local_buffer[1024] = {0};
                ssize_t valread = read(new_socket, local_buffer, 1024);
                if (valread > 0) {
                    NSString *cmd = [[NSString alloc] initWithBytes:local_buffer length:valread encoding:NSUTF8StringEncoding];
                    // UNIX Sockets are inherently local, no need to check IP or tcpEnabled config
                    NSString *response = handle_command(cmd);
                    if (response) {
                        write(new_socket, [response UTF8String], [response lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
                    }
                }
                close(new_socket);
            });
        }
    });
}

// --- REPLACEMENT NOTE: Removed %ctor from here to move to the end ---



// --- ROBUST HOOKS ---

static NSTimer *g_volUpTimer = nil;
static BOOL g_volUpTriggered = NO;
static BOOL g_volIsReplaying = NO; // Recursion guard for replay

static NSTimer *g_volDownTimer = nil;
static BOOL g_volDownTriggered = NO;

static BOOL g_volUpIsDown = NO;
static BOOL g_volDownIsDown = NO;
static BOOL g_volComboTriggered = NO;
static NSTimeInterval g_lastVolUpPressTime = 0;
static NSTimeInterval g_lastVolDownPressTime = 0;

static NSTimer *g_pendingVolUpSeqTimer = nil;
static NSTimer *g_pendingVolDownSeqTimer = nil;
static BOOL g_volSeqJustFired = NO;

static void cancel_pending_volume_sequences() {
    if (g_pendingVolUpSeqTimer) {
        [g_pendingVolUpSeqTimer invalidate];
        g_pendingVolUpSeqTimer = nil;
    }
    if (g_pendingVolDownSeqTimer) {
        [g_pendingVolDownSeqTimer invalidate];
        g_pendingVolDownSeqTimer = nil;
    }
}

static NSTimer *g_lockButtonTimer = nil;
static BOOL g_lockButtonTriggered = NO;
static NSTimer *g_systemPowerOffTimer = nil; // New for dual-stage
static BOOL g_forceSystemLongPress = NO;     // New for dual-stage
static BOOL g_powerIsDown = NO;
static BOOL g_powerVolComboTriggered = NO;





// static NSTimeInterval g_lastPowerUpTime = 0; // Removed unused variable



// Helper to trigger haptic feedback
// Helper to trigger haptic feedback
static void trigger_haptic() {
    if (RC_IsForegroundAppExcluded()) return;
    AudioServicesPlaySystemSound(1520);
}

// --- SAFE VOLUME HOLD IMPLEMENTATION ---


static int g_lastRingerState = -1;

%hook SBRingerControl

-(void)setRingerMuted:(BOOL)muted {
    %orig;

    if (g_lastRingerState == -1) {
        // First initialization (respring/reboot) - just track state, don't fire
        SRLog(@"SBRingerControl Initial State: %d", muted);
        g_lastRingerState = (int)muted;
        return;
    }

    if (g_lastRingerState == (int)muted) {
        // State hasn't changed, ignore
        return;
    }

    // State changed
    g_lastRingerState = (int)muted;
    SRLog(@"SBRingerControl setRingerMuted: %d", muted);
    
    // Fire generic toggle status
    RCExecuteTrigger(@"trigger_ringer_toggle");

    if (muted) {
        RCExecuteTrigger(@"trigger_ringer_mute");
    } else {
        RCExecuteTrigger(@"trigger_ringer_unmute");
    }
}

%end

static BOOL iPadHasVolumeButtonsOnTop() {
    static BOOL onTop = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct utsname systemInfo;
        uname(&systemInfo);
        NSString *machine = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
        if ([machine isEqualToString:@"iPad14,1"] || [machine isEqualToString:@"iPad14,2"] || // iPad mini 6
            [machine isEqualToString:@"iPad16,1"] || [machine isEqualToString:@"iPad16,2"] || // iPad mini 7
            [machine isEqualToString:@"iPad13,18"] || [machine isEqualToString:@"iPad13,19"]) { // iPad 10
            onTop = YES;
        }
    });
    return onTop;
}

static BOOL iPadIsSwappedBySystem() {
    if ([[UIDevice currentDevice] userInterfaceIdiom] != UIUserInterfaceIdiomPad) {
        return NO;
    }
    
    SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
    UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
    if ([sb respondsToSelector:@selector(activeInterfaceOrientation)]) {
        orientation = [sb activeInterfaceOrientation];
    }
    
    BOOL buttonsOnTop = iPadHasVolumeButtonsOnTop();
    if (buttonsOnTop) {
        return (orientation == UIInterfaceOrientationPortraitUpsideDown || orientation == UIInterfaceOrientationLandscapeRight);
    } else {
        return (orientation == UIInterfaceOrientationPortraitUpsideDown || orientation == UIInterfaceOrientationLandscapeLeft);
    }
}

static BOOL should_swap_in_hooks() {
    load_trigger_config();
    if (![g_triggerConfig[@"masterEnabled"] boolValue]) return NO;
    if (![g_triggerConfig[@"fixedVolumeButtons"] boolValue]) return NO;
    
    return iPadIsSwappedBySystem();
}

static BOOL should_swap_in_hid_listener() {
    load_trigger_config();
    if (![g_triggerConfig[@"masterEnabled"] boolValue]) return NO;
    if ([g_triggerConfig[@"fixedVolumeButtons"] boolValue]) {
        return NO;
    }
    
    return iPadIsSwappedBySystem();
}

static BOOL g_isSwappingVolume = NO;

%hook SBVolumeHardwareButtonActions

- (void)volumeIncreasePressDownWithModifiers:(long long)arg1 {
    if (!g_isSwappingVolume && should_swap_in_hooks()) {
        g_isSwappingVolume = YES;
        [self volumeDecreasePressDownWithModifiers:arg1];
        g_isSwappingVolume = NO;
        return;
    }

    if (g_volIsReplaying || RC_IsForegroundAppExcluded()) {
        %orig;
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    g_volUpIsDown = YES;
    g_lastVolUpPressTime = now;

    // 1. Check for Power + Volume Up combination
    if (g_powerIsDown) {
        cancel_pending_volume_sequences();
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL enabled = masterEnabled && [g_triggerConfig[@"triggers"][@"power_volume_up"][@"enabled"] boolValue];
        if (enabled) {
            SRLog(@"Power + Volume Up combo triggered (from Vol Up Hook)");
            g_powerVolComboTriggered = YES;
            if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
            if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
            trigger_haptic();
            RCExecuteTrigger(@"power_volume_up");
            return;
        }
    }

    // 2. Check for pending Volume Down -> Volume Up sequence
    if (g_pendingVolDownSeqTimer) {
        [g_pendingVolDownSeqTimer invalidate];
        g_pendingVolDownSeqTimer = nil;
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL seqDownUpEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_down_then_up"][@"enabled"] boolValue];
        if (seqDownUpEnabled) {
            SRLog(@"Volume Down then Up sequence triggered!");
            g_volSeqJustFired = YES;
            if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
            if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
            trigger_haptic();
            RCExecuteTrigger(@"volume_down_then_up");
            return;
        }
    }

    // 3. If user is rapidly tapping Vol Up again, cancel pending Vol Up replay timer and replay immediately
    if (g_pendingVolUpSeqTimer) {
        [g_pendingVolUpSeqTimer invalidate];
        g_pendingVolUpSeqTimer = nil;
        g_volIsReplaying = YES;
        [self volumeIncreasePressDownWithModifiers:0];
        [self volumeIncreasePressUp];
        g_volIsReplaying = NO;
    }

    // 4. Check for simultaneous Volume Up + Volume Down dual press
    BOOL isDualPress = g_volDownIsDown || (g_lastVolDownPressTime > 0 && (now - g_lastVolDownPressTime) < 0.20);
    if (isDualPress) {
        cancel_pending_volume_sequences();
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];
        
        if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
        if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
        g_volUpTriggered = NO;
        g_volDownTriggered = NO;

        if (comboEnabled && !g_volComboTriggered) {
            g_volComboTriggered = YES;
            SRLog(@"Volume Both Press combo triggered (from Vol Up Hook)");
            trigger_haptic();
            RCExecuteTrigger(@"volume_both_press");
        } else {
            g_volComboTriggered = YES;
        }
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];
        BOOL holdEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_up_hold"][@"enabled"] boolValue];
        BOOL seqUpDownEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_up_then_down"][@"enabled"] boolValue];

        if (holdEnabled || comboEnabled || seqUpDownEnabled) {
            if (g_volUpTimer) [g_volUpTimer invalidate];
            g_volUpTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:NO block:^(NSTimer *timer) {
                if (g_volComboTriggered || g_powerVolComboTriggered || g_volDownIsDown) return;
                g_volUpTimer = nil;
                if (holdEnabled) {
                    g_volUpTriggered = YES;
                    trigger_haptic();
                    RCExecuteTrigger(@"volume_up_hold");
                } else {
                    g_volIsReplaying = YES;
                    [self volumeIncreasePressDownWithModifiers:arg1];
                    g_volIsReplaying = NO;
                }
            }];
        } else {
            g_volIsReplaying = YES;
            [self volumeIncreasePressDownWithModifiers:arg1];
            g_volIsReplaying = NO;
        }
    });
}

- (void)volumeIncreasePressUp {
    if (!g_isSwappingVolume && should_swap_in_hooks()) {
        g_isSwappingVolume = YES;
        [self volumeDecreasePressUp];
        g_isSwappingVolume = NO;
        return;
    }

    g_volUpIsDown = NO;
    if (g_volIsReplaying || RC_IsForegroundAppExcluded()) {
        %orig;
        return;
    }

    if (g_volSeqJustFired) {
        g_volSeqJustFired = NO;
        if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
        return;
    }

    if (g_volComboTriggered) {
        if (!g_volDownIsDown) g_volComboTriggered = NO;
        if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
        return;
    }

    if (g_powerVolComboTriggered) {
        if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL holdEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_up_hold"][@"enabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];
        BOOL seqUpDownEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_up_then_down"][@"enabled"] boolValue];

        if (g_volUpTriggered) {
            g_volUpTriggered = NO;
            return;
        }

        if (g_volUpTimer) {
            [g_volUpTimer invalidate];
            g_volUpTimer = nil;

            if (seqUpDownEnabled) {
                if (g_pendingVolUpSeqTimer) [g_pendingVolUpSeqTimer invalidate];
                g_pendingVolUpSeqTimer = [NSTimer scheduledTimerWithTimeInterval:0.38 repeats:NO block:^(NSTimer *timer) {
                    g_pendingVolUpSeqTimer = nil;
                    g_volIsReplaying = YES;
                    [self volumeIncreasePressDownWithModifiers:0];
                    [self volumeIncreasePressUp];
                    g_volIsReplaying = NO;
                }];
            } else if (holdEnabled || comboEnabled) {
                g_volIsReplaying = YES;
                [self volumeIncreasePressDownWithModifiers:0];
                [self volumeIncreasePressUp];
                g_volIsReplaying = NO;
            }
        } else {
            g_volIsReplaying = YES;
            [self volumeIncreasePressUp];
            g_volIsReplaying = NO;
        }
    });
}

- (void)volumeDecreasePressDownWithModifiers:(long long)arg1 {
    if (!g_isSwappingVolume && should_swap_in_hooks()) {
        g_isSwappingVolume = YES;
        [self volumeIncreasePressDownWithModifiers:arg1];
        g_isSwappingVolume = NO;
        return;
    }

    if (g_volIsReplaying || RC_IsForegroundAppExcluded()) {
        %orig;
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    g_volDownIsDown = YES;
    g_lastVolDownPressTime = now;

    // 1. Check for Power + Volume Down combination
    if (g_powerIsDown) {
        cancel_pending_volume_sequences();
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL enabled = masterEnabled && [g_triggerConfig[@"triggers"][@"power_volume_down"][@"enabled"] boolValue];
        if (enabled) {
            SRLog(@"Power + Volume Down combo triggered (from Vol Down Hook)");
            g_powerVolComboTriggered = YES;
            if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
            if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
            trigger_haptic();
            RCExecuteTrigger(@"power_volume_down");
            return;
        }
    }

    // 2. Check for pending Volume Up -> Volume Down sequence
    if (g_pendingVolUpSeqTimer) {
        [g_pendingVolUpSeqTimer invalidate];
        g_pendingVolUpSeqTimer = nil;
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL seqUpDownEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_up_then_down"][@"enabled"] boolValue];
        if (seqUpDownEnabled) {
            SRLog(@"Volume Up then Down sequence triggered!");
            g_volSeqJustFired = YES;
            if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
            if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
            trigger_haptic();
            RCExecuteTrigger(@"volume_up_then_down");
            return;
        }
    }

    // 3. If user is rapidly tapping Vol Down again, cancel pending Vol Down replay timer and replay immediately
    if (g_pendingVolDownSeqTimer) {
        [g_pendingVolDownSeqTimer invalidate];
        g_pendingVolDownSeqTimer = nil;
        g_volIsReplaying = YES;
        [self volumeDecreasePressDownWithModifiers:0];
        [self volumeDecreasePressUp];
        g_volIsReplaying = NO;
    }

    // 4. Check for simultaneous Volume Up + Volume Down dual press
    BOOL isDualPress = g_volUpIsDown || (g_lastVolUpPressTime > 0 && (now - g_lastVolUpPressTime) < 0.20);
    if (isDualPress) {
        cancel_pending_volume_sequences();
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];
        
        if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
        if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
        g_volUpTriggered = NO;
        g_volDownTriggered = NO;

        if (comboEnabled && !g_volComboTriggered) {
            g_volComboTriggered = YES;
            SRLog(@"Volume Both Press combo triggered (from Vol Down Hook)");
            trigger_haptic();
            RCExecuteTrigger(@"volume_both_press");
        } else {
            g_volComboTriggered = YES;
        }
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];
        BOOL holdEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_down_hold"][@"enabled"] boolValue];
        BOOL seqDownUpEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_down_then_up"][@"enabled"] boolValue];

        if (holdEnabled || comboEnabled || seqDownUpEnabled) {
            if (g_volDownTimer) [g_volDownTimer invalidate];
            g_volDownTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:NO block:^(NSTimer *timer) {
                if (g_volComboTriggered || g_powerVolComboTriggered || g_volUpIsDown) return;
                g_volDownTimer = nil;
                if (holdEnabled) {
                    g_volDownTriggered = YES;
                    trigger_haptic();
                    RCExecuteTrigger(@"volume_down_hold");
                } else {
                    g_volIsReplaying = YES;
                    [self volumeDecreasePressDownWithModifiers:arg1];
                    g_volIsReplaying = NO;
                }
            }];
        } else {
            g_volIsReplaying = YES;
            [self volumeDecreasePressDownWithModifiers:arg1];
            g_volIsReplaying = NO;
        }
    });
}

- (void)volumeDecreasePressUp {
    if (!g_isSwappingVolume && should_swap_in_hooks()) {
        g_isSwappingVolume = YES;
        [self volumeIncreasePressUp];
        g_isSwappingVolume = NO;
        return;
    }

    g_volDownIsDown = NO;
    if (g_volIsReplaying || RC_IsForegroundAppExcluded()) {
        %orig;
        return;
    }

    if (g_volSeqJustFired) {
        g_volSeqJustFired = NO;
        if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
        return;
    }

    if (g_volComboTriggered) {
        if (!g_volUpIsDown) g_volComboTriggered = NO;
        if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
        return;
    }

    if (g_powerVolComboTriggered) {
        if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL holdEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_down_hold"][@"enabled"] boolValue];
        BOOL comboEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue];
        BOOL seqDownUpEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"volume_down_then_up"][@"enabled"] boolValue];

        if (g_volDownTriggered) {
            g_volDownTriggered = NO;
            return;
        }

        if (g_volDownTimer) {
            [g_volDownTimer invalidate];
            g_volDownTimer = nil;

            if (seqDownUpEnabled) {
                if (g_pendingVolDownSeqTimer) [g_pendingVolDownSeqTimer invalidate];
                g_pendingVolDownSeqTimer = [NSTimer scheduledTimerWithTimeInterval:0.38 repeats:NO block:^(NSTimer *timer) {
                    g_pendingVolDownSeqTimer = nil;
                    g_volIsReplaying = YES;
                    [self volumeDecreasePressDownWithModifiers:0];
                    [self volumeDecreasePressUp];
                    g_volIsReplaying = NO;
                }];
            } else if (holdEnabled || comboEnabled) {
                g_volIsReplaying = YES;
                [self volumeDecreasePressDownWithModifiers:0];
                [self volumeDecreasePressUp];
                g_volIsReplaying = NO;
            }
        } else {
            g_volIsReplaying = YES;
            [self volumeDecreasePressUp];
            g_volIsReplaying = NO;
        }
    });
}

%end


// --- IOHID Definitions for Background Listener ---
typedef struct __IOHIDEvent * IOHIDEventRef;
typedef struct __IOHIDEventSystemClient * IOHIDEventSystemClientRef;
typedef uint32_t IOHIDEventOptionBits;
typedef uint32_t IOOptionBits;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventGetType(IOHIDEventRef event);
extern int IOHIDEventGetIntegerValue(IOHIDEventRef event, int field);
extern void IOHIDEventSystemClientRegisterEventCallback(IOHIDEventSystemClientRef client, void* callback, void* target, void* refcon);
extern void IOHIDEventSystemClientScheduleWithRunLoop(IOHIDEventSystemClientRef client, CFRunLoopRef runLoop, CFStringRef runLoopMode);

typedef void (*IOHIDEventSystemClientEventCallback)(void* target, void* refcon, void* queue, IOHIDEventRef event);

// Usage Pages / Usages
#define kHIDPage_GenericDesktop 0x01
#define kHIDPage_Consumer       0x0C
#define kHIDUsage_GD_SystemSleep 0x82
#define kHIDUsage_Csmr_Power     0x30
#define kHIDUsage_Csmr_Menu      0x40
#define kHIDUsage_Csmr_VolumeIncrement 0xE9
#define kHIDUsage_Csmr_VolumeDecrement 0xEA
#define kHIDUsage_Csmr_PlayOrPause 0xCD

#define kIOHIDEventTypeKeyboard 3
#define kIOHIDEventFieldKeyboardUsagePage 0x30000
#define kIOHIDEventFieldKeyboardUsage 0x30001
#define kIOHIDEventFieldKeyboardDown 0x30002

// --- BACKGROUND HID LISTENER (Safe for NFC) ---
// Restores reliable Home Button counting without crashing NearField

static int g_homeClickCount = 0;
static NSTimer *g_homeClickTimer = nil;

// Power Button Multi-Click Globals
static int g_powerClickCount = 0;
static NSTimer *g_powerClickTimer = nil;
static NSTimeInterval g_lastHIDTime = 0;
static BOOL g_hidButtonDown = NO;
static IOHIDEventSystemClientRef g_hidClient = NULL;

static void RC_CheckAndFire();

static void RC_ProcessHomeClick() {
    if (RC_IsForegroundAppExcluded()) return;
    g_homeClickCount++;
    SRLog(@"[HID] 🔵 CLICK DETECTED (Up)! Count: %d", g_homeClickCount);
    
    // Dispatch timer scheduling to Main Thread to be safe with Timers/RunLoops
    dispatch_async(dispatch_get_main_queue(), ^{
        RC_CheckAndFire();
    });
}

static void RC_CheckAndFire() {
    // 1. Reset existing timer
    if (g_homeClickTimer) {
        [g_homeClickTimer invalidate];
        g_homeClickTimer = nil;
    }
    
    // 2. Load Config
    load_trigger_config();
    BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
    BOOL quadEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"trigger_home_quadruple_click"][@"enabled"] boolValue];

    // 3. IMMEDIATE FIRE CHECK (Quadruple)
    if (quadEnabled && g_homeClickCount >= 4) {
        SRLog(@"🚀 QUAD CLICK (4+) REACHED! Firing immediately.");
        trigger_haptic();
        RCExecuteTrigger(@"trigger_home_quadruple_click");
        g_homeClickCount = 0; // Reset Sequence
        return;
    }
    
    // 4. Determines Timeout
    NSTimeInterval timeout = 0.35; 
    if (quadEnabled) timeout = 0.55; 
    
    // 5. Schedule Timer
    g_homeClickTimer = [NSTimer scheduledTimerWithTimeInterval:timeout repeats:NO block:^(NSTimer *timer) {
        g_homeClickTimer = nil;
        SRLog(@"🔵 SEQUENCE ENDED. Final count: %d", g_homeClickCount);
        
        NSString *triggerKey = nil;
        
        if (g_homeClickCount == 4 && quadEnabled) triggerKey = @"trigger_home_quadruple_click";
        else if (g_homeClickCount == 3) triggerKey = @"trigger_home_triple_click";
        else if (g_homeClickCount == 2) triggerKey = @"trigger_home_double_click";
        
        if (triggerKey && masterEnabled) {
            BOOL enabled = [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
            if (enabled) {
                SRLog(@"✅ FIRING TRIGGER: %@", triggerKey);
                trigger_haptic();
                RCExecuteTrigger(triggerKey);
            }
        }
        g_homeClickCount = 0;
    }];
}

static void RC_CheckAndFirePower();

static void RC_ProcessPowerClick() {
    // 1. Reset timer
    if (g_powerClickTimer) {
        [g_powerClickTimer invalidate];
        g_powerClickTimer = nil;
    }
    
    g_powerClickCount++;
    SRLog(@"[HID] ⚡️ POWER CLICK DETECTED. Count: %d", g_powerClickCount);
    
    // Dispatch timer scheduling to Main Thread to be safe with Timers/RunLoops
    dispatch_async(dispatch_get_main_queue(), ^{
        RC_CheckAndFirePower();
    });
}

// Power Button Multi-Click Logic
static void RC_CheckAndFirePower() {
    // 1. Reset timer
    if (g_powerClickTimer) {
        [g_powerClickTimer invalidate];
        g_powerClickTimer = nil;
    }
    
    load_trigger_config();
    BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
    BOOL quadEnabled = masterEnabled && [g_triggerConfig[@"triggers"][@"power_quadruple_click"][@"enabled"] boolValue];
    
    // 3. IMMEDIATE FIRE CHECK (Quadruple)
    if (quadEnabled && g_powerClickCount >= 4) {
        SRLog(@"🚀 POWER QUAD CLICK (4+) REACHED! Firing.");
        trigger_haptic();
        RCExecuteTrigger(@"power_quadruple_click");
        g_powerClickCount = 0;
        return;
    }
    
    // 4. Timeout
    NSTimeInterval timeout = 0.4; 
    
    // 5. Schedule Timer
    g_powerClickTimer = [NSTimer scheduledTimerWithTimeInterval:timeout repeats:NO block:^(NSTimer *timer) {
        g_powerClickTimer = nil;
        SRLog(@"POWER SEQUENCE ENDED. Final count: %d", g_powerClickCount);
        
        NSString *triggerKey = nil;
        
        if (g_powerClickCount == 4) triggerKey = @"power_quadruple_click"; // Backup if immediate failed or disabled? No, if disabled we land here.
        else if (g_powerClickCount == 3) triggerKey = @"power_triple_click";
        else if (g_powerClickCount == 2) triggerKey = @"power_double_tap";
        
        if (triggerKey && masterEnabled) {
            BOOL enabled = [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
            if (enabled) {
                SRLog(@"✅ FIRING POWER TRIGGER: %@", triggerKey);
                trigger_haptic();
                RCExecuteTrigger(triggerKey);
            }
        }
        g_powerClickCount = 0;
    }];
}

static void handle_hid_event(void* target, void* refcon, IOHIDEventSystemClientRef service, IOHIDEventRef event) {
    if (RC_IsForegroundAppExcluded()) return;
    int type = IOHIDEventGetType(event);
    
    if (type == 14) { // kIOHIDEventTypeProximity
        int detection = IOHIDEventGetIntegerValue(event, (14 << 16) | 0);
        int level = IOHIDEventGetIntegerValue(event, (14 << 16) | 1);
        SRLog(@"[HID Proximity] Event type 14 detected! detection=%d, level=%d", detection, level);
        g_latestHIDProximityState = (detection != 0) ? 1 : 0;
    }
    
    if (type == 29) { // Biometric Event (Finger on sensor)
        // Toggle Logic for "Hold" (Fire by itself after 1.0s)
        // Assumption: Sensor sends event on DOWN ... (Silence) ... and UP.
        
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

        dispatch_async(dispatch_get_main_queue(), ^{
            load_trigger_config();
            BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                ([g_triggerConfig[@"triggers"][@"touchid_hold"][@"enabled"] boolValue] || 
                 [g_triggerConfig[@"triggers"][@"touchid_tap"][@"enabled"] boolValue]);
            if (!enabled) return;

            // DEBOUNCE CHECK:
            if (now < g_bioIgnoreUntil) {
                // SRLog(@"[Bio] Ignoring Event (Debounce)");
                return;
            }

            // STATE-BASED TOGGLE LOGIC:
            NSTimeInterval diff = (g_bioFingerDownTime == 0) ? 0 : (now - g_bioFingerDownTime);
            BOOL isStale = (diff > 5.0); // If >5s, assume we missed a lift event and reset.

            if (g_bioFingerDownTime != 0 && !isStale) {
                // STATE = DOWN. This event must be LIFT.
                
                // VARIABLE DELAY:
                // If we started on the lockscreen, we need a bigger window (0.4s) for biometrics to "win" the race.
                // If we're already unlocked, we want it fast (0.05s) for responsiveness.
                NSTimeInterval liftDelay = g_bioWasLocked ? 0.4 : 0.05;

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(liftDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (g_bioFingerDownTime == 0) return; // Already handled or reset

                    // Cancel timer if running.
                    if (g_bioWatchdogTimer) {
                        [g_bioWatchdogTimer invalidate];
                        g_bioWatchdogTimer = nil;

                        NSTimeInterval now_lift = [[NSDate date] timeIntervalSince1970];
                        if (now_lift < g_bioIgnoreUntil) {
                            SRLog(@"[Bio] Suppressing Tap (Finger Lift within Ignore Window)");
                            g_bioFingerDownTime = 0;
                            g_bioHoldTriggered = NO;
                            return;
                        }

                        // STATE-AWARE SUPPRESSION:
                        // If we were locked when we put our finger down, but we are now UNLOCKED, 
                        // this was an unlock attempt. Skip the tap.
                        Class LSMC = objc_getClass("SBLockScreenManager");
                        SBLockScreenManager *lsm = LSMC ? [LSMC sharedInstance] : nil;
                        BOOL currentlyLocked = lsm ? [lsm isUILocked] : NO;
                        
                        if (g_bioWasLocked && !currentlyLocked) {
                            SRLog(@"[Bio] Suppressing Tap (Finger Lift after Unlock Match Detected)");
                            g_bioFingerDownTime = 0;
                            g_bioHoldTriggered = NO;
                            return;
                        }

                        if ([g_triggerConfig[@"triggers"][@"touchid_tap"][@"enabled"] boolValue]) {
                            trigger_haptic();
                            RCExecuteTrigger(@"touchid_tap");
                        }
                    }
                    g_bioFingerDownTime = 0; // Reset State to UP.
                    g_bioHoldTriggered = NO;
                    
                    // START DEBOUNCE (Ignore subsequent events for 0.5s to squash "bouncing")
                    g_bioIgnoreUntil = [[NSDate date] timeIntervalSince1970] + 0.5;
                });

            } else {
                // STATE = UP (or Stale). This event must be DOWN.
                // Start Timer!
                g_bioFingerDownTime = now; // Set State to DOWN.
                
                // Track initial lock state
                Class LSMC = objc_getClass("SBLockScreenManager");
                SBLockScreenManager *lsm = LSMC ? [LSMC sharedInstance] : nil;
                g_bioWasLocked = NO;
                if (lsm && [lsm respondsToSelector:@selector(isUILocked)]) {
                    g_bioWasLocked = [lsm isUILocked];
                }

                
                if (g_bioWatchdogTimer) [g_bioWatchdogTimer invalidate];
                g_bioWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *timer) {

                    g_bioWatchdogTimer = nil; // Timer is done.
                    
                    // ADD DECISION WINDOW FOR HOLD (0.3s)
                    // Similar to the Tap fix, we wait a moment on the lockscreen to let biometrics "win".
                    NSTimeInterval holdDecisionDelay = g_bioWasLocked ? 0.3 : 0.0;
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(holdDecisionDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        // Check ignore window first
                        if ([[NSDate date] timeIntervalSince1970] < g_bioIgnoreUntil) {
                            SRLog(@"[Bio] Suppressing Hold (Inside Ignore Window)");
                            return;
                        }

                        // STATE-AWARE SUPPRESSION (Hold):
                        Class LSMC2 = objc_getClass("SBLockScreenManager");
                        SBLockScreenManager *lsm2 = LSMC2 ? [LSMC2 sharedInstance] : nil;
                        BOOL currentlyLocked2 = lsm2 ? [lsm2 isUILocked] : NO;
                        
                        if (g_bioWasLocked && !currentlyLocked2) {
                            SRLog(@"[Bio] Suppressing Hold (Unlock succeeded during decision window)");
                            return;
                        }

                        // Check if trigger is enabled and has actions BEFORE firing haptics
                        if (g_triggerConfig) {
                            NSDictionary *holdTrigger = g_triggerConfig[@"triggers"][@"touchid_hold"];
                            if ([holdTrigger[@"enabled"] boolValue] && [holdTrigger[@"actions"] count] > 0) {
                                trigger_haptic();
                                RCExecuteTrigger(@"touchid_hold");
                            }
                        }
                    });
                }];
            }
        });

    }
    
    // Log Biometric/Mesa events specifically?
    // kIOHIDEventTypeBiometric = 29?
    // Let's just log everything that isn't accelerometer (usually high freq)
    // Accelerometer is... often type 13?
    
    if (type == kIOHIDEventTypeKeyboard) {
        int usagePage = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardUsagePage);
        int usage = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardUsage);
        int down = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardDown);
        
        // SRLog(@"[HID] KEYBOARD (1) -> Page: 0x%X Usage: 0x%X Down: %d", usagePage, usage, down);
        
        // Home Button (Page 0x0C, Usage 0x40)
        if (usagePage == kHIDPage_Consumer && usage == kHIDUsage_Csmr_Menu) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            
            if (down) {
                if (!g_hidButtonDown) {
                    g_hidButtonDown = YES;
                    g_lastHIDTime = now;

                    
                    // SUPPRESS TOUCH ID HOLD:
                    // If user is clicking, they are not "Holding" for the gesture.
                    // Suppress bio events for 1.5s (covers triple clicks).
                    g_bioIgnoreUntil = now + 1.5;
                    
                    // Dispatch state reset to Main Thread to ensure synchronization with Bio handlers
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (g_bioWatchdogTimer) {
                            [g_bioWatchdogTimer invalidate];
                            g_bioWatchdogTimer = nil;
                        }
                        g_bioFingerDownTime = 0;
                        g_bioHoldTriggered = NO;
                    });
                }
            } else { // UP
                if (g_hidButtonDown) {
                    if (now - g_lastHIDTime > 0.05) { // 50ms Debounce
                        g_hidButtonDown = NO;
                        g_lastHIDTime = now;

                        RC_ProcessHomeClick();
                    }
                }
            }
        }
        
        // Power Button (Page 0x0C, Usage 0x30)
        if (usagePage == kHIDPage_Consumer && usage == kHIDUsage_Csmr_Power) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            static NSTimeInterval lastPowerDownTime = 0;

            if (down) {
                if (!g_powerIsDown) {
                    g_powerIsDown = YES;
                    lastPowerDownTime = now;
                    SRLog(@"[HID] ⚡️ Power DOWN");
                    
                    // SUPPRESS TOUCH ID HOLD (on Power Wake/Press):
                    // If user is pressing power, they might be waking to unlock.
                    // Suppress bio events for 1.5s.
                    NSTimeInterval now_power = [[NSDate date] timeIntervalSince1970];
                    g_bioIgnoreUntil = now_power + 1.5;
                    // Also cancel any pending hold timer
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (g_bioWatchdogTimer) {
                            [g_bioWatchdogTimer invalidate];
                            g_bioWatchdogTimer = nil;
                        }
                    });
                    g_bioFingerDownTime = 0;
                    g_bioHoldTriggered = NO;

                    // Check for simultaneous press if Volume is already down
                    if (g_volUpIsDown || g_volDownIsDown) {
                        NSString *triggerKey = g_volUpIsDown ? @"power_volume_up" : @"power_volume_down";
                        load_trigger_config();
                        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
                        BOOL enabled = masterEnabled && [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
                        
                        if (enabled && !g_powerVolComboTriggered) {
                            SRLog(@"[HID] ⚡️+🔊 POWER + VOLUME COMBINATION DETECTED (Power after Volume): %@", triggerKey);
                            g_powerVolComboTriggered = YES;
                            dispatch_async(dispatch_get_main_queue(), ^{
                                 cancel_pending_volume_sequences();
                                 if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
                                 if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
                                 trigger_haptic();
                                 RCExecuteTrigger(triggerKey);
                            });
                        }
                    }
                }
            } else { // UP
                if (g_powerIsDown) {
                    if (now - lastPowerDownTime > 0.05) { // 50ms Debounce
                        g_powerIsDown = NO;
                        SRLog(@"[HID] ⚡️ Power UP");
                        
                        // Invalidate pending power hold timers immediately on physical button release
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (g_lockButtonTimer) {
                                [g_lockButtonTimer invalidate];
                                g_lockButtonTimer = nil;
                            }
                            if (g_systemPowerOffTimer) {
                                [g_systemPowerOffTimer invalidate];
                                g_systemPowerOffTimer = nil;
                            }
                        });

                        // If a combo was triggered, DON'T count this as a click for multi-tap
                        if (g_powerVolComboTriggered) {
                            SRLog(@"[HID] Combo was triggered, resetting power click count.");
                            g_powerClickCount = 0;
                            g_powerVolComboTriggered = NO;
                        } else {
                            RC_ProcessPowerClick();
                        }
                    }
                    g_powerIsDown = NO; // Handle fast bounce
                }
            }
        }
        
        // Volume Buttons (Page 0x0C, Usage 0xE9/0xEA)
        if (usagePage == kHIDPage_Consumer && (usage == kHIDUsage_Csmr_VolumeIncrement || usage == kHIDUsage_Csmr_VolumeDecrement)) {
            uint32_t mappedUsage = usage;
            if (should_swap_in_hid_listener()) {
                mappedUsage = (usage == kHIDUsage_Csmr_VolumeIncrement) ? kHIDUsage_Csmr_VolumeDecrement : kHIDUsage_Csmr_VolumeIncrement;
            }

            if (mappedUsage == kHIDUsage_Csmr_VolumeIncrement) g_volUpIsDown = !!down;
            if (mappedUsage == kHIDUsage_Csmr_VolumeDecrement) g_volDownIsDown = !!down;
            
            // Check for Power + Volume combination
            if (down && g_powerIsDown) {
                NSString *triggerKey = (mappedUsage == kHIDUsage_Csmr_VolumeIncrement) ? @"power_volume_up" : @"power_volume_down";
                load_trigger_config();
                BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
                BOOL enabled = masterEnabled && [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
                
                if (enabled) {
                    SRLog(@"[HID] ⚡️+🔊 POWER + VOLUME COMBINATION DETECTED: %@", triggerKey);
                    g_powerVolComboTriggered = YES;
                    
                    // Invalidate standard timers in Main Thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                         cancel_pending_volume_sequences();
                         if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
                         if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
                         trigger_haptic();
                         RCExecuteTrigger(triggerKey);
                    });
                    
                    // We might want to swallow the volume event here, but HID listener is just a listener.
                    // The Volume hooks will also fire, we handle suppression there too.
                }
            }
            
            if (g_volUpIsDown && g_volDownIsDown) {
                if (!g_volComboTriggered) {
                    load_trigger_config();
                    if ([g_triggerConfig[@"masterEnabled"] boolValue] && [g_triggerConfig[@"triggers"][@"volume_both_press"][@"enabled"] boolValue]) {
                        g_volComboTriggered = YES;
                        
                        // Invalidate standard timers in Main Thread
                        dispatch_async(dispatch_get_main_queue(), ^{
                             cancel_pending_volume_sequences();
                             if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
                             if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
                             trigger_haptic();
                             RCExecuteTrigger(@"volume_both_press");
                        });
                    }
                }
            } else if (!g_volUpIsDown && !g_volDownIsDown) {
                if (g_volComboTriggered) {
                    g_volComboTriggered = NO;
                }
            }
        }
    }
}

static void setup_background_hid_listener() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SRLog(@"🔌 Setting up BACKGROUND HID Listener...");
        
        // Create client
        g_hidClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!g_hidClient) {
            SRLog(@"❌ Failed to create HID Client");
            return;
        }
        
        // Register callback
        IOHIDEventSystemClientRegisterEventCallback(g_hidClient, (IOHIDEventSystemClientEventCallback)handle_hid_event, NULL, NULL);
        
        // Create RunLoop for this background thread
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        
        // Schedule client
        IOHIDEventSystemClientScheduleWithRunLoop(g_hidClient, [runLoop getCFRunLoop], kCFRunLoopDefaultMode);
        
        SRLog(@"✅ HID Listener Scheduled on Background RunLoop. Running...");
        
        // Run the runloop indefinitely
        while (YES) {
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    });
}


%hook SBLockScreenManager

- (BOOL)_attemptUnlockWithPasscode:(id)passcode mesa:(BOOL)mesa finishUIUnlock:(BOOL)finishUI {
    BOOL result = %orig;
    if (mesa) {
        SRLog(@"🧬 Biometric (Mesa) Match Detected - setting immediate suppression flag");
        g_bioIgnoreUntil = [[NSDate date] timeIntervalSince1970] + 2.0;
        
        // Cancel pending timers immediately
        if (g_bioWatchdogTimer) {
            [g_bioWatchdogTimer invalidate];
            g_bioWatchdogTimer = nil;
        }
    }
    return result;
}

%end

%hook SBProximitySensorManager
- (id)init {
    id orig = %orig;
    g_proximitySensorManager = orig;
    SRLog(@"[RemoteCompanion] Hooked SBProximitySensorManager init: %@", g_proximitySensorManager);
    return orig;
}
- (id)initWithHIDInterface:(id)arg1 hardwareDefaults:(id)arg2 interfaceOrientationProvider:(id)arg3 {
    id orig = %orig;
    g_proximitySensorManager = orig;
    SRLog(@"[RemoteCompanion] Hooked SBProximitySensorManager custom init: %@", g_proximitySensorManager);
    return orig;
}
%end

%hook SBLockHardwareButtonActions

- (void)performInitialButtonDownActions {
    if (RC_IsForegroundAppExcluded()) {
        %orig;
        return;
    }
    SRLog(@"performInitialButtonDownActions on %@", [self class]);
    g_powerIsDown = YES;
    
    // Check for simultaneous press if Volume is already down
    if (g_volUpIsDown || g_volDownIsDown) {
        NSString *triggerKey = g_volUpIsDown ? @"power_volume_up" : @"power_volume_down";
        load_trigger_config();
        BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
        BOOL enabled = masterEnabled && [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
        
        if (enabled && !g_powerVolComboTriggered) {
            SRLog(@"Power + Volume combo detected (from Lock button down): %@", triggerKey);
            g_powerVolComboTriggered = YES;
            if (g_volUpTimer) { [g_volUpTimer invalidate]; g_volUpTimer = nil; }
            if (g_volDownTimer) { [g_volDownTimer invalidate]; g_volDownTimer = nil; }
            trigger_haptic();
            RCExecuteTrigger(triggerKey);
            return;
        }
    }
    
    load_trigger_config();
    BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
    BOOL longPressEnabled = masterEnabled && 
                   [g_triggerConfig[@"triggers"][@"power_long_press"][@"enabled"] boolValue];

    SRLog(@"Power Button DOWN (Actions) - enabled=%d", longPressEnabled);

    if (longPressEnabled) {
        if (g_lockButtonTimer == nil && !g_lockButtonTriggered) {
            g_lockButtonTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *timer) {
                g_lockButtonTimer = nil;
                if (!g_powerIsDown) {
                    SRLog(@"Power Long Press ignored because button is not down");
                    return;
                }
                g_lockButtonTriggered = YES;
                trigger_haptic();
                RCExecuteTrigger(@"power_long_press");
                SRLog(@"Power Long Press Fired (Stage 1)!");
                
                // Start Stage 2 Timer (System Power Off) - 2.0s later (2.5s total hold)
                g_systemPowerOffTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO block:^(NSTimer *t) {
                     g_systemPowerOffTimer = nil;
                     if (!g_powerIsDown) return;
                     SRLog(@"Power Long Press (Stage 2) - Forcing System Power Off Screen");
                     g_forceSystemLongPress = YES;
                     
                     // Manually invoke the action again, but this time g_forceSystemLongPress is YES
                     [self performLongPressActions];
                }];
            }];
        }
    }

    BOOL multiClickEnabled = masterEnabled && 
        ([g_triggerConfig[@"triggers"][@"power_double_tap"][@"enabled"] boolValue] ||
         [g_triggerConfig[@"triggers"][@"power_triple_click"][@"enabled"] boolValue] ||
         [g_triggerConfig[@"triggers"][@"power_quadruple_click"][@"enabled"] boolValue]);

    // SUPPRESSION: If a multi-click sequence is in progress, swallow the DOWN event for 2nd click onwards.
    // This stops the phone from waking/locking on subsequent clicks while allowing single-tap %orig.
    if (multiClickEnabled && g_powerClickCount >= 2) {
        SRLog(@"Suppressing system DOWN for click sequence (count=%d)", g_powerClickCount);
        return;
    }

    %orig;
}

- (void)performButtonUpPreActions {
    SRLog(@"performButtonUpPreActions on %@", [self class]);
    SRLog(@"Power Button UP (Actions)");
    g_powerIsDown = NO;

    if (g_lockButtonTimer) {
        [g_lockButtonTimer invalidate];
        g_lockButtonTimer = nil;
    }
    if (g_systemPowerOffTimer) {
        [g_systemPowerOffTimer invalidate];
        g_systemPowerOffTimer = nil;
    }
    g_forceSystemLongPress = NO;
    
    if (g_lockButtonTriggered) {
        g_lockButtonTriggered = NO;
        SRLog(@"Power Button Release: Long press already fired, resetting.");
        return; 
    }

    load_trigger_config();
    BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
    BOOL multiClickEnabled = masterEnabled && 
        ([g_triggerConfig[@"triggers"][@"power_double_tap"][@"enabled"] boolValue] ||
         [g_triggerConfig[@"triggers"][@"power_triple_click"][@"enabled"] boolValue] ||
         [g_triggerConfig[@"triggers"][@"power_quadruple_click"][@"enabled"] boolValue]);

    // SUPPRESSION: Swallow UP events for 2nd click onwards.
    // Click 1 passes %orig so system can lock/wake normally if sequence stops.
    if (multiClickEnabled && g_powerClickCount >= 2) {
        SRLog(@"Suppressing system UP for click #%d", g_powerClickCount);
        return;
    }

    // SUPPRESSION: If a Power + Volume combo was triggered, swallow the Power UP as well.
    if (g_powerVolComboTriggered) {
        SRLog(@"Suppressing system UP because a Power + Volume combo was triggered.");
        // g_powerVolComboTriggered will be reset in handle_hid_event UP
        return;
    }

    %orig;
}

- (void)performLongPressActions {
    SRLog(@"performLongPressActions called - g_lockButtonTriggered=%d, force=%d", g_lockButtonTriggered, g_forceSystemLongPress);
    
    if (g_forceSystemLongPress) {
        SRLog(@"Allowing System Power Off (Stage 2)");
        g_forceSystemLongPress = NO; // Reset immediately
        %orig;
        return;
    }

    load_trigger_config();
    BOOL masterEnabled = [g_triggerConfig[@"masterEnabled"] boolValue];
    BOOL longPressEnabled = masterEnabled && 
                   [g_triggerConfig[@"triggers"][@"power_long_press"][@"enabled"] boolValue];

    if (longPressEnabled) {
        if (!g_lockButtonTriggered) {
            if (g_lockButtonTimer) {
                [g_lockButtonTimer invalidate];
                g_lockButtonTimer = nil;
            }
            g_lockButtonTriggered = YES;
            trigger_haptic();
            RCExecuteTrigger(@"power_long_press");
            SRLog(@"Power Long Press Fired (via performLongPressActions)!");
            
            // Start Stage 2 Timer (System Power Off) - 2.0s later
            g_systemPowerOffTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO block:^(NSTimer *t) {
                 g_systemPowerOffTimer = nil;
                 if (!g_powerIsDown) return;
                 SRLog(@"Power Long Press (Stage 2) - Forcing System Power Off Screen");
                 g_forceSystemLongPress = YES;
                 [self performLongPressActions];
            }];
        }
        SRLog(@"Power Long Press Actions (Default) Suppressed (Stage 1 active)");
        return; 
    }

    if (g_lockButtonTriggered) {
        SRLog(@"Power Long Press Actions (Default) Suppressed (Stage 1 active)");
        return; 
    }
    %orig;
}

- (void)performDoublePressActions {
    SRLog(@"performDoublePressActions called (System)");
    // We handle double press manually in performButtonUpPreActions to support Triple/Quad clicks.
    // So we do NOT fire "power_double_tap" here to avoid duplicates.
    // However, if we suppress %orig completely, we might break Wallet double-click.
    // For now, let's just allow orig so system features work, 
    // relying on our manual counter for OUR actions.
    
    // Logic: If we have a configured double tap action, our manual handler will fire it.
    // If not, this does nothing related to us.
    
    /*
    load_trigger_config();
    BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                   [g_triggerConfig[@"triggers"][@"power_double_tap"][@"enabled"] boolValue];

    if (enabled) {
        // Don't fire here, manual handler does it.
    }
    */
    /*
        trigger_haptic();
        RCExecuteTrigger(@"power_double_tap");
        SRLog(@"Power Double Tap Fired (Actions)");
        return; 
    }
    */
    %orig;
}

%end

// [Generic simulation registration handled by catch-all observer in register_simulation_observers]

%hook SBLockHardwareButton
- (void)doublePress:(id)arg1 {
    SRLog(@"SBLockHardwareButton doublePress: called");
    load_trigger_config();
    BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                   [g_triggerConfig[@"triggers"][@"power_double_tap"][@"enabled"] boolValue];
    if (enabled) {
        // We already handled it in Actions (hopefully), or we handle it here if Actions wasn't called
        // But to be safe, let's see if this one fires.
        %orig; 
    } else {
        %orig;
    }
}
%end



// [Removed unused biometric hooks]


// --- Cleanup: Removed failed biometric logic ---

// [Removed unused SBHomeHardwareButton hook]

// --- REPLACEMENT NOTE: Removed %ctor from here to move to the end ---



// ============ STATUS BAR GESTURES (HOLD + SWIPE) ============
// Hook UIApplication - uses screen coordinates for reliable detection

static NSTimer *g_statusBarHoldTimer = nil;
static BOOL g_statusBarHoldTriggered = NO;
static NSString *g_pendingStatusBarTrigger = nil;

// Swipe tracking
static CGFloat g_statusBarSwipeStartX = 0;
static CGFloat g_statusBarSwipeStartY = 0;
static BOOL g_statusBarTouchActive = NO;

// Bottom Bar Swipe tracking
static CGFloat g_bottomBarSwipeStartX = 0;
static CGFloat g_bottomBarSwipeStartY = 0;
static BOOL g_bottomBarTouchActive = NO;
static BOOL g_bottomBarHapticFired = NO;

// Status Bar Extended State
static BOOL g_statusBarSwipeHapticFired = NO;
static BOOL g_statusBarSwipeTriggered = NO;
static NSTimeInterval g_lastStatusBarDoubleTapTime = 0;

%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    // Only process touch events
    if (event.type == UIEventTypeTouches) {
        UITouch *touch = [[event allTouches] anyObject];
        
        if (touch && touch.phase == UITouchPhaseBegan) {
            UIWindow *window = nil;
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            window = [UIApplication sharedApplication].keyWindow ?: [[UIApplication sharedApplication].windows firstObject];
            #pragma clang diagnostic pop
            UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
            
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            if (window && window.windowScene) {
                orientation = window.windowScene.interfaceOrientation;
            } else {
                orientation = [UIApplication sharedApplication].statusBarOrientation;
            }
            #pragma clang diagnostic pop

            CGPoint loc = [touch locationInView:nil];
            CGSize screenSize = [[UIScreen mainScreen] bounds].size;
            
            // Logic width/height (always portrait relative)
            CGFloat lw = MIN(screenSize.width, screenSize.height);
            CGFloat lh = MAX(screenSize.width, screenSize.height);
            
            // BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
            
            // Map coordinates and determine logic regions based on orientation
            BOOL inTopRegion = NO;
            BOOL inBottomRegion = NO;
            
            if (orientation == UIInterfaceOrientationPortrait) {
                inTopRegion = (loc.y < 50);
                inBottomRegion = (loc.y > lh - 50);
            } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
                inTopRegion = (loc.y > lh - 50);
                inBottomRegion = (loc.y < 50);
            } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
                // Home button on right: Status bar is physically at X=0-50, Bottom bar at X=lw-50
                inTopRegion = (loc.x < 50);
                inBottomRegion = (loc.x > lw - 50);
            } else if (orientation == UIInterfaceOrientationLandscapeRight) {
                // Home button on left: Status bar is physically at X=lw-50, Bottom bar at X=0-50
                inTopRegion = (loc.x > lw - 50);
                inBottomRegion = (loc.x < 50);
            }

            SRLog(@"[Debug] TouchBegan phys=(%.1f, %.1f) orient=%ld (T=%d B=%d)", loc.x, loc.y, (long)orientation, inTopRegion, inBottomRegion);
            
            if (inTopRegion) {
                g_statusBarSwipeStartX = loc.x;
                g_statusBarSwipeStartY = loc.y;
                g_statusBarTouchActive = YES;
                g_statusBarSwipeHapticFired = NO;
                g_statusBarSwipeTriggered = NO;
                g_statusBarHoldTriggered = NO;
                
                if (touch.tapCount == 2) {
                    if (g_statusBarHoldTimer) {
                        [g_statusBarHoldTimer invalidate];
                        g_statusBarHoldTimer = nil;
                    }
                    g_pendingStatusBarTrigger = nil;
                    
                    load_trigger_config();
                    BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                                   [g_triggerConfig[@"triggers"][@"trigger_statusbar_double_tap"][@"enabled"] boolValue];
                    
                    if (enabled) {
                        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                        if (now - g_lastStatusBarDoubleTapTime > 0.4) {
                            g_lastStatusBarDoubleTapTime = now;
                            g_statusBarHoldTriggered = YES;
                            trigger_haptic();
                            RCExecuteTrigger(@"trigger_statusbar_double_tap");
                            SRLog(@"[RCStatus] Status Bar Double Tap FIRED!");
                        } else {
                            g_statusBarHoldTriggered = YES;
                            SRLog(@"[RCStatus] Status Bar Double Tap ignored (cooldown: %.3fs)", now - g_lastStatusBarDoubleTapTime);
                        }
                    }
                } else {
                    // Determine region for status bar hold (Left, Center, Right)
                    CGFloat progress = 0;
                    if (orientation == UIInterfaceOrientationPortrait) {
                        progress = loc.x / lw;
                    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
                        progress = 1.0 - (loc.x / lw);
                    } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
                        progress = 1.0 - (loc.y / lh);
                    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
                        progress = loc.y / lh;
                    }
                    
                    if (progress < 0.33) {
                        g_pendingStatusBarTrigger = @"trigger_statusbar_left_hold";
                    } else if (progress > 0.66) {
                        g_pendingStatusBarTrigger = @"trigger_statusbar_right_hold";
                    } else {
                        g_pendingStatusBarTrigger = @"trigger_statusbar_center_hold";
                    }
                    
                    SRLog(@"[RCStatus] Top Region Touch at progress=%.2f -> Key: %@", progress, g_pendingStatusBarTrigger);
                    
                    // Cancel any existing timer
                    if (g_statusBarHoldTimer) {
                        [g_statusBarHoldTimer invalidate];
                        g_statusBarHoldTimer = nil;
                    }
                    
                    // Start 0.3s hold timer
                    g_statusBarHoldTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *timer) {
                        g_statusBarHoldTimer = nil;
                        
                        // Ignore stale timer callbacks (e.g., touch already ended/cancelled).
                        if (!g_statusBarTouchActive || g_statusBarSwipeTriggered || !g_pendingStatusBarTrigger) {
                            return;
                        }

                        if (g_pendingStatusBarTrigger) {
                            load_trigger_config();
                            BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                                           [g_triggerConfig[@"triggers"][g_pendingStatusBarTrigger][@"enabled"] boolValue];
                            
                            if (enabled) {
                                g_statusBarHoldTriggered = YES;
                                trigger_haptic();
                                RCExecuteTrigger(g_pendingStatusBarTrigger);
                                SRLog(@"%@ FIRED!", g_pendingStatusBarTrigger);
                            }
                        }
                    }];
                }
            }
            
            // Bottom bar region = bottom 50pts
            if (inBottomRegion) {
                g_bottomBarSwipeStartX = loc.x;
                g_bottomBarSwipeStartY = loc.y;
                g_bottomBarTouchActive = YES;
                g_bottomBarHapticFired = NO;
            }
        }
        else if (touch && (touch.phase == UITouchPhaseMoved || touch.phase == UITouchPhaseEnded)) {
            CGPoint loc = [touch locationInView:nil];
            UIWindow *window = nil;
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            window = [UIApplication sharedApplication].keyWindow ?: [[UIApplication sharedApplication].windows firstObject];
            #pragma clang diagnostic pop
            UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            if (window && window.windowScene) orientation = window.windowScene.interfaceOrientation;
            else orientation = [UIApplication sharedApplication].statusBarOrientation;
            #pragma clang diagnostic pop

            BOOL isEnded = (touch.phase == UITouchPhaseEnded);
            
            if (g_statusBarTouchActive || g_bottomBarTouchActive) {
                CGFloat startX = g_statusBarTouchActive ? g_statusBarSwipeStartX : g_bottomBarSwipeStartX;
                CGFloat startY = g_statusBarTouchActive ? g_statusBarSwipeStartY : g_bottomBarSwipeStartY;
                
                CGFloat dx_phys = loc.x - startX;
                CGFloat dy_phys = loc.y - startY;
                
                CGFloat user_dx = 0;
                CGFloat user_dy = 0;
                
                if (orientation == UIInterfaceOrientationPortrait) {
                    user_dx = dx_phys; user_dy = dy_phys;
                } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
                    user_dx = -dx_phys; user_dy = -dy_phys;
                } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
                    user_dx = -dy_phys; user_dy = dx_phys;
                } else if (orientation == UIInterfaceOrientationLandscapeRight) {
                    user_dx = dy_phys; user_dy = -dx_phys;
                }

                CGFloat abs_udx = fabs(user_dx);
                CGFloat abs_udy = fabs(user_dy);
                BOOL isHoz = (abs_udx > abs_udy * 2.0);
                
                // --- Status Bar Moves ---
                if (g_statusBarTouchActive && !g_statusBarHoldTriggered) {
                    if ((abs_udx > 15 || abs_udy > 15) && g_statusBarHoldTimer) {
                        [g_statusBarHoldTimer invalidate];
                        g_statusBarHoldTimer = nil;
                        g_pendingStatusBarTrigger = nil;
                    }
                    
                    if (isHoz && abs_udx > 15 && !g_statusBarSwipeHapticFired) {
                        NSString *trigger = (user_dx > 0) ? @"trigger_statusbar_swipe_right" : @"trigger_statusbar_swipe_left";
                        load_trigger_config();
                        if ([g_triggerConfig[@"masterEnabled"] boolValue] && [g_triggerConfig[@"triggers"][trigger][@"enabled"] boolValue]) {
                            trigger_haptic();
                        }
                        g_statusBarSwipeHapticFired = YES;
                    }
                    
                    if (!g_statusBarSwipeTriggered && isHoz && abs_udx > 50) {
                        NSString *trigger = (user_dx > 0) ? @"trigger_statusbar_swipe_right" : @"trigger_statusbar_swipe_left";
                        RCExecuteTrigger(trigger);
                        g_statusBarSwipeTriggered = YES;
                    }
                }
                
                // --- Bottom Bar Moves ---
                if (g_bottomBarTouchActive && !g_bottomBarHapticFired) {
                    if (isHoz && abs_udx > 15) {
                        NSString *trigger = (user_dx > 0) ? @"trigger_bottombar_swipe_right" : @"trigger_bottombar_swipe_left";
                        load_trigger_config();
                        if ([g_triggerConfig[@"masterEnabled"] boolValue] && [g_triggerConfig[@"triggers"][trigger][@"enabled"] boolValue]) {
                            trigger_haptic();
                        }
                        g_bottomBarHapticFired = YES;
                    }
                }
                
                // --- Gesture Finalized ---
                if (isEnded) {
                    if (g_statusBarHoldTimer) {
                        [g_statusBarHoldTimer invalidate];
                        g_statusBarHoldTimer = nil;
                    }
                    g_pendingStatusBarTrigger = nil;

                    if (g_statusBarTouchActive && !g_statusBarHoldTriggered && !g_statusBarSwipeTriggered) {
                        if (isHoz && abs_udx > 40) {
                            NSString *trigger = (user_dx > 0) ? @"trigger_statusbar_swipe_right" : @"trigger_statusbar_swipe_left";
                            RCExecuteTrigger(trigger);
                        }
                    }
                    if (g_bottomBarTouchActive) {
                        if (isHoz && abs_udx > 60) {
                            NSString *trigger = (user_dx > 0) ? @"trigger_bottombar_swipe_right" : @"trigger_bottombar_swipe_left";
                            RCExecuteTrigger(trigger);
                        }
                    }
                    SRLog(@"[Debug] Ended: user_dx=%.1f user_dy=%.1f orient=%ld isHoz=%d", user_dx, user_dy, (long)orientation, isHoz);
                    g_statusBarTouchActive = NO;
                    g_bottomBarTouchActive = NO;
                    g_statusBarHoldTriggered = NO;
                }
            }
        }
        else if (touch && touch.phase == UITouchPhaseCancelled) {
            if (g_statusBarHoldTimer) {
                [g_statusBarHoldTimer invalidate];
                g_statusBarHoldTimer = nil;
            }
            g_statusBarHoldTriggered = NO;
            g_pendingStatusBarTrigger = nil;
            g_statusBarTouchActive = NO;
            g_bottomBarTouchActive = NO;
            g_bottomBarHapticFired = NO;
        }
    }
    
    %orig;
}

%end

@implementation SREdgeGestureRecognizer

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // Early exit: Check if edge gestures should even be active
    if (!should_register_edge_gestures()) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    
    UITouch *touch = [touches anyObject];
    CGPoint loc = [touch locationInView:nil];
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    
    // Check if touch is near edge (within 25pt) - narrower as requested
    CGFloat edgeThreshold = 25.0;
    
    // Check vertical margins to avoid interference with Control Center (top) and Home Swipe (bottom)
    CGFloat verticalMargin = 100.0;
    
    BOOL isNearLeft = (loc.x < edgeThreshold);
    BOOL isNearRight = (loc.x > screenSize.width - edgeThreshold);
    BOOL isWithinVerticalBounds = (loc.y > verticalMargin) && (loc.y < screenSize.height - verticalMargin);
    
    if (!isWithinVerticalBounds) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    
    if (self.isLeftEdge && !isNearLeft) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    
    if (self.isRightEdge && !isNearRight) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }

    [super touchesBegan:touches withEvent:event];
    self.hasTriggered = NO;
    SRLog(@"Edge Gesture touchesBegan: X=%.2f Y=%.2f", loc.x, loc.y);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    // State tracking and haptics now handled in handleEdgeGesture:
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    SRLog(@"Edge Gesture touchesEnded - State before super: %ld", (long)self.state);
    [super touchesEnded:touches withEvent:event];
    SRLog(@"Edge Gesture touchesEnded - State after super: %ld", (long)self.state);
}

@end

// --- SYSTEM GESTURE MANAGER HOOK ---

@interface SRGestureHelper : NSObject
+ (instancetype)sharedInstance;
- (void)handleEdgeGesture:(SREdgeGestureRecognizer *)gesture;
@end

@implementation SRGestureHelper
+ (instancetype)sharedInstance {
    static SRGestureHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SRGestureHelper alloc] init];
    });
    return sharedInstance;
}

- (void)handleEdgeGesture:(SREdgeGestureRecognizer *)gesture {
    // Instant Fire: Trigger as soon as Changed state hits threshold
    if (gesture.state == UIGestureRecognizerStateChanged && !gesture.hasTriggered) {
        CGPoint translation = [gesture translationInView:nil];
        CGFloat verticalSwipeDistance = fabs(translation.y);
        CGFloat horizontalDrift = fabs(translation.x);
        
        // Threshold: 30pt for instant trigger
        if (verticalSwipeDistance > 30 && horizontalDrift < 100) {
            SRLog(@"Instant Edge Trigger! V=%.2f H=%.2f", verticalSwipeDistance, horizontalDrift);
            
            gesture.hasTriggered = YES;

            NSString *triggerKey = nil;
            if (gesture.isLeftEdge) {
                triggerKey = (translation.y < 0) ? @"trigger_edge_left_swipe_up" : @"trigger_edge_left_swipe_down";
            } else if (gesture.isRightEdge) {
                triggerKey = (translation.y < 0) ? @"trigger_edge_right_swipe_up" : @"trigger_edge_right_swipe_down";
            }
            
            if (triggerKey) {
                load_trigger_config();
                BOOL enabled = [g_triggerConfig[@"masterEnabled"] boolValue] && 
                               [g_triggerConfig[@"triggers"][triggerKey][@"enabled"] boolValue];
                
                if (enabled) {
                    // Haptic feedback ONLY if enabled
                    trigger_haptic();
                    RCExecuteTrigger(triggerKey);
                    SRLog(@"%@ FIRED INSTANTLY!", triggerKey);
                } else {
                    SRLog(@"%@ detected (disabled)", triggerKey);
                }
            }
        }
    }
    
    // Reset state on finish/fail
    if (gesture.state == UIGestureRecognizerStateEnded || 
        gesture.state == UIGestureRecognizerStateCancelled || 
        gesture.state == UIGestureRecognizerStateFailed) {
        SRLog(@"Edge Gesture Finished (State %ld): hasTriggered=%d", (long)gesture.state, gesture.hasTriggered);
        gesture.hasTriggered = NO;
    }
}
@end

static SREdgeGestureRecognizer *leftEdgeRecognizer;
static SREdgeGestureRecognizer *rightEdgeRecognizer;
static SBSystemGestureManager *g_gestureManager = nil;

// Helper: Check if any edge gestures are enabled
static BOOL should_register_edge_gestures() {
    if (!g_triggerConfig) return NO;
    if (![g_triggerConfig[@"masterEnabled"] boolValue]) return NO;
    
    NSDictionary *triggers = g_triggerConfig[@"triggers"];
    NSArray *edgeTriggers = @[@"trigger_edge_left_swipe_up", 
                               @"trigger_edge_left_swipe_down",
                               @"trigger_edge_right_swipe_up",
                               @"trigger_edge_right_swipe_down"];
    
    for (NSString *key in edgeTriggers) {
        NSDictionary *trigger = triggers[key];
        if (trigger && [trigger[@"enabled"] boolValue]) {
            return YES; // At least one edge gesture is enabled
        }
    }
    
    return NO;
}

// Register gesture recognizers
static void register_edge_gestures() {
    if (!g_gestureManager) {
        g_gestureManager = [%c(SBSystemGestureManager) mainDisplayManager];
        if (!g_gestureManager) {
            SRLog(@"ERROR: Could not find mainDisplayManager");
            return;
        }
    }
    
    // Left Edge
    if (!leftEdgeRecognizer) {
        leftEdgeRecognizer = [[SREdgeGestureRecognizer alloc] initWithTarget:[SRGestureHelper sharedInstance] action:@selector(handleEdgeGesture:)];
        leftEdgeRecognizer.isLeftEdge = YES;
        leftEdgeRecognizer.cancelsTouchesInView = NO; // Don't block other touches by default
        leftEdgeRecognizer.delaysTouchesBegan = NO;   // Don't add lag
        [g_gestureManager addGestureRecognizer:leftEdgeRecognizer withType:120];
        SRLog(@"Registered LEFT edge gesture recognizer");
    }
    
    // Right Edge
    if (!rightEdgeRecognizer) {
        rightEdgeRecognizer = [[SREdgeGestureRecognizer alloc] initWithTarget:[SRGestureHelper sharedInstance] action:@selector(handleEdgeGesture:)];
        rightEdgeRecognizer.isRightEdge = YES;
        rightEdgeRecognizer.cancelsTouchesInView = NO; // Don't block other touches by default
        rightEdgeRecognizer.delaysTouchesBegan = NO;   // Don't add lag
        [g_gestureManager addGestureRecognizer:rightEdgeRecognizer withType:121];
        SRLog(@"Registered RIGHT edge gesture recognizer");
    }
}

// Unregister gesture recognizers
static void unregister_edge_gestures() {
    if (leftEdgeRecognizer) {
        if (leftEdgeRecognizer.view) {
            [leftEdgeRecognizer.view removeGestureRecognizer:leftEdgeRecognizer];
        }
        leftEdgeRecognizer = nil;
        SRLog(@"Unregistered LEFT edge gesture recognizer");
    }
    
    if (rightEdgeRecognizer) {
        if (rightEdgeRecognizer.view) {
            [rightEdgeRecognizer.view removeGestureRecognizer:rightEdgeRecognizer];
        }
        rightEdgeRecognizer = nil;
        SRLog(@"Unregistered RIGHT edge gesture recognizer");
    }
}

// Update gesture registration based on config
static void update_edge_gestures() {
    @try {
        BOOL shouldRegister = should_register_edge_gestures();
        BOOL currentlyRegistered = (leftEdgeRecognizer != nil || rightEdgeRecognizer != nil);
        
        if (shouldRegister && !currentlyRegistered) {
            SRLog(@"Edge gestures enabled - registering...");
            register_edge_gestures();
        } else if (!shouldRegister && currentlyRegistered) {
            SRLog(@"Edge gestures disabled - unregistering...");
            unregister_edge_gestures();
        } else if (shouldRegister && currentlyRegistered) {
            // SRLog(@"Edge gestures already registered and should be");
        } else {
            // SRLog(@"Edge gestures not needed and not registered");
        }
    } @catch (NSException *e) {
        SRLog(@"ERROR in update_edge_gestures: %@", e);
    }
}


%hook SBUIController

- (void)ACPowerChanged {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        handle_power_state_transition(is_device_power_connected(), @"SBUIController ACPowerChanged");
    });
}

- (void)updateBatteryState:(id)arg1 {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        handle_power_state_transition(is_device_power_connected(), @"SBUIController updateBatteryState");
    });
}

- (void)setIsACPowerConnected:(BOOL)arg1 {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        handle_power_state_transition(arg1, @"SBUIController setIsACPowerConnected");
    });
}

%end


static NSTimeInterval s_last_camera_app_trigger = 0;

static void rc_camera_launched_notification_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now - s_last_camera_app_trigger > 2.0) {
            s_last_camera_app_trigger = now;
            g_currentAppBundleId = @"com.apple.camera";
            SRLog(@"[AppLaunch] Camera App Launched event received (lockscreen or unlocked), triggering app_launch_com.apple.camera");
            RCExecuteTrigger(@"app_launch_com.apple.camera");
        }
    });
}

%hook SpringBoard

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        SRLog(@"[Trigger] Shake detected");
        RCExecuteTrigger(@"shake");
    }
    %orig;
}

- (void)frontDisplayDidChange:(id)arg1 {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
            SBApplication *frontApp = [self _accessibilityFrontMostApplication];
            NSString *bundleId = [frontApp bundleIdentifier];
            
            // Track previous app for the 'previous app' action
            if ((bundleId && ![bundleId isEqualToString:g_currentAppBundleId]) || (!bundleId && g_currentAppBundleId)) {
                if (g_currentAppBundleId && ![g_currentAppBundleId isEqualToString:@"com.apple.springboard"]) {
                    g_previousAppBundleId = g_currentAppBundleId;
                }
                g_currentAppBundleId = bundleId;
            }
            
            static NSString *lastApp = nil;
            NSString *effectiveBundleId = bundleId ?: @"com.apple.springboard";
            if (![effectiveBundleId isEqualToString:lastApp]) {
                lastApp = effectiveBundleId;
                if ([effectiveBundleId isEqualToString:@"com.apple.camera"]) {
                    s_last_camera_app_trigger = [[NSDate date] timeIntervalSince1970];
                }
                SRLog(@"[AppLaunch] App became Active: %@", effectiveBundleId);
                NSString *triggerKey = [NSString stringWithFormat:@"app_launch_%@", effectiveBundleId];
                RCExecuteTrigger(triggerKey);
            }
        }
    });
}

%end

%hook SBSystemGestureManager

- (void)addGestureRecognizer:(UIGestureRecognizer *)recognizer withType:(NSUInteger)type {
    %orig;
}

%end

%hook BBServer
- (void)publishBulletin:(id)bulletin destinations:(NSUInteger)destinations {
    %orig;
    if (!bulletin) return;
    if (!g_triggerConfig) return;
    
    NSString *bundleId = [bulletin performSelector:@selector(sectionID)];
    NSString *title = [bulletin performSelector:@selector(title)] ?: @"";
    NSString *subtitle = [bulletin performSelector:@selector(subtitle)] ?: @"";
    NSString *message = [bulletin performSelector:@selector(message)] ?: @"";
    
    NSArray *triggers = g_triggerConfig[@"notificationTriggers"];
    for (NSDictionary *trigger in triggers) {
        if (![trigger[@"enabled"] boolValue]) continue;
        
        NSString *matchBundleId = trigger[@"bundleId"];
        NSString *overrideBundleId = trigger[@"overrideBundleId"];
        
        if (matchBundleId && matchBundleId.length > 0) {
            BOOL matches = [matchBundleId isEqualToString:bundleId];
            if (!matches && [matchBundleId isEqualToString:@"com.shazam.Shazam"] && [bundleId isEqualToString:@"com.apple.ShazamNotifications"]) {
                matches = YES;
            }
            if (!matches && overrideBundleId && overrideBundleId.length > 0 && [overrideBundleId isEqualToString:bundleId]) {
                matches = YES;
            }
            if (!matches) continue;
        } else if (overrideBundleId && overrideBundleId.length > 0) {
            if (![overrideBundleId isEqualToString:bundleId]) continue;
        }
        
        NSString *textMatch = trigger[@"textMatch"];
        if (textMatch && textMatch.length > 0) {
            BOOL found = ([title rangeOfString:textMatch options:NSCaseInsensitiveSearch].location != NSNotFound) ||
                         ([subtitle rangeOfString:textMatch options:NSCaseInsensitiveSearch].location != NSNotFound) ||
                         ([message rangeOfString:textMatch options:NSCaseInsensitiveSearch].location != NSNotFound);
            if (!found) continue;
        }
        
        NSString *triggerKey = trigger[@"triggerKey"];
        if (triggerKey) {
            SRLog(@"[RCNotif] Triggering %@ for notification from %@", triggerKey, bundleId);
            RCExecuteTrigger(triggerKey);
        }
    }
}
%end

// ==========================================
// Camera App Hooks (com.apple.camera)
// ==========================================

@interface CAMViewfinderViewController : UIViewController
- (void)changeToCaptureMode:(NSInteger)mode device:(NSInteger)device animated:(BOOL)animated;
- (void)changeToCaptureMode:(NSInteger)mode animated:(BOOL)animated;
- (void)changeToCaptureMode:(NSInteger)mode;
- (void)changeToZoomFactor:(double)zoom animated:(BOOL)animated;
- (void)setZoomFactor:(double)zoom;
- (void)_setZoomFactor:(double)zoom;
- (id)zoomControl;
@end

@interface CAMZoomControl : UIControl
- (void)setZoomFactor:(double)zoom animated:(BOOL)animated;
- (void)setZoomFactor:(double)zoom;
- (void)setSelectedZoomFactor:(double)zoom;
@end

%group CameraHook

static NSTimeInterval s_last_shutter_time = 0;
static NSString *s_last_intent_uuid = nil;
static NSString *s_last_autoshutter_uuid = nil;

static void rc_trigger_camera_shutter(id viewfinder) {
    if (!viewfinder) return;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - s_last_shutter_time < 1.2) {
        SRLog(@"[CameraHook] rc_trigger_camera_shutter debounced (%.2fs ago)", now - s_last_shutter_time);
        return;
    }
    s_last_shutter_time = now;
    SRLog(@"[CameraHook] rc_trigger_camera_shutter executing on %@", viewfinder);
    
    // Method 1: CameraUI Master Shutter Handler
    if ([viewfinder respondsToSelector:@selector(_handleShutterButtonActionWithEventTriggerDescription:)]) {
        SRLog(@"[CameraHook] Calling _handleShutterButtonActionWithEventTriggerDescription:");
        ((void (*)(id, SEL, id))objc_msgSend)(viewfinder, @selector(_handleShutterButtonActionWithEventTriggerDescription:), @"RemoteCompanion");
        return;
    }
    
    // Method 2: capturePhoto / direct capture
    if ([viewfinder respondsToSelector:@selector(capturePhoto)]) {
        SRLog(@"[CameraHook] Calling capturePhoto");
        ((void (*)(id, SEL))objc_msgSend)(viewfinder, @selector(capturePhoto));
        return;
    }
    
    // Method 3: CAMViewfinderViewController direct methods
    if ([viewfinder respondsToSelector:@selector(pressShutterButton)]) {
        SRLog(@"[CameraHook] Calling pressShutterButton");
        ((void (*)(id, SEL))objc_msgSend)(viewfinder, @selector(pressShutterButton));
        return;
    }
    
    // Method 4: Check for shutterButton property
    if ([viewfinder respondsToSelector:@selector(shutterButton)]) {
        id sb = [viewfinder performSelector:@selector(shutterButton)];
        if (sb) {
            SRLog(@"[CameraHook] Found shutterButton: %@", sb);
            if ([sb respondsToSelector:@selector(sendActionsForControlEvents:)]) {
                [sb performSelector:@selector(sendActionsForControlEvents:) withObject:@(UIControlEventTouchUpInside)];
                return;
            }
        }
    }
    
    // Method 5: Check bottomBar / shutterControl / viewfinder controls
    if ([viewfinder respondsToSelector:@selector(bottomBar)]) {
        id bb = [viewfinder performSelector:@selector(bottomBar)];
        if (bb && [bb respondsToSelector:@selector(shutterButton)]) {
            id sb = [bb performSelector:@selector(shutterButton)];
            if (sb && [sb respondsToSelector:@selector(sendActionsForControlEvents:)]) {
                SRLog(@"[CameraHook] Found bottomBar shutterButton: %@", sb);
                [sb performSelector:@selector(sendActionsForControlEvents:) withObject:@(UIControlEventTouchUpInside)];
                return;
            }
        }
    }
    
    // Method 6: Simulated tap on physical/UI shutter button location
    rc_load_touch_symbols();
    CGSize s = [UIScreen mainScreen].bounds.size;
    double sw = MIN(s.width, s.height);
    double sh = MAX(s.width, s.height);
    if (sw <= 0) sw = 375.0;
    if (sh <= 0) sh = 667.0;
    SRLog(@"[CameraHook] Simulating tap on shutter at (%.1f, %.1f)", sw * 0.50, sh * 0.88);
    rc_simulate_tap(sw * 0.50, sh * 0.88);
}

static void rc_camera_shutter_notification_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    id vf = (__bridge id)observer;
    if (vf) {
        dispatch_async(dispatch_get_main_queue(), ^{
            rc_trigger_camera_shutter(vf);
        });
    }
}

static void rc_apply_camera_intent_to_viewfinder(id viewfinder) {
    if (!viewfinder) return;
    NSDictionary *intent = [NSDictionary dictionaryWithContentsOfFile:@"/tmp/rc_camera_intent.plist"];
    if (!intent) return;
    
    NSTimeInterval ts = [intent[@"timestamp"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - ts > 12.0) return; // Expired (older than 12 seconds)
    
    NSString *uuid = intent[@"uuid"];
    if (uuid && [uuid isEqualToString:s_last_intent_uuid]) {
        return; // Already processed this intent
    }
    s_last_intent_uuid = [uuid copy];
    
    NSInteger targetMode = [intent[@"mode"] integerValue];
    NSInteger targetDevice = [intent[@"device"] integerValue]; // 0 = Back, 1 = Front
    double targetZoom = [intent[@"zoom"] doubleValue];
    if (targetZoom <= 0) targetZoom = (targetMode == 1 && targetDevice == 0) ? 2.0 : 1.0;
    NSInteger targetFlash = [intent[@"flash"] integerValue]; // 1 = Flash / Torch ON
    BOOL autoShutter = [intent[@"autoShutter"] boolValue];
    
    SRLog(@"[CameraHook] Executing intent (UUID=%@): targetMode=%ld, targetDevice=%ld, targetZoom=%.1f, targetFlash=%ld, autoShutter=%d on %@", 
          uuid, (long)targetMode, (long)targetDevice, targetZoom, (long)targetFlash, autoShutter, viewfinder);
    
    // 1. Primary Mode & Device Switch
    if ([viewfinder respondsToSelector:@selector(_handleUserChangedToMode:device:zoomFactor:)]) {
        SRLog(@"[CameraHook] Invoking _handleUserChangedToMode:%ld device:%ld zoomFactor:%.1f", (long)targetMode, (long)targetDevice, targetZoom);
        ((void (*)(id, SEL, NSInteger, NSInteger, double))objc_msgSend)(viewfinder, @selector(_handleUserChangedToMode:device:zoomFactor:), targetMode, targetDevice, targetZoom);
    } else if ([viewfinder respondsToSelector:@selector(changeToCaptureMode:device:animated:)]) {
        [viewfinder changeToCaptureMode:targetMode device:targetDevice animated:NO];
    }
    
    // 2. Zoom Control Notification
    if (targetDevice == 0 && [viewfinder respondsToSelector:@selector(zoomControl:didChangeZoomFactor:interactionType:)]) {
        id zc = nil;
        if ([viewfinder respondsToSelector:@selector(zoomControl)]) {
            zc = [viewfinder performSelector:@selector(zoomControl)];
        }
        ((void (*)(id, SEL, id, double, NSInteger))objc_msgSend)(viewfinder, @selector(zoomControl:didChangeZoomFactor:interactionType:), zc, targetZoom, 1);
    }
    
    // 3. Mode Dial fallback
    if ([viewfinder respondsToSelector:@selector(modeDial)]) {
        id dial = [viewfinder performSelector:@selector(modeDial)];
        if (dial && [dial respondsToSelector:@selector(setSelectedMode:animated:)]) {
            [dial performSelector:@selector(setSelectedMode:animated:) withObject:@(targetMode) withObject:@(NO)];
        }
    }
    
    // 4. Flash / Torch Control (applied cleanly once capture session is ready)
    if (targetFlash == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SRLog(@"[CameraHook] Engaging Flash/Torch ON once");
            if ([viewfinder respondsToSelector:@selector(_setResolvedTorchMode:animated:)]) {
                ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(viewfinder, @selector(_setResolvedTorchMode:animated:), 1, NO);
            }
            if ([viewfinder respondsToSelector:@selector(_handleUserChangedTorchMode:)]) {
                ((void (*)(id, SEL, NSInteger))objc_msgSend)(viewfinder, @selector(_handleUserChangedTorchMode:), 1);
            }
            if ([viewfinder respondsToSelector:@selector(_setResolvedFlashMode:)]) {
                ((void (*)(id, SEL, NSInteger))objc_msgSend)(viewfinder, @selector(_setResolvedFlashMode:), 1);
            }
            if ([viewfinder respondsToSelector:@selector(_handleUserChangedFlashMode:)]) {
                ((void (*)(id, SEL, NSInteger))objc_msgSend)(viewfinder, @selector(_handleUserChangedFlashMode:), 1);
            }
            if ([viewfinder respondsToSelector:@selector(remoteShutter:setFlashMode:)]) {
                ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(viewfinder, @selector(remoteShutter:setFlashMode:), nil, 1);
            }
            if ([viewfinder respondsToSelector:@selector(torchButton)]) {
                id tb = [viewfinder performSelector:@selector(torchButton)];
                if (tb && [tb respondsToSelector:@selector(setTorchMode:animated:)]) {
                    ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(tb, @selector(setTorchMode:animated:), 1, NO);
                } else if (tb && [tb respondsToSelector:@selector(setTorchMode:)]) {
                    ((void (*)(id, SEL, NSInteger))objc_msgSend)(tb, @selector(setTorchMode:), 1);
                }
            }
        });
    }
    
    // 5. Auto Shutter trigger (fires exactly once if requested)
    if (autoShutter) {
        if (!uuid || ![uuid isEqualToString:s_last_autoshutter_uuid]) {
            s_last_autoshutter_uuid = [uuid copy];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.80 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SRLog(@"[CameraHook] Auto-triggering shutter once for intent %@...", uuid);
                rc_trigger_camera_shutter(viewfinder);
            });
        }
    }
}

static void rc_camera_intent_notification_callback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    id vf = (__bridge id)observer;
    if (vf) {
        dispatch_async(dispatch_get_main_queue(), ^{
            rc_apply_camera_intent_to_viewfinder(vf);
        });
    }
}

%hook CAMViewfinderViewController

static NSTimeInterval s_last_camera_launch_notify = 0;

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SRLog(@"[CameraHook] viewDidAppear called on %@", self);
    rc_apply_camera_intent_to_viewfinder(self);
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - s_last_camera_launch_notify > 2.0) {
        s_last_camera_launch_notify = now;
        SRLog(@"[CameraHook] Posting com.saihgupr.remotecompanion.camera_launched");
        notify_post("com.saihgupr.remotecompanion.camera_launched");
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SRLog(@"[CameraHook] viewWillAppear called on %@", self);
    rc_apply_camera_intent_to_viewfinder(self);
}

- (void)viewDidLoad {
    %orig;
    SRLog(@"[CameraHook] viewDidLoad called on %@", self);
    
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        (CFNotificationCallback)rc_camera_intent_notification_callback,
        CFSTR("com.saihgupr.remotecompanion.camera_intent"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        (CFNotificationCallback)rc_camera_shutter_notification_callback,
        CFSTR("com.saihgupr.remotecompanion.camera_shutter"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        CFSTR("com.saihgupr.remotecompanion.camera_intent"),
        NULL
    );
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        CFSTR("com.saihgupr.remotecompanion.camera_shutter"),
        NULL
    );
    %orig;
}

%end

%end

%ctor {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleID isEqualToString:@"com.apple.springboard"]) {
        %init(_ungrouped);
        
        SRLog(@"Tweak Loaded in %@ - Starting Initialization...", bundleID);
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)rc_camera_launched_notification_callback,
            CFSTR("com.saihgupr.remotecompanion.camera_launched"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        // Start Background HID Listener immediately (safe for NFC)
        setup_background_hid_listener();
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SRLog(@"Delayed Initialization & Gesture Setup...");
            
            load_trigger_config();
            register_config_observer();
            register_simulation_observers();
            register_system_event_observers(); // WiFi/BT Triggers
            start_server();
            start_web_server();
            start_schedule_timer();
            start_mqtt_subscriber();
            
            // Conditionally register edge gestures based on config
            update_edge_gestures();
            
            SRLog(@"Initialization Complete.");
        });
    } else if ([bundleID isEqualToString:@"com.apple.camera"]) {
        %init(CameraHook);
        SRLog(@"[RemoteCompanion] Loaded inside com.apple.camera");
    } else {
        SRLog(@"Tweak Loaded in %@ - Skipping Full Initialization (Choicy Visibility Only)", bundleID);
    }
}
