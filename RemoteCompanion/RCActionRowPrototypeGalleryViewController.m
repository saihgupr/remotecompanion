#import "RCActionRowPrototypeGalleryViewController.h"
#import "RCConfigManager.h"
#import "RCInlineRowChip.h"
#import "RCInlineRowEditor.h"
#import "RCInlineRowItem.h"
#import "RCInlineRowSequenceView.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

// ---------------------------------------------------------------------------
// TEMPORARY DESIGN PROTOTYPE
//
// R1-R5 are five ways to show an action's value on the row itself, instead of
// writing the value nowhere and asking for it in a modal alert. After the five
// cards come the three value panels those rows open: number, choice and text.
//
// The rows, the chip and the editors are the shipping classes
// (RCInlineRow*), so what the cards show is what the action sequence does.
// Each gallery card is a still of the design at close to real width. Tapping a
// card opens the same thing full size and live.
// ---------------------------------------------------------------------------

static const CGFloat RCRowProtoColumnBreak = 620.0;

static NSInteger const RCRowProtoDemoCurrent = 0;
static NSInteger const RCRowProtoDemoChips = 1;
static NSInteger const RCRowProtoDemoInline = 2;
static NSInteger const RCRowProtoDemoSheet = 3;
static NSInteger const RCRowProtoDemoInspector = 4;
static NSInteger const RCRowProtoDemoNumberPanel = 5;
static NSInteger const RCRowProtoDemoChoicePanel = 6;
static NSInteger const RCRowProtoDemoTextPanel = 7;

#pragma mark - Look

static UIColor *RCRowProtoPageColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"mainBackground" defaultVal:0.09];
}

static UIColor *RCRowProtoBlockColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12];
}

static UIColor *RCRowProtoBorderColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"borders" defaultVal:0.14];
}

static UIColor *RCRowProtoSeparatorColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"separators" defaultVal:0.30];
}

static UIColor *RCRowProtoAccent(UIView *view) {
    return view.tintColor ?: [UIColor systemBlueColor];
}

