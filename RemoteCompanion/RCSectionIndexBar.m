#import "RCSectionIndexBar.h"
#import <QuartzCore/QuartzCore.h>

// The rail lives in the margin left of the inset-grouped cards (20 pt on a
// phone), so its letters never sit on a row. The capsule and the naming bubble
// only appear under a finger.
static const CGFloat RCSectionRailWidth = 20.0;
static const CGFloat RCSectionRailMinRow = 8.0;
static const CGFloat RCSectionRailMaxRow = 18.0;
static const CGFloat RCSectionCapsuleOutset = 2.0;
static const CGFloat RCSectionBubbleHeight = 42.0;
static const CGFloat RCSectionBubbleGap = 8.0;

#pragma mark - Short names

// "Volume Buttons" -> VB, "Notifications" -> N. Two letters at most; a clash
// falls back to the first two letters of the first word ("App Long Press" ->
// AP beside "App Launch" -> AL), so the rail stays even.
static NSArray<NSString *> *RCSectionIndexWords(NSString *title) {
    NSCharacterSet *notLetters = [[NSCharacterSet letterCharacterSet] invertedSet];
    NSArray *parts = [title componentsSeparatedByCharactersInSet:notLetters];
    NSSet *skip = [NSSet setWithArray:@[@"of", @"and", @"the", @"on", @"to", @"for", @"with", @"a", @"an", @"trigger", @"triggers"]];
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length == 0) continue;
        if ([skip containsObject:[part lowercaseString]]) continue;
        [words addObject:part];
    }
    return words;
}

static NSString *RCSectionIndexCode(NSString *title, NSMutableSet<NSString *> *used) {
    NSArray<NSString *> *words = RCSectionIndexWords(title);
    if (words.count == 0) return @"•";

    NSString *first = words[0];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (words.count >= 2) {
        [candidates addObject:[NSString stringWithFormat:@"%@%@",
                               [first substringToIndex:1],
                               [words[1] substringToIndex:1]]];
    } else {
        [candidates addObject:[first substringToIndex:1]];
    }
    if (first.length >= 2) [candidates addObject:[first substringToIndex:2]];
    if (words.count >= 2 && first.length >= 2) {
        [candidates addObject:[NSString stringWithFormat:@"%@%@",
                               [first substringToIndex:2],
                               [words[1] substringToIndex:1]]];
    }
    if (first.length >= 3) [candidates addObject:[first substringToIndex:3]];
    if (words.count >= 2 && words[1].length >= 2) {
        [candidates addObject:[NSString stringWithFormat:@"%@%@",
                               [first substringToIndex:1],
                               [words[1] substringToIndex:2]]];
    }

    for (NSString *candidate in candidates) {
        NSString *code = [candidate uppercaseString];
        if (![used containsObject:code]) {
            [used addObject:code];
            return code;
        }
    }

    // Two sections with the same initials and no longer form to tell apart:
    // a number is better than two identical ticks.
    NSString *base = [candidates.firstObject uppercaseString];
    for (NSInteger i = 2; ; i++) {
        NSString *code = [NSString stringWithFormat:@"%@%ld", base, (long)i];
        if (![used containsObject:code]) {
            [used addObject:code];
            return code;
        }
    }
}

#pragma mark - Bar

