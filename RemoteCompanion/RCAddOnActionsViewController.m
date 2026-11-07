#import "RCAddOnActionsViewController.h"
#import "RCConfigManager.h"
#import "RCAddOnCatalog.h"

@interface RCAddOnActionsViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *actions;
@end

@implementation RCAddOnActionsViewController

- (instancetype)initWithAddOn:(NSString *)identifier title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = title;
        _actions = [RCAddOnCatalog actionsForAddOn:identifier];
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
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.actions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSDictionary *action = self.actions[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.text = action[@"shortName"] ?: action[@"name"];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.numberOfLines = 0;
    UIImage *custom = [action[@"image"] isKindOfClass:[UIImage class]] ? action[@"image"] : nil;
    cell.imageView.image = custom ?: [UIImage systemImageNamed:action[@"icon"]];
    cell.imageView.tintColor = [UIColor secondaryLabelColor];
    // Actions with options or a field ask for them next
    cell.accessoryType = [RCAddOnCatalog commandAsksForDetails:action[@"command"]] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.onSelect) self.onSelect(self.actions[indexPath.row]);
}

@end
