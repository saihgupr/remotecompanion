#import "RCFunctionsMenuPrototypeGalleryViewController.h"
#import "RCFunctionsMenuPrototypeKit.h"
#import "RCFunctionsMenuPrototypeScreens.h"

#import <math.h>

// ---------------------------------------------------------------------------
// TEMPORARY DESIGN PROTOTYPE
//
// Six takes on the Select Action picker, shown as inert screens inside cards at
// close to their real width. Tapping a card opens that take alone, full size.
//
// Nothing in this file is referenced by the shipping picker. The only existing
// file it could touch is RCAdvancedSettingsViewController, for the entry row.
// ---------------------------------------------------------------------------

#pragma mark - Fade at the bottom of a card

// The card cuts a full screen off partway down; this softens the cut instead of
// ending on a half row.
@interface RCFMFadeView : UIView
@end

@implementation RCFMFadeView

+ (Class)layerClass {
    return [CAGradientLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self updateColors];
    }
    return self;
}

- (void)updateColors {
    CAGradientLayer *gradient = (CAGradientLayer *)self.layer;
    UIColor *page = RCFMPageColor();
    gradient.colors = @[(id)[page colorWithAlphaComponent:0].CGColor, (id)page.CGColor];
    gradient.startPoint = CGPointMake(0.5, 0);
    gradient.endPoint = CGPointMake(0.5, 1);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateColors];
}

@end

#pragma mark - Full size take

@interface RCFMPrototypeDetailViewController : UIViewController
- (instancetype)initWithDescriptor:(NSDictionary *)descriptor;
@end

@interface RCFMPrototypeDetailViewController ()
@property (nonatomic, copy) NSDictionary *descriptor;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *frameView;
@end

@implementation RCFMPrototypeDetailViewController

