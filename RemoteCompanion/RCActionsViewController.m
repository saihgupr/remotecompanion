#import "RCActionsViewController.h"
#import "RCConfigManager.h"
#import "RCActionPickerViewController.h"
#import "RCShortcutPickerViewController.h"
#import "RCAppPickerViewController.h"
#import "RCConditionPickerViewController.h"
#import "RCTextInputViewController.h"
#import "RCTimeRangeViewController.h"
#import "RCSetVariableViewController.h"
#import "RCVariableConditionViewController.h"
#import "RCNumberSettingViewController.h"
#import "RCToastEditorViewController.h"
#import "RCServerClient.h"
#import "RCRunningViewController.h"
#import "RCRunHistoryViewController.h"
#import "RCScheduledTriggerViewController.h"
#import "RCNotificationTriggerViewController.h"
#import "RCWiFiTriggerViewController.h"
#import "RCBluetoothTriggerViewController.h"
#import "RCAudioOutputTriggerViewController.h"
#import "RCWrapSizing.h"
#import "RCNFCTriggerViewController.h"
#import "RCDevicePickerViewController.h"
#import "RCFocusPickerViewController.h"
#import "RCKMMacroPickerViewController.h"
#import <notify.h>
#import <objc/runtime.h>

#define kSimulateNotificationPrefix "com.pizzaman.rc.simulate."

static void rc_parse_km_cmd(NSString *cmd, NSString **outMacro, NSString **outParam) {
    if (!cmd || ![cmd isKindOfClass:[NSString class]]) {
        if (outMacro) *outMacro = @"";
        if (outParam) *outParam = @"";
        return;
    }
    NSString *raw = [cmd hasPrefix:@"km "] ? [cmd substringFromIndex:3] : cmd;
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *macro = nil;
    NSString *param = nil;
    if ([[raw lowercaseString] hasPrefix:@"trigger "]) {
        NSString *after = [[raw substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([after hasPrefix:@"\""]) {
            NSRange endQ = [after rangeOfString:@"\"" options:0 range:NSMakeRange(1, after.length - 1)];
            if (endQ.location != NSNotFound) {
                macro = [after substringWithRange:NSMakeRange(1, endQ.location - 1)];
                NSString *rem = [[after substringFromIndex:endQ.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (rem.length > 0) {
                    if ([rem hasPrefix:@"\""] && [rem hasSuffix:@"\""] && rem.length >= 2) {
                        param = [rem substringWithRange:NSMakeRange(1, rem.length - 2)];
                    } else {
                        param = rem;
                    }
                }
            }
        }
        if (!macro) {
            NSArray *parts = [after componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSMutableArray *cp = [NSMutableArray array];
            for (NSString *p in parts) { if (p.length > 0) [cp addObject:p]; }
            if (cp.count > 0) {
                macro = cp[0];
                if (cp.count > 1) {
                    param = [[cp subarrayWithRange:NSMakeRange(1, cp.count - 1)] componentsJoinedByString:@" "];
                }
            }
        }
    } else {
        macro = raw;
    }
    if (outMacro) *outMacro = macro ?: @"";
    if (outParam) *outParam = param ?: @"";
}


@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface RCActionCell : UITableViewCell
@end

@implementation RCActionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    return self;
}

// Grows to show the whole title and subtitle, never below the usual row height
- (CGSize)systemLayoutSizeFittingSize:(CGSize)targetSize withHorizontalFittingPriority:(UILayoutPriority)horizontalFittingPriority verticalFittingPriority:(UILayoutPriority)verticalFittingPriority {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"]) return CGSizeMake(targetSize.width, 70.0);
    return CGSizeMake(targetSize.width, RCWrappedCellHeight(self, targetSize.width, 70.0));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat indentWidth = self.indentationWidth > 0 ? self.indentationWidth : 14.0f;
    CGFloat indentOffset = self.indentationLevel * indentWidth;
    
    if (self.indentationLevel > 0 && self.imageView && !CGRectIsEmpty(self.imageView.frame)) {
        CGRect imgFrame = self.imageView.frame;
        imgFrame.origin.x += indentOffset;
        self.imageView.frame = imgFrame;
    }
    
    if (self.textLabel && !CGRectIsEmpty(self.textLabel.frame)) {
        CGRect textFrame = self.textLabel.frame;
        if (self.indentationLevel > 0) {
            textFrame.origin.x += indentOffset;
        }
        CGFloat maxW = self.contentView.bounds.size.width - textFrame.origin.x - 6.0f;
        textFrame.size.width = MAX(0, maxW);
        self.textLabel.frame = textFrame;
    }
    
    if (self.detailTextLabel && !CGRectIsEmpty(self.detailTextLabel.frame)) {
        CGRect detailFrame = self.detailTextLabel.frame;
        if (self.indentationLevel > 0) {
            detailFrame.origin.x += indentOffset;
        }
        CGFloat maxW = self.contentView.bounds.size.width - detailFrame.origin.x - 6.0f;
        detailFrame.size.width = MAX(0, maxW);
        self.detailTextLabel.frame = detailFrame;
    }
}

@end

@interface RCActionsViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSString *triggerKey;
@property (nonatomic, strong) NSMutableArray *actions;
@property (nonatomic, strong) UIBarButtonItem *moreButton;
// While this trigger runs: the row of the action it's on (highlighted, like a debugger's current
// line), or NSNotFound
@property (nonatomic, assign) NSInteger runningIndex; // the longest run's (scrolled to)
@property (nonatomic, strong) NSIndexSet *runningIndexes; // every run's (all highlighted)
@property (nonatomic, copy) NSString *runningRunID; // with one run, Stop ends it
@property (nonatomic, strong) NSTimer *runTimer;
@property (nonatomic, assign) int runsToken;
@property (nonatomic, assign) int stepToken;
@property (nonatomic, assign) BOOL pollInFlight, pollAgain;
// The debugger view: follows this one run (highlight, time, Stop), read-only. Without it the page is
// the trigger's ordinary editor, with a strip at the top while the trigger runs.
@property (nonatomic, copy) NSString *debugRunID;
@property (nonatomic, assign) BOOL debugRunSeen; // the followed run has shown up (it ending closes the view)
@property (nonatomic, copy) NSArray<NSDictionary *> *stripRuns; // this trigger's runs, for the strip
@property (nonatomic, weak) UILabel *stripLabel;
// Reordering: the rows being dragged (one action, or a whole block), the picture of them that
// follows the finger, the line where they'd land, and the gap (insert before this row) it marks
@property (nonatomic, assign) NSRange reorderRange;
@property (nonatomic, strong) UIView *reorderSnapshot;
@property (nonatomic, strong) UIView *reorderLine;
@property (nonatomic, assign) NSInteger reorderGap;
@property (nonatomic, assign) CGFloat reorderGrabOffset; // finger to the picture's centre (it floats above the finger)
@property (nonatomic, assign) CGPoint pressStart;
@property (nonatomic, assign) BOOL pressMoved;
@property (nonatomic, strong) CADisplayLink *reorderScrollLink;
@property (nonatomic, assign) CGFloat reorderFingerY; // in the table's visible frame, for scrolling
@property (nonatomic, strong) UISelectionFeedbackGenerator *reorderTick;
@end

// The drag handle: line.3.horizontal is iOS 15 and later; iOS 14 has the older name
static UIImage *RCGrabberImage(void) {
    return [UIImage systemImageNamed:@"line.3.horizontal"] ?: [UIImage systemImageNamed:@"line.horizontal.3"];
}


@implementation RCActionsViewController

static id g_actionClipboard = nil;

- (NSString *)displayNameForCommand:(id)cmd {
    return [[RCConfigManager sharedManager] nameForCommand:cmd truncate:YES];
}

- (NSAttributedString *)attributedDisplayNameForCommand:(NSString *)cmd {
    if (![cmd isKindOfClass:[NSString class]]) return nil;
    NSString *lower = [cmd lowercaseString];
    NSString *baseText = nil;
    NSString *paramText = nil;
    
    UIColor *accentColor = [UIColor systemBlueColor];
    
    if ([lower hasPrefix:@"set-vol "]) {
        baseText = @"Set Volume ";
        paramText = [NSString stringWithFormat:@"%@%%", [cmd substringFromIndex:8]];
    } else if ([lower hasPrefix:@"ringer volume "]) {
        baseText = @"Set Ringer Volume ";
        paramText = [NSString stringWithFormat:@"%@%%", [cmd substringFromIndex:14]];
    } else if ([lower hasPrefix:@"brightness "]) {
        baseText = @"Set Brightness ";
        paramText = [NSString stringWithFormat:@"%@%%", [cmd substringFromIndex:11]];
    } else if ([lower hasPrefix:@"flashlight "] || [lower hasPrefix:@"flash "]) {
        NSString *val = [cmd substringFromIndex:[lower hasPrefix:@"flashlight "] ? 11 : 6];
        // Only if it's a number (flashlight intensity)
        NSScanner *scanner = [NSScanner scannerWithString:val];
        BOOL isNumeric = [scanner scanFloat:NULL] && [scanner isAtEnd];
        if (isNumeric) {
            baseText = @"Flashlight ";
            paramText = [NSString stringWithFormat:@"%@%%", val];
        }
    } else if ([lower hasPrefix:@"stop trigger "]) {
        baseText = @"Stop: ";
        paramText = [[RCConfigManager sharedManager] displayNameForTrigger:[cmd substringFromIndex:13]];
    } else if ([lower hasPrefix:@"delay "]) {
        baseText = @"Wait ";
        paramText = [NSString stringWithFormat:@"%@s", [cmd substringFromIndex:6]];
    } else if ([lower hasPrefix:@"shortcut:"]) {
        baseText = @"Shortcut: ";
        paramText = [RCConfigManager shortcutNameForAction:cmd silent:NULL input:NULL];
    } else if ([lower hasPrefix:@"uiopen "]) {
        baseText = @"Open ";
        NSString *bundleId = [cmd substringFromIndex:7];
        NSString *appName = bundleId;
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if (proxyClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleId];
            if (proxy) {
                NSString *name = [proxy performSelector:@selector(localizedName)];
                if (name.length > 0) {
                    appName = name;
                }
            }
#pragma clang diagnostic pop
        }
        paramText = appName;
    } else if ([lower isEqualToString:@"kill current"] || [lower isEqualToString:@"kill front"] ||
               [lower isEqualToString:@"kill foreground"] || [lower isEqualToString:@"kill current app"] ||
               [lower isEqualToString:@"kill front app"]) {
        // Runtime-resolved target, not a bundle ID: plain label, no accent
        return [[NSAttributedString alloc] initWithString:@"Kill Current App" attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: [UIColor labelColor]
        }];
    } else if ([lower hasPrefix:@"kill "]) {
        baseText = @"Kill ";
        NSString *bundleId = [cmd substringFromIndex:5];
        NSString *appName = bundleId;
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if (proxyClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleId];
            if (proxy) {
                NSString *name = [proxy performSelector:@selector(localizedName)];
                if (name.length > 0) {
                    appName = name;
                }
            }
#pragma clang diagnostic pop
        }
        paramText = appName;
    } else if ([lower hasPrefix:@"airplay connect "]) {
        baseText = @"AirPlay Connect ";
        paramText = [cmd substringFromIndex:16];
    } else if ([lower hasPrefix:@"bt connect "] || [lower hasPrefix:@"bluetooth connect "]) {
        baseText = @"Connect ";
        paramText = [cmd substringFromIndex:[lower hasPrefix:@"bt connect "] ? 11 : 18];
    } else if ([lower hasPrefix:@"bt disconnect "] || [lower hasPrefix:@"bluetooth disconnect "]) {
        baseText = @"Disconnect ";
        paramText = [cmd substringFromIndex:[lower hasPrefix:@"bt disconnect "] ? 14 : 21];
    } else if ([lower hasPrefix:@"focus on "]) {
        baseText = @"Turn On ";
        paramText = [cmd substringFromIndex:9];
    } else if ([lower hasPrefix:@"focus toggle "]) {
        baseText = @"Toggle ";
        paramText = [cmd substringFromIndex:13];
    } else if ([lower hasPrefix:@"toast "]) {
        baseText = @"Toast ";
        NSString *argString = [cmd substringFromIndex:6];
        NSString *firstArg = nil;
        if ([argString hasPrefix:@"\""]) {
            NSRange nextQuote = [argString rangeOfString:@"\"" options:0 range:NSMakeRange(1, argString.length - 1)];
            if (nextQuote.location != NSNotFound) {
                firstArg = [argString substringWithRange:NSMakeRange(1, nextQuote.location - 1)];
            } else {
                firstArg = [argString substringFromIndex:1];
            }
        } else {
            NSRange firstSpace = [argString rangeOfString:@" "];
            if (firstSpace.location != NSNotFound) {
                firstArg = [argString substringToIndex:firstSpace.location];
            } else {
                firstArg = argString;
            }
        }
        paramText = firstArg;
    } else if ([lower hasPrefix:@"unlock "]) {
        baseText = @"Unlock Device ";
        paramText = @"(Passcode)";
    } else if ([lower hasPrefix:@"lock-toggle "] || [lower hasPrefix:@"lock toggle "]) {
        baseText = @"Lock Toggle ";
        paramText = @"(Passcode)";
    }
    
    if (baseText && paramText) {
        NSString *fullText = [NSString stringWithFormat:@"%@%@", baseText, paramText];
        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:fullText];
        NSRange baseRange = NSMakeRange(0, baseText.length);
        NSRange paramRange = NSMakeRange(baseText.length, paramText.length);
        
        [attrStr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium] range:NSMakeRange(0, fullText.length)];
        [attrStr addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor] range:baseRange];
        [attrStr addAttribute:NSForegroundColorAttributeName value:accentColor range:paramRange];
        return attrStr;
    }
    
    return nil;
}

- (NSString *)iconForCommand:(id)cmd {
    return [[RCConfigManager sharedManager] iconForCommand:cmd];
}

// What happens when the trigger fires again while its actions are still running (in a wait):
// "parallel" runs them again alongside, "restart" stops the run that's going and starts over,
// "single" ignores the new firing
- (NSString *)runMode {
    NSString *mode = [[RCConfigManager sharedManager] triggerDataForKey:_triggerKey][@"mode"];
    return [mode isKindOfClass:[NSString class]] ? mode : @"parallel";
}

- (void)setRunMode:(NSString *)mode {
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSMutableDictionary *data = [[config triggerDataForKey:_triggerKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([mode isEqualToString:@"parallel"]) [data removeObjectForKey:@"mode"]; else data[@"mode"] = mode;
    [config updateTrigger:_triggerKey withData:data];
    self.moreButton.menu = [self moreMenu];
    [self.tableView reloadData];
}

- (void)setKeepsDefaultAction:(BOOL)keep {
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSMutableDictionary *data = [[config triggerDataForKey:_triggerKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (keep) data[@"keepDefault"] = @YES; else [data removeObjectForKey:@"keepDefault"];
    [config updateTrigger:_triggerKey withData:data];
    self.moreButton.menu = [self moreMenu];
}

// A trigger with a loop restarts when it fires again (instead of running a second copy alongside),
// unless When Triggered Again was already chosen
- (void)defaultToRestartForLoop {
    if ([[RCConfigManager sharedManager] triggerDataForKey:_triggerKey][@"mode"]) return;
    [self setRunMode:@"restart"];
}

// When Triggered Again: in the ••• menu, and on the banner above the sequence
- (UIMenu *)runModeMenu {
    __weak typeof(self) weakSelf = self;
    NSMutableArray *modes = [NSMutableArray array];
    NSString *current = [self runMode];
    NSArray *choices = @[@[@"parallel", @"Run Alongside", @"square.stack"], @[@"restart", @"Restart", @"arrow.counterclockwise"], @[@"single", @"Ignore", @"nosign"]];
    for (NSArray *choice in choices) {
        UIAction *action = [UIAction actionWithTitle:choice[1] image:[UIImage systemImageNamed:choice[2]] identifier:nil handler:^(__kindof UIAction *a) {
            [weakSelf setRunMode:choice[0]];
        }];
        action.state = [current isEqualToString:choice[0]] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [modes addObject:action];
    }
    return [UIMenu menuWithTitle:@"When Triggered Again" image:[UIImage systemImageNamed:@"repeat"] identifier:nil options:0 children:modes];
}

- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;
    NSMutableArray *menuActions = [NSMutableArray arrayWithObject:[self runModeMenu]];
    // Triggers that take over what iOS normally does can keep it as well: the ping sound, and with a
    // Home button the Accessibility Shortcut, App Switcher, Siri and screenshot, otherwise Siri, the
    // Accessibility Shortcut, a screenshot and Wallet
    NSArray *keepsDefault = [RCConfigManager hasHomeButton]
        ? @[@"trigger_watch_ping", @"trigger_watch_ping_hold", @"trigger_home_triple_click", @"trigger_home_double_click", @"trigger_home_hold", @"trigger_home_power"]
        : @[@"trigger_watch_ping", @"trigger_watch_ping_hold", @"power_long_press", @"power_triple_click", @"power_volume_up", @"power_double_tap"];
    if ([keepsDefault containsObject:_triggerKey]) {
        BOOL keep = [[[RCConfigManager sharedManager] triggerDataForKey:_triggerKey][@"keepDefault"] boolValue];
        UIAction *sound = [UIAction actionWithTitle:@"Keep Default Action" image:[UIImage systemImageNamed:@"arrow.uturn.backward.circle"] identifier:nil handler:^(__kindof UIAction *a) {
            [weakSelf setKeepsDefaultAction:!keep];
        }];
        sound.state = keep ? UIMenuElementStateOn : UIMenuElementStateOff;
        [menuActions addObject:sound];
    }
    [menuActions addObject:[UIAction actionWithTitle:@"Run History" image:[UIImage systemImageNamed:@"clock.arrow.circlepath"] identifier:nil handler:^(__unused UIAction *a) {
        [weakSelf.navigationController pushViewController:[[RCRunHistoryViewController alloc] initWithTriggerKey:weakSelf.triggerKey] animated:YES];
    }]];
    [menuActions addObject:[UIAction actionWithTitle:@"Import Actions" image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(__kindof UIAction *a) {
        [weakSelf importActions];
    }]];
    [menuActions addObject:[UIAction actionWithTitle:@"Export Actions" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__kindof UIAction *a) {
        [weakSelf exportActions];
    }]];
    UIAction *clearAction = [UIAction actionWithTitle:@"Clear All Actions" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__kindof UIAction *a) {
        [weakSelf clearAllActions];
    }];
    clearAction.attributes = UIMenuElementAttributesDestructive;
    [menuActions addObject:clearAction];
    return [UIMenu menuWithTitle:@"" children:menuActions];
}

// Picks a trigger for a "stop trigger" action; done gets its key
- (void)pickTriggerToStop:(void (^)(NSString *key))done {
    RCConfigManager *config = [RCConfigManager sharedManager];
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in [config allConfiguredTriggerKeys]) if (![key isEqualToString:_triggerKey]) [keys addObject:key];
    [keys sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [[config displayNameForTrigger:a] localizedCaseInsensitiveCompare:[config displayNameForTrigger:b]];
    }];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Stop Trigger" message:@"Stops that trigger's actions while they're still running, such as during a delay." preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *key in keys) {
        [sheet addAction:[UIAlertAction actionWithTitle:[config displayNameForTrigger:key] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { done(key); }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (instancetype)initWithTriggerKey:(NSString *)triggerKey followingRun:(NSString *)runID {
    self = [self initWithTriggerKey:triggerKey];
    if (self) _debugRunID = [runID copy];
    return self;
}

- (instancetype)initWithTriggerKey:(NSString *)triggerKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _triggerKey = triggerKey;
        _runningIndex = NSNotFound;
    }
    return self;
}

