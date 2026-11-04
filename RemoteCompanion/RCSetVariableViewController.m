#import "RCSetVariableViewController.h"
#import "RCConfigManager.h"
#import "RCServerClient.h"
#import "RCVariableEditorParts.h"
#import "RCCommandPickerViewController.h"

typedef NS_ENUM(NSInteger, RCSetVariableSection) {
    RCSetVariableSectionNewValue = 0,
    RCSetVariableSectionChange,
    RCSetVariableSectionVariable,
    RCSetVariableSectionFields,
    RCSetVariableSectionScope,
    RCSetVariableSectionCount
};

// The kinds: code, tile title, icon, whether it changes an existing number, footer, and
// fields (label, key in the action, placeholder). "command" saves as command_number with Number Only.
static NSArray<NSDictionary *> *RCSetVariableKindList(void) {
    static NSArray *kinds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *numberHint = @"Number or {variable}";
        kinds = @[
            @{ @"op": @"set", @"title": @"Text or Number", @"icon": @"textformat",
               @"message": @"Stores this text or number, replacing the current value. {name} inserts another variable's value; {round} inserts the repeat round.",
               @"fields": @[@[@"Value", @"value", @"Text, number or {variable}"]] },
            @{ @"op": @"random", @"title": @"Random Number", @"icon": @"dice", @"fallbackIcon": @"shuffle",
               @"message": @"Stores a random whole number from From to To, both included. Each can be a number or a {variable}.",
               @"fields": @[@[@"From", @"min", numberHint], @[@"To", @"max", numberHint]] },
            @{ @"op": @"command", @"title": @"RC Command", @"icon": @"terminal",
               @"message": @"Runs an RC command and stores its answer. For example, wifi status stores \"WiFi ON\".",
               @"numberMessage": @"Runs an RC command and stores the first number in its answer. For example, volume answers \"Volume: 100%\" and stores 100.",
               @"fields": @[@[@"Command", @"value", @"volume"]] },
            @{ @"op": @"add", @"title": @"Add", @"icon": @"plus", @"change": @YES,
               @"message": @"Adds the amount to the variable. A variable without a value starts at 0, so Add 1 works as a counter.",
               @"fields": @[@[@"Amount", @"value", numberHint]] },
            @{ @"op": @"subtract", @"title": @"Subtract", @"icon": @"minus", @"change": @YES,
               @"message": @"Subtracts the amount from the variable. A variable without a value starts at 0.",
               @"fields": @[@[@"Amount", @"value", numberHint]] },
            @{ @"op": @"multiply", @"title": @"Multiply", @"icon": @"multiply", @"change": @YES,
               @"message": @"Multiplies the variable by this number.",
               @"fields": @[@[@"By", @"value", numberHint]] },
            @{ @"op": @"divide", @"title": @"Divide", @"icon": @"divide", @"change": @YES,
               @"message": @"Divides the variable by this number. Dividing by 0 leaves it unchanged.", @"fields": @[@[@"By", @"value", numberHint]] },
            @{ @"op": @"round", @"title": @"Round", @"icon": @"number", @"change": @YES,
               @"message": @"Rounds the variable to this many decimal places; empty rounds to a whole number. For example, 2 turns 3.14159 into 3.14.", @"fields": @[@[@"Decimals", @"value", @"0"]] },
        ];
    });
    return kinds;
}