- (instancetype)initWithDescriptor:(NSDictionary *)descriptor {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _descriptor = [descriptor copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.descriptor[@"name"];
    self.navigationItem.prompt = [NSString stringWithFormat:@"Prototype %@", self.descriptor[@"letter"]];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                          target:self
                                                                                          action:@selector(close)];

    self.view.backgroundColor = RCFMPageColor();

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.alwaysBounceVertical = YES;
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

    [self installScreen];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.frameView.layer.borderColor = [RCFMBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)installScreen {
    [self.frameView removeFromSuperview];

    UIView *frame = [[UIView alloc] init];
    frame.backgroundColor = RCFMPageColor();
    frame.layer.cornerRadius = 22;
    frame.layer.cornerCurve = kCACornerCurveContinuous;
    frame.layer.borderWidth = 1;
    frame.clipsToBounds = YES;
    frame.translatesAutoresizingMaskIntoConstraints = NO;
    frame.isAccessibilityElement = YES;
    frame.accessibilityLabel = @"Static preview of this prototype screen";
    self.frameView = frame;
    [self.contentView addSubview:frame];

    RCFMScreenView *screen = ((RCFMScreenView *(^)(void))self.descriptor[@"make"])();
    screen.userInteractionEnabled = NO;
    screen.accessibilityElementsHidden = YES;
    [frame addSubview:screen];

    NSLayoutConstraint *width = [frame.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor constant:-32];
    width.priority = 999;
    [NSLayoutConstraint activateConstraints:@[
        [frame.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [frame.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [frame.widthAnchor constraintLessThanOrEqualToConstant:420],
        [frame.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [frame.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [frame.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-24],
        [screen.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor],
        [screen.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor],
        [screen.topAnchor constraintEqualToAnchor:frame.topAnchor],
        [screen.bottomAnchor constraintEqualToAnchor:frame.bottomAnchor],
        width,
    ]];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!self.isViewLoaded || !previousTraitCollection) return;
    if ([self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) return;
    [self installScreen];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Contact sheet card

@interface RCFMPrototypeCardView : UIControl
@property (nonatomic, copy) void (^onOpen)(void);
- (instancetype)initWithDescriptor:(NSDictionary *)descriptor;
@end

@interface RCFMPrototypeCardView ()
@property (nonatomic, strong) UIView *stageView;
@end

@implementation RCFMPrototypeCardView

- (instancetype)initWithDescriptor:(NSDictionary *)descriptor {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = RCFMBlockColor();
        self.layer.cornerRadius = 18;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityLabel = [NSString stringWithFormat:@"Prototype %@, %@. %@",
                                   descriptor[@"letter"], descriptor[@"name"], descriptor[@"summary"]];
        self.accessibilityHint = @"Opens this take full size";

        UIView *badge = [[UIView alloc] init];
        badge.backgroundColor = [RCFMAccent() colorWithAlphaComponent:0.16];
        badge.layer.cornerRadius = 8;
        badge.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *letter = [[UILabel alloc] init];
        letter.text = descriptor[@"letter"];
        letter.font = RCFMMonoFont(12, UIFontTextStyleCaption1, UIFontWeightSemibold);
        letter.textColor = RCFMAccent();
        letter.textAlignment = NSTextAlignmentCenter;
        letter.adjustsFontSizeToFitWidth = YES;
        letter.minimumScaleFactor = 0.7;
        letter.translatesAutoresizingMaskIntoConstraints = NO;
        [badge addSubview:letter];
        [NSLayoutConstraint activateConstraints:@[
            [letter.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:6],
            [letter.trailingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:-6],
            [letter.topAnchor constraintEqualToAnchor:badge.topAnchor constant:4],
            [letter.bottomAnchor constraintEqualToAnchor:badge.bottomAnchor constant:-4],
            [badge.widthAnchor constraintGreaterThanOrEqualToConstant:26],
            [badge.heightAnchor constraintGreaterThanOrEqualToConstant:26],
        ]];

        UILabel *name = [[UILabel alloc] init];
        name.text = descriptor[@"name"];
        name.font = RCFMFont(UIFontTextStyleHeadline, UIFontWeightSemibold);
        name.textColor = [UIColor labelColor];
        name.numberOfLines = 0;
        name.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *summary = [[UILabel alloc] init];
        summary.text = descriptor[@"summary"];
        summary.font = RCFMFont(UIFontTextStyleFootnote, UIFontWeightRegular);
        summary.textColor = [UIColor secondaryLabelColor];
        summary.numberOfLines = 0;
        summary.translatesAutoresizingMaskIntoConstraints = NO;

        UIImageView *chevron = [[UIImageView alloc] init];
        chevron.image = [UIImage systemImageNamed:@"chevron.right"
                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11
                                                                                                weight:UIImageSymbolWeightSemibold]];
        chevron.tintColor = [UIColor tertiaryLabelColor];
        chevron.translatesAutoresizingMaskIntoConstraints = NO;

        self.stageView = [[UIView alloc] init];
        self.stageView.backgroundColor = RCFMPageColor();
        self.stageView.layer.cornerRadius = 14;
        self.stageView.layer.cornerCurve = kCACornerCurveContinuous;
        self.stageView.layer.borderWidth = 1;
        self.stageView.clipsToBounds = YES;
        self.stageView.translatesAutoresizingMaskIntoConstraints = NO;

        RCFMScreenView *screen = ((RCFMScreenView *(^)(void))descriptor[@"make"])();
        screen.userInteractionEnabled = NO;
        screen.accessibilityElementsHidden = YES;
        [self.stageView addSubview:screen];

        RCFMFadeView *fade = [[RCFMFadeView alloc] initWithFrame:CGRectZero];
        [self.stageView addSubview:fade];

        [self addSubview:badge];
        [self addSubview:name];
        [self addSubview:summary];
        [self addSubview:chevron];
        [self addSubview:self.stageView];

        NSLayoutConstraint *stageWidth = [self.stageView.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-20];
        stageWidth.priority = 999;

        [NSLayoutConstraint activateConstraints:@[
            [badge.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [badge.centerYAnchor constraintEqualToAnchor:name.centerYAnchor],

            [name.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:10],
            [name.topAnchor constraintEqualToAnchor:self.topAnchor constant:11],
            [name.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-6],

            [chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [chevron.centerYAnchor constraintEqualToAnchor:name.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:12],
            [chevron.heightAnchor constraintEqualToConstant:16],

            [summary.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
            [summary.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [summary.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:3],

            [self.stageView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:10],
            [self.stageView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-10],
            [self.stageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.stageView.widthAnchor constraintLessThanOrEqualToConstant:400],
            [self.stageView.topAnchor constraintEqualToAnchor:summary.bottomAnchor constant:10],
            [self.stageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
            [self.stageView.heightAnchor constraintGreaterThanOrEqualToConstant:[descriptor[@"previewHeight"] doubleValue]],
            stageWidth,

            [screen.leadingAnchor constraintEqualToAnchor:self.stageView.leadingAnchor],
            [screen.trailingAnchor constraintEqualToAnchor:self.stageView.trailingAnchor],
            [screen.topAnchor constraintEqualToAnchor:self.stageView.topAnchor],

            [fade.leadingAnchor constraintEqualToAnchor:self.stageView.leadingAnchor],
            [fade.trailingAnchor constraintEqualToAnchor:self.stageView.trailingAnchor],
            [fade.bottomAnchor constraintEqualToAnchor:self.stageView.bottomAnchor],
            [fade.heightAnchor constraintEqualToConstant:40],
        ]];

        [self addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
        [self applyBorderColors];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyBorderColors];
}

- (void)applyBorderColors {
    UIColor *border = [RCFMBorderColor() resolvedColorWithTraitCollection:self.traitCollection];
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
        self.transform = highlighted ? CGAffineTransformMakeScale(0.98, 0.98) : CGAffineTransformIdentity;
        self.alpha = highlighted ? 0.92 : 1.0;
    } completion:nil];
}

@end

@interface RCFMPrototypeCardCell : UITableViewCell
@property (nonatomic, strong) UIStackView *rowStack;
@property (nonatomic, copy) void (^onOpenDescriptor)(NSDictionary *descriptor);
- (void)configureWithDescriptors:(NSArray<NSDictionary *> *)descriptors;
@end

@implementation RCFMPrototypeCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _rowStack = [[UIStackView alloc] init];
        _rowStack.axis = UILayoutConstraintAxisHorizontal;
        _rowStack.spacing = 10;
        _rowStack.alignment = UIStackViewAlignmentFill;
        _rowStack.distribution = UIStackViewDistributionFillEqually;
        _rowStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_rowStack];
        [NSLayoutConstraint activateConstraints:@[
            [_rowStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_rowStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_rowStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:7],
            [_rowStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-7],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.rowStack.alpha = 1.0;
    self.rowStack.transform = CGAffineTransformIdentity;
}

- (void)configureWithDescriptors:(NSArray<NSDictionary *> *)descriptors {
    self.rowStack.alpha = 1.0;
    self.rowStack.transform = CGAffineTransformIdentity;
    for (UIView *view in self.rowStack.arrangedSubviews) {
        [self.rowStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSDictionary *descriptor in descriptors) {
        RCFMPrototypeCardView *card = [[RCFMPrototypeCardView alloc] initWithDescriptor:descriptor];
        __weak typeof(self) weakSelf = self;
        card.onOpen = ^{
            if (weakSelf.onOpenDescriptor) weakSelf.onOpenDescriptor(descriptor);
        };
        [self.rowStack addArrangedSubview:card];
    }
}

@end

#pragma mark - Gallery

@interface RCFunctionsMenuPrototypeGalleryViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *variants;
@property (nonatomic, assign) NSInteger columnCount;
@property (nonatomic, assign) CGFloat headerWidth;
@property (nonatomic, copy) NSString *headerCategory;
@property (nonatomic, assign) BOOL hasAnimated;
@end

@implementation RCFunctionsMenuPrototypeGalleryViewController

+ (instancetype)galleryViewController {
    return [[self alloc] init];
}

- (instancetype)init {
    return [self initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Action Menu Styles";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.variants = @[
        @{ @"letter": @"P1", @"name": @"Current", @"previewHeight": @420,
           @"summary": @"The shipping list, as it is today.",
           @"make": ^RCFMScreenView *(void){ return RCFMMakeP1(); } },
        @{ @"letter": @"P2", @"name": @"Icon chips", @"previewHeight": @420,
           @"summary": @"Chips gain symbols, tighter metrics and an accent fill.",
           @"make": ^RCFMScreenView *(void){ return RCFMMakeP2(); } },
        @{ @"letter": @"P3", @"name": @"Search first", @"previewHeight": @540,
           @"summary": @"Big search up top, then Recent and Favorites cards.",
           @"make": ^RCFMScreenView *(void){ return RCFMMakeP3(); } },
        @{ @"letter": @"P4", @"name": @"Rows with values", @"previewHeight": @660,
           @"summary": @"Each row shows its setting: 40%, 2s, AudioStream.",
           @"make": ^RCFMScreenView *(void){ return RCFMMakeP4(); } },
        @{ @"letter": @"P5", @"name": @"Large grid", @"previewHeight": @480,
           @"summary": @"Two-column tiles with a one-line subtitle.",
           @"make": ^RCFMScreenView *(void){ return RCFMMakeP5(); } },
        @{ @"letter": @"P6", @"name": @"Command palette", @"previewHeight": @460,
           @"summary": @"One flat ranked list, tagged; clears to Recents.",
           @"make": ^RCFMScreenView *(void){ return RCFMMakeP6(); } },
    ];

    self.tableView.backgroundColor = RCFMPageColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 560;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    self.tableView.showsVerticalScrollIndicator = YES;
    [self.tableView registerClass:[RCFMPrototypeCardCell class] forCellReuseIdentifier:@"card"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.tableView.backgroundColor = RCFMPageColor();
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    NSInteger columns = [self columnCountForWidth:width];
    if (columns != self.columnCount) {
        self.columnCount = columns;
        [self.tableView reloadData];
    }
    NSString *category = self.traitCollection.preferredContentSizeCategory ?: @"";
    BOOL sameWidth = fabs(self.headerWidth - width) < 0.5;
    BOOL sameCategory = [self.headerCategory isEqualToString:category];
    if (sameWidth && sameCategory && self.tableView.tableHeaderView) return;
    self.headerWidth = width;
    self.headerCategory = category;
    self.tableView.tableHeaderView = [self makeHeaderViewWithWidth:width];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!self.isViewLoaded || !previousTraitCollection) return;
    if ([self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) return;
    self.tableView.tableHeaderView = nil;
    [self.tableView reloadData];
    [self.view setNeedsLayout];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.hasAnimated || UIAccessibilityIsReduceMotionEnabled()) return;
    self.hasAnimated = YES;
    NSArray<UITableViewCell *> *cells = self.tableView.visibleCells;
    for (NSUInteger i = 0; i < cells.count; i++) {
        UIStackView *stack = ((RCFMPrototypeCardCell *)cells[i]).rowStack;
        stack.alpha = 0;
        stack.transform = CGAffineTransformMakeTranslation(0, 12);
        [UIView animateWithDuration:0.38
                              delay:0.04 * i
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            stack.alpha = 1;
            stack.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

#pragma mark - Rows

- (NSInteger)columnCountForWidth:(CGFloat)width {
    return width >= RCFMColumnBreak ? 2 : 1;
}

- (NSArray<NSArray<NSDictionary *> *> *)rows {
    NSInteger columns = MAX(1, self.columnCount);
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.variants.count; i += columns) {
        NSRange range = NSMakeRange(i, MIN((NSUInteger)columns, self.variants.count - i));
        [rows addObject:[self.variants subarrayWithRange:range]];
    }
    return rows;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger columns = [self columnCountForWidth:CGRectGetWidth(tableView.bounds)];
    if (columns != self.columnCount) self.columnCount = columns;
    return (NSInteger)self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCFMPrototypeCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"card" forIndexPath:indexPath];
    __weak typeof(self) weakSelf = self;
    cell.onOpenDescriptor = ^(NSDictionary *descriptor) {
        [weakSelf openDescriptor:descriptor];
    };
    [cell configureWithDescriptors:self.rows[indexPath.row]];
    return cell;
}

- (void)openDescriptor:(NSDictionary *)descriptor {
    RCFMPrototypeDetailViewController *detail = [[RCFMPrototypeDetailViewController alloc] initWithDescriptor:descriptor];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detail];
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent]];
        sheet.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Header

- (NSAttributedString *)eyebrowText:(NSString *)text color:(UIColor *)color kern:(CGFloat)kern {
    return [[NSAttributedString alloc] initWithString:text
                                           attributes:@{
        NSFontAttributeName: RCFMFont(UIFontTextStyleCaption2, UIFontWeightSemibold),
        NSForegroundColorAttributeName: color,
        NSKernAttributeName: @(kern),
    }];
}

- (UIView *)makeHeaderViewWithWidth:(CGFloat)width {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 0)];

    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.attributedText = [self eyebrowText:@"PROTOTYPE" color:[UIColor secondaryLabelColor] kern:1.4];
    eyebrow.lineBreakMode = NSLineBreakByTruncatingTail;
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *range = [[UILabel alloc] init];
    range.attributedText = [self eyebrowText:@"SIX TAKES" color:[UIColor tertiaryLabelColor] kern:1.0];
    range.textAlignment = NSTextAlignmentRight;
    range.hidden = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
                   || [self.traitCollection.preferredContentSizeCategory isEqualToString:UIContentSizeCategoryExtraExtraExtraLarge];
    [range setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    range.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.text = @"Ways to pick an action";
    title.font = RCFMFont(UIFontTextStyleTitle2, UIFontWeightSemibold);
    title.textColor = [UIColor labelColor];
    title.numberOfLines = 0;
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *body = [[UILabel alloc] init];
    body.text = @"Six takes on Select Action. P1 is today's screen; the rest change one idea each. Tap a card to open it full size.";
    body.font = RCFMFont(UIFontTextStyleFootnote, UIFontWeightRegular);
    body.textColor = [UIColor secondaryLabelColor];
    body.numberOfLines = 0;
    body.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:eyebrow];
    [header addSubview:range];
    [header addSubview:title];
    [header addSubview:body];
    [NSLayoutConstraint activateConstraints:@[
        [eyebrow.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [eyebrow.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],
        [eyebrow.trailingAnchor constraintLessThanOrEqualToAnchor:range.leadingAnchor constant:-12],
        [range.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [range.centerYAnchor constraintEqualToAnchor:eyebrow.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [title.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:8],
        [body.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [body.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [body.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16],
    ]];

    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                         withHorizontalFittingPriority:UILayoutPriorityRequired
                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    header.frame = CGRectMake(0, 0, width, size.height);
    return header;
}

@end
