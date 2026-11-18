#ifndef RC_TWO_FINGER_GESTURES_H
#define RC_TWO_FINGER_GESTURES_H

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

// Screen-wide two-finger gesture recognizer driven by raw HID digitizer slots.
// Coordinates arriving here must already be scaled to upright portrait points
// (x * S, y * L) so distance and angle checks are aspect-ratio-correct.

typedef enum {
    RCTFOrientPortrait = 0,
    RCTFOrientPortraitUpsideDown = 1,
    RCTFOrientLandscapeLeft = 2,
    RCTFOrientLandscapeRight = 3,
} RCTFOrientation;

enum {
    RCTFMaskTap        = 1u << 0,
    RCTFMaskSwipeLeft  = 1u << 1,
    RCTFMaskSwipeRight = 1u << 2,
    RCTFMaskSwipeUp    = 1u << 3,
    RCTFMaskSwipeDown  = 1u << 4,
    RCTFMaskRotateCW   = 1u << 5,
    RCTFMaskRotateCCW  = 1u << 6,
    RCTFMaskBarTop     = 1u << 7,
    RCTFMaskBarBottom  = 1u << 8,
    RCTFMaskAnySwipe   = RCTFMaskSwipeLeft | RCTFMaskSwipeRight | RCTFMaskSwipeUp | RCTFMaskSwipeDown,
    RCTFMaskAnyRotate  = RCTFMaskRotateCW | RCTFMaskRotateCCW,
    RCTFMaskAnyTrigger = 0x7Fu,
};

typedef enum {
    RCTFTriggerNone = 0,
    RCTFTriggerTap,
    RCTFTriggerSwipeLeft,
    RCTFTriggerSwipeRight,
    RCTFTriggerSwipeUp,
    RCTFTriggerSwipeDown,
    RCTFTriggerRotateCW,
    RCTFTriggerRotateCCW,
} RCTFTrigger;

typedef enum {
    RCTFPhaseIdle = 0,
    RCTFPhaseOneDown,
    RCTFPhaseTwoTracking,
    RCTFPhaseTriggered,
    RCTFPhaseDisqualified,
} RCTFPhase;

typedef struct {
    double x;
    double y;
} RCTFPoint;

typedef struct {
    RCTFPhase phase;
    uint8_t slot[2];
    RCTFPoint startPt[2];
    RCTFPoint prevPt[2];
    double downTime[2];
    double liftTime[2];
    double maxMove[2];
    double startSep;
    double cumAngle;
    bool tapEligible;
    bool barTopPriority;
    bool barBottomPriority;
    RCTFOrientation orientation;
} RCTFState;

static inline void RCTFReset(RCTFState *s) {
    memset(s, 0, sizeof(*s));
    s->phase = RCTFPhaseIdle;
}

static inline void RCTFUserDelta(double dxPhys, double dyPhys, RCTFOrientation orient, double *outDX, double *outDY) {
    double ux = dxPhys, uy = dyPhys;
    if (orient == RCTFOrientPortraitUpsideDown) {
        ux = -dxPhys; uy = -dyPhys;
    } else if (orient == RCTFOrientLandscapeLeft) {
        ux = -dyPhys; uy = dxPhys;
    } else if (orient == RCTFOrientLandscapeRight) {
        ux = dyPhys; uy = -dxPhys;
    }
    if (outDX) *outDX = ux;
    if (outDY) *outDY = uy;
}

static inline int RCTFCountBits(uint32_t mask) {
    int count = 0;
    while (mask) {
        mask &= (mask - 1u);
        count++;
    }
    return count;
}

static inline RCTFPoint RCTFSlotPoint(const double *xs, const double *ys, uint8_t slot, double S, double L) {
    RCTFPoint p = { xs[slot] * S, ys[slot] * L };
    return p;
}

static inline double RCTFDist(RCTFPoint a, RCTFPoint b) {
    return hypot(b.x - a.x, b.y - a.y);
}

static inline uint32_t RCTFMaskBitForTrigger(RCTFTrigger trigger) {
    switch (trigger) {
        case RCTFTriggerTap:        return RCTFMaskTap;
        case RCTFTriggerSwipeLeft:  return RCTFMaskSwipeLeft;
        case RCTFTriggerSwipeRight: return RCTFMaskSwipeRight;
        case RCTFTriggerSwipeUp:    return RCTFMaskSwipeUp;
        case RCTFTriggerSwipeDown:  return RCTFMaskSwipeDown;
        case RCTFTriggerRotateCW:   return RCTFMaskRotateCW;
        case RCTFTriggerRotateCCW:  return RCTFMaskRotateCCW;
        default:                    return 0;
    }
}