// Editors on screen following runs; the tweak sends step signals only while there's one
static NSInteger g_runWatchers = 0;

static void RCSetRunWatching(BOOL watching) {
    g_runWatchers = MAX(0, g_runWatchers + (watching ? 1 : -1));
    static int token = NOTIFY_TOKEN_INVALID;
    if (token == NOTIFY_TOKEN_INVALID) notify_register_check("com.pizzaman.rc.run_watch", &token);
    if (token != NOTIFY_TOKEN_INVALID) notify_set_state(token, g_runWatchers > 0 ? 1 : 0);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startRunWatch];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopRunWatch];
}

// In the background nothing is shown, so nothing is followed
- (void)appDidEnterBackground {
    [self stopRunWatch];
}

- (void)appWillEnterForeground {
    if (self.view.window) [self startRunWatch];
}

// Follow a run of this trigger: one when it starts or ends (runs_changed), each step (run_step),
// and once a second for the time
- (void)startRunWatch {
    if (self.runsToken) return;
    RCSetRunWatching(YES);
    __weak typeof(self) weakSelf = self;
    int token;
    if (notify_register_dispatch("com.pizzaman.rc.runs_changed", &token, dispatch_get_main_queue(), ^(int t) { [weakSelf pollRun]; }) == NOTIFY_STATUS_OK) {
        self.runsToken = token;
    }
    if (notify_register_dispatch("com.pizzaman.rc.run_step", &token, dispatch_get_main_queue(), ^(int t) { [weakSelf pollRun]; }) == NOTIFY_STATUS_OK) {
        self.stepToken = token;
    }
    [self pollRun];
}

- (void)stopRunWatch {
    if (!self.runsToken && !self.stepToken) return;
    RCSetRunWatching(NO);
    if (self.runsToken) notify_cancel(self.runsToken);
    if (self.stepToken) notify_cancel(self.stepToken);
    self.runsToken = 0;
    self.stepToken = 0;
    [self.runTimer invalidate];
    self.runTimer = nil;
}

// One request at a time: steps that come while one is out are covered by one more after it
- (void)pollRun {
    if (self.pollInFlight) { self.pollAgain = YES; return; }
    self.pollInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"running" completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *runs = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!strongSelf.isViewLoaded) { strongSelf.pollInFlight = NO; return; }
            NSMutableArray *mine = [NSMutableArray array]; // this trigger's runs, longest first
            if ([runs isKindOfClass:[NSArray class]]) {
                for (NSDictionary *run in runs) {
                    if ([run isKindOfClass:[NSDictionary class]] && [run[@"key"] isEqual:strongSelf.triggerKey]) [mine addObject:run];
                }
            }
            [strongSelf showRuns:mine];
            strongSelf.pollInFlight = NO;
            if (strongSelf.pollAgain) {
                strongSelf.pollAgain = NO;
                [strongSelf pollRun];
            }
        });
    }];
}

- (void)showRuns:(NSArray<NSDictionary *> *)runs {
    if (self.debugRunID) {
        NSDictionary *run = nil;
        for (NSDictionary *each in runs) if ([each[@"id"] isEqual:self.debugRunID]) run = each;
        [self showDebugRun:run];
    } else {
        [self showStripForRuns:runs];
    }
}

// The ordinary editor: a strip at the top of the list while the trigger runs
- (void)showStripForRuns:(NSArray<NSDictionary *> *)runs {
    BOOL had = self.stripRuns.count > 0;
    self.stripRuns = runs;
    if (had != (runs.count > 0)) {
        [self.tableView reloadData]; // the strip comes or goes (the header's height changes)
    } else if (self.stripLabel) {
        self.stripLabel.text = [self stripText];
    }
    if (runs.count && !self.runTimer && self.runsToken) {
        __weak typeof(self) weakSelf = self;
        self.runTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) { [weakSelf pollRun]; }];
    } else if (!runs.count) {
        [self.runTimer invalidate];
        self.runTimer = nil;
    }
}

- (NSString *)stripText {
    NSDictionary *run = self.stripRuns.firstObject;
    if (!run) return @"";
    NSInteger seconds = [run[@"seconds"] integerValue];
    NSString *time = seconds < 60 ? [NSString stringWithFormat:@"%ld s", (long)seconds] : [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
    if (self.stripRuns.count > 1) return [NSString stringWithFormat:@"%lu running · longest %@", (unsigned long)self.stripRuns.count, time];
    NSString *step = run[@"step"] ? [[RCConfigManager sharedManager] nameForCommand:run[@"step"] truncate:YES] : @"Starting";
    return [NSString stringWithFormat:@"%@ · %@ · %@", [run[@"test"] boolValue] ? @"Testing" : @"Running", time, step];
}

// The strip: green, with the runs' state; tap for this trigger's Running list, Stop ends them all
- (UIView *)runStripWithWidth:(CGFloat)width left:(CGFloat)left right:(CGFloat)right {
    UIView *strip = [[UIView alloc] initWithFrame:CGRectMake(left, 10, width - left - right, 40)];
    strip.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    strip.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.18];
    strip.layer.cornerRadius = 10;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.circle.fill"]];
    icon.tintColor = [UIColor systemGreenColor];
    icon.contentMode = UIViewContentModeCenter;
    icon.frame = CGRectMake(10, 0, 24, 40);
    [strip addSubview:icon];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(42, 0, strip.bounds.size.width - 42 - 44, 40)];
    label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    label.textColor = [UIColor labelColor];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = [self stripText];
    [strip addSubview:label];
    self.stripLabel = label;
    UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
    [stop setImage:[UIImage systemImageNamed:@"stop.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20]] forState:UIControlStateNormal];
    stop.tintColor = [UIColor systemRedColor];
    stop.frame = CGRectMake(strip.bounds.size.width - 44, 0, 44, 40);
    stop.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    stop.accessibilityLabel = @"Stop";
    [stop addTarget:self action:@selector(stopAllRuns) forControlEvents:UIControlEventTouchUpInside];
    [strip addSubview:stop];
    [strip addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openRuns)]];
    return strip;
}

- (void)stopAllRuns {
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:[@"stop trigger " stringByAppendingString:self.triggerKey] completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf pollRun]; });
    }];
}

// The debugger view: the followed run's step highlighted, its time and loop round above the title,
// and Stop. When the run ends, the view closes.
- (void)showDebugRun:(NSDictionary *)run {
    if (!run) {
        [self.runTimer invalidate];
        self.runTimer = nil;
        self.navigationItem.prompt = self.debugRunSeen ? @"Finished" : @"Not running";
        if (self.runningIndexes.count) {
            NSIndexSet *old = self.runningIndexes;
            self.runningIndexes = [NSIndexSet indexSet];
            [old enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [self repaintRunRow:i]; }];
        }
        self.navigationItem.rightBarButtonItems = @[];
        if (self.debugRunSeen && self.navigationController.topViewController == self) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (weakSelf.navigationController.topViewController == weakSelf) [weakSelf.navigationController popViewControllerAnimated:YES];
            });
        }
        return;
    }
    self.debugRunSeen = YES;
    NSInteger index = run[@"index"] ? [run[@"index"] integerValue] : NSNotFound;
    if (index != NSNotFound && (index < 0 || index >= (NSInteger)self.actions.count)) index = NSNotFound;
    NSIndexSet *indexes = index != NSNotFound ? [NSIndexSet indexSetWithIndex:index] : [NSIndexSet indexSet];
    if (![indexes isEqualToIndexSet:self.runningIndexes ?: [NSIndexSet indexSet]]) {
        NSMutableIndexSet *changed = [indexes mutableCopy];
        [changed addIndexes:self.runningIndexes ?: [NSIndexSet indexSet]];
        self.runningIndexes = indexes;
        // Repainted in place: reloading the rows cross-fades the old and new cells, and quick steps
        // stacked those fades into a darker green
        NSInteger rowCount = [self.tableView numberOfRowsInSection:0];
        [changed enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
            if ((NSInteger)i < rowCount) [self repaintRunRow:i];
        }];
    }
    if (index != self.runningIndex) {
        self.runningIndex = index;
        if (index != NSNotFound) [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] atScrollPosition:UITableViewScrollPositionNone animated:YES];
    }
    NSInteger seconds = [run[@"seconds"] integerValue];
    NSString *prompt = [NSString stringWithFormat:@"%@ for %ld s", [run[@"test"] boolValue] ? @"Testing" : @"Running", (long)seconds];
    NSDictionary *loop = [run[@"loop"] isKindOfClass:[NSDictionary class]] ? run[@"loop"] : nil;
    if (loop) {
        NSInteger count = loop[@"count"] ? [loop[@"count"] integerValue] : [loop[@"repeat"] isKindOfClass:[NSDictionary class]] ? [loop[@"repeat"][@"count"] integerValue] : 0;
        prompt = count > 0 ? [prompt stringByAppendingFormat:@" · Round %ld of %ld", (long)[loop[@"round"] integerValue], (long)count]
                           : [prompt stringByAppendingFormat:@" · Round %ld", (long)[loop[@"round"] integerValue]];
    }
    self.navigationItem.prompt = prompt;
    if (!self.runTimer && self.runsToken) {
        __weak typeof(self) weakSelf = self;
        self.runTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) { [weakSelf pollRun]; }];
    }
}

// The followed run: Stop ends it
- (void)stopRun {
    if (!self.debugRunID.length) return;
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:[@"stop run " stringByAppendingString:self.debugRunID] completion:^(NSString *output, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf pollRun]; });
    }];
}

// This trigger's Running list (from the strip): each run with Stop, and its debugger view
- (void)openRuns {
    [self.navigationController pushViewController:[[RCRunningViewController alloc] initWithTriggerKey:self.triggerKey] animated:YES];
}

// Shows or clears the run highlight on a visible row (rows scrolled in later get it from
// willDisplayCell)
- (void)repaintRunRow:(NSInteger)row {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (!cell) return;
    if (![self.runningIndexes containsIndex:row]) {
        // The icon's own tint, as cellForRow sets it
        id item = row < (NSInteger)self.actions.count ? self.actions[row] : nil;
        BOOL isStep = [item isKindOfClass:[NSDictionary class]] && !((NSDictionary *)item)[@"command"];
        if (isStep) {
            cell.imageView.tintColor = ([self isBlockEndItem:item] || [self isElseActionItem:item]) ? [UIColor tertiaryLabelColor] : [UIColor systemGrayColor];
        } else {
            NSString *action = [item isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)item)[@"command"] : item;
            cell.imageView.tintColor = [[self iconForCommand:action] hasPrefix:@"USER_APP:"] ? nil : [UIColor systemGrayColor];
        }
    }
    [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
}

// The debugger view is read-only (no adding, moving, editing or deleting)
- (BOOL)runShown {
    return self.debugRunID != nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    // Elegant grey tint
    self.navigationController.navigationBar.tintColor = [UIColor labelColor];
    
    self.title = [[RCConfigManager sharedManager] displayNameForTrigger:_triggerKey];
    
    // Plus Button to add action directly
    UIBarButtonItem *plusButton = [[UIBarButtonItem alloc] 
        initWithImage:[UIImage systemImageNamed:@"plus"] 
        style:UIBarButtonItemStylePlain 
        target:self 
        action:@selector(addAction)];
    
    // More options menu (when fired again, Import, Export, Clear)
    UIBarButtonItem *moreButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[self moreMenu]];
    self.moreButton = moreButton;
    
    NSMutableArray *rightItems = [NSMutableArray arrayWithArray:@[moreButton, plusButton]];
    
    BOOL isConfigurable = [_triggerKey hasPrefix:@"sched_"] ||
                          [_triggerKey hasPrefix:@"notif_"] ||
                          [_triggerKey hasPrefix:@"notify_"] ||
                          [_triggerKey hasPrefix:@"wifi_"] ||
                          [_triggerKey hasPrefix:@"bt_"] ||
                          [_triggerKey hasPrefix:@"output_"] ||
                          [_triggerKey hasPrefix:@"app_launch_"] ||
                          [_triggerKey hasPrefix:@"app_exit_"];
    
    if (isConfigurable) {
        UIBarButtonItem *settingsButton = [[UIBarButtonItem alloc] 
            initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"] 
            style:UIBarButtonItemStylePlain 
            target:self 
            action:@selector(editTriggerSettings)];
        [rightItems addObject:settingsButton];
    }
    
    UIBarButtonItem *playButton = [[UIBarButtonItem alloc] 
        initWithImage:[UIImage systemImageNamed:@"play"] 
        style:UIBarButtonItemStylePlain 
        target:self 
        action:@selector(runSequence)];
    [rightItems addObject:playButton];
    
    self.navigationItem.rightBarButtonItems = rightItems;
    if (self.debugRunID) {
        // The debugger view: just Stop for the run it follows
        UIBarButtonItem *stop = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"stop.circle.fill"] style:UIBarButtonItemStylePlain target:self action:@selector(stopRun)];
        stop.tintColor = [UIColor systemRedColor];
        stop.accessibilityLabel = @"Stop";
        self.navigationItem.rightBarButtonItems = @[stop];
    }

    // Add tap gesture to title if it's an NFC trigger
    if ([_triggerKey hasPrefix:@"nfc_"]) {
        UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(renameTrigger)];
        
        // Create a custom title view to accept interactions
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = self.title;
        titleLabel.font = [UIFont boldSystemFontOfSize:17];
        titleLabel.userInteractionEnabled = YES;
        [titleLabel addGestureRecognizer:titleTap];
        
        self.navigationItem.titleView = titleLabel;
    }

    
    // Enable Large Titles
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    
    // Listen for color tweak changes
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleTweaksChanged:) 
                                                  name:@"RCConfigTweaksChangedNotification" 
                                               object:nil];
    // Listen for config changes
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleConfigChanged:) 
                                                  name:RCConfigChangedNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wrapLongNamesSettingChanged:) name:@"RCWrapLongNamesSettingChanged" object:nil];
    [self applyTweaks];
    
    // Load actions
    _actions = [[[RCConfigManager sharedManager] actionsForTrigger:_triggerKey] mutableCopy];
    [self updateWrappedTitle];
    
    // Non-editing mode to allow swipe actions
    self.tableView.editing = NO;
    self.tableView.allowsSelectionDuringEditing = YES;
    // Reordering is the page's own drag (see "Reordering"): iOS's drag and drop drew the dragged row
    // empty on iOS 14 and guessed whether a drop next to a block's edge went in or out
    self.tableView.dragInteractionEnabled = NO;
    [self installReorderGestures];
    
    // Deletion is handled via swipe actions (trailingSwipeActionsConfigurationForRowAtIndexPath)
    
    // rightBarButtonItems set above

    [self.tableView registerClass:[RCActionCell class] forCellReuseIdentifier:@"ActionCell"];
    // Long names wrap and the row grows with them, never below the usual 70
    self.tableView.rowHeight = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] ? UITableViewAutomaticDimension : 70.0;
    self.tableView.estimatedRowHeight = 70;
}

- (void)wrapLongNamesSettingChanged:(NSNotification *)note {
    self.tableView.rowHeight = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"] ? UITableViewAutomaticDimension : 70.0;
    [self.tableView reloadData];
}

// A long trigger name ("Launch Alaska, Amazon, Notes") is cut off in a large title, which can't wrap:
// when it doesn't fit, the name is shown wrapped above the list instead, and the bar title is left empty.
// Once the screen shows the name that way it keeps doing so until it is closed: the navigation bar
// can't be switched back to a large title in place (it stayed at its small size), so a name that
// becomes short just shows in the same header at the large-title size.
- (void)updateWrappedTitle {
    if ([_triggerKey hasPrefix:@"nfc_"]) return; // has its own tappable title
    NSString *name = self.title ?: @"";
    // Known before the screen is laid out for the first time, so the right title is there from the start
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) width = self.navigationController.view.bounds.size.width;
    if (width <= 0) width = [UIScreen mainScreen].bounds.size.width;
    CGFloat available = width - 40.0;
    UIFont *largeFont = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    BOOL fits = ceil([name sizeWithAttributes:@{ NSFontAttributeName: largeFont }].width) <= available;
    BOOL showingHeader = (self.tableView.tableHeaderView != nil);
    if (fits && !showingHeader) return; // an ordinary large title

    if (!showingHeader) {
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
        self.navigationItem.titleView = [[UIView alloc] init];
    }
    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.font = fits ? largeFont : [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    label.textColor = [UIColor labelColor];
    label.text = name;
    CGSize size = [label sizeThatFits:CGSizeMake(available, CGFLOAT_MAX)];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, available + 40.0, ceil(size.height) + 24.0)];
    label.frame = CGRectMake(20.0, 4.0, available, ceil(size.height));
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:label];
    self.tableView.tableHeaderView = header;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    static const void *kWidthKey = &kWidthKey;
    NSNumber *last = objc_getAssociatedObject(self, kWidthKey);
    if (!last || fabs(last.doubleValue - self.tableView.bounds.size.width) > 0.5) {
        objc_setAssociatedObject(self, kWidthKey, @(self.tableView.bounds.size.width), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self updateWrappedTitle];
    }
}

- (void)handleTweaksChanged:(NSNotification *)note {
    [self applyTweaks];
}

- (void)handleConfigChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        _actions = [[[RCConfigManager sharedManager] actionsForTrigger:_triggerKey] mutableCopy];
        [self.tableView reloadData];
    });
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    self.view.backgroundColor = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    [self.tableView reloadData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self applyTweaks];
        }
    }
}

// iOS 14 draws a dragged row as if in Light mode, so its dynamic text colours turned black and
// vanished on the dark card. There the row's colours are fixed to what they are now.
- (void)fixColorsForDragOnCell:(UITableViewCell *)cell {
    if (@available(iOS 15.0, *)) return;
    UITraitCollection *traits = self.traitCollection;
    for (UILabel *label in @[cell.textLabel ?: [UILabel new], cell.detailTextLabel ?: [UILabel new]]) {
        if (label.attributedText.length) {
            NSMutableAttributedString *text = [label.attributedText mutableCopy];
            [text enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(UIColor *color, NSRange range, BOOL *stop) {
                if (color) [text addAttribute:NSForegroundColorAttributeName value:[color resolvedColorWithTraitCollection:traits] range:range];
            }];
            label.attributedText = text;
        }
        if (label.textColor) label.textColor = [label.textColor resolvedColorWithTraitCollection:traits];
    }
    if (cell.imageView.tintColor) cell.imageView.tintColor = [cell.imageView.tintColor resolvedColorWithTraitCollection:traits];
    if (cell.accessoryView.tintColor) cell.accessoryView.tintColor = [cell.accessoryView.tintColor resolvedColorWithTraitCollection:traits];
}

- (void)runSequence {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    
    NSString *notificationName = [NSString stringWithFormat:@"%s%@", kSimulateNotificationPrefix, _triggerKey];
    
    // Slight delay to ensure haptic plays before the app is potentially obscured
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        notify_post([notificationName UTF8String]);
    });
}

