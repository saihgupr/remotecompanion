#import "RCWhatsNew.h"
#import "RCConfigManager.h"

NSString *const RCWhatsNewDismissedNotification = @"RCWhatsNewDismissedNotification";

static NSString *const kRCWhatsNewSeenKey = @"RCWhatsNewSeenVersion";   // the version whose card was last shown
static NSString *const kRCWhatsNewDismissedKey = @"RCWhatsNewDismissed"; // "t:<id>" / "a:<command>" taken out of New

#pragma mark - The text (approved before each release)

// One entry per version (major.minor). features: the card's rows, each an SF Symbol (the first this
// iOS has), its color, a title and one line. triggers / actions: what New Trigger and Select Action
// show under New. A trigger or action this build doesn't have is simply not shown.
static NSDictionary<NSString *, NSDictionary *> *RCWhatsNewReleases(void) {
    return @{
        @"4.6": @{
            @"features": @[
                @{ @"symbols": @[@"airplane.circle.fill", @"airplane"], @"color": @"orange",
                   @"title": @"Airplane Mode Triggers", @"text": @"Run actions when Airplane Mode turns on or off." },
                @{ @"symbols": @[@"iphone.landscape", @"rotate.right.fill", @"rotate.right"], @"color": @"blue",
                   @"title": @"Physical Orientation", @"text": @"Triggers for how the phone is held, and Set Orientation to turn the screen." },
                @{ @"symbols": @[@"switch.2"], @"color": @"indigo",
                   @"title": @"Control Center Button", @"text": @"A Control Center button of your own that runs a trigger." },
                @{ @"symbols": @[@"text.viewfinder", @"doc.text.viewfinder"], @"color": @"green",
                   @"title": @"Text on Screen", @"text": @"Tap, wait for or copy any text on screen, and check for it in If." },
                @{ @"symbols": @[@"timer.circle.fill", @"timer"], @"color": @"red",
                   @"title": @"Timer", @"text": @"Start a Clock timer from an action." },
                @{ @"symbols": @[@"bell.badge.fill"], @"color": @"pink",
                   @"title": @"Real Notifications", @"text": @"Notify now posts a standard iOS notification." },
            ],
            @"triggers": @[@"trigger_device_airplane_on", @"trigger_device_airplane_off",
                           @"trigger_device_orientation_portrait_up", @"trigger_device_orientation_landscape_left",
                           @"trigger_device_orientation_landscape_right", @"trigger_device_orientation_portrait_upside_down",
                           @"Control Center Button", @"Action Sequence Edited"],
            @"actions": @[@"__SET_ORIENTATION__", @"__TIMER__", @"__SCREEN_TAP__", @"__SCREEN_WAIT__", @"screen copy rect", @"screen copy"],
        },
    };
}

// A first install: what RemoteCompanion is, on the same card
static NSArray<NSDictionary *> *RCWhatsNewWelcomeFeatures(void) {
    return @[
        @{ @"symbols": @[@"hand.tap.fill"], @"color": @"blue",
           @"title": @"Triggers", @"text": @"Buttons, gestures, apps, places and times can each start something." },
        @{ @"symbols": @[@"bolt.circle.fill", @"bolt.fill"], @"color": @"orange",
           @"title": @"Actions", @"text": @"Each trigger runs a list of actions, from media and settings to scripts." },
        @{ @"symbols": @[@"puzzlepiece.extension.fill", @"square.grid.2x2.fill"], @"color": @"green",
           @"title": @"Ready-made Pieces", @"text": @"Add-ons, Shortcuts, Home Assistant and more plug in as actions." },
        @{ @"symbols": @[@"globe.americas.fill", @"globe"], @"color": @"indigo",
           @"title": @"Web UI", @"text": @"Set everything up from a computer on the same Wi-Fi." },
    ];
}

#pragma mark - The card

@interface RCWhatsNewViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle features:(NSArray<NSDictionary *> *)features button:(NSString *)button;
@end

@interface RCWhatsNewViewController ()
@property (nonatomic, copy) NSString *cardTitle;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSArray<NSDictionary *> *features;
@property (nonatomic, copy) NSString *buttonTitle;
@property (nonatomic, strong) NSArray<UIView *> *rows;
@property (nonatomic, assign) BOOL played;
@end

