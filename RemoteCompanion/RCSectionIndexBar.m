#import "RCSectionIndexBar.h"
#import <QuartzCore/QuartzCore.h>

// The rail lives in the margin left of the inset-grouped cards (20 pt on a
// phone), so its letters never sit on a row. The bubble only appears under a
// finger, and that finger may slide right off the rail and down the bubble's
// rows to pick one of the categories filed under the letter.
static const CGFloat RCSectionRailWidth = 20.0;
static const CGFloat RCSectionRailMinRow = 10.0;
static const CGFloat RCSectionRailMaxRow = 30.0;
static const CGFloat RCSectionRailTopInset = 10.0;
static const CGFloat RCSectionRailBottomInset = 12.0;
static const CGFloat RCSectionHighlightMaxSide = 18.0;
static const CGFloat RCSectionBubbleGap = 8.0;
static const CGFloat RCSectionBubblePadding = 12.0;
static const CGFloat RCSectionBubbleRowHeight = 26.0;
static const CGFloat RCSectionBubbleIconSide = 16.0;
static const CGFloat RCSectionBubbleIconGap = 8.0;

static UIFont *RCSectionBubbleFont(void) {
    return [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
}

#pragma mark - Entries

// One tick on the rail: a letter, or the star for Favorites, and the section it
// jumps to. Several categories can share a letter; the entry points at the
// first of them.
@interface RCSectionIndexEntry : NSObject
@property (nonatomic, copy) NSString *letter;
@property (nonatomic, assign) NSInteger section;
@end

@implementation RCSectionIndexEntry

+ (instancetype)letterEntry:(NSString *)letter section:(NSInteger)section {
    RCSectionIndexEntry *entry = [[RCSectionIndexEntry alloc] init];
    entry.letter = letter;
    entry.section = section;
    return entry;
}

+ (instancetype)starEntryForSection:(NSInteger)section {
    return [self letterEntry:nil section:section];
}

@end

// The letter a title is filed under ("App Launch Triggers" -> A). A title with
// no letters at all (there is none today) shares the # entry.
static NSString *RCSectionIndexLetterForTitle(NSString *title) {
    if (title.length == 0) return nil;
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    for (NSUInteger i = 0; i < title.length; i++) {
        unichar c = [title characterAtIndex:i];
        if ([letters characterIsMember:c]) {
            return [[title substringWithRange:NSMakeRange(i, 1)] uppercaseString];
        }
    }
    return @"#";
}

#pragma mark - Glyph

// A letter, or the star, centred in its row. Its tint is the only state; the
// circle behind it belongs to the bar.
@interface RCSectionIndexGlyphView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIImageView *imageView;
- (void)applyFont:(UIFont *)font;
- (void)setActive:(BOOL)active;
@end

@implementation RCSectionIndexGlyphView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];

        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.contentMode = UIViewContentModeCenter;
        _imageView.userInteractionEnabled = NO;
        [self addSubview:_imageView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.label.frame = self.bounds;
    self.imageView.frame = self.bounds;
}

- (void)applyFont:(UIFont *)font {
    self.label.font = font;
}

- (void)setActive:(BOOL)active {
    UIColor *color = active ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    self.label.textColor = color;
    self.imageView.tintColor = color;
}

@end

#pragma mark - Bubble row

// One section inside the capsule: its icon, its name, and a quieter tint unless
// it is the row the list is showing or about to show.
@interface RCSectionBubbleRowView : UIView
@property (nonatomic, strong) UIView *selectionView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) BOOL emphasized;
- (void)applyTitle:(NSString *)title icon:(UIImage *)icon emphasized:(BOOL)emphasized;
- (void)applyColors;
@end