- (void)editTriggerSettings {
    UIViewController *vc = nil;
    
    if ([_triggerKey hasPrefix:@"sched_"]) {
        vc = [[RCScheduledTriggerViewController alloc] initWithTriggerKey:_triggerKey];
    } else if ([_triggerKey hasPrefix:@"notif_"] || [_triggerKey hasPrefix:@"notify_"]) {
        vc = [[RCNotificationTriggerViewController alloc] initWithTriggerKey:_triggerKey];
    } else if ([_triggerKey hasPrefix:@"wifi_"]) {
        vc = [[RCWiFiTriggerViewController alloc] initWithTriggerKey:_triggerKey];
    } else if ([_triggerKey hasPrefix:@"bt_"]) {
        vc = [[RCBluetoothTriggerViewController alloc] initWithTriggerKey:_triggerKey];
    } else if ([_triggerKey hasPrefix:@"output_"]) {
        vc = [[RCAudioOutputTriggerViewController alloc] initWithTriggerKey:_triggerKey];
    } else if ([_triggerKey hasPrefix:@"app_launch_"] || [_triggerKey hasPrefix:@"app_exit_"]) {
        BOOL isExit = [_triggerKey hasPrefix:@"app_exit_"];
        NSString *prefix = isExit ? @"app_exit_" : @"app_launch_";
        RCAppPickerViewController *appVC = [[RCAppPickerViewController alloc] init];
        appVC.allowsMultipleApps = YES;
        NSArray *apps = [[RCConfigManager sharedManager] triggerDataForKey:_triggerKey][@"apps"];
        appVC.selectedBundleIds = ([apps isKindOfClass:[NSArray class]] && apps.count) ? apps : @[ [_triggerKey substringFromIndex:prefix.length] ];
        appVC.onAppsSelected = ^(NSArray<NSString *> *names, NSArray<NSString *> *bundleIds) {
            // The key follows the first app; the actions go with the trigger
            RCConfigManager *config = [RCConfigManager sharedManager];
            NSString *newKey = [config saveAppTriggerWithPrefix:prefix names:names bundleIds:bundleIds replacing:self.triggerKey];
            // This screen moves to the new key with the trigger. Left on the old one, its next
            // reload of the actions would read it and bring it back as an empty, disabled trigger.
            self.triggerKey = newKey;
            self.title = [config displayNameForTrigger:newKey];
            self.actions = [[config actionsForTrigger:newKey] mutableCopy];
            [self.tableView reloadData];
            [self updateWrappedTitle];
            // The picker closes itself once this returns (popping here too went back a screen too far)
        };
        vc = appVC;
    } else if ([_triggerKey hasPrefix:@"nfc_"]) {
        [self renameTrigger];
        return;
    }
    
    if (vc) {
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (void)renameTrigger {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Tag" 
                                                                   message:@"Enter a new name for this NFC tag:" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"My Tag";
        textField.text = self.title;
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newName = alert.textFields.firstObject.text;
        if (newName.length > 0) {
            [[RCConfigManager sharedManager] renameTrigger:self.triggerKey toName:newName];
            self.title = newName;
            
            // Update custom title view text
            if ([self.navigationItem.titleView isKindOfClass:[UILabel class]]) {
                ((UILabel *)self.navigationItem.titleView).text = newName;
                [self.navigationItem.titleView sizeToFit];
            }
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showHUDToast:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconName {
    NSString *safeTitle = [title stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    NSString *safeSubtitle = [subtitle stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    NSString *safeIcon = [iconName stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];

    NSString *cmd = [NSString stringWithFormat:@"toast \"%@\" \"%@\" \"%@\"", 
                     safeTitle ?: @"", 
                     safeSubtitle ?: @"", 
                     safeIcon ?: @""];
                     
    [[RCServerClient sharedClient] executeCommand:cmd completion:^(NSString * _Nullable output, NSError * _Nullable error) {
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                           message:subtitle
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:alert animated:YES completion:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }
    }];
}

- (void)exportActions {
    if (_actions.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Actions"
                                                                       message:@"There are no actions in this sequence to export."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_actions options:NSJSONWritingPrettyPrinted error:&error];
    if (error || !jsonData) {
        NSLog(@"Failed to serialize actions for export: %@", error);
        return;
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [UIPasteboard generalPasteboard].string = jsonString;
    
    [self showHUDToast:@"Copied to Clipboard" subtitle:nil icon:@"doc.on.doc"];
}

- (void)importActions {
    __weak typeof(self) weakSelf = self;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Actions"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        // Pre-fill with current sequence so user can see and clear it
        if (self.actions.count > 0) {
            NSError *serErr = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.actions options:NSJSONWritingPrettyPrinted error:&serErr];
            if (!serErr && jsonData) {
                textField.text = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }
        }
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!strongSelf || text.length == 0) return;
        
        NSArray *newCommands = nil;
        if ([text hasPrefix:@"["] && [text hasSuffix:@"]"]) {
            NSError *jsonErr = nil;
            id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&jsonErr];
            if (!jsonErr && [parsed isKindOfClass:[NSArray class]]) newCommands = parsed;
        }
        if (!newCommands) {
            NSMutableArray *lines = [NSMutableArray array];
            for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
                NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (line.length > 0) [lines addObject:line];
            }
            if (lines.count > 0) newCommands = lines;
        }
        NSMutableArray *validCmds = [NSMutableArray array];
        for (id cmd in newCommands) {
            if ([cmd isKindOfClass:[NSString class]]) {
                NSString *clean = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (clean.length > 0) [validCmds addObject:clean];
            } else if ([cmd isKindOfClass:[NSDictionary class]]) {
                [validCmds addObject:cmd];
            }
        }
        if (validCmds.count > 0) {
            [strongSelf.actions removeAllObjects];
            [strongSelf.actions addObjectsFromArray:validCmds];
            [strongSelf saveActions];
            [strongSelf.tableView reloadData];
            [strongSelf showHUDToast:@"Import Successful"
                           subtitle:[NSString stringWithFormat:@"Loaded %lu action(s).", (unsigned long)validCmds.count]
                               icon:@"square.and.arrow.down"];
        } else {
            [strongSelf showHUDToast:@"Import Failed" subtitle:@"No valid actions found." icon:@"exclamationmark.triangle"];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearAllActions {
    if (self.actions.count == 0) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear All Actions"
                                                                   message:@"Are you sure you want to clear all actions from this trigger?"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear All Actions" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self.actions removeAllObjects];
        [[RCConfigManager sharedManager] setActions:self.actions forTrigger:self.triggerKey];
        [self.tableView reloadData];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addAction {

    RCActionPickerViewController *picker = [[RCActionPickerViewController alloc] init];
    picker.onActionSelected = ^(NSString *action) {
        if ([action isEqualToString:@"__SHORTCUT_PICKER__"]) {
            // Present Shortcut Picker
            RCShortcutPickerViewController *vc = [[RCShortcutPickerViewController alloc] init];
            vc.showsSilentOption = YES;
            __weak RCShortcutPickerViewController *weakPicker = vc;
            vc.onShortcutSelected = ^(NSString *shortcutName) {
                [self.actions addObject:[RCConfigManager shortcutActionWithName:shortcutName silent:weakPicker.runSilently input:nil]];
                [self saveActions];
                [self.tableView reloadData];
                // Dismiss picker
                 [self dismissViewControllerAnimated:YES completion:nil];
            };
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });
            
        } else if ([action isEqualToString:@"__CUSTOM__"]) {
            // Show custom text input for command
            RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
            inputVC.promptTitle = @"Terminal Command";
            inputVC.promptMessage = @"Enter terminal command";
            inputVC.showRootToggle = YES;
            inputVC.variableActions = self.actions;
            inputVC.initialText = @"";
            
            __weak typeof(inputVC) weakInputVC = inputVC;
            inputVC.onComplete = ^(NSString *text) {
                if (text.length > 0) {
                    NSString *prefix = weakInputVC.isRootToggled ? @"root" : @"exec";
                    [self.actions addObject:[NSString stringWithFormat:@"%@ %@", prefix, text]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            };
            
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });

        } else if ([action isEqualToString:@"__CUSTOM_ROOT__"]) {
            // Re-use terminal command but fixed as root
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Root Command" 
                message:@"Enter terminal command (runs as root)" 
                preferredStyle:UIAlertControllerStyleAlert];
                
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"ldrestart";
                textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
                textField.autocorrectionType = UITextAutocorrectionTypeNo;
            }];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull alertAction) {
                NSString *input = alert.textFields.firstObject.text;
                if (input.length > 0) {
                    [self.actions addObject:[NSString stringWithFormat:@"root %@", input]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            }]];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:alert animated:YES completion:nil];
            });

        } else if ([action isEqualToString:@"__BT_CONNECT__"] || [action isEqualToString:@"__BT_DISCONNECT__"] || [action isEqualToString:@"__AIRPLAY_CONNECT__"]) {
            
            NSString *title = @"Device Name";
            NSString *prefix = @"";
            
            if ([action isEqualToString:@"__BT_CONNECT__"]) {
                title = @"Connect to Bluetooth";
                prefix = @"bt connect ";
            } else if ([action isEqualToString:@"__BT_DISCONNECT__"]) {
                title = @"Disconnect Bluetooth";
                prefix = @"bluetooth disconnect ";
            } else if ([action isEqualToString:@"__AIRPLAY_CONNECT__"]) {
                title = @"Connect AirPlay";
                prefix = @"airplay connect ";
            }

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                message:@"Enter exact device name" 
                preferredStyle:UIAlertControllerStyleAlert];
                
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"My Device";
            }];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull alertAction) {
                NSString *input = alert.textFields.firstObject.text;
                if (input.length > 0) {
                    [self.actions addObject:[NSString stringWithFormat:@"%@%@", prefix, input]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            }]];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:alert animated:YES completion:nil];
            });

        } else if ([action isEqualToString:@"__STOP_TRIGGER__"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self pickTriggerToStop:^(NSString *key) {
                    [self.actions addObject:[@"stop trigger " stringByAppendingString:key]];
                    [self saveActions];
                    [self.tableView reloadData];
                }];
            });
        } else if ([action isEqualToString:@"__DELAY__"]) {
            [self presentDelayForIndex:NSNotFound current:nil after:0.5];
        } else if ([action isEqualToString:@"__OPEN_APP__"]) {
            RCAppPickerViewController *appPicker = [[RCAppPickerViewController alloc] init];
            appPicker.onAppSelected = ^(NSString *name, NSString *bundleId) {
                // Save as "uiopen <bundleId>"
                [self.actions addObject:[NSString stringWithFormat:@"uiopen %@", bundleId]];
                [self saveActions];
                [self.tableView reloadData];
            };
            
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:appPicker];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });
        } else if ([action isEqualToString:@"__KILL_APP__"]) {
            RCAppPickerViewController *appPicker = [[RCAppPickerViewController alloc] init];
            appPicker.onAppSelected = ^(NSString *name, NSString *bundleId) {
                // Save as "kill <bundleId>"
                [self.actions addObject:[NSString stringWithFormat:@"kill %@", bundleId]];
                [self saveActions];
                [self.tableView reloadData];
            };
            
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:appPicker];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });
        } else if ([action isEqualToString:@"__IF_CONDITION__"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentIfConditionPickerForIndex:NSNotFound];
            });
        } else if ([action isEqualToString:@"__REPEAT__"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentRepeatCountForIndex:NSNotFound];
            });
        } else if ([action isEqualToString:@"__EXIT_REPEAT__"]) {
            [self.actions addObject:@{ @"type": @"exit_repeat" }];
            [self saveActions];
            [self.tableView reloadData];
        } else if ([action isEqualToString:@"__WAIT_UNTIL__"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentIfConditionPickerForIndex:NSNotFound insertIndex:NSNotFound type:@"wait_until"];
            });
        } else if ([action isEqualToString:@"__SET_VARIABLE__"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentSetVariable:nil existingIndex:NSNotFound];
            });
        } else if ([action isEqualToString:@"__REPEAT_WHILE__"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentIfConditionPickerForIndex:NSNotFound insertIndex:NSNotFound type:@"repeat_while"];
            });
        } else if ([action isEqualToString:@"__LUA_SCRIPT__"]) {
            RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
            inputVC.promptTitle = @"Lua Script";
            inputVC.promptMessage = @"Enter Lua code to execute";
            inputVC.initialText = @"";
            inputVC.onComplete = ^(NSString *text) {
                if (text.length > 0) {
                    [self.actions addObject:[NSString stringWithFormat:@"Lua %@", text]];
                    [self saveActions];
                    [self.tableView reloadData];
                }
            };
            
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentViewController:nav animated:YES completion:nil];
            });
        } else if ([action isEqualToString:@"__TOAST__"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentToastEditorForIndex:NSNotFound];
            });
        } else if ([self levelPrefixForCommand:action]) {
            [self presentLevelActionForCommand:action index:NSNotFound after:0.5];
        } else {
            [self.actions addObject:action];
            [self saveActions];
            [self.tableView reloadData];
        }
    };
    
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)saveActions {
    [[RCConfigManager sharedManager] setActions:_actions forTrigger:_triggerKey];
}

- (NSString *)actionTypeForItem:(id)item {
    if (![item isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return [[((NSDictionary *)item)[@"type"] description] lowercaseString];
}

- (BOOL)isIfActionItem:(id)item {
    return [[self actionTypeForItem:item] isEqualToString:@"if"];
}

- (BOOL)isElseActionItem:(id)item {
    return [[self actionTypeForItem:item] isEqualToString:@"else"];
}

- (BOOL)isElseIfActionItem:(id)item {
    return [[self actionTypeForItem:item] isEqualToString:@"else_if"];
}

- (BOOL)isEndIfActionItem:(id)item {
    NSString *type = [self actionTypeForItem:item];
    return [type isEqualToString:@"end_if"] || [type isEqualToString:@"end"];
}

// Repeat blocks: Repeat (a count) or Repeat While (a condition) ... End Repeat
- (BOOL)isRepeatActionItem:(id)item {
    NSString *type = [self actionTypeForItem:item];
    return [type isEqualToString:@"repeat"] || [type isEqualToString:@"repeat_while"];
}

- (BOOL)isRepeatWhileActionItem:(id)item {
    return [[self actionTypeForItem:item] isEqualToString:@"repeat_while"];
}

- (BOOL)isEndRepeatActionItem:(id)item {
    return [[self actionTypeForItem:item] isEqualToString:@"end_repeat"];
}

// A block's first and last rows, If or Repeat: for nesting, moving and deleting whole blocks
- (BOOL)isBlockStartItem:(id)item {
    return [self isIfActionItem:item] || [self isRepeatActionItem:item];
}

- (BOOL)isBlockEndItem:(id)item {
    return [self isEndIfActionItem:item] || [self isEndRepeatActionItem:item];
}

- (NSInteger)matchingElseIndexForIfAtIndex:(NSInteger)startIndex {
    if (startIndex < 0 || startIndex >= (NSInteger)self.actions.count) {
        return NSNotFound;
    }
    if (![self isIfActionItem:self.actions[startIndex]]) {
        return NSNotFound;
    }
    
    NSInteger depth = 0;
    for (NSInteger idx = startIndex; idx < (NSInteger)self.actions.count; idx++) {
        id item = self.actions[idx];
        if ([self isIfActionItem:item]) {
            depth++;
        } else if ([self isEndIfActionItem:item]) {
            depth--;
            if (depth == 0) return NSNotFound;
        } else if ([self isElseActionItem:item]) {
            if (depth == 1) return idx;
        }
    }
    return NSNotFound;
}

- (NSInteger)matchingEndIndexForIfAtIndex:(NSInteger)startIndex {
    if (startIndex < 0 || startIndex >= (NSInteger)self.actions.count) {
        return NSNotFound;
    }
    if (![self isBlockStartItem:self.actions[startIndex]]) {
        return NSNotFound;
    }
    
    NSInteger depth = 0;
    for (NSInteger idx = startIndex; idx < (NSInteger)self.actions.count; idx++) {
        id item = self.actions[idx];
        if ([self isBlockStartItem:item]) {
            depth++;
        } else if ([self isBlockEndItem:item]) {
            depth--;
            if (depth == 0) {
                return idx;
            }
        }
    }
    return NSNotFound;
}

- (NSInteger)matchingIfIndexForEndAtIndex:(NSInteger)endIndex {
    if (endIndex < 0 || endIndex >= (NSInteger)self.actions.count) {
        return NSNotFound;
    }
    if (![self isBlockEndItem:self.actions[endIndex]]) {
        return NSNotFound;
    }
    
    NSInteger depth = 0;
    for (NSInteger idx = endIndex; idx >= 0; idx--) {
        id item = self.actions[idx];
        if ([self isBlockEndItem:item]) {
            depth++;
        } else if ([self isBlockStartItem:item]) {
            depth--;
            if (depth == 0) {
                return idx;
            }
        }
    }
    return NSNotFound;
}

- (NSRange)ifBlockRangeForIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.actions.count) {
        return NSMakeRange(NSNotFound, 0);
    }
    
    id item = self.actions[index];
    if ([self isBlockStartItem:item]) {
        NSInteger endIndex = [self matchingEndIndexForIfAtIndex:index];
        if (endIndex != NSNotFound) {
            return NSMakeRange(index, endIndex - index + 1);
        }
    } else if ([self isBlockEndItem:item]) {
        NSInteger startIndex = [self matchingIfIndexForEndAtIndex:index];
        if (startIndex != NSNotFound) {
            return NSMakeRange(startIndex, index - startIndex + 1);
        }
    }
    
    return NSMakeRange(index, 1);
}

- (NSInteger)indentationLevelForRow:(NSInteger)row {
    NSInteger depth = 0;
    for (NSInteger idx = 0; idx < row; idx++) {
        id item = self.actions[idx];
        if ([self isBlockStartItem:item]) {
            depth++;
        } else if ([self isBlockEndItem:item]) {
            depth = MAX(depth - 1, 0);
        }
    }
    
    id current = self.actions[row];
    if ([self isBlockEndItem:current] || [self isElseActionItem:current] || [self isElseIfActionItem:current]) {
        return MAX(depth - 1, 0);
    }
    return depth;
}

// The vibration conditions as this iOS version's Settings shows them: iOS 17's one Haptics
// setting in place of the two switches, or the switches by their name for this version
static NSArray<NSDictionary *> *RCAdaptVibrationConditions(NSArray<NSDictionary *> *definitions) {
    NSMutableArray *adapted = [NSMutableArray array];
    for (NSDictionary *def in definitions) {
        BOOL silent = [def[@"key"] isEqualToString:@"silent_vibration"], ring = [def[@"key"] isEqualToString:@"ring_vibration"];
        if (!silent && !ring) { [adapted addObject:def]; continue; }
        if ([RCConfigManager usesHapticsMenu]) {
            if (silent) [adapted addObject:@{
                @"key": @"haptics",
                @"title": @"Haptics",
                @"icon": @"iphone.radiowaves.left.and.right",
                @"section": def[@"section"] ?: @"Sound",
                @"values": @[
                    @{ @"value": @"ALWAYS", @"title": @"Always Play" },
                    @{ @"value": @"SILENT_ONLY", @"title": @"Play in Silent Mode" },
                    @{ @"value": @"RING_ONLY", @"title": @"Don't Play in Silent Mode" },
                    @{ @"value": @"NEVER", @"title": @"Never Play" }
                ]
            }];
            continue;
        }
        NSMutableDictionary *renamed = [def mutableCopy];
        renamed[@"title"] = [RCConfigManager vibrationNameForSilentMode:silent];
        [adapted addObject:renamed];
    }
    return adapted;
}

