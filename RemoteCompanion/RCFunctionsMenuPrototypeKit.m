#import "RCFunctionsMenuPrototypeKit.h"
#import "RCConfigManager.h"

#import <math.h>

#pragma mark - Shared look

const CGFloat RCFMColumnBreak = 700.0;

UIColor *RCFMPageColor(void) {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    // The picker's own background, which falls back to the main one
    CGFloat main = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    return [cm tweakColorForKey:@"actionPickerBackground" defaultVal:main];
}

UIColor *RCFMBlockColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12];
}

UIColor *RCFMBorderColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"borders" defaultVal:0.14];
}

UIColor *RCFMSeparatorColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"separators" defaultVal:0.30];
}

UIColor *RCFMAccent(void) {
    return [UIColor systemBlueColor];
}

CGFloat RCFMBasePointSize(UIFontTextStyle style) {
    if ([style isEqualToString:UIFontTextStyleLargeTitle]) return 34;
    if ([style isEqualToString:UIFontTextStyleTitle1]) return 28;
    if ([style isEqualToString:UIFontTextStyleTitle2]) return 22;
    if ([style isEqualToString:UIFontTextStyleTitle3]) return 20;
    if ([style isEqualToString:UIFontTextStyleHeadline]) return 17;
    if ([style isEqualToString:UIFontTextStyleBody]) return 17;
    if ([style isEqualToString:UIFontTextStyleCallout]) return 16;
    if ([style isEqualToString:UIFontTextStyleSubheadline]) return 15;
    if ([style isEqualToString:UIFontTextStyleFootnote]) return 13;
    if ([style isEqualToString:UIFontTextStyleCaption1]) return 12;
    if ([style isEqualToString:UIFontTextStyleCaption2]) return 11;
    return 17;
}

UIFont *RCFMFont(UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:RCFMBasePointSize(style) weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

UIFont *RCFMMonoFont(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

static UIImage *RCFMSymbolImage(NSString *name, CGFloat pointSize, UIFontWeight weight) {
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return nil;
    return [UIImage systemImageNamed:name
                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight]];
}

static BOOL RCFMUsesAccessibilityText(void) {
    return UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory);
}

#pragma mark - Catalog

static NSDictionary *RCFMAction(NSString *name, NSString *icon, NSString *subtitle) {
    NSMutableDictionary *action = [@{ @"name": name, @"icon": icon, @"subtitle": subtitle ?: @"" } mutableCopy];
    return action;
}

static NSArray<NSString *> *RCFMTitles;
static NSArray<NSArray<NSDictionary *> *> *RCFMAllSections;