static UIColor *RCWhatsNewColor(NSString *name) {
    NSDictionary *colors = @{ @"blue": [UIColor systemBlueColor], @"orange": [UIColor systemOrangeColor], @"green": [UIColor systemGreenColor],
                              @"indigo": [UIColor systemIndigoColor], @"red": [UIColor systemRedColor], @"pink": [UIColor systemPinkColor],
                              @"purple": [UIColor systemPurpleColor], @"teal": [UIColor systemTealColor], @"yellow": [UIColor systemYellowColor] };
    return colors[name] ?: [UIColor systemBlueColor];
}

static UIImage *RCWhatsNewSymbol(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        UIImage *image = [UIImage systemImageNamed:name];
        if (image) return image;
    }
    return [UIImage systemImageNamed:@"star.fill"];
}

// Drawn where no symbol shows it. "island": the top of an iPhone, the Dynamic Island in it (its
// camera a dot at the right end)
static UIImage *RCWhatsNewDrawn(NSString *name, CGFloat side) {
    if (![name isEqualToString:@"island"]) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        CGFloat k = side / 40.0;
        [[UIColor blackColor] setStroke];
        [[UIColor blackColor] setFill];
        // The phone's top, its sides running off the bottom
        UIBezierPath *phone = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(4 * k, 5 * k, 32 * k, 46 * k) cornerRadius:10 * k];
        phone.lineWidth = 2.6 * k;
        [phone stroke];
        // The island
        UIBezierPath *island = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(11 * k, 10.5 * k, 18 * k, 7 * k) cornerRadius:3.5 * k];
        [island fill];
        CGContextSetBlendMode(context, kCGBlendModeClear);
        CGContextFillEllipseInRect(context, CGRectMake(23.6 * k, 12.6 * k, 2.8 * k, 2.8 * k));
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        // A tap on it
        CGContextSetAlpha(context, 0.55);
        UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(13 * k, 22 * k, 14 * k, 14 * k)];
        ring.lineWidth = 2 * k;
        [ring stroke];
        CGContextSetAlpha(context, 1);
        CGContextFillEllipseInRect(context, CGRectMake(17 * k, 26 * k, 6 * k, 6 * k));
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@implementation RCWhatsNewViewController

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle features:(NSArray<NSDictionary *> *)features button:(NSString *)button {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _cardTitle = [title copy];
        _subtitle = [subtitle copy];
        _features = [features copy];
        _buttonTitle = [button copy];
        self.modalPresentationStyle = UIModalPresentationPageSheet;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 26;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    UILabel *title = [[UILabel alloc] init];
    title.text = self.cardTitle;
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 0;
    title.adjustsFontForContentSizeCategory = YES;
    [stack addArrangedSubview:title];
    if (self.subtitle.length) {
        UILabel *subtitle = [[UILabel alloc] init];
        subtitle.text = self.subtitle;
        subtitle.font = [UIFont systemFontOfSize:17];
        subtitle.textColor = [UIColor secondaryLabelColor];
        subtitle.textAlignment = NSTextAlignmentCenter;
        subtitle.numberOfLines = 0;
        [stack addArrangedSubview:subtitle];
        [stack setCustomSpacing:12 afterView:title];
    }
    [stack setCustomSpacing:40 afterView:stack.arrangedSubviews.lastObject];

    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *feature in self.features) {
        UIView *row = [self rowForFeature:feature];
        [stack addArrangedSubview:row];
        [rows addObject:row];
    }
    self.rows = rows;

    // The button stays at the bottom, over the list's end
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:self.buttonTitle forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor systemBlueColor];
    button.layer.cornerRadius = 14;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button addTarget:self action:@selector(done) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:button.topAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:56],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:40],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-40],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:520],
        [button.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [button.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [button.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
        [button.heightAnchor constraintEqualToConstant:52],
    ]];
}

