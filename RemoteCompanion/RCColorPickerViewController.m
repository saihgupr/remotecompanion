#import "RCColorPickerViewController.h"

@implementation RCColorPickerViewController {
    NSString *_selected;
    NSArray<NSString *> *_names;
}

+ (NSArray<NSString *> *)colorNames {
    return @[@"red", @"orange", @"yellow", @"green", @"teal",
             @"blue", @"indigo", @"purple", @"pink", @"gray"];
}

+ (NSString *)titleForName:(NSString *)name {
    static NSDictionary *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = @{
            @"red": @"Red", @"orange": @"Orange", @"yellow": @"Yellow",
            @"green": @"Green", @"teal": @"Teal", @"blue": @"Blue",
            @"indigo": @"Indigo", @"purple": @"Purple", @"pink": @"Pink",
            @"gray": @"Gray"
        };
    });
    return titles[name] ?: @"Pink";
}

+ (UIColor *)colorForName:(NSString *)name {
    static NSDictionary *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colors = @{
            @"red": [UIColor systemRedColor],
            @"orange": [UIColor systemOrangeColor],
            @"yellow": [UIColor systemYellowColor],
            @"green": [UIColor systemGreenColor],
            @"teal": [UIColor systemTealColor],
            @"blue": [UIColor systemBlueColor],
            @"indigo": [UIColor systemIndigoColor],
            @"purple": [UIColor systemPurpleColor],
            @"pink": [UIColor systemPinkColor],
            @"gray": [UIColor systemGrayColor]
        };
    });
    return colors[name] ?: [UIColor systemPinkColor];
}

- (instancetype)initWithSelectedName:(NSString *)name {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _selected = [name copy] ?: @"pink";
        _names = [RCColorPickerViewController colorNames];
        self.title = @"Icon Color";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                           target:self
                                                                                           action:@selector(close)];
    self.tableView.rowHeight = 50;
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_names.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSString *name = _names[indexPath.row];
    cell.textLabel.text = [RCColorPickerViewController titleForName:name];
    cell.imageView.image = [UIImage systemImageNamed:@"circle.fill"];
    cell.imageView.tintColor = [RCColorPickerViewController colorForName:name];
    cell.accessoryType = [name isEqualToString:_selected] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = _names[indexPath.row];
    if (self.onPick) self.onPick(name);
    [self close];
}

@end