// The default point sizes of the text styles, so a custom weight still starts
// from the right place and scales through UIFontMetrics.
static CGFloat RCRowProtoBaseSize(UIFontTextStyle style) {
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

static UIFont *RCRowProtoFontSized(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

static UIFont *RCRowProtoFont(UIFontTextStyle style, UIFontWeight weight) {
    return RCRowProtoFontSized(RCRowProtoBaseSize(style), style, weight);
}

static UIFont *RCRowProtoDigitFontSized(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

static UIFont *RCRowProtoDigitFont(UIFontTextStyle style, UIFontWeight weight) {
    return RCRowProtoDigitFontSized(RCRowProtoBaseSize(style), style, weight);
}

static UIFont *RCRowProtoMonoFontSized(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont monospacedSystemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

static UIImage *RCRowProtoSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIImageConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    UIImage *image = name.length ? [UIImage systemImageNamed:name withConfiguration:configuration] : nil;
    return image ?: [UIImage systemImageNamed:@"square.dashed" withConfiguration:configuration];
}

static UILabel *RCRowProtoLabel(NSString *text, UIFont *font, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static UILabel *RCRowProtoNote(NSString *text) {
    UILabel *label = RCRowProtoLabel(text, RCRowProtoFont(UIFontTextStyleFootnote, UIFontWeightRegular), [UIColor secondaryLabelColor]);
    label.numberOfLines = 0;
    return label;
}

static UILabel *RCRowProtoEyebrow(NSString *text, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.attributedText = [[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName: RCRowProtoFont(UIFontTextStyleCaption2, UIFontWeightSemibold),
        NSForegroundColorAttributeName: color,
        NSKernAttributeName: @1.2,
    }];
    label.numberOfLines = 1;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static UIView *RCRowProtoHairline(void) {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = RCRowProtoSeparatorColor();
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    return line;
}

// A rounded fill: a card, a stage, a chip's backing
static UIView *RCRowProtoWell(UIColor *fill, CGFloat radius) {
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = fill;
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}

static UIImage *RCRowProtoGrabberImage(void) {
    return [UIImage systemImageNamed:@"line.3.horizontal"] ?: [UIImage systemImageNamed:@"line.horizontal.3"];
}

#pragma mark - The stage builder

@class RCRowProtoStageBuilder;

// The stage host: the live detail screen answers these. A gallery card passes
// no host, which is what makes its stills still.
@protocol RCRowProtoStageHost <NSObject>
- (void)rowProtoStageAskForValue:(RCInlineRowItem *)item;
- (void)rowProtoStageAskForLegacyAlert;
@end

@interface RCRowProtoStageBuilder : NSObject
+ (UIView *)stageForDemo:(NSInteger)demo host:(id<RCRowProtoStageHost>)host showsPaneInCompact:(BOOL)showsPane;
+ (UIView *)panelForItem:(RCInlineRowItem *)item;
+ (RCInlineRowItem *)itemForDemo:(NSInteger)demo;
@end

#pragma mark - R1: the shipping row, and the alert it opens

@interface RCRowProtoLegacyRowView : UIView
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol showsSeparator:(BOOL)showsSeparator;
@end

@implementation RCRowProtoLegacyRowView

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol showsSeparator:(BOOL)showsSeparator {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        UIImageView *icon = [[UIImageView alloc] initWithImage:RCRowProtoSymbol(symbol, 18, UIImageSymbolWeightRegular)];
        icon.tintColor = [UIColor secondaryLabelColor];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *titleLabel = RCRowProtoLabel(title, RCRowProtoFontSized(16, UIFontTextStyleBody, UIFontWeightMedium), [UIColor labelColor]);
        titleLabel.numberOfLines = 0;

        UILabel *subtitleLabel = RCRowProtoLabel(subtitle, RCRowProtoFontSized(15, UIFontTextStyleSubheadline, UIFontWeightRegular), [UIColor secondaryLabelColor]);
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.hidden = subtitle.length == 0;

        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 1;
        textStack.translatesAutoresizingMaskIntoConstraints = NO;

        UIImageView *grabber = [[UIImageView alloc] initWithImage:RCRowProtoGrabberImage()];
        grabber.tintColor = [UIColor tertiaryLabelColor];
        grabber.contentMode = UIViewContentModeScaleAspectFit;
        grabber.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:icon];
        [self addSubview:textStack];
        [self addSubview:grabber];

        NSMutableArray *constraints = [NSMutableArray arrayWithArray:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:70],
            [icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:22],
            [icon.heightAnchor constraintEqualToConstant:22],
            [textStack.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
            [textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [textStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:13],
            [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-13],
            [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:grabber.leadingAnchor constant:-8],
            [grabber.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [grabber.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [grabber.widthAnchor constraintEqualToConstant:18],
            [grabber.heightAnchor constraintEqualToConstant:18],
        ]];
        if (showsSeparator) {
            UIView *line = [[UIView alloc] init];
            line.backgroundColor = RCRowProtoSeparatorColor();
            line.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:line];
            [constraints addObjectsFromArray:@[
                [line.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
                [line.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                [line.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
            ]];
        }
        [NSLayoutConstraint activateConstraints:constraints];
    }
    return self;
}

@end

// What the alert looks like, built from the system material so it reads in
// both themes. A still: the buttons are labels, not controls.
@interface RCRowProtoAlertMock : UIView
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message value:(NSString *)value;
@end

@implementation RCRowProtoAlertMock

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message value:(NSString *)value {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        self.layer.cornerRadius = 14;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;

        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
        blur.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:blur];
        [NSLayoutConstraint activateConstraints:@[
            [blur.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [blur.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [blur.topAnchor constraintEqualToAnchor:self.topAnchor],
            [blur.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        UIView *content = [[UIView alloc] init];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [content.topAnchor constraintEqualToAnchor:self.topAnchor],
            [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        UILabel *titleLabel = RCRowProtoLabel(title, RCRowProtoFont(UIFontTextStyleHeadline, UIFontWeightSemibold), [UIColor labelColor]);
        titleLabel.numberOfLines = 0;
        titleLabel.textAlignment = NSTextAlignmentCenter;

        UILabel *messageLabel = RCRowProtoLabel(message, RCRowProtoFont(UIFontTextStyleFootnote, UIFontWeightRegular), [UIColor labelColor]);
        messageLabel.numberOfLines = 0;
        messageLabel.textAlignment = NSTextAlignmentCenter;

        UIView *fieldWell = RCRowProtoWell([UIColor secondarySystemFillColor], 6);
        UILabel *fieldLabel = RCRowProtoLabel(value, RCRowProtoFont(UIFontTextStyleBody, UIFontWeightRegular), [UIColor labelColor]);
        fieldLabel.textAlignment = NSTextAlignmentCenter;
        [fieldWell addSubview:fieldLabel];

        UIView *topLine = RCRowProtoHairline();
        UIView *buttonRow = [[UIView alloc] init];
        buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *sideLine = [[UIView alloc] init];
        sideLine.backgroundColor = RCRowProtoSeparatorColor();
        sideLine.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *cancel = RCRowProtoLabel(@"Cancel", RCRowProtoFont(UIFontTextStyleBody, UIFontWeightRegular), [UIColor labelColor]);
        cancel.textAlignment = NSTextAlignmentCenter;
        UILabel *set = RCRowProtoLabel(@"Set", RCRowProtoFont(UIFontTextStyleBody, UIFontWeightSemibold), RCRowProtoAccent(self));
        set.textAlignment = NSTextAlignmentCenter;

        [content addSubview:titleLabel];
        [content addSubview:messageLabel];
        [content addSubview:fieldWell];
        [content addSubview:topLine];
        [content addSubview:buttonRow];
        [content addSubview:sideLine];
        [content addSubview:cancel];
        [content addSubview:set];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
            [titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
            [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:19],

            [messageLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
            [messageLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
            [messageLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4],

            [fieldWell.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
            [fieldWell.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
            [fieldWell.topAnchor constraintEqualToAnchor:messageLabel.bottomAnchor constant:12],
            [fieldWell.heightAnchor constraintGreaterThanOrEqualToConstant:30],
            [fieldLabel.leadingAnchor constraintEqualToAnchor:fieldWell.leadingAnchor constant:6],
            [fieldLabel.trailingAnchor constraintEqualToAnchor:fieldWell.trailingAnchor constant:-6],
            [fieldLabel.topAnchor constraintGreaterThanOrEqualToAnchor:fieldWell.topAnchor constant:4],
            [fieldLabel.bottomAnchor constraintLessThanOrEqualToAnchor:fieldWell.bottomAnchor constant:-4],
            [fieldLabel.centerYAnchor constraintEqualToAnchor:fieldWell.centerYAnchor],

            [topLine.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [topLine.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [topLine.topAnchor constraintEqualToAnchor:fieldWell.bottomAnchor constant:16],

            [buttonRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [buttonRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [buttonRow.topAnchor constraintEqualToAnchor:topLine.bottomAnchor],
            [buttonRow.heightAnchor constraintGreaterThanOrEqualToConstant:44],
            [buttonRow.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],

            [cancel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [cancel.widthAnchor constraintEqualToAnchor:content.widthAnchor multiplier:0.5],
            [cancel.centerYAnchor constraintEqualToAnchor:buttonRow.centerYAnchor],
            [cancel.topAnchor constraintGreaterThanOrEqualToAnchor:buttonRow.topAnchor constant:10],
            [cancel.bottomAnchor constraintLessThanOrEqualToAnchor:buttonRow.bottomAnchor constant:-10],
            [set.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [set.widthAnchor constraintEqualToAnchor:content.widthAnchor multiplier:0.5],
            [set.centerYAnchor constraintEqualToAnchor:buttonRow.centerYAnchor],
            [set.topAnchor constraintGreaterThanOrEqualToAnchor:buttonRow.topAnchor constant:10],
            [set.bottomAnchor constraintLessThanOrEqualToAnchor:buttonRow.bottomAnchor constant:-10],

            [sideLine.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
            [sideLine.topAnchor constraintEqualToAnchor:buttonRow.topAnchor],
            [sideLine.bottomAnchor constraintEqualToAnchor:buttonRow.bottomAnchor],
            [sideLine.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        ]];
    }
    return self;
}

@end

// The shipping row, then the alert it opens. Side by side when there is room,
// stacked when there is not.
@interface RCRowProtoCurrentStage : UIView
@property (nonatomic, copy) void (^onShowAlert)(void);
@end

@interface RCRowProtoCurrentStage ()
@property (nonatomic, strong) UIControl *legacyCard;
@property (nonatomic, strong) UIStackView *pairStack;
@property (nonatomic, strong) UIView *rightColumn;
@property (nonatomic, strong) UIImageView *arrowView;
@property (nonatomic, strong) NSLayoutConstraint *rightWidth;
@property (nonatomic, assign) BOOL wide;
@end

@implementation RCRowProtoCurrentStage

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        UIControl *legacyCard = [[UIControl alloc] init];
        self.legacyCard = legacyCard;
        legacyCard.translatesAutoresizingMaskIntoConstraints = NO;
        legacyCard.backgroundColor = RCRowProtoBlockColor();
        legacyCard.layer.cornerRadius = 12;
        legacyCard.layer.cornerCurve = kCACornerCurveContinuous;
        legacyCard.layer.borderWidth = 1;
        legacyCard.layer.borderColor = [RCRowProtoBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        legacyCard.clipsToBounds = YES;
        legacyCard.isAccessibilityElement = YES;
        legacyCard.accessibilityTraits = UIAccessibilityTraitButton;
        legacyCard.accessibilityLabel = @"The current action row";
        legacyCard.accessibilityHint = @"Opens the same modal alert the app uses";
        [legacyCard addTarget:self action:@selector(showAlert) forControlEvents:UIControlEventTouchUpInside];

        UIStackView *rowStack = [[UIStackView alloc] initWithArrangedSubviews:@[
            [[RCRowProtoLegacyRowView alloc] initWithTitle:@"Wait 2 s" subtitle:@"2 seconds" symbol:@"clock" showsSeparator:YES],
            [[RCRowProtoLegacyRowView alloc] initWithTitle:@"Set Volume" subtitle:nil symbol:@"speaker.wave.2.fill" showsSeparator:YES],
            [[RCRowProtoLegacyRowView alloc] initWithTitle:@"Low Power Mode" subtitle:@"On" symbol:@"bolt.slash.fill" showsSeparator:NO],
        ]];
        rowStack.axis = UILayoutConstraintAxisVertical;
        rowStack.spacing = 0;
        rowStack.translatesAutoresizingMaskIntoConstraints = NO;
        [legacyCard addSubview:rowStack];
        [NSLayoutConstraint activateConstraints:@[
            [rowStack.leadingAnchor constraintEqualToAnchor:legacyCard.leadingAnchor],
            [rowStack.trailingAnchor constraintEqualToAnchor:legacyCard.trailingAnchor],
            [rowStack.topAnchor constraintEqualToAnchor:legacyCard.topAnchor],
            [rowStack.bottomAnchor constraintEqualToAnchor:legacyCard.bottomAnchor],
        ]];

        UILabel *leftCaption = RCRowProtoEyebrow(@"IN THE SEQUENCE", [UIColor secondaryLabelColor]);
        UIView *leftColumn = [[UIView alloc] init];
        leftColumn.translatesAutoresizingMaskIntoConstraints = NO;
        [leftColumn addSubview:leftCaption];
        [leftColumn addSubview:legacyCard];
        [NSLayoutConstraint activateConstraints:@[
            [leftCaption.leadingAnchor constraintEqualToAnchor:leftColumn.leadingAnchor],
            [leftCaption.topAnchor constraintEqualToAnchor:leftColumn.topAnchor],
            [leftCaption.trailingAnchor constraintLessThanOrEqualToAnchor:leftColumn.trailingAnchor],
            [legacyCard.leadingAnchor constraintEqualToAnchor:leftColumn.leadingAnchor],
            [legacyCard.trailingAnchor constraintEqualToAnchor:leftColumn.trailingAnchor],
            [legacyCard.topAnchor constraintEqualToAnchor:leftCaption.bottomAnchor constant:8],
            [legacyCard.bottomAnchor constraintEqualToAnchor:leftColumn.bottomAnchor],
        ]];

        UILabel *rightCaption = RCRowProtoEyebrow(@"WHAT YOU GET", [UIColor secondaryLabelColor]);
        RCRowProtoAlertMock *alert = [[RCRowProtoAlertMock alloc] initWithTitle:@"Set Volume" message:@"Enter a value (0-100)" value:@"40"];
        self.rightColumn = [[UIView alloc] init];
        self.rightColumn.translatesAutoresizingMaskIntoConstraints = NO;
        [self.rightColumn addSubview:rightCaption];
        [self.rightColumn addSubview:alert];
        [NSLayoutConstraint activateConstraints:@[
            [rightCaption.leadingAnchor constraintEqualToAnchor:self.rightColumn.leadingAnchor],
            [rightCaption.topAnchor constraintEqualToAnchor:self.rightColumn.topAnchor],
            [rightCaption.trailingAnchor constraintLessThanOrEqualToAnchor:self.rightColumn.trailingAnchor],
            [alert.centerXAnchor constraintEqualToAnchor:self.rightColumn.centerXAnchor],
            [alert.topAnchor constraintEqualToAnchor:rightCaption.bottomAnchor constant:8],
            [alert.widthAnchor constraintEqualToConstant:270],
            [alert.widthAnchor constraintLessThanOrEqualToAnchor:self.rightColumn.widthAnchor],
            [alert.bottomAnchor constraintEqualToAnchor:self.rightColumn.bottomAnchor],
        ]];

        UIView *arrowBox = [[UIView alloc] init];
        arrowBox.translatesAutoresizingMaskIntoConstraints = NO;
        self.arrowView = [[UIImageView alloc] initWithImage:RCRowProtoSymbol(@"arrow.down", 14, UIImageSymbolWeightSemibold)];
        self.arrowView.tintColor = [UIColor tertiaryLabelColor];
        self.arrowView.contentMode = UIViewContentModeScaleAspectFit;
        self.arrowView.translatesAutoresizingMaskIntoConstraints = NO;
        [arrowBox addSubview:self.arrowView];
        [NSLayoutConstraint activateConstraints:@[
            [arrowBox.widthAnchor constraintEqualToConstant:24],
            [arrowBox.heightAnchor constraintEqualToConstant:24],
            [self.arrowView.centerXAnchor constraintEqualToAnchor:arrowBox.centerXAnchor],
            [self.arrowView.centerYAnchor constraintEqualToAnchor:arrowBox.centerYAnchor],
            [self.arrowView.widthAnchor constraintEqualToConstant:16],
            [self.arrowView.heightAnchor constraintEqualToConstant:16],
        ]];

        self.pairStack = [[UIStackView alloc] initWithArrangedSubviews:@[leftColumn, arrowBox, self.rightColumn]];
        self.pairStack.axis = UILayoutConstraintAxisVertical;
        self.pairStack.alignment = UIStackViewAlignmentFill;
        self.pairStack.spacing = 14;
        self.pairStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.pairStack];
        [NSLayoutConstraint activateConstraints:@[
            [self.pairStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.pairStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.pairStack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.pairStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        // Always stacked: the card is never wide enough for the pair to sit side by side.
        self.rightWidth = [self.rightColumn.widthAnchor constraintEqualToConstant:270];
        self.rightWidth.active = NO;
        self.wide = NO;
    }
    return self;
}

- (void)showAlert {
    if (self.onShowAlert) self.onShowAlert();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.legacyCard.layer.borderColor = [RCRowProtoBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

@end

#pragma mark - R4: the sheet, as a still

@interface RCRowProtoSheetMockView : UIView
- (instancetype)initWithItem:(RCInlineRowItem *)item;
@end

@implementation RCRowProtoSheetMockView

- (instancetype)initWithItem:(RCInlineRowItem *)item {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = RCRowProtoBlockColor();
        self.layer.cornerRadius = 18;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [RCRowProtoBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        self.clipsToBounds = YES;

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 12;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
        ]];

        UIView *grabberBox = [[UIView alloc] init];
        grabberBox.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *grabber = [[UIView alloc] init];
        grabber.backgroundColor = [UIColor tertiaryLabelColor];
        grabber.layer.cornerRadius = 2.5;
        grabber.translatesAutoresizingMaskIntoConstraints = NO;
        [grabberBox addSubview:grabber];
        [NSLayoutConstraint activateConstraints:@[
            [grabberBox.heightAnchor constraintEqualToConstant:5],
            [grabber.centerXAnchor constraintEqualToAnchor:grabberBox.centerXAnchor],
            [grabber.widthAnchor constraintEqualToConstant:36],
            [grabber.heightAnchor constraintEqualToConstant:5],
        ]];
        [stack addArrangedSubview:grabberBox];

        UILabel *name = RCRowProtoLabel(item.name, RCRowProtoFont(UIFontTextStyleHeadline, UIFontWeightSemibold), [UIColor labelColor]);
        name.numberOfLines = 0;
        RCInlineRowChip *chip = [[RCInlineRowChip alloc] initWithFrame:CGRectZero];
        [chip setValueText:item.displayValue];
        chip.userInteractionEnabled = NO;
        UIView *spacer = [[UIView alloc] init];
        [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[name, spacer, chip]];
        header.axis = UILayoutConstraintAxisHorizontal;
        header.alignment = UIStackViewAlignmentCenter;
        header.spacing = 8;
        [stack addArrangedSubview:header];

        RCInlineRowEditor *editor = [[RCInlineRowEditor alloc] initWithItem:item style:RCInlineRowEditorStyleRegular otherActions:nil];
        editor.userInteractionEnabled = NO;
        [stack addArrangedSubview:editor];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.borderColor = [RCRowProtoBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

@end

#pragma mark - R5: sequence and inspector

@interface RCRowProtoInspectorView : UIView
@property (nonatomic, copy) void (^onActivate)(NSInteger index, RCInlineRowItem *item);
- (instancetype)initWithItems:(NSArray<RCInlineRowItem *> *)items showsPaneWhenCompact:(BOOL)showsPane;
@end

@interface RCRowProtoInspectorView ()
@property (nonatomic, strong) NSArray<RCInlineRowItem *> *items;
@property (nonatomic, assign) BOOL showsPaneWhenCompact;
@property (nonatomic, assign) BOOL wide;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, strong) UIStackView *columns;
@property (nonatomic, strong) RCInlineRowSequenceView *sequence;
@property (nonatomic, strong) UIView *paneColumn;
@property (nonatomic, strong) UIView *paneHost;
@property (nonatomic, strong) UILabel *paneEyebrow;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) NSLayoutConstraint *paneWidth;
- (void)selectIndex:(NSInteger)index;
- (void)rebuildPane;
@end

@implementation RCRowProtoInspectorView

- (instancetype)initWithItems:(NSArray<RCInlineRowItem *> *)items showsPaneWhenCompact:(BOOL)showsPane {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _items = items ?: @[];
        _showsPaneWhenCompact = showsPane;
        _selectedIndex = 0;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _sequence = [[RCInlineRowSequenceView alloc] initWithItems:items style:RCInlineRowSequenceStyleInspector];
        __weak typeof(self) weakSelf = self;
        _sequence.onActivate = ^(NSInteger index, RCInlineRowItem *item) {
            [weakSelf selectIndex:index];
            if (!weakSelf.wide && !weakSelf.showsPaneWhenCompact && weakSelf.onActivate) weakSelf.onActivate(index, item);
        };

        _hint = RCRowProtoNote(@"Tap a row. On a phone the editor slides up as a sheet.");
        _hint.hidden = showsPane;

        UIStackView *leftStack = [[UIStackView alloc] initWithArrangedSubviews:@[_sequence, _hint]];
        leftStack.axis = UILayoutConstraintAxisVertical;
        leftStack.spacing = 12;
        leftStack.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *leftColumn = [[UIView alloc] init];
        leftColumn.translatesAutoresizingMaskIntoConstraints = NO;
        [leftColumn addSubview:leftStack];
        [NSLayoutConstraint activateConstraints:@[
            [leftStack.leadingAnchor constraintEqualToAnchor:leftColumn.leadingAnchor],
            [leftStack.trailingAnchor constraintEqualToAnchor:leftColumn.trailingAnchor],
            [leftStack.topAnchor constraintEqualToAnchor:leftColumn.topAnchor],
            [leftStack.bottomAnchor constraintEqualToAnchor:leftColumn.bottomAnchor],
        ]];

        _paneEyebrow = RCRowProtoEyebrow(@"EDITING", [UIColor secondaryLabelColor]);
        _paneHost = [[UIView alloc] init];
        _paneHost.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *paneStack = [[UIStackView alloc] initWithArrangedSubviews:@[_paneEyebrow, _paneHost]];
        paneStack.axis = UILayoutConstraintAxisVertical;
        paneStack.spacing = 8;
        paneStack.translatesAutoresizingMaskIntoConstraints = NO;

        _paneColumn = [[UIView alloc] init];
        _paneColumn.translatesAutoresizingMaskIntoConstraints = NO;
        [_paneColumn addSubview:paneStack];
        [NSLayoutConstraint activateConstraints:@[
            [paneStack.leadingAnchor constraintEqualToAnchor:_paneColumn.leadingAnchor],
            [paneStack.trailingAnchor constraintEqualToAnchor:_paneColumn.trailingAnchor],
            [paneStack.topAnchor constraintEqualToAnchor:_paneColumn.topAnchor],
            [paneStack.bottomAnchor constraintEqualToAnchor:_paneColumn.bottomAnchor],
        ]];

        _columns = [[UIStackView alloc] initWithArrangedSubviews:@[leftColumn, _paneColumn]];
        _columns.axis = UILayoutConstraintAxisVertical;
        _columns.alignment = UIStackViewAlignmentFill;
        _columns.spacing = 14;
        _columns.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_columns];
        [NSLayoutConstraint activateConstraints:@[
            [_columns.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_columns.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_columns.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_columns.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        _paneWidth = [_paneColumn.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.46];
        _paneColumn.hidden = !showsPane;
        [self rebuildPane];
    }
    return self;
}

- (void)selectIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.items.count) return;
    self.selectedIndex = index;
    [self rebuildPane];
}

- (void)rebuildPane {
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.items.count) return;
    RCInlineRowItem *item = self.items[self.selectedIndex];
    for (UIView *view in self.paneHost.subviews) [view removeFromSuperview];

    UIView *card = RCRowProtoWell(RCRowProtoBlockColor(), 16);
    UIView *panel = [RCRowProtoStageBuilder panelForItem:item];
    [card addSubview:panel];
    [self.paneHost addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.paneHost.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:self.paneHost.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:self.paneHost.topAnchor],
        [card.bottomAnchor constraintEqualToAnchor:self.paneHost.bottomAnchor],
        [panel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [panel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [panel.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [panel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
    ]];
    self.paneEyebrow.attributedText = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"EDITING · %@", item.name.uppercaseString]
                                                                      attributes:@{
        NSFontAttributeName: RCRowProtoFont(UIFontTextStyleCaption2, UIFontWeightSemibold),
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
        NSKernAttributeName: @1.2,
    }];
    self.paneEyebrow.accessibilityLabel = [NSString stringWithFormat:@"Editing %@", item.name];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL wide = CGRectGetWidth(self.bounds) >= RCRowProtoColumnBreak;
    if (wide == self.wide) return;
    self.wide = wide;
    self.columns.axis = wide ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    self.columns.alignment = wide ? UIStackViewAlignmentTop : UIStackViewAlignmentFill;
    self.columns.spacing = wide ? 16 : 14;
    self.paneWidth.active = wide;
    self.paneColumn.hidden = (!wide && !self.showsPaneWhenCompact);
    self.hint.hidden = (wide || self.showsPaneWhenCompact);
    [self layoutIfNeeded];
}

@end

#pragma mark - Sample values

static RCInlineRowItem *RCRowProtoVolumeItem(void) {
    RCInlineRowItem *item = [[RCInlineRowItem alloc] init];
    item.name = @"Set Volume";
    item.detail = @"This iPhone";
    item.symbolName = @"speaker.wave.2.fill";
    item.kind = RCInlineRowKindNumber;
    item.caption = @"Volume";
    item.unit = @"%";
    item.minimumValue = 0;
    item.maximumValue = 100;
    item.step = 5;
    item.decimals = 0;
    item.numberValue = 40;
    return item;
}

static RCInlineRowItem *RCRowProtoDelayItem(void) {
    RCInlineRowItem *item = [[RCInlineRowItem alloc] init];
    item.name = @"Wait";
    item.detail = @"Before the next action";
    item.symbolName = @"clock";
    item.kind = RCInlineRowKindNumber;
    item.caption = @"Seconds";
    item.unit = @"s";
    item.unitNeedsSpace = YES;
    item.minimumValue = 0;
    item.maximumValue = 86400;
    item.step = 0.5;
    item.decimals = 2;
    item.allowsDecimals = YES;
    item.numberValue = 2;
    return item;
}

static RCInlineRowItem *RCRowProtoLowPowerItem(void) {
    RCInlineRowItem *item = [[RCInlineRowItem alloc] init];
    item.name = @"Low Power Mode";
    item.detail = @"This iPhone";
    item.symbolName = @"bolt.slash.fill";
    item.kind = RCInlineRowKindChoice;
    item.caption = @"Low Power Mode";
    item.options = @[@"On", @"Off"];
    item.choiceIndex = 0;
    return item;
}

static RCInlineRowItem *RCRowProtoToastItem(void) {
    RCInlineRowItem *item = [[RCInlineRowItem alloc] init];
    item.name = @"Show Toast";
    item.detail = @"This iPhone";
    item.symbolName = @"text.bubble.fill";
    item.kind = RCInlineRowKindText;
    item.caption = @"Message";
    item.textValue = @"Backup finished";
    item.placeholder = @"Type a message";
    return item;
}

@implementation RCRowProtoStageBuilder

+ (RCInlineRowItem *)itemForDemo:(NSInteger)demo {
    if (demo == RCRowProtoDemoNumberPanel) return RCRowProtoVolumeItem();
    if (demo == RCRowProtoDemoChoicePanel) return RCRowProtoLowPowerItem();
    if (demo == RCRowProtoDemoTextPanel) return RCRowProtoToastItem();
    return nil;
}

+ (UIView *)panelForItem:(RCInlineRowItem *)item {
    return [[RCInlineRowEditor alloc] initWithItem:item style:RCInlineRowEditorStyleRegular otherActions:nil];
}

+ (UIView *)stageForDemo:(NSInteger)demo host:(id<RCRowProtoStageHost>)host showsPaneInCompact:(BOOL)showsPane {
    __weak id<RCRowProtoStageHost> weakHost = host;

    if (demo == RCRowProtoDemoCurrent) {
        RCRowProtoCurrentStage *stage = [[RCRowProtoCurrentStage alloc] init];
        stage.onShowAlert = ^{ [weakHost rowProtoStageAskForLegacyAlert]; };
        return stage;
    }

    if (demo >= RCRowProtoDemoNumberPanel) {
        RCInlineRowItem *item = [self itemForDemo:demo];
        return item ? [self panelForItem:item] : [[UIView alloc] init];
    }

    NSArray<RCInlineRowItem *> *items = @[RCRowProtoVolumeItem(), RCRowProtoDelayItem(), RCRowProtoLowPowerItem()];
    if (demo == RCRowProtoDemoInline) {
        items = @[RCRowProtoVolumeItem(), RCRowProtoToastItem(), RCRowProtoLowPowerItem()];
    }

    if (demo == RCRowProtoDemoInspector) {
        RCRowProtoInspectorView *inspector = [[RCRowProtoInspectorView alloc] initWithItems:items showsPaneWhenCompact:showsPane];
        inspector.onActivate = ^(NSInteger index, RCInlineRowItem *item) {
            [weakHost rowProtoStageAskForValue:item];
        };
        return inspector;
    }

    RCInlineRowSequenceStyle style = RCInlineRowSequenceStyleChips;
    if (demo == RCRowProtoDemoInline) style = RCInlineRowSequenceStyleInline;
    else if (demo == RCRowProtoDemoSheet) style = RCInlineRowSequenceStyleSheet;

    RCInlineRowSequenceView *sequence = [[RCInlineRowSequenceView alloc] initWithItems:items style:style];
    if (demo != RCRowProtoDemoInline) {
        sequence.onActivate = ^(NSInteger index, RCInlineRowItem *item) {
            [weakHost rowProtoStageAskForValue:item];
        };
    }
    if (demo == RCRowProtoDemoInline) [sequence setExpandedIndex:0 animated:NO];

    // On a card, R4 also shows the sheet it opens. The live screen shows the real one.
    if (demo == RCRowProtoDemoSheet && host == nil) {
        UIStackView *stage = [[UIStackView alloc] initWithArrangedSubviews:@[
            sequence,
            RCRowProtoEyebrow(@"THE SHEET, OVER THE BOTTOM HALF", [UIColor secondaryLabelColor]),
            [[RCRowProtoSheetMockView alloc] initWithItem:items[1]],
        ]];
        stage.axis = UILayoutConstraintAxisVertical;
        stage.spacing = 10;
        stage.translatesAutoresizingMaskIntoConstraints = NO;
        return stage;
    }
    return sequence;
}

@end

#pragma mark - The demos

static NSArray<NSDictionary *> *RCRowProtoDescriptors(void) {
    return @[
        @{ @"badge": @"R1", @"name": @"Current", @"summary": @"A subtitle row, then a modal alert for the value.",
           @"demo": @(RCRowProtoDemoCurrent) },
        @{ @"badge": @"R2", @"name": @"Value chips", @"summary": @"The value sits on the row, in a chip that opens the editor.",
           @"demo": @(RCRowProtoDemoChips) },
        @{ @"badge": @"R3", @"name": @"Inline expand", @"summary": @"The row opens in place, and the rest of the sequence dims.",
           @"demo": @(RCRowProtoDemoInline) },
        @{ @"badge": @"R4", @"name": @"Bottom sheet", @"summary": @"A compact row. The editor slides up over the bottom half.",
           @"demo": @(RCRowProtoDemoSheet) },
        @{ @"badge": @"R5", @"name": @"Inspector", @"summary": @"The sequence on the left, the selected value on the right.",
           @"demo": @(RCRowProtoDemoInspector) },
        @{ @"badge": @"P1", @"name": @"Number", @"summary": @"Half steps, a big readout, and an exact field.",
           @"demo": @(RCRowProtoDemoNumberPanel) },
        @{ @"badge": @"P2", @"name": @"Choice", @"summary": @"The options as a list, the chosen one marked.",
           @"demo": @(RCRowProtoDemoChoicePanel) },
        @{ @"badge": @"P3", @"name": @"Text", @"summary": @"One line, with the + menu for a variable.",
           @"demo": @(RCRowProtoDemoTextPanel) },
    ];
}

#pragma mark - Full size

@interface RCRowProtoDetailViewController : UIViewController <RCRowProtoStageHost>
- (instancetype)initWithDescriptor:(NSDictionary *)descriptor;
@end

@interface RCRowProtoDetailViewController ()
@property (nonatomic, copy) NSDictionary *descriptor;
@property (nonatomic, assign) NSInteger demo;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) RCInlineRowItem *panelItem;
@property (nonatomic, strong) UILabel *liveNote;
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) UIScrollView *sheetScroll;
@property (nonatomic, strong) UILabel *sheetValueLabel;
@property (nonatomic, strong) NSLayoutConstraint *sheetBottom;
@property (nonatomic, strong) RCInlineRowItem *sheetItem;
- (void)installStage;
- (NSString *)noteForDemo;
- (void)presentValueSheetForItem:(RCInlineRowItem *)item;
- (void)dimTapped;
- (void)doneTapped;
- (void)dismissSheetAnimated:(BOOL)animated completion:(void (^)(void))completion;
@end

@implementation RCRowProtoDetailViewController

- (instancetype)initWithDescriptor:(NSDictionary *)descriptor {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _descriptor = [descriptor copy];
        _demo = [descriptor[@"demo"] integerValue];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.descriptor[@"name"];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.prompt = [NSString stringWithFormat:@"Prototype %@ · Nothing is saved", self.descriptor[@"badge"]];
    self.view.backgroundColor = RCRowProtoPageColor();

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
    ]];

    [self installStage];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(valueChanged:)
                                                 name:RCInlineRowValueChangedNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)installStage {
    UIView *stage = nil;
    if (self.demo >= RCRowProtoDemoNumberPanel) {
        self.panelItem = [RCRowProtoStageBuilder itemForDemo:self.demo];
        stage = [RCRowProtoStageBuilder panelForItem:self.panelItem];
    } else {
        stage = [RCRowProtoStageBuilder stageForDemo:self.demo host:self showsPaneInCompact:NO];
    }
    if (!stage) return;
    stage.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:stage];

    CGFloat maxWidth = 520.0;
    if (self.demo == RCRowProtoDemoInspector) maxWidth = 980.0;
    else if (self.demo == RCRowProtoDemoCurrent) maxWidth = 760.0;
    else if (self.demo >= RCRowProtoDemoNumberPanel) maxWidth = 440.0;
    NSLayoutConstraint *preferredWidth = [stage.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor constant:-40];
    preferredWidth.priority = 999;
    [NSLayoutConstraint activateConstraints:@[
        [stage.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:20],
        [stage.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [stage.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [stage.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [stage.widthAnchor constraintLessThanOrEqualToConstant:maxWidth],
        preferredWidth,
    ]];

    UILabel *note = RCRowProtoNote([self noteForDemo]);
    [self.contentView addSubview:note];
    [NSLayoutConstraint activateConstraints:@[
        [note.leadingAnchor constraintEqualToAnchor:stage.leadingAnchor],
        [note.trailingAnchor constraintEqualToAnchor:stage.trailingAnchor],
        [note.topAnchor constraintEqualToAnchor:stage.bottomAnchor constant:16],
    ]];

    UIView *last = note;
    if (self.demo >= RCRowProtoDemoNumberPanel) {
        self.liveNote = RCRowProtoLabel(nil, RCRowProtoFont(UIFontTextStyleSubheadline, UIFontWeightSemibold), RCRowProtoAccent(self.view));
        self.liveNote.numberOfLines = 0;
        self.liveNote.text = [NSString stringWithFormat:@"The row would read %@.", self.panelItem.displayValue];
        [self.contentView addSubview:self.liveNote];
        [NSLayoutConstraint activateConstraints:@[
            [self.liveNote.leadingAnchor constraintEqualToAnchor:stage.leadingAnchor],
            [self.liveNote.trailingAnchor constraintEqualToAnchor:stage.trailingAnchor],
            [self.liveNote.topAnchor constraintEqualToAnchor:note.bottomAnchor constant:8],
        ]];
        last = self.liveNote;
    }

    [NSLayoutConstraint activateConstraints:@[
        [last.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-32],
    ]];
}

- (NSString *)noteForDemo {
    switch (self.demo) {
        case RCRowProtoDemoCurrent:
            return @"Tap the sequence row. That is the real alert the app shows now: the value is not on the row at all.";
        case RCRowProtoDemoChips:
            return @"Tap a value chip. The same panel opens for a number, a choice or a line of text.";
        case RCRowProtoDemoInline:
            return @"Tap a row to fold its editor open. The other rows step back rather than disappear.";
        case RCRowProtoDemoSheet:
            return @"Tap a row. The sheet covers the bottom half, and the row it belongs to stays in view.";
        case RCRowProtoDemoInspector:
            return @"On a tablet the editor sits to the right of the sequence. On a phone the same editor slides up as a sheet.";
        case RCRowProtoDemoNumberPanel:
            return @"The number panel. Half steps for time, or whole steps for a percentage, with an exact field for anything else.";
        case RCRowProtoDemoChoicePanel:
            return @"The choice panel. The chosen option is marked, and the row above shows the same word.";
        default:
            return @"The text panel. One line, a keyboard, and the + menu when the value should come from a variable.";
    }
}

- (void)valueChanged:(NSNotification *)note {
    RCInlineRowItem *item = note.object;
    if (self.panelItem && item == self.panelItem) {
        self.liveNote.text = [NSString stringWithFormat:@"The row would read %@.", self.panelItem.displayValue];
    }
    if (self.sheetItem && item == self.sheetItem) {
        self.sheetValueLabel.text = item.displayValue;
    }
}

#pragma mark Stage host

- (void)rowProtoStageAskForValue:(RCInlineRowItem *)item {
    [self presentValueSheetForItem:item];
}

- (void)rowProtoStageAskForLegacyAlert {
    [self.view endEditing:YES];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Set Volume"
                                                                   message:@"Enter a value (0-100)"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.textAlignment = NSTextAlignmentCenter;
        field.text = @"40";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark Sheet

- (void)presentValueSheetForItem:(RCInlineRowItem *)item {
    if (!item) return;
    [self dismissSheetAnimated:NO completion:nil];
    [self.view endEditing:YES];

    UIView *dim = [[UIView alloc] init];
    dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    dim.alpha = 0;
    dim.translatesAutoresizingMaskIntoConstraints = NO;
    dim.accessibilityElementsHidden = YES;
    [dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dimTapped)]];
    [self.view addSubview:dim];

    UIView *sheet = [[UIView alloc] init];
    sheet.backgroundColor = RCRowProtoPageColor();
    sheet.layer.cornerRadius = 22;
    sheet.layer.cornerCurve = kCACornerCurveContinuous;
    sheet.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    sheet.layer.shadowColor = [UIColor blackColor].CGColor;
    sheet.layer.shadowOpacity = 0.22;
    sheet.layer.shadowRadius = 24;
    sheet.layer.shadowOffset = CGSizeMake(0, -8);
    sheet.translatesAutoresizingMaskIntoConstraints = NO;
    sheet.accessibilityViewIsModal = YES;
    [self.view addSubview:sheet];

    UIView *grabber = [[UIView alloc] init];
    grabber.backgroundColor = [UIColor tertiaryLabelColor];
    grabber.layer.cornerRadius = 2.5;
    grabber.translatesAutoresizingMaskIntoConstraints = NO;
    [sheet addSubview:grabber];

    UILabel *title = RCRowProtoLabel(item.name, RCRowProtoFont(UIFontTextStyleHeadline, UIFontWeightSemibold), [UIColor labelColor]);
    title.numberOfLines = 0;
    self.sheetValueLabel = RCRowProtoLabel(item.displayValue, RCRowProtoDigitFont(UIFontTextStyleSubheadline, UIFontWeightSemibold), RCRowProtoAccent(self.view));
    self.sheetValueLabel.numberOfLines = 0;

    UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.sheetValueLabel]];
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.spacing = 2;
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    [sheet addSubview:titleStack];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.titleLabel.font = RCRowProtoFont(UIFontTextStyleBody, UIFontWeightSemibold);
    done.accessibilityLabel = @"Done editing";
    [done addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [sheet addSubview:done];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    scroll.showsVerticalScrollIndicator = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [sheet addSubview:scroll];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];

    UIView *panel = [RCRowProtoStageBuilder panelForItem:item];
    [content addSubview:panel];

    UILabel *footnote = RCRowProtoNote(@"The row behind the sheet updates as you type.");
    [content addSubview:footnote];

    [NSLayoutConstraint activateConstraints:@[
        [dim.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [dim.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [dim.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [dim.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [sheet.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [sheet.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor],
        [sheet.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor],
        [sheet.heightAnchor constraintGreaterThanOrEqualToConstant:280],
        [sheet.widthAnchor constraintLessThanOrEqualToConstant:620],

        [grabber.centerXAnchor constraintEqualToAnchor:sheet.centerXAnchor],
        [grabber.topAnchor constraintEqualToAnchor:sheet.topAnchor constant:8],
        [grabber.widthAnchor constraintEqualToConstant:36],
        [grabber.heightAnchor constraintEqualToConstant:5],

        [titleStack.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor constant:20],
        [titleStack.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:10],
        [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:done.leadingAnchor constant:-12],
        [done.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor constant:-16],
        [done.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],

        [scroll.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:titleStack.bottomAnchor constant:12],
        [scroll.bottomAnchor constraintEqualToAnchor:sheet.safeAreaLayoutGuide.bottomAnchor],

        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],

        [panel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [panel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [panel.topAnchor constraintEqualToAnchor:content.topAnchor],
        [footnote.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [footnote.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [footnote.topAnchor constraintEqualToAnchor:panel.bottomAnchor constant:12],
        [footnote.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
    ]];

    NSLayoutConstraint *width = [sheet.widthAnchor constraintEqualToAnchor:self.view.widthAnchor];
    width.priority = 999;
    width.active = YES;
    NSLayoutConstraint *sheetHeight = [sheet.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.62];
    sheetHeight.priority = 999;
    sheetHeight.active = YES;
    self.sheetBottom = [sheet.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.sheetBottom.active = YES;

    self.dimView = dim;
    self.sheetView = sheet;
    self.sheetScroll = scroll;
    self.sheetItem = item;

    sheet.transform = CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.view.bounds));
    if (UIAccessibilityIsReduceMotionEnabled()) {
        dim.alpha = 1;
        sheet.transform = CGAffineTransformIdentity;
        return;
    }
    [UIView animateWithDuration:0.36
                          delay:0
         usingSpringWithDamping:0.9
          initialSpringVelocity:0.2
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        dim.alpha = 1;
        sheet.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dimTapped {
    [self dismissSheetAnimated:YES completion:nil];
}

- (void)doneTapped {
    [self dismissSheetAnimated:YES completion:nil];
}

- (void)dismissSheetAnimated:(BOOL)animated completion:(void (^)(void))completion {
    UIView *sheet = self.sheetView;
    UIView *dim = self.dimView;
    self.sheetView = nil;
    self.dimView = nil;
    self.sheetScroll = nil;
    self.sheetValueLabel = nil;
    self.sheetItem = nil;

    void (^cleanup)(void) = ^{
        [sheet removeFromSuperview];
        [dim removeFromSuperview];
        if (completion) completion();
    };
    if (!sheet) {
        if (completion) completion();
        return;
    }
    [self.view endEditing:YES];
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.26 animations:^{
            dim.alpha = 0;
            sheet.transform = CGAffineTransformMakeTranslation(0, CGRectGetHeight(sheet.bounds));
        } completion:^(__unused BOOL finished) {
            cleanup();
        }];
    } else {
        cleanup();
    }
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect keyboard = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:keyboard fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(local));

    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.scrollView.contentInset = insets;
    self.scrollView.verticalScrollIndicatorInsets = insets;
    if (self.sheetView) {
        self.sheetBottom.constant = -overlap;
        [self.view layoutIfNeeded];
    }
}

@end

#pragma mark - Gallery card

@interface RCRowProtoGalleryCardView : UIControl
@property (nonatomic, copy) void (^onOpen)(void);
- (instancetype)initWithDescriptor:(NSDictionary *)descriptor;
@end

@interface RCRowProtoGalleryCardView ()
@property (nonatomic, strong) UIView *stageView;
@end

@implementation RCRowProtoGalleryCardView

- (instancetype)initWithDescriptor:(NSDictionary *)descriptor {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = RCRowProtoBlockColor();
        self.layer.cornerRadius = 18;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [RCRowProtoBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        self.clipsToBounds = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityLabel = [NSString stringWithFormat:@"Prototype %@, %@. %@",
                                   descriptor[@"badge"], descriptor[@"name"], descriptor[@"summary"]];
        self.accessibilityHint = @"Opens this design full size";

        UIView *badge = RCRowProtoWell([[UIColor systemBlueColor] colorWithAlphaComponent:0.16], 8);
        UILabel *badgeLabel = RCRowProtoLabel(descriptor[@"badge"], RCRowProtoMonoFontSized(12, UIFontTextStyleCaption1, UIFontWeightSemibold), [UIColor systemBlueColor]);
        badgeLabel.textAlignment = NSTextAlignmentCenter;
        badgeLabel.adjustsFontSizeToFitWidth = YES;
        badgeLabel.minimumScaleFactor = 0.7;
        [badge addSubview:badgeLabel];
        [NSLayoutConstraint activateConstraints:@[
            [badgeLabel.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:7],
            [badgeLabel.trailingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:-7],
            [badgeLabel.topAnchor constraintEqualToAnchor:badge.topAnchor constant:5],
            [badgeLabel.bottomAnchor constraintEqualToAnchor:badge.bottomAnchor constant:-5],
            [badge.widthAnchor constraintGreaterThanOrEqualToConstant:30],
            [badge.heightAnchor constraintGreaterThanOrEqualToConstant:30],
        ]];

        UILabel *name = RCRowProtoLabel(descriptor[@"name"], RCRowProtoFont(UIFontTextStyleHeadline, UIFontWeightSemibold), [UIColor labelColor]);
        name.numberOfLines = 0;

        UIImageView *chevron = [[UIImageView alloc] initWithImage:RCRowProtoSymbol(@"chevron.right", 11, UIImageSymbolWeightSemibold)];
        chevron.tintColor = [UIColor tertiaryLabelColor];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *summary = RCRowProtoLabel(descriptor[@"summary"], RCRowProtoFont(UIFontTextStyleFootnote, UIFontWeightRegular), [UIColor secondaryLabelColor]);
        summary.numberOfLines = 0;

        NSInteger demo = [descriptor[@"demo"] integerValue];
        UIView *stage = RCRowProtoWell(RCRowProtoPageColor(), 14);
        self.stageView = stage;
        stage.layer.borderWidth = 1;
        stage.layer.borderColor = [RCRowProtoBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;

        UIView *mock = [RCRowProtoStageBuilder stageForDemo:demo host:nil showsPaneInCompact:YES];
        mock.userInteractionEnabled = NO;
        mock.accessibilityElementsHidden = YES;
        [stage addSubview:mock];

        [self addSubview:badge];
        [self addSubview:name];
        [self addSubview:summary];
        [self addSubview:chevron];
        [self addSubview:stage];

        [NSLayoutConstraint activateConstraints:@[
            [badge.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [badge.centerYAnchor constraintEqualToAnchor:name.centerYAnchor],

            [name.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:10],
            [name.topAnchor constraintEqualToAnchor:self.topAnchor constant:11],
            [name.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],

            [chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [chevron.centerYAnchor constraintEqualToAnchor:name.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:12],
            [chevron.heightAnchor constraintEqualToConstant:16],

            [summary.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
            [summary.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [summary.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:3],

            [stage.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [stage.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [stage.topAnchor constraintEqualToAnchor:summary.bottomAnchor constant:10],
            [stage.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],

            [mock.leadingAnchor constraintEqualToAnchor:stage.leadingAnchor constant:8],
            [mock.trailingAnchor constraintEqualToAnchor:stage.trailingAnchor constant:-8],
            [mock.topAnchor constraintEqualToAnchor:stage.topAnchor constant:8],
            [mock.bottomAnchor constraintEqualToAnchor:stage.bottomAnchor constant:-8],
        ]];

        [self addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIColor *border = [RCRowProtoBorderColor() resolvedColorWithTraitCollection:self.traitCollection];
    self.layer.borderColor = border.CGColor;
    self.stageView.layer.borderColor = border.CGColor;
}

- (void)openTapped {
    if (self.onOpen) self.onOpen();
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.16
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
        self.alpha = highlighted ? 0.94 : 1.0;
    } completion:nil];
}

@end

@interface RCRowProtoGalleryCell : UITableViewCell
@property (nonatomic, copy) void (^onOpenDescriptor)(NSDictionary *descriptor);
- (void)configureWithDescriptor:(NSDictionary *)descriptor;
@end

@implementation RCRowProtoGalleryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    for (UIView *view in self.contentView.subviews) [view removeFromSuperview];
}

- (void)configureWithDescriptor:(NSDictionary *)descriptor {
    for (UIView *view in self.contentView.subviews) [view removeFromSuperview];

    RCRowProtoGalleryCardView *card = [[RCRowProtoGalleryCardView alloc] initWithDescriptor:descriptor];
    __weak typeof(self) weakSelf = self;
    card.onOpen = ^{
        if (weakSelf.onOpenDescriptor) weakSelf.onOpenDescriptor(descriptor);
    };
    [self.contentView addSubview:card];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        [card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
        [card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
        [card.widthAnchor constraintLessThanOrEqualToConstant:620],
    ]];
}

@end

#pragma mark - The gallery

@interface RCActionRowPrototypeGalleryViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *descriptors;
@property (nonatomic, assign) BOOL hasAnimated;
- (void)openDescriptor:(NSDictionary *)descriptor;
- (void)closePresented;
@end

@implementation RCActionRowPrototypeGalleryViewController

+ (instancetype)prototypeGallery {
    return [[self alloc] init];
}

- (instancetype)init {
    return [self initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Action Row Styles";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.descriptors = RCRowProtoDescriptors();
    self.tableView.backgroundColor = RCRowProtoPageColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 360;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 0;
    [self.tableView registerClass:[RCRowProtoGalleryCell class] forCellReuseIdentifier:@"card"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.tableView.backgroundColor = RCRowProtoPageColor();
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!self.isViewLoaded || !previousTraitCollection) return;
    if ([self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) return;
    [self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.hasAnimated || UIAccessibilityIsReduceMotionEnabled()) return;
    self.hasAnimated = YES;
    NSArray<UITableViewCell *> *cells = self.tableView.visibleCells;
    for (NSUInteger i = 0; i < cells.count; i++) {
        UIView *card = cells[i].contentView.subviews.firstObject;
        card.alpha = 0;
        card.transform = CGAffineTransformMakeTranslation(0, 12);
        [UIView animateWithDuration:0.38
                              delay:0.05 * i
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            card.alpha = 1;
            card.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

#pragma mark Rows

- (NSArray<NSDictionary *> *)descriptorsForSection:(NSInteger)section {
    if (section == 0) return [self.descriptors subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)5, self.descriptors.count))];
    return [self.descriptors subarrayWithRange:NSMakeRange(MIN((NSUInteger)5, self.descriptors.count),
                                                            self.descriptors.count - MIN((NSUInteger)5, self.descriptors.count))];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self descriptorsForSection:section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCRowProtoGalleryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"card" forIndexPath:indexPath];
    NSDictionary *descriptor = [self descriptorsForSection:indexPath.section][indexPath.row];
    __weak typeof(self) weakSelf = self;
    cell.onOpenDescriptor = ^(NSDictionary *item) {
        [weakSelf openDescriptor:item];
    };
    [cell configureWithDescriptor:descriptor];
    return cell;
}

- (void)openDescriptor:(NSDictionary *)descriptor {
    RCRowProtoDetailViewController *detail = [[RCRowProtoDetailViewController alloc] initWithDescriptor:descriptor];
    detail.hidesBottomBarWhenPushed = YES;
    if (self.navigationController) {
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detail];
    detail.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                            target:self
                                                                                            action:@selector(closePresented)];
    if (@available(iOS 15.0, *)) {
        nav.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent largeDetent]];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)closePresented {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark Headers and feet

- (UIView *)headerForSection:(NSInteger)section width:(CGFloat)width {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 0)];

    UIView *inner = [[UIView alloc] init];
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [inner.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],
        [inner.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
        [inner.leadingAnchor constraintGreaterThanOrEqualToAnchor:header.leadingAnchor constant:20],
        [inner.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-20],
        [inner.widthAnchor constraintLessThanOrEqualToConstant:620],
    ]];
    NSLayoutConstraint *innerWidth = [inner.widthAnchor constraintEqualToAnchor:header.widthAnchor constant:-40];
    innerWidth.priority = 999;
    innerWidth.active = YES;

    BOOL first = section == 0;
    UILabel *eyebrow = RCRowProtoEyebrow(first ? @"PROTOTYPE · TEMPORARY" : @"VALUE EDITORS", [UIColor secondaryLabelColor]);
    UILabel *title = RCRowProtoLabel(first ? @"The row after an action" : @"Three panels, one family",
                                    RCRowProtoFont(UIFontTextStyleTitle2, UIFontWeightSemibold), [UIColor labelColor]);
    title.numberOfLines = 0;
    UILabel *body = RCRowProtoNote(first
        ? @"A value should live on the row that owns it. R1 is what ships now: the row has no value, and a modal alert asks for it. R2-R5 keep it in the sequence, in a chip the row opens. Tap a card to try one full size."
        : @"Number, choice and text. One panel per kind, so a chip, an inline row and the inspector column all open the same thing.");

    [inner addSubview:eyebrow];
    [inner addSubview:title];
    [inner addSubview:body];
    [NSLayoutConstraint activateConstraints:@[
        [eyebrow.leadingAnchor constraintEqualToAnchor:inner.leadingAnchor],
        [eyebrow.trailingAnchor constraintLessThanOrEqualToAnchor:inner.trailingAnchor],
        [eyebrow.topAnchor constraintEqualToAnchor:inner.topAnchor],
        [title.leadingAnchor constraintEqualToAnchor:inner.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:inner.trailingAnchor],
        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:6],
        [body.leadingAnchor constraintEqualToAnchor:inner.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:inner.trailingAnchor],
        [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [body.bottomAnchor constraintEqualToAnchor:inner.bottomAnchor],
    ]];
    return header;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [self headerForSection:section width:CGRectGetWidth(tableView.bounds)];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    CGFloat width = CGRectGetWidth(tableView.bounds);
    UIView *header = [self headerForSection:section width:width];
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                         withHorizontalFittingPriority:UILayoutPriorityRequired
                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return ceil(size.height);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != 1) return nil;
    CGFloat width = CGRectGetWidth(tableView.bounds);
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 0)];
    UILabel *note = RCRowProtoNote(@"Nothing here is wired into your actions. Close the screen and everything is exactly as it was.");
    [footer addSubview:note];
    [NSLayoutConstraint activateConstraints:@[
        [note.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20],
        [note.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20],
        [note.topAnchor constraintEqualToAnchor:footer.topAnchor constant:12],
        [note.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:-28],
    ]];
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section != 1) return 0.0001;
    CGFloat width = CGRectGetWidth(tableView.bounds);
    UIView *footer = [self tableView:tableView viewForFooterInSection:section];
    CGSize size = [footer systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                         withHorizontalFittingPriority:UILayoutPriorityRequired
                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return ceil(size.height);
}

@end