@interface RCSectionIndexBar ()
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy) NSArray *icons;
@property (nonatomic, strong) NSMutableArray<UILabel *> *letters;
@property (nonatomic, strong) UIView *lettersView;
@property (nonatomic, strong) UIView *capsule;
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIImageView *bubbleIcon;
@property (nonatomic, strong) UILabel *bubbleLabel;
@property (nonatomic, strong) UISelectionFeedbackGenerator *haptics;
@property (nonatomic, assign) NSInteger activeIndex;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) BOOL shown;
@property (nonatomic, assign) BOOL laidOut;
@property (nonatomic, assign) BOOL keepActiveAfterScroll;
@property (nonatomic, assign) CGFloat rowHeight;
@property (nonatomic, assign) CGFloat railTop;
@property (nonatomic, assign) CGFloat railLeft;
@property (nonatomic, assign) CGFloat railHeight;
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
        _letters = [NSMutableArray array];
        _activeIndex = -1;
        _haptics = [[UISelectionFeedbackGenerator alloc] init];

        _capsule = [[UIView alloc] initWithFrame:CGRectZero];
        _capsule.layer.cornerRadius = 12.0;
        _capsule.alpha = 0.0;
        _capsule.userInteractionEnabled = NO;
        [self addSubview:_capsule];

        _lettersView = [[UIView alloc] initWithFrame:CGRectZero];
        _lettersView.backgroundColor = [UIColor clearColor];
        _lettersView.userInteractionEnabled = NO;
        [self addSubview:_lettersView];

        _bubble = [[UIView alloc] initWithFrame:CGRectZero];
        _bubble.layer.cornerRadius = 12.0;
        _bubble.layer.borderWidth = 0.5;
        _bubble.alpha = 0.0;
        _bubble.userInteractionEnabled = NO;
        [self addSubview:_bubble];

        _bubbleIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _bubbleIcon.contentMode = UIViewContentModeScaleAspectFit;
        [_bubble addSubview:_bubbleIcon];

        _bubbleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _bubbleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _bubbleLabel.numberOfLines = 1;
        _bubbleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_bubble addSubview:_bubbleLabel];

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
    self.capsule.backgroundColor = card;
    self.bubble.backgroundColor = card;
    self.bubble.layer.borderColor = [[UIColor separatorColor] colorWithAlphaComponent:0.8].CGColor;
    self.bubbleLabel.textColor = [UIColor labelColor];
    self.bubbleIcon.tintColor = [UIColor secondaryLabelColor];
    for (NSUInteger i = 0; i < self.letters.count; i++) {
        UILabel *label = self.letters[i];
        label.textColor = ((NSInteger)i == self.activeIndex) ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    }
}

#pragma mark - Data

- (void)setSectionTitles:(NSArray<NSString *> *)titles icons:(NSArray *)icons {
    self.titles = titles ?: @[];
    self.icons = icons ?: @[];

    for (UILabel *label in self.letters) [label removeFromSuperview];
    [self.letters removeAllObjects];
    self.activeIndex = -1;

    NSMutableSet<NSString *> *used = [NSMutableSet set];
    UIFont *font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];

    for (NSString *title in self.titles) {
        NSString *code = RCSectionIndexCode(title, used);
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = code;
        label.font = font;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor secondaryLabelColor];
        label.userInteractionEnabled = NO;
        [self.lettersView addSubview:label];
        [self.letters addObject:label];
    }

    self.hidden = !self.shown;
    self.userInteractionEnabled = self.shown && self.letters.count > 1;
    if (self.host) [self layoutInView:self.host];
    [self setNeedsLayout];
}

- (void)layoutInView:(UIView *)host {
    if (!host) return;
    self.host = host;
    // The chrome moves as the large title collapses: never shift the codes
    // under a finger that is already on them
    if (self.scrubbing) return;
    self.frame = CGRectMake(0, 0, host.bounds.size.width, host.bounds.size.height);
    self.lettersView.frame = self.bounds;
    self.laidOut = YES;

    UIEdgeInsets safe = host.safeAreaInsets;
    NSUInteger count = self.letters.count;
    if (count == 0) {
        self.capsule.frame = CGRectZero;
        return;
    }

    CGFloat chromeTop = (self.topChrome > 0 ? self.topChrome : safe.top + 144.0) + 10.0;
    CGFloat bottomBound = host.bounds.size.height - safe.bottom - 12.0;
    CGFloat available = MAX(120.0, bottomBound - chromeTop);
    CGFloat row = MIN(RCSectionRailMaxRow, MAX(RCSectionRailMinRow, available / (CGFloat)count));
    if (row * (CGFloat)count > available + 1.0) {
        row = MAX(1.0, available / (CGFloat)count); // landscape with a long list
    }
    CGFloat height = row * (CGFloat)count;
    CGFloat top = chromeTop; // the first code lines up with the first section
    CGFloat left = safe.left;

    self.rowHeight = row;
    self.railTop = top;
    self.railLeft = left;
    self.railHeight = height;

    UIFont *font = [UIFont systemFontOfSize:MIN(10.5, MAX(7.0, row - 2.0)) weight:UIFontWeightSemibold];
    for (NSUInteger i = 0; i < count; i++) {
        UILabel *label = self.letters[i];
        label.font = font;
        label.frame = CGRectMake(left, top + row * (CGFloat)i, RCSectionRailWidth, row);
    }
    self.capsule.frame = CGRectMake(left - RCSectionCapsuleOutset,
                                    top - 8.0,
                                    RCSectionRailWidth + RCSectionCapsuleOutset * 2.0,
                                    height + 16.0);
    self.capsule.layer.cornerRadius = MIN(12.0, self.capsule.bounds.size.height / 2.0);

    if (self.activeIndex >= 0) [self positionBubbleForIndex:self.activeIndex];
}