@implementation RCSectionBubbleRowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;

        // A faint well behind the row the finger has settled on, so the eye can
        // follow it while the rows move under the finger
        _selectionView = [[UIView alloc] initWithFrame:CGRectZero];
        _selectionView.layer.cornerRadius = 6.0;
        _selectionView.backgroundColor = [UIColor clearColor];
        _selectionView.userInteractionEnabled = NO;
        [self addSubview:_selectionView];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.font = RCSectionBubbleFont();
        _label.numberOfLines = 1;
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_label];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.selectionView.frame = CGRectInset(self.bounds, -4.0, 1.0);
    CGFloat iconRoom = self.iconView.hidden ? 0.0 : (RCSectionBubbleIconSide + RCSectionBubbleIconGap);
    self.iconView.frame = CGRectMake(0, (self.bounds.size.height - RCSectionBubbleIconSide) / 2.0,
                                     RCSectionBubbleIconSide, RCSectionBubbleIconSide);
    self.label.frame = CGRectMake(iconRoom, 0,
                                  MAX(0.0, self.bounds.size.width - iconRoom),
                                  self.bounds.size.height);
}

- (void)applyTitle:(NSString *)title icon:(UIImage *)icon emphasized:(BOOL)emphasized {
    self.label.text = title;
    self.iconView.image = icon;
    self.iconView.hidden = (icon == nil);
    self.emphasized = emphasized;
    [self applyColors];
    [self setNeedsLayout];
}

- (void)applyColors {
    UIColor *color = self.emphasized ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    self.label.textColor = color;
    self.iconView.tintColor = color;
    self.selectionView.backgroundColor = self.emphasized ? [UIColor quaternarySystemFillColor] : [UIColor clearColor];
}

@end

#pragma mark - Bar

@interface RCSectionIndexBar ()
@property (nonatomic, copy) NSArray<RCSectionIndexEntry *> *entries;
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy) NSArray *icons;
@property (nonatomic, strong) NSMutableArray<RCSectionIndexGlyphView *> *glyphs;
@property (nonatomic, strong) UIView *stackView;
@property (nonatomic, strong) UIView *highlight;
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) NSMutableArray<RCSectionBubbleRowView *> *bubbleRows;
@property (nonatomic, strong) UISelectionFeedbackGenerator *haptics;
@property (nonatomic, assign) NSInteger activeEntry;
// The row inside the active letter's group, 0-based. Separate from activeEntry
// so the letter stays marked while the finger walks the rows.
@property (nonatomic, assign) NSInteger activeRow;
@property (nonatomic, assign) NSInteger activeRowCount;
// YES while the finger has slid right off the rail into the capsule: the
// capsule is frozen and its rows drive the list instead of the letters.
@property (nonatomic, assign) BOOL inBubble;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) BOOL shown;
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, assign) BOOL laidOut;
@property (nonatomic, assign) BOOL keepActiveAfterScroll;
@property (nonatomic, assign) CGFloat rowHeight;
@property (nonatomic, assign) CGFloat stackTop;
@property (nonatomic, assign) CGFloat stackLeft;
@property (nonatomic, assign) CGFloat stackHeight;
@property (nonatomic, weak) UIView *host;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, assign) CFTimeInterval animStartTime;
@property (nonatomic, assign) CGFloat animStartOffset;
@property (nonatomic, assign) CGFloat animTargetOffset;
@property (nonatomic, assign) CFTimeInterval animDuration;
@property (nonatomic, assign) BOOL indicatorWasShown;
@property (nonatomic, assign) BOOL indicatorHidden;
@end

@implementation RCSectionIndexBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.multipleTouchEnabled = NO;
        self.hidden = YES;
        self.alpha = 0.0;
        _glyphs = [NSMutableArray array];
        _bubbleRows = [NSMutableArray array];
        _activeEntry = -1;
        _haptics = [[UISelectionFeedbackGenerator alloc] init];

        // The letters share one column; the circle slides behind the active one
        _stackView = [[UIView alloc] initWithFrame:CGRectZero];
        _stackView.backgroundColor = [UIColor clearColor];
        _stackView.userInteractionEnabled = NO;
        [self addSubview:_stackView];

        _highlight = [[UIView alloc] initWithFrame:CGRectZero];
        _highlight.alpha = 0.0;
        _highlight.userInteractionEnabled = NO;
        [_stackView addSubview:_highlight];

        _bubble = [[UIView alloc] initWithFrame:CGRectZero];
        _bubble.layer.cornerRadius = 12.0;
        _bubble.layer.borderWidth = 0.5;
        _bubble.alpha = 0.0;
        _bubble.userInteractionEnabled = NO;
        [self addSubview:_bubble];

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;
        self.accessibilityLabel = @"Section index";
        [self updateColors];
    }
    return self;
}

