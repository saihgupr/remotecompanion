// Swipe Triggers > Adjust on Screen, in SpringBoard (see RCSwipeZones.h).
//
// The overlay is a window above every app and the Dynamic Island. It takes only the touches on its
// handles, its panel and its side button; every other touch goes to the app beneath, so a swipe
// trigger can be tried against the zones as they're drawn. While it's open SpringBoard's edge
// gestures are held back (two swipes up still go Home; see RC_ZoneEditorOpen in Tweak.x), and
// while a handle is dragged swipe and button triggers are paused.

#import "RCSwipeZones.h"
#import <notify.h>
#import <objc/message.h>

typedef NS_ENUM(NSInteger, RCZonesMode) {
    RCZonesModeZones,
    RCZonesModeDistances,
};

// One setting with a handle: its config key, name, default and range, and which view it's in
@interface RCZoneSetting : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) double defaultValue, minValue, maxValue;
@property (nonatomic) BOOL percent;
@property (nonatomic) RCZonesMode mode;
@end
@implementation RCZoneSetting
@end

static RCZoneSetting *RCZoneMake(NSString *key, NSString *title, double def, double min, double max, BOOL percent, RCZonesMode mode) {
    RCZoneSetting *s = [RCZoneSetting new];
    s.key = key; s.title = title; s.defaultValue = def; s.minValue = min; s.maxValue = max; s.percent = percent; s.mode = mode;
    return s;
}

// The same keys and defaults as Swipe Triggers' rows in the app and RC_SwipeSetting in Tweak.x
static NSArray<RCZoneSetting *> *RCZoneSettings(void) {
    static NSArray *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        settings = @[
            RCZoneMake(@"swipeStatusBarHeight", @"Status Bar Height", 25, 10, 100, NO, RCZonesModeZones),
            RCZoneMake(@"swipeStatusBarLeftZone", @"Status Bar Left Zone", 33, 5, 60, YES, RCZonesModeZones),
            RCZoneMake(@"swipeStatusBarRightZone", @"Status Bar Right Zone", 33, 5, 60, YES, RCZonesModeZones),
            RCZoneMake(@"swipeEdgeStrip", @"Edge Strip", 25, 10, 60, NO, RCZonesModeZones),
            RCZoneMake(@"swipeBottomZoneHeight", @"Bottom Zone Height", 25, 10, 100, NO, RCZonesModeZones),
            RCZoneMake(@"swipeBottomLeftZone", @"Bottom Left Zone", 33, 5, 60, YES, RCZonesModeZones),
            RCZoneMake(@"swipeBottomRightZone", @"Bottom Right Zone", 33, 5, 60, YES, RCZonesModeZones),
            RCZoneMake(@"swipeStatusBarDistance", @"Status Bar Swipe", 50, 10, 250, NO, RCZonesModeDistances),
            RCZoneMake(@"swipeTopDownDistance", @"Top Swipe Down", 45, 10, 250, NO, RCZonesModeDistances),
            RCZoneMake(@"swipeEdgeDistance", @"Edge Swipe", 30, 10, 250, NO, RCZonesModeDistances),
            RCZoneMake(@"swipeBottomBarDistance", @"Bottom Bar Swipe", 60, 10, 250, NO, RCZonesModeDistances),
            RCZoneMake(@"swipeBottomUpDistance", @"Bottom Swipe Up", 45, 10, 250, NO, RCZonesModeDistances),
        ];
    });
    return settings;
}

static NSString *RCZoneValueText(RCZoneSetting *s, double value) {
    return [NSString stringWithFormat:s.percent ? @"%.0f%%" : @"%.0f pt", value];
}

@class RCZonesCanvas;

@interface RCZonesController : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) RCZonesCanvas *canvas;
@property (nonatomic, strong) UIVisualEffectView *panel;
@property (nonatomic, strong) UIButton *tab; // the side button while hidden
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIButton *minusButton, *plusButton;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *values;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *openingValues; // for Revert
@property (nonatomic) RCZonesMode mode;
@property (nonatomic, copy) NSString *selectedKey; // the handle last touched: - and + change it
@property (nonatomic) BOOL dragging, expanded;
@property (nonatomic) CGPoint dragStart;
@property (nonatomic) double dragStartValue;
@property (nonatomic) BOOL lockWarned; // the warning tap for a locked value, once per drag
@property (nonatomic) double lockBumpValue; // where the last bump was, dragging a locked handle
@property (nonatomic, strong) UINotificationFeedbackGenerator *lockWarning;
@property (nonatomic, strong) UIImpactFeedbackGenerator *lockBump;
@property (nonatomic, strong) UISelectionFeedbackGenerator *tick;
@property (nonatomic, strong) NSTimer *repeatTimer;
@property (nonatomic, strong) NSTimer *saveTimer;
- (double)value:(NSString *)key;
- (BOOL)isLocked:(NSString *)key;
- (CGPoint)handlePointForKey:(NSString *)key;
- (CGPoint)anchorPointForKey:(NSString *)key;
- (void)arrowForKey:(NSString *)key from:(CGPoint *)from direction:(CGPoint *)dir;
- (NSString *)handleKeyNear:(CGPoint)p;
- (void)beginDragAt:(CGPoint)p;
- (void)dragTo:(CGPoint)p;
- (void)endDrag;
@end