static void RCFMBuildCatalog(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        RCFMTitles = @[@"Media", @"Sound", @"Capture", @"Apps & Navigation", @"Device Controls",
                       @"Connectivity", @"System", @"Integrations", @"Scripting & Logic"];

        NSArray *media = @[
            RCFMAction(@"Play", @"play.fill", @"Start the current track"),
            RCFMAction(@"Pause", @"pause.fill", @"Hold the current track"),
            RCFMAction(@"Play/Pause", @"playpause.fill", @"Toggle playback"),
            RCFMAction(@"Next Track", @"forward.fill", @"Skip to the next song"),
        ];
        NSArray *sound = @[
            RCFMAction(@"Volume Up", @"speaker.wave.3.fill", @"A few steps louder"),
            RCFMAction(@"Volume Down", @"speaker.wave.1.fill", @"A few steps quieter"),
            RCFMAction(@"Set Volume...", @"slider.horizontal.3", @"Pick an exact level"),
            RCFMAction(@"Set Ringer Volume...", @"bell.fill", @"Pick the ring level"),
            RCFMAction(@"Mute", @"speaker.slash.fill", @"Silence the output"),
            RCFMAction(@"Noise Control", @"ear", @"Cycle the noise modes"),
        ];
        NSArray *capture = @[
            RCFMAction(@"Screenshot", @"camera.viewfinder", @"Save a picture of the screen"),
            RCFMAction(@"Screen Recording", @"record.circle.fill", @"Start or stop a recording"),
            RCFMAction(@"Open Camera...", @"camera.fill", @"Choose front or back"),
            RCFMAction(@"Camera Shutter / Snap", @"camera.circle.fill", @"Take a photo now"),
        ];
        NSArray *apps = @[
            RCFMAction(@"Open App...", @"square.grid.2x2.fill", @"Pick from installed apps"),
            RCFMAction(@"Home Button", @"house.fill", @"Go to the Home Screen"),
            RCFMAction(@"App Switcher", @"square.stack.3d.up.fill", @"Show the open apps"),
            RCFMAction(@"Control Center", @"switch.2", @"Open Control Center"),
            RCFMAction(@"Activate Siri", @"mic.circle.fill", @"Start a Siri request"),
            RCFMAction(@"Record Gesture", @"record.circle", @"Record taps and swipes"),
        ];
        NSArray *device = @[
            RCFMAction(@"Appearance", @"circle.lefthalf.fill", @"Light or dark"),
            RCFMAction(@"Set Brightness...", @"sun.max.fill", @"Pick an exact level"),
            RCFMAction(@"Flashlight", @"flashlight.on.fill", @"Toggle the light"),
            RCFMAction(@"Lock Device", @"lock.fill", @"Lock the screen"),
            RCFMAction(@"Do Not Disturb", @"moon.circle.fill", @"Toggle Focus"),
            RCFMAction(@"Set Focus...", @"moon.circle", @"Pick a Focus mode"),
            RCFMAction(@"Timer...", @"timer", @"Start a countdown"),
        ];
        NSArray *connectivity = @[
            RCFMAction(@"Wi-Fi", @"wifi", @"Toggle Wi-Fi"),
            RCFMAction(@"Bluetooth", @"bolt.horizontal.fill", @"Toggle Bluetooth"),
            RCFMAction(@"Airplane Mode", @"airplane", @"Turn every radio off"),
            RCFMAction(@"Connect AirPlay...", @"airplayaudio", @"Pick an output"),
            RCFMAction(@"Location Services", @"location.fill", @"Toggle location"),
        ];
        NSArray *system = @[
            RCFMAction(@"Respring Device", @"memories", @"Restart SpringBoard"),
            RCFMAction(@"Safe Mode", @"shield.slash.fill", @"Reboot into Safe Mode"),
            RCFMAction(@"Soft Reboot (ldrestart)", @"arrow.clockwise", @"Restart without a full boot"),
            RCFMAction(@"Refresh Icon Cache (uicache)", @"square.grid.2x2", @"Rebuild the Home Screen icons"),
        ];
        NSArray *integrations = @[
            RCFMAction(@"Home Assistant: Control Entity...", @"lightbulb.fill", @"Pick an entity and action"),
            RCFMAction(@"Keyboard Maestro: Trigger Macro...", @"command", @"Run a macro on the Mac"),
            RCFMAction(@"SSH: Run Remote Command...", @"terminal.fill", @"Run a command over SSH"),
            RCFMAction(@"REST API Call...", @"network", @"Send an HTTP request"),
            RCFMAction(@"Shortcuts: Run Shortcut...", @"wand.and.stars", @"Run any shortcut"),
            RCFMAction(@"Remote RC: Run Command...", @"iphone.radiowaves.left.and.right", @"Send to another device"),
        ];
        NSArray *scripting = @[
            RCFMAction(@"Custom Lua Script", @"scroll.fill", @"Run your own script"),
            RCFMAction(@"If Condition...", @"arrow.triangle.branch", @"Branch on a condition"),
            RCFMAction(@"Repeat...", @"repeat", @"Loop a set number of times"),
            RCFMAction(@"Delay", @"hourglass", @"Wait before the next step"),
            RCFMAction(@"Set Variable...", @"x.squareroot", @"Store a value"),
            RCFMAction(@"Notification...", @"bell.badge.fill", @"Show a notification"),
        ];

        RCFMAllSections = @[media, sound, capture, apps, device, connectivity, system, integrations, scripting];
    });
}

NSArray<NSString *> *RCFMSectionTitles(void) {
    RCFMBuildCatalog();
    return RCFMTitles;
}

NSArray<NSArray<NSDictionary *> *> *RCFMSections(void) {
    RCFMBuildCatalog();
    return RCFMAllSections;
}

