// A Control Center button that runs a Control Center Button trigger.
//
// Built once per slot (see the Makefile): RC_CC_SLOT is 1...8 and RC_CC_CLASS the class name.
// The module is loaded by CCSupport into SpringBoard. It only draws the trigger's icon and, on
// a tap, posts a Darwin notification the tweak (also in SpringBoard) is listening for.
// Keep it small: a crash here is a crash in SpringBoard.
#import <UIKit/UIKit.h>
#import <notify.h>
#import <ControlCenterUIKit/CCUIToggleModule.h>

#ifndef RC_CC_SLOT
#define RC_CC_SLOT 1
#endif
#ifndef RC_CC_CLASS
#define RC_CC_CLASS RCCCButton1
#endif

#define RC_STR_(x) #x
#define RC_STR(x) RC_STR_(x)

static NSString *const kRCCCConfigPath = @"/var/mobile/Documents/rc_triggers.plist";
static NSString *const kRCCCDefaultSymbol = @"bolt.fill";

@interface RC_CC_CLASS : CCUIToggleModule
@end

@implementation RC_CC_CLASS {
    UIImage *_glyph;
    NSDate *_glyphConfigDate;
}

// The icon the trigger was given, as a template image the way Control Center draws its own
- (UIImage *)iconGlyph {
    NSDate *modified = [[[NSFileManager defaultManager] attributesOfItemAtPath:kRCCCConfigPath error:nil] fileModificationDate];
    if (_glyph && (modified == _glyphConfigDate || [modified isEqualToDate:_glyphConfigDate])) return _glyph;

    NSString *symbol = nil;
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:kRCCCConfigPath];
    NSDictionary *triggers = [config[@"triggers"] isKindOfClass:[NSDictionary class]] ? config[@"triggers"] : nil;
    NSDictionary *trigger = triggers[@"trigger_cc_button_" RC_STR(RC_CC_SLOT)];
    if ([trigger isKindOfClass:[NSDictionary class]] && [trigger[@"icon"] isKindOfClass:[NSString class]]) symbol = trigger[@"icon"];

    UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
    UIImage *image = symbol.length ? [UIImage systemImageNamed:symbol withConfiguration:size] : nil;
    if (!image) image = [UIImage systemImageNamed:kRCCCDefaultSymbol withConfiguration:size];
    _glyph = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _glyphConfigDate = modified;
    return _glyph;
}

- (UIImage *)selectedIconGlyph {
    return [self iconGlyph];
}

- (UIColor *)selectedColor {
    return [UIColor systemBlueColor];
}

// A press, not a switch: never stays on
- (BOOL)isSelected {
    return NO;
}

- (void)setSelected:(BOOL)selected {
    if (selected) notify_post("com.saihgupr.remotecompanion.ccbutton." RC_STR(RC_CC_SLOT));
    [self refreshState];
}

@end