- (UIView *)rowForFeature:(NSDictionary *)feature {
    UIColor *color = RCWhatsNewColor(feature[@"color"]);
    UIImage *drawn = RCWhatsNewDrawn(feature[@"drawn"], 40);
    UIImageView *icon = [[UIImageView alloc] initWithImage:drawn ?: RCWhatsNewSymbol(feature[@"symbols"])];
    UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightRegular];
    // Two tones of its color where iOS has them (15 and later), as Apple's own What's New does
    if (@available(iOS 15.0, *)) size = [size configurationByApplyingConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:color]];
    icon.preferredSymbolConfiguration = size;
    icon.tintColor = color;
    icon.contentMode = drawn ? UIViewContentModeScaleAspectFit : UIViewContentModeCenter;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:46].active = YES;
    [icon.heightAnchor constraintEqualToConstant:40].active = YES;

    UILabel *title = [[UILabel alloc] init];
    title.text = feature[@"title"];
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    title.numberOfLines = 0;
    UILabel *text = [[UILabel alloc] init];
    text.text = feature[@"text"];
    text.font = [UIFont systemFontOfSize:15];
    text.textColor = [UIColor secondaryLabelColor];
    text.numberOfLines = 0;
    UIStackView *words = [[UIStackView alloc] initWithArrangedSubviews:@[title, text]];
    words.axis = UILayoutConstraintAxisVertical;
    words.spacing = 2;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, words]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 16;
    row.isAccessibilityElement = YES;
    row.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", feature[@"title"], feature[@"text"]];
    return row;
}

// The rows come in one after another the first time the card shows (still with Reduce Motion)
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.played || UIAccessibilityIsReduceMotionEnabled()) return;
    for (UIView *row in self.rows) {
        row.alpha = 0;
        row.transform = CGAffineTransformMakeTranslation(0, 14);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.played) return;
    self.played = YES;
    [self.rows enumerateObjectsUsingBlock:^(UIView *row, NSUInteger i, BOOL *stop) {
        [UIView animateWithDuration:0.45 delay:0.08 * i usingSpringWithDamping:0.9 initialSpringVelocity:0
                            options:UIViewAnimationOptionAllowUserInteraction animations:^{
            row.alpha = 1;
            row.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

- (void)done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - When it shows

@implementation RCWhatsNew

// "4.6.0" -> "4.6"
+ (NSString *)currentRelease {
    NSString *version = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: @"";
    NSArray *parts = [version componentsSeparatedByString:@"."];
    return parts.count >= 2 ? [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]] : version;
}

+ (NSDictionary *)currentEntry {
    return RCWhatsNewReleases()[[self currentRelease]];
}

+ (NSString *)whatsNewTitle {
    return [NSString stringWithFormat:@"What's New in %@", [self currentRelease]];
}

+ (BOOL)hasWhatsNew {
    return [[self currentEntry][@"features"] count] > 0;
}

+ (void)present:(UIViewController *)card from:(UIViewController *)host {
    UIViewController *top = host;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:card animated:YES completion:nil];
}

+ (void)showWhatsNewFrom:(UIViewController *)host {
    NSDictionary *entry = [self currentEntry];
    if (![entry[@"features"] count]) return;
    [self present:[[RCWhatsNewViewController alloc] initWithTitle:[self whatsNewTitle] subtitle:nil features:entry[@"features"] button:@"Continue"] from:host];
}

+ (void)showIfNeededFrom:(UIViewController *)host {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *current = [self currentRelease];
    NSString *seen = [defaults stringForKey:kRCWhatsNewSeenKey];
    if ([seen isEqualToString:current]) return;
    [defaults setObject:current forKey:kRCWhatsNewSeenKey];
    // Never seen a card: a first install, unless triggers were already set up (an update from a
    // version before this card)
    BOOL firstInstall = !seen && [[RCConfigManager sharedManager] allConfiguredTriggerKeys].count == 0;
    if (firstInstall) {
        [self present:[[RCWhatsNewViewController alloc] initWithTitle:@"Welcome to RemoteCompanion"
                                                             subtitle:@"Make your iPhone's buttons, gestures and more do what you want."
                                                             features:RCWhatsNewWelcomeFeatures() button:@"Get Started"] from:host];
        return;
    }
    [self showWhatsNewFrom:host];
}

#pragma mark - New items

+ (NSMutableSet<NSString *> *)dismissed {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kRCWhatsNewDismissedKey];
    return [NSMutableSet setWithArray:[saved isKindOfClass:[NSArray class]] ? saved : @[]];
}

+ (void)dismissIds:(NSArray<NSString *> *)ids {
    if (!ids.count) return;
    NSMutableSet *dismissed = [self dismissed];
    NSUInteger before = dismissed.count;
    [dismissed addObjectsFromArray:ids];
    if (dismissed.count == before) return;
    [[NSUserDefaults standardUserDefaults] setObject:dismissed.allObjects forKey:kRCWhatsNewDismissedKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCWhatsNewDismissedNotification object:nil];
}

+ (BOOL)isNewTrigger:(NSString *)itemId {
    if (!itemId.length || ![[self currentEntry][@"triggers"] containsObject:itemId]) return NO;
    return ![[self dismissed] containsObject:[@"t:" stringByAppendingString:itemId]];
}

+ (BOOL)isNewAction:(NSString *)command {
    if (!command.length || ![[self currentEntry][@"actions"] containsObject:command]) return NO;
    return ![[self dismissed] containsObject:[@"a:" stringByAppendingString:command]];
}

+ (void)dismissTrigger:(NSString *)itemId { if (itemId) [self dismissTriggers:@[itemId]]; }
+ (void)dismissAction:(NSString *)command { if (command) [self dismissActions:@[command]]; }

+ (void)dismissTriggers:(NSArray<NSString *> *)itemIds {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *itemId in itemIds) [ids addObject:[@"t:" stringByAppendingString:itemId]];
    [self dismissIds:ids];
}

