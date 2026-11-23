// rc-party: listens to the room and prints a torch level for each moment of the music.
//
// The tweak spawns this for "flashlight party" and turns the level into flashlight brightness.
// It lives in its own tool because microphone access needs the TCC entitlement this binary is
// signed with, and SpringBoard cannot record. One JSON line per update on stdout:
//
//   {"type":"level","v":0.42}
//   {"type":"ended","reason":"quiet|timeout|stop"}
//   {"type":"error","message":"..."}
//
// A "stop" line on stdin asks it to finish. It ends by itself after a timeout, or after the room
// stays quiet, so a forgotten party cannot run the LED (or the battery) down.

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import <stdatomic.h>
#import <string.h>
#import <unistd.h>

static _Atomic float gLevel = 0;
static _Atomic bool gRunning = true;
static float gLevelEnv = 0; // timer only
static BOOL gEmittedEnd = NO;

static BOOL gBeatStyle = NO;
static float gSensitivity = 1.0f;
static float gCap = 0.85f;
static double gTimeout = 900;
static double gStartedAt = 0;
static double gLastActivityAt = 0;
static double gLastBeatAt = 0;

// Audio thread only
static float gLowPass = 0;
static float gRmsHistory[96];
static int gRmsIndex = 0;
static BOOL gRmsFilled = NO;
static float gBassEnv = 0;
static float gPump = 0;
static float gFlash = 0;

static void rc_party_emit(NSDictionary *event) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void rc_party_end(NSString *reason) {
    if (gEmittedEnd) return;
    gEmittedEnd = YES;
    atomic_store(&gRunning, false);
    rc_party_emit(@{ @"type": @"ended", @"reason": reason ?: @"stop" });
}