- (NSArray<NSDictionary *> *)ifConditionDefinitions {
    return RCAdaptVibrationConditions(@[
        @{
            @"key": @"time_between",
            @"title": @"Time of Day (Between)",
            @"icon": @"clock",
            @"section": @"Time"
        },
        @{
            @"key": @"day_of_week",
            @"title": @"Day of the Week",
            @"icon": @"calendar",
            @"section": @"Time",
            @"values": @[
                @{ @"value": @"WEEKDAYS", @"title": @"Weekdays" },
                @{ @"value": @"WEEKENDS", @"title": @"Weekends" },
                @{ @"value": @"MON", @"title": @"Monday" },
                @{ @"value": @"TUE", @"title": @"Tuesday" },
                @{ @"value": @"WED", @"title": @"Wednesday" },
                @{ @"value": @"THU", @"title": @"Thursday" },
                @{ @"value": @"FRI", @"title": @"Friday" },
                @{ @"value": @"SAT", @"title": @"Saturday" },
                @{ @"value": @"SUN", @"title": @"Sunday" }
            ]
        },
        @{
            @"key": @"lock",
            @"title": @"Lock Status",
            @"icon": @"lock.fill",
            @"section": @"Device",
            @"values": @[
                @{ @"value": @"LOCKED", @"title": @"Locked" },
                @{ @"value": @"UNLOCKED", @"title": @"Unlocked" }
            ]
        },
        @{
            @"key": @"autolock",
            @"title": @"Auto-Lock",
            @"values": @[
                @{ @"value": @"30S", @"title": @"30 Seconds" },
                @{ @"value": @"1M", @"title": @"1 Minute" },
                @{ @"value": @"2M", @"title": @"2 Minutes" },
                @{ @"value": @"3M", @"title": @"3 Minutes" },
                @{ @"value": @"4M", @"title": @"4 Minutes" },
                @{ @"value": @"5M", @"title": @"5 Minutes" },
                @{ @"value": @"NEVER", @"title": @"Never" }
            ]
        },
        @{
            @"key": @"player",
            @"title": @"Player Status",
            @"icon": @"play.circle",
            @"section": @"Sound",
            @"values": @[
                @{ @"value": @"PLAYING", @"title": @"Playing" },
                @{ @"value": @"PAUSED", @"title": @"Paused" },
                @{ @"value": @"STOPPED", @"title": @"Stopped" }
            ]
        },
        @{
            @"key": @"wifi",
            @"title": @"Wi-Fi",
            @"icon": @"wifi",
            @"section": @"Connectivity",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"wifi_network",
            @"title": @"Wi-Fi Network",
            @"icon": @"network",
            @"section": @"Connectivity",
            @"input": @"text",
            @"placeholder": @"Network name"
        },
        @{
            @"key": @"bluetooth",
            @"title": @"Bluetooth",
            @"icon": @"dot.radiowaves.left.and.right",
            @"section": @"Connectivity",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"bt_device",
            @"title": @"Bluetooth Device Connected",
            @"icon": @"headphones",
            @"section": @"Connectivity",
            @"input": @"text",
            @"placeholder": @"Device name"
        },
        @{
            @"key": @"carplay",
            @"title": @"CarPlay",
            @"icon": @"car.fill",
            @"section": @"Connectivity",
            @"values": @[
                @{ @"value": @"CONNECTED", @"title": @"Connected" },
                @{ @"value": @"NOT_CONNECTED", @"title": @"Not Connected" }
            ]
        },
        @{
            @"key": @"cellular",
            @"title": @"Cellular Data",
            @"icon": @"antenna.radiowaves.left.and.right",
            @"section": @"Connectivity",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"location",
            @"title": @"Location Services",
            @"icon": @"location.fill",
            @"section": @"Connectivity",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"airplane",
            @"title": @"Airplane Mode",
            @"icon": @"airplane",
            @"section": @"Connectivity",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"dnd",
            @"title": @"Do Not Disturb",
            @"icon": @"moon.fill",
            @"section": @"Sound",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            // Values: Off, Any Focus, the Focus modes (the condition picker lists them)
            @"key": @"focus",
            @"title": @"Focus",
            @"icon": @"moon.circle",
            @"section": @"Sound"
        },
        @{
            @"key": @"lpm",
            @"title": @"Low Power Mode",
            @"icon": @"battery.25",
            @"section": @"Power",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"ringer",
            @"title": @"Ringer Switch",
            @"icon": @"bell.fill",
            @"section": @"Sound",
            @"values": @[
                @{ @"value": @"SILENT", @"title": @"Silent" },
                @{ @"value": @"RING", @"title": @"Ring" }
            ]
        },
        @{
            @"key": @"silent_vibration",
            @"title": @"Silent Vibration",
            @"icon": @"bell.slash",
            @"section": @"Sound",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"ring_vibration",
            @"title": @"Ring Vibration",
            @"icon": @"bell",
            @"section": @"Sound",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"orientation",
            @"title": @"Orientation",
            @"icon": @"rotate.right",
            @"section": @"Device",
            @"values": @[
                @{ @"value": @"PORTRAIT", @"title": @"Portrait" },
                @{ @"value": @"LANDSCAPE", @"title": @"Landscape" }
            ]
        },
        @{
            @"key": @"rotation_lock",
            @"title": @"Rotation Lock",
            @"icon": @"lock.rotation",
            @"section": @"Device",
            @"values": @[
                @{ @"value": @"LOCKED", @"title": @"Locked" },
                @{ @"value": @"UNLOCKED", @"title": @"Unlocked" }
            ]
        },
        @{
            @"key": @"appearance",
            @"title": @"Appearance",
            @"icon": @"circle.lefthalf.fill",
            @"section": @"Device",
            @"values": @[
                @{ @"value": @"DARK", @"title": @"Dark" },
                @{ @"value": @"LIGHT", @"title": @"Light" }
            ]
        },
        @{
            @"key": @"flashlight",
            @"title": @"Flashlight",
            @"icon": @"flashlight.on.fill",
            @"section": @"Device",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        },
        @{
            @"key": @"screenrecord",
            @"title": @"Screen Recording",
            @"icon": @"record.circle",
            @"section": @"Device",
            @"values": @[
                @{ @"value": @"ACTIVE", @"title": @"Recording" },
                @{ @"value": @"INACTIVE", @"title": @"Not Recording" }
            ]
        },
        @{
            @"key": @"charging",
            @"title": @"Charging",
            @"icon": @"bolt.fill",
            @"section": @"Power",
            @"values": @[
                @{ @"value": @"CHARGING", @"title": @"Charging" },
                @{ @"value": @"NOT_CHARGING", @"title": @"Not Charging" }
            ]
        },
        @{
            @"key": @"battery",
            @"title": @"Battery Level",
            @"icon": @"battery.100",
            @"section": @"Power",
            @"input": @"threshold"
        },
        @{
            @"key": @"volume",
            @"title": @"Volume Level",
            @"icon": @"speaker.wave.2.fill",
            @"section": @"Sound",
            @"input": @"threshold"
        },
        @{
            @"key": @"front_app",
            @"title": @"Front Application",
            @"icon": @"square.grid.2x2",
            @"section": @"Device"
        },
        @{
            @"key": @"proximity",
            @"title": @"Proximity Sensor",
            @"icon": @"ear",
            @"section": @"Device",
            @"values": @[
                @{ @"value": @"NEAR", @"title": @"Near" },
                @{ @"value": @"FAR", @"title": @"Far" }
            ]
        },
        @{
            @"key": @"screen",
            @"title": @"Screen",
            @"icon": @"iphone",
            @"section": @"Device",
            @"values": @[
                @{ @"value": @"ON", @"title": @"On" },
                @{ @"value": @"OFF", @"title": @"Off" }
            ]
        }
   ,
        @{
            // A variable from Set Variable: name, comparison and value (the editor's prompts)
            @"key": @"variable",
            @"title": @"Variable",
            @"icon": @"x.squareroot",
            @"section": @"Variables",
            @"input": @"variable"
        }
    ]);
}

- (void)configurePopoverSourceForAlert:(UIAlertController *)alert {
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
}

- (NSDictionary *)buildIfActionWithCondition:(NSDictionary *)condition expectedValue:(NSDictionary *)expectedValue {
    return @{
        @"type": @"if",
        @"conditionKey": condition[@"key"] ?: @"",
        @"conditionTitle": condition[@"title"] ?: @"Condition",
        @"expectedValue": expectedValue[@"value"] ?: @"",
        @"expectedTitle": expectedValue[@"title"] ?: @"Value"
    };
}

// Puts an If / Else If row in place: replaces the one being edited, or inserts it
// at insertIndex or the end. Only a new top-level If owns an End If marker; an
// Else If belongs to the existing block and must not create another terminator.
- (void)applyIfAction:(NSDictionary *)ifAction existingIndex:(NSInteger)existingIndex insertIndex:(NSInteger)insertIndex {
    // An edited condition stays disabled if it was
    if (existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count) {
        id old = self.actions[existingIndex];
        if ([old isKindOfClass:[NSDictionary class]] && old[@"disabled"]) {
            NSMutableDictionary *kept = [ifAction mutableCopy];
            kept[@"disabled"] = old[@"disabled"];
            ifAction = kept;
        }
    }
    // Wait Until: one row, no End; a new one asks for its time limit, an edited one keeps it
    if ([[ifAction[@"type"] description].lowercaseString isEqualToString:@"wait_until"]) {
        BOOL editing = existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count;
        if (editing) {
            NSMutableDictionary *item = [ifAction mutableCopy];
            id old = self.actions[existingIndex];
            item[@"timeout"] = ([old isKindOfClass:[NSDictionary class]] && old[@"timeout"]) ? old[@"timeout"] : @60;
            self.actions[existingIndex] = item;
            [self saveActions];
            [self.tableView reloadData];
        } else {
            [self presentWaitLimitForAction:ifAction existingIndex:NSNotFound insertIndex:insertIndex];
        }
        return;
    }
    BOOL isElseIf = [[ifAction[@"type"] description].lowercaseString isEqualToString:@"else_if"];
    // A Repeat While block ends with End Repeat (same condition fields as If)
    NSDictionary *endMarker = [self isRepeatActionItem:ifAction] ? @{ @"type": @"end_repeat" } : @{ @"type": @"end_if" };
    if (existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count) {
        self.actions[existingIndex] = ifAction;
    } else if (insertIndex != NSNotFound && insertIndex >= 0 && insertIndex <= (NSInteger)self.actions.count) {
        [self.actions insertObject:ifAction atIndex:insertIndex];
        if (!isElseIf) {
            [self.actions insertObject:endMarker atIndex:insertIndex + 1];
        }
    } else {
        [self.actions addObject:ifAction];
        if (!isElseIf) {
            [self.actions addObject:endMarker];
        }
    }
    [self saveActions];
    BOOL newLoop = [self isRepeatActionItem:ifAction] && !(existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count);
    if (newLoop) [self defaultToRestartForLoop];
    [self.tableView reloadData];
}

// The value of the block being edited, if it's for this condition (to prefill inputs)
- (NSString *)existingExpectedValueForCondition:(NSString *)key index:(NSInteger)existingIndex {
    if (existingIndex == NSNotFound || existingIndex < 0 || existingIndex >= (NSInteger)self.actions.count) return nil;
    NSDictionary *act = self.actions[existingIndex];
    if (![act isKindOfClass:[NSDictionary class]] || ![act[@"conditionKey"] isEqualToString:key]) return nil;
    return act[@"expectedValue"];
}

- (void)presentIfValuePickerForCondition:(NSDictionary *)condition existingIndex:(NSInteger)existingIndex insertIndex:(NSInteger)insertIndex type:(NSString *)type {
    NSString *actionType = type ?: @"if";

    // Text: a name to match (Wi-Fi network, Bluetooth device), case-insensitive
    if ([condition[@"input"] isEqualToString:@"text"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:condition[@"title"]
                                                                       message:@"Matches the exact name (case doesn't matter)."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        NSString *existing = [self existingExpectedValueForCondition:condition[@"key"] index:existingIndex];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = condition[@"placeholder"];
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            textField.text = existing;
        }];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (name.length == 0) return;
            [weakSelf applyIfAction:@{ @"type": actionType, @"conditionKey": condition[@"key"], @"conditionTitle": condition[@"title"],
                                       @"expectedValue": name, @"expectedTitle": name }
                      existingIndex:existingIndex insertIndex:insertIndex];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self configurePopoverSourceForAlert:alert];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // Variable: how to compare, then the name (and the value to compare with)
    if ([condition[@"input"] isEqualToString:@"variable"]) {
        [self presentVariableConditionForType:actionType existingIndex:existingIndex insertIndex:insertIndex];
        return;
    }

    // Threshold: above / below a percentage (battery, volume)
    if ([condition[@"input"] isEqualToString:@"threshold"]) {
        // The one being edited, when it's the same condition: its direction and number
        NSString *current = nil;
        NSInteger choice = 0;
        if (existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count) {
            id item = self.actions[existingIndex];
            if ([item isKindOfClass:[NSDictionary class]] && [[item[@"conditionKey"] description] isEqualToString:condition[@"key"]]) {
                NSString *raw = [[item[@"expectedValue"] description] uppercaseString];
                if ([raw hasPrefix:@"BELOW "]) choice = 1;
                NSRange space = [raw rangeOfString:@" "];
                if (space.location != NSNotFound) current = [[item[@"expectedValue"] description] substringFromIndex:space.location + 1];
            }
        }
        RCNumberSettingViewController *editor = [[RCNumberSettingViewController alloc] initWithTitle:condition[@"title"] label:@"Percent" value:current otherActions:self.actions];
        editor.choices = @[@"Above", @"Below"];
        editor.selectedChoice = choice;
        editor.placeholder = @"50";
        editor.maximum = 100;
        editor.note = @"True when the level is above or below this percentage.";
        editor.allowsRound = [self roundAvailableAtIndex:existingIndex != NSNotFound ? existingIndex : insertIndex];
        __weak typeof(self) weakSelf = self;
        editor.onSave = ^(id typed, NSInteger picked) {
            // A variable stays as typed ("ABOVE {limit}"); the tweak fills it in when it checks
            NSString *word = picked == 1 ? @"Below" : @"Above";
            NSString *value = [typed description];
            [weakSelf applyIfAction:@{ @"type": actionType, @"conditionKey": condition[@"key"], @"conditionTitle": condition[@"title"],
                                       @"expectedValue": [NSString stringWithFormat:@"%@ %@", word.uppercaseString, value],
                                       @"expectedTitle": [NSString stringWithFormat:@"%@ %@%%", word.lowercaseString, value] }
                      existingIndex:existingIndex insertIndex:insertIndex];
        };
        [self presentNumberSetting:editor after:0.35];
        return;
    }
    
    if ([condition[@"key"] isEqualToString:@"time_between"]) {
        NSString *current = nil;
        if (existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count) {
            id item = self.actions[existingIndex];
            if ([item isKindOfClass:[NSDictionary class]] && [[item[@"conditionKey"] description] isEqualToString:@"time_between"]) current = [item[@"expectedValue"] description];
        }
        RCTimeRangeViewController *editor = [[RCTimeRangeViewController alloc] initWithRange:current];
        __weak typeof(self) weakSelf = self;
        editor.onSave = ^(NSString *value, NSString *title) {
            [weakSelf applyIfAction:@{ @"type": actionType, @"conditionKey": @"time_between", @"conditionTitle": @"Time of Day",
                                       @"expectedValue": value, @"expectedTitle": title }
                      existingIndex:existingIndex insertIndex:insertIndex];
        };
        [self presentNumberSetting:editor after:0.35];
        return;
    }
    
    if ([condition[@"key"] isEqualToString:@"front_app"]) {
        RCAppPickerViewController *appPicker = [[RCAppPickerViewController alloc] init];
        __weak typeof(self) weakSelf = self;
        appPicker.onAppSelected = ^(NSString *name, NSString *bundleId) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            NSDictionary *ifAction = @{
                @"type": actionType,
                @"conditionKey": @"front_app",
                @"conditionTitle": @"Front Application",
                @"expectedValue": bundleId,
                @"expectedTitle": name
            };
            
            [strongSelf applyIfAction:ifAction existingIndex:existingIndex insertIndex:insertIndex];
            [strongSelf.navigationController popToViewController:strongSelf animated:YES];
        };
        appPicker.suppressAutoPop = YES; // back to this editor, past the condition picker
        [self.navigationController pushViewController:appPicker animated:YES];
        return;
    }

    NSArray *values = condition[@"values"] ?: @[];
    NSString *title = [NSString stringWithFormat:@"%@ is...", condition[@"title"] ?: @"Condition"];
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:title
                                                                     message:nil
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *value in values) {
        [picker addAction:[UIAlertAction actionWithTitle:value[@"title"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            NSDictionary *ifAction = @{
                @"type": actionType,
                @"conditionKey": condition[@"key"] ?: @"",
                @"conditionTitle": condition[@"title"] ?: @"Condition",
                @"expectedValue": value[@"value"] ?: @"",
                @"expectedTitle": value[@"title"] ?: @"Value"
            };
            [strongSelf applyIfAction:ifAction existingIndex:existingIndex insertIndex:insertIndex];
        }]];
    }
    
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverSourceForAlert:picker];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)presentIfConditionPickerForIndex:(NSInteger)existingIndex insertIndex:(NSInteger)insertIndex type:(NSString *)type {
    NSString *title = [type isEqualToString:@"else_if"] ? @"Else If Condition" : [type isEqualToString:@"repeat_while"] ? @"Repeat While" : [type isEqualToString:@"wait_until"] ? @"Wait Until" : @"If Condition";
    NSDictionary *existing = nil;
    if (existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count && [self.actions[existingIndex] isKindOfClass:[NSDictionary class]]) {
        existing = self.actions[existingIndex];
    }
    NSArray *conditions = [self ifConditionDefinitions];
    if (![RCConfigManager supportsFocus]) {
        conditions = [conditions filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key != 'focus'"]];
    }
    RCConditionPickerViewController *picker = [[RCConditionPickerViewController alloc] initWithConditions:conditions title:title existing:existing];
    __weak typeof(self) weakSelf = self;
    NSString *actionType = type ?: @"if";
    picker.onValueSelected = ^(NSDictionary *condition, NSDictionary *value) {
        [weakSelf applyIfAction:@{ @"type": actionType, @"conditionKey": condition[@"key"] ?: @"", @"conditionTitle": condition[@"title"] ?: @"Condition",
                                   @"expectedValue": value[@"value"] ?: @"", @"expectedTitle": value[@"title"] ?: @"Value" }
                  existingIndex:existingIndex insertIndex:insertIndex];
    };
    // Time range, names, levels, apps: the editor's own prompts
    picker.onInputRequested = ^(NSDictionary *condition) {
        [weakSelf presentIfValuePickerForCondition:condition existingIndex:existingIndex insertIndex:insertIndex type:type];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

// Wait Until's time limit, in seconds: for a new Wait Until (then added) or the one at existingIndex
- (void)presentWaitLimitForAction:(NSDictionary *)waitAction existingIndex:(NSInteger)existingIndex insertIndex:(NSInteger)insertIndex {
    RCNumberSettingViewController *editor = [[RCNumberSettingViewController alloc] initWithTitle:@"Time Limit" label:@"Seconds"
                                                                                             value:[waitAction[@"timeout"] description] ?: @"60" otherActions:self.actions];
    editor.placeholder = @"60";
    editor.minimum = 1;
    editor.maximum = 86400;
    editor.note = @"The longest to wait, up to a day. Then the actions go on anyway.";
    editor.allowsRound = [self roundAvailableAtIndex:existingIndex != NSNotFound ? existingIndex : insertIndex];
    editor.saveTitle = existingIndex == NSNotFound ? @"Add" : @"Save";
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(id seconds, __unused NSInteger choice) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSMutableDictionary *item = [waitAction mutableCopy];
        item[@"timeout"] = seconds;
        if (existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)strongSelf.actions.count) {
            strongSelf.actions[existingIndex] = item;
        } else if (insertIndex != NSNotFound && insertIndex >= 0 && insertIndex <= (NSInteger)strongSelf.actions.count) {
            [strongSelf.actions insertObject:item atIndex:insertIndex];
        } else {
            [strongSelf.actions addObject:item];
        }
        [strongSelf saveActions];
        [strongSelf.tableView reloadData];
    };
    // After the condition picker has closed (it may still be going back)
    [self presentNumberSetting:editor after:0.35];
}

// A number setting's screen, as a half-height sheet where it can be
- (void)presentNumberSetting:(UIViewController *)editor after:(NSTimeInterval)delay {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent]];
        sheet.prefersGrabberVisible = YES;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf presentViewController:nav animated:YES completion:nil];
    });
}

