#import "RCDelayPrototypeKit.h"
#import "RCConfigManager.h"

#import <math.h>

#pragma mark - Shared look

const CGFloat RCDelayColumnBreak = 700.0;

UIColor *RCDelayPageColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"mainBackground" defaultVal:0.09];
}

UIColor *RCDelayBlockColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12];
}

UIColor *RCDelayBorderColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"borders" defaultVal:0.14];
}

UIColor *RCDelaySeparatorColor(void) {
    return [[RCConfigManager sharedManager] tweakColorForKey:@"separators" defaultVal:0.30];
}

UIColor *RCDelayAccent(UIView *view) {
    return view.tintColor ?: [UIColor systemBlueColor];
}

// The default point sizes for the text styles, so a custom weight still scales
// from the right starting point through UIFontMetrics.
CGFloat RCDelayBasePointSize(UIFontTextStyle style) {
    if ([style isEqualToString:UIFontTextStyleLargeTitle]) return 34;
    if ([style isEqualToString:UIFontTextStyleTitle1]) return 28;
    if ([style isEqualToString:UIFontTextStyleTitle2]) return 22;
    if ([style isEqualToString:UIFontTextStyleTitle3]) return 20;
    if ([style isEqualToString:UIFontTextStyleHeadline]) return 17;
    if ([style isEqualToString:UIFontTextStyleBody]) return 17;
    if ([style isEqualToString:UIFontTextStyleCallout]) return 16;
    if ([style isEqualToString:UIFontTextStyleSubheadline]) return 15;
    if ([style isEqualToString:UIFontTextStyleFootnote]) return 13;
    if ([style isEqualToString:UIFontTextStyleCaption1]) return 12;
    if ([style isEqualToString:UIFontTextStyleCaption2]) return 11;
    return 17;
}

UIFont *RCDelayFont(UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:RCDelayBasePointSize(style) weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

UIFont *RCDelayDigitFontOfSize(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

UIFont *RCDelayDigitFont(UIFontTextStyle style, UIFontWeight weight) {
    return RCDelayDigitFontOfSize(RCDelayBasePointSize(style), style, weight);
}

UIFont *RCDelayMonoFont(CGFloat size, UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont monospacedSystemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

UILabel *RCDelayNoteLabel(NSString *text) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = RCDelayFont(UIFontTextStyleFootnote, UIFontWeightRegular);
    label.textColor = [UIColor secondaryLabelColor];
    label.numberOfLines = 0;
    return label;
}

// "2", "2.5", "0.03": no trailing zeroes, but nothing lost.
NSString *RCDelayTrimZeroes(NSString *text) {
    if ([text rangeOfString:@"."].location == NSNotFound) return text;
    NSString *trimmed = text;
    while ([trimmed hasSuffix:@"0"]) trimmed = [trimmed substringToIndex:trimmed.length - 1];
    if ([trimmed hasSuffix:@"."]) trimmed = [trimmed substringToIndex:trimmed.length - 1];
    return trimmed;
}

NSString *RCDelayFormat(double value, NSInteger decimals) {
    if (fabs(value - round(value)) < 0.000001 && decimals > 0) {
        return [NSString stringWithFormat:@"%.0f", value];
    }
    return RCDelayTrimZeroes([NSString stringWithFormat:@"%.*f", (int)decimals, value]);
}

// A number typed in the field, or NO for "{name}" and anything unfinished.
BOOL RCDelayNumberFromText(NSString *text, double *outValue) {
    NSString *trimmed = [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return NO;
    if ([trimmed hasPrefix:@"{"]) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:[trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."]];
    double value = 0;
    if (![scanner scanDouble:&value] || !scanner.isAtEnd) return NO;
    if (outValue) *outValue = value;
    return YES;
}

#pragma mark - Variant base

@implementation RCDelayVariantView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _valueText = @"2";
        self.backgroundColor = [UIColor clearColor];
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (void)setValueText:(NSString *)valueText {
    _valueText = [valueText copy] ?: @"";
    [self valueTextDidChange];
}

- (void)valueTextDidChange {
    // override
}

- (void)insertVariableNamed:(NSString *)name {
    self.valueText = [NSString stringWithFormat:@"{%@}", name];
}

- (UIButton *)makeVariableButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *image = [UIImage systemImageNamed:@"plus.circle"
                            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17
                                                                                             weight:UIImageSymbolWeightMedium]];
    [button setImage:image forState:UIControlStateNormal];
    button.frame = CGRectMake(0, 0, 34, 34);
    button.accessibilityLabel = @"Insert Variable";
    button.showsMenuAsPrimaryAction = YES;
    __weak typeof(self) weakSelf = self;
    // Sample variables, so the menu has the same shape as the real one.
    button.menu = RCVariableInsertMenuWithRound(@[@"count", @"attempt"], @[@"volume", @"battery"], YES, ^(NSString *name) {
        [weakSelf insertVariableNamed:name];
    });
    return button;
}

- (UITextField *)makeNumberField {
    UITextField *field = [[UITextField alloc] init];
    field.font = RCDelayDigitFont(UIFontTextStyleBody, UIFontWeightRegular);
    field.textColor = [UIColor labelColor];
    field.tintColor = [UIColor systemBlueColor];
    field.keyboardType = UIKeyboardTypeDecimalPad;
    field.textAlignment = NSTextAlignmentRight;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.text = self.valueText;
    return field;
}

@end
