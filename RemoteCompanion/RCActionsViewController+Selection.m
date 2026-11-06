#import "RCActionsViewController+Selection.h"
#import <objc/runtime.h>

static NSString *const kRCActionsPasteboardType = @"com.saihgupr.remotecompanion.actions";

// Methods of the actions screen this file uses
@interface RCActionsViewController (SelectionHost)
- (NSMutableArray *)actions;
- (UIBarButtonItem *)moreButton;
- (UIMenu *)moreMenu;
- (void)saveActions;
- (NSRange)ifBlockRangeForIndex:(NSInteger)index;
- (BOOL)isIfActionItem:(id)item;
- (BOOL)isElseActionItem:(id)item;
- (BOOL)isElseIfActionItem:(id)item;
- (BOOL)isEndIfActionItem:(id)item;
- (void)showHUDToast:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconName;
@end

static const void *kSelectingKey = &kSelectingKey;
static const void *kSavedItemsKey = &kSavedItemsKey;
static const void *kPausedKey = &kPausedKey;

@implementation RCActionsViewController (Selection)

- (BOOL)rc_isSelectingActions {
    return [objc_getAssociatedObject(self, kSelectingKey) boolValue];
}

static NSString *RCActionCountText(NSUInteger count) {
    return count == 1 ? @"1 Action" : [NSString stringWithFormat:@"%lu Actions", (unsigned long)count];
}

#pragma mark - Clipboard

+ (NSArray *)rc_actionsOnPasteboard {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if (![pasteboard containsPasteboardTypes:@[kRCActionsPasteboardType]]) return nil;
    NSData *data = [pasteboard dataForPasteboardType:kRCActionsPasteboardType];
    if (!data) return nil;
    id actions = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [actions isKindOfClass:[NSArray class]] && [actions count] ? actions : nil;
}

- (void)rc_addActionsSectionToMenuItems:(NSMutableArray<UIMenuElement *> *)menuItems {
    __weak typeof(self) weakSelf = self;
    // Both checked each time the menu opens (iOS 15): the menu is built before the actions load,
    // and a copy from another trigger should show up
    NSArray<UIMenuElement *> *(^items)(void) = ^NSArray<UIMenuElement *> * {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSMutableArray *list = [NSMutableArray array];
        UIAction *select = [UIAction actionWithTitle:@"Select Actions" image:[UIImage systemImageNamed:@"checkmark.circle"] identifier:nil handler:^(__kindof UIAction *a) {
            [weakSelf rc_setSelecting:YES];
        }];
        if (@available(iOS 15.0, *)) {
            if (strongSelf.actions.count == 0) select.attributes = UIMenuElementAttributesDisabled;
        }
        [list addObject:select];
        NSArray *copied = [RCActionsViewController rc_actionsOnPasteboard];
        if (copied) {
            [list addObject:[UIAction actionWithTitle:[NSString stringWithFormat:@"Paste %@", RCActionCountText(copied.count)]
                                                image:[UIImage systemImageNamed:@"doc.on.clipboard"]
                                           identifier:nil
                                              handler:^(__kindof UIAction *a) { [weakSelf rc_pasteActions]; }]];
        }
        return list;
    };
    NSMutableArray<UIMenuElement *> *children = [items() mutableCopy];
    if (@available(iOS 15.0, *)) {
        children = [@[[UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
            completion(items());
        }]] mutableCopy];
    }
    // Import and Export join them
    for (UIMenuElement *element in [menuItems copy]) {
        if ([element.title isEqualToString:@"Import Actions"] || [element.title isEqualToString:@"Export Actions"]) {
            [menuItems removeObject:element];
            [children addObject:element];
        }
    }
    [menuItems addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:children]];
}