static RCZonesController *g_zones;

BOOL RCSwipeZonesIsExpanded(void) { return g_zones.expanded; }
BOOL RCSwipeZonesIsDragging(void) { return g_zones.dragging; }

#pragma mark - Window

// Takes a touch only when one of its views does; the rest go to the app beneath
@interface RCZonesWindow : UIWindow
@end
@implementation RCZonesWindow
- (BOOL)_shouldCreateContextAsSecure { return YES; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

static UIWindowScene *RCZonesWindowScene(void) {
    id app = [UIApplication sharedApplication];
    SEL wsmSel = NSSelectorFromString(@"windowSceneManager");
    id wsm = [app respondsToSelector:wsmSel] ? ((id (*)(id, SEL))objc_msgSend)(app, wsmSel) : nil;
    SEL embeddedSel = NSSelectorFromString(@"embeddedDisplayWindowScene");
    id scene = [wsm respondsToSelector:embeddedSel] ? ((id (*)(id, SEL))objc_msgSend)(wsm, embeddedSel) : nil;
    if ([scene isKindOfClass:[UIWindowScene class]]) return scene;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

#pragma mark - Drawing

static void RCFill(CGRect rect, UIColor *color) {
    [color setFill];
    UIRectFillUsingBlendMode(rect, kCGBlendModeNormal);
}

static void RCText(NSString *text, CGPoint center, CGFloat size, UIColor *color) {
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [UIColor colorWithWhite:0 alpha:0.8];
    shadow.shadowBlurRadius = 2;
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:size weight:UIFontWeightSemibold],
                             NSForegroundColorAttributeName: color, NSShadowAttributeName: shadow };
    CGSize textSize = [text sizeWithAttributes:attrs];
    [text drawAtPoint:CGPointMake(round(center.x - textSize.width / 2), round(center.y - textSize.height / 2)) withAttributes:attrs];
}

// A value label in a dark pill, kept on screen
static void RCPill(NSString *text, CGPoint center, CGRect bounds, BOOL active) {
    UIFont *font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    CGSize textSize = [text sizeWithAttributes:@{ NSFontAttributeName: font }];
    CGRect pill = CGRectMake(0, 0, textSize.width + 14, textSize.height + 6);
    pill.origin.x = MIN(MAX(center.x - pill.size.width / 2, 4), CGRectGetMaxX(bounds) - pill.size.width - 4);
    pill.origin.y = MIN(MAX(center.y - pill.size.height / 2, 4), CGRectGetMaxY(bounds) - pill.size.height - 4);
    [[UIColor colorWithWhite:0 alpha:active ? 0.85 : 0.7] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:pill.size.height / 2] fill];
    [text drawAtPoint:CGPointMake(pill.origin.x + 7, pill.origin.y + 3)
       withAttributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: active ? [UIColor systemYellowColor] : [UIColor whiteColor] }];
}

static void RCDashedLine(CGPoint a, CGPoint b, UIColor *color) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:a];
    [path addLineToPoint:b];
    path.lineWidth = 1.5;
    CGFloat dash[] = {4, 3};
    [path setLineDash:dash count:2 phase:0];
    [color setStroke];
    [path stroke];
}

static void RCArrow(CGPoint from, CGPoint to, UIColor *color) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:from];
    [path addLineToPoint:to];
    CGFloat angle = atan2(to.y - from.y, to.x - from.x), head = 10;
    [path moveToPoint:CGPointMake(to.x - head * cos(angle - M_PI / 6), to.y - head * sin(angle - M_PI / 6))];
    [path addLineToPoint:to];
    [path addLineToPoint:CGPointMake(to.x - head * cos(angle + M_PI / 6), to.y - head * sin(angle + M_PI / 6))];
    path.lineWidth = 3;
    path.lineCapStyle = kCGLineCapRound;
    path.lineJoinStyle = kCGLineJoinRound;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 3, [UIColor colorWithWhite:0 alpha:0.7].CGColor);
    [color setStroke];
    [path stroke];
    [color setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(from.x - 4, from.y - 4, 8, 8)] fill]; // where the swipe starts
    CGContextRestoreGState(ctx);
}

static void RCKnob(CGPoint p, UIColor *tint, BOOL active, BOOL selected, BOOL locked) {
    CGFloat r = active ? 14 : 11;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 4, [UIColor colorWithWhite:0 alpha:0.5].CGColor);
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(p.x - r, p.y - r, r * 2, r * 2)] fill];
    CGContextRestoreGState(ctx);
    [tint setFill];
    if (locked) {
        // Locked in Settings: a gray knob with a white padlock on it, a little larger to fit it
        r += 2;
        [[UIColor systemGrayColor] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(p.x - r + 3, p.y - r + 3, (r - 3) * 2, (r - 3) * 2)] fill];
        UIImage *lock = [[UIImage systemImageNamed:@"lock.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIImageSymbolWeightBold]]
                          imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        [lock drawAtPoint:CGPointMake(p.x - lock.size.width / 2, p.y - lock.size.height / 2)];
    } else {
        [tint setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(p.x - r + 4, p.y - r + 4, (r - 4) * 2, (r - 4) * 2)] fill];
    }
    if (selected) { // the handle - and + change
        UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(p.x - r - 4, p.y - r - 4, (r + 4) * 2, (r + 4) * 2)];
        ring.lineWidth = 2;
        [[UIColor systemYellowColor] setStroke];
        [ring stroke];
    }
}

