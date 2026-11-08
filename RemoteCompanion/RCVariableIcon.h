#import <UIKit/UIKit.h>

// The Variables menu icon: an orange italic x, in the style of Shortcuts' variable glyph.
// The default is 29 points; sized versions keep the same proportions for action rows.
// ActionSized returns a template image with a 1.25x glyph for the normal action icon tint.
UIImage *RCVariableMenuIcon(void);
UIImage *RCVariableMenuIconSized(CGFloat side);
UIImage *RCVariableMenuIconActionSized(CGFloat side);