BOOL RCSetVariableNameValid(NSString *name) {
    if (name.length == 0 || name.length > 40 || [name isEqualToString:@"round"]) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    if ([name rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return NO;
    return ![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[name characterAtIndex:0]];
}

UIMenu *RCVariableInsertMenu(NSArray<NSString *> *runNames, NSArray<NSString *> *savedNames, void (^insert)(NSString *name)) {
    return RCVariableInsertMenuWithRound(runNames, savedNames, YES, insert);
}

UIMenu *RCVariableInsertMenuWithRound(NSArray<NSString *> *runNames, NSArray<NSString *> *savedNames, BOOL includesRound, void (^insert)(NSString *name)) {
    UIAction *(^item)(NSString *) = ^UIAction *(NSString *name) {
        return [UIAction actionWithTitle:name image:nil identifier:nil handler:^(__unused UIAction *a) { insert(name); }];
    };
    NSMutableArray *children = [NSMutableArray array];
    NSMutableArray *runItems = [NSMutableArray array], *savedItems = [NSMutableArray array];
    for (NSString *name in runNames) [runItems addObject:item(name)];
    for (NSString *name in savedNames) [savedItems addObject:item(name)];
    if (runItems.count) [children addObject:[UIMenu menuWithTitle:@"This Run" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:runItems]];
    if (savedItems.count) [children addObject:[UIMenu menuWithTitle:@"Saved" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:savedItems]];
    // {round} isn't a variable that's set: it's the pass a Repeat is on
    if (includesRound) {
        UIAction *round = [UIAction actionWithTitle:@"Repeat Round" image:[UIImage systemImageNamed:@"repeat"] identifier:nil handler:^(__unused UIAction *a) { insert(@"round"); }];
        if (@available(iOS 15.0, *)) round.subtitle = @"The current pass of a Repeat: 1, 2, 3…";
        [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[round]]];
    }
    if (!children.count) {
        UIAction *none = [UIAction actionWithTitle:@"No Variables Yet" image:nil identifier:nil handler:^(__unused UIAction *a) {}];
        none.attributes = UIMenuElementAttributesDisabled;
        [children addObject:none];
    }
    return [UIMenu menuWithTitle:@"" children:children];
}

@implementation RCSetVariableFooter
- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (self) {
        _label = [[UILabel alloc] init];
        _label.numberOfLines = 0;
        _label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _label.textColor = [UIColor secondaryLabelColor];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_label];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [_label.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
    }
    return self;
}
@end


@implementation RCSetVariableTile
- (instancetype)initWithKind:(NSDictionary *)kind compact:(BOOL)compact {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _op = kind[@"op"];
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 2;
        self.accessibilityLabel = kind[@"title"];
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.isAccessibilityElement = YES;
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:compact ? 18 : 20 weight:UIImageSymbolWeightMedium];
        UIImage *icon = [UIImage systemImageNamed:kind[@"icon"] withConfiguration:config];
        if (!icon && kind[@"fallbackIcon"]) icon = [UIImage systemImageNamed:kind[@"fallbackIcon"] withConfiguration:config];
        _iconView = [[UIImageView alloc] initWithImage:icon];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = kind[@"title"];
        _titleLabel.font = [UIFont systemFontOfSize:compact ? 11 : 12 weight:UIFontWeightMedium];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = compact ? 1 : 2;
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.75;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconView];
        [self addSubview:_titleLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:compact ? 64 : 76],
            [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:compact ? 11 : 12],
            [_iconView.heightAnchor constraintEqualToConstant:24],
            [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:6],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3],
        ]];
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *accent = self.tintColor ?: [UIColor systemBlueColor];
    self.backgroundColor = selected ? [accent colorWithAlphaComponent:0.18] : [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    self.layer.borderColor = (selected ? accent : [UIColor clearColor]).CGColor;
    self.iconView.tintColor = selected ? accent : [UIColor labelColor];
    self.titleLabel.textColor = selected ? accent : [UIColor labelColor];
    if (selected) self.accessibilityTraits |= UIAccessibilityTraitSelected;
    else self.accessibilityTraits &= ~UIAccessibilityTraitSelected;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    self.selected = self.selected;
}
@end

@interface RCSetVariableViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSDictionary *original;
@property (nonatomic, copy) NSString *op;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *typed; // op -> key -> text
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) NSArray<UITextField *> *valueFields; // up to two, reused by every kind
@property (nonatomic, strong) UISwitch *runOnlySwitch;
@property (nonatomic, strong) UISwitch *numberOnlySwitch;
@property (nonatomic, strong) NSArray<UIButton *> *insertButtons; // the + in each value field
@property (nonatomic, strong) UIView *commandAccessory;           // RC Command: the command list and +
@property (nonatomic, strong) UIButton *variableButton;
@property (nonatomic, strong) NSArray<RCSetVariableTile *> *tiles;
@property (nonatomic, strong) UIView *valueGrid;
@property (nonatomic, strong) UIView *changeGrid;
@property (nonatomic, strong) RCSetVariableFooter *variableFooter;
@property (nonatomic, strong) RCSetVariableFooter *fieldsFooter;
// Variables to choose from: set This Run Only by this trigger, and saved (on the phone or by this trigger)
@property (nonatomic, strong) NSArray<NSString *> *runNames;
@property (nonatomic, strong) NSArray<NSString *> *savedNames;
@property (nonatomic, strong) NSArray<NSString *> *triggerSavedNames;
// A Change kind's variable: picked from the menu, or typed as a new name
@property (nonatomic, copy) NSString *pickedName;
@property (nonatomic, assign) BOOL pickedRunOnly;
@property (nonatomic, assign) BOOL typingNewName;
@end