@interface RCZonesCanvas : UIView
@property (nonatomic, weak) RCZonesController *owner;
@end

@implementation RCZonesCanvas

// Only the handles take touches
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [self.owner handleKeyNear:point] != nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self.owner beginDragAt:[touches.anyObject locationInView:self]]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self.owner dragTo:[touches.anyObject locationInView:self]]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self.owner endDrag]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self.owner endDrag]; }

- (void)drawRect:(CGRect)rect {
    RCZonesController *o = self.owner;
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    BOOL zones = o.mode == RCZonesModeZones;
    CGFloat fade = zones ? 1.0 : 0.4;

    CGFloat top = [o value:@"swipeStatusBarHeight"], bottom = [o value:@"swipeBottomZoneHeight"], edge = [o value:@"swipeEdgeStrip"];
    CGFloat sbLeft = W * [o value:@"swipeStatusBarLeftZone"] / 100.0, sbRight = W * (1 - [o value:@"swipeStatusBarRightZone"] / 100.0);
    CGFloat bLeft = W * [o value:@"swipeBottomLeftZone"] / 100.0, bRight = W * (1 - [o value:@"swipeBottomRightZone"] / 100.0);

    // Zones: the status bar's three, the side edge strips between them and the bottom's three
    NSArray<UIColor *> *topTints = @[[UIColor systemBlueColor], [UIColor systemIndigoColor], [UIColor systemPurpleColor]];
    NSArray<UIColor *> *bottomTints = @[[UIColor systemGreenColor], [UIColor systemTealColor], [UIColor colorWithRed:0.35 green:0.78 blue:0.98 alpha:1]];
    CGFloat topXs[] = {0, sbLeft, sbRight, W}, bottomXs[] = {0, bLeft, bRight, W};
    NSArray *names = @[@"Left", @"Center", @"Right"];
    for (int i = 0; i < 3; i++) {
        RCFill(CGRectMake(topXs[i], 0, topXs[i + 1] - topXs[i], top), [topTints[i] colorWithAlphaComponent:0.45 * fade]);
        RCFill(CGRectMake(bottomXs[i], H - bottom, bottomXs[i + 1] - bottomXs[i], bottom), [bottomTints[i] colorWithAlphaComponent:0.45 * fade]);
        if (zones) {
            if (top >= 16) RCText(names[i], CGPointMake((topXs[i] + topXs[i + 1]) / 2, top - 9), 11, [UIColor whiteColor]);
            if (bottom >= 16) RCText(names[i], CGPointMake((bottomXs[i] + bottomXs[i + 1]) / 2, H - bottom + 9), 11, [UIColor whiteColor]);
        }
    }
    UIColor *edgeTint = [[UIColor systemOrangeColor] colorWithAlphaComponent:0.4 * fade];
    RCFill(CGRectMake(0, top, edge, H - top - bottom), edgeTint);
    RCFill(CGRectMake(W - edge, top, edge, H - top - bottom), edgeTint);
    UIColor *line = [UIColor colorWithWhite:1 alpha:0.85 * fade];
    RCFill(CGRectMake(0, top - 1, W, 2), line);
    RCFill(CGRectMake(0, H - bottom - 1, W, 2), line);
    RCFill(CGRectMake(edge - 1, top, 2, H - top - bottom), line);
    RCFill(CGRectMake(W - edge - 1, top, 2, H - top - bottom), line);
    for (int i = 1; i < 3; i++) {
        RCFill(CGRectMake(topXs[i] - 1, 0, 2, top), line);
        RCFill(CGRectMake(bottomXs[i] - 1, H - bottom, 2, bottom), line);
    }

    for (RCZoneSetting *s in RCZoneSettings()) {
        if (s.mode != o.mode) continue;
        CGPoint knob = [o handlePointForKey:s.key];
        BOOL active = o.dragging && [o.selectedKey isEqualToString:s.key];
        BOOL selected = [o.selectedKey isEqualToString:s.key];
        UIColor *tint = [UIColor systemOrangeColor];
        if ([s.key hasPrefix:@"swipeStatusBar"] || [s.key isEqualToString:@"swipeTopDownDistance"]) tint = [UIColor systemBlueColor];
        if ([s.key hasPrefix:@"swipeBottom"]) tint = [UIColor systemGreenColor];
        NSString *value = RCZoneValueText(s, [o value:s.key]);

        CGPoint labelAt = CGPointMake(knob.x, knob.y + 26);
        CGPoint anchor = [o anchorPointForKey:s.key];
        if (s.mode == RCZonesModeZones) RCDashedLine(anchor, knob, line); // the tab's stem to its line
        BOOL locked = [o isLocked:s.key];
        if ([s.key hasPrefix:@"swipeBottom"] && s.mode == RCZonesModeZones) {
            labelAt = CGPointMake(knob.x, knob.y - 26);
        } else if ([s.key isEqualToString:@"swipeEdgeStrip"]) {
            labelAt = CGPointMake(knob.x + 34, knob.y);
            CGPoint mirror = CGPointMake(W - knob.x, knob.y);
            RCDashedLine(CGPointMake(W - anchor.x, anchor.y), mirror, line);
            RCKnob(mirror, tint, active, selected, locked); // the right side's, the same value
            RCPill(value, CGPointMake(mirror.x - 34, mirror.y), self.bounds, active);
        } else if (s.mode == RCZonesModeDistances) {
            CGPoint from = CGPointZero, dir = CGPointZero;
            [o arrowForKey:s.key from:&from direction:&dir];
            RCArrow(from, knob, [UIColor whiteColor]);
            value = [NSString stringWithFormat:@"%@ %@", s.title, value];
            labelAt = dir.x != 0 ? CGPointMake(knob.x, knob.y - 22) : CGPointMake(knob.x + (knob.x > W / 2 ? -70 : 70), knob.y);
        }
        RCKnob(knob, tint, active, selected, locked);
        RCPill(value, labelAt, self.bounds, active);
    }
}

