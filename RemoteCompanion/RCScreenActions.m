#import "RCScreenActions.h"

@implementation RCScreenActions

+ (NSArray<NSString *> *)verbs {
    return @[@"tap", @"wait"];
}

+ (NSString *)commandForVerb:(NSString *)verb text:(NSString *)text seconds:(double)seconds {
    // Quotes inside the text would end it early; the tweak reads up to the last quote, so
    // they're kept as they are
    NSString *command = [NSString stringWithFormat:@"screen %@ \"%@\"", verb, text];
    if ([verb isEqualToString:@"wait"]) command = [command stringByAppendingFormat:@" %g", seconds > 0 ? seconds : 10];
    return command;
}

+ (BOOL)parseCommand:(NSString *)command verb:(NSString **)verb text:(NSString **)text seconds:(double *)seconds {
    if (![command isKindOfClass:[NSString class]] || ![command hasPrefix:@"screen "]) return NO;
    NSString *rest = [command substringFromIndex:7];
    NSRange space = [rest rangeOfString:@" "];
    if (space.location == NSNotFound) return NO;
    NSString *v = [rest substringToIndex:space.location];
    if (![[self verbs] containsObject:v]) return NO;
    NSString *arg = [[rest substringFromIndex:space.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    double s = 10;
    NSString *t = arg;
    if ([arg hasPrefix:@"\""]) {
        NSRange close = [arg rangeOfString:@"\"" options:NSBackwardsSearch];
        if (close.location > 0) {
            NSString *after = [[arg substringFromIndex:close.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (after.length) s = after.doubleValue;
            t = [arg substringWithRange:NSMakeRange(1, close.location - 1)];
        }
    }
    if (verb) *verb = v;
    if (text) *text = t;
    if (seconds) *seconds = s;
    return YES;
}

+ (NSString *)nameForCommand:(NSString *)command {
    NSString *verb = nil, *text = nil;
    if (![self parseCommand:command verb:&verb text:&text seconds:NULL]) return nil;
    NSDictionary *names = @{ @"tap": @"Tap", @"wait": @"Wait for" };
    return [NSString stringWithFormat:@"%@ “%@”", names[verb], text];
}

+ (NSString *)iconForVerb:(NSString *)verb {
    NSDictionary *icons = @{ @"tap": @"hand.tap.fill", @"wait": @"hourglass" };
    NSString *icon = icons[verb];
    if (icon && [UIImage systemImageNamed:icon]) return icon;
    return [UIImage systemImageNamed:@"text.viewfinder"] ? @"text.viewfinder" : @"doc.text.magnifyingglass"; // iOS 15+
}

+ (void)promptForVerb:(NSString *)verb existing:(NSString *)command from:(UIViewController *)controller
               done:(void (^)(NSString *command))done {
    NSString *oldText = nil;
    double oldSeconds = 10;
    [self parseCommand:command verb:NULL text:&oldText seconds:&oldSeconds];
    NSDictionary *titles = @{ @"tap": @"Tap Text on Screen", @"wait": @"Wait for Text" };
    NSDictionary *messages = @{
        @"tap": @"Taps this text where it shows on the screen.",
        @"wait": @"Waits until this text shows on the screen, then goes on.",
    };
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:titles[verb] message:messages[verb]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Text (e.g. Wi-Fi)";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.text = oldText;
    }];
    BOOL wait = [verb isEqualToString:@"wait"];
    if (wait) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = @"Seconds (default 10)";
            field.keyboardType = UIKeyboardTypeDecimalPad;
            if (command) field.text = [NSString stringWithFormat:@"%g", oldSeconds];
        }];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:command ? @"Save" : @"Add" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *text = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!text.length) return;
        double seconds = wait ? alert.textFields[1].text.doubleValue : 0;
        if (wait && seconds <= 0) seconds = 10;
        if (done) done([self commandForVerb:verb text:text seconds:MIN(seconds, 120)]);
    }]];
    [controller presentViewController:alert animated:YES completion:nil];
}

@end
