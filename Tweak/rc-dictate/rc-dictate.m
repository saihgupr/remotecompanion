#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <math.h>
#import <signal.h>
#import <stdio.h>
#import <unistd.h>

@interface RCDictationRunner : NSObject
@property (nonatomic, strong) NSObject *lock;
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) SFSpeechRecognizer *recognizer;
@property (nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *request;
@property (nonatomic, strong) SFSpeechRecognitionTask *task;
@property (nonatomic, strong) dispatch_semaphore_t finalSemaphore;
@property (nonatomic, strong) dispatch_semaphore_t exitSemaphore;
@property (nonatomic, copy) NSString *latestText;
@property (nonatomic, assign) BOOL hasEmittedText;
@property (nonatomic, assign) BOOL emittedFinal;
@property (nonatomic, assign) BOOL didFallbackToServer;
@property (nonatomic, assign) BOOL stopping;
@property (nonatomic, assign) BOOL stopped;
@property (nonatomic, assign) CFAbsoluteTime lastLevelSentAt;
@property (nonatomic, assign) int exitCode;
@end

@implementation RCDictationRunner

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [NSObject new];
        _finalSemaphore = dispatch_semaphore_create(0);
        _exitSemaphore = dispatch_semaphore_create(0);
        _latestText = @"";
        _exitCode = 0;
    }
    return self;
}

- (void)emitJSON:(NSDictionary *)obj {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!data) return;
    @synchronized (self.lock) {
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }
}

- (void)emitError:(NSString *)message {
    [self emitJSON:@{ @"type": @"error", @"message": message ?: @"Dictation failed" }];
}

- (BOOL)ensureAuthorizationsWithError:(NSString **)errorOut {
    SFSpeechRecognizerAuthorizationStatus speechStatus = [SFSpeechRecognizer authorizationStatus];
    if (speechStatus == SFSpeechRecognizerAuthorizationStatusNotDetermined) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block SFSpeechRecognizerAuthorizationStatus resolved = SFSpeechRecognizerAuthorizationStatusDenied;
        [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
            resolved = status;
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)));
        speechStatus = resolved;
    }
    if (speechStatus != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        if (errorOut) *errorOut = @"Speech recognition permission denied";
        return NO;
    }

    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionRecordPermission micPerm = session.recordPermission;
    if (micPerm == AVAudioSessionRecordPermissionUndetermined) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block BOOL granted = NO;
        [session requestRecordPermission:^(BOOL ok) {
            granted = ok;
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)));
        micPerm = granted ? AVAudioSessionRecordPermissionGranted : AVAudioSessionRecordPermissionDenied;
    }
    if (micPerm != AVAudioSessionRecordPermissionGranted) {
        if (errorOut) *errorOut = @"Microphone permission denied";
        return NO;
    }
    return YES;
}

- (void)startRecognitionTaskOnDevice:(BOOL)onDevice {
    SFSpeechAudioBufferRecognitionRequest *req = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    req.shouldReportPartialResults = YES;
    if (@available(iOS 13.0, *)) {
        req.requiresOnDeviceRecognition = onDevice && self.recognizer.supportsOnDeviceRecognition;
    }

    @synchronized (self.lock) {
        if (self.stopping) return;
        self.request = req;
    }

    __weak typeof(self) weakSelf = self;
    SFSpeechRecognitionTask *task = [self.recognizer recognitionTaskWithRequest:req resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (result) {
            NSString *text = result.bestTranscription.formattedString ?: @"";
            BOOL isFinal = result.isFinal;
            @synchronized (strongSelf.lock) {
                strongSelf.latestText = text;
                if (text.length > 0) strongSelf.hasEmittedText = YES;
                if (isFinal) strongSelf.emittedFinal = YES;
            }
            if (isFinal) {
                [strongSelf emitJSON:@{ @"type": @"final", @"text": text }];
                dispatch_semaphore_signal(strongSelf.finalSemaphore);
            } else {
                [strongSelf emitJSON:@{ @"type": @"partial", @"text": text }];
            }
        }

        if (error) {
            BOOL shouldFallback = NO;
            BOOL alreadyStopping = NO;
            @synchronized (strongSelf.lock) {
                alreadyStopping = strongSelf.stopping;
                if (onDevice && !strongSelf.hasEmittedText && !strongSelf.didFallbackToServer && !alreadyStopping) {
                    strongSelf.didFallbackToServer = YES;
                    shouldFallback = YES;
                }
            }
            if (shouldFallback) {
                [req endAudio];
                [strongSelf startRecognitionTaskOnDevice:NO];
                return;
            }
            if (!alreadyStopping) {
                [strongSelf emitError:error.localizedDescription ?: @"Speech recognition error"];
                strongSelf.exitCode = 1;
                [strongSelf stopAndWaitForFinal:NO];
            } else {
                dispatch_semaphore_signal(strongSelf.finalSemaphore);
            }
        }
    }];

    @synchronized (self.lock) {
        self.task = task;
    }
}

