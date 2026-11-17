#import "RCInlineRowItem.h"

#import <math.h>

NSString *const RCInlineRowValueChangedNotification = @"RCInlineRowValueChangedNotification";

// A typed number, or NO for "{name}" and anything unfinished.
static BOOL RCInlineRowNumberFromText(NSString *text, double *outValue) {
    NSString *trimmed = [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return NO;
    if ([trimmed hasPrefix:@"{"]) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:[trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."]];
    double value = 0;
    if (![scanner scanDouble:&value] || !scanner.isAtEnd) return NO;
    if (outValue) *outValue = value;
    return YES;
}

// A saved or Run Only variable's name
static BOOL RCInlineRowNameIsValid(NSString *name) {
    if (!name.length) return NO;
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    unichar first = [name characterAtIndex:0];
    if (![letters characterIsMember:first] && first != '_') return NO;
    for (NSUInteger i = 1; i < name.length; i++) {
        unichar character = [name characterAtIndex:i];
        if (![letters characterIsMember:character] && ![digits characterIsMember:character] && character != '_') return NO;
    }
    return YES;
}

@implementation RCInlineRowItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _minimumValue = 0;
        _maximumValue = 100;
        _step = 1;
        _decimals = 0;
        _allowsRound = YES;
        _options = @[];
        _choiceIndex = 0;
    }
    return self;
}

- (NSString *)numberText {
    NSString *text = [NSString stringWithFormat:@"%.*f", (int)MAX(0, self.decimals), self.numberValue];
    if (self.decimals > 0) {
        while ([text hasSuffix:@"0"]) text = [text substringToIndex:text.length - 1];
        if ([text hasSuffix:@"."]) text = [text substringToIndex:text.length - 1];
    }
    return text;
}

- (NSString *)choiceValue {
    if (self.choiceIndex < 0 || self.choiceIndex >= (NSInteger)self.options.count) return nil;
    if (self.optionValues.count == self.options.count) return self.optionValues[self.choiceIndex];
    return self.options[self.choiceIndex];
}

- (NSString *)displayValue {
    if (self.variableName.length) return [NSString stringWithFormat:@"{%@}", self.variableName];
    if (self.kind == RCInlineRowKindNumber) {
        NSString *unit = self.unit ?: @"";
        if (!unit.length) return [self numberText];
        return [NSString stringWithFormat:@"%@%@%@", [self numberText], self.unitNeedsSpace ? @" " : @"", unit];
    }
    if (self.kind == RCInlineRowKindChoice) {
        if (self.choiceIndex >= 0 && self.choiceIndex < (NSInteger)self.options.count) return self.options[self.choiceIndex];
        return @"Not set";
    }
    return self.textValue.length ? self.textValue : @"Not set";
}

- (NSString *)editableNumberText {
    if (self.variableName.length) return [NSString stringWithFormat:@"{%@}", self.variableName];
    return [self numberText];
}

- (void)applyEditableNumberText:(NSString *)text {
    NSString *trimmed = [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed hasPrefix:@"{"]) {
        NSString *name = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"{}"]];
        self.variableName = name.length ? name : nil;
        return;
    }
    double number = 0;
    if (!RCInlineRowNumberFromText(trimmed, &number)) return;
    if (!self.allowsDecimals && floor(number) != number) return;
    self.variableName = nil;
    self.numberValue = number;
}

- (NSString *)command {
    if (self.commandBuilder) return self.commandBuilder(self);
    NSString *prefix = self.prefix ?: @"";
    if (self.kind == RCInlineRowKindText) {
        NSString *text = [self.textValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!text.length) return nil;
        return [prefix stringByAppendingString:text];
    }
    if (self.kind == RCInlineRowKindChoice) {
        NSString *value = [self choiceValue];
        if (!value.length) return nil;
        return [prefix stringByAppendingString:value];
    }
    if (self.variableName.length) {
        if ([self.variableName isEqualToString:@"round"] && !self.allowsRound) return nil;
        if (!RCInlineRowNameIsValid(self.variableName)) return nil;
        return [NSString stringWithFormat:@"%@{%@}", prefix, self.variableName];
    }
    double number = self.numberValue;
    if (!self.allowsDecimals && floor(number) != number) return nil;
    if (number < self.minimumValue || number > self.maximumValue) return nil;
    NSString *text = self.allowsDecimals ? [NSString stringWithFormat:@"%.10g", number]
                                         : [NSString stringWithFormat:@"%ld", (long)llround(number)];
    return [prefix stringByAppendingString:text];
}

@end

void RCInlineRowNotifyValueChanged(RCInlineRowItem *item) {
    if (!item) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:RCInlineRowValueChangedNotification object:item];
}