// Whether an action at index (NSNotFound: the end) sits inside a Repeat or Repeat While, where {round} has a value
- (BOOL)roundAvailableAtIndex:(NSInteger)index {
    NSInteger end = index == NSNotFound ? (NSInteger)self.actions.count : MAX(0, MIN(index, (NSInteger)self.actions.count));
    NSInteger depth = 0;
    for (NSInteger i = 0; i < end; i++) {
        id item = self.actions[i];
        if ([self isRepeatActionItem:item]) depth++;
        else if ([[self actionTypeForItem:item] isEqualToString:@"end_repeat"]) depth = MAX(0, depth - 1);
    }
    return depth > 0;
}

// Puts a command at index (keeping any settings around it), or adds it at the end
- (void)storeCommand:(NSString *)command atIndex:(NSInteger)index {
    if (index != NSNotFound && index >= 0 && index < (NSInteger)self.actions.count) {
        id original = self.actions[index];
        if ([original isKindOfClass:[NSDictionary class]] && [original[@"command"] isKindOfClass:[NSString class]]) {
            NSMutableDictionary *d = [original mutableCopy];
            d[@"command"] = command;
            self.actions[index] = d;
        } else {
            self.actions[index] = command;
        }
    } else {
        [self.actions addObject:command];
    }
    [self saveActions];
    [self.tableView reloadData];
}