@implementation RCSetVariableViewController

- (instancetype)initWithAction:(NSDictionary *)action otherActions:(NSArray *)otherActions {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _original = action;
        NSString *op = [[action[@"op"] description] lowercaseString] ?: @"set";
        if ([op isEqualToString:@"command_number"]) op = @"command";
        BOOL known = NO;
        for (NSDictionary *kind in RCSetVariableKindList()) if ([kind[@"op"] isEqualToString:op]) known = YES;
        _op = known ? op : @"set";
        _typed = [NSMutableDictionary dictionary];
        NSMutableDictionary *mine = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"value", @"min", @"max"]) {
            if (action[key]) mine[key] = [action[key] description];
        }
        _typed[_op] = mine;

        NSMutableOrderedSet *run = [NSMutableOrderedSet orderedSet], *saved = [NSMutableOrderedSet orderedSet];
        for (id item in otherActions) {
            if (![item isKindOfClass:[NSDictionary class]] || ![[item[@"type"] description] isEqualToString:@"set_variable"]) continue;
            NSString *name = [item[@"name"] description];
            if (!RCSetVariableNameValid(name)) continue;
            if ([[item[@"scope"] description] isEqualToString:@"run"]) [run addObject:name];
            else [saved addObject:name];
        }
        _runNames = [run.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        _triggerSavedNames = saved.array;
        _savedNames = [self mergedSaved:@[]];

        NSString *name = [action[@"name"] description];
        if ([self isChangeOp:_op] && name.length) {
            _pickedName = name;
            _pickedRunOnly = [[action[@"scope"] description] isEqualToString:@"run"];
        }
        self.title = @"Set Variable";
    }
    return self;
}

- (instancetype)init {
    return [self initWithAction:nil otherActions:nil];
}

