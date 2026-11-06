#import "RCGestureDetailViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Drawing

// One finger's stroke: where it went and when (seconds from the start)
@interface RCGestureStroke : NSObject
@property (nonatomic, strong) NSMutableArray<NSValue *> *points;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *times;
@property (nonatomic, assign) BOOL edge; // started on a screen edge (home bar, Back)
@end
@implementation RCGestureStroke
@end

// The screen as a rounded outline with every stroke drawn on it, numbered in order. A tap is a
// ring. During a replay the strokes draw themselves with the recorded timing and a dot shows
// each finger that's down.
@interface RCGesturePreviewView : UIView
@property (nonatomic, strong) NSArray<RCGestureStroke *> *strokes;
@property (nonatomic, assign) CGSize screen;
@property (nonatomic, assign) double duration;
@property (nonatomic, assign) double now; // < 0: not replaying, all drawn
@property (nonatomic, assign) double rangeStart; // only what happens between these (Trim)
@property (nonatomic, assign) double rangeEnd;
@end

@implementation RCGesturePreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
        _now = -1;
        _rangeEnd = HUGE_VAL;
    }
    return self;
}

+ (NSArray<UIColor *> *)colors {
    return @[ [UIColor systemRedColor], [UIColor systemBlueColor], [UIColor systemGreenColor], [UIColor systemOrangeColor],
              [UIColor systemPurpleColor], [UIColor systemTealColor], [UIColor systemPinkColor], [UIColor systemYellowColor] ];
}

// The screen's outline, fitted in the view
- (CGRect)screenRect {
    CGSize screen = self.screen.width > 0 ? self.screen : CGSizeMake(390, 844);
    CGRect area = CGRectInset(self.bounds, 8, 8);
    CGFloat scale = MIN(area.size.width / screen.width, area.size.height / screen.height);
    CGSize size = CGSizeMake(screen.width * scale, screen.height * scale);
    return CGRectMake(CGRectGetMidX(area) - size.width / 2, CGRectGetMidY(area) - size.height / 2, size.width, size.height);
}