- (void)dealloc {
    [_link invalidate];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self cancelScrollAnimation];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self updateColors];
        }
    }
}

- (void)updateColors {
    UIColor *card = [UIColor secondarySystemGroupedBackgroundColor];
    self.bubble.backgroundColor = card;
    self.bubble.layer.borderColor = [[UIColor separatorColor] colorWithAlphaComponent:0.8].CGColor;
    self.highlight.backgroundColor = [UIColor secondarySystemFillColor];
    for (RCSectionBubbleRowView *row in self.bubbleRows) [row applyColors];
    [self updateGlyphColors];
}

#pragma mark - Data

- (void)setSectionTitles:(NSArray<NSString *> *)titles icons:(NSArray *)icons {
    self.titles = titles ?: @[];
    self.icons = icons ?: @[];

    for (RCSectionIndexGlyphView *glyph in self.glyphs) [glyph removeFromSuperview];
    [self.glyphs removeAllObjects];
    self.activeEntry = -1;
    self.activeRow = 0;
    self.activeRowCount = 0;
    self.inBubble = NO;
    self.bubble.alpha = 0.0;
    self.highlight.alpha = 0.0;

    // A star for Favorites, then one entry per new initial. The table is sorted
    // by title, so the sections with one initial sit together and the entry
    // jumps to the first of them.
    NSMutableArray<RCSectionIndexEntry *> *entries = [NSMutableArray array];
    NSUInteger first = 0;
    if (self.titles.count > 0 && [self.titles.firstObject isEqualToString:@"Favorites"]) {
        [entries addObject:[RCSectionIndexEntry starEntryForSection:0]];
        first = 1;
    }
    NSString *previous = nil;
    for (NSUInteger i = first; i < self.titles.count; i++) {
        NSString *letter = RCSectionIndexLetterForTitle(self.titles[i]);
        if (letter.length == 0 || [letter isEqualToString:previous]) continue;
        [entries addObject:[RCSectionIndexEntry letterEntry:letter section:(NSInteger)i]];
        previous = letter;
    }
    self.entries = entries;

    UIImage *star = [UIImage systemImageNamed:@"star.fill"];
    for (RCSectionIndexEntry *entry in entries) {
        RCSectionIndexGlyphView *glyph = [[RCSectionIndexGlyphView alloc] initWithFrame:CGRectZero];
        if (entry.letter.length == 0 && star) {
            glyph.imageView.image = star;
            glyph.imageView.preferredSymbolConfiguration =
                [UIImageSymbolConfiguration configurationWithPointSize:9.0 weight:UIImageSymbolWeightSemibold];
        } else {
            glyph.label.text = entry.letter.length > 0 ? entry.letter : @"★";
        }
        [glyph setActive:NO];
        [self.stackView addSubview:glyph];
        [self.glyphs addObject:glyph];
    }

    // A reload during a scrub must still place the new letters; the guard in
    // layoutInView is for chrome moving under a finger, not for new data
    BOOL scrubbing = self.scrubbing;
    self.scrubbing = NO;
    if (self.host) [self layoutInView:self.host];
    self.scrubbing = scrubbing;
    [self setShown:self.shown animated:NO];
    [self setNeedsLayout];
}