// Saved names from the phone plus the ones this trigger saves, without the This Run ones
- (NSArray<NSString *> *)mergedSaved:(NSArray<NSString *> *)phoneNames {
    NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:phoneNames];
    [all addObjectsFromArray:self.triggerSavedNames ?: @[]];
    [all minusSet:[NSSet setWithArray:self.runNames ?: @[]]];
    return [all.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (BOOL)isChangeOp:(NSString *)op {
    for (NSDictionary *kind in RCSetVariableKindList()) if ([kind[@"op"] isEqualToString:op]) return [kind[@"change"] boolValue];
    return NO;
}

- (BOOL)isChange {
    return [self isChangeOp:self.op];
}

- (NSDictionary *)currentKind {
    for (NSDictionary *kind in RCSetVariableKindList()) if ([kind[@"op"] isEqualToString:self.op]) return kind;
    return RCSetVariableKindList().firstObject;
}

- (NSArray *)currentFields {
    return [self currentKind][@"fields"];
}

// The name field shows for Set Value kinds, and for a Change kind given a new name
- (BOOL)showsNameField {
    return !self.isChange || self.typingNewName;
}

- (UITextField *)makeField {
    UITextField *field = [[UITextField alloc] init];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.delegate = self;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    return field;
}

- (UIView *)gridWithOps:(NSArray<NSString *> *)ops columns:(NSUInteger)columns tiles:(NSMutableArray *)tiles {
    UIStackView *grid = [[UIStackView alloc] init];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 10;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    NSMutableArray *kinds = [NSMutableArray array];
    for (NSDictionary *kind in RCSetVariableKindList()) if ([ops containsObject:kind[@"op"]]) [kinds addObject:kind];
    for (NSUInteger start = 0; start < kinds.count; start += columns) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.distribution = UIStackViewDistributionFillEqually;
        row.spacing = columns > 3 ? 8 : 10;
        for (NSUInteger i = start; i < MIN(start + columns, kinds.count); i++) {
            RCSetVariableTile *tile = [[RCSetVariableTile alloc] initWithKind:kinds[i] compact:columns > 3];
            [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:tile];
            [tiles addObject:tile];
        }
        [grid addArrangedSubview:row];
    }
    return grid;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UIColor *bg = [cm tweakColorForKey:@"mainBackground" defaultVal:0.09];
    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 30;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];

    self.nameField = [self makeField];
    self.nameField.placeholder = @"count";
    self.nameField.text = self.pickedName ? nil : [self.original[@"name"] description];
    self.nameField.font = [UIFont monospacedSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightRegular];
    self.nameField.returnKeyType = UIReturnKeyNext;
    self.valueFields = @[[self makeField], [self makeField]];
    NSMutableArray *inserts = [NSMutableArray array];
    for (UITextField *field in self.valueFields) {
        UIButton *insert = [UIButton buttonWithType:UIButtonTypeSystem];
        [insert setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
        insert.frame = CGRectMake(0, 0, 36, 36);
        insert.showsMenuAsPrimaryAction = YES;
        insert.accessibilityLabel = @"Insert Variable";
        field.rightView = insert;
        field.rightViewMode = UITextFieldViewModeAlways;
        [inserts addObject:insert];
    }
    self.insertButtons = inserts;
    UIButton *list = [UIButton buttonWithType:UIButtonTypeSystem];
    [list setImage:[UIImage systemImageNamed:@"list.bullet.circle"] forState:UIControlStateNormal];
    list.frame = CGRectMake(0, 0, 36, 36);
    list.accessibilityLabel = @"Choose Command";
    [list addTarget:self action:@selector(chooseCommand) forControlEvents:UIControlEventTouchUpInside];
    self.commandAccessory = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 72, 36)];
    [self.commandAccessory addSubview:list];

    self.runOnlySwitch = [[UISwitch alloc] init];
    self.runOnlySwitch.on = [[self.original[@"scope"] description] isEqualToString:@"run"];
    self.numberOnlySwitch = [[UISwitch alloc] init];
    self.numberOnlySwitch.on = [[[self.original[@"op"] description] lowercaseString] isEqualToString:@"command_number"];
    [self.numberOnlySwitch addTarget:self action:@selector(numberOnlyChanged) forControlEvents:UIControlEventValueChanged];

    self.variableButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.variableButton.titleLabel.font = [UIFont monospacedSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightRegular];
    // Left-aligned like the text fields, the arrow after the name with a gap.
    // Right-to-left puts the image after the title; the insets are in absolute left/right.
    self.variableButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.variableButton.imageEdgeInsets = UIEdgeInsetsMake(0, 10, 0, -10);
    self.variableButton.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 10);
    self.variableButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self.variableButton setImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"] forState:UIControlStateNormal];
    self.variableButton.showsMenuAsPrimaryAction = YES;
    self.variableButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.variableFooter = [[RCSetVariableFooter alloc] initWithReuseIdentifier:nil];
    self.fieldsFooter = [[RCSetVariableFooter alloc] initWithReuseIdentifier:nil];

    NSMutableArray *tiles = [NSMutableArray array];
    self.valueGrid = [self gridWithOps:@[@"set", @"random", @"command"] columns:3 tiles:tiles];
    self.changeGrid = [self gridWithOps:@[@"add", @"subtract", @"multiply", @"divide", @"round"] columns:5 tiles:tiles];
    self.tiles = tiles;

    [self applyKind];
    [self rebuildVariableMenu];
    [self updateState];
    [self loadSavedNames];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.original) [self.nameField becomeFirstResponder];
}

- (void)loadSavedNames {
    __weak typeof(self) weakSelf = self;
    [[RCServerClient sharedClient] executeCommand:@"var list" completion:^(NSString *output, NSError *error) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![parsed isKindOfClass:[NSDictionary class]] || ![parsed count]) return;
        NSArray *phoneNames = [parsed allKeys];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.isViewLoaded) return;
            strongSelf.savedNames = [strongSelf mergedSaved:phoneNames];
            [strongSelf rebuildVariableMenu];
            [UIView performWithoutAnimation:^{
                [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:RCSetVariableSectionVariable] withRowAnimation:UITableViewRowAnimationNone];
            }];
        });
    }];
}

