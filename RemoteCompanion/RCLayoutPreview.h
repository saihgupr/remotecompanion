#import <UIKit/UIKit.h>

// Settings > Layout's preview: a small copy of one screen (Triggers, New Trigger, Select Action or
// Banners) as its Layout settings draw it, built from the app's own grid, tiles, rows and category
// bar with sample triggers and actions. It follows each change to the screen it shows; the page's
// screen control (above the settings) picks which one.
@interface RCLayoutPreview : UIView
- (instancetype)initWithWidth:(CGFloat)width;
// Shows this screen (a Layout screen's key)
- (void)showScreen:(NSString *)screen;
// The height it needs at its width
+ (CGFloat)heightForWidth:(CGFloat)width;
@end