@end

#pragma mark - Controller

@implementation RCZonesController

// Every app's status bar is hidden while the zones are drawn (see RCZonesStatusBarsFollow)
- (void)setExpanded:(BOOL)expanded {
    if (_expanded == expanded) return;
    _expanded = expanded;
    static int token = -1;
    if (token == -1 && notify_register_check(kRCSwipeZonesOpenNotification, &token) != NOTIFY_STATUS_OK) return;
    notify_set_state(token, expanded ? 1 : 0);
    notify_post(kRCSwipeZonesOpenNotification);
}

- (instancetype)init {
    if ((self = [super init])) {
        self.values = [NSMutableDictionary dictionary];
        self.tick = [[UISelectionFeedbackGenerator alloc] init];
    }
    return self;
}

- (void)loadValues {
    NSDictionary *config = RCSwipeZonesConfig();
    for (RCZoneSetting *s in RCZoneSettings()) {
        id raw = config[s.key];
        double v = [raw isKindOfClass:[NSNumber class]] ? [raw doubleValue] : 0;
        if (!(v >= 5 && v <= 400)) v = s.defaultValue;
        self.values[s.key] = @(MIN(MAX(v, s.minValue), s.maxValue));
    }
    self.openingValues = [self.values copy];
}

- (NSDictionary *)defaults {
    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
    for (RCZoneSetting *s in RCZoneSettings()) defaults[s.key] = @(s.defaultValue);
    return defaults;
}

- (RCZoneSetting *)settingForKey:(NSString *)key {
    for (RCZoneSetting *s in RCZoneSettings()) if ([s.key isEqualToString:key]) return s;
    return nil;
}

- (double)value:(NSString *)key { return self.values[key].doubleValue; }

// Locked in Settings (its slider's lock): shown, but left as it is
- (BOOL)isLocked:(NSString *)key {
    id list = RCSwipeZonesConfig()[@"lockedSettings"];
    return key.length && [list isKindOfClass:[NSArray class]] && [list containsObject:key];
}

#pragma mark Building