// Evaluates one HID digitizer snapshot and returns a trigger once recognized.
// `barTopPriority` / `barBottomPriority` are computed by the caller when two
// fingers first settle so bar-specific 2-finger slides win in their zones.
static inline RCTFTrigger RCTFProcessFrame(
    RCTFState *s,
    uint32_t mask,
    const double *xs,
    const double *ys,
    double now,
    double S,
    double L,
    RCTFOrientation orientation,
    uint32_t configMask,
    bool barTopPriority,
    bool barBottomPriority
) {
    if (!(configMask & RCTFMaskAnyTrigger) || S <= 0 || L <= 0) {
        RCTFReset(s);
        return RCTFTriggerNone;
    }

    // Timing and geometry thresholds tuned against real multi-touch jitter,
    // fast two-thumb typing, resting-thumb scrolling, and pinch-to-zoom.
    const double kChordTapDownMax    = 0.095;
    const double kChordJoinMax       = 0.140;
    const double kChordTapLiftMax    = 0.095;
    const double kTapMaxDuration     = 0.280;
    const double kTapMaxMove         = 15.0;
    const double kOneDownMaxMove     = 20.0;
    const double kSwipeMinFingerMove = 28.0;
    const double kSwipeMinAvgMove    = 32.0;
    const double kSwipeAxisRatio     = 1.50;
    const double kSwipeMinCos        = 0.50;
    const double kSwipeMaxSepRatio   = 0.65;
    const double kSwipeMaxAngleRad   = 25.0 * M_PI / 180.0;
    const double kRotateMinSep       = 40.0;
    const double kRotateMinAngleRad  = 38.0 * M_PI / 180.0;
    const double kRotatePinchRatio   = 1.40;
    const double kRotateDriftRatio   = 0.65;

    int count = RCTFCountBits(mask);

    if (s->phase == RCTFPhaseTriggered || s->phase == RCTFPhaseDisqualified) {
        if (count == 0) RCTFReset(s);
        return RCTFTriggerNone;
    }

    if (count >= 3) {
        s->phase = RCTFPhaseDisqualified;
        return RCTFTriggerNone;
    }

    if (s->phase == RCTFPhaseIdle) {
        if (count == 0) return RCTFTriggerNone;
        if (count == 1) {
            uint8_t slot0 = (uint8_t)__builtin_ctz(mask);
            RCTFPoint p0 = RCTFSlotPoint(xs, ys, slot0, S, L);
            s->phase = RCTFPhaseOneDown;
            s->slot[0] = slot0;
            s->startPt[0] = p0;
            s->prevPt[0] = p0;
            s->downTime[0] = now;
            s->maxMove[0] = 0;
            return RCTFTriggerNone;
        }
        // count == 2 directly in the same HID report
        uint8_t s0 = (uint8_t)__builtin_ctz(mask);
        uint8_t s1 = (uint8_t)__builtin_ctz(mask & ~(1u << s0));
        RCTFPoint p0 = RCTFSlotPoint(xs, ys, s0, S, L);
        RCTFPoint p1 = RCTFSlotPoint(xs, ys, s1, S, L);
        s->phase = RCTFPhaseTwoTracking;
        s->slot[0] = s0; s->slot[1] = s1;
        s->startPt[0] = p0; s->startPt[1] = p1;
        s->prevPt[0] = p0; s->prevPt[1] = p1;
        s->downTime[0] = now; s->downTime[1] = now;
        s->liftTime[0] = 0; s->liftTime[1] = 0;
        s->maxMove[0] = 0; s->maxMove[1] = 0;
        s->startSep = RCTFDist(p0, p1);
        s->cumAngle = 0;
        s->tapEligible = true;
        s->barTopPriority = barTopPriority;
        s->barBottomPriority = barBottomPriority;
        s->orientation = orientation;
        return RCTFTriggerNone;
    }

    if (s->phase == RCTFPhaseOneDown) {
        if (count == 0) {
            RCTFReset(s);
            return RCTFTriggerNone;
        }
        if (count == 1) {
            uint8_t slot0 = (uint8_t)__builtin_ctz(mask);
            if (slot0 != s->slot[0]) {
                s->phase = RCTFPhaseDisqualified;
                return RCTFTriggerNone;
            }
            RCTFPoint p0 = RCTFSlotPoint(xs, ys, slot0, S, L);
            double mv = RCTFDist(s->startPt[0], p0);
            if (mv > s->maxMove[0]) s->maxMove[0] = mv;
            s->prevPt[0] = p0;
            // Once finger 1 rests or drags beyond the chord window, don't let
            // a later second finger (e.g., resting thumb + scroll) start a gesture.
            if ((now - s->downTime[0]) > kChordJoinMax || s->maxMove[0] > kOneDownMaxMove) {
                s->phase = RCTFPhaseDisqualified;
            }
            return RCTFTriggerNone;
        }
        // count == 2: second finger joined
        uint32_t bit0 = 1u << s->slot[0];
        if (!(mask & bit0)) {
            s->phase = RCTFPhaseDisqualified;
            return RCTFTriggerNone;
        }
        uint8_t s1 = (uint8_t)__builtin_ctz(mask & ~bit0);
        RCTFPoint p0 = RCTFSlotPoint(xs, ys, s->slot[0], S, L);
        RCTFPoint p1 = RCTFSlotPoint(xs, ys, s1, S, L);
        double mv0 = RCTFDist(s->startPt[0], p0);
        if (mv0 > s->maxMove[0]) s->maxMove[0] = mv0;
        if ((now - s->downTime[0]) > kChordJoinMax || s->maxMove[0] > kOneDownMaxMove) {
            s->phase = RCTFPhaseDisqualified;
            return RCTFTriggerNone;
        }
        s->phase = RCTFPhaseTwoTracking;
        s->slot[1] = s1;
        s->startPt[1] = p1;
        s->prevPt[0] = p0;
        s->prevPt[1] = p1;
        s->downTime[1] = now;
        s->liftTime[0] = 0; s->liftTime[1] = 0;
        s->maxMove[1] = 0;
        s->startSep = RCTFDist(p0, p1);
        s->cumAngle = 0;
        s->tapEligible = ((now - s->downTime[0]) <= kChordTapDownMax) && (s->maxMove[0] <= kTapMaxMove);
        s->barTopPriority = barTopPriority;
        s->barBottomPriority = barBottomPriority;
        s->orientation = orientation;
        return RCTFTriggerNone;
    }

    // RCTFPhaseTwoTracking
    uint32_t expectedMask = (1u << s->slot[0]) | (1u << s->slot[1]);
    if (mask & ~expectedMask) {
        s->phase = RCTFPhaseDisqualified;
        return RCTFTriggerNone;
    }

    bool down[2] = {
        (mask & (1u << s->slot[0])) != 0,
        (mask & (1u << s->slot[1])) != 0,
    };
    for (int i = 0; i < 2; i++) {
        // If a lifted slot returns before both fingers release, reject bounce/double-tap reuse.
        if (down[i] && s->liftTime[i] != 0) {
            s->phase = RCTFPhaseDisqualified;
            return RCTFTriggerNone;
        }
        if (!down[i] && s->liftTime[i] == 0) s->liftTime[i] = now;
    }

    double firstDown = s->downTime[0] < s->downTime[1] ? s->downTime[0] : s->downTime[1];

    if (down[0] && down[1]) {
        RCTFPoint p0 = RCTFSlotPoint(xs, ys, s->slot[0], S, L);
        RCTFPoint p1 = RCTFSlotPoint(xs, ys, s->slot[1], S, L);
        double d0x = p0.x - s->startPt[0].x, d0y = p0.y - s->startPt[0].y;
        double d1x = p1.x - s->startPt[1].x, d1y = p1.y - s->startPt[1].y;
        double m0 = hypot(d0x, d0y), m1 = hypot(d1x, d1y);
        if (m0 > s->maxMove[0]) s->maxMove[0] = m0;
        if (m1 > s->maxMove[1]) s->maxMove[1] = m1;
        if (s->maxMove[0] > kTapMaxMove || s->maxMove[1] > kTapMaxMove || (now - firstDown) > kTapMaxDuration) {
            s->tapEligible = false;
        }

        // Update unwrapped rotation angle only when fingers stay well separated
        // so micro-jitter on touching fingertips doesn't blow up atan2.
        double pvx = s->prevPt[1].x - s->prevPt[0].x;
        double pvy = s->prevPt[1].y - s->prevPt[0].y;
        double cvx = p1.x - p0.x;
        double cvy = p1.y - p0.y;
        double prevSep = hypot(pvx, pvy);
        double curSep = hypot(cvx, cvy);
        if (s->startSep >= kRotateMinSep && prevSep >= kRotateMinSep && curSep >= kRotateMinSep) {
            double cross = pvx * cvy - pvy * cvx;
            double dot = pvx * cvx + pvy * cvy;
            s->cumAngle += atan2(cross, dot);
        }
        s->prevPt[0] = p0;
        s->prevPt[1] = p1;

        // 1. Evaluate 2-Finger Rotate (CW / CCW)
        if (configMask & RCTFMaskAnyRotate) {
            double absAngle = fabs(s->cumAngle);
            if (absAngle >= kRotateMinAngleRad && s->startSep >= kRotateMinSep && curSep >= kRotateMinSep) {
                double avgSep = 0.5 * (s->startSep + curSep);
                double rotArc = 0.5 * avgSep * absAngle;
                double pinchDelta = fabs(curSep - s->startSep);
                double midDelta = hypot(0.5 * (d0x + d1x), 0.5 * (d0y + d1y));
                if (rotArc >= pinchDelta * kRotatePinchRatio && rotArc >= midDelta * kRotateDriftRatio) {
                    // In UIKit/HID y-down coords, positive cross product is clockwise on screen.
                    RCTFTrigger trig = (s->cumAngle > 0) ? RCTFTriggerRotateCW : RCTFTriggerRotateCCW;
                    if (configMask & RCTFMaskBitForTrigger(trig)) {
                        s->phase = RCTFPhaseTriggered;
                        return trig;
                    }
                }
            }
        }

        // 2. Evaluate 2-Finger Swipe (Left / Right / Up / Down)
        if (configMask & RCTFMaskAnySwipe) {
            if (m0 >= kSwipeMinFingerMove && m1 >= kSwipeMinFingerMove && fabs(s->cumAngle) < kSwipeMaxAngleRad) {
                double cosAngle = (d0x * d1x + d0y * d1y) / (m0 * m1);
                double avgMove = 0.5 * (m0 + m1);
                double sepDelta = fabs(curSep - s->startSep);
                if (cosAngle >= kSwipeMinCos && sepDelta <= kSwipeMaxSepRatio * avgMove) {
                    double userDX = 0, userDY = 0;
                    RCTFUserDelta(0.5 * (d0x + d1x), 0.5 * (d0y + d1y), s->orientation, &userDX, &userDY);
                    double ax = fabs(userDX), ay = fabs(userDY);
                    RCTFTrigger trig = RCTFTriggerNone;
                    if (ax >= kSwipeMinAvgMove && ax > ay * kSwipeAxisRatio) {
                        trig = (userDX > 0) ? RCTFTriggerSwipeRight : RCTFTriggerSwipeLeft;
                    } else if (ay >= kSwipeMinAvgMove && ay > ax * kSwipeAxisRatio) {
                        trig = (userDY > 0) ? RCTFTriggerSwipeDown : RCTFTriggerSwipeUp;
                    }
                    if (trig != RCTFTriggerNone) {
                        if ((trig == RCTFTriggerSwipeDown && s->barTopPriority) ||
                            (trig == RCTFTriggerSwipeUp && s->barBottomPriority)) {
                            s->phase = RCTFPhaseDisqualified;
                            return RCTFTriggerNone;
                        }
                        if (configMask & RCTFMaskBitForTrigger(trig)) {
                            s->phase = RCTFPhaseTriggered;
                            return trig;
                        }
                    }
                }
            }
        }
        return RCTFTriggerNone;
    }

    if (down[0] || down[1]) {
        int idx = down[0] ? 0 : 1;
        RCTFPoint p = RCTFSlotPoint(xs, ys, s->slot[idx], S, L);
        double mv = RCTFDist(s->startPt[idx], p);
        if (mv > s->maxMove[idx]) s->maxMove[idx] = mv;
        if (s->maxMove[idx] > kTapMaxMove || (now - firstDown) > kTapMaxDuration) {
            s->tapEligible = false;
        }
        if (!s->tapEligible) {
            s->phase = RCTFPhaseDisqualified;
        }
        return RCTFTriggerNone;
    }

    // Both fingers lifted cleanly
    RCTFTrigger result = RCTFTriggerNone;
    if ((configMask & RCTFMaskTap) && s->tapEligible) {
        double liftGap = fabs(s->liftTime[1] - s->liftTime[0]);
        if ((now - firstDown) <= kTapMaxDuration &&
            liftGap <= kChordTapLiftMax &&
            s->maxMove[0] <= kTapMaxMove &&
            s->maxMove[1] <= kTapMaxMove) {
            result = RCTFTriggerTap;
        }
    }
    RCTFReset(s);
    return result;
}

#endif