NSDictionary *RCFMActionNamed(NSString *name) {
    RCFMBuildCatalog();
    for (NSArray<NSDictionary *> *section in RCFMAllSections) {
        for (NSDictionary *action in section) {
            if ([action[@"name"] isEqualToString:name]) return action;
        }
    }
    return nil;
}

NSString *RCFMSectionIcon(NSString *title) {
    static NSDictionary *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        icons = @{ @"Media": @"play.rectangle.fill",
                   @"Sound": @"speaker.wave.2.fill",
                   @"Capture": @"camera.fill",
                   @"Apps & Navigation": @"square.grid.2x2.fill",
                   @"Device Controls": @"slider.horizontal.3",
                   @"Connectivity": @"wifi",
                   @"System": @"gearshape.fill",
                   @"Integrations": @"puzzlepiece.extension.fill",
                   @"Scripting & Logic": @"chevron.left.forwardslash.chevron.right" };
    });
    return icons[title];
}

NSString *RCFMShortSectionTitle(NSString *title) {
    static NSDictionary *shortTitles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shortTitles = @{ @"Media": @"Media",
                         @"Sound": @"Sound",
                         @"Capture": @"Capture",
                         @"Apps & Navigation": @"Apps",
                         @"Device Controls": @"Device",
                         @"Connectivity": @"Network",
                         @"System": @"System",
                         @"Integrations": @"Integration",
                         @"Scripting & Logic": @"Logic" };
    });
    return shortTitles[title] ?: title;
}

#pragma mark - Chip

@interface RCFMChipView ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIStackView *row;
@property (nonatomic, assign) BOOL compact;
@end

@implementation RCFMChipView

- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol compact:(BOOL)compact {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _compact = compact;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = title;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.layer.masksToBounds = YES;

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.image = RCFMSymbolImage(symbol, compact ? 11 : 12, UIFontWeightSemibold);
        _iconView.hidden = (_iconView.image == nil);

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = RCFMFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
        _titleLabel.numberOfLines = 1;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _row = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _titleLabel]];
        _row.axis = UILayoutConstraintAxisHorizontal;
        _row.alignment = UIStackViewAlignmentCenter;
        _row.spacing = compact ? 5 : 6;
        _row.layoutMarginsRelativeArrangement = YES;
        _row.layoutMargins = compact ? UIEdgeInsetsMake(6, 11, 6, 12) : UIEdgeInsetsMake(7, 14, 7, 14);
        _row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_row];

        [NSLayoutConstraint activateConstraints:@[
            [_row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_row.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:compact ? 12 : 13],
            [_iconView.heightAnchor constraintEqualToConstant:compact ? 12 : 13],
        ]];
        [self applyLook];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetMidY(self.bounds);
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [self applyLook];
}

- (void)setUsesAccent:(BOOL)usesAccent {
    _usesAccent = usesAccent;
    [self applyLook];
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self applyLook];
}

- (void)applyLook {
    UIColor *accent = RCFMAccent();
    if (self.isChosen) {
        self.backgroundColor = self.usesAccent ? accent : [UIColor labelColor];
        UIColor *onFill = self.usesAccent ? [UIColor whiteColor] : [UIColor systemBackgroundColor];
        self.titleLabel.textColor = onFill;
        self.iconView.tintColor = onFill;
        self.accessibilityTraits |= UIAccessibilityTraitSelected;
    } else {
        self.backgroundColor = [UIColor tertiarySystemFillColor];
        self.titleLabel.textColor = [UIColor labelColor];
        self.iconView.tintColor = self.usesAccent ? accent : [UIColor labelColor];
        self.accessibilityTraits &= ~UIAccessibilityTraitSelected;
    }
}

@end

#pragma mark - Search field

@interface RCFMSearchFieldView ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) UIImageView *clearView;
@end

@implementation RCFMSearchFieldView

