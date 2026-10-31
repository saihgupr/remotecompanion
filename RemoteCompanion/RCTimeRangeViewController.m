#import "RCTimeRangeViewController.h"
#import "RCConfigManager.h"
#import "RCVariableEditorParts.h"

// Minutes after midnight for "09:00", "9:30 PM", "9 am"..., read the way the tweak reads them; -1 if none
static NSInteger RCTimeRangeMinutes(NSString *text) {
    NSString *clean = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if (!clean.length) return -1;
    BOOL pm = [clean containsString:@"PM"], am = [clean containsString:@"AM"];
    NSMutableString *digits = [NSMutableString string];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789:"];
    for (NSUInteger i = 0; i < clean.length; i++) {
        unichar c = [clean characterAtIndex:i];
        if ([allowed characterIsMember:c]) [digits appendFormat:@"%C", c];
    }
    NSArray *parts = [digits componentsSeparatedByString:@":"];
    if (![parts.firstObject length]) return -1;
    NSInteger hour = [parts[0] integerValue], minute = parts.count > 1 ? [parts[1] integerValue] : 0;
    if (pm && hour < 12) hour += 12;
    else if (am && hour == 12) hour = 0;
    hour = MAX(0, MIN(23, hour));
    minute = MAX(0, MIN(59, minute));
    return hour * 60 + minute;
}

@interface RCTimeRangeViewController ()
@property (nonatomic, strong) UIDatePicker *startPicker;
@property (nonatomic, strong) UIDatePicker *endPicker;
@property (nonatomic, strong) RCSetVariableFooter *footer;
@property (nonatomic, assign) NSInteger startMinutes;
@property (nonatomic, assign) NSInteger endMinutes;
@property (nonatomic, copy) NSString *variableRange; // the range being edited, when it holds variables
@end

@implementation RCTimeRangeViewController

- (instancetype)initWithRange:(NSString *)range {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Time of Day";
        _startMinutes = 9 * 60;
        _endMinutes = 17 * 60;
        NSString *s = [range description] ?: @"";
        // Variables ("{wake} - 09:00") can't show on time pickers: the footer says Save replaces them
        if ([s rangeOfString:@"{"].location != NSNotFound) _variableRange = [s copy];
        for (NSString *dash in @[@"–", @"—", @" to "]) s = [s stringByReplacingOccurrencesOfString:dash withString:@"-" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
        NSArray *parts = [s componentsSeparatedByString:@"-"];
        if (parts.count >= 2) {
            NSInteger start = RCTimeRangeMinutes(parts[0]), end = RCTimeRangeMinutes(parts[1]);
            if (start >= 0 && end >= 0) { _startMinutes = start; _endMinutes = end; }
        }
    }
    return self;
}

- (NSDate *)dateForMinutes:(NSInteger)minutes {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    return [calendar dateBySettingHour:minutes / 60 minute:minutes % 60 second:0 ofDate:[NSDate date] options:0];
}

- (NSInteger)minutesForDate:(NSDate *)date {
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:date];
    return c.hour * 60 + c.minute;
}

- (UIDatePicker *)pickerForMinutes:(NSInteger)minutes {
    UIDatePicker *picker = [[UIDatePicker alloc] init];
    picker.datePickerMode = UIDatePickerModeTime;
    if (@available(iOS 14.0, *)) picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    picker.date = [self dateForMinutes:minutes];
    [picker addTarget:self action:@selector(pickerChanged) forControlEvents:UIControlEventValueChanged];
    [picker sizeToFit];
    return picker;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.saveTitle ?: @"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.startPicker = [self pickerForMinutes:self.startMinutes];
    self.endPicker = [self pickerForMinutes:self.endMinutes];
    self.footer = [[RCSetVariableFooter alloc] initWithReuseIdentifier:nil];
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 30;
}

- (void)pickerChanged {
    self.startMinutes = [self minutesForDate:self.startPicker.date];
    self.endMinutes = [self minutesForDate:self.endPicker.date];
    // The footer says whether the range runs past midnight. Only its text changes, so an
    // open time picker stays open.
    self.footer.label.text = [self footerText];
    [UIView performWithoutAnimation:^{
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    self.footer.label.text = [self footerText];
    return self.footer;
}

- (NSString *)footerText {
    if (self.variableRange) return [NSString stringWithFormat:@"Now “%@”, which uses variables. Save replaces it with these times; Cancel keeps it.", self.variableRange];
    if (self.startMinutes == self.endMinutes) return @"True for that one minute.";
    if (self.endMinutes < self.startMinutes) return @"True from the start time, past midnight, until the end time.";
    return @"True from the start time until the end time.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.text = indexPath.row == 0 ? @"Start" : @"End";
    cell.accessoryView = indexPath.row == 0 ? self.startPicker : self.endPicker;
    return cell;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    NSInteger start = [self minutesForDate:self.startPicker.date], end = [self minutesForDate:self.endPicker.date];
    NSString *value = [NSString stringWithFormat:@"%02ld:%02ld - %02ld:%02ld", (long)(start / 60), (long)(start % 60), (long)(end / 60), (long)(end % 60)];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterNoStyle;
    f.timeStyle = NSDateFormatterShortStyle;
    NSString *title = [NSString stringWithFormat:@"%@ – %@", [f stringFromDate:self.startPicker.date], [f stringFromDate:self.endPicker.date]];
    void (^onSave)(NSString *, NSString *) = self.onSave;
    [self dismissViewControllerAnimated:YES completion:^{
        if (onSave) onSave(value, title);
    }];
}

@end
