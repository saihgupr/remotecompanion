#import "RCMenuPrompt.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

extern void SRLog(NSString *format, ...);
extern void RCMenuWakeScreenIfOff(void);

// Drawn while the phone is locked too: only secure windows show on the lock screen
@interface RCMenuWindow : UIWindow
@end
@implementation RCMenuWindow
- (BOOL)_shouldCreateContextAsSecure { return YES; }
@end

static UIWindowScene *RCMenuWindowScene(void) {
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

@interface RCMenuCard : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UILabel *countdown;
@property (nonatomic, copy) void (^onPick)(NSInteger index);
@property (nonatomic) double deadline; // CFAbsoluteTime, 0 for none
@property (nonatomic, strong) NSTimer *ticker;
@end

@implementation RCMenuCard

- (UIButton *)rowWithTitle:(NSString *)title icon:(NSString *)icon tag:(NSInteger)tag cancel:(BOOL)cancel {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
    row.tag = tag;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.contentHorizontalAlignment = cancel ? UIControlContentHorizontalAlignmentCenter : UIControlContentHorizontalAlignmentLeft;
    row.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    row.titleLabel.font = cancel ? [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold] : [UIFont systemFontOfSize:17];
    row.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [row setTitle:title forState:UIControlStateNormal];
    [row setTitleColor:cancel ? [UIColor secondaryLabelColor] : [UIColor labelColor] forState:UIControlStateNormal];
    UIImage *image = icon.length ? [UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium]] : nil;
    if (image && !cancel) {
        [row setImage:image forState:UIControlStateNormal];
        row.tintColor = [UIColor systemBlueColor];
        row.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, -10);
    }
    row.accessibilityLabel = title;
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    [row.heightAnchor constraintEqualToConstant:50].active = YES;
    return row;
}

- (void)showTitle:(NSString *)title options:(NSArray<NSDictionary *> *)options timeout:(double)timeout {
    UIWindowScene *scene = RCMenuWindowScene();
    UIWindow *window = scene ? [[RCMenuWindow alloc] initWithWindowScene:scene] : [[RCMenuWindow alloc] init];
    window.frame = [UIScreen mainScreen].bounds;
    window.windowLevel = UIWindowLevelAlert + 2600.0; // over apps, the lock screen and Control Center
    window.backgroundColor = [UIColor clearColor];
    UIViewController *root = [[UIViewController alloc] init];
    window.rootViewController = root;
    UIView *view = root.view;

    // The dim behind the card: a tap there is Cancel
    UIButton *dim = [UIButton buttonWithType:UIButtonTypeCustom];
    dim.frame = view.bounds;
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    dim.tag = RCMenuPromptCancelled;
    dim.accessibilityLabel = @"Cancel";
    [dim addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:dim];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor secondarySystemBackgroundColor];
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    [view addSubview:card];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    UIStackView *head = [[UIStackView alloc] init];
    head.axis = UILayoutConstraintAxisVertical;
    head.alignment = UIStackViewAlignmentCenter;
    head.spacing = 2;
    head.layoutMarginsRelativeArrangement = YES;
    head.layoutMargins = UIEdgeInsetsMake(14, 16, 10, 16);
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title.length ? title : @"Choose";
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.numberOfLines = 2;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [head addArrangedSubview:titleLabel];
    if (timeout > 0) {
        self.countdown = [[UILabel alloc] init];
        self.countdown.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        self.countdown.textColor = [UIColor secondaryLabelColor];
        [head addArrangedSubview:self.countdown];
    }
    [stack addArrangedSubview:head];

    // Long lists scroll; the card stays at most 70% of the screen tall
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *rows = [[UIStackView alloc] init];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:rows];
    [options enumerateObjectsUsingBlock:^(NSDictionary *option, NSUInteger i, BOOL *stop) {
        UIView *line = [[UIView alloc] init];
        line.backgroundColor = [UIColor separatorColor];
        [line.heightAnchor constraintEqualToConstant:0.5].active = YES;
        [rows addArrangedSubview:line];
        NSString *name = [option[@"name"] description].length ? [option[@"name"] description] : [NSString stringWithFormat:@"Option %lu", (unsigned long)i + 1];
        // Its own icon, or its number in a circle
        NSString *icon = [option[@"icon"] description];
        if (!icon.length || ![UIImage systemImageNamed:icon]) icon = i < 50 ? [NSString stringWithFormat:@"%lu.circle.fill", (unsigned long)i + 1] : @"circle.fill";
        [rows addArrangedSubview:[self rowWithTitle:name icon:icon tag:(NSInteger)i cancel:NO]];
    }];
    [stack addArrangedSubview:scroll];
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = [UIColor separatorColor];
    [line.heightAnchor constraintEqualToConstant:0.5].active = YES;
    [stack addArrangedSubview:line];
    [stack addArrangedSubview:[self rowWithTitle:@"Cancel" icon:nil tag:RCMenuPromptCancelled cancel:YES]];

    NSLayoutConstraint *fit = [scroll.heightAnchor constraintEqualToAnchor:rows.heightAnchor];
    fit.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:MIN(300, view.bounds.size.width - 48)],
        [card.heightAnchor constraintLessThanOrEqualToAnchor:view.heightAnchor multiplier:0.7],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [rows.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [rows.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [rows.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor],
        [rows.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor],
        fit,
    ]];

    self.window = window;
    window.hidden = NO;
    window.alpha = 0;
    card.transform = CGAffineTransformMakeScale(1.08, 1.08);
    [UIView animateWithDuration:0.2 animations:^{ window.alpha = 1; card.transform = CGAffineTransformIdentity; }];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];

    if (timeout > 0) {
        self.deadline = CFAbsoluteTimeGetCurrent() + timeout;
        [self tick];
        __weak typeof(self) weakSelf = self;
        self.ticker = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t) { [weakSelf tick]; }];
    }
}