// Volume, Ringer Volume and Brightness: their command's prefix, for the picker's item or a stored command
- (NSString *)levelPrefixForCommand:(NSString *)command {
    if (![command isKindOfClass:[NSString class]]) return nil;
    NSDictionary *placeholders = @{ @"__SET_VOLUME__": @"set-vol ", @"__SET_RINGER_VOLUME__": @"ringer volume ", @"__SET_BRIGHTNESS__": @"brightness " };
    if (placeholders[command]) return placeholders[command];
    // A stored command: the prefix, then a number or a variable
    static NSRegularExpression *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+(\\.\\d+)?|\\{[A-Za-z_][A-Za-z0-9_]*\\})$" options:0 error:nil]; });
    for (NSString *prefix in placeholders.allValues) {
        if (![command hasPrefix:prefix]) continue;
        NSString *rest = [[command substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([value firstMatchInString:rest options:0 range:NSMakeRange(0, rest.length)]) return prefix;
    }
    return nil;
}

// A level action on the number panel: 0 to 100, or a variable. Edits the action at index, or adds one at the end.
- (void)presentLevelActionForCommand:(NSString *)command index:(NSInteger)index after:(NSTimeInterval)delay {
    NSString *prefix = [self levelPrefixForCommand:command];
    if (!prefix) return;
    BOOL editing = index != NSNotFound && index >= 0 && index < (NSInteger)self.actions.count;
    NSString *current = [command hasPrefix:prefix] ? [[command substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : nil;
    NSString *title = [prefix isEqualToString:@"set-vol "] ? @"Volume" : [prefix isEqualToString:@"ringer volume "] ? @"Ringer Volume" : @"Brightness";
    NSString *note = [prefix isEqualToString:@"set-vol "] ? @"The media volume to set, from 0 to 100."
                   : [prefix isEqualToString:@"ringer volume "] ? @"The ringer and alerts volume to set, from 0 to 100."
                   : @"The screen brightness to set, from 0 to 100.";
    RCNumberSettingViewController *editor = [[RCNumberSettingViewController alloc] initWithTitle:title label:@"Percent" value:current otherActions:self.actions];
    editor.placeholder = @"50";
    editor.maximum = 100;
    editor.note = note;
    editor.allowsRound = [self roundAvailableAtIndex:editing ? index : NSNotFound];
    editor.saveTitle = editing ? @"Save" : @"Add";
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(id value, __unused NSInteger choice) {
        NSString *text = [value isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%ld", (long)[value integerValue]] : [value description];
        [weakSelf storeCommand:[prefix stringByAppendingString:text] atIndex:editing ? index : NSNotFound];
    };
    [self presentNumberSetting:editor after:delay];
}

// Toast: its own screen. Edits the toast at index, or adds one at the end.
- (void)presentToastEditorForIndex:(NSInteger)index {
    BOOL editing = index != NSNotFound && index >= 0 && index < (NSInteger)self.actions.count;
    id original = editing ? self.actions[index] : nil;
    NSString *current = [original isKindOfClass:[NSDictionary class]] ? [original[@"command"] description] : ([original isKindOfClass:[NSString class]] ? original : nil);
    RCToastEditorViewController *editor = [[RCToastEditorViewController alloc] initWithCommand:current otherActions:self.actions];
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(NSString *command) {
        [weakSelf storeCommand:command atIndex:editing ? index : NSNotFound]; // keeps any settings around it
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    [self presentViewController:nav animated:YES completion:nil];
}

// Delay: seconds, or a variable. Edits the delay at index, or adds one at the end.
- (void)presentDelayForIndex:(NSInteger)index current:(NSString *)current after:(NSTimeInterval)delay {
    BOOL editing = index != NSNotFound && index >= 0 && index < (NSInteger)self.actions.count;
    RCNumberSettingViewController *editor = [[RCNumberSettingViewController alloc] initWithTitle:@"Delay" label:@"Seconds" value:current otherActions:self.actions];
    editor.placeholder = @"1";
    editor.allowsDecimals = YES;
    editor.maximum = 86400;
    editor.note = @"How long to wait before the next action, up to a day.";
    editor.allowsRound = [self roundAvailableAtIndex:editing ? index : NSNotFound];
    editor.saveTitle = editing ? @"Save" : @"Add";
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(id seconds, __unused NSInteger choice) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *text = [seconds isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%g", [seconds doubleValue]] : seconds;
        [strongSelf storeCommand:[@"delay " stringByAppendingString:text] atIndex:editing ? index : NSNotFound];
    };
    [self presentNumberSetting:editor after:delay];
}

// The Variable condition for an If, Else If, Repeat While or Wait Until: its own screen
- (void)presentVariableConditionForType:(NSString *)actionType existingIndex:(NSInteger)existingIndex insertIndex:(NSInteger)insertIndex {
    NSDictionary *existing = nil;
    if (existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count) {
        id item = self.actions[existingIndex];
        if ([item isKindOfClass:[NSDictionary class]] && [[item[@"conditionKey"] description] isEqualToString:@"variable"]) existing = item;
    }
    RCVariableConditionViewController *editor = [[RCVariableConditionViewController alloc] initWithCondition:existing otherActions:self.actions];
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(NSString *name, NSString *comparison, NSString *value) {
        NSString *title = [RCVariableConditionViewController titleForComparison:comparison].lowercaseString;
        NSString *phrase = value.length ? [NSString stringWithFormat:@"%@ %@", title, value] : title;
        [weakSelf applyIfAction:@{ @"type": actionType, @"conditionKey": @"variable", @"conditionTitle": name,
                                   @"variable": name, @"comparison": comparison, @"expectedValue": value, @"expectedTitle": phrase }
                  existingIndex:existingIndex insertIndex:insertIndex];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    // After the condition picker has closed (it may still be going back)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf presentViewController:nav animated:YES completion:nil];
    });
}

// Set Variable: its own screen. Edits the one at existingIndex, or adds one at the end.
- (void)presentSetVariable:(NSDictionary *)draft existingIndex:(NSInteger)existingIndex {
    BOOL editing = existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count;
    NSMutableArray *others = [self.actions mutableCopy];
    if (editing) [others removeObjectAtIndex:existingIndex];
    RCSetVariableViewController *editor = [[RCSetVariableViewController alloc] initWithAction:editing ? draft : nil otherActions:others];
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(NSDictionary *item) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (editing && existingIndex < (NSInteger)strongSelf.actions.count) {
            strongSelf.actions[existingIndex] = item;
        } else {
            [strongSelf.actions addObject:item];
        }
        [strongSelf saveActions];
        [strongSelf.tableView reloadData];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    [self presentViewController:nav animated:YES completion:nil];
}

// Repeat: how many times. Edits the Repeat at existingIndex, or adds a Repeat block at the end.
- (void)presentRepeatCountForIndex:(NSInteger)existingIndex {
    BOOL editing = existingIndex != NSNotFound && existingIndex >= 0 && existingIndex < (NSInteger)self.actions.count;
    RCNumberSettingViewController *editor = [[RCNumberSettingViewController alloc] initWithTitle:@"Repeat" label:@"Times"
                                                                                             value:editing ? [self.actions[existingIndex][@"count"] description] : nil otherActions:self.actions];
    editor.placeholder = @"3";
    editor.minimum = 1;
    editor.maximum = 1000;
    editor.note = @"Runs the actions inside this many times, up to 1,000. In their text, {round} becomes the current round.";
    editor.allowsRound = [self roundAvailableAtIndex:editing ? existingIndex : NSNotFound];
    editor.saveTitle = editing ? @"Save" : @"Add";
    __weak typeof(self) weakSelf = self;
    editor.onSave = ^(id count, __unused NSInteger choice) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        // An edited Repeat keeps its other keys, such as disabled
        id old = editing && existingIndex < (NSInteger)strongSelf.actions.count ? strongSelf.actions[existingIndex] : nil;
        NSMutableDictionary *repeat = [old isKindOfClass:[NSDictionary class]] ? [old mutableCopy] : [@{ @"type": @"repeat" } mutableCopy];
        repeat[@"count"] = count;
        if (editing) {
            strongSelf.actions[existingIndex] = repeat;
        } else {
            [strongSelf.actions addObject:repeat];
            [strongSelf.actions addObject:@{ @"type": @"end_repeat" }];
        }
        [strongSelf saveActions];
        if (!editing) [strongSelf defaultToRestartForLoop];
        [strongSelf.tableView reloadData];
    };
    [self presentNumberSetting:editor after:0];
}

- (void)presentIfConditionPickerForIndex:(NSInteger)index {
    NSString *type = @"if";
    if (index != NSNotFound && index >= 0 && index < (NSInteger)self.actions.count) {
        id actionItem = self.actions[index];
        if ([self isElseIfActionItem:actionItem]) {
            type = @"else_if";
        } else if ([self isRepeatWhileActionItem:actionItem]) {
            type = @"repeat_while";
        } else if ([[self actionTypeForItem:actionItem] isEqualToString:@"wait_until"]) {
            type = @"wait_until";
        }
    }
    [self presentIfConditionPickerForIndex:index insertIndex:NSNotFound type:type];
}

- (void)presentIfValuePickerForCondition:(NSDictionary *)condition existingIndex:(NSInteger)index {
    [self presentIfValuePickerForCondition:condition existingIndex:index insertIndex:NSNotFound type:@"if"];
}

- (NSInteger)elseIfInsertionIndexForBlockIndex:(NSInteger)index {
    id item = self.actions[index];
    NSInteger ifIndex = NSNotFound;
    if ([self isIfActionItem:item]) {
        ifIndex = index;
    } else if ([self isElseIfActionItem:item] || [self isElseActionItem:item]) {
        NSInteger depth = 0;
        for (NSInteger idx = index; idx >= 0; idx--) {
            id checkItem = self.actions[idx];
            if ([self isEndIfActionItem:checkItem]) {
                depth++;
            } else if ([self isIfActionItem:checkItem]) {
                depth--;
                if (depth < 0) {
                    ifIndex = idx;
                    break;
                }
            }
        }
    } else if ([self isEndIfActionItem:item]) {
        ifIndex = [self matchingIfIndexForEndAtIndex:index];
    }
    
    if (ifIndex == NSNotFound) return NSNotFound;
    
    NSInteger depth = 0;
    for (NSInteger idx = ifIndex; idx < (NSInteger)self.actions.count; idx++) {
        id checkItem = self.actions[idx];
        if ([self isIfActionItem:checkItem]) {
            depth++;
        } else if ([self isEndIfActionItem:checkItem]) {
            depth--;
            if (depth == 0) {
                return idx;
            }
        } else if ([self isElseActionItem:checkItem]) {
            if (depth == 1) {
                return idx;
            }
        }
    }
    return NSNotFound;
}

- (NSInteger)moveActionFromIndex:(NSInteger)sourceIndex toFinalIndex:(NSInteger)finalIndex {
    if (sourceIndex < 0 || sourceIndex >= (NSInteger)self.actions.count) {
        return NSNotFound;
    }
    
    NSRange rangeToMove = [self ifBlockRangeForIndex:sourceIndex];
    if (rangeToMove.location == NSNotFound || rangeToMove.length == 0) {
        return NSNotFound;
    }
    
    NSInteger maxFinalIndex = (NSInteger)self.actions.count - (NSInteger)rangeToMove.length;
    finalIndex = MAX(0, MIN(finalIndex, maxFinalIndex));
    if (finalIndex == (NSInteger)rangeToMove.location) {
        return rangeToMove.location;
    }
    
    NSArray *itemsToMove = [self.actions subarrayWithRange:rangeToMove];
    [self.actions removeObjectsInRange:rangeToMove];

    finalIndex = MAX(0, MIN(finalIndex, (NSInteger)self.actions.count));
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(finalIndex, itemsToMove.count)];
    [self.actions insertObjects:itemsToMove atIndexes:indexes];
    
    [self saveActions];
    [self.tableView reloadData];
    return finalIndex;
}

// The long-press menu (a row's options, or the page's when pressed below the rows)
- (void)showOptionsAtPoint:(CGPoint)touchPoint {
    if ([self runShown]) return; // read-only while it runs
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:touchPoint];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:indexPath ? @"Action Options" : @"Actions"
                                                                   message:nil 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    if (indexPath) {
        id item = self.actions[indexPath.row];
        BOOL isDisabled = [[RCConfigManager sharedManager] isActionDisabled:item];
        
        // Disable / Enable option
        NSString *toggleTitle = isDisabled ? @"Enable Action" : @"Disable Action";
        [alert addAction:[UIAlertAction actionWithTitle:toggleTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            self.actions[indexPath.row] = [[RCConfigManager sharedManager] toggleActionDisabled:item];
            [self saveActions];
            [self.tableView reloadData];
        }]];
        
        // Copy option
        [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            g_actionClipboard = [item copy];
        }]];
        
        // Paste Above/Below options
        if (g_actionClipboard) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Paste Above" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self.actions insertObject:[g_actionClipboard copy] atIndex:indexPath.row];
                [self saveActions];
                [self.tableView reloadData];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Paste Below" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self.actions insertObject:[g_actionClipboard copy] atIndex:indexPath.row + 1];
                [self saveActions];
                [self.tableView reloadData];
            }]];
        }
        
        // Keyboard Maestro options
        NSString *longPressCmdStr = [item isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)item)[@"command"] : item;
        if ([longPressCmdStr isKindOfClass:[NSString class]] && ([longPressCmdStr hasPrefix:@"km "] || [longPressCmdStr isEqualToString:@"km"])) {
            NSString *macroName = @"";
            NSString *paramVal = @"";
            rc_parse_km_cmd(longPressCmdStr, &macroName, &paramVal);
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Edit Parameter / Value…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self promptEditKMParameterAtIndex:indexPath.row];
            }]];
            
            if (paramVal.length > 0) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Remove Parameter" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                    NSString *newCmd = [NSString stringWithFormat:@"km trigger \"%@\"", macroName];
                    if ([self.actions[indexPath.row] isKindOfClass:[NSDictionary class]]) {
                        NSMutableDictionary *d = [self.actions[indexPath.row] mutableCopy];
                        d[@"command"] = newCmd;
                        self.actions[indexPath.row] = d;
                    } else {
                        self.actions[indexPath.row] = newCmd;
                    }
                    [self saveActions];
                    [self.tableView reloadData];
                }]];
            }
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Test Macro" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [[RCServerClient sharedClient] executeCommand:longPressCmdStr completion:^(NSString * _Nullable output, NSError * _Nullable error) {}];
            }]];
        }

        // If-specific options
        if ([self isIfActionItem:item] || [self isElseIfActionItem:item] || [self isElseActionItem:item] || [self isEndIfActionItem:item]) {
            NSInteger insertionIndex = [self elseIfInsertionIndexForBlockIndex:indexPath.row];
            if (insertionIndex != NSNotFound) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Add Else If" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                    [self presentIfConditionPickerForIndex:NSNotFound insertIndex:insertionIndex type:@"else_if"];
                }]];
            }
            
            // Add Nested If option for if/else/end_if items themselves
            [alert addAction:[UIAlertAction actionWithTitle:@"Add Nested If" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                NSInteger insertIndex = indexPath.row + 1;
                if ([self isIfActionItem:item]) {
                    insertIndex = indexPath.row + 1;
                } else if ([self isElseIfActionItem:item] || [self isElseActionItem:item]) {
                    insertIndex = indexPath.row + 1;
                } else if ([self isEndIfActionItem:item]) {
                    insertIndex = indexPath.row;
                }
                [self presentIfConditionPickerForIndex:NSNotFound insertIndex:insertIndex type:@"if"];
            }]];
            
            NSInteger ifIndex = NSNotFound;
            if ([self isIfActionItem:item]) {
                ifIndex = indexPath.row;
            } else {
                NSInteger depth = 0;
                for (NSInteger idx = indexPath.row; idx >= 0; idx--) {
                    id checkItem = self.actions[idx];
                    if ([self isEndIfActionItem:checkItem]) {
                        depth++;
                    } else if ([self isIfActionItem:checkItem]) {
                        depth--;
                        if (depth < 0) {
                            ifIndex = idx;
                            break;
                        }
                    }
                }
            }
            
            if (ifIndex != NSNotFound) {
                NSInteger elseIndex = [self matchingElseIndexForIfAtIndex:ifIndex];
                BOOL hasElse = (elseIndex != NSNotFound);
                
                if (hasElse) {
                    if ([self isElseActionItem:item] || [self isIfActionItem:item]) {
                        [alert addAction:[UIAlertAction actionWithTitle:@"Remove Else" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
                            [self.actions removeObjectAtIndex:elseIndex];
                            [self saveActions];
                            [self.tableView reloadData];
                        }]];
                    }
                } else {
                    [alert addAction:[UIAlertAction actionWithTitle:@"Add Else" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                        NSInteger endIndex = [self matchingEndIndexForIfAtIndex:ifIndex];
                        if (endIndex != NSNotFound) {
                            [self.actions insertObject:@{ @"type": @"else" } atIndex:endIndex];
                            [self saveActions];
                            [self.tableView reloadData];
                        }
                    }]];
                }
            }
            
            if ([self isIfActionItem:item] || [self isElseIfActionItem:item]) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Edit Condition" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                    [self presentIfConditionPickerForIndex:indexPath.row];
                }]];
            }
            
            if ([self isElseIfActionItem:item]) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Delete Else If" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
                    [self.actions removeObjectAtIndex:indexPath.row];
                    [self saveActions];
                    [self.tableView reloadData];
                }]];
            }
        }
        
        // Wait Until: its condition and time limit
        if ([[self actionTypeForItem:item] isEqualToString:@"wait_until"]) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Edit Condition" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self presentIfConditionPickerForIndex:indexPath.row];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Edit Time Limit" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self presentWaitLimitForAction:self.actions[indexPath.row] existingIndex:indexPath.row insertIndex:NSNotFound];
            }]];
        }

        // Repeat blocks: change the count or condition, and add an If inside
        if ([self isRepeatActionItem:item] || [self isEndRepeatActionItem:item]) {
            if ([self isRepeatActionItem:item]) {
                BOOL isWhile = [self isRepeatWhileActionItem:item];
                [alert addAction:[UIAlertAction actionWithTitle:isWhile ? @"Edit Condition" : @"Edit Count" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                    if (isWhile) [self presentIfConditionPickerForIndex:indexPath.row];
                    else [self presentRepeatCountForIndex:indexPath.row];
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"Add Nested If" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                NSInteger insertIndex = [self isRepeatActionItem:item] ? indexPath.row + 1 : indexPath.row;
                [self presentIfConditionPickerForIndex:NSNotFound insertIndex:insertIndex type:@"if"];
            }]];
        }

        // Add Nested If option for regular items inside if blocks
        NSInteger currentIndent = [self indentationLevelForRow:indexPath.row];
        if (currentIndent > 0 && ![self isBlockStartItem:item] && ![self isElseIfActionItem:item] && ![self isElseActionItem:item] && ![self isBlockEndItem:item]) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Add Nested If" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self presentIfConditionPickerForIndex:NSNotFound insertIndex:indexPath.row type:@"if"];
            }]];
        }
    } else {
        // Long press on empty space
        if (g_actionClipboard) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Paste" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self.actions addObject:[g_actionClipboard copy]];
                [self saveActions];
                [self.tableView reloadData];
            }]];
        } else {
            return; // Nothing to do on empty space if clipboard is empty
        }
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverSourceForAlert:alert];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self runShown]) return;
    id actionData = self.actions[indexPath.row];
    
    if ([actionData isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)actionData;
        if (dict[@"command"] && [dict[@"command"] isKindOfClass:[NSString class]]) {
            actionData = dict[@"command"];
        } else {
            if ([self isIfActionItem:actionData] || [self isElseIfActionItem:actionData] || [self isRepeatWhileActionItem:actionData] || [[self actionTypeForItem:actionData] isEqualToString:@"wait_until"]) {
                [self presentIfConditionPickerForIndex:indexPath.row];
            } else if ([self isRepeatActionItem:actionData]) {
                [self presentRepeatCountForIndex:indexPath.row];
            } else if ([[self actionTypeForItem:actionData] isEqualToString:@"set_variable"]) {
                [self presentSetVariable:actionData existingIndex:indexPath.row];
            }
            return;
        }
    }
    
    NSString *currentAction = (NSString *)actionData;
    NSDictionary *toggleInfo = [[RCConfigManager sharedManager] toggleInfoForCommand:currentAction];
    
    if (toggleInfo) {
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:toggleInfo[@"name"]
                                                                         message:@"Select desired state"
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
        
        NSArray *suffixes = toggleInfo[@"suffixes"];
        NSArray *displaySuffixes = toggleInfo[@"displaySuffixes"];
        NSString *matchedPrefix = toggleInfo[@"matchedPrefix"];
        NSArray *prefixes = toggleInfo[@"prefixes"];
        NSString *canonicalPrefix = (matchedPrefix.length > 0) ? matchedPrefix : (prefixes.firstObject ?: @"");
        
        __weak typeof(self) weakSelf = self;
        for (NSUInteger idx = 0; idx < suffixes.count; idx++) {
            NSString *suffix = suffixes[idx];
            NSString *displaySuffix = displaySuffixes[idx];
            
            [picker addAction:[UIAlertAction actionWithTitle:displaySuffix
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction * _Nonnull action) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                
                NSString *newCommand = [NSString stringWithFormat:@"%@%@", canonicalPrefix, suffix];
                if (matchedPrefix.length == 0 && [toggleInfo[@"key"] isEqualToString:@"audiomix"] && [suffix isEqualToString:@"toggle"]) {
                    newCommand = @"audiomix";
                }
                
                if ([strongSelf.actions[indexPath.row] isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *d = [strongSelf.actions[indexPath.row] mutableCopy];
                    d[@"command"] = newCommand;
                    strongSelf.actions[indexPath.row] = d;
                } else {
                    strongSelf.actions[indexPath.row] = newCommand;
                }
                [strongSelf saveActions];
                [strongSelf.tableView reloadData];
            }]];
        }
        
        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        
        picker.popoverPresentationController.sourceView = self.view;
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (cell) {
            picker.popoverPresentationController.sourceRect = cell.bounds;
            picker.popoverPresentationController.sourceView = cell;
        } else {
            picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
        }
        
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }
    
    if ([currentAction.lowercaseString hasPrefix:@"toast "]) {
        [self presentToastEditorForIndex:indexPath.row];
        return;
    }

    if ([currentAction hasPrefix:@"exec "] || [currentAction hasPrefix:@"root "]) {
        // Edit Terminal Command
        BOOL isRoot = [currentAction hasPrefix:@"root "];
        NSString *currentCommand = [currentAction substringFromIndex:5];
        
        RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
        inputVC.promptTitle = @"Edit Command";
        inputVC.promptMessage = @"Update your terminal command";
        inputVC.initialText = currentCommand;
        inputVC.showRootToggle = YES;
        inputVC.isRootToggled = isRoot;
        inputVC.variableActions = self.actions;
        
        __weak typeof(inputVC) weakInputVC = inputVC;
        inputVC.onComplete = ^(NSString *text) {
            if (text.length > 0) {
                NSString *prefix = weakInputVC.isRootToggled ? @"root" : @"exec";
                [self storeCommand:[NSString stringWithFormat:@"%@ %@", prefix, text] atIndex:indexPath.row];
            }
        };
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
        [self presentViewController:nav animated:YES completion:nil];
    } else if ([self levelPrefixForCommand:currentAction]) {
        [self presentLevelActionForCommand:currentAction index:indexPath.row after:0];
    } else if ([currentAction hasPrefix:@"Lua "] || [currentAction hasPrefix:@"lua_eval "] || [currentAction hasPrefix:@"lua "]) {
        // Edit Lua Script
        int prefixLength = [currentAction hasPrefix:@"lua_eval "] ? 9 : 4;
        NSString *currentCode = [currentAction substringFromIndex:prefixLength];
        
        RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
        inputVC.promptTitle = @"Edit Lua Script";
        inputVC.promptMessage = @"Update your Lua code";
        inputVC.initialText = currentCode;
        inputVC.onComplete = ^(NSString *text) {
            if (text.length > 0) {
                // We always save as Lua (direct) when editing
                self.actions[indexPath.row] = [NSString stringWithFormat:@"Lua %@", text];
                [self saveActions];
                [self.tableView reloadData];
            }
        };
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
        [self presentViewController:nav animated:YES completion:nil];

    } else if ([currentAction hasPrefix:@"stop trigger "]) {
        [self pickTriggerToStop:^(NSString *key) {
            self.actions[indexPath.row] = [@"stop trigger " stringByAppendingString:key];
            [self saveActions];
            [self.tableView reloadData];
        }];
    } else if ([currentAction hasPrefix:@"delay "]) {
        [self presentDelayForIndex:indexPath.row current:[currentAction substringFromIndex:6] after:0];
    } else if ([currentAction hasPrefix:@"shortcut:"]) {
        // Change the shortcut, or whether it runs silently (keeping its input)
        BOOL silent = NO;
        NSString *input = nil;
        NSString *shortcutName = [RCConfigManager shortcutNameForAction:currentAction silent:&silent input:&input];
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:shortcutName message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Change Shortcut" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            RCShortcutPickerViewController *shortcutPicker = [[RCShortcutPickerViewController alloc] init];
            shortcutPicker.showsSilentOption = YES;
            shortcutPicker.runSilently = silent;
            __weak RCShortcutPickerViewController *weakPicker = shortcutPicker;
            shortcutPicker.onShortcutSelected = ^(NSString *name) {
                self.actions[indexPath.row] = [RCConfigManager shortcutActionWithName:name silent:weakPicker.runSilently input:input];
                [self saveActions];
                [self.tableView reloadData];
            };
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:shortcutPicker];
            [self presentViewController:nav animated:YES completion:nil];
        }]];
        UIAlertAction *silentAction = [UIAlertAction actionWithTitle:@"Run Silently" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            self.actions[indexPath.row] = [RCConfigManager shortcutActionWithName:shortcutName silent:!silent input:input];
            [self saveActions];
            [self.tableView reloadData];
        }];
        @try { [silentAction setValue:@(silent) forKey:@"checked"]; } @catch (NSException *e) {} // the tick
        [sheet addAction:silentAction];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
        [self presentViewController:sheet animated:YES completion:nil];
    } else if ([currentAction hasPrefix:@"uiopen "]) {
        // Edit App
        RCAppPickerViewController *appPicker = [[RCAppPickerViewController alloc] init];
        appPicker.onAppSelected = ^(NSString *name, NSString *bundleId) {
            self.actions[indexPath.row] = [NSString stringWithFormat:@"uiopen %@", bundleId];
            [self saveActions];
            [self.tableView reloadData];
        };
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:appPicker];
        [self presentViewController:nav animated:YES completion:nil];
    } else if ([[currentAction lowercaseString] isEqualToString:@"kill current"] ||
               [[currentAction lowercaseString] isEqualToString:@"kill front"] ||
               [[currentAction lowercaseString] isEqualToString:@"kill foreground"] ||
               [[currentAction lowercaseString] isEqualToString:@"kill current app"] ||
               [[currentAction lowercaseString] isEqualToString:@"kill front app"]) {
        // Kill Current App targets the focused app at run time: nothing to edit
        return;
    } else if ([currentAction hasPrefix:@"kill "]) {
        // Edit Kill App
        RCAppPickerViewController *appPicker = [[RCAppPickerViewController alloc] init];
        appPicker.onAppSelected = ^(NSString *name, NSString *bundleId) {
            self.actions[indexPath.row] = [NSString stringWithFormat:@"kill %@", bundleId];
            [self saveActions];
            [self.tableView reloadData];
        };
        
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:appPicker];
        [self presentViewController:nav animated:YES completion:nil];
    } else if ([currentAction hasPrefix:@"airplay connect "] || [currentAction hasPrefix:@"airplay-connect "]) {
        [self editAirPlayConnectAtIndex:indexPath.row];
    } else if ([currentAction hasPrefix:@"bt connect "] || [currentAction hasPrefix:@"bluetooth connect "] || [currentAction hasPrefix:@"bt-connect "]) {
        [self editBluetoothConnectAtIndex:indexPath.row isDisconnect:NO];
    } else if ([currentAction hasPrefix:@"bt disconnect "] || [currentAction hasPrefix:@"bluetooth disconnect "] || [currentAction hasPrefix:@"bt-disconnect "]) {
        [self editBluetoothConnectAtIndex:indexPath.row isDisconnect:YES];
    } else if ([currentAction hasPrefix:@"focus on "] || [currentAction hasPrefix:@"focus toggle "] || [currentAction isEqualToString:@"focus off"]) {
        [self editFocusAtIndex:indexPath.row];
    } else if ([currentAction hasPrefix:@"km "] || [currentAction isEqualToString:@"km"]) {
        NSString *macroName = @"";
        NSString *paramVal = @"";
        rc_parse_km_cmd(currentAction, &macroName, &paramVal);
        
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:macroName.length ? macroName : @"Keyboard Maestro"
                                                                       message:paramVal.length ? [NSString stringWithFormat:@"Parameter: %@", paramVal] : @"No parameter configured"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        
        [sheet addAction:[UIAlertAction actionWithTitle:@"Edit Parameter / Value…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self promptEditKMParameterAtIndex:indexPath.row];
        }]];
        
        if (paramVal.length > 0) {
            [sheet addAction:[UIAlertAction actionWithTitle:@"Remove Parameter" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                NSString *newCmd = [NSString stringWithFormat:@"km trigger \"%@\"", macroName];
                if ([self.actions[indexPath.row] isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *d = [self.actions[indexPath.row] mutableCopy];
                    d[@"command"] = newCmd;
                    self.actions[indexPath.row] = d;
                } else {
                    self.actions[indexPath.row] = newCmd;
                }
                [self saveActions];
                [self.tableView reloadData];
            }]];
        }
        
        [sheet addAction:[UIAlertAction actionWithTitle:@"Change Macro…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            RCKMMacroPickerViewController *picker = [[RCKMMacroPickerViewController alloc] init];
            picker.onMacroSelected = ^(NSString *cmd) {
                if ([self.actions[indexPath.row] isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *d = [self.actions[indexPath.row] mutableCopy];
                    d[@"command"] = cmd;
                    self.actions[indexPath.row] = d;
                } else {
                    self.actions[indexPath.row] = cmd;
                }
                [self saveActions];
                [self.tableView reloadData];
                [self dismissViewControllerAnimated:YES completion:nil];
            };
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
            picker.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(dismissModalPicker)];
            [self presentViewController:nav animated:YES completion:nil];
        }]];
        
        [sheet addAction:[UIAlertAction actionWithTitle:@"Test Macro" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [[RCServerClient sharedClient] executeCommand:currentAction completion:^(NSString * _Nullable output, NSError * _Nullable error) {}];
        }]];
        
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        
        sheet.popoverPresentationController.sourceView = self.view;
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (cell) {
            sheet.popoverPresentationController.sourceRect = cell.bounds;
            sheet.popoverPresentationController.sourceView = cell;
        }
        [self presentViewController:sheet animated:YES completion:nil];
        return;
    } else if ([currentAction isEqualToString:@"unlock"] || [currentAction hasPrefix:@"unlock "]) {
        [self promptEditUnlockActionAtIndex:indexPath.row];
        return;
    } else if ([currentAction isEqualToString:@"lock-toggle"] || [currentAction isEqualToString:@"lock toggle"] || [currentAction hasPrefix:@"lock-toggle "] || [currentAction hasPrefix:@"lock toggle "]) {
        [self promptEditLockToggleActionAtIndex:indexPath.row];
        return;
    } else {
        // Any other command: the command editor, with the variable menu
        RCTextInputViewController *inputVC = [[RCTextInputViewController alloc] init];
        inputVC.promptTitle = @"Edit Action";
        inputVC.initialText = currentAction;
        inputVC.variableActions = self.actions;
        inputVC.onComplete = ^(NSString *text) {
            if (text.length > 0) [self storeCommand:text atIndex:indexPath.row];
        };
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:inputVC];
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)promptEditUnlockActionAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.actions.count) return;
    id item = self.actions[index];
    NSString *cmdStr = [item isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)item)[@"command"] : item;
    BOOL hasPasscode = [cmdStr hasPrefix:@"unlock "] && cmdStr.length > 7;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Unlock Action"
                                                                   message:@"Enter a passcode to unlock automatically, or choose 'Wake Screen Only' to present the passcode screen.\n\nNote: Configured passcodes are stored in plain text in trigger settings (rc_triggers.plist)."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = hasPasscode ? @"New Passcode (or leave blank to keep)" : @"Passcode (optional)";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        textField.secureTextEntry = YES;
    }];
    
    __weak typeof(self) weakSelf = self;
    
    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"Save Passcode" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UITextField *tf = alert.textFields.firstObject;
        NSString *pin = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *finalCmd;
        if (pin.length > 0) {
            finalCmd = [NSString stringWithFormat:@"unlock %@", pin];
        } else if (hasPasscode) {
            finalCmd = cmdStr;
        } else {
            finalCmd = @"unlock";
        }
        
        if ([strongSelf.actions[index] isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *d = [strongSelf.actions[index] mutableCopy];
            d[@"command"] = finalCmd;
            strongSelf.actions[index] = d;
        } else {
            strongSelf.actions[index] = finalCmd;
        }
        [strongSelf saveActions];
        [strongSelf.tableView reloadData];
    }];
    
    UIAlertAction *wakeOnly = [UIAlertAction actionWithTitle:@"Wake Screen Only" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *finalCmd = @"unlock";
        if ([strongSelf.actions[index] isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *d = [strongSelf.actions[index] mutableCopy];
            d[@"command"] = finalCmd;
            strongSelf.actions[index] = d;
        } else {
            strongSelf.actions[index] = finalCmd;
        }
        [strongSelf saveActions];
        [strongSelf.tableView reloadData];
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:wakeOnly];
    [alert addAction:saveAction];
    [alert addAction:cancel];
    alert.preferredAction = saveAction;
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptEditLockToggleActionAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.actions.count) return;
    id item = self.actions[index];
    NSString *cmdStr = [item isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)item)[@"command"] : item;
    BOOL hasPasscode = ([cmdStr hasPrefix:@"lock-toggle "] && cmdStr.length > 12) || ([cmdStr hasPrefix:@"lock toggle "] && cmdStr.length > 12);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Lock Toggle Action"
                                                                   message:@"Enter a passcode to unlock automatically when locked, or choose 'No Passcode' to toggle without passcode entry.\n\nNote: Configured passcodes are stored in plain text in trigger settings (rc_triggers.plist)."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = hasPasscode ? @"New Passcode (or leave blank to keep)" : @"Passcode (optional)";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        textField.secureTextEntry = YES;
    }];
    
    __weak typeof(self) weakSelf = self;
    
    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"Save Passcode" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UITextField *tf = alert.textFields.firstObject;
        NSString *pin = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *finalCmd;
        if (pin.length > 0) {
            finalCmd = [NSString stringWithFormat:@"lock-toggle %@", pin];
        } else if (hasPasscode) {
            finalCmd = cmdStr;
        } else {
            finalCmd = @"lock-toggle";
        }
        
        if ([strongSelf.actions[index] isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *d = [strongSelf.actions[index] mutableCopy];
            d[@"command"] = finalCmd;
            strongSelf.actions[index] = d;
        } else {
            strongSelf.actions[index] = finalCmd;
        }
        [strongSelf saveActions];
        [strongSelf.tableView reloadData];
    }];
    
    UIAlertAction *noPasscode = [UIAlertAction actionWithTitle:@"No Passcode" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *finalCmd = @"lock-toggle";
        if ([strongSelf.actions[index] isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *d = [strongSelf.actions[index] mutableCopy];
            d[@"command"] = finalCmd;
            strongSelf.actions[index] = d;
        } else {
            strongSelf.actions[index] = finalCmd;
        }
        [strongSelf saveActions];
        [strongSelf.tableView reloadData];
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:noPasscode];
    [alert addAction:saveAction];
    [alert addAction:cancel];
    alert.preferredAction = saveAction;
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptEditKMParameterAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.actions.count) return;
    id item = self.actions[index];
    NSString *cmdStr = [item isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)item)[@"command"] : item;
    NSString *macroName = @"";
    NSString *paramVal = @"";
    rc_parse_km_cmd(cmdStr, &macroName, &paramVal);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Parameter: %@", macroName]
                                                                   message:@"Enter value passed to KM %TriggerValue% (leave empty for none):"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = paramVal;
        tf.placeholder = @"Parameter / Value (optional)";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *val = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *newCmd;
        if (val.length > 0) {
            newCmd = [NSString stringWithFormat:@"km trigger \"%@\" \"%@\"", macroName, val];
        } else {
            newCmd = [NSString stringWithFormat:@"km trigger \"%@\"", macroName];
        }
        if ([self.actions[index] isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *d = [self.actions[index] mutableCopy];
            d[@"command"] = newCmd;
            self.actions[index] = d;
        } else {
            self.actions[index] = newCmd;
        }
        [self saveActions];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissModalPicker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Opens the Focus modes over the editor with the action's Focus ticked; choosing one asks Turn
// On or Toggle again, choosing Off makes it "focus off"
- (void)editFocusAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.actions.count || ![self.actions[index] isKindOfClass:[NSString class]]) return;
    NSString *action = self.actions[index];
    BOOL toggle = [action hasPrefix:@"focus toggle "];
    NSString *current = [action hasPrefix:@"focus on "] ? [action substringFromIndex:9] : toggle ? [action substringFromIndex:13] : @"";

    RCFocusPickerViewController *picker = [[RCFocusPickerViewController alloc] initWithTitle:@"Set Focus"
                                                                                  fixedRows:@[ @{ @"name": @"Off", @"value": @"", @"icon": @"moon.zzz" } ]];
    picker.currentValue = current;
    picker.buildsCommand = YES;
    __weak typeof(self) weakSelf = self;
    picker.onSelected = ^(NSDictionary *row) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || index >= (NSInteger)strongSelf.actions.count) return;
        strongSelf.actions[index] = row[@"command"];
        [strongSelf saveActions];
        [strongSelf.tableView reloadData];
        [strongSelf dismissViewControllerAnimated:YES completion:nil];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)editAirPlayConnectAtIndex:(NSInteger)index {
    [self presentDevicePickerWithKind:RCDevicePickerKindAirPlay title:@"AirPlay Device" commandPrefix:@"airplay connect" index:index];
}