- (NSArray<NSString *> *)allNames {
    NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:self.runNames];
    [all addObjectsFromArray:self.savedNames];
    return [all.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

#pragma mark - State

// The menu of variables a Change kind can work on, plus New Name
- (void)rebuildVariableMenu {
    __weak typeof(self) weakSelf = self;
    UIAction *(^pick)(NSString *, BOOL) = ^UIAction *(NSString *name, BOOL runOnly) {
        UIAction *action = [UIAction actionWithTitle:name image:nil identifier:nil handler:^(__unused UIAction *a) {
            [weakSelf pickVariable:name runOnly:runOnly];
        }];
        if (!weakSelf.typingNewName && [weakSelf.pickedName isEqualToString:name] && weakSelf.pickedRunOnly == runOnly) action.state = UIMenuElementStateOn;
        return action;
    };
    NSMutableArray *runItems = [NSMutableArray array], *savedItems = [NSMutableArray array];
    NSMutableArray *runNames = [self.runNames mutableCopy], *savedNames = [self.savedNames mutableCopy];
    // A name from the action being edited that isn't set anywhere else still shows
    if (self.pickedName && ![runNames containsObject:self.pickedName] && ![savedNames containsObject:self.pickedName]) {
        [(self.pickedRunOnly ? runNames : savedNames) addObject:self.pickedName];
    }
    for (NSString *name in runNames) [runItems addObject:pick(name, YES)];
    for (NSString *name in savedNames) [savedItems addObject:pick(name, NO)];
    NSMutableArray *children = [NSMutableArray array];
    if (runItems.count) [children addObject:[UIMenu menuWithTitle:@"This Run" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:runItems]];
    if (savedItems.count) [children addObject:[UIMenu menuWithTitle:@"Saved" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:savedItems]];
    UIAction *newName = [UIAction actionWithTitle:@"New Name" image:[UIImage systemImageNamed:@"plus"] identifier:nil handler:^(__unused UIAction *a) {
        [weakSelf startNewName];
    }];
    if (self.typingNewName) newName.state = UIMenuElementStateOn;
    [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[newName]]];
    self.variableButton.menu = [UIMenu menuWithTitle:@"" children:children];
    NSString *title = self.typingNewName ? @"New Name" : (self.pickedName ?: @"Choose");
    [self.variableButton setTitle:title forState:UIControlStateNormal];
    [self rebuildInsertMenus];
}

// The + in each value field: a menu of known variables (and {round}) to put in the field
- (void)rebuildInsertMenus {
    __weak typeof(self) weakSelf = self;
    for (UITextField *field in self.valueFields) {
        __weak UITextField *weakField = field;
        self.insertButtons[[self.valueFields indexOfObject:field]].menu = RCVariableInsertMenu(self.runNames, self.savedNames, ^(NSString *name) {
            [weakSelf insertVariable:name intoField:weakField];
        });
    }
}

// Text values get {name} at the cursor; number values take one variable, so it replaces the field
- (void)insertVariable:(NSString *)name intoField:(UITextField *)field {
    if (!field) return;
    NSString *token = [NSString stringWithFormat:@"{%@}", name];
    BOOL textValue = [self.op isEqualToString:@"set"] || [self.op isEqualToString:@"command"];
    if (!textValue) {
        field.text = token;
    } else if (field.isFirstResponder && field.selectedTextRange) {
        [field replaceRange:field.selectedTextRange withText:token];
    } else {
        field.text = [(field.text ?: @"") stringByAppendingString:token];
    }
    [self storeTyped];
    [self updateState];
}

- (void)pickVariable:(NSString *)name runOnly:(BOOL)runOnly {
    BOOL wasTyping = self.typingNewName;
    self.pickedName = name;
    self.pickedRunOnly = runOnly;
    self.typingNewName = NO;
    [self rebuildVariableMenu];
    if (wasTyping) [self reloadVariableAndScope];
    [self updateState];
}

- (void)startNewName {
    if (self.typingNewName) return;
    self.typingNewName = YES;
    self.nameField.text = nil;
    [self rebuildVariableMenu];
    [self reloadVariableAndScope];
    [self updateState];
    [self.nameField becomeFirstResponder];
}

- (void)reloadVariableAndScope {
    NSMutableIndexSet *sections = [NSMutableIndexSet indexSetWithIndex:RCSetVariableSectionVariable];
    [sections addIndex:RCSetVariableSectionScope];
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
    }];
}

