#import "RCSectionCardView.h"

// The layer changes below are made on long-lived layers, and Core Animation
// would otherwise fade them on its own (0.25s) whenever they happen outside a
// UIView animation block. The cards used to be thrown away and rebuilt for
// every row, so they never showed that fade: turn it off to keep the look the
// same when a reused card has its colours or shape changed.
static void RCSectionCardWithoutLayerAnimation(dispatch_block_t changes) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    changes();
    [CATransaction commit];
}

@implementation RCSectionCardView {
    CAShapeLayer *_fillLayer;
    CAShapeLayer *_borderLayer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _borderWidth = 1.0;
    _cornerRadius = 12.0;
    _position = RCSectionCardPositionMiddle;

    // The card itself is invisible: everything is drawn by the two layers, so
    // the transparent parts show what is behind the card.
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;

    _fillLayer = [CAShapeLayer layer];
    _fillLayer.fillColor = [UIColor clearColor].CGColor;
    _fillLayer.strokeColor = [UIColor clearColor].CGColor;
    [self.layer addSublayer:_fillLayer];

    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = [UIColor clearColor].CGColor;
    _borderLayer.strokeColor = [UIColor clearColor].CGColor;
    _borderLayer.lineWidth = _borderWidth;
    [self.layer addSublayer:_borderLayer];
}

#pragma mark - Properties

- (void)setFillColor:(UIColor *)fillColor {
    _fillColor = fillColor;
    UIColor *color = fillColor ?: [UIColor clearColor];
    RCSectionCardWithoutLayerAnimation(^{
        self->_fillLayer.fillColor = color.CGColor;
    });
}

- (void)setBorderColor:(UIColor *)borderColor {
    _borderColor = borderColor;
    UIColor *color = borderColor ?: [UIColor clearColor];
    RCSectionCardWithoutLayerAnimation(^{
        self->_borderLayer.strokeColor = color.CGColor;
    });
}

- (void)setBorderWidth:(CGFloat)borderWidth {
    _borderWidth = borderWidth;
    [self setNeedsLayout];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    [self setNeedsLayout];
}

- (void)setPosition:(RCSectionCardPosition)position {
    _position = position;
    [self setNeedsLayout];
}

- (void)configureWithFillColor:(UIColor *)fillColor
                   borderColor:(UIColor *)borderColor
                   borderWidth:(CGFloat)borderWidth
                  cornerRadius:(CGFloat)cornerRadius
                      position:(RCSectionCardPosition)position {
    self.fillColor = fillColor;
    self.borderColor = borderColor;
    self.borderWidth = borderWidth;
    self.cornerRadius = cornerRadius;
    self.position = position;
    // Draw for the bounds we already have, so a cell being configured for the
    // screen is correct before the next layout pass.
    [self rebuildLayers];
}

#pragma mark - Layout

// A rotation changes the cell's width, which changes this view's bounds. The
// layers are rebuilt here so the card follows without a table reload.
- (void)layoutSubviews {
    [super layoutSubviews];
    [self rebuildLayers];
}

- (void)rebuildLayers {
    RCSectionCardWithoutLayerAnimation(^{
        [self buildLayersForCurrentBounds];
    });
}

- (void)buildLayersForCurrentBounds {
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    CGFloat lineWidth = MAX(0.0, _borderWidth);

    _fillLayer.frame = bounds;
    _borderLayer.frame = bounds;
    _borderLayer.lineWidth = lineWidth;

    // Nothing useful to draw yet (a cell with no size); the next layout pass
    // calls this again with real bounds.
    if (width <= 0.0 || height <= 0.0) {
        _fillLayer.path = nil;
        _borderLayer.path = nil;
        return;
    }

    // The border is stroked centred on its path, so the path is pulled in by
    // half a line: the outer half of the stroke then sits exactly on the fill's
    // edge and the whole line stays inside the card.
    CGRect borderRect = CGRectInset(bounds, lineWidth * 0.5, lineWidth * 0.5);

    _fillLayer.path = [self pathForRect:bounds].CGPath;

    if (CGRectGetWidth(borderRect) <= 0.0 || CGRectGetHeight(borderRect) <= 0.0) {
        _borderLayer.path = nil;
        return;
    }
    _borderLayer.path = [self pathForRect:borderRect].CGPath;
    [self updateBorderMaskInBounds:bounds lineWidth:lineWidth];
}

- (UIBezierPath *)pathForRect:(CGRect)rect {
    CGFloat radius = _cornerRadius;
    switch (_position) {
        case RCSectionCardPositionSingle:
            return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
        case RCSectionCardPositionFirst:
            return [UIBezierPath bezierPathWithRoundedRect:rect
                                         byRoundingCorners:(UIRectCornerTopLeft | UIRectCornerTopRight)
                                               cornerRadii:CGSizeMake(radius, radius)];
        case RCSectionCardPositionLast:
            return [UIBezierPath bezierPathWithRoundedRect:rect
                                         byRoundingCorners:(UIRectCornerBottomLeft | UIRectCornerBottomRight)
                                               cornerRadii:CGSizeMake(radius, radius)];
        case RCSectionCardPositionMiddle:
        default:
            return [UIBezierPath bezierPathWithRect:rect];
    }
}

// Rows in a run share their touching edges, so the line between them is hidden:
// the top row loses its bottom line, the bottom row its top line, and a row in
// between loses both. A single row keeps its full border.
- (void)updateBorderMaskInBounds:(CGRect)bounds lineWidth:(CGFloat)lineWidth {
    if (_position == RCSectionCardPositionSingle || lineWidth <= 0.0) {
        _borderLayer.mask = nil;
        return;
    }

    CGRect maskRect = bounds;
    switch (_position) {
        case RCSectionCardPositionFirst:
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
            break;
        case RCSectionCardPositionLast:
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
            break;
        case RCSectionCardPositionMiddle:
        default:
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - (2.0 * lineWidth));
            break;
    }

    CAShapeLayer *maskLayer = (CAShapeLayer *)_borderLayer.mask;
    if (![maskLayer isKindOfClass:[CAShapeLayer class]]) {
        maskLayer = [CAShapeLayer layer];
        _borderLayer.mask = maskLayer;
    }
    maskLayer.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
}

@end