- (void)drawRect:(CGRect)rect {
    CGRect phone = [self screenRect];
    CGSize screen = self.screen.width > 0 ? self.screen : CGSizeMake(390, 844);
    CGFloat scale = phone.size.width / screen.width;
    UIBezierPath *outline = [UIBezierPath bezierPathWithRoundedRect:phone cornerRadius:phone.size.width * 0.12];
    [[UIColor colorWithWhite:0.5 alpha:0.12] setFill];
    [outline fill];
    [[UIColor colorWithWhite:0.5 alpha:0.45] setStroke];
    outline.lineWidth = 1.5;
    [outline stroke];

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    [outline addClip];
    NSArray<UIColor *> *colors = [RCGesturePreviewView colors];
    BOOL replaying = self.now >= 0;
    NSMutableArray *labels = [NSMutableArray array];
    [self.strokes enumerateObjectsUsingBlock:^(RCGestureStroke *stroke, NSUInteger idx, BOOL *stop) {
        UIColor *color = colors[idx % colors.count];
        // The points inside the range; during a replay, only those done so far
        NSMutableArray<NSValue *> *points = [NSMutableArray array];
        NSUInteger inRange = 0;
        for (NSUInteger i = 0; i < stroke.points.count; i++) {
            double t = stroke.times[i].doubleValue;
            if (t < self.rangeStart - 1e-6 || t > self.rangeEnd + 1e-6) continue;
            inRange++;
            if (replaying && t > self.now) continue;
            [points addObject:stroke.points[i]];
        }
        if (points.count == 0) return;
        CGPoint (^place)(NSUInteger) = ^CGPoint(NSUInteger i) {
            CGPoint p = points[i].CGPointValue;
            return CGPointMake(phone.origin.x + p.x * scale, phone.origin.y + p.y * scale);
        };
        NSUInteger shown = points.count;
        BOOL finished = !replaying || shown == inRange;
        // The whole stroke faintly underneath while replaying
        UIBezierPath *path = [UIBezierPath bezierPath];
        path.lineWidth = 4;
        path.lineCapStyle = kCGLineCapRound;
        path.lineJoinStyle = kCGLineJoinRound;
        CGRect bounds = CGRectNull;
        for (NSUInteger i = 0; i < shown; i++) {
            CGPoint p = place(i);
            if (i == 0) [path moveToPoint:p]; else [path addLineToPoint:p];
            bounds = CGRectUnion(bounds, CGRectMake(p.x, p.y, 0, 0));
        }
        BOOL tap = bounds.size.width < 6 && bounds.size.height < 6 && finished;
        CGPoint start = place(0);
        if (tap) {
            UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:start radius:11 startAngle:0 endAngle:2 * M_PI clockwise:YES];
            ring.lineWidth = 3;
            [[color colorWithAlphaComponent:0.25] setFill];
            [ring fill];
            [color setStroke];
            [ring stroke];
        } else {
            [[color colorWithAlphaComponent:0.9] setStroke];
            [path stroke];
            UIBezierPath *dot = [UIBezierPath bezierPathWithArcCenter:start radius:5 startAngle:0 endAngle:2 * M_PI clockwise:YES];
            [color setFill];
            [dot fill];
            if (finished) {
                // An arrowhead where it lifted
                CGPoint end = place(shown - 1);
                CGPoint before = end;
                for (NSInteger i = (NSInteger)shown - 2; i >= 0; i--) {
                    before = place(i);
                    if (hypot(end.x - before.x, end.y - before.y) > 8) break;
                }
                CGFloat angle = atan2(end.y - before.y, end.x - before.x);
                UIBezierPath *arrow = [UIBezierPath bezierPath];
                [arrow moveToPoint:end];
                [arrow addLineToPoint:CGPointMake(end.x - 12 * cos(angle - 0.5), end.y - 12 * sin(angle - 0.5))];
                [arrow addLineToPoint:CGPointMake(end.x - 12 * cos(angle + 0.5), end.y - 12 * sin(angle + 0.5))];
                [arrow closePath];
                [arrow fill];
            }
        }
        // A finger that's down now
        if (!finished) {
            CGPoint p = place(shown - 1);
            UIBezierPath *finger = [UIBezierPath bezierPathWithArcCenter:p radius:14 startAngle:0 endAngle:2 * M_PI clockwise:YES];
            [[color colorWithAlphaComponent:0.35] setFill];
            [finger fill];
        }
        [labels addObject:@[@(labels.count + 1), [NSValue valueWithCGPoint:start], color, @(stroke.edge)]];
    }];
    CGContextRestoreGState(ctx);

    // Numbers by each start, so the order is clear
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightBold], NSForegroundColorAttributeName: [UIColor whiteColor] };
    for (NSArray *label in labels) {
        if (labels.count < 2) break;
        NSString *text = [label[0] stringValue];
        CGPoint p = [label[1] CGPointValue];
        CGSize size = [text sizeWithAttributes:attrs];
        CGFloat d = MAX(18, size.width + 8);
        CGRect badge = CGRectMake(p.x + 8, p.y - d - 4, d, 18);
        badge.origin.x = MIN(MAX(badge.origin.x, phone.origin.x + 2), CGRectGetMaxX(phone) - d - 2);
        badge.origin.y = MIN(MAX(badge.origin.y, phone.origin.y + 2), CGRectGetMaxY(phone) - 20);
        [(UIColor *)label[2] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:badge cornerRadius:9] fill];
        [text drawAtPoint:CGPointMake(CGRectGetMidX(badge) - size.width / 2, CGRectGetMidY(badge) - size.height / 2) withAttributes:attrs];
    }
}

@end

#pragma mark - Trim bar

// The gesture's timeline: a bar for each touch, in the drawing's colors, and two handles that
// pick the part kept. Outside them is dimmed.
@interface RCTrimBar : UIControl
@property (nonatomic, assign) double duration;
@property (nonatomic, assign) double start;
@property (nonatomic, assign) double end;
@property (nonatomic, strong) NSArray<NSArray *> *segments; // @[from, to, color]
@property (nonatomic, assign) NSInteger dragging; // 0 none, 1 start, 2 end
@end