// Shows the current kind: tile selection, footer, field placeholders and keyboards
- (void)applyKind {
    NSDictionary *kind = [self currentKind];
    for (RCSetVariableTile *tile in self.tiles) tile.selected = [tile.op isEqualToString:self.op];
    BOOL numberOnly = [self.op isEqualToString:@"command"] && self.numberOnlySwitch.isOn;
    self.fieldsFooter.label.text = numberOnly ? kind[@"numberMessage"] : kind[@"message"];
    NSArray *fields = kind[@"fields"];
    NSDictionary *mine = self.typed[self.op];
    BOOL numeric = ![self.op isEqualToString:@"set"] && ![self.op isEqualToString:@"command"];
    // RC Command's field also has the command list, before the +
    UIButton *firstInsert = self.insertButtons.firstObject;
    if ([self.op isEqualToString:@"command"]) {
        firstInsert.frame = CGRectMake(36, 0, 36, 36);
        [self.commandAccessory addSubview:firstInsert];
        self.valueFields.firstObject.rightView = self.commandAccessory;
    } else if (self.valueFields.firstObject.rightView != firstInsert) {
        [firstInsert removeFromSuperview];
        firstInsert.frame = CGRectMake(0, 0, 36, 36);
        self.valueFields.firstObject.rightView = firstInsert;
    }
    [self.valueFields enumerateObjectsUsingBlock:^(UITextField *field, NSUInteger i, __unused BOOL *stop) {
        if (i >= fields.count) { field.text = nil; return; }
        NSArray *spec = fields[i];
        field.text = mine[spec[1]];
        field.placeholder = spec[2];
        field.keyboardType = numeric ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeDefault;
        field.returnKeyType = i + 1 < fields.count ? UIReturnKeyNext : UIReturnKeyDone;
    }];
}

// Remembers what's typed for the current kind, so switching kinds and back keeps it
- (void)storeTyped {
    NSMutableDictionary *mine = self.typed[self.op] ?: [NSMutableDictionary dictionary];
    [[self currentFields] enumerateObjectsUsingBlock:^(NSArray *spec, NSUInteger i, __unused BOOL *stop) {
        mine[spec[1]] = self.valueFields[i].text ?: @"";
    }];
    self.typed[self.op] = mine;
}

- (NSString *)trimmed:(NSString *)text {
    return [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// The variable's name as it will be saved, or nil when there isn't a usable one
- (NSString *)chosenName {
    if (self.isChange && !self.typingNewName) return self.pickedName;
    NSString *name = [self trimmed:self.nameField.text];
    return RCSetVariableNameValid(name) ? name : nil;
}

- (void)setFooter:(RCSetVariableFooter *)footer text:(NSString *)text color:(UIColor *)color {
    BOOL changed = ![footer.label.text isEqualToString:text];
    footer.label.text = text;
    footer.label.textColor = color;
    if (changed && self.tableView.window) {
        [UIView performWithoutAnimation:^{
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
        }];
    }
}

// Save is on only when the action is complete; a name that can't be used says why under it
- (void)updateState {
    NSString *typedName = [self trimmed:self.nameField.text];
    NSString *text;
    UIColor *color = [UIColor secondaryLabelColor];
    if (self.showsNameField && typedName.length && !RCSetVariableNameValid(typedName)) {
        text = [typedName isEqualToString:@"round"] ? @"\"round\" is reserved." : @"Letters, digits and _ only, not starting with a digit.";
        color = [UIColor systemRedColor];
    } else if (self.isChange && !self.typingNewName) {
        text = !self.pickedName ? @"Choose the variable to change. Its value must be a number; otherwise it stays unchanged and Run History shows why."
             : (self.pickedRunOnly ? @"Changes the value this run set. It is forgotten when the run ends." : @"Changes the saved value, which every trigger can use.");
    } else if (self.isChange) {
        text = @"A new variable starts at 0.";
    } else {
        text = @"Letters, digits and _. Write {name} in any action's text to insert the value.";
    }
    [self setFooter:self.variableFooter text:text color:color];

    BOOL fieldsOK = YES;
    if (![self.op isEqualToString:@"set"] && ![self.op isEqualToString:@"round"]) {
        for (NSUInteger i = 0; i < [self currentFields].count; i++) {
            if (![self trimmed:self.valueFields[i].text].length) fieldsOK = NO;
        }
    }
    self.navigationItem.rightBarButtonItem.enabled = [self chosenName] != nil && fieldsOK;
}

#pragma mark - Actions

- (void)tileTapped:(RCSetVariableTile *)tile {
    if ([tile.op isEqualToString:self.op]) return;
    BOOL wasChange = self.isChange;
    [self storeTyped];
    self.op = tile.op;
    BOOL groupChanged = wasChange != self.isChange;
    if (groupChanged && self.isChange) {
        // A typed name carries over: picked when it's a known variable (or the one picked before),
        // otherwise kept as a new name
        NSString *typedName = [self trimmed:self.nameField.text];
        if ([self.runNames containsObject:typedName]) { self.pickedName = typedName; self.pickedRunOnly = YES; self.typingNewName = NO; }
        else if ([self.savedNames containsObject:typedName]) { self.pickedName = typedName; self.pickedRunOnly = NO; self.typingNewName = NO; }
        else if (self.pickedName && [typedName isEqualToString:self.pickedName]) { self.pickedRunOnly = self.runOnlySwitch.isOn; self.typingNewName = NO; }
        else self.typingNewName = typedName.length > 0;
    } else if (groupChanged) {
        if (!self.typingNewName && self.pickedName) {
            self.nameField.text = self.pickedName;
            self.runOnlySwitch.on = self.pickedRunOnly;
        }
        self.typingNewName = NO;
    }
    [self applyKind];
    [self rebuildVariableMenu];
    NSMutableIndexSet *sections = [NSMutableIndexSet indexSetWithIndex:RCSetVariableSectionFields];
    if (groupChanged) {
        [sections addIndex:RCSetVariableSectionVariable];
        [sections addIndex:RCSetVariableSectionScope];
    }
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
    }];
    [self updateState];
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}