- (void)build {
    UIWindowScene *scene = RCZonesWindowScene();
    RCZonesWindow *window = scene ? [[RCZonesWindow alloc] initWithWindowScene:scene] : [[RCZonesWindow alloc] init];
    window.frame = [UIScreen mainScreen].fixedCoordinateSpace.bounds; // drawn upright
    window.windowLevel = UIWindowLevelAlert + 2580; // above apps and the Dynamic Island, under the gesture recorder
    window.backgroundColor = [UIColor clearColor];
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window = window;
    CGRect bounds = window.bounds;

    self.canvas = [[RCZonesCanvas alloc] initWithFrame:bounds];
    self.canvas.owner = self;
    self.canvas.backgroundColor = [UIColor clearColor];
    self.canvas.contentMode = UIViewContentModeRedraw;
    [window addSubview:self.canvas];

    // The panel: what's selected with - and +, Zones or Distances, and the buttons. Dragged by its
    // empty parts, so it can be moved off whatever it covers.
    CGFloat panelWidth = MIN(bounds.size.width - 150, 260);
    self.panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    self.panel.layer.cornerRadius = 18;
    self.panel.clipsToBounds = YES;
    [window addSubview:self.panel];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"Swipe Triggers";
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Zones", @"Distances"]];
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];

    self.detailLabel = [[UILabel alloc] init];
    self.detailLabel.font = [UIFont systemFontOfSize:13];
    self.detailLabel.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    self.detailLabel.textAlignment = NSTextAlignmentCenter;
    self.detailLabel.numberOfLines = 0;

    self.minusButton = [self stepButton:@"minus"];
    self.plusButton = [self stepButton:@"plus"];
    UIStackView *steps = [[UIStackView alloc] initWithArrangedSubviews:@[self.minusButton, self.detailLabel, self.plusButton]];
    steps.spacing = 6;
    steps.alignment = UIStackViewAlignmentCenter;

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self button:@"Revert" action:@selector(revertTapped) bold:NO],
        [self button:@"Reset" action:@selector(resetTapped) bold:NO],
        [self button:@"Hide" action:@selector(hideTapped) bold:NO],
        [self button:@"Done" action:@selector(doneTapped) bold:YES]]];
    buttons.distribution = UIStackViewDistributionFillEqually;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.modeControl, steps, buttons]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.panel.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.panel.contentView.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:self.panel.contentView.bottomAnchor constant:-4],
        [stack.leadingAnchor constraintEqualToAnchor:self.panel.contentView.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:self.panel.contentView.trailingAnchor constant:-10],
        [self.minusButton.widthAnchor constraintEqualToConstant:40],
        [self.plusButton.widthAnchor constraintEqualToConstant:40],
        [self.detailLabel.heightAnchor constraintGreaterThanOrEqualToConstant:52],
    ]];
    [self updateDetail];
    CGSize size = [self.panel systemLayoutSizeFittingSize:CGSizeMake(panelWidth, UILayoutFittingCompressedSize.height)
                            withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.panel.frame = CGRectMake((bounds.size.width - panelWidth) / 2, bounds.size.height * 0.55 - size.height / 2, panelWidth, size.height);
    [self.panel addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panelPanned:)]];

    // While hidden: a small button at the right side brings it back
    self.tab = [UIButton buttonWithType:UIButtonTypeSystem];
    self.tab.frame = CGRectMake(bounds.size.width - 50, bounds.size.height * 0.42, 44, 44);
    self.tab.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    self.tab.layer.cornerRadius = 22;
    self.tab.tintColor = [UIColor systemYellowColor];
    [self.tab setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    [self.tab addTarget:self action:@selector(showTapped) forControlEvents:UIControlEventTouchUpInside];
    self.tab.hidden = YES;
    [window addSubview:self.tab];
}

- (UIButton *)button:(NSString *)title action:(SEL)action bold:(BOOL)bold {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:bold ? UIFontWeightSemibold : UIFontWeightRegular];
    button.tintColor = bold ? [UIColor systemYellowColor] : [UIColor whiteColor];
    [button.heightAnchor constraintEqualToConstant:40].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