- (instancetype)initWithPlaceholder:(NSString *)placeholder text:(NSString *)text large:(BOOL)large {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [UIColor tertiarySystemFillColor];
        self.layer.cornerRadius = large ? 12 : 10;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _iconView = [[UIImageView alloc] init];
        _iconView.image = RCFMSymbolImage(@"magnifyingglass", large ? 17 : 15, UIFontWeightMedium);
        _iconView.tintColor = [UIColor secondaryLabelColor];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;

        _textLabel = [[UILabel alloc] init];
        _textLabel.font = RCFMFont(UIFontTextStyleBody, UIFontWeightRegular);
        _textLabel.text = text.length ? text : placeholder;
        _textLabel.textColor = text.length ? [UIColor labelColor] : [UIColor secondaryLabelColor];
        _textLabel.textAlignment = (!text.length && !large) ? NSTextAlignmentCenter : NSTextAlignmentLeft;
        _textLabel.numberOfLines = 1;
        _textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _textLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_iconView];
        [self addSubview:_textLabel];

        NSMutableArray *constraints = [NSMutableArray arrayWithArray:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:large ? 46 : 38],
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:large ? 14 : 11],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:large ? 18 : 16],
            [_iconView.heightAnchor constraintEqualToConstant:large ? 18 : 16],
            [_textLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:8],
            [_textLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_textLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:6],
            [_textLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-6],
        ]];

        if (text.length) {
            _clearView = [[UIImageView alloc] init];
            _clearView.image = RCFMSymbolImage(@"xmark.circle.fill", large ? 16 : 14, UIFontWeightRegular);
            _clearView.tintColor = [UIColor tertiaryLabelColor];
            _clearView.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:_clearView];
            [constraints addObjectsFromArray:@[
                [_clearView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
                [_clearView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
                [_clearView.widthAnchor constraintEqualToConstant:large ? 16 : 14],
                [_clearView.heightAnchor constraintEqualToConstant:large ? 16 : 14],
                [_textLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_clearView.leadingAnchor constant:-6],
            ]];
        } else {
            [constraints addObject:[_textLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12]];
        }

        [NSLayoutConstraint activateConstraints:constraints];
        self.accessibilityElementsHidden = YES;
    }
    return self;
}

@end

#pragma mark - Row

@interface RCFMRowView ()
@property (nonatomic, strong) UIStackView *row;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIView *tagView;
@property (nonatomic, strong) UILabel *tagLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@end

@implementation RCFMRowView

- (instancetype)initWithAction:(NSDictionary *)action {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _iconView = [[UIImageView alloc] init];
        _iconView.tintColor = [UIColor secondaryLabelColor];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = RCFMFont(UIFontTextStyleBody, UIFontWeightRegular);
        _nameLabel.textColor = [UIColor labelColor];
        _nameLabel.numberOfLines = 0;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_nameLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = RCFMMonoFont(15, UIFontTextStyleSubheadline, UIFontWeightRegular);
        _valueLabel.textColor = [UIColor secondaryLabelColor];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.numberOfLines = 1;
        _valueLabel.hidden = YES;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _tagLabel = [[UILabel alloc] init];
        _tagLabel.font = RCFMFont(UIFontTextStyleCaption2, UIFontWeightSemibold);
        _tagLabel.textColor = [UIColor secondaryLabelColor];
        _tagLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _tagView = [[UIView alloc] init];
        _tagView.backgroundColor = [UIColor tertiarySystemFillColor];
        _tagView.layer.cornerRadius = 5;
        _tagView.hidden = YES;
        _tagView.translatesAutoresizingMaskIntoConstraints = NO;
        [_tagView addSubview:_tagLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_tagLabel.leadingAnchor constraintEqualToAnchor:_tagView.leadingAnchor constant:6],
            [_tagLabel.trailingAnchor constraintEqualToAnchor:_tagView.trailingAnchor constant:-6],
            [_tagLabel.topAnchor constraintEqualToAnchor:_tagView.topAnchor constant:2],
            [_tagLabel.bottomAnchor constraintEqualToAnchor:_tagView.bottomAnchor constant:-2],
            [_tagView.heightAnchor constraintGreaterThanOrEqualToConstant:18],
            [_tagLabel.centerYAnchor constraintEqualToAnchor:_tagView.centerYAnchor],
        ]];
        [_tagView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_tagView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _chevronView = [[UIImageView alloc] init];
        _chevronView.image = RCFMSymbolImage(@"chevron.right", 11, UIFontWeightSemibold);
        _chevronView.tintColor = [UIColor tertiaryLabelColor];
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        _chevronView.hidden = YES;
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;

        _row = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _nameLabel, _valueLabel, _tagView, _chevronView]];
        _row.axis = UILayoutConstraintAxisHorizontal;
        _row.alignment = UIStackViewAlignmentCenter;
        _row.spacing = 12;
        _row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_row];

        [NSLayoutConstraint activateConstraints:@[
            [_row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_row.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [_row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:52],
            [_iconView.widthAnchor constraintEqualToConstant:24],
            [_iconView.heightAnchor constraintEqualToConstant:22],
            [_chevronView.widthAnchor constraintEqualToConstant:8],
            [_chevronView.heightAnchor constraintEqualToConstant:14],
        ]];

        [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;

        self.name = action[@"name"];
        self.symbol = action[@"icon"];
        self.opensMore = [self actionOpensMore:action];
    }
    return self;
}