- (void)layoutInView:(UIView *)host {
    if (!host) return;
    self.host = host;
    // The chrome moves as the large title collapses: never shift the letters
    // under a finger that is already on them
    if (self.scrubbing) return;
    self.frame = CGRectMake(0, 0, host.bounds.size.width, host.bounds.size.height);
    self.stackView.frame = self.bounds;
    self.laidOut = YES;

    UIEdgeInsets safe = host.safeAreaInsets;
    NSUInteger count = self.entries.count;
    if (count == 0) {
        self.stackTop = 0;
        self.stackHeight = 0;
        self.highlight.frame = CGRectZero;
        return;
    }

    CGFloat chromeTop = (self.topChrome > 0 ? self.topChrome : safe.top + 144.0) + RCSectionRailTopInset;
    CGFloat bottomBound = host.bounds.size.height - safe.bottom - RCSectionRailBottomInset;
    CGFloat available = MAX(120.0, bottomBound - chromeTop);

    // A generous, even pitch that never grows past a comfortable finger, and
    // the column centred on the screen so the first and last letters sit an
    // equal distance from the edges
    CGFloat row = available / (CGFloat)count;
    row = MIN(row, RCSectionRailMaxRow);
    row = MAX(row, RCSectionRailMinRow);
    if (row * (CGFloat)count > available + 1.0) {
        row = MAX(1.0, available / (CGFloat)count); // landscape with many letters
    }
    CGFloat height = row * (CGFloat)count;
    CGFloat top = (host.bounds.size.height - height) / 2.0;
    CGFloat maxTop = bottomBound - height;
    if (maxTop < chromeTop) {
        top = chromeTop;
    } else {
        top = MIN(MAX(top, chromeTop), maxTop);
    }
    CGFloat left = safe.left;

    self.rowHeight = row;
    self.stackTop = top;
    self.stackLeft = left;
    self.stackHeight = height;

    UIFont *font = [UIFont systemFontOfSize:MIN(11.0, MAX(7.0, row - 3.0)) weight:UIFontWeightSemibold];
    for (NSUInteger i = 0; i < count; i++) {
        RCSectionIndexGlyphView *glyph = self.glyphs[i];
        [glyph applyFont:font];
        glyph.frame = CGRectMake(left, top + row * (CGFloat)i, RCSectionRailWidth, row);
    }

    CGFloat side = MIN(RCSectionHighlightMaxSide, MAX(8.0, row - 2.0));
    self.highlight.bounds = CGRectMake(0, 0, side, side);
    self.highlight.layer.cornerRadius = side / 2.0;
    [self positionHighlightForEntry:self.activeEntry];

    if (self.activeEntry >= 0) [self updateBubbleForEntry:self.activeEntry];
}

#pragma mark - Showing

- (void)setShown:(BOOL)shown animated:(BOOL)animated {
    self.shown = shown;
    BOOL visible = shown && self.entries.count > 1;
    if (visible == self.visible) {
        self.hidden = !visible;
        self.userInteractionEnabled = visible;
        return;
    }
    self.visible = visible;
    self.userInteractionEnabled = visible;

    if (!visible) {
        [self cancelScrollAnimation];
        self.scrubbing = NO;
        [self resetAppearanceAnimated:NO];
    }

    if (visible) self.hidden = NO;
    if (!animated) {
        self.alpha = visible ? 1.0 : 0.0;
        self.hidden = !visible;
        return;
    }
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{ self.alpha = visible ? 1.0 : 0.0; }
                     completion:^(BOOL finished) { if (!self.visible) self.hidden = YES; }];
}

#pragma mark - Touch

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.visible || !self.laidOut) return NO;
    // A little wider than the letters, like the system index, but never far
    // enough right to cover a row's icon.
    CGFloat right = self.stackLeft + RCSectionRailWidth + 12.0;
    CGFloat top = self.stackTop - 12.0;
    CGFloat bottom = self.stackTop + self.stackHeight + 12.0;
    return point.x >= 0 && point.x <= right && point.y >= top && point.y <= bottom;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.entries.count < 2) return;
    CGPoint point = [touches.anyObject locationInView:self];
    [self beginScrubAtY:point.y];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.scrubbing) return;
    CGPoint point = [touches.anyObject locationInView:self];
    [self updateScrubAtPoint:point];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endScrub];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endScrub];
}

