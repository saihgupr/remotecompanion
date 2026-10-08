#import "RCBannersViewController.h"
#import "RCActionPickerViewController.h"
#import "RCConfigManager.h"

// Lists the action picker's catalog; tapping an action adds/removes it from the
// config's "bannerActions". Each entry tells the tweak how to recognise the action:
//   id      - the catalog command (what this screen keys on)
//   title   - banner title (the action's name)
//   icon    - SF Symbol for the banner
//   toggle  - YES for toggles, which show their new state instead of just the name
//   match   - command patterns: ending in " ", ":" or "-" = prefix, otherwise exact
//   exclude - other catalog actions' longer patterns within this one's prefixes
//             (Open Camera "camera " must not catch Camera Shutter "camera shutter")
//
// Actions that show a banner of their own (Camera, Home Assistant, ...) are listed too,
// ticked unless switched off: their banners stay their own, and switching one off adds
// it to the config's "bannerOptOut", which the tweak checks before showing it.
@interface RCBannersViewController ()
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIds;
@property (nonatomic, strong) NSMutableSet<NSString *> *optedOutIds;
@end

// Catalog commands of the actions that show a banner of their own (the ids the tweak checks)
static NSSet<NSString *> *RCOwnBannerIds(void) {
    static NSSet *ids;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ids = [NSSet setWithArray:@[@"__CAMERA_PICKER__", @"__CAMERA_VIDEO_PICKER__", @"camera record",
                                    @"__HA_PICKER__", @"__KM_TRIGGER__", @"__MQTT_PUBLISH__", @"audiomix toggle",
                                    @"sneakycam photo", @"sneakycam video",
                                    @"queue album", @"queue artist", @"shuffle all songs", @"delete current song"]];
    });
    return ids;
}

// The picker's catalog, minus entries that don't run an action of their own
static NSArray<NSArray<NSDictionary *> *> *RCBannerCatalog(NSArray<NSString *> **titlesOut) {
    NSSet *skip = [NSSet setWithArray:@[@"__IF_CONDITION__", @"__DELAY__", @"__TOAST__"]];
    RCActionPickerViewController *picker = [[RCActionPickerViewController alloc] init];
    NSArray *catalog = [picker catalogSections];
    NSArray *titles = [picker catalogSectionTitles];
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *sectionTitles = [NSMutableArray array];
    for (NSUInteger i = 0; i < catalog.count; i++) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *item in catalog[i]) {
            if (![skip containsObject:item[@"command"]]) [items addObject:item];
        }
        if (items.count) {
            [sections addObject:items];
            [sectionTitles addObject:i < titles.count ? titles[i] : @""];
        }
    }
    if (titlesOut) *titlesOut = sectionTitles;
    return sections;
}

@implementation RCBannersViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Banners";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"settingsBackground" defaultVal:[cm tweakValueForKey:@"mainBackground" defaultVal:0.09]];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];

    NSArray *titles = nil;
    self.sections = RCBannerCatalog(&titles);
    self.sectionTitles = titles;

    self.selectedIds = [NSMutableSet set];
    for (NSDictionary *entry in cm.bannerActions) {
        if ([entry[@"id"] isKindOfClass:[NSString class]]) [self.selectedIds addObject:entry[@"id"]];
    }
    // ANC Off and Transparency Mode were their own entries before Noise Control took all three modes
    if ([self.selectedIds containsObject:@"anc off"] || [self.selectedIds containsObject:@"anc transparency"]) [self.selectedIds addObject:@"anc on"];
    self.optedOutIds = [NSMutableSet setWithArray:cm.bannerOptOut];
}

+ (NSUInteger)checkedCount {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSSet *selected = [NSSet setWithArray:[cm.bannerActions valueForKey:@"id"]];
    NSSet *optedOut = [NSSet setWithArray:cm.bannerOptOut];
    NSUInteger count = 0;
    for (NSArray *section in RCBannerCatalog(NULL)) {
        for (NSDictionary *item in section) {
            NSString *command = item[@"command"];
            BOOL own = [RCOwnBannerIds() containsObject:command];
            if (own ? ![optedOut containsObject:command] : [selected containsObject:command]) count++;
        }
    }
    return count;
}

- (BOOL)isChecked:(NSString *)command {
    if ([RCOwnBannerIds() containsObject:command]) return ![self.optedOutIds containsObject:command];
    return [self.selectedIds containsObject:command];
}

#pragma mark - Matching