// - or +: a point (or percent) a tap, repeating while held
- (UIButton *)stepButton:(NSString *)symbol {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:[symbol stringByAppendingString:@".circle.fill"]
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:28]] forState:UIControlStateNormal];
    button.tintColor = [UIColor whiteColor];
    [button.heightAnchor constraintEqualToConstant:44].active = YES;
    [button addTarget:self action:@selector(stepDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return button;
}

#pragma mark Showing

- (void)show {
    if (!self.window) {
        [self loadValues];
        [self build];
    }
    self.expanded = YES;
    self.window.hidden = NO;
    self.canvas.hidden = NO;
    self.panel.hidden = NO;
    self.tab.hidden = YES;
    [self.canvas setNeedsDisplay];
}

- (void)hide {
    self.expanded = NO;
    self.dragging = NO;
    self.canvas.hidden = YES;
    self.panel.hidden = YES;
    self.tab.hidden = NO;
    [self saveNow];
}

- (void)close {
    self.expanded = NO;
    self.dragging = NO;
    [self saveNow];
    [self.repeatTimer invalidate];
    self.window.hidden = YES;
    self.window = nil;
    g_zones = nil;
}

#pragma mark Geometry (upright screen points)

// A distance's arrow: where the swipe starts and which way it goes
- (void)arrowForKey:(NSString *)key from:(CGPoint *)from direction:(CGPoint *)dir {
    CGFloat W = self.canvas.bounds.size.width, H = self.canvas.bounds.size.height;
    CGFloat top = [self value:@"swipeStatusBarHeight"], bottom = [self value:@"swipeBottomZoneHeight"], edge = [self value:@"swipeEdgeStrip"];
    *from = CGPointZero; *dir = CGPointMake(1, 0);
    if ([key isEqualToString:@"swipeStatusBarDistance"]) { *from = CGPointMake(W * 0.12, top + 48); *dir = CGPointMake(1, 0); }
    else if ([key isEqualToString:@"swipeTopDownDistance"]) { *from = CGPointMake(W * 0.84, top / 2); *dir = CGPointMake(0, 1); }
    else if ([key isEqualToString:@"swipeEdgeDistance"]) { *from = CGPointMake(MAX(edge / 2, 14), H * 0.3); *dir = CGPointMake(0, 1); }
    else if ([key isEqualToString:@"swipeBottomBarDistance"]) { *from = CGPointMake(W * 0.12, H - bottom - 48); *dir = CGPointMake(1, 0); }
    else if ([key isEqualToString:@"swipeBottomUpDistance"]) { *from = CGPointMake(W * 0.84, H - bottom / 2); *dir = CGPointMake(0, -1); }
}

// Where a handle is drawn: a tab inside the screen joined to the line it moves (see
// -anchorPointForKey:), so no handle sits where iOS's edge gestures start
- (CGPoint)handlePointForKey:(NSString *)key {
    CGFloat W = self.canvas.bounds.size.width, H = self.canvas.bounds.size.height;
    CGFloat top = [self value:@"swipeStatusBarHeight"], bottom = [self value:@"swipeBottomZoneHeight"];
    if ([key isEqualToString:@"swipeStatusBarHeight"]) return CGPointMake(W * [self value:@"swipeStatusBarLeftZone"] / 200.0, top + 44);
    if ([key isEqualToString:@"swipeStatusBarLeftZone"]) return CGPointMake(W * [self value:key] / 100.0, top + 24);
    if ([key isEqualToString:@"swipeStatusBarRightZone"]) return CGPointMake(W * (1 - [self value:key] / 100.0), top + 24);
    if ([key isEqualToString:@"swipeEdgeStrip"]) return CGPointMake([self value:key] + 36, H * 0.3);
    if ([key isEqualToString:@"swipeBottomZoneHeight"]) return CGPointMake(W / 2, H - bottom - 44);
    if ([key isEqualToString:@"swipeBottomLeftZone"]) return CGPointMake(W * [self value:key] / 100.0, H - bottom - 24);
    if ([key isEqualToString:@"swipeBottomRightZone"]) return CGPointMake(W * (1 - [self value:key] / 100.0), H - bottom - 24);
    CGPoint from, dir;
    [self arrowForKey:key from:&from direction:&dir];
    double d = [self value:key];
    return CGPointMake(from.x + dir.x * d, from.y + dir.y * d);
}

// The point on the line a zone handle moves, for its stem
- (CGPoint)anchorPointForKey:(NSString *)key {
    CGFloat H = self.canvas.bounds.size.height;
    CGFloat top = [self value:@"swipeStatusBarHeight"], bottom = [self value:@"swipeBottomZoneHeight"];
    CGPoint knob = [self handlePointForKey:key];
    if ([self settingForKey:key].mode != RCZonesModeZones) return knob;
    if ([key hasPrefix:@"swipeStatusBar"]) return CGPointMake(knob.x, top);
    if ([key isEqualToString:@"swipeEdgeStrip"]) return CGPointMake([self value:key], knob.y);
    return CGPointMake(knob.x, H - bottom);
}

// The value a handle at p stands for, along its own axis
- (double)valueForKey:(NSString *)key atPoint:(CGPoint)p {
    CGFloat W = self.canvas.bounds.size.width, H = self.canvas.bounds.size.height;
    if ([key isEqualToString:@"swipeStatusBarHeight"]) return p.y;
    if ([key isEqualToString:@"swipeStatusBarLeftZone"] || [key isEqualToString:@"swipeBottomLeftZone"]) return p.x / W * 100;
    if ([key isEqualToString:@"swipeStatusBarRightZone"] || [key isEqualToString:@"swipeBottomRightZone"]) return (W - p.x) / W * 100;
    if ([key isEqualToString:@"swipeEdgeStrip"]) return self.dragStart.x < W / 2 ? p.x : W - p.x; // the side the drag started on
    if ([key isEqualToString:@"swipeBottomZoneHeight"]) return H - p.y;
    CGPoint from, dir;
    [self arrowForKey:key from:&from direction:&dir];
    return (p.x - from.x) * dir.x + (p.y - from.y) * dir.y;
}

- (NSString *)handleKeyNear:(CGPoint)p {
    if (!self.expanded) return nil;
    NSString *best = nil;
    CGFloat bestDistance = 30; // a finger's reach around a handle
    CGFloat W = self.canvas.bounds.size.width;
    for (RCZoneSetting *s in RCZoneSettings()) {
        if (s.mode != self.mode) continue;
        CGPoint knob = [self handlePointForKey:s.key];
        CGFloat d = hypot(knob.x - p.x, knob.y - p.y);
        if ([s.key isEqualToString:@"swipeEdgeStrip"]) d = MIN(d, hypot(W - knob.x - p.x, knob.y - p.y)); // the right side's handle
        if (d < bestDistance) { bestDistance = d; best = s.key; }
    }
    return best;
}

#pragma mark Changing values

// Keeps a value in its range (the center keeps at least a tenth of a split strip), applies it to
// the tweak at once and saves a moment later
- (void)setZoneValue:(double)v forKey:(NSString *)key {
    RCZoneSetting *s = [self settingForKey:key];
    double max = s.maxValue;
    NSDictionary *partner = @{ @"swipeStatusBarLeftZone": @"swipeStatusBarRightZone", @"swipeStatusBarRightZone": @"swipeStatusBarLeftZone",
                               @"swipeBottomLeftZone": @"swipeBottomRightZone", @"swipeBottomRightZone": @"swipeBottomLeftZone" };
    if (partner[key]) max = MIN(max, 90 - [self value:partner[key]]);
    v = MIN(MAX(round(v), s.minValue), max);
    double old = [self value:key];
    if (v == old) return;
    if ([self isLocked:key]) {
        // It doesn't move: a warning as the drag starts pulling, then a firm bump every 5 it would
        // have gone, like hitting a stop
        if (!self.lockWarned) {
            [self.lockWarning notificationOccurred:UINotificationFeedbackTypeWarning];
            self.lockWarned = YES;
            self.lockBumpValue = v;
        } else if (fabs(v - self.lockBumpValue) >= 5) {
            [self.lockBump impactOccurred];
            [self.lockBump prepare];
            self.lockBumpValue = v;
        }
        return;
    }
    self.values[key] = @(v);
    if (floor(v / 5) != floor(old / 5) || v == s.defaultValue) [self.tick selectionChanged];
    RCSwipeZonesApply(self.values, [self defaults], NO);
    [self saveSoon];
    [self updateDetail];
    [self.canvas setNeedsDisplay];
}

- (void)saveSoon {
    [self.saveTimer invalidate];
    self.saveTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(saveNow) userInfo:nil repeats:NO];
}