- (BOOL)actionOpensMore:(NSDictionary *)action {
    NSString *name = action[@"name"];
    if ([name isKindOfClass:[NSString class]] && [name hasSuffix:@"..."]) return YES;
    return [name isEqualToString:@"Record Gesture"] || [name isEqualToString:@"Custom Lua Script"];
}

- (void)setName:(NSString *)name {
    _name = [name copy];
    self.nameLabel.text = name;
    self.accessibilityLabel = name;
}

- (void)setSymbol:(NSString *)symbol {
    _symbol = [symbol copy];
    self.iconView.image = RCFMSymbolImage(symbol, 17, UIFontWeightRegular);
}

- (void)setValueText:(NSString *)valueText {
    _valueText = [valueText copy];
    self.valueLabel.text = valueText;
    self.valueLabel.hidden = valueText.length == 0;
}

- (void)setCategoryTag:(NSString *)categoryTag {
    _categoryTag = [categoryTag copy];
    self.tagLabel.text = categoryTag.length ? categoryTag.uppercaseString : nil;
    self.tagView.hidden = categoryTag.length == 0;
}

- (void)setOpensMore:(BOOL)opensMore {
    _opensMore = opensMore;
    self.chevronView.hidden = !opensMore;
    self.accessibilityHint = opensMore ? @"Asks for more" : nil;
}

- (void)setTopHit:(BOOL)topHit {
    _topHit = topHit;
    self.backgroundColor = topHit ? [RCFMAccent() colorWithAlphaComponent:0.16] : [UIColor clearColor];
    self.iconView.tintColor = topHit ? RCFMAccent() : [UIColor secondaryLabelColor];
    self.accessibilityValue = topHit ? @"Top result" : nil;
}

@end

NSArray<RCFMRowView *> *RCFMRowsForActions(NSArray<NSDictionary *> *actions) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *action in actions) {
        [rows addObject:[[RCFMRowView alloc] initWithAction:action]];
    }
    return rows;
}

NSArray<RCFMRowView *> *RCFMRowsForNames(NSArray<NSString *> *names) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *name in names) {
        NSDictionary *action = RCFMActionNamed(name);
        if (action) [rows addObject:[[RCFMRowView alloc] initWithAction:action]];
    }
    return rows;
}

#pragma mark - Tile

@interface RCFMTileView ()
@property (nonatomic, strong) UIView *iconWell;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIStackView *column;
@end

@implementation RCFMTileView

