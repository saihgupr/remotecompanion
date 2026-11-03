#import <UIKit/UIKit.h>

// The one toast pill. Both the on-device HUD (Tweak's rc_show_hud_toast_ex)
// and the app's toast editor preview build their pill through this class, so
// the two cannot drift apart. Every metric below matches the native ringer
// HUD look the tweak has always drawn: callers only add presentation around
// it (window/animation on device, table-row embedding in the editor).
@interface RCToastPillView : UIView

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                     iconName:(NSString *)iconName;

@property (nonatomic, copy) NSString *pillTitle;
@property (nonatomic, copy) NSString *pillMessage;
@property (nonatomic, copy) NSString *pillIconName;

// Editor-only affordance: when YES and the title is empty, the pill shows a
// dim "Title" placeholder so the row never looks broken while typing. The
// on-device toast never sets this (a fired toast always has a title).
@property (nonatomic, assign) BOOL showsPlaceholderTitle;

// Test-kit prompts let a long message wrap instead of truncating. Normal
// toasts keep this NO (single line, truncated tail).
@property (nonatomic, assign) BOOL wrapsMessage;

+ (BOOL)hasIconForName:(NSString *)iconName;
+ (CGFloat)maxPillWidthForScreenWidth:(CGFloat)screenWidth;
+ (CGSize)sizeForTitle:(NSString *)title
               message:(NSString *)message
              iconName:(NSString *)iconName
          wrapsMessage:(BOOL)wrap
              maxWidth:(CGFloat)maxWidth;

+ (UIFont *)pillTitleFont;
+ (UIFont *)pillMessageFont;

@end
