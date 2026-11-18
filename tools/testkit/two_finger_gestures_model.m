// macOS: clang -fobjc-arc -framework Foundation tools/testkit/two_finger_gestures_model.m -o /tmp/rc-twofinger && /tmp/rc-twofinger
#include "../../Tweak/RCTwoFingerGestures.h"
#include <stdio.h>
#include <stdlib.h>

static const double kTestS = 390.0;
static const double kTestL = 844.0;

static void expect(bool cond, const char *msg) {
    if (!cond) {
        fprintf(stderr, "FAIL: %s\n", msg);
        exit(1);
    }
}

static RCTFTrigger step(RCTFState *s, uint32_t mask, const double *xs, const double *ys,
                        double now, RCTFOrientation orient, uint32_t cfg,
                        bool barTop, bool barBottom) {
    return RCTFProcessFrame(s, mask, xs, ys, now, kTestS, kTestL, orient, cfg, barTop, barBottom);
}

static void feedLiftAll(RCTFState *s, double now, uint32_t cfg) {
    double xs[32] = {0}, ys[32] = {0};
    step(s, 0, xs, ys, now, RCTFOrientPortrait, cfg, false, false);
}

int main(void) {
    double xs[32] = {0}, ys[32] = {0};
    RCTFState s;
    RCTFReset(&s);
    uint32_t allCfg = RCTFMaskAnyTrigger;

    // 1. Clean 2-finger tap (simultaneous down, slight lift stagger)
    xs[0] = 140.0 / kTestS; ys[0] = 400.0 / kTestL;
    xs[1] = 240.0 / kTestS; ys[1] = 400.0 / kTestL;
    expect(step(&s, 0x3, xs, ys, 1.000, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "tap down");
    expect(step(&s, 0x3, xs, ys, 1.040, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "tap hold");
    expect(step(&s, 0x2, xs, ys, 1.070, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "tap lift 0");
    expect(step(&s, 0x0, xs, ys, 1.095, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerTap, "tap fires on lift 1");

    // 2. Resting thumb (>140ms) followed by 2nd finger tap must NOT fire
    RCTFReset(&s);
    xs[0] = 30.0 / kTestS; ys[0] = 500.0 / kTestL;
    expect(step(&s, 0x1, xs, ys, 2.000, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "thumb down");
    xs[1] = 200.0 / kTestS; ys[1] = 400.0 / kTestL;
    expect(step(&s, 0x3, xs, ys, 2.200, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "late finger 2");
    expect(step(&s, 0x1, xs, ys, 2.260, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "late finger 2 lift");
    expect(step(&s, 0x0, xs, ys, 2.290, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "resting thumb never fires tap");

    // 3. Staggered 2-thumb typing (lift gap 120ms > 95ms) must NOT fire tap
    RCTFReset(&s);
    xs[0] = 100.0 / kTestS; ys[0] = 700.0 / kTestL;
    xs[1] = 280.0 / kTestS; ys[1] = 700.0 / kTestL;
    step(&s, 0x1, xs, ys, 3.000, RCTFOrientPortrait, allCfg, false, false);
    step(&s, 0x3, xs, ys, 3.040, RCTFOrientPortrait, allCfg, false, false);
    step(&s, 0x2, xs, ys, 3.060, RCTFOrientPortrait, allCfg, false, false);
    expect(step(&s, 0x0, xs, ys, 3.180, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "typing lift stagger rejected");

    // 4. Slot bounce / double tap before full release must NOT fire tap
    RCTFReset(&s);
    step(&s, 0x3, xs, ys, 4.000, RCTFOrientPortrait, allCfg, false, false);
    step(&s, 0x2, xs, ys, 4.040, RCTFOrientPortrait, allCfg, false, false);
    step(&s, 0x3, xs, ys, 4.070, RCTFOrientPortrait, allCfg, false, false);
    expect(step(&s, 0x0, xs, ys, 4.100, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "bounce slot reuse rejected");

    // 5. Three fingers must disqualify entire session until 0 fingers
    RCTFReset(&s);
    step(&s, 0x3, xs, ys, 5.000, RCTFOrientPortrait, allCfg, false, false);
    xs[2] = 180.0 / kTestS; ys[2] = 300.0 / kTestL;
    step(&s, 0x7, xs, ys, 5.020, RCTFOrientPortrait, allCfg, false, false);
    step(&s, 0x3, xs, ys, 5.040, RCTFOrientPortrait, allCfg, false, false);
    expect(step(&s, 0x0, xs, ys, 5.060, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "3 fingers disqualified");

    // 6. Portrait 2-finger swipes (L/R/U/D)
    struct { double dx; double dy; RCTFOrientation orient; RCTFTrigger expected; const char *name; } swipes[] = {
        { -45,   0, RCTFOrientPortrait,           RCTFTriggerSwipeLeft,  "portrait swipe left" },
        {  45,   0, RCTFOrientPortrait,           RCTFTriggerSwipeRight, "portrait swipe right" },
        {   0, -45, RCTFOrientPortrait,           RCTFTriggerSwipeUp,    "portrait swipe up" },
        {   0,  45, RCTFOrientPortrait,           RCTFTriggerSwipeDown,  "portrait swipe down" },
        {  45,   0, RCTFOrientPortraitUpsideDown, RCTFTriggerSwipeLeft,  "upsidedown swipe left" },
        {   0, -45, RCTFOrientLandscapeLeft,      RCTFTriggerSwipeRight, "landscapeLeft swipe right" },
        {  45,   0, RCTFOrientLandscapeLeft,      RCTFTriggerSwipeDown,  "landscapeLeft swipe down" },
        {   0, -45, RCTFOrientLandscapeRight,     RCTFTriggerSwipeLeft,  "landscapeRight swipe left" },
        {  45,   0, RCTFOrientLandscapeRight,     RCTFTriggerSwipeUp,    "landscapeRight swipe up" },
    };
    for (size_t i = 0; i < sizeof(swipes) / sizeof(swipes[0]); i++) {
        RCTFReset(&s);
        xs[0] = 150.0 / kTestS; ys[0] = 400.0 / kTestL;
        xs[1] = 230.0 / kTestS; ys[1] = 400.0 / kTestL;
        double t = 10.0 + (double)i;
        step(&s, 0x3, xs, ys, t, swipes[i].orient, allCfg, false, false);
        xs[0] += swipes[i].dx / kTestS; ys[0] += swipes[i].dy / kTestL;
        xs[1] += swipes[i].dx / kTestS; ys[1] += swipes[i].dy / kTestL;
        RCTFTrigger got = step(&s, 0x3, xs, ys, t + 0.08, swipes[i].orient, allCfg, false, false);
        expect(got == swipes[i].expected, swipes[i].name);
        // Must not fire again before lifting
        xs[0] += swipes[i].dx / kTestS; ys[0] += swipes[i].dy / kTestL;
        xs[1] += swipes[i].dx / kTestS; ys[1] += swipes[i].dy / kTestL;
        expect(step(&s, 0x3, xs, ys, t + 0.14, swipes[i].orient, allCfg, false, false) == RCTFTriggerNone, "no repeat before lift");
        feedLiftAll(&s, t + 0.18, allCfg);
    }

    // 7. Resting-thumb + 1-finger swipe must NOT fire
    RCTFReset(&s);
    xs[0] = 100.0 / kTestS; ys[0] = 400.0 / kTestL;
    xs[1] = 220.0 / kTestS; ys[1] = 400.0 / kTestL;
    step(&s, 0x3, xs, ys, 20.0, RCTFOrientPortrait, allCfg, false, false);
    xs[1] += 60.0 / kTestS;
    expect(step(&s, 0x3, xs, ys, 20.08, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "one stationary + one swipe rejected");

    // 8. Bar priority suppresses matching bar-direction swipe, allows perpendicular
    RCTFReset(&s);
    xs[0] = 150.0 / kTestS; ys[0] = 40.0 / kTestL;
    xs[1] = 230.0 / kTestS; ys[1] = 40.0 / kTestL;
    step(&s, 0x3, xs, ys, 21.0, RCTFOrientPortrait, allCfg | RCTFMaskBarTop, true, false);
    ys[0] += 50.0 / kTestL; ys[1] += 50.0 / kTestL;
    expect(step(&s, 0x3, xs, ys, 21.08, RCTFOrientPortrait, allCfg | RCTFMaskBarTop, true, false) == RCTFTriggerNone, "top bar priority suppresses general swipe down");

    // 9. Pinch-to-zoom (even with 35 deg drift) must NOT fire swipe or rotate
    RCTFReset(&s);
    xs[0] = 160.0 / kTestS; ys[0] = 400.0 / kTestL;
    xs[1] = 230.0 / kTestS; ys[1] = 400.0 / kTestL; // sep = 70
    step(&s, 0x3, xs, ys, 22.0, RCTFOrientPortrait, allCfg, false, false);
    // Spread to sep=210 (pinchDelta = 140) while rotating 40 deg
    double cx = 195.0, cy = 400.0, r2 = 105.0, ang = 40.0 * M_PI / 180.0;
    xs[0] = (cx - r2 * cos(ang)) / kTestS; ys[0] = (cy - r2 * sin(ang)) / kTestL;
    xs[1] = (cx + r2 * cos(ang)) / kTestS; ys[1] = (cy + r2 * sin(ang)) / kTestL;
    expect(step(&s, 0x3, xs, ys, 22.10, RCTFOrientPortrait, allCfg, false, false) == RCTFTriggerNone, "sloppy pinch rejected");

    // 10. Clean 2-finger CW rotation across multiple steps (and crossing +/- pi boundary)
    RCTFReset(&s);
    double r = 70.0;
    double a0 = 165.0 * M_PI / 180.0; // starts near +pi
    xs[0] = (cx - r * cos(a0)) / kTestS; ys[0] = (cy - r * sin(a0)) / kTestL;
    xs[1] = (cx + r * cos(a0)) / kTestS; ys[1] = (cy + r * sin(a0)) / kTestL;
    step(&s, 0x3, xs, ys, 23.00, RCTFOrientPortrait, allCfg, false, false);
    RCTFTrigger rotCW = RCTFTriggerNone;
    for (int k = 1; k <= 5; k++) {
        double a = a0 + k * (10.0 * M_PI / 180.0); // crosses +180 -> -145
        xs[0] = (cx - r * cos(a)) / kTestS; ys[0] = (cy - r * sin(a)) / kTestL;
        xs[1] = (cx + r * cos(a)) / kTestS; ys[1] = (cy + r * sin(a)) / kTestL;
        rotCW = step(&s, 0x3, xs, ys, 23.00 + k * 0.02, RCTFOrientPortrait, allCfg, false, false);
        if (rotCW != RCTFTriggerNone) break;
    }
    expect(rotCW == RCTFTriggerRotateCW, "CW rotation across pi boundary");

    // 11. Clean 2-finger CCW rotation (one-finger anchored orbit)
    RCTFReset(&s);
    xs[0] = 150.0 / kTestS; ys[0] = 400.0 / kTestL;
    xs[1] = 270.0 / kTestS; ys[1] = 400.0 / kTestL; // radius 120 around finger 0
    step(&s, 0x3, xs, ys, 24.00, RCTFOrientPortrait, allCfg, false, false);
    RCTFTrigger rotCCW = RCTFTriggerNone;
    for (int k = 1; k <= 5; k++) {
        double a = -k * (10.0 * M_PI / 180.0);
        xs[1] = (150.0 + 120.0 * cos(a)) / kTestS;
        ys[1] = (400.0 + 120.0 * sin(a)) / kTestL;
        rotCCW = step(&s, 0x3, xs, ys, 24.00 + k * 0.02, RCTFOrientPortrait, allCfg, false, false);
        if (rotCCW != RCTFTriggerNone) break;
    }
    expect(rotCCW == RCTFTriggerRotateCCW, "CCW anchored rotation");

    // 12. Disabled trigger bit is ignored
    RCTFReset(&s);
    xs[0] = 150.0 / kTestS; ys[0] = 400.0 / kTestL;
    xs[1] = 230.0 / kTestS; ys[1] = 400.0 / kTestL;
    step(&s, 0x3, xs, ys, 25.00, RCTFOrientPortrait, RCTFMaskSwipeRight, false, false);
    xs[0] -= 50.0 / kTestS; xs[1] -= 50.0 / kTestS;
    expect(step(&s, 0x3, xs, ys, 25.08, RCTFOrientPortrait, RCTFMaskSwipeRight, false, false) == RCTFTriggerNone, "unconfigured swipe left ignored");

    puts("PASS: two-finger gesture model");
    return 0;
}