- (instancetype)initWithAction:(NSDictionary *)action {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = RCFMBlockColor();
        self.layer.cornerRadius = 14;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _iconWell = [[UIView alloc] init];
        _iconWell.backgroundColor = [RCFMAccent() colorWithAlphaComponent:0.16];
        _iconWell.layer.cornerRadius = 10;
        _iconWell.layer.cornerCurve = kCACornerCurveContinuous;
        _iconWell.translatesAutoresizingMaskIntoConstraints = NO;

        _iconView = [[UIImageView alloc] init];
        _iconView.image = RCFMSymbolImage(action[@"icon"], 18, UIFontWeightRegular);
        _iconView.tintColor = RCFMAccent();
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconWell addSubview:_iconView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.text = action[@"name"] ?: @"";
        _nameLabel.font = RCFMFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
        _nameLabel.textColor = [UIColor labelColor];
        _nameLabel.numberOfLines = 0;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.text = action[@"subtitle"];
        _subtitleLabel.font = RCFMFont(UIFontTextStyleFootnote, UIFontWeightRegular);
        _subtitleLabel.textColor = [UIColor secondaryLabelColor];
        _subtitleLabel.numberOfLines = 1;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _column = [[UIStackView alloc] initWithArrangedSubviews:@[_iconWell, _nameLabel, _subtitleLabel]];
        _column.axis = UILayoutConstraintAxisVertical;
        _column.alignment = UIStackViewAlignmentLeading;
        _column.spacing = 8;
        [_column setCustomSpacing:2 afterView:_nameLabel];
        _column.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_column];

        [NSLayoutConstraint activateConstraints:@[
            [_column.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_column.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_column.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
            [_column.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
            [_iconWell.widthAnchor constraintEqualToConstant:36],
            [_iconWell.heightAnchor constraintEqualToConstant:36],
            [_iconView.centerXAnchor constraintEqualToAnchor:_iconWell.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconWell.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:20],
            [_iconView.heightAnchor constraintEqualToConstant:20],
            [_nameLabel.widthAnchor constraintEqualToAnchor:_column.widthAnchor],
            [_subtitleLabel.widthAnchor constraintEqualToAnchor:_column.widthAnchor],
        ]];

        self.isAccessibilityElement = YES;
        self.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", action[@"name"], action[@"subtitle"]];
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

@end

NSArray<NSArray<RCFMTileView *> *> *RCFMTileRowsForActions(NSArray<NSDictionary *> *actions) {
    NSInteger columns = RCFMUsesAccessibilityText() ? 1 : 2;
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *current = [NSMutableArray array];
    for (NSDictionary *action in actions) {
        [current addObject:[[RCFMTileView alloc] initWithAction:action]];
        if ((NSInteger)current.count == columns) {
            [rows addObject:[current copy]];
            [current removeAllObjects];
        }
    }
    if (current.count) [rows addObject:[current copy]];
    return rows;
}

#pragma mark - Screen

static UIView *RCFMSeparator(void);

@interface RCFMScreenView ()
@property (nonatomic, strong, readwrite) UIStackView *stack;
@end

@implementation RCFMScreenView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = RCFMPageColor();
        _stack = [[UIStackView alloc] init];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 0;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

static UIView *RCFMPadded(UIView *view, CGFloat leading, CGFloat trailing, CGFloat top, CGFloat bottom) {
    UIView *holder = [[UIView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [holder addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:leading],
        [view.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-trailing],
        [view.topAnchor constraintEqualToAnchor:holder.topAnchor constant:top],
        [view.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor constant:-bottom],
    ]];
    return holder;
}

- (void)addHeaderWithTitle:(NSString *)title showsCancel:(BOOL)showsCancel compact:(BOOL)compact {
    UIView *header = [[UIView alloc] init];

    UILabel *cancel = [[UILabel alloc] init];
    cancel.text = @"Cancel";
    cancel.font = RCFMFont(UIFontTextStyleBody, UIFontWeightRegular);
    cancel.textColor = [UIColor labelColor];
    cancel.hidden = !showsCancel;
    cancel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = compact ? RCFMFont(UIFontTextStyleHeadline, UIFontWeightSemibold)
                              : RCFMFont(UIFontTextStyleLargeTitle, UIFontWeightBold);
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.numberOfLines = compact ? 1 : 0;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    if (compact) {
        [cancel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    }

    [header addSubview:cancel];
    [header addSubview:titleLabel];

    if (compact) {
        [NSLayoutConstraint activateConstraints:@[
            [cancel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
            [cancel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
            [titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:cancel.trailingAnchor constant:8],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-16],
            [cancel.topAnchor constraintGreaterThanOrEqualToAnchor:header.topAnchor constant:10],
            [header.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [cancel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
            [cancel.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],
            [titleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
            [titleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
            [titleLabel.topAnchor constraintEqualToAnchor:cancel.bottomAnchor constant:4],
            [titleLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-10],
        ]];
    }

    [self.stack addArrangedSubview:header];
}

- (RCFMSearchFieldView *)addSearchFieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text large:(BOOL)large {
    RCFMSearchFieldView *field = [[RCFMSearchFieldView alloc] initWithPlaceholder:placeholder text:text large:large];
    [self.stack addArrangedSubview:RCFMPadded(field, 16, 16, 10, 4)];
    return field;
}

- (void)addChipRow:(NSArray<RCFMChipView *> *)chips {
    if (chips.count == 0) return;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.showsHorizontalScrollIndicator = NO;
    scroll.alwaysBounceHorizontal = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:chips];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    row.layoutMarginsRelativeArrangement = YES;
    row.layoutMargins = UIEdgeInsetsMake(4, 16, 4, 16);
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [row.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
        [scroll.heightAnchor constraintEqualToAnchor:chips.firstObject.heightAnchor constant:8],
    ]];

    [self.stack addArrangedSubview:scroll];
}

- (void)addSectionTitle:(NSString *)title {
    UIView *container = [[UIView alloc] init];
    UILabel *label = [[UILabel alloc] init];
    label.text = title.uppercaseString;
    label.font = RCFMFont(UIFontTextStyleFootnote, UIFontWeightSemibold);
    label.textColor = [UIColor secondaryLabelColor];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-16],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:18],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-6],
    ]];
    label.accessibilityTraits = UIAccessibilityTraitHeader;
    [self.stack addArrangedSubview:container];
}

- (void)addRows:(NSArray<RCFMRowView *> *)rows {
    if (rows.count == 0) return;

    UIView *group = [[UIView alloc] init];
    group.backgroundColor = RCFMBlockColor();
    group.layer.cornerRadius = 12;
    group.layer.cornerCurve = kCACornerCurveContinuous;
    group.clipsToBounds = YES;
    group.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *column = [[UIStackView alloc] init];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 0;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [group addSubview:column];

    for (NSUInteger i = 0; i < rows.count; i++) {
        [column addArrangedSubview:rows[i]];
        if (i < rows.count - 1) [column addArrangedSubview:RCFMSeparator()];
    }

    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:group.leadingAnchor],
        [column.trailingAnchor constraintEqualToAnchor:group.trailingAnchor],
        [column.topAnchor constraintEqualToAnchor:group.topAnchor],
        [column.bottomAnchor constraintEqualToAnchor:group.bottomAnchor],
    ]];

    [self.stack addArrangedSubview:RCFMPadded(group, 16, 16, 0, 0)];
}

