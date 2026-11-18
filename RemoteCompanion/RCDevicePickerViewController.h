#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, RCDevicePickerKind) {
    RCDevicePickerKindBluetooth, // the phone's paired devices
    RCDevicePickerKindAirPlay,   // the AirPlay outputs reachable right now
    RCDevicePickerKindWatchFace, // faces on the paired Apple Watch
};

// A searchable list of Bluetooth or AirPlay devices fetched from the tweak, with an icon per
// device type. Used when adding or editing the Bluetooth Connect / Disconnect and AirPlay
// Connect actions. Shows a Cancel button when it's the root of a presented navigation stack.
@interface RCDevicePickerViewController : UITableViewController

- (instancetype)initWithKind:(RCDevicePickerKind)kind title:(NSString *)title;

// The device name the action uses now: shown ticked (or listed as "Not Found")
@property (nonatomic, copy) NSString *currentDevice;
// device: @{ @"name": ..., @"target": ... } - target is what goes after "bt connect " /
// "airplay connect " ("UID # Name" for AirPlay when the UID is known). The caller closes
// the picker.
@property (nonatomic, copy) void (^onDeviceSelected)(NSDictionary *device);

@end