static const CGFloat kRCTrimHandle = 16;

@implementation RCTrimBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (CGRect)track {
    return CGRectInset(self.bounds, kRCTrimHandle + 4, 6);
}

- (CGFloat)xFor:(double)t {
    CGRect track = [self track];
    return track.origin.x + (self.duration > 0 ? t / self.duration : 0) * track.size.width;
}

- (double)timeAt:(CGFloat)x {
    CGRect track = [self track];
    return MIN(MAX((x - track.origin.x) / MAX(track.size.width, 1), 0), 1) * self.duration;
}

- (void)drawRect:(CGRect)rect {
    CGRect track = [self track];
    [[UIColor colorWithWhite:0.5 alpha:0.18] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:track cornerRadius:6] fill];
    // A bar for each touch, in its row of the strip
    CGFloat lane = MAX(4, MIN(10, (track.size.height - 8) / MAX(1, (CGFloat)MIN(self.segments.count, 4))));
    [self.segments enumerateObjectsUsingBlock:^(NSArray *seg, NSUInteger i, BOOL *stop) {
        CGFloat x1 = [self xFor:[seg[0] doubleValue]], x2 = MAX([self xFor:[seg[1] doubleValue]], x1 + 4);
        CGFloat y = track.origin.y + 4 + (i % 4) * lane;
        [(UIColor *)seg[2] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x1, y, x2 - x1, lane - 2) cornerRadius:2] fill];
    }];
    // Dim what's cut, then the handles and the frame between them
    CGFloat sx = [self xFor:self.start], ex = [self xFor:self.end];
    [[UIColor colorWithWhite:0 alpha:0.55] setFill];
    UIRectFillUsingBlendMode(CGRectMake(track.origin.x, track.origin.y, sx - track.origin.x, track.size.height), kCGBlendModeNormal);
    UIRectFillUsingBlendMode(CGRectMake(ex, track.origin.y, CGRectGetMaxX(track) - ex, track.size.height), kCGBlendModeNormal);
    UIColor *yellow = [UIColor systemYellowColor];
    [yellow setFill];
    UIRectFill(CGRectMake(sx, track.origin.y - 2, ex - sx, 3));
    UIRectFill(CGRectMake(sx, CGRectGetMaxY(track) - 1, ex - sx, 3));
    for (NSNumber *edge in @[@(sx - kRCTrimHandle), @(ex)]) {
        CGRect handle = CGRectMake(edge.doubleValue, track.origin.y - 2, kRCTrimHandle, track.size.height + 4);
        [[UIBezierPath bezierPathWithRoundedRect:handle cornerRadius:5] fill];
        [[UIColor colorWithWhite:0 alpha:0.6] setFill];
        UIRectFill(CGRectMake(CGRectGetMidX(handle) - 1, CGRectGetMidY(handle) - 8, 2, 16));
        [yellow setFill];
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGFloat x = [touch locationInView:self].x;
    CGFloat toStart = fabs(x - ([self xFor:self.start] - kRCTrimHandle / 2));
    CGFloat toEnd = fabs(x - ([self xFor:self.end] + kRCTrimHandle / 2));
    if (MIN(toStart, toEnd) > 44) return NO;
    self.dragging = toStart <= toEnd ? 1 : 2;
    [self holdPage:YES];
    return YES;
}

// While a handle is held the page doesn't scroll, or a drag that drifts up or down would scroll it
// and drop the handle
- (void)holdPage:(BOOL)hold {
    for (UIView *view = self.superview; view; view = view.superview) {
        if ([view isKindOfClass:[UIScrollView class]]) {
            ((UIScrollView *)view).scrollEnabled = !hold;
            break;
        }
    }
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    self.dragging = 0;
    [self holdPage:NO];
}

// A drag that starts on a handle stays with it, however it moves
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (self.dragging) return NO;
    return [super gestureRecognizerShouldBegin:recognizer];
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGFloat x = [touch locationInView:self].x;
    double gap = MIN(0.05, self.duration / 2);
    if (self.dragging == 1) self.start = MIN([self timeAt:x + kRCTrimHandle / 2], self.end - gap);
    else self.end = MAX([self timeAt:x - kRCTrimHandle / 2], self.start + gap);
    [self setNeedsDisplay];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    self.dragging = 0;
    [self holdPage:NO];
    [self sendActionsForControlEvents:UIControlEventEditingDidEnd];
}