static UIView *RCFMSeparator(void) {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = RCFMSeparatorColor();
    line.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *holder = [[UIView alloc] init];
    holder.translatesAutoresizingMaskIntoConstraints = NO;
    [holder addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [holder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [line.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:50],
        [line.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor],
        [line.topAnchor constraintEqualToAnchor:holder.topAnchor],
        [line.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
    ]];
    return holder;
}

- (void)addTileGrid:(NSArray<NSArray<RCFMTileView *> *> *)grid {
    if (grid.count == 0) return;

    // A section with an odd number of tiles keeps the last one half width,
    // rather than letting it stretch across the row.
    NSUInteger columns = 0;
    for (NSArray<RCFMTileView *> *tiles in grid) columns = MAX(columns, tiles.count);

    NSMutableArray *rows = [NSMutableArray array];
    for (NSArray<RCFMTileView *> *tiles in grid) {
        NSMutableArray<UIView *> *arranged = [tiles mutableCopy];
        if (columns > 1 && arranged.count < columns) {
            UIView *spacer = [[UIView alloc] init];
            spacer.backgroundColor = [UIColor clearColor];
            [arranged addObject:spacer];
        }
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:arranged];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentFill;
        row.distribution = UIStackViewDistributionFillEqually;
        row.spacing = 10;
        [rows addObject:row];
    }

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:rows];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 10;
    column.translatesAutoresizingMaskIntoConstraints = NO;

    [self.stack addArrangedSubview:RCFMPadded(column, 16, 16, 0, 0)];
}

- (void)addSpacer:(CGFloat)height {
    UIView *spacer = [[UIView alloc] init];
    [spacer.heightAnchor constraintEqualToConstant:height].active = YES;
    [self.stack addArrangedSubview:spacer];
}

@end