- (void)tick {
    if (!self.deadline) return;
    double left = MAX(0, self.deadline - CFAbsoluteTimeGetCurrent());
    self.countdown.text = [NSString stringWithFormat:@"Closes in %.0f s", ceil(left)];
}

- (void)rowTapped:(UIButton *)sender {
    if (self.onPick) self.onPick(sender.tag);
    self.onPick = nil;
}

- (void)close {
    [self.ticker invalidate];
    self.ticker = nil;
    UIWindow *window = self.window;
    self.window = nil;
    [UIView animateWithDuration:0.15 animations:^{ window.alpha = 0; } completion:^(BOOL finished) { window.hidden = YES; }];
}

@end

NSInteger RCMenuPromptRun(NSString *title, NSArray<NSDictionary *> *options, double timeout, BOOL (^stopped)(void)) {
    if ([NSThread isMainThread]) return RCMenuPromptCancelled; // it waits; the main thread can't
    __block NSInteger picked = RCMenuPromptTimedOut;
    __block BOOL done = NO;
    dispatch_semaphore_t pickedSignal = dispatch_semaphore_create(0);
    __block RCMenuCard *card = nil;
    RCMenuWakeScreenIfOff();
    dispatch_sync(dispatch_get_main_queue(), ^{
        card = [[RCMenuCard alloc] init];
        card.onPick = ^(NSInteger index) {
            if (done) return;
            done = YES;
            picked = index;
            dispatch_semaphore_signal(pickedSignal);
        };
        [card showTitle:title options:options timeout:timeout];
    });
    CFAbsoluteTime deadline = timeout > 0 ? CFAbsoluteTimeGetCurrent() + timeout : 0;
    while (YES) {
        if (dispatch_semaphore_wait(pickedSignal, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC))) == 0) break;
        if (stopped && stopped()) { picked = RCMenuPromptCancelled; break; }
        if (deadline && CFAbsoluteTimeGetCurrent() >= deadline) { picked = RCMenuPromptTimedOut; break; }
    }
    dispatch_sync(dispatch_get_main_queue(), ^{
        done = YES;
        [card close];
        card = nil;
    });
    return picked;
}