- (NSInteger)entryForY:(CGFloat)y {
    if (self.rowHeight <= 0 || self.entries.count == 0) return 0;
    NSInteger entry = (NSInteger)floor((y - self.stackTop) / self.rowHeight);
    return MAX(0, MIN((NSInteger)self.entries.count - 1, entry));
}

- (void)beginScrubAtY:(CGFloat)y {
    self.scrubbing = YES;
    self.inBubble = NO;
    self.activeRow = 0;
    self.keepActiveAfterScroll = NO;
    [self.haptics prepare];
    [self selectEntry:[self entryForY:y]];
    [self showHighlight];
    [self showBubble];
    [self hideIndicator];
}

// One finger drives both modes: left of the capsule it scrubs letters, well
// past the capsule's left edge it walks the capsule's rows. The gap between the
// two thresholds is a deadband, so a scrub that wobbles a little sideways does
// not fall into the capsule by accident.
- (void)updateScrubAtPoint:(CGPoint)point {
    // From bounds and centre, not frame: the show spring scales the frame
    CGFloat bubbleLeft = self.bubble.center.x - self.bubble.bounds.size.width / 2.0;
    CGFloat enterX = bubbleLeft + 6.0;
    CGFloat leaveX = self.stackLeft + RCSectionRailWidth + 4.0;

    if (!self.inBubble) {
        if (point.x >= enterX && self.bubble.alpha > 0.5) {
            self.inBubble = YES;
            [self selectRowAtY:point.y];
            return;
        }
        [self updateScrubAtY:point.y];
        return;
    }

    // Back over the letters: the capsule may follow the finger again
    if (point.x <= leaveX) {
        self.inBubble = NO;
        self.activeRow = 0;
        NSInteger entry = [self entryForY:point.y];
        // Same letter: re-centre on it. New letter: selectEntry rebuilds.
        if (entry == self.activeEntry) [self updateBubbleForEntry:entry];
        [self selectEntry:entry];
        return;
    }

    [self selectRowAtY:point.y];
}

- (void)updateScrubAtY:(CGFloat)y {
    NSInteger entry = [self entryForY:y];
    if (entry != self.activeEntry) [self selectEntry:entry];
}

// The row under the finger, read off where the capsule actually sits so a
// capsule clamped near the top or bottom still maps one row per 26 pt of finger
// travel.
- (void)selectRowAtY:(CGFloat)y {
    if (self.activeEntry < 0 || self.activeEntry >= (NSInteger)self.entries.count) return;
    NSInteger count = self.activeRowCount;
    if (count <= 0) return;

    CGFloat rowsTop = self.bubble.center.y - self.bubble.bounds.size.height / 2.0 + RCSectionBubblePadding;
    NSInteger row = (NSInteger)floor((y - rowsTop) / RCSectionBubbleRowHeight);
    row = MAX(0, MIN(count - 1, row));
    if (row == self.activeRow) return;

    self.activeRow = row;
    [self.haptics selectionChanged];
    [self updateBubbleEmphasis];
    NSInteger section = self.entries[self.activeEntry].section + row;
    [self animateToOffset:[self targetOffsetForSection:section] duration:0.16];
}

- (void)selectEntry:(NSInteger)entry {
    if (entry < 0 || entry >= (NSInteger)self.entries.count) return;
    BOOL changed = (entry != self.activeEntry);
    self.activeEntry = entry;

    if (changed) {
        self.activeRow = 0;
        [self.haptics selectionChanged];
        [self updateGlyphColors];
        [self updateBubbleForEntry:entry];
        [self positionHighlightForEntry:entry];
    }

    CGFloat target = [self targetOffsetForSection:self.entries[entry].section];
    [self animateToOffset:target duration:(self.scrubbing ? 0.16 : 0.32)];
}