- (void)saveNow {
    if (!self.saveTimer) return; // nothing changed since the last save
    [self.saveTimer invalidate];
    self.saveTimer = nil;
    RCSwipeZonesApply(self.values, [self defaults], YES);
}

- (void)beginDragAt:(CGPoint)p {
    NSString *key = [self handleKeyNear:p];
    if (!key) return;
    self.selectedKey = key;
    self.dragging = YES;
    self.dragStart = p;
    self.dragStartValue = [self value:key];
    self.lockWarned = NO;
    [self.tick prepare];
    if ([self isLocked:key]) {
        if (!self.lockWarning) self.lockWarning = [[UINotificationFeedbackGenerator alloc] init];
        if (!self.lockBump) self.lockBump = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
        [self.lockWarning prepare];
        [self.lockBump prepare];
        // a tap on it already says it's locked
        [self.lockBump impactOccurred];
    }
    [self updateDetail];
    [self.canvas setNeedsDisplay];
}

// The value follows the finger's movement, so grabbing a tab off its line doesn't jump it
- (void)dragTo:(CGPoint)p {
    if (!self.dragging || !self.selectedKey) return;
    NSString *key = self.selectedKey;
    [self setZoneValue:self.dragStartValue + [self valueForKey:key atPoint:p] - [self valueForKey:key atPoint:self.dragStart] forKey:key];
}

- (void)endDrag {
    // triggers stay paused a moment longer, for the tweak's own handling of the same touch
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.dragging = NO;
        [self.canvas setNeedsDisplay];
    });
}

- (void)stepDown:(UIButton *)sender {
    double delta = sender == self.plusButton ? 1 : -1;
    [self step:delta];
    [self.repeatTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.45 repeats:NO block:^(NSTimer *t) {
        weakSelf.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.08 repeats:YES block:^(NSTimer *t2) { [weakSelf step:delta]; }];
    }];
}

- (void)stepUp {
    [self.repeatTimer invalidate];
    self.repeatTimer = nil;
}

- (void)step:(double)delta {
    if (!self.selectedKey) return;
    if (!self.repeatTimer) self.lockWarned = NO;
    [self setZoneValue:[self value:self.selectedKey] + delta forKey:self.selectedKey];
}

- (void)updateDetail {
    RCZoneSetting *s = self.selectedKey ? [self settingForKey:self.selectedKey] : nil;
    if (s && s.mode != self.mode) s = nil;
    BOOL locked = s && [self isLocked:s.key];
    self.minusButton.enabled = self.plusButton.enabled = s != nil && !locked;
    self.minusButton.alpha = self.plusButton.alpha = (s && !locked) ? 1 : 0.35;
    if (locked) {
        self.detailLabel.text = [NSString stringWithFormat:@"%@\n%@, locked in Settings", s.title, RCZoneValueText(s, [self value:s.key])];
    } else if (s) {
        self.detailLabel.text = [NSString stringWithFormat:@"%@\n%@ (Default %@)", s.title, RCZoneValueText(s, [self value:s.key]), RCZoneValueText(s, s.defaultValue)];
    } else if (self.mode == RCZonesModeZones) {
        self.detailLabel.text = @"Drag a handle, or tap one and use - and +.";
    } else {
        self.detailLabel.text = @"Drag an arrow's end, or tap one and use - and +.";
    }
}

#pragma mark Buttons

- (void)modeChanged:(UISegmentedControl *)control {
    self.mode = control.selectedSegmentIndex == 1 ? RCZonesModeDistances : RCZonesModeZones;
    [self updateDetail];
    [self.canvas setNeedsDisplay];
}

- (void)panelPanned:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.window];
    CGRect frame = CGRectOffset(self.panel.frame, t.x, t.y);
    CGRect bounds = self.window.bounds;
    frame.origin.x = MIN(MAX(frame.origin.x, 4), bounds.size.width - frame.size.width - 4);
    frame.origin.y = MIN(MAX(frame.origin.y, 50), bounds.size.height - frame.size.height - 40);
    self.panel.frame = frame;
    [pan setTranslation:CGPointZero inView:self.window];
}

// Revert and Reset leave locked values as they are
- (void)applyAll:(NSDictionary *)values {
    NSMutableDictionary *merged = [values mutableCopy];
    for (NSString *key in values) if ([self isLocked:key] && self.values[key]) merged[key] = self.values[key];
    [self.values setDictionary:merged];
    RCSwipeZonesApply(self.values, [self defaults], NO);
    [self saveSoon];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self updateDetail];
    [self.canvas setNeedsDisplay];
}