@end

#pragma mark - Page

typedef NS_ENUM(NSInteger, RCGestureDetailSection) {
    RCGestureDetailSectionInfo,
    RCGestureDetailSectionActions,
    RCGestureDetailSectionDelete,
};

@interface RCGestureDetailViewController ()
@property (nonatomic, strong) RCGesturePreviewView *preview;
@property (nonatomic, strong) UIButton *replayButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, assign) CFTimeInterval replayStart;
@property (nonatomic, strong) NSDate *created;
@property (nonatomic, assign) NSInteger strokeCount;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL trimming;
@property (nonatomic, strong) RCTrimBar *trimBar;
@property (nonatomic, strong) UILabel *trimLabel;
@end

@implementation RCGestureDetailViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)setName:(NSString *)name {
    _name = [name copy];
    self.title = name;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 440)];
    RCGesturePreviewView *preview = [[RCGesturePreviewView alloc] initWithFrame:CGRectMake(0, 8, 320, 360)];
    preview.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [preview addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replay)]];
    [header addSubview:preview];
    self.preview = preview;
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(0, 170, 320, 20)];
    status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    status.textAlignment = NSTextAlignmentCenter;
    status.textColor = [UIColor secondaryLabelColor];
    status.font = [UIFont systemFontOfSize:15];
    status.text = @"Loading…";
    [header addSubview:status];
    self.statusLabel = status;
    UIButton *replay = [UIButton buttonWithType:UIButtonTypeSystem];
    [replay setTitle:@" Replay" forState:UIControlStateNormal];
    [replay setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] forState:UIControlStateNormal];
    replay.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    replay.frame = CGRectMake(0, 376, 320, 36);
    replay.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    replay.hidden = YES;
    [replay addTarget:self action:@selector(replay) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:replay];
    self.replayButton = replay;
    RCTrimBar *bar = [[RCTrimBar alloc] initWithFrame:CGRectMake(16, 372, 288, 44)];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    bar.hidden = YES;
    [bar addTarget:self action:@selector(trimChanged) forControlEvents:UIControlEventValueChanged];
    [bar addTarget:self action:@selector(replay) forControlEvents:UIControlEventEditingDidEnd];
    [header addSubview:bar];
    self.trimBar = bar;
    UILabel *trimLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 416, 320, 20)];
    trimLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    trimLabel.textAlignment = NSTextAlignmentCenter;
    trimLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    trimLabel.textColor = [UIColor secondaryLabelColor];
    trimLabel.hidden = YES;
    [header addSubview:trimLabel];
    self.trimLabel = trimLabel;
    self.tableView.tableHeaderView = header;
    // Back from Replace Recording: the new recording
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(load) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self load];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.link invalidate];
    self.link = nil;
}

#pragma mark - Loading

// The tweak writes the gesture out (as for Export), then it's read back here
- (void)load {
    NSString *path = @"/tmp/rc-gesture-preview.json";
    NSString *command = [NSString stringWithFormat:@"gesture export \"%@\" \"%@\"", path, self.name];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSData *data = [output hasPrefix:@"Exported"] ? [NSData dataWithContentsOfFile:path] : nil;
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        NSDictionary *file = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *entry = [file isKindOfClass:[NSDictionary class]] ? [file[@"gestures"] firstObject] : nil;
        if (![entry isKindOfClass:[NSDictionary class]]) {
            strongSelf.statusLabel.text = error.localizedDescription ?: @"Couldn't load the gesture";
            return;
        }
        [strongSelf show:entry];
    }];
}