#pragma mark - Showing

- (void)setShown:(BOOL)shown animated:(BOOL)animated {
    if (shown == _shown) {
        self.userInteractionEnabled = shown && self.letters.count > 1;
        return;
    }
    _shown = shown;
    self.userInteractionEnabled = shown && self.letters.count > 1;
    if (!shown) {
        [self cancelScrollAnimation];
        [self finishScrubAppearance];
        self.scrubbing = NO;
        self.activeIndex = -1;
        [self updateLetterStylesAnimated:NO];
    }

    if (shown) self.hidden = NO;
    void (^changes)(void) = ^{ self.alpha = shown ? 1.0 : 0.0; };
    if (animated) {
        [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:changes
                         completion:^(BOOL finished) { if (!shown) self.hidden = YES; }];
    } else {
        changes();
        self.hidden = !shown;
    }
}

#pragma mark - Touch

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.shown || self.letters.count < 2 || !self.laidOut) return NO;
    // A little wider than the letters, like the system index, but never far
    // enough right to cover a row's icon.
    CGFloat right = self.railLeft + RCSectionRailWidth + 12.0;
    CGFloat top = self.railTop - 12.0;
    CGFloat bottom = self.railTop + self.railHeight + 12.0;
    return point.x >= 0 && point.x <= right && point.y >= top && point.y <= bottom;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.letters.count < 2) return;
    CGPoint point = [touches.anyObject locationInView:self];
    [self beginScrubAtY:point.y];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.scrubbing) return;
    CGPoint point = [touches.anyObject locationInView:self];
    [self updateScrubAtY:point.y];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endScrub];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endScrub];
}

- (NSInteger)indexForY:(CGFloat)y {
    if (self.rowHeight <= 0) return 0;
    NSInteger index = (NSInteger)floor((y - self.railTop) / self.rowHeight);
    return MAX(0, MIN((NSInteger)self.letters.count - 1, index));
}

- (void)beginScrubAtY:(CGFloat)y {
    self.scrubbing = YES;
    self.keepActiveAfterScroll = NO;
    [self.haptics prepare];
    [self showCapsule];
    [self selectIndex:[self indexForY:y] animated:YES];
    [self showBubble];
    [self hideIndicator];
}

- (void)updateScrubAtY:(CGFloat)y {
    NSInteger index = [self indexForY:y];
    if (index != self.activeIndex) {
        [self selectIndex:index animated:YES];
    }
}

- (void)selectIndex:(NSInteger)index animated:(BOOL)animated {
    if (index < 0 || index >= (NSInteger)self.titles.count) return;
    BOOL changed = (index != self.activeIndex);
    self.activeIndex = index;

    if (changed) {
        [self.haptics selectionChanged];
        [self updateLetterStylesAnimated:animated];
        [self updateBubbleContent];
        [self positionBubbleForIndex:index];
    }

    CGFloat target = [self targetOffsetForSection:index];
    [self animateToOffset:target duration:(self.scrubbing ? 0.16 : 0.32)];
}

- (void)endScrub {
    if (!self.scrubbing) return;
    self.scrubbing = NO;
    [self finishScrubAppearance];

    NSInteger index = self.activeIndex;
    if (index < 0) return;
    [self animateToOffset:[self targetOffsetForSection:index] duration:0.32];
}

- (void)showCapsule {
    self.capsule.transform = CGAffineTransformMakeScale(0.94, 0.94);
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.capsule.alpha = 1.0;
        self.capsule.transform = CGAffineTransformIdentity;
    } completion:nil];
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

- (void)finishScrubAppearance {
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.capsule.alpha = 0.0;
        self.bubble.alpha = 0.0;
    } completion:nil];
}

#pragma mark - Bubble

- (void)updateLetterStylesAnimated:(BOOL)animated {
    for (NSUInteger i = 0; i < self.letters.count; i++) {
        UILabel *label = self.letters[i];
        BOOL active = ((NSInteger)i == self.activeIndex);
        UIColor *color = active ? [UIColor labelColor] : [UIColor secondaryLabelColor];
        CGFloat scale = active ? 1.16 : 1.0;
        if (animated) {
            [UIView animateWithDuration:0.13 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                             animations:^{
                label.transform = CGAffineTransformMakeScale(scale, scale);
            } completion:nil];
        } else {
            label.transform = CGAffineTransformMakeScale(scale, scale);
        }
        label.textColor = color;
    }
}

