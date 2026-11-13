#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RCTimerActionType) {
    RCTimerActionStart = 0,
    RCTimerActionStop,
    RCTimerActionPause,
    RCTimerActionResume,
    RCTimerActionStatus
};

// Native Apple Clock timer action (MobileTimer.framework).
// Stored as a single command string:
//   timer 20m
//   timer 20m --label "Nap"
//   timer stop | pause | resume | status [--label "Nap"]
@interface RCTimerCommand : NSObject

@property (nonatomic, assign) RCTimerActionType action;
@property (nonatomic, copy, nullable) NSString *durationExpression;
@property (nonatomic, copy, nullable) NSString *label;
@property (nonatomic, copy, nullable) NSString *parseError;

+ (BOOL)isTimerCommand:(nullable NSString *)command;
+ (nullable instancetype)commandWithString:(nullable NSString *)command;
+ (double)parseDurationSeconds:(nullable NSString *)expr;
+ (BOOL)containsVariable:(nullable NSString *)expr;
+ (NSString *)compactTokenForSeconds:(NSInteger)seconds;
+ (NSString *)displayDurationForSeconds:(double)seconds;

- (instancetype)initWithAction:(RCTimerActionType)action
            durationExpression:(nullable NSString *)durationExpression
                         label:(nullable NSString *)label;

- (NSString *)string;
- (NSString *)displayDuration;
- (NSString *)actionTitle;
- (nullable NSString *)actionAccentText;
- (nullable NSString *)actionDetailText;
- (NSString *)singleLineSummary;
- (nullable NSString *)bannerSubtitle;

@end

NS_ASSUME_NONNULL_END