- (void)endScrub {
    if (!self.scrubbing) return;
    self.scrubbing = NO;
    self.inBubble = NO;
    [self hideBubbleAnimated:YES];

    // The circle stays while the list settles, so the eye keeps the place
    NSInteger entry = self.activeEntry;
    if (entry < 0) return;
    NSInteger section = self.entries[entry].section + MAX(0, self.activeRow);
    [self animateToOffset:[self targetOffsetForSection:section] duration:0.32];
}

#pragma mark - Appearance

- (void)updateGlyphColors {
    for (NSUInteger i = 0; i < self.glyphs.count; i++) {
        [self.glyphs[i] setActive:((NSInteger)i == self.activeEntry)];
    }
}

- (void)positionHighlightForEntry:(NSInteger)entry {
    if (entry < 0 || entry >= (NSInteger)self.entries.count) return;
    self.highlight.center = CGPointMake(self.stackLeft + RCSectionRailWidth / 2.0,
                                        self.stackTop + self.rowHeight * ((CGFloat)entry + 0.5));
}

- (void)showHighlight {
    if (self.highlight.alpha < 0.01) {
        self.highlight.transform = CGAffineTransformMakeScale(0.72, 0.72);
    }
    [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.highlight.alpha = 1.0;
        self.highlight.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hideHighlightAnimated:(BOOL)animated {
    if (!animated) {
        self.highlight.alpha = 0.0;
        self.highlight.transform = CGAffineTransformIdentity;
        return;
    }
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{ self.highlight.alpha = 0.0; }
                     completion:nil];
}

- (void)showBubble {
    if (self.bubble.alpha < 0.01) {
        self.bubble.transform = CGAffineTransformMakeScale(0.92, 0.92);
    }
    [UIView animateWithDuration:0.18 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.2
                         options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.bubble.alpha = 1.0;
        self.bubble.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hideBubbleAnimated:(BOOL)animated {
    if (!animated) {
        self.bubble.alpha = 0.0;
        return;
    }
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{ self.bubble.alpha = 0.0; }
                     completion:nil];
}

- (void)resetAppearanceAnimated:(BOOL)animated {
    self.activeEntry = -1;
    self.activeRow = 0;
    self.activeRowCount = 0;
    self.inBubble = NO;
    [self updateGlyphColors];
    [self hideBubbleAnimated:animated];
    [self hideHighlightAnimated:animated];
}

#pragma mark - Bubble

// The capsule lists every section filed under the touched entry, the selected
// one at full strength and the rest quieter. It grows with the group, so its
// size and position are worked out per entry change, never per frame.
- (void)updateBubbleForEntry:(NSInteger)entry {
    // A finger inside the capsule owns it: rebuilding would slide rows under it
    if (self.inBubble) return;
    if (!self.host || entry < 0 || entry >= (NSInteger)self.entries.count) return;
    NSInteger firstSection = self.entries[entry].section;
    if (firstSection < 0 || firstSection >= (NSInteger)self.titles.count) return;
    NSInteger endSection = (entry + 1 < (NSInteger)self.entries.count)
        ? self.entries[entry + 1].section
        : (NSInteger)self.titles.count;
    endSection = MIN(endSection, (NSInteger)self.titles.count);
    NSUInteger rowCount = (NSUInteger)MAX(0, endSection - firstSection);
    if (rowCount == 0) return;
    self.activeRowCount = (NSInteger)rowCount;
    self.activeRow = MAX(0, MIN((NSInteger)rowCount - 1, self.activeRow));

    while (self.bubbleRows.count < rowCount) {
        RCSectionBubbleRowView *row = [[RCSectionBubbleRowView alloc] initWithFrame:CGRectZero];
        [self.bubble addSubview:row];
        [self.bubbleRows addObject:row];
    }

    // As wide as the longest name in the group, capped at the screen edge
    UIEdgeInsets safe = self.host.safeAreaInsets;
    CGFloat x = self.stackLeft + RCSectionRailWidth + RCSectionBubbleGap;
    CGFloat maxWidth = MAX(80.0, self.bounds.size.width - x - safe.right - 8.0);
    CGFloat maxText = MAX(40.0, maxWidth - RCSectionBubblePadding * 2.0
                         - RCSectionBubbleIconSide - RCSectionBubbleIconGap);
    UIFont *font = RCSectionBubbleFont();
    CGFloat widest = 0;
    for (NSUInteger i = 0; i < rowCount; i++) {
        NSString *title = self.titles[firstSection + (NSInteger)i];
        CGSize size = [title boundingRectWithSize:CGSizeMake(maxText, 20.0)
                                          options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                                       attributes:@{NSFontAttributeName: font}
                                          context:nil].size;
        widest = MAX(widest, ceil(MIN(size.width, maxText)));
    }
    CGFloat rowWidth = RCSectionBubbleIconSide + RCSectionBubbleIconGap + widest;
    CGFloat width = RCSectionBubblePadding * 2.0 + rowWidth;
    CGFloat height = RCSectionBubblePadding * 2.0 + RCSectionBubbleRowHeight * (CGFloat)rowCount;

    for (NSUInteger i = 0; i < self.bubbleRows.count; i++) {
        RCSectionBubbleRowView *row = self.bubbleRows[i];
        if (i >= rowCount) {
            row.hidden = YES;
            continue;
        }
        NSInteger section = firstSection + (NSInteger)i;
        id icon = (section < (NSInteger)self.icons.count) ? self.icons[section] : nil;
        UIImage *image = [icon isKindOfClass:[UIImage class]] ? icon : nil;
        [row applyTitle:self.titles[section] icon:image emphasized:((NSInteger)i == self.activeRow)];
        row.hidden = NO;
        row.frame = CGRectMake(RCSectionBubblePadding,
                               RCSectionBubblePadding + RCSectionBubbleRowHeight * (CGFloat)i,
                               rowWidth,
                               RCSectionBubbleRowHeight);
    }

    // Centred on the letter under the finger, kept inside the safe area
    CGFloat centerY = self.stackTop + self.rowHeight * ((CGFloat)entry + 0.5);
    CGFloat topLimit = safe.top + 8.0;
    CGFloat bottomLimit = self.bounds.size.height - safe.bottom - 8.0 - height;
    CGFloat y = centerY - height / 2.0;
    if (bottomLimit < topLimit) y = topLimit;
    else y = MIN(MAX(y, topLimit), bottomLimit);

    self.bubble.frame = CGRectMake(x, y, width, height);
}

// Only the tint moves as the finger walks the rows; the capsule itself stays
// where it was when the finger arrived.
- (void)updateBubbleEmphasis {
    for (NSUInteger i = 0; i < self.bubbleRows.count; i++) {
        RCSectionBubbleRowView *row = self.bubbleRows[i];
        BOOL emphasized = (!row.hidden && (NSInteger)i == self.activeRow);
        if (row.emphasized == emphasized) continue;
        row.emphasized = emphasized;
        [row applyColors];
    }
}

#pragma mark - Scrolling

- (CGFloat)targetOffsetForSection:(NSInteger)index {
    UITableView *table = self.tableView;
    if (!table) return 0;
    CGRect header = [table rectForHeaderInSection:index];
    UIEdgeInsets inset = table.adjustedContentInset;
    CGFloat top = header.origin.y - inset.top;
    CGFloat minOffset = -inset.top;
    CGFloat maxOffset = MAX(minOffset, table.contentSize.height + inset.bottom - table.bounds.size.height);
    return MIN(MAX(top, minOffset), maxOffset);
}

- (void)animateToOffset:(CGFloat)target duration:(CFTimeInterval)duration {
    UITableView *table = self.tableView;
    if (!table) return;

    // The table's own deceleration would fight the glide
    CGPoint current = table.contentOffset;
    [table setContentOffset:current animated:NO];

    if (fabs(target - current.y) < 0.5) {
        table.contentOffset = CGPointMake(current.x, target);
        [self finishScrollAnimation];
        return;
    }

    [self.link invalidate];
    self.animStartOffset = current.y;
    self.animTargetOffset = target;
    self.animStartTime = CACurrentMediaTime();
    self.animDuration = MAX(0.08, duration);
    [self hideIndicator];

    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(stepScrollAnimation:)];
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stepScrollAnimation:(CADisplayLink *)link {
    UITableView *table = self.tableView;
    if (!table) {
        [self finishScrollAnimation];
        return;
    }
    CFTimeInterval t = (CACurrentMediaTime() - self.animStartTime) / self.animDuration;
    if (t >= 1.0) {
        table.contentOffset = CGPointMake(table.contentOffset.x, self.animTargetOffset);
        [self finishScrollAnimation];
        return;
    }
    CGFloat eased = 1.0 - pow(1.0 - t, 3.0);
    CGFloat y = self.animStartOffset + (self.animTargetOffset - self.animStartOffset) * eased;
    table.contentOffset = CGPointMake(table.contentOffset.x, y);
}

- (void)finishScrollAnimation {
    [self.link invalidate];
    self.link = nil;

    if (self.scrubbing) return; // still under the finger: keep the indicator away
    [self restoreIndicatorIfNeeded];

    if (self.activeEntry >= 0) {
        if (self.keepActiveAfterScroll) {
            self.keepActiveAfterScroll = NO; // VoiceOver keeps its place marked
        } else {
            [self resetAppearanceAnimated:YES];
        }
    }
}

- (void)cancelScrollAnimation {
    [self.link invalidate];
    self.link = nil;
    [self restoreIndicatorIfNeeded];
    if (!self.scrubbing && self.activeEntry >= 0) [self resetAppearanceAnimated:YES];
}

- (void)hideIndicator {
    UITableView *table = self.tableView;
    if (!table) return;
    if (!self.indicatorHidden) {
        self.indicatorWasShown = table.showsVerticalScrollIndicator;
        self.indicatorHidden = YES;
    }
    table.showsVerticalScrollIndicator = NO;
}

- (void)restoreIndicatorIfNeeded {
    if (!self.indicatorHidden) return;
    self.tableView.showsVerticalScrollIndicator = self.indicatorWasShown;
    self.indicatorHidden = NO;
}

#pragma mark - Accessibility

- (CGRect)accessibilityFrame {
    if (!self.laidOut) return [super accessibilityFrame];
    CGRect rail = CGRectMake(self.stackLeft - 6.0, self.stackTop - 8.0,
                             RCSectionRailWidth + 12.0, self.stackHeight + 16.0);
    return UIAccessibilityConvertFrameToScreenCoordinates(rail, self);
}

- (NSString *)accessibilityValue {
    NSInteger entry = self.activeEntry;
    if (entry < 0 || entry >= (NSInteger)self.entries.count) return nil;
    NSInteger section = self.entries[entry].section + MAX(0, self.activeRow);
    if (section < 0 || section >= (NSInteger)self.titles.count) return nil;
    return self.titles[section];
}

- (void)accessibilityIncrement {
    [self accessibilityStep:1];
}

- (void)accessibilityDecrement {
    [self accessibilityStep:-1];
}

- (void)accessibilityStep:(NSInteger)step {
    NSInteger count = (NSInteger)self.entries.count;
    if (count == 0) return;
    // Nothing selected yet: the first step lands on the first entry
    NSInteger base = self.activeEntry >= 0 ? self.activeEntry : -1;
    NSInteger entry = MAX(0, MIN(count - 1, base + step));
    NSInteger section = self.entries[entry].section;

    self.keepActiveAfterScroll = YES;
    self.inBubble = NO;
    self.activeRow = 0;
    self.activeEntry = entry;
    [self updateGlyphColors];
    [self positionHighlightForEntry:entry];
    self.highlight.alpha = 1.0;
    [self updateBubbleForEntry:entry];
    [self animateToOffset:[self targetOffsetForSection:section] duration:0.3];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.titles[section]);
}

@end
