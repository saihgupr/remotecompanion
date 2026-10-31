#import "RCCommandPickerViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

// Sections: title, rows of { title, command, icon, number? }
static NSArray<NSArray *> *RCValueCommandSections(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @[@"Levels", @[
                @{ @"title": @"Battery Level", @"command": @"battery", @"icon": @"battery.75", @"number": @YES },
                @{ @"title": @"Volume", @"command": @"volume", @"icon": @"speaker.wave.2.fill", @"number": @YES },
            ]],
            @[@"Connectivity", @[
                @{ @"title": @"Wi-Fi", @"command": @"wifi status", @"icon": @"wifi" },
                @{ @"title": @"Bluetooth", @"command": @"bt status", @"icon": @"antenna.radiowaves.left.and.right" },
                @{ @"title": @"Cellular Data", @"command": @"cell status", @"icon": @"antenna.radiowaves.left.and.right" },
                @{ @"title": @"Airplane Mode", @"command": @"airplane status", @"icon": @"airplane" },
                @{ @"title": @"Location Services", @"command": @"location status", @"icon": @"location.fill" },
                @{ @"title": @"CarPlay", @"command": @"carplay status", @"icon": @"car.fill" },
            ]],
            @[@"Sound", @[
                @{ @"title": @"Ringer", @"command": @"ringer status", @"icon": @"bell.fill" },
                @{ @"title": @"Silent Vibrate", @"command": @"vibration silent-status", @"icon": @"iphone.radiowaves.left.and.right" },
                @{ @"title": @"Haptics", @"command": @"haptics status", @"icon": @"hand.tap.fill", @"fallbackIcon": @"hand.point.up.fill" },
                @{ @"title": @"Media Playing", @"command": @"is-playing", @"icon": @"play.fill" },
            ]],
            @[@"Device", @[
                @{ @"title": @"Lock State", @"command": @"lock status", @"icon": @"lock.fill" },
                @{ @"title": @"Low Power Mode", @"command": @"low power status", @"icon": @"battery.25" },
                @{ @"title": @"Flashlight", @"command": @"flashlight status", @"icon": @"flashlight.on.fill" },
                @{ @"title": @"Do Not Disturb", @"command": @"dnd status", @"icon": @"moon.fill" },
                @{ @"title": @"Focus", @"command": @"focus status", @"icon": @"moon.circle.fill" },
                @{ @"title": @"Screen Recording", @"command": @"screenrecord status", @"icon": @"record.circle" },
                @{ @"title": @"Proximity", @"command": @"proximity status", @"icon": @"sensor.tag.radiowaves.forward.fill", @"fallbackIcon": @"hand.raised.fill" },
            ]],
            @[@"Display", @[
                @{ @"title": @"Orientation", @"command": @"orientation status", @"icon": @"rectangle.portrait.rotate", @"fallbackIcon": @"rotate.right.fill" },
                @{ @"title": @"Appearance", @"command": @"appearance status", @"icon": @"circle.lefthalf.filled", @"fallbackIcon": @"circle.lefthalf.fill" },
                @{ @"title": @"Auto-Lock", @"command": @"autolock status", @"icon": @"timer" },
            ]],
        ];
    });
    return list;
}

@interface RCCommandPickerViewController ()
@property (nonatomic, copy) NSString *selected;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *answers; // command -> first line
@end

@implementation RCCommandPickerViewController

- (instancetype)initWithSelectedCommand:(NSString *)selected {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _selected = [[selected stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString] ?: @"";
        _answers = [NSMutableDictionary dictionary];
        self.title = @"Command";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    [self loadAnswers];
}

// Runs each command once, one after another, and shows its answer in its row
- (void)loadAnswers {
    NSMutableArray<NSString *> *queue = [NSMutableArray array];
    for (NSArray *section in RCValueCommandSections()) for (NSDictionary *row in section[1]) [queue addObject:row[@"command"]];
    [self askNext:queue];
}

- (void)askNext:(NSMutableArray<NSString *> *)queue {
    if (!queue.count || !self.isViewLoaded) return;
    NSString *command = queue.firstObject;
    [queue removeObjectAtIndex:0];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:command completion:^(NSString *output, NSError *error) {
        NSString *line = [[output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@"\n"].firstObject;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.navigationController) return; // gone back
            strongSelf.answers[command] = line.length ? line : @"—";
            NSIndexPath *path = [strongSelf indexPathForCommand:command];
            if (path) [strongSelf.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
            [strongSelf askNext:queue];
        });
    }];
}

- (NSIndexPath *)indexPathForCommand:(NSString *)command {
    NSArray *sections = RCValueCommandSections();
    for (NSUInteger s = 0; s < sections.count; s++) {
        NSArray *rows = sections[s][1];
        for (NSUInteger r = 0; r < rows.count; r++) if ([rows[r][@"command"] isEqualToString:command]) return [NSIndexPath indexPathForRow:r inSection:s];
    }
    return nil;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RCValueCommandSections().count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [RCValueCommandSections()[section][1] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return RCValueCommandSections()[section][0];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Levels are stored as a number, such as 85.";
    if (section == (NSInteger)RCValueCommandSections().count - 1) return @"Each row shows the answer this phone gives now; the variable stores the answer at run time.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = RCValueCommandSections()[indexPath.section][1][indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Command"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Command"];
    cell.backgroundColor = [[RCConfigManager sharedManager] tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.text = row[@"title"];
    NSString *answer = self.answers[row[@"command"]];
    NSMutableAttributedString *detail = [[NSMutableAttributedString alloc] initWithString:row[@"command"] attributes:@{
        NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor] }];
    [detail appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"   %@", answer ?: @"…"] attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: answer ? [UIColor systemBlueColor] : [UIColor tertiaryLabelColor] }]];
    cell.detailTextLabel.attributedText = detail;
    UIImage *icon = [UIImage systemImageNamed:row[@"icon"]] ?: [UIImage systemImageNamed:row[@"fallbackIcon"] ?: @"terminal"];
    cell.imageView.image = icon;
    cell.imageView.tintColor = [UIColor systemBlueColor];
    cell.imageView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
    cell.accessoryType = [row[@"command"] isEqualToString:self.selected] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = RCValueCommandSections()[indexPath.section][1][indexPath.row];
    self.selected = row[@"command"];
    [tableView reloadData];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    if (self.onPick) self.onPick(row[@"command"], [row[@"number"] boolValue]);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    });
}

@end