- (void)editBluetoothConnectAtIndex:(NSInteger)index isDisconnect:(BOOL)isDisconnect {
    [self presentDevicePickerWithKind:RCDevicePickerKindBluetooth
                                title:isDisconnect ? @"Disconnect Bluetooth" : @"Connect Bluetooth"
                        commandPrefix:isDisconnect ? @"bt disconnect" : @"bt connect"
                                index:index];
}

// Opens the device list over the editor with the action's current device ticked;
// choosing one rewrites the action as "<prefix> <device>"
- (void)presentDevicePickerWithKind:(RCDevicePickerKind)kind title:(NSString *)title commandPrefix:(NSString *)prefix index:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.actions.count || ![self.actions[index] isKindOfClass:[NSString class]]) return;
    NSString *action = self.actions[index];
    // The device: everything after the command word(s), minus an AirPlay "UID # " part
    NSString *current = @"";
    for (NSString *word in @[ @"airplay connect ", @"airplay-connect ", @"bluetooth disconnect ", @"bluetooth connect ", @"bt disconnect ", @"bt connect ", @"bt-disconnect ", @"bt-connect " ]) {
        if ([action hasPrefix:word]) { current = [action substringFromIndex:word.length]; break; }
    }
    NSRange hash = [current rangeOfString:@" # "];
    if (hash.location != NSNotFound) current = [current substringFromIndex:NSMaxRange(hash)];
    current = [current stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\" \t"]];

    RCDevicePickerViewController *picker = [[RCDevicePickerViewController alloc] initWithKind:kind title:title];
    picker.currentDevice = current;
    __weak typeof(self) weakSelf = self;
    __weak RCDevicePickerViewController *weakPicker = picker;
    picker.onDeviceSelected = ^(NSDictionary *device) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || index >= (NSInteger)strongSelf.actions.count) return;
        strongSelf.actions[index] = [NSString stringWithFormat:@"%@ %@", prefix, device[@"target"]];
        [strongSelf saveActions];
        [strongSelf.tableView reloadData];
        [weakPicker dismissViewControllerAnimated:YES completion:nil];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (UIBezierPath *)fillPathForRect:(CGRect)rect
                            first:(BOOL)isFirst
                             last:(BOOL)isLast
                           single:(BOOL)isSingle
                     cornerRadius:(CGFloat)cornerRadius {
    if (isSingle) {
        return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius];
    }
    if (isFirst) {
        return [UIBezierPath bezierPathWithRoundedRect:rect
                                     byRoundingCorners:(UIRectCornerTopLeft | UIRectCornerTopRight)
                                           cornerRadii:CGSizeMake(cornerRadius, cornerRadius)];
    }
    if (isLast) {
        return [UIBezierPath bezierPathWithRoundedRect:rect
                                     byRoundingCorners:(UIRectCornerBottomLeft | UIRectCornerBottomRight)
                                           cornerRadii:CGSizeMake(cornerRadius, cornerRadius)];
    }
    return [UIBezierPath bezierPathWithRect:rect];
}

- (void)applySectionCardStyleToCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *config = [RCConfigManager sharedManager];
    UIColor *fillColor = [config tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIColor *selectedFillColor = [config tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    UIColor *borderColor = [config tweakColorForKey:@"borders" defaultVal:0.14];
    // The action a run of this trigger is on: green, like a debugger's current line
    if ([self.runningIndexes containsIndex:indexPath.row]) {
        fillColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.22];
        borderColor = [UIColor systemGreenColor];
        cell.imageView.tintColor = [UIColor systemGreenColor];
    }
    
    NSInteger rowCount = [self.tableView numberOfRowsInSection:indexPath.section];
    if (rowCount < 1) {
        return;
    }
    
    BOOL isSingle = (rowCount == 1);
    BOOL isFirst = (indexPath.row == 0);
    BOOL isLast = (indexPath.row == rowCount - 1);
    
    CGFloat lineWidth = 1.0;
    CGFloat cornerRadius = 12.0;
    CGRect fillRect = CGRectInset(cell.bounds, 0.0, 0.0);
    CGRect borderRect = CGRectInset(fillRect, lineWidth * 0.5, lineWidth * 0.5);
    if (CGRectGetWidth(fillRect) <= 0 || CGRectGetHeight(fillRect) <= 0) {
        return;
    }
    if (CGRectGetWidth(borderRect) <= 0 || CGRectGetHeight(borderRect) <= 0) {
        return;
    }
    
    UIBezierPath *fillPath = [self fillPathForRect:fillRect
                                             first:isFirst
                                              last:isLast
                                            single:isSingle
                                      cornerRadius:cornerRadius];
    
    UIBezierPath *borderPath = [self fillPathForRect:borderRect
                                             first:isFirst
                                              last:isLast
                                            single:isSingle
                                      cornerRadius:cornerRadius];
    
    UIView *normalBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
    normalBackgroundView.backgroundColor = [UIColor clearColor];
    
    CAShapeLayer *normalFillLayer = [CAShapeLayer layer];
    normalFillLayer.frame = normalBackgroundView.bounds;
    normalFillLayer.path = fillPath.CGPath;
    normalFillLayer.fillColor = fillColor.CGColor;
    [normalBackgroundView.layer addSublayer:normalFillLayer];
    
    CAShapeLayer *normalBorderLayer = [CAShapeLayer layer];
    normalBorderLayer.frame = normalBackgroundView.bounds;
    normalBorderLayer.path = borderPath.CGPath;
    normalBorderLayer.fillColor = [UIColor clearColor].CGColor;
    normalBorderLayer.strokeColor = borderColor.CGColor;
    normalBorderLayer.lineWidth = lineWidth;
    
    if (!isSingle) {
        CGRect maskRect = normalBorderLayer.bounds;
        if (isFirst) {
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else if (isLast) {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - (2.0 * lineWidth));
        }
        CAShapeLayer *maskLayer = [CAShapeLayer layer];
        maskLayer.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
        normalBorderLayer.mask = maskLayer;
    }
    [normalBackgroundView.layer addSublayer:normalBorderLayer];
    
    UIView *selectedBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
    selectedBackgroundView.backgroundColor = [UIColor clearColor];
    
    CAShapeLayer *selectedFillLayer = [CAShapeLayer layer];
    selectedFillLayer.frame = selectedBackgroundView.bounds;
    selectedFillLayer.path = fillPath.CGPath;
    selectedFillLayer.fillColor = selectedFillColor.CGColor;
    [selectedBackgroundView.layer addSublayer:selectedFillLayer];
    
    CAShapeLayer *selectedBorderLayer = [CAShapeLayer layer];
    selectedBorderLayer.frame = selectedBackgroundView.bounds;
    selectedBorderLayer.path = borderPath.CGPath;
    selectedBorderLayer.fillColor = [UIColor clearColor].CGColor;
    selectedBorderLayer.strokeColor = borderColor.CGColor;
    selectedBorderLayer.lineWidth = lineWidth;
    if (!isSingle) {
        CGRect maskRect = selectedBorderLayer.bounds;
        if (isFirst) {
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else if (isLast) {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - lineWidth);
        } else {
            maskRect.origin.y = lineWidth;
            maskRect.size.height = MAX(0.0, maskRect.size.height - (2.0 * lineWidth));
        }
        CAShapeLayer *maskLayer = [CAShapeLayer layer];
        maskLayer.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
        selectedBorderLayer.mask = maskLayer;
    }
    [selectedBackgroundView.layer addSublayer:selectedBorderLayer];
    
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.backgroundView = normalBackgroundView;
    cell.selectedBackgroundView = selectedBackgroundView;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _actions.count;
}

// A banner above the sequence when the trigger restarts or ignores a new trigger while running,
// so it's seen however long the sequence is
- (NSString *)runModeBannerText {
    NSString *mode = [self runMode];
    if ([mode isEqualToString:@"restart"]) return @"If triggered again while running, this sequence will start over.";
    if ([mode isEqualToString:@"single"]) return @"If triggered again while running, the new trigger will be ignored.";
    // Run Alongside, the default: shown only where a run lasts long enough for it to matter
    if ([self sequenceTakesTime]) return @"If triggered again while running, another run will start alongside.";
    return nil;
}

// Whether a run can last a while: a delay, a loop or a Wait Until
- (BOOL)sequenceTakesTime {
    for (id item in _actions) {
        if ([item isKindOfClass:[NSString class]] && [[(NSString *)item lowercaseString] hasPrefix:@"delay "]) return YES;
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSString *type = [item[@"type"] isKindOfClass:[NSString class]] ? item[@"type"] : @"";
            if ([@[@"repeat", @"repeat_while", @"wait_until"] containsObject:type]) return YES;
        }
    }
    return NO;
}

- (CGFloat)runModeBannerHeightForWidth:(CGFloat)width {
    NSString *text = [self runModeBannerText];
    if (!text) return 0;
    CGFloat textWidth = width - self.tableView.layoutMargins.left - self.tableView.layoutMargins.right - 78; // margins, icon, chevron, padding
    CGRect bounds = [text boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                    attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13] } context:nil];
    return MAX(40, ceil(bounds.size.height) + 20);
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (_actions.count == 0) return nil;
    
    CGFloat width = tableView.bounds.size.width;
    CGFloat bannerHeight = [self runModeBannerHeightForWidth:width];
    CGFloat stripHeight = [self showsRunStrip] ? 52 : 0;
    CGFloat top = (bannerHeight > 0 ? bannerHeight + 12 : 0) + stripHeight;
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 40 + top)];
    if (stripHeight > 0) {
        [headerView addSubview:[self runStripWithWidth:width left:tableView.layoutMargins.left right:tableView.layoutMargins.right]];
    }
    if (bannerHeight > 0) {
        // Lined up with the action cards (the table's margins), and kept so as the header is resized
        CGFloat left = tableView.layoutMargins.left, right = tableView.layoutMargins.right;
        // Tapping it changes When Triggered Again, as the ••• menu does
        UIButton *banner = [UIButton buttonWithType:UIButtonTypeCustom];
        banner.frame = CGRectMake(left, 10 + stripHeight, width - left - right, bannerHeight);
        banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        banner.backgroundColor = [UIColor tertiarySystemFillColor];
        banner.layer.cornerRadius = 10;
        banner.menu = [self runModeMenu];
        banner.showsMenuAsPrimaryAction = YES;
        banner.enabled = ![self runShown]; // the debugger view is read-only
        banner.accessibilityLabel = [self runModeBannerText];
        banner.accessibilityHint = @"Changes what happens when triggered again";
        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.up.chevron.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]]];
        chevron.tintColor = [UIColor tertiaryLabelColor];
        chevron.contentMode = UIViewContentModeCenter;
        chevron.frame = CGRectMake(banner.bounds.size.width - 30, 0, 20, bannerHeight);
        chevron.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        chevron.userInteractionEnabled = NO;
        chevron.hidden = [self runShown];
        [banner addSubview:chevron];
        NSString *mode = [self runMode];
        NSString *iconName = [mode isEqualToString:@"restart"] ? @"arrow.counterclockwise" : [mode isEqualToString:@"single"] ? @"nosign" : @"square.stack";
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
        icon.tintColor = [UIColor secondaryLabelColor];
        icon.contentMode = UIViewContentModeCenter;
        icon.frame = CGRectMake(12, 0, 22, bannerHeight);
        icon.userInteractionEnabled = NO;
        [banner addSubview:icon];
        UILabel *text = [[UILabel alloc] initWithFrame:CGRectMake(44, 0, banner.bounds.size.width - 78, bannerHeight)];
        text.text = [self runModeBannerText];
        text.font = [UIFont systemFontOfSize:13];
        text.textColor = [UIColor secondaryLabelColor];
        text.numberOfLines = 0;
        text.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [banner addSubview:text];
        [headerView addSubview:banner];
    }
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15 + top, width - 40, 20)];
    label.text = @"ACTION SEQUENCE";
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    [headerView addSubview:label];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (_actions.count == 0) return 0;
    CGFloat bannerHeight = [self runModeBannerHeightForWidth:tableView.bounds.size.width];
    return 40.0f + (bannerHeight > 0 ? bannerHeight + 12 : 0) + ([self showsRunStrip] ? 52 : 0);
}

// The ordinary editor while its trigger runs (the debugger view has the run above its title instead)
- (BOOL)showsRunStrip {
    return !self.debugRunID && self.stripRuns.count > 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (_actions.count == 0) {
        return @"Tap + to add actions. They will run in sequence when the trigger fires.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCActionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell" forIndexPath:indexPath];
    
    // Action card styling applied via applySectionCardStyleToCell: below
    id actionItem = _actions[indexPath.row];
    NSString *cleanName = [self displayNameForCommand:actionItem];
    NSString *subtitle = nil;
    NSInteger indentationLevel = [self indentationLevelForRow:indexPath.row];

    cell.indentationWidth = 14.0f;
    cell.indentationLevel = indentationLevel;

    BOOL wrapLongNames = [[NSUserDefaults standardUserDefaults] boolForKey:@"RCWrapLongNamesEnabled"];
    cell.textLabel.numberOfLines = wrapLongNames ? 0 : 1;
    cell.detailTextLabel.numberOfLines = wrapLongNames ? 0 : 1;

    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.textLabel.minimumScaleFactor = 0.80f;
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.minimumScaleFactor = 0.80f;

    if ([actionItem isKindOfClass:[NSDictionary class]] && !((NSDictionary *)actionItem)[@"command"]) {
        cell.textLabel.text = cleanName;
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        // If / Else If rows can be long ("If Bluetooth Device Connected is …"): wrap to a second line
        cell.textLabel.numberOfLines = wrapLongNames ? 0 : 1;
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        BOOL isControl = [self isBlockEndItem:actionItem] || [self isElseActionItem:actionItem];
        cell.textLabel.textColor = isControl ? [UIColor secondaryLabelColor] : [UIColor labelColor];
        cell.detailTextLabel.text = nil;
        
        cell.imageView.image = [UIImage systemImageNamed:[self iconForCommand:actionItem]];
        cell.imageView.tintColor = isControl ? [UIColor tertiaryLabelColor] : [UIColor systemGrayColor];
        
        UIImageView *handleView = [[UIImageView alloc] initWithImage:RCGrabberImage()];
        handleView.tintColor = [UIColor systemGray3Color];
        cell.accessoryView = handleView;
        [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
        
        BOOL isDisabled = [[RCConfigManager sharedManager] isActionDisabled:actionItem];
        cell.contentView.alpha = isDisabled ? 0.38f : 1.0f;
        cell.accessoryView.alpha = isDisabled ? 0.38f : 1.0f;
        return cell;
    }

    NSString *action = [actionItem isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)actionItem)[@"command"] : (NSString *)actionItem;
    cell.textLabel.numberOfLines = wrapLongNames ? 0 : 1;
    NSDictionary *toggleInfo = [[RCConfigManager sharedManager] toggleInfoForCommand:action];

    // Logic to separate "Type" from "Value"
    if (toggleInfo) {
        NSString *baseName = toggleInfo[@"name"];
        NSString *suffix = toggleInfo[@"currentDisplaySuffix"];
        NSString *fullText = [NSString stringWithFormat:@"%@ %@", baseName, suffix];
        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:fullText];
        
        NSRange baseRange = NSMakeRange(0, baseName.length + 1); // includes the space
        NSRange suffixRange = [fullText rangeOfString:suffix options:NSBackwardsSearch];
        
        UIColor *accentColor = [UIColor systemBlueColor];
        
        [attrStr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16 weight:UIFontWeightMedium] range:NSMakeRange(0, fullText.length)];
        [attrStr addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor] range:baseRange];
        if (suffixRange.location != NSNotFound) {
            [attrStr addAttribute:NSForegroundColorAttributeName value:accentColor range:suffixRange];
        }
        cell.textLabel.attributedText = attrStr;
        subtitle = nil;
    } else {
        cell.textLabel.attributedText = nil; // Clear any attributed text
        // The plain style first: a reused cell keeps the font of the row it last showed (a Terminal
        // Command's monospace, say), and once text is set attributedText is never nil to check
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        cell.textLabel.textColor = [UIColor labelColor];
        
        NSAttributedString *paramAttrStr = [self attributedDisplayNameForCommand:action];
        if (paramAttrStr) {
            cell.textLabel.attributedText = paramAttrStr;
            subtitle = nil;
            if ([action hasPrefix:@"shortcut:"]) {
                BOOL silent = NO;
                [RCConfigManager shortcutNameForAction:action silent:&silent input:NULL];
                if (silent) subtitle = @"Silent";
            }
        } else {
            if ([action hasPrefix:@"exec "]) {
                cell.textLabel.text = [action substringFromIndex:5];
                subtitle = @"Terminal Command";
            } else if ([action hasPrefix:@"root "]) {
                cell.textLabel.text = [action substringFromIndex:5];
                subtitle = @"Root Command";
            } else if ([action hasPrefix:@"Lua "] || [action hasPrefix:@"lua "]) {
                cell.textLabel.text = [action hasPrefix:@"Lua "] ? [action substringFromIndex:4] : [action substringFromIndex:4];
                subtitle = @"Lua Script";
            } else if ([action hasPrefix:@"delay "]) {
                cell.textLabel.text = [NSString stringWithFormat:@"Wait %@s", [action substringFromIndex:6]];
                subtitle = [NSString stringWithFormat:@"%@ seconds", [action substringFromIndex:6]];
            } else if ([action hasPrefix:@"shortcut:"]) {
                cell.textLabel.text = cleanName;
                subtitle = @"Siri Shortcut";
            } else if ([action hasPrefix:@"uiopen "]) {
                cell.textLabel.text = cleanName;
                subtitle = @"Application";
            } else if ([action hasPrefix:@"kill "]) {
                cell.textLabel.text = cleanName;
                subtitle = @"Kill Application";
            } else if ([action hasPrefix:@"airplay connect "]) {
                cell.textLabel.text = cleanName;
                subtitle = @"AirPlay Device";
            } else if ([action hasPrefix:@"bt connect "] || [action hasPrefix:@"bluetooth connect "]) {
                cell.textLabel.text = cleanName;
                subtitle = @"Bluetooth Device";
            } else if ([action hasPrefix:@"bt disconnect "] || [action hasPrefix:@"bluetooth disconnect "]) {
                cell.textLabel.text = cleanName;
                subtitle = nil;
            } else if ([action hasPrefix:@"airplay disconnect"]) {
                cell.textLabel.text = cleanName;
                subtitle = nil;
            } else if ([action isEqualToString:@"respring"] || [action isEqualToString:@"safemode"] || [action isEqualToString:@"safe-mode"] || [action isEqualToString:@"ldrestart"] || [action isEqualToString:@"userspace-reboot"] || [action isEqualToString:@"uicache"] || [action isEqualToString:@"player status"]) {
                cell.textLabel.text = cleanName;
                subtitle = nil;
            } else {
                cell.textLabel.text = cleanName;
                subtitle = nil;
            }
        }
    }

    if (subtitle) {
        cell.detailTextLabel.text = subtitle;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

        // Use monospace for code-like things
        if ([action hasPrefix:@"exec "] || [action hasPrefix:@"root "] || [action hasPrefix:@"Lua "] || [action hasPrefix:@"lua "]) {
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
            cell.textLabel.numberOfLines = wrapLongNames ? 0 : 1;
            cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        } else {
             cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
             cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
             cell.textLabel.numberOfLines = wrapLongNames ? 0 : 1;
        }
    } else {
        cell.detailTextLabel.text = nil;
        // No subtitle: long names (shortcuts, apps, entities, toast text) wrap to a
        // second line rather than being cut off
        cell.textLabel.numberOfLines = wrapLongNames ? 0 : 1;
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    NSString *iconName = [self iconForCommand:action];
    if ([iconName hasPrefix:@"USER_APP:"]) {
        NSString *bundleId = [iconName substringFromIndex:9];
        cell.imageView.image = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:0 scale:[UIScreen mainScreen].scale];
        cell.imageView.tintColor = nil;
    } else {
        cell.imageView.image = [UIImage systemImageNamed:iconName];
        cell.imageView.tintColor = [UIColor systemGrayColor];
    }

    // Custom reorder handle (since editing = NO)
    UIImageView *handleView = [[UIImageView alloc] initWithImage:RCGrabberImage()];
    handleView.tintColor = [UIColor systemGray3Color];
    cell.accessoryView = handleView;
    [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
    
    BOOL isDisabled = [[RCConfigManager sharedManager] isActionDisabled:actionItem];
    cell.contentView.alpha = isDisabled ? 0.38f : 1.0f;
    cell.accessoryView.alpha = isDisabled ? 0.38f : 1.0f;
    return cell;
}