// Frames: <f t, B count, then per finger B slot, B flags (bit 0 down, bits 2-5 edge), <f x, <f y
- (void)show:(NSDictionary *)entry {
    NSData *frames = [[NSData alloc] initWithBase64EncodedString:entry[@"frames"] ?: @"" options:0];
    const uint8_t *p = frames.bytes, *end = p + frames.length;
    NSMutableDictionary<NSNumber *, RCGestureStroke *> *active = [NSMutableDictionary dictionary];
    NSMutableArray<RCGestureStroke *> *strokes = [NSMutableArray array];
    double last = 0;
    while (p + 5 <= end) {
        float t;
        memcpy(&t, p, 4);
        int n = p[4];
        p += 5;
        if (p + n * 10 > end) break;
        last = t;
        for (int j = 0; j < n; j++) {
            float xy[2];
            memcpy(xy, p + 2, 8);
            NSNumber *slot = @(p[0]);
            BOOL down = p[1] & 1;
            BOOL edge = ((p[1] >> 2) & 0xF) || (p[1] & 2);
            p += 10;
            RCGestureStroke *stroke = active[slot];
            if (!stroke) {
                if (!down) continue;
                stroke = [[RCGestureStroke alloc] init];
                stroke.points = [NSMutableArray array];
                stroke.times = [NSMutableArray array];
                stroke.edge = edge;
                active[slot] = stroke;
                [strokes addObject:stroke];
            }
            [stroke.points addObject:[NSValue valueWithCGPoint:CGPointMake(xy[0], xy[1])]];
            [stroke.times addObject:@(t)];
            if (!down) [active removeObjectForKey:slot];
        }
    }
    NSArray *screen = entry[@"screen"];
    if ([screen isKindOfClass:[NSArray class]] && screen.count == 2) self.preview.screen = CGSizeMake([screen[0] doubleValue], [screen[1] doubleValue]);
    self.preview.strokes = strokes;
    self.preview.duration = last;
    self.strokeCount = strokes.count;
    double created = [entry[@"created"] doubleValue];
    self.created = created > 0 ? [NSDate dateWithTimeIntervalSince1970:created] : nil;
    self.loaded = YES;
    self.statusLabel.hidden = YES;
    self.replayButton.hidden = strokes.count == 0;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCGestureDetailSectionInfo] withRowAnimation:UITableViewRowAnimationNone];
    [self replay];
}

#pragma mark - Replay

- (void)replay {
    if (!self.loaded || self.preview.strokes.count == 0) return;
    [self.link invalidate];
    self.replayStart = CACurrentMediaTime();
    self.preview.now = self.preview.rangeStart;
    [self.preview setNeedsDisplay];
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)tick {
    double now = self.preview.rangeStart + CACurrentMediaTime() - self.replayStart;
    if (now > MIN(self.preview.duration, self.preview.rangeEnd) + 0.05) {
        [self.link invalidate];
        self.link = nil;
        now = -1; // done: all of it, still
    }
    self.preview.now = now;
    [self.preview setNeedsDisplay];
}

#pragma mark - Trim

// Trim: the timeline under the drawing, Cancel and Save at the top. It starts at the first touch,
// so the wait before it is already cut.
- (void)startTrim {
    if (!self.loaded || self.preview.strokes.count == 0) return;
    double first = HUGE_VAL;
    NSMutableArray *segments = [NSMutableArray array];
    NSArray<UIColor *> *colors = [RCGesturePreviewView colors];
    [self.preview.strokes enumerateObjectsUsingBlock:^(RCGestureStroke *stroke, NSUInteger i, BOOL *stop) {
        if (!stroke.times.count) return;
        [segments addObject:@[stroke.times.firstObject, stroke.times.lastObject, colors[i % colors.count]]];
    }];
    for (NSArray *seg in segments) first = MIN(first, [seg[0] doubleValue]);
    self.trimming = YES;
    self.tableView.delaysContentTouches = NO; // a handle is caught at once, before the page can scroll
    self.trimBar.duration = self.preview.duration;
    self.trimBar.segments = segments;
    self.trimBar.start = first < HUGE_VAL ? MAX(0, first - 0.05) : 0;
    self.trimBar.end = self.preview.duration;
    [self.trimBar setNeedsDisplay];
    self.trimBar.hidden = NO;
    self.trimLabel.hidden = NO;
    self.replayButton.hidden = YES;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(endTrim)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTrim)];
    [self.tableView reloadData];
    [self trimChanged];
    [self replay];
}