- (void)updateBubbleContent {
    if (!self.host) return;
    if (self.activeIndex < 0 || self.activeIndex >= (NSInteger)self.titles.count) return;
    NSString *title = self.titles[self.activeIndex];
    id icon = (self.activeIndex < (NSInteger)self.icons.count) ? self.icons[self.activeIndex] : nil;
    UIImage *image = [icon isKindOfClass:[UIImage class]] ? icon : nil;

    self.bubbleLabel.text = title;
    self.bubbleIcon.image = image;
    self.bubbleIcon.hidden = (image == nil);

    UIEdgeInsets safe = self.host.safeAreaInsets;
    CGFloat left = self.railLeft + RCSectionRailWidth + RCSectionBubbleGap;
    CGFloat iconRoom = image ? (16.0 + 7.0) : 0.0;
    CGFloat maxText = MAX(60.0, self.bounds.size.width - left - safe.right - 8.0 - 24.0 - iconRoom);
    CGSize textSize = [title boundingRectWithSize:CGSizeMake(maxText, 22.0)
                                          options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                                       attributes:@{NSFontAttributeName: self.bubbleLabel.font}
                                          context:nil].size;
    CGFloat textWidth = ceil(MIN(textSize.width, maxText));
    CGFloat width = 12.0 + iconRoom + textWidth + 12.0;

    CGRect frame = self.bubble.frame;
    frame.size = CGSizeMake(width, RCSectionBubbleHeight);
    self.bubble.frame = frame;

    CGFloat x = 12.0;
    if (image) {
        self.bubbleIcon.frame = CGRectMake(12.0, (RCSectionBubbleHeight - 16.0) / 2.0, 16.0, 16.0);
        x += iconRoom;
    } else {
        self.bubbleIcon.frame = CGRectZero;
    }
    self.bubbleLabel.frame = CGRectMake(x, 0, textWidth, RCSectionBubbleHeight);
    [self positionBubbleForIndex:self.activeIndex];
}

- (void)positionBubbleForIndex:(NSInteger)index {
    if (!self.host || index < 0) return;
    UIEdgeInsets safe = self.host.safeAreaInsets;
    CGFloat centerY = self.railTop + self.rowHeight * ((CGFloat)index + 0.5);
    CGFloat half = self.bubble.bounds.size.height / 2.0;
    centerY = MAX(safe.top + half + 8.0, MIN(self.bounds.size.height - safe.bottom - half - 8.0, centerY));

    CGFloat x = self.railLeft + RCSectionRailWidth + RCSectionBubbleGap;
    CGFloat maxX = self.bounds.size.width - safe.right - 8.0 - self.bubble.bounds.size.width;
    x = MIN(x, maxX);

    CGRect frame = self.bubble.frame;
    frame.origin = CGPointMake(x, centerY - half);
    self.bubble.frame = frame;
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

    if (self.activeIndex >= 0 && !self.keepActiveAfterScroll) {
        NSInteger index = self.activeIndex;
        self.activeIndex = -1;
        for (NSUInteger i = 0; i < self.letters.count; i++) {
            UILabel *label = self.letters[i];
            [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                             animations:^{
                label.transform = CGAffineTransformIdentity;
            } completion:nil];
            if ((NSInteger)i == index) label.textColor = [UIColor secondaryLabelColor];
        }
    }
}

- (void)cancelScrollAnimation {
    [self.link invalidate];
    self.link = nil;
    [self restoreIndicatorIfNeeded];
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
    CGRect rail = CGRectMake(self.railLeft - 6.0, self.railTop - 8.0,
                             RCSectionRailWidth + 12.0, self.railHeight + 16.0);
    return UIAccessibilityConvertFrameToScreenCoordinates(rail, self);
}

- (NSString *)accessibilityValue {
    NSInteger index = self.activeIndex;
    if (index < 0 || index >= (NSInteger)self.titles.count) return nil;
    return self.titles[index];
}

- (void)accessibilityIncrement {
    [self accessibilityStep:1];
}

- (void)accessibilityDecrement {
    [self accessibilityStep:-1];
}

- (void)accessibilityStep:(NSInteger)step {
    NSInteger count = (NSInteger)self.titles.count;
    if (count == 0) return;
    NSInteger base = self.activeIndex >= 0 ? self.activeIndex : 0;
    NSInteger index = MAX(0, MIN(count - 1, base + step));
    self.keepActiveAfterScroll = YES;
    self.activeIndex = index;
    [self updateLetterStylesAnimated:NO];
    [self updateBubbleContent];
    [self animateToOffset:[self targetOffsetForSection:index] duration:0.3];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.titles[index]);
}

@end