- (void)applyIndentGuidesToCell:(UITableViewCell *)cell level:(NSInteger)indentationLevel {
    for (UIView *subview in [cell.contentView.subviews copy]) {
        if (subview.tag == 998811) {
            [subview removeFromSuperview];
        }
    }
    
    if (indentationLevel <= 0) return;
    
    UIView *container = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.userInteractionEnabled = NO;
    container.tag = 998811;
    
    CGFloat indentWidth = cell.indentationWidth > 0 ? cell.indentationWidth : 14.0f;
    CGFloat baseMargin = 16.0f;
    CGFloat lineW = 1.0f / [UIScreen mainScreen].scale;
    
    RCConfigManager *config = [RCConfigManager sharedManager];
    UIColor *lineColor = [config tweakColorForKey:@"separators" defaultVal:0.25];
    
    for (NSInteger i = 1; i <= indentationLevel; i++) {
        CGFloat x = baseMargin + (i - 1) * indentWidth + 6.0f;
        
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(x, 0, lineW, cell.contentView.bounds.size.height)];
        line.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        line.backgroundColor = lineColor;
        line.userInteractionEnabled = NO;
        [container addSubview:line];
    }
    
    [cell.contentView addSubview:container];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self applySectionCardStyleToCell:cell atIndexPath:indexPath];
    if ([self runShown]) cell.accessoryView.hidden = YES; // no drag handles while it runs
    else cell.accessoryView.hidden = NO;
    NSInteger level = [self indentationLevelForRow:indexPath.row];
    [self applyIndentGuidesToCell:cell level:level];
    // Rows being dragged stay dimmed as they scroll back into view (and a reused cell doesn't)
    BOOL dragged = self.reorderSnapshot && NSLocationInRange(indexPath.row, self.reorderRange);
    cell.alpha = dragged ? 0.3 : 1.0;
    [self fixColorsForDragOnCell:cell];
}

#pragma mark - Reordering

// Two ways to pick up a row: the grabber at once (a short press), or a long press anywhere that
// then moves. A long press that doesn't move opens the row's options instead, on release.
- (void)installReorderGestures {
    UILongPressGestureRecognizer *grab = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleGrab:)];
    grab.minimumPressDuration = 0.12;
    grab.allowableMovement = 10; // a quick swipe or scroll from the grabber stays a swipe or scroll
    grab.delegate = self;
    grab.name = @"rc.grab";
    [self.tableView addGestureRecognizer:grab];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleRowPress:)];
    press.minimumPressDuration = 0.5;
    press.allowableMovement = 10;
    press.delegate = self;
    press.name = @"rc.press";
    [self.tableView addGestureRecognizer:press];
}

// The grabber: the trailing end of a row
- (BOOL)isOnGrabber:(CGPoint)point {
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath) return NO;
    CGRect row = [self.tableView rectForRowAtIndexPath:indexPath];
    return point.x >= CGRectGetMaxX(row) - 56;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if ([gesture.name isEqualToString:@"rc.grab"]) {
        return ![self runShown] && !self.tableView.isEditing && [self isOnGrabber:[gesture locationInView:self.tableView]];
    }
    if ([gesture.name isEqualToString:@"rc.press"]) {
        return !self.reorderSnapshot && ![self isOnGrabber:[gesture locationInView:self.tableView]];
    }
    return YES;
}

- (void)handleGrab:(UILongPressGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.tableView];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: [self beginReorderAtPoint:point]; break;
        case UIGestureRecognizerStateChanged: [self moveReorderToPoint:point]; break;
        case UIGestureRecognizerStateEnded: [self endReorder:YES]; break;
        default: [self endReorder:NO]; break;
    }
}

- (void)handleRowPress:(UILongPressGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.tableView];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            self.pressStart = point;
            self.pressMoved = NO;
            UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [haptic impactOccurred];
            break;
        }
        case UIGestureRecognizerStateChanged:
            if (!self.pressMoved && hypot(point.x - self.pressStart.x, point.y - self.pressStart.y) > 10) {
                self.pressMoved = YES;
                if (![self runShown] && [self.tableView indexPathForRowAtPoint:self.pressStart]) [self beginReorderAtPoint:self.pressStart];
            }
            if (self.reorderSnapshot) [self moveReorderToPoint:point];
            break;
        case UIGestureRecognizerStateEnded:
            if (self.reorderSnapshot) [self endReorder:YES];
            else if (!self.pressMoved) [self showOptionsAtPoint:point];
            break;
        default:
            [self endReorder:NO];
            break;
    }
}

- (void)beginReorderAtPoint:(CGPoint)point {
    if (self.reorderSnapshot) return;
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath || indexPath.row >= (NSInteger)self.actions.count) return;
    NSRange range = [self ifBlockRangeForIndex:indexPath.row];
    if (range.location == NSNotFound || range.length == 0) return;
    self.reorderRange = range;
    self.reorderGap = range.location;

    // A picture of the rows (as far as they're on screen), taken by the page itself
    CGRect first = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:range.location inSection:0]];
    CGRect last = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:NSMaxRange(range) - 1 inSection:0]];
    CGRect visible = CGRectMake(0, self.tableView.contentOffset.y, self.tableView.bounds.size.width, self.tableView.bounds.size.height);
    CGRect area = CGRectIntersection(CGRectUnion(first, last), visible);
    if (CGRectIsEmpty(area)) area = first;
    UIView *snapshot = [self.tableView resizableSnapshotViewFromRect:area afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
    if (!snapshot) return;
    snapshot.frame = area;
    snapshot.layer.shadowColor = [UIColor blackColor].CGColor;
    snapshot.layer.shadowOpacity = 0.35;
    snapshot.layer.shadowRadius = 10;
    snapshot.layer.shadowOffset = CGSizeMake(0, 4);
    [self.tableView addSubview:snapshot];
    self.reorderSnapshot = snapshot;
    // Held above the finger and a little to the right, so the line where it lands (at the finger)
    // stays in sight
    self.reorderGrabOffset = -(area.size.height / 2 + 18);

    UIView *line = [[UIView alloc] init];
    line.backgroundColor = [UIColor systemBlueColor];
    line.layer.cornerRadius = 2;
    line.hidden = YES;
    [self.tableView addSubview:line];
    self.reorderLine = line;

    [self setReorderRowsDimmed:YES];
    CGPoint lifted = CGPointMake(CGRectGetMidX(area) + 16, point.y + self.reorderGrabOffset);
    [UIView animateWithDuration:0.18 animations:^{
        snapshot.transform = CGAffineTransformMakeScale(0.96, 0.96);
        snapshot.center = lifted;
        snapshot.alpha = 0.92;
    }];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    self.reorderTick = [[UISelectionFeedbackGenerator alloc] init];
    [self.reorderTick prepare];

    self.reorderScrollLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(reorderAutoScroll)];
    [self.reorderScrollLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.tableView.scrollEnabled = NO; // the finger moves the rows, not the list (it scrolls at the edges)
    [self moveReorderToPoint:point];
}

- (void)setReorderRowsDimmed:(BOOL)dimmed {
    for (NSUInteger row = self.reorderRange.location; row < NSMaxRange(self.reorderRange); row++) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
        cell.alpha = dimmed ? 0.3 : 1.0;
    }
}

- (void)moveReorderToPoint:(CGPoint)point {
    if (!self.reorderSnapshot) return;
    CGPoint center = self.reorderSnapshot.center;
    center.y = point.y + self.reorderGrabOffset;
    self.reorderSnapshot.center = center;
    self.reorderFingerY = point.y - self.tableView.contentOffset.y;

    // The gap the finger is nearest: above a row's middle is before it, below is after it
    NSInteger gap = self.reorderGap;
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:CGPointMake(CGRectGetMidX(self.tableView.bounds), point.y)];
    if (indexPath) {
        CGRect rect = [self.tableView rectForRowAtIndexPath:indexPath];
        gap = point.y < CGRectGetMidY(rect) ? indexPath.row : indexPath.row + 1;
    } else if (self.actions.count) {
        CGRect lastRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:self.actions.count - 1 inSection:0]];
        gap = point.y > CGRectGetMaxY(lastRect) ? (NSInteger)self.actions.count : 0;
    }
    // Inside the rows being moved: where they are now
    if (gap > (NSInteger)self.reorderRange.location && gap < (NSInteger)NSMaxRange(self.reorderRange)) gap = self.reorderRange.location;
    // Only where the blocks stay whole (an Else stays in its If, an End with its start)
    if (gap != self.reorderGap && ![self reorderGapIsValid:gap]) gap = self.reorderGap;
    if (gap != self.reorderGap) {
        self.reorderGap = gap;
        [self.reorderTick selectionChanged];
        [self.reorderTick prepare];
    }
    [self placeReorderLine];
}

// The actions as they'd be with the dragged rows moved to the gap
- (NSArray *)actionsAfterMovingToGap:(NSInteger)gap {
    NSMutableArray *moved = [self.actions mutableCopy];
    NSArray *items = [moved subarrayWithRange:self.reorderRange];
    [moved removeObjectsInRange:self.reorderRange];
    NSInteger insertAt = gap > (NSInteger)self.reorderRange.location ? gap - (NSInteger)self.reorderRange.length : gap;
    insertAt = MAX(0, MIN(insertAt, (NSInteger)moved.count));
    [moved insertObjects:items atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(insertAt, items.count)]];
    return moved;
}

// Whether the If and Repeat blocks are all whole: each End closes its own kind, Else and Else If
// only directly inside an If, nothing left open
- (BOOL)actionsAreWellFormed:(NSArray *)actions {
    NSMutableArray *open = [NSMutableArray array];
    for (id item in actions) {
        if ([self isIfActionItem:item]) [open addObject:@"if"];
        else if ([self isRepeatActionItem:item]) [open addObject:@"repeat"];
        else if ([self isElseActionItem:item] || [self isElseIfActionItem:item]) {
            if (![open.lastObject isEqualToString:@"if"]) return NO;
        } else if ([self isEndIfActionItem:item]) {
            if (![open.lastObject isEqualToString:@"if"]) return NO;
            [open removeLastObject];
        } else if ([self isEndRepeatActionItem:item]) {
            if (![open.lastObject isEqualToString:@"repeat"]) return NO;
            [open removeLastObject];
        }
    }
    return open.count == 0;
}

- (BOOL)reorderGapIsValid:(NSInteger)gap {
    if (gap == (NSInteger)self.reorderRange.location || gap == (NSInteger)NSMaxRange(self.reorderRange)) return YES; // where it is
    // A list already out of shape doesn't hold every move back
    if (![self actionsAreWellFormed:self.actions]) return YES;
    return [self actionsAreWellFormed:[self actionsAfterMovingToGap:gap]];
}

// The line between the rows at the gap, indented as deep as the moved rows would sit
- (void)placeReorderLine {
    NSInteger gap = self.reorderGap;
    BOOL inPlace = gap == (NSInteger)self.reorderRange.location || gap == (NSInteger)NSMaxRange(self.reorderRange);
    self.reorderLine.hidden = inPlace;
    if (inPlace || !self.actions.count) return;
    CGFloat y;
    if (gap < (NSInteger)self.actions.count) y = CGRectGetMinY([self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:gap inSection:0]]);
    else y = CGRectGetMaxY([self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:self.actions.count - 1 inSection:0]]);
    NSInteger depth = 0;
    for (NSInteger i = 0; i < gap; i++) {
        if (i >= (NSInteger)self.reorderRange.location && i < (NSInteger)NSMaxRange(self.reorderRange)) continue;
        id item = self.actions[i];
        if ([self isBlockStartItem:item]) depth++;
        else if ([self isBlockEndItem:item]) depth = MAX(0, depth - 1);
    }
    CGRect row = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:MIN(gap, (NSInteger)self.actions.count - 1) inSection:0]];
    CGFloat x = CGRectGetMinX(row) + 14 + depth * 14;
    self.reorderLine.frame = CGRectMake(x, y - 2, CGRectGetMaxX(row) - 12 - x, 4);
    [self.tableView bringSubviewToFront:self.reorderLine];
    [self.tableView bringSubviewToFront:self.reorderSnapshot];
}

// Near the top or bottom of the list, it scrolls (faster the closer the finger)
- (void)reorderAutoScroll {
    if (!self.reorderSnapshot) return;
    UITableView *table = self.tableView;
    CGFloat top = table.adjustedContentInset.top, height = table.bounds.size.height;
    CGFloat edge = 70, step = 0;
    if (self.reorderFingerY < top + edge) step = -(top + edge - self.reorderFingerY) / 6;
    else if (self.reorderFingerY > height - edge) step = (self.reorderFingerY - (height - edge)) / 6;
    if (step == 0) return;
    CGFloat minY = -top;
    CGFloat maxY = MAX(minY, table.contentSize.height + table.adjustedContentInset.bottom - height);
    CGFloat newY = MAX(minY, MIN(maxY, table.contentOffset.y + step));
    if (newY == table.contentOffset.y) return;
    table.contentOffset = CGPointMake(table.contentOffset.x, newY);
    [self moveReorderToPoint:CGPointMake(0, newY + self.reorderFingerY)];
}

- (void)endReorder:(BOOL)commit {
    if (!self.reorderSnapshot) return;
    [self.reorderScrollLink invalidate];
    self.reorderScrollLink = nil;
    self.tableView.scrollEnabled = YES;
    UIView *snapshot = self.reorderSnapshot;
    UIView *line = self.reorderLine;
    self.reorderSnapshot = nil;
    self.reorderLine = nil;
    NSInteger gap = self.reorderGap;
    NSRange range = self.reorderRange;
    BOOL moves = commit && gap != (NSInteger)range.location && gap != (NSInteger)NSMaxRange(range) && [self reorderGapIsValid:gap];
    [self setReorderRowsDimmed:NO];
    [line removeFromSuperview];
    if (moves) {
        NSInteger finalIndex = gap > (NSInteger)range.location ? gap - (NSInteger)range.length : gap;
        [self moveActionFromIndex:range.location toFinalIndex:finalIndex];
        [snapshot removeFromSuperview];
        return;
    }
    // Back where it came from
    CGRect home = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:range.location inSection:0]];
    [UIView animateWithDuration:0.2 animations:^{
        snapshot.transform = CGAffineTransformIdentity;
        snapshot.frame = CGRectMake(snapshot.frame.origin.x, home.origin.y, snapshot.frame.size.width, snapshot.frame.size.height);
        snapshot.alpha = 0;
    } completion:^(__unused BOOL finished) { [snapshot removeFromSuperview]; }];
}

// Swipe Actions
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self runShown]) return [UISwipeActionsConfiguration configurationWithActions:@[]];
    NSRange rangeToDelete = [self ifBlockRangeForIndex:indexPath.row];
    BOOL isBlockDelete = rangeToDelete.length > 1;
    
    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
        title:isBlockDelete ? @"Delete Block" : @"Delete"
        handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            // A block with actions in it: delete them too, or keep them where they are
            NSInteger inside = isBlockDelete ? [self actionCountInsideBlockRange:rangeToDelete] : 0;
            if (inside > 0 && NSMaxRange(rangeToDelete) <= self.actions.count) {
                [self confirmDeleteBlockRange:rangeToDelete actionCount:inside from:sourceView completion:completionHandler];
                return;
            }
            if (rangeToDelete.location != NSNotFound && rangeToDelete.length > 0 && NSMaxRange(rangeToDelete) <= self.actions.count) {
                [self.actions removeObjectsInRange:rangeToDelete];
            } else if (indexPath.row < self.actions.count) {
                [self.actions removeObjectAtIndex:indexPath.row];
            }
            [self saveActions];
            [tableView reloadData];
            completionHandler(YES);
        }];

    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

// The actions inside a block (nested blocks' rows counted as theirs), not its Else and Else If rows
- (NSInteger)actionCountInsideBlockRange:(NSRange)range {
    NSInteger count = 0;
    for (NSUInteger i = range.location + 1; i + 1 < NSMaxRange(range); i++) {
        id item = self.actions[i];
        if ([self isElseActionItem:item] || [self isElseIfActionItem:item] || [self isBlockEndItem:item]) continue;
        count++;
    }
    return count;
}

- (void)confirmDeleteBlockRange:(NSRange)range actionCount:(NSInteger)count from:(UIView *)sourceView completion:(void (^)(BOOL))completion {
    NSString *message = count == 1 ? @"This block contains 1 action." : [NSString stringWithFormat:@"This block contains %ld actions.", (long)count];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Delete Block" message:message preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Keep Actions" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [weakSelf unwrapBlockRange:range];
        completion(YES);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete All" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && NSMaxRange(range) <= strongSelf.actions.count) {
            [strongSelf.actions removeObjectsInRange:range];
            [strongSelf saveActions];
            [strongSelf.tableView reloadData];
        }
        completion(YES);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {
        completion(NO);
    }]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = sourceView ?: self.view;
        sheet.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

// Keep Actions: the block's own rows go (its start, its end, and its Else and Else If rows), and
// everything inside stays in order, nested blocks included
- (void)unwrapBlockRange:(NSRange)range {
    if (NSMaxRange(range) > self.actions.count || range.length < 2) return;
    NSMutableIndexSet *remove = [NSMutableIndexSet indexSetWithIndex:range.location];
    [remove addIndex:NSMaxRange(range) - 1];
    NSInteger depth = 0;
    for (NSUInteger i = range.location + 1; i + 1 < NSMaxRange(range); i++) {
        id item = self.actions[i];
        if ([self isBlockStartItem:item]) depth++;
        else if ([self isBlockEndItem:item]) depth--;
        else if (depth == 0 && ([self isElseActionItem:item] || [self isElseIfActionItem:item])) [remove addIndex:i];
    }
    [self.actions removeObjectsAtIndexes:remove];
    [self saveActions];
    [self.tableView reloadData];
}

// Reordering (legacy but kept for logic reference, though drag/drop is primary now)
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    [self moveActionFromIndex:sourceIndexPath.row toFinalIndex:destinationIndexPath.row];
}

// Deletion (legacy - leading/trailing swipe actions are preferred now)
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone; // Prevent standard delete indicator
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}


@end