// Placeholder commands open a picker; these are the commands they produce.
- (NSArray<NSString *> *)patternsForCommand:(NSString *)command isToggle:(BOOL *)isToggle {
    static NSDictionary *placeholders;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        placeholders = @{
            @"__SET_VOLUME__": @[@"set-vol "],
            @"__SET_RINGER_VOLUME__": @[@"ringer volume "],
            @"__SET_BRIGHTNESS__": @[@"brightness "],
            @"__CAMERA_PICKER__": @[@"camera ", @"open camera ", @"camera", @"open camera"],
            @"__CAMERA_VIDEO_PICKER__": @[@"camera video ", @"open camera video ", @"camera video", @"open camera video", @"camera 2x"],
            @"__BT_CONNECT__": @[@"bt connect ", @"bluetooth connect "],
            @"__BT_DISCONNECT__": @[@"bt disconnect ", @"bluetooth disconnect "],
            @"__AIRPLAY_CONNECT__": @[@"airplay connect "],
            @"__FOCUS__": @[@"focus on ", @"focus toggle ", @"focus off"],
            @"__OPEN_APP__": @[@"uiopen "],
            @"__KILL_APP__": @[@"kill "],
            @"__HA_PICKER__": @[@"ha "],
            @"__KM_TRIGGER__": @[@"km "],
            @"__MQTT_PUBLISH__": @[@"mqtt "],
            @"__SHORTCUT_PICKER__": @[@"shortcut:"],
            @"__LUA_SCRIPT__": @[@"lua ", @"lua_eval "],
            @"__CUSTOM__": @[@"exec ", @"root ", @"sudo "]
        };
    });
    if (isToggle) *isToggle = NO;
    if (placeholders[command]) return placeholders[command];

    NSDictionary *info = [[RCConfigManager sharedManager] toggleInfoForCommand:command];
    if ([info[@"prefixes"] isKindOfClass:[NSArray class]] && [info[@"prefixes"] count]) {
        if (isToggle) *isToggle = YES;
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *p in info[@"prefixes"]) [out addObject:[p lowercaseString]];
        return out;
    }
    return @[[command lowercaseString]];
}

static BOOL RCBannerIsPrefixPattern(NSString *p) {
    if (p.length == 0) return NO;
    unichar last = [p characterAtIndex:p.length - 1];
    return last == ' ' || last == ':' || last == '-';
}

- (NSDictionary *)entryForItem:(NSDictionary *)item {
    NSString *command = item[@"command"];
    BOOL isToggle = NO;
    NSArray *patterns = [self patternsForCommand:command isToggle:&isToggle];

    // Longer patterns of other catalog actions that fall within this one's prefixes
    NSMutableOrderedSet *exclude = [NSMutableOrderedSet orderedSet];
    for (NSArray *section in self.sections) {
        for (NSDictionary *other in section) {
            if ([other[@"command"] isEqualToString:command]) continue;
            for (NSString *otherPattern in [self patternsForCommand:other[@"command"] isToggle:NULL]) {
                for (NSString *mine in patterns) {
                    if (RCBannerIsPrefixPattern(mine) && otherPattern.length > mine.length && [otherPattern hasPrefix:mine] && ![patterns containsObject:otherPattern]) {
                        [exclude addObject:otherPattern];
                    }
                }
            }
        }
    }

    NSString *title = item[@"name"];
    for (NSString *ellipsis in @[@"...", @"…"]) {
        if ([title hasSuffix:ellipsis]) title = [title substringToIndex:title.length - ellipsis.length];
    }
    return @{
        @"id": command,
        @"title": title,
        @"icon": item[@"icon"] ?: @"",
        @"toggle": @(isToggle),
        @"match": patterns,
        @"exclude": exclude.array
    };
}

- (void)saveSelection {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSArray *section in self.sections) {
        for (NSDictionary *item in section) {
            if ([RCOwnBannerIds() containsObject:item[@"command"]]) continue; // own banners: bannerOptOut instead
            if ([self.selectedIds containsObject:item[@"command"]]) [entries addObject:[self entryForItem:item]];
        }
    }
    [RCConfigManager sharedManager].bannerActions = entries;
    [RCConfigManager sharedManager].bannerOptOut = self.optedOutIds.allObjects;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sectionTitles[section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 0) return nil;
    return @"Checked actions show a banner whenever a trigger runs them. Toggles show their new state; other actions show their name.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    NSDictionary *item = self.sections[indexPath.section][indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.textLabel.text = item[@"name"];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.imageView.image = [UIImage systemImageNamed:item[@"icon"]];
    cell.imageView.tintColor = [UIColor systemGrayColor];
    cell.accessoryType = [self isChecked:item[@"command"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *command = self.sections[indexPath.section][indexPath.row][@"command"];
    NSMutableSet *set = [RCOwnBannerIds() containsObject:command] ? self.optedOutIds : self.selectedIds;
    if ([set containsObject:command]) [set removeObject:command];
    else [set addObject:command];
    [self saveSelection];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

@end