- (void)rc_pasteActions {
    NSArray *copied = [RCActionsViewController rc_actionsOnPasteboard];
    if (!copied) return;
    [self.actions addObjectsFromArray:copied];
    [self saveActions];
    [self.tableView reloadData];
    NSIndexPath *last = [NSIndexPath indexPathForRow:self.actions.count - 1 inSection:0];
    if ([self.tableView numberOfSections] > 0 && last.row < [self.tableView numberOfRowsInSection:0]) {
        [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    }
    [self showHUDToast:[NSString stringWithFormat:@"Pasted %@", RCActionCountText(copied.count)] subtitle:nil icon:@"doc.on.clipboard"];
}

#pragma mark - Selecting

- (void)rc_setSelecting:(BOOL)selecting {
    if (selecting == self.rc_isSelectingActions) return;
    objc_setAssociatedObject(self, kSelectingKey, @(selecting), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITableView *tableView = self.tableView;

    if (selecting) {
        objc_setAssociatedObject(self, kSavedItemsKey, @{
            @"right": self.navigationItem.rightBarButtonItems ?: @[],
            @"back": @(self.navigationItem.hidesBackButton),
        }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.navigationItem.rightBarButtonItems = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(rc_endSelecting)]];
        [self.navigationItem setHidesBackButton:YES animated:YES];
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Select All" style:UIBarButtonItemStylePlain target:self action:@selector(rc_toggleSelectAll)];
        tableView.dragInteractionEnabled = NO;
        // The screen's own long press (reordering) rests while selecting
        NSMutableArray *paused = [NSMutableArray array];
        for (UIGestureRecognizer *recognizer in tableView.gestureRecognizers) {
            if (recognizer.class == [UILongPressGestureRecognizer class] && recognizer.enabled) {
                recognizer.enabled = NO;
                [paused addObject:recognizer];
            }
        }
        objc_setAssociatedObject(self, kPausedKey, paused, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tableView.allowsMultipleSelectionDuringEditing = YES;
        [tableView setEditing:YES animated:YES];
        [self.navigationController setToolbarHidden:NO animated:YES];
    } else {
        NSDictionary *saved = objc_getAssociatedObject(self, kSavedItemsKey);
        self.navigationItem.rightBarButtonItems = saved[@"right"];
        self.navigationItem.leftBarButtonItem = nil;
        [self.navigationItem setHidesBackButton:[saved[@"back"] boolValue] animated:YES];
        [tableView setEditing:NO animated:YES];
        tableView.allowsMultipleSelectionDuringEditing = NO;
        tableView.dragInteractionEnabled = YES;
        for (UIGestureRecognizer *recognizer in objc_getAssociatedObject(self, kPausedKey)) recognizer.enabled = YES;
        objc_setAssociatedObject(self, kPausedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self.navigationController setToolbarHidden:YES animated:YES];
        self.toolbarItems = nil;
    }
    [self rc_selectionChanged];
}

- (void)rc_endSelecting {
    [self rc_setSelecting:NO];
}

- (void)rc_toggleSelectAll {
    UITableView *tableView = self.tableView;
    BOOL allSelected = tableView.indexPathsForSelectedRows.count == self.actions.count;
    for (NSUInteger row = 0; row < self.actions.count; row++) {
        NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
        if (allSelected) [tableView deselectRowAtIndexPath:path animated:NO];
        else [tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self rc_selectionChanged];
}

// The If an Else If or Else row belongs to
- (NSInteger)rc_ifIndexForBranchAtIndex:(NSInteger)index {
    NSInteger depth = 0;
    for (NSInteger i = index - 1; i >= 0; i--) {
        id item = self.actions[i];
        if ([self isEndIfActionItem:item]) depth++;
        else if ([self isIfActionItem:item]) {
            if (depth == 0) return i;
            depth--;
        }
    }
    return NSNotFound;
}

// The selected rows, with each If block they touch taken whole
- (NSIndexSet *)rc_selectedIndexes {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) {
        NSInteger row = path.row;
        if (row < 0 || row >= (NSInteger)self.actions.count) continue;
        id item = self.actions[row];
        NSInteger start = row;
        if ([self isElseIfActionItem:item] || [self isElseActionItem:item]) {
            NSInteger ifIndex = [self rc_ifIndexForBranchAtIndex:row];
            if (ifIndex != NSNotFound) start = ifIndex;
        }
        NSRange range = [self ifBlockRangeForIndex:start];
        if (range.location == NSNotFound || NSMaxRange(range) > self.actions.count) range = NSMakeRange(row, 1);
        [indexes addIndexesInRange:range];
    }
    return indexes;
}

- (void)rc_selectionChanged {
    if (!self.rc_isSelectingActions) return;
    NSUInteger count = [self rc_selectedIndexes].count;
    BOOL allSelected = self.tableView.indexPathsForSelectedRows.count == self.actions.count && self.actions.count > 0;
    self.navigationItem.leftBarButtonItem.title = allSelected ? @"Deselect All" : @"Select All";

    UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(rc_copySelected)];
    UIBarButtonItem *delete = [[UIBarButtonItem alloc] initWithTitle:@"Delete" style:UIBarButtonItemStylePlain target:self action:@selector(rc_deleteSelected)];
    delete.tintColor = [UIColor systemRedColor];
    copy.enabled = delete.enabled = count > 0;
    UILabel *label = [UILabel new];
    label.text = count ? [NSString stringWithFormat:@"%@ Selected", RCActionCountText(count)] : @"Select Actions";
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.textColor = [UIColor secondaryLabelColor];
    [label sizeToFit];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *flex2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    [self setToolbarItems:@[copy, flex, [[UIBarButtonItem alloc] initWithCustomView:label], flex2, delete] animated:NO];
}

- (void)rc_copySelected {
    NSIndexSet *indexes = [self rc_selectedIndexes];
    if (indexes.count == 0) return;
    NSArray *selected = [self.actions objectsAtIndexes:indexes];
    NSData *data = [NSJSONSerialization dataWithJSONObject:selected options:0 error:nil];
    if (!data) return;
    [[UIPasteboard generalPasteboard] setItems:@[ @{ kRCActionsPasteboardType: data } ] options:@{}];
    [self rc_setSelecting:NO];
    if (@available(iOS 15.0, *)) {} else {
        self.moreButton.menu = [self moreMenu]; // shows Paste
    }
    [self showHUDToast:[NSString stringWithFormat:@"Copied %@", RCActionCountText(indexes.count)] subtitle:nil icon:@"doc.on.doc"];
}

- (void)rc_deleteSelected {
    NSIndexSet *indexes = [self rc_selectedIndexes];
    if (indexes.count == 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete %@?", RCActionCountText(indexes.count)]
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.actions removeObjectsAtIndexes:indexes];
        [strongSelf saveActions];
        [strongSelf rc_setSelecting:NO];
        [strongSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self rc_selectionChanged];
}

@end