- (void)revertTapped { [self applyAll:self.openingValues]; }
- (void)resetTapped { [self applyAll:[self defaults]]; }
- (void)hideTapped { [self hide]; }
- (void)showTapped { [self show]; }
- (void)doneTapped { [self close]; }

@end

#pragma mark - Status bars

// In every app and SpringBoard: while the zones are drawn, status bars are hidden (alpha 0), checked
// again every half second in case an app lays its status bar out anew; afterwards the hidden ones come back
static NSHashTable<UIView *> *g_hiddenStatusBars;
static NSHashTable<UIWindow *> *g_quietIslandWindows; // SpringBoard: the Dynamic Island's windows, touches off
static NSTimer *g_statusBarTimer;

static BOOL RCZonesOpenState(void) {
    static int token = -1;
    if (token == -1 && notify_register_check(kRCSwipeZonesOpenNotification, &token) != NOTIFY_STATUS_OK) return NO;
    uint64_t state = 0;
    notify_get_state(token, &state);
    return state != 0;
}

static void RCZonesHideStatusBarsIn(UIView *view, Class modern, Class legacy) {
    if ((modern && [view isKindOfClass:modern]) || (legacy && [view isKindOfClass:legacy])) {
        if (view.alpha > 0) {
            view.alpha = 0;
            [g_hiddenStatusBars addObject:view];
        }
        return;
    }
    for (UIView *sub in view.subviews) RCZonesHideStatusBarsIn(sub, modern, legacy);
}

static void RCZonesStatusBarsFollow(void) {
    BOOL hide = RCZonesOpenState();
    if (!g_hiddenStatusBars) g_hiddenStatusBars = [NSHashTable weakObjectsHashTable];
    if (!g_quietIslandWindows) g_quietIslandWindows = [NSHashTable weakObjectsHashTable];
    if (hide) {
        Class modern = NSClassFromString(@"UIStatusBar_Base"), legacy = NSClassFromString(@"_UIStatusBar");
        Class statusBarWindow = NSClassFromString(@"SBStatusBarWindow"), islandWindow = NSClassFromString(@"SBSystemApertureWindow");
        NSMutableSet<UIWindow *> *windows = [NSMutableSet set];
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:[UIApplication sharedApplication].windows ?: @[]];
#pragma clang diagnostic pop
        for (UIWindow *window in windows) {
            if ([window isKindOfClass:[RCZonesWindow class]]) continue;
            // SpringBoard draws the status bar over apps in its own window: hidden whole
            if (statusBarWindow && [window isKindOfClass:statusBarWindow]) {
                if (window.alpha > 0) { window.alpha = 0; [g_hiddenStatusBars addObject:window]; }
                continue;
            }
            // The Dynamic Island would take touches meant for the handles near it
            if (islandWindow && [window isKindOfClass:islandWindow]) {
                if (window.userInteractionEnabled) { window.userInteractionEnabled = NO; [g_quietIslandWindows addObject:window]; }
                continue;
            }
            RCZonesHideStatusBarsIn(window, modern, legacy);
        }
        if (!g_statusBarTimer) {
            g_statusBarTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { RCZonesStatusBarsFollow(); }];
        }
    } else {
        [g_statusBarTimer invalidate];
        g_statusBarTimer = nil;
        for (UIView *view in g_hiddenStatusBars) view.alpha = 1;
        [g_hiddenStatusBars removeAllObjects];
        for (UIWindow *window in g_quietIslandWindows) window.userInteractionEnabled = YES;
        [g_quietIslandWindows removeAllObjects];
    }
}

#pragma mark - Opening

static void RCSwipeZonesShow(void) {
    if (!g_zones) g_zones = [[RCZonesController alloc] init];
    [g_zones show];
}

__attribute__((constructor)) static void RCSwipeZonesInit(void) {
    if (!NSClassFromString(@"UIApplication")) return;
    int openToken;
    notify_register_dispatch(kRCSwipeZonesOpenNotification, &openToken, dispatch_get_main_queue(), ^(int t) { RCZonesStatusBarsFollow(); });
    // an app opened while the zones are drawn
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) { if (RCZonesOpenState()) RCZonesStatusBarsFollow(); }];
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    int token;
    notify_register_dispatch(kRCSwipeZonesShowNotification, &token, dispatch_get_main_queue(), ^(int t) { RCSwipeZonesShow(); });
    // Hidden when the phone locks, so the zones never cover the lock screen
    int lockToken;
    notify_register_dispatch("com.apple.springboard.lockcomplete", &lockToken, dispatch_get_main_queue(), ^(int t) {
        if (g_zones.expanded) [g_zones hide];
    });
    // A respring while the zones were drawn left the state on: status bars come back
    if (RCZonesOpenState()) {
        int resetToken;
        if (notify_register_check(kRCSwipeZonesOpenNotification, &resetToken) == NOTIFY_STATUS_OK) {
            notify_set_state(resetToken, 0);
            notify_post(kRCSwipeZonesOpenNotification);
        }
    }
}