// RC Command: picks a command that answers with a value; levels turn Number Only on
- (void)chooseCommand {
    [self.view endEditing:YES];
    RCCommandPickerViewController *picker = [[RCCommandPickerViewController alloc] initWithSelectedCommand:self.valueFields.firstObject.text];
    __weak typeof(self) weakSelf = self;
    picker.onPick = ^(NSString *command, BOOL number) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.valueFields.firstObject.text = command;
        strongSelf.numberOnlySwitch.on = number;
        [strongSelf numberOnlyChanged]; // keeps the text and updates the note
        [strongSelf updateState];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)numberOnlyChanged {
    [self storeTyped];
    [self applyKind];
    [UIView performWithoutAnimation:^{
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }];
}

- (void)nameChipTapped:(UIButton *)chip {
    NSString *name = [chip titleForState:UIControlStateNormal];
    self.nameField.text = name;
    // Using a This Run variable's name keeps it This Run Only
    if ([self.runNames containsObject:name]) self.runOnlySwitch.on = YES;
    else if ([self.savedNames containsObject:name]) self.runOnlySwitch.on = NO;
    [self updateState];
}

- (void)fieldChanged:(UITextField *)field {
    [self updateState];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSUInteger count = [self currentFields].count;
    if (textField == self.nameField) {
        [self.valueFields[0] becomeFirstResponder];
    } else if (textField == self.valueFields[0] && count > 1) {
        [self.valueFields[1] becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return NO;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    [self storeTyped];
    NSString *name = [self chosenName];
    if (!name) return;
    NSMutableDictionary *item = [@{ @"type": @"set_variable", @"name": name, @"value": @"" } mutableCopy];
    NSString *op = self.op;
    if ([op isEqualToString:@"command"] && self.numberOnlySwitch.isOn) op = @"command_number";
    if (![op isEqualToString:@"set"]) item[@"op"] = op;
    for (NSArray *spec in [self currentFields]) {
        NSString *text = self.typed[self.op][spec[1]] ?: @"";
        // A Set value is kept as typed (spaces may matter); the rest are trimmed
        item[spec[1]] = [self.op isEqualToString:@"set"] ? text : [self trimmed:text];
    }
    BOOL runOnly = (self.isChange && !self.typingNewName) ? self.pickedRunOnly : self.runOnlySwitch.isOn;
    if (runOnly) item[@"scope"] = @"run";
    if (self.original[@"disabled"]) item[@"disabled"] = self.original[@"disabled"];
    void (^onSave)(NSDictionary *) = self.onSave;
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:^{
        if (onSave) onSave(item);
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RCSetVariableSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case RCSetVariableSectionNewValue:
        case RCSetVariableSectionChange:
            return 1;
        case RCSetVariableSectionVariable:
            if (self.isChange) return self.typingNewName ? 2 : 1;
            return self.allNames.count ? 2 : 1;
        case RCSetVariableSectionFields:
            return [self currentFields].count + ([self.op isEqualToString:@"command"] ? 1 : 0);
        default:
            return self.showsNameField ? 1 : 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case RCSetVariableSectionNewValue: return @"Set Value";
        case RCSetVariableSectionChange: return @"Change Value";
        default: return nil;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == RCSetVariableSectionVariable) return self.variableFooter;
    if (section == RCSetVariableSectionFields) return self.fieldsFooter;
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RCSetVariableSectionScope && self.showsNameField) return @"Off: the value is saved for every trigger. On: it is forgotten when this run ends.";
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == RCSetVariableSectionNewValue || section == RCSetVariableSectionChange) return 8;
    if (section == RCSetVariableSectionScope && !self.showsNameField) return CGFLOAT_MIN;
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == RCSetVariableSectionScope && !self.showsNameField) return CGFLOAT_MIN;
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)plainCell {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// A row with a label on the left and a control filling the rest
- (UITableViewCell *)cellWithLabel:(NSString *)labelText control:(UIView *)control {
    UITableViewCell *cell = [self plainCell];
    [control removeFromSuperview];
    UILabel *label = [[UILabel alloc] init];
    label.text = labelText;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [cell.contentView addSubview:label];
    [cell.contentView addSubview:control];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [label.widthAnchor constraintGreaterThanOrEqualToConstant:90],
        [control.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
        [control.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [control.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [control.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [control.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    return cell;
}

// A row with a switch. The switch goes in the content view rather than accessoryView: these
// switches are kept across reloads, and a cell on its way out would keep taking an accessory
// back from the new cell during layout, freezing the screen.
- (UITableViewCell *)switchCell:(NSString *)labelText control:(UISwitch *)control {
    UITableViewCell *cell = [self plainCell];
    [control removeFromSuperview];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *label = [[UILabel alloc] init];
    label.text = labelText;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:label];
    [cell.contentView addSubview:control];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12],
        [control.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [control.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    return cell;
}

- (UITableViewCell *)gridCell:(UIView *)grid {
    UITableViewCell *cell = [self plainCell];
    cell.backgroundColor = [UIColor clearColor];
    [grid removeFromSuperview];
    [cell.contentView addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [grid.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        [grid.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [grid.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
    ]];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case RCSetVariableSectionNewValue: return [self gridCell:self.valueGrid];
        case RCSetVariableSectionChange: return [self gridCell:self.changeGrid];
        case RCSetVariableSectionVariable:
            if (self.isChange) {
                if (indexPath.row == 0) return [self cellWithLabel:@"Variable" control:self.variableButton];
                return [self cellWithLabel:@"Name" control:self.nameField];
            }
            if (indexPath.row == 0) return [self cellWithLabel:@"Name" control:self.nameField];
            return [self savedNamesCell];
        case RCSetVariableSectionFields: {
            NSArray *fields = [self currentFields];
            if (indexPath.row < (NSInteger)fields.count) {
                return [self cellWithLabel:fields[indexPath.row][0] control:self.valueFields[indexPath.row]];
            }
            return [self switchCell:@"Number Only" control:self.numberOnlySwitch];
        }
        default: {
            return [self switchCell:@"This Run Only" control:self.runOnlySwitch];
        }
    }
}

// Known variables as chips; tapping one fills in the name
- (UITableViewCell *)savedNamesCell {
    UITableViewCell *cell = [self plainCell];
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.showsHorizontalScrollIndicator = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    RCConfigManager *cm = [RCConfigManager sharedManager];
    for (NSString *name in self.allNames) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        [chip setTitle:name forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightMedium];
        chip.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
        chip.layer.cornerRadius = 15;
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        CGFloat width = [name sizeWithAttributes:@{ NSFontAttributeName: chip.titleLabel.font }].width + 24;
        [NSLayoutConstraint activateConstraints:@[
            [chip.heightAnchor constraintEqualToConstant:30],
            [chip.widthAnchor constraintEqualToConstant:ceil(width)],
        ]];
        [chip addTarget:self action:@selector(nameChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:chip];
    }
    [scroll addSubview:row];
    [cell.contentView addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [scroll.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
        [scroll.heightAnchor constraintEqualToConstant:30],
        [row.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [row.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [row.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
    ]];
    return cell;
}

@end