- (void)trimChanged {
    self.preview.rangeStart = self.trimBar.start;
    self.preview.rangeEnd = self.trimBar.end;
    if (!self.link) self.preview.now = -1;
    [self.preview setNeedsDisplay];
    self.trimLabel.text = [NSString stringWithFormat:@"%.2f s \u2013 %.2f s  \u00B7  %.1f s long", self.trimBar.start, self.trimBar.end, self.trimBar.end - self.trimBar.start];
}

- (void)endTrim {
    self.trimming = NO;
    self.tableView.delaysContentTouches = YES;
    self.trimBar.hidden = YES;
    self.trimLabel.hidden = YES;
    self.replayButton.hidden = self.preview.strokes.count == 0;
    self.preview.rangeStart = 0;
    self.preview.rangeEnd = HUGE_VAL;
    self.preview.now = -1;
    [self.preview setNeedsDisplay];
    self.navigationItem.hidesBackButton = NO;
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem = nil;
    [self.tableView reloadData];
}

- (void)saveTrim {
    NSString *command = [NSString stringWithFormat:@"gesture trim \"%@\" %.3f %.3f", self.name, self.trimBar.start, self.trimBar.end];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || ![output hasPrefix:@"Trimmed"]) {
            strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
            NSString *detail = error.localizedDescription ?: [output stringByReplacingOccurrencesOfString:@"Error: " withString:@""];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't Trim" message:detail preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        [strongSelf endTrim];
        [strongSelf load];
        if (strongSelf.onChange) strongSelf.onChange();
    }];
}

#pragma mark - Rows

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.trimming ? 0 : 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RCGestureDetailSectionInfo) return 3;
    if (section == RCGestureDetailSectionActions) return 4;
    return 2; // Replace Recording, Delete Gesture
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCGestureDetailSectionInfo) return @"Tap the drawing to replay it. Numbers show the order of the touches; a ring is a tap.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    if (indexPath.section == RCGestureDetailSectionInfo) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Length";
            cell.detailTextLabel.text = self.loaded ? [NSString stringWithFormat:@"%.1f s", self.preview.duration] : @"–";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Touches";
            cell.detailTextLabel.text = self.loaded ? [NSString stringWithFormat:@"%ld", (long)self.strokeCount] : @"–";
        } else {
            cell.textLabel.text = @"Recorded";
            cell.detailTextLabel.text = self.created ? [NSDateFormatter localizedStringFromDate:self.created dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"–";
        }
        return cell;
    }
    if (indexPath.section == RCGestureDetailSectionDelete) {
        // Both lose the current recording
        BOOL replace = indexPath.row == 0;
        cell.textLabel.text = replace ? @"Replace Recording" : @"Delete Gesture";
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.imageView.image = [UIImage systemImageNamed:replace ? @"record.circle" : @"trash"];
        cell.imageView.tintColor = [UIColor systemRedColor];
        return cell;
    }
    NSArray *titles = @[@"Play on Phone", @"Trim", @"Rename", @"Export"];
    NSArray *icons = @[@"play.fill", @"scissors", @"pencil", @"square.and.arrow.up"];
    cell.textLabel.text = titles[indexPath.row];
    cell.textLabel.textColor = self.view.tintColor;
    cell.imageView.image = [UIImage systemImageNamed:icons[indexPath.row]] ?: [UIImage systemImageNamed:@"scissors"];
    cell.imageView.tintColor = self.view.tintColor;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section != RCGestureDetailSectionInfo;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == RCGestureDetailSectionInfo || !self.onAction) return;
    if (indexPath.section == RCGestureDetailSectionActions && indexPath.row == 1) {
        [self startTrim];
        return;
    }
    NSString *action = indexPath.section == RCGestureDetailSectionDelete
        ? (indexPath.row == 0 ? @"record" : @"delete")
        : @[@"play", @"", @"rename", @"export"][indexPath.row];
    self.onAction(action, [tableView cellForRowAtIndexPath:indexPath]);
}

@end