static void rc_party_fail(NSString *message) {
    rc_party_emit(@{ @"type": @"error", @"message": message ?: @"Party failed" });
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *style = @"pump";
        float sensitivity = 5;
        float cap = 85;
        double timeoutMinutes = 15;
        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            if ([arg isEqualToString:@"--style"] && i + 1 < argc) style = [@(argv[++i]) lowercaseString];
            else if ([arg isEqualToString:@"--sensitivity"] && i + 1 < argc) sensitivity = @(argv[++i]).floatValue;
            else if ([arg isEqualToString:@"--cap"] && i + 1 < argc) cap = @(argv[++i]).floatValue;
            else if ([arg isEqualToString:@"--timeout"] && i + 1 < argc) timeoutMinutes = @(argv[++i]).doubleValue;
        }
        gBeatStyle = [style isEqualToString:@"beat"];
        sensitivity = MAX(1, MIN(10, sensitivity));
        gSensitivity = 0.55f + sensitivity * 0.09f; // 0.64 at 1, 1.45 at 10
        gCap = MAX(10, MIN(100, cap)) / 100.0f;
        gTimeout = MAX(1, MIN(60, timeoutMinutes)) * 60.0;

        AVAudioSession *session = [AVAudioSession sharedInstance];
        if (session.recordPermission != AVAudioSessionRecordPermissionGranted) {
            if (session.recordPermission != AVAudioSessionRecordPermissionUndetermined) {
                rc_party_fail(@"Microphone permission denied");
                return 1;
            }
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            __block BOOL granted = NO;
            [session requestRecordPermission:^(BOOL ok) {
                granted = ok;
                dispatch_semaphore_signal(sem);
            }];
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)));
            if (!granted) {
                rc_party_fail(@"Microphone permission denied");
                return 1;
            }
        }

        NSError *error = nil;
        // PlayAndRecord with MixWithOthers: the music keeps playing at full volume through the
        // speaker while the mic hears it. DefaultToSpeaker matters, or the music an app is
        // already playing would come out of the earpiece. Default mode keeps Apple's input
        // processing, which is what makes a phone microphone usable for this.
        AVAudioSessionCategoryOptions options =
            AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker;
        if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                        mode:AVAudioSessionModeDefault
                     options:options
                       error:&error] ||
            ![session setActive:YES error:&error]) {
            rc_party_fail(error.localizedDescription ?: @"Could not start the microphone");
            return 1;
        }

        AVAudioEngine *engine = [AVAudioEngine new];
        AVAudioInputNode *input = engine.inputNode;
        AVAudioFormat *format = [input outputFormatForBus:0];
        if (format.sampleRate <= 0 || format.channelCount == 0) {
            rc_party_fail(@"No microphone input");
            [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
            return 1;
        }

        const float alpha = 1.0f - expf(-2.0f * (float)M_PI * 250.0f / (float)format.sampleRate);
        [input installTapOnBus:0 bufferSize:1024 format:nil block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            float *samples = buffer.floatChannelData ? buffer.floatChannelData[0] : NULL;
            AVAudioFrameCount count = buffer.frameLength;
            if (!samples || count == 0) return;

            float bassSum = 0, fullSum = 0;
            for (AVAudioFrameCount i = 0; i < count; i++) {
                float sample = samples[i];
                gLowPass += alpha * (sample - gLowPass);
                bassSum += gLowPass * gLowPass;
                fullSum += sample * sample;
            }
            float bassRms = sqrtf(bassSum / count);
            float fullRms = sqrtf(fullSum / count);

            // The room's own noise is the quietest moment of the last two seconds. Music's peaks
            // rise well above it, while a paused song leaves only that floor, so the meter cannot
            // normalise silence up into a bright light.
            gRmsHistory[gRmsIndex] = fullRms;
            gRmsIndex = (gRmsIndex + 1) % 96;
            if (gRmsIndex == 0) gRmsFilled = YES;
            int historyCount = gRmsFilled ? 96 : MAX(gRmsIndex, 1);
            float noise = gRmsHistory[0];
            for (int i = 1; i < historyCount; i++) noise = MIN(noise, gRmsHistory[i]);
            noise = MAX(noise, 0.0008f);

            // Signal above the room, as a ratio. Silence sits at 1.0; music rises above it, so a
            // quiet room can never be normalised up into a bright light.
            float fullNorm = MIN(1.0f, MAX(0.0f, (fullRms / noise - 1.0f) / 1.5f));
            float bassNorm = MIN(1.0f, MAX(0.0f, (bassRms / noise - 1.0f) / 1.5f));
            float energy = 0.65f * bassNorm + 0.35f * fullNorm;

            double now = CFAbsoluteTimeGetCurrent();
            float previousEnv = gBassEnv;
            gBassEnv += 0.15f * (energy - gBassEnv);
            BOOL beat = energy > previousEnv * 1.35f + 0.04f && energy > 0.2f && now - gLastBeatAt > 0.22;
            if (beat) gLastBeatAt = now;

            float out = 0;
            if (gBeatStyle) {
                // A flash on each kick over a dim body, so the light reads as a beat and not a
                // series of separate on/off commands.
                if (beat) gFlash = 1.0f;
                gFlash *= 0.86f;
                gPump += 0.30f * (energy - gPump);
                out = gCap * (0.10f + 0.80f * gFlash + 0.22f * gPump);
            } else {
                // Pump: follow the music, rise quickly, fall slowly.
                float target = gCap * powf(energy, 1.1f);
                gPump += (target > gPump ? 0.35f : 0.10f) * (target - gPump);
                out = gPump;
            }
            out = MIN(gCap, MAX(0.0f, out * gSensitivity));
            atomic_store(&gLevel, out);
        }];

        if (![engine startAndReturnError:&error]) {
            rc_party_fail(error.localizedDescription ?: @"Could not start audio");
            [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
            return 1;
        }

        gStartedAt = gLastActivityAt = gLastBeatAt = CFAbsoluteTimeGetCurrent();
        gLevelEnv = 0;

        __block dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC / 30, 2 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{
            if (!atomic_load(&gRunning)) {
                dispatch_source_cancel(timer);
                return;
            }
            double now = CFAbsoluteTimeGetCurrent();
            float raw = atomic_load(&gLevel);
            // The smoothed light level is the activity test: room noise cannot hold it up, while
            // music does. Two seconds after it falls away the LED goes dark, and fifteen seconds
            // later the party ends, so a paused song cannot leave it running.
            gLevelEnv += 0.15f * (raw - gLevelEnv);
            if (gLevelEnv > 0.18f) gLastActivityAt = now;
            if (now - gLastActivityAt > 15.0) {
                rc_party_end(@"quiet");
                dispatch_source_cancel(timer);
                return;
            }
            if (now - gStartedAt > gTimeout) {
                rc_party_end(@"timeout");
                dispatch_source_cancel(timer);
                return;
            }
            float level = (now - gLastActivityAt > 2.0) ? 0.0f : MAX(raw, 0.02f);
            rc_party_emit(@{ @"type": @"level", @"v": @(level) });
        });
        dispatch_resume(timer);

        // "stop" on stdin, or the pipe closing because the tweak went away.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char buf[64];
            while (true) {
                ssize_t n = read(STDIN_FILENO, buf, sizeof(buf) - 1);
                if (n <= 0) break;
                buf[n] = 0;
                if (strstr(buf, "stop")) break;
            }
            rc_party_end(@"stop");
            dispatch_async(dispatch_get_main_queue(), ^{
                [engine stop];
                [input removeTapOnBus:0];
                [[AVAudioSession sharedInstance] setActive:NO
                                               withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                                     error:nil];
                exit(0);
            });
        });

        dispatch_main();
    }
}