+ (void)dismissActions:(NSArray<NSString *> *)commands {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *command in commands) [ids addObject:[@"a:" stringByAppendingString:command]];
    [self dismissIds:ids];
}

// Red and small, like an app's notification badge, to sit on a tile's top right corner
+ (UILabel *)newTag {
    UILabel *tag = [[UILabel alloc] init];
    tag.text = @"NEW";
    tag.font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightHeavy];
    tag.textColor = [UIColor whiteColor];
    tag.backgroundColor = [UIColor systemRedColor];
    tag.textAlignment = NSTextAlignmentCenter;
    tag.clipsToBounds = YES;
    CGSize size = [tag.text sizeWithAttributes:@{ NSFontAttributeName: tag.font }];
    tag.frame = CGRectMake(0, 0, ceil(size.width) + 8, 14);
    tag.layer.cornerRadius = 7;
    tag.isAccessibilityElement = NO;
    tag.userInteractionEnabled = NO;
    return tag;
}

// A list row's mark: a small red dot, as on an app with something new
+ (UIView *)newDot {
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    dot.backgroundColor = [UIColor systemRedColor];
    dot.layer.cornerRadius = 5;
    dot.userInteractionEnabled = NO;
    dot.isAccessibilityElement = NO;
    return dot;
}

// The tag tight on a tile's own top right corner, just over its edges, as on a Home Screen app
+ (void)pinTag:(UIView *)tag toCornerOf:(UIView *)tile in:(UIView *)container {
    CGSize size = tag.bounds.size;
    tag.translatesAutoresizingMaskIntoConstraints = NO;
    tag.layer.zPosition = 10; // over the tile beside it
    [container addSubview:tag];
    [NSLayoutConstraint activateConstraints:@[
        // Above the tile's own corner mark (its chevron or check, 7 points in), clear of it
        [tag.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:4],
        [tag.topAnchor constraintEqualToAnchor:tile.topAnchor constant:-7],
        [tag.widthAnchor constraintEqualToConstant:size.width],
        [tag.heightAnchor constraintEqualToConstant:size.height],
    ]];
}

+ (void)pinTag:(UIView *)tag toIcon:(UIView *)icon in:(UIView *)container {
    CGSize size = tag.bounds.size;
    tag.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:tag];
    [NSLayoutConstraint activateConstraints:@[
        // A little in from the icon's top right, the dot mostly over the corner
        [tag.centerXAnchor constraintEqualToAnchor:icon.trailingAnchor constant:-1],
        [tag.centerYAnchor constraintEqualToAnchor:icon.topAnchor constant:3],
        [tag.widthAnchor constraintEqualToConstant:size.width],
        [tag.heightAnchor constraintEqualToConstant:size.height],
    ]];
}

+ (void)placeTag:(UIView *)tag onIcon:(UIView *)icon {
    if (!tag || !icon || icon.hidden || CGRectIsEmpty(icon.frame)) { tag.hidden = YES; return; }
    CGRect frame = [icon.superview convertRect:icon.frame toView:tag.superview];
    // The icon's top right corner, the dot mostly over it
    tag.center = CGPointMake(CGRectGetMaxX(frame) - 1, CGRectGetMinY(frame) + 3);
    tag.hidden = NO;
    [tag.superview bringSubviewToFront:tag];
}

@end
