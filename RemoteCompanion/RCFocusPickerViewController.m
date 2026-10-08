#import "RCFocusPickerViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"

@interface RCFocusPickerViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *fixedRows;
@property (nonatomic, strong) NSArray<NSDictionary *> *modes;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *errorText;
@end

@implementation RCFocusPickerViewController

- (instancetype)initWithTitle:(NSString *)title fixedRows:(NSArray<NSDictionary *> *)fixedRows {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _fixedRows = [fixedRows copy] ?: @[];
        _modes = @[];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = 52;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *bg = [cm tweakColorForKey:@"actionPickerBackground" defaultVal:mainBG];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    }

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

    [self reload];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Loading

- (void)reload {
    self.loading = YES;
    self.errorText = nil;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"focus list" completion:^(NSString *output, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.loading = NO;
        [strongSelf.refreshControl endRefreshing];
        if (error || !output) {
            strongSelf.errorText = error.localizedDescription ?: @"Couldn't fetch Focus modes";
            strongSelf.modes = @[];
        } else {
            strongSelf.modes = [strongSelf modesFromOutput:output];
        }
        [strongSelf.tableView reloadData];
    }];
}

// One per line: the name, a tab, its SF Symbol. Anything else is a message from the tweak.
- (NSArray<NSDictionary *> *)modesFromOutput:(NSString *)output {
    NSMutableArray *modes = [NSMutableArray array];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        NSString *name = [parts.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0) continue;
        if (parts.count < 2) {
            self.errorText = [name hasPrefix:@"Error: "] ? [name substringFromIndex:7] : name;
            continue;
        }
        NSString *symbol = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [modes addObject:@{ @"name": name, @"value": name, @"icon": [UIImage systemImageNamed:symbol] ? symbol : @"moon.fill" }];
    }
    if (modes.count) self.errorText = nil;
    // Editing an action or condition whose Focus has since been renamed or deleted: keep it visible
    if (self.currentValue.length && ![self isFixedValue:self.currentValue]) {
        BOOL listed = NO;
        for (NSDictionary *mode in modes) listed = listed || [mode[@"value"] caseInsensitiveCompare:self.currentValue] == NSOrderedSame;
        if (!listed && modes.count) [modes insertObject:@{ @"name": self.currentValue, @"value": self.currentValue, @"icon": @"moon.fill", @"missing": @YES } atIndex:0];
    }
    return modes;
}

- (BOOL)isFixedValue:(NSString *)value {
    for (NSDictionary *row in self.fixedRows) {
        if ([row[@"value"] caseInsensitiveCompare:value] == NSOrderedSame) return YES;
    }
    return NO;
}

#pragma mark - Rows

// Section 0: the fixed rows. Section 1: the Focus modes, or one status row. Section 2: Try Again.
- (BOOL)showsStatusRow {
    return self.loading || self.errorText || self.modes.count == 0;
}

- (BOOL)showsTryAgain {
    return !self.loading && (self.errorText || self.modes.count == 0);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self showsTryAgain] ? 3 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.fixedRows.count;
    if (section == 2) return 1;
    return [self showsStatusRow] ? 1 : self.modes.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? @"Focus Modes" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.imageView.tintColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    if (indexPath.section == 2) {
        cell.textLabel.text = @"Try Again";
        cell.textLabel.textColor = self.view.tintColor;
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.clockwise"];
        cell.imageView.tintColor = self.view.tintColor;
        return cell;
    }

    if (indexPath.section == 1 && [self showsStatusRow]) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.numberOfLines = 0;
        if (self.loading) {
            cell.textLabel.text = @"Loading Focus modes…";
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        } else {
            cell.textLabel.text = self.errorText ?: @"No Focus modes found";
        }
        return cell;
    }

    NSDictionary *row = indexPath.section == 0 ? self.fixedRows[indexPath.row] : self.modes[indexPath.row];
    cell.textLabel.text = row[@"name"];
    cell.imageView.image = [UIImage systemImageNamed:row[@"icon"]];
    if ([row[@"missing"] boolValue]) cell.detailTextLabel.text = @"Not Found";
    BOOL ticked = self.currentValue && [row[@"value"] caseInsensitiveCompare:self.currentValue] == NSOrderedSame;
    cell.accessoryType = ticked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section != 1 || ![self showsStatusRow];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) {
        [self reload];
        return;
    }
    if (indexPath.section == 1 && [self showsStatusRow]) return;
    NSDictionary *row = indexPath.section == 0 ? self.fixedRows[indexPath.row] : self.modes[indexPath.row];
    if (!self.buildsCommand) {
        if (self.onSelected) self.onSelected(row);
        return;
    }
    NSString *name = row[@"value"];
    if (name.length == 0) {
        [self finishRow:row command:@"focus off"];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSArray *choice in @[ @[ @"Turn On", @"on" ], @[ @"Toggle", @"toggle" ] ]) {
        [sheet addAction:[UIAlertAction actionWithTitle:choice[0] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [weakSelf finishRow:row command:[NSString stringWithFormat:@"focus %@ %@", choice[1], name]];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)finishRow:(NSDictionary *)row command:(NSString *)command {
    NSMutableDictionary *chosen = [row mutableCopy];
    chosen[@"command"] = command;
    if (self.onSelected) self.onSelected(chosen);
}

@end