- (BOOL)start {
    NSString *authErr = nil;
    if (![self ensureAuthorizationsWithError:&authErr]) {
        [self emitError:authErr];
        self.exitCode = 1;
        return NO;
    }

    self.recognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale currentLocale]];
    if (!self.recognizer || !self.recognizer.isAvailable) {
        self.recognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"en-US"]];
    }
    if (!self.recognizer || !self.recognizer.isAvailable) {
        [self emitError:@"Speech recognizer unavailable"];
        self.exitCode = 1;
        return NO;
    }

    NSError *sessionErr = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryRecord
                         mode:AVAudioSessionModeMeasurement
                      options:AVAudioSessionCategoryOptionDuckOthers
                        error:&sessionErr]) {
        sessionErr = nil;
        if (![session setCategory:AVAudioSessionCategoryRecord
                             mode:AVAudioSessionModeDefault
                          options:AVAudioSessionCategoryOptionDuckOthers
                            error:&sessionErr]) {
            [self emitError:sessionErr.localizedDescription ?: @"Couldn't configure audio session"];
            self.exitCode = 1;
            return NO;
        }
    }
    if (![session setActive:YES error:&sessionErr]) {
        [self emitError:sessionErr.localizedDescription ?: @"Couldn't activate audio session"];
        self.exitCode = 1;
        return NO;
    }

    self.engine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *inputNode = self.engine.inputNode;
    AVAudioFormat *format = [inputNode outputFormatForBus:0];
    if (!format || format.sampleRate <= 0 || format.channelCount == 0) {
        [self emitError:@"No audio input format available"];
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        self.exitCode = 1;
        return NO;
    }

    BOOL preferOnDevice = NO;
    if (@available(iOS 13.0, *)) {
        preferOnDevice = self.recognizer.supportsOnDeviceRecognition;
    }
    [self startRecognitionTaskOnDevice:preferOnDevice];

    __weak typeof(self) weakSelf = self;
    [inputNode installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        SFSpeechAudioBufferRecognitionRequest *activeReq = nil;
        BOOL stopping = NO;
        @synchronized (strongSelf.lock) {
            stopping = strongSelf.stopping;
            activeReq = strongSelf.request;
        }
        if (stopping || !activeReq) return;
        [activeReq appendAudioPCMBuffer:buffer];

        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        BOOL emitLevel = NO;
        @synchronized (strongSelf.lock) {
            if (now - strongSelf.lastLevelSentAt >= 0.125) {
                strongSelf.lastLevelSentAt = now;
                emitLevel = YES;
            }
        }
        if (emitLevel && buffer.floatChannelData && buffer.frameLength > 0) {
            const float *samples = buffer.floatChannelData[0];
            AVAudioFrameCount count = buffer.frameLength;
            double sum = 0.0;
            for (AVAudioFrameCount i = 0; i < count; i++) {
                double s = samples[i];
                sum += s * s;
            }
            double rms = sqrt(sum / (double)count);
            double scaled = fmin(1.0, fmax(0.0, rms * 6.0));
            [strongSelf emitJSON:@{ @"type": @"level", @"v": @(round(scaled * 100.0) / 100.0) }];
        }
    }];

    [self.engine prepare];
    NSError *engineErr = nil;
    if (![self.engine startAndReturnError:&engineErr]) {
        [inputNode removeTapOnBus:0];
        [self emitError:engineErr.localizedDescription ?: @"Couldn't start audio engine"];
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        self.exitCode = 1;
        return NO;
    }

    [self emitJSON:@{ @"type": @"ready" }];
    return YES;
}

- (void)stopAndWaitForFinal:(BOOL)waitForFinal {
    SFSpeechAudioBufferRecognitionRequest *req = nil;
    SFSpeechRecognitionTask *task = nil;
    AVAudioEngine *engine = nil;
    @synchronized (self.lock) {
        if (self.stopped) return;
        if (self.stopping && waitForFinal) return;
        self.stopping = YES;
        self.stopped = YES;
        req = self.request;
        task = self.task;
        engine = self.engine;
    }

    if (engine) {
        [engine stop];
        @try {
            [engine.inputNode removeTapOnBus:0];
        } @catch (NSException *ignored) {}
    }
    if (req) {
        [req endAudio];
    }

    if (waitForFinal && task) {
        dispatch_semaphore_wait(self.finalSemaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)));
        NSString *fallbackText = nil;
        BOOL needFallbackFinal = NO;
        @synchronized (self.lock) {
            if (!self.emittedFinal && self.latestText.length > 0) {
                self.emittedFinal = YES;
                fallbackText = [self.latestText copy];
                needFallbackFinal = YES;
            }
        }
        if (needFallbackFinal) {
            [self emitJSON:@{ @"type": @"final", @"text": fallbackText }];
        }
    }

    if (task) {
        [task cancel];
    }
    [[AVAudioSession sharedInstance] setActive:NO
                                   withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                         error:nil];
    dispatch_semaphore_signal(self.exitSemaphore);
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        setvbuf(stdout, NULL, _IONBF, 0);

        RCDictationRunner *runner = [[RCDictationRunner alloc] init];

        signal(SIGTERM, SIG_IGN);
        signal(SIGINT, SIG_IGN);
        dispatch_source_t termSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
        dispatch_source_set_event_handler(termSource, ^{
            [runner stopAndWaitForFinal:YES];
        });
        dispatch_resume(termSource);

        dispatch_source_t intSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
        dispatch_source_set_event_handler(intSource, ^{
            [runner stopAndWaitForFinal:YES];
        });
        dispatch_resume(intSource);

        if (![runner start]) {
            return runner.exitCode ?: 1;
        }

        // Stop on stdin "stop\n" or EOF.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            char buf[256];
            while (fgets(buf, sizeof(buf), stdin) != NULL) {
                NSString *line = [@(buf) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([line isEqualToString:@"stop"]) {
                    break;
                }
            }
            [runner stopAndWaitForFinal:YES];
        });

        // Hard 120s safety timeout so dictation can never leak or drain battery.
        dispatch_semaphore_wait(runner.exitSemaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120.0 * NSEC_PER_SEC)));
        [runner stopAndWaitForFinal:YES];
        return runner.exitCode;
    }
}
