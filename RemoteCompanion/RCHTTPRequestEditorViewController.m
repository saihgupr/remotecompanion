#import "RCHTTPRequestEditorViewController.h"
#import "RCConfigManager.h"
#import "RCHTTPAction.h"

@interface RCHTTPRequestEditorViewController () <UITextFieldDelegate, UITextViewDelegate>
@property (nonatomic, strong) UISegmentedControl *methodSegment;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextView *headersView;
@property (nonatomic, strong) UILabel *headersPlaceholder;
@property (nonatomic, strong) UITextView *bodyView;
@property (nonatomic, strong) UILabel *bodyPlaceholder;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic, copy) NSString *initialURL;
@property (nonatomic, copy) NSString *initialHeaders;
@property (nonatomic, copy) NSString *initialBody;
@property (nonatomic, copy) NSString *actionString;
@property (nonatomic, assign) BOOL editingExisting;
@end

@implementation RCHTTPRequestEditorViewController

static NSArray<NSString *> *RCHTTPMethods(void) {
    static NSArray *methods;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        methods = @[@"GET", @"POST", @"PUT", @"PATCH", @"DELETE"];
    });
    return methods;
}

- (instancetype)initWithActionString:(NSString *)anAction {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        NSDictionary *components = [RCHTTPAction componentsFromActionString:anAction];
        _initialURL = [components[@"url"] description] ?: @"";
        _initialHeaders = [RCHTTPAction linesFromHeaders:components[@"headers"]];
        _initialBody = [components[@"body"] description] ?: @"";
        _actionString = [anAction copy] ?: @"";
        _editingExisting = anAction.length > 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.editingExisting ? @"Edit REST Request" : @"New REST Request";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelTapped)];
    self.saveButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = self.saveButton;

    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 10;
    }

    [self buildFields];
    [self updateSaveButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTweaks];
}

- (void)applyTweaks {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    CGFloat mainBG = [cm tweakValueForKey:@"mainBackground" defaultVal:0.09];
    UIColor *settingsBG = [cm tweakColorForKey:@"settingsBackground" defaultVal:mainBG];
    self.view.backgroundColor = settingsBG;
    self.tableView.backgroundColor = settingsBG;
    self.navigationController.navigationBar.backgroundColor = [cm tweakColorForKey:@"navBar" defaultVal:0.09];
    self.tableView.separatorColor = [cm tweakColorForKey:@"separators" defaultVal:0.30];
}

- (void)buildFields {
    // A saved action's method may be newer than this list: show it, not GET
    NSDictionary *components = [RCHTTPAction componentsFromActionString:self.actionString];
    NSString *method = [components[@"method"] description] ?: @"GET";
    NSMutableArray *items = [RCHTTPMethods() mutableCopy];
    if (![items containsObject:method]) {
        [items insertObject:method atIndex:0];
    }
    self.methodSegment = [[UISegmentedControl alloc] initWithItems:items];
    self.methodSegment.selectedSegmentIndex = [items indexOfObject:method];
    [self.methodSegment addTarget:self action:@selector(methodChanged:) forControlEvents:UIControlEventValueChanged];

    self.urlField = [[UITextField alloc] init];
    self.urlField.placeholder = @"http://127.0.0.1:8080/api/command?cmd=play";
    self.urlField.text = self.initialURL;
    self.urlField.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.urlField.textColor = [UIColor labelColor];
    self.urlField.tintColor = [UIColor labelColor];
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.urlField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.urlField.returnKeyType = UIReturnKeyNext;
    self.urlField.delegate = self;
    [self.urlField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    self.urlField.translatesAutoresizingMaskIntoConstraints = NO;

    self.headersView = [self textViewWithText:self.initialHeaders];
    self.headersPlaceholder = [self placeholderLabel:@"Authorization: Bearer …"];

    self.bodyView = [self textViewWithText:self.initialBody];
    self.bodyPlaceholder = [self placeholderLabel:@"{\"key\": \"value\"}"];
}

- (UITextView *)textViewWithText:(NSString *)text {
    UITextView *view = [[UITextView alloc] init];
    view.delegate = self;
    view.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    view.backgroundColor = [UIColor clearColor];
    view.textColor = [UIColor labelColor];
    view.tintColor = [UIColor labelColor];
    view.keyboardType = UIKeyboardTypeDefault;
    view.autocapitalizationType = UITextAutocapitalizationTypeNone;
    view.autocorrectionType = UITextAutocorrectionTypeNo;
    view.spellCheckingType = UITextSpellCheckingTypeNo;
    view.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4);
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.text = text ?: @"";
    return view;
}

- (UILabel *)placeholderLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    label.textColor = [UIColor tertiaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.hidden = NO;
    return label;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Request";
    if (section == 1) return @"Headers";
    return @"Body";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Calls this URL when the action runs. For example, http://127.0.0.1:8080/api/command?cmd=play runs an RC command on this iPhone. The Web UI must be on.";
    }
    if (section == 1) {
        return @"Optional. One Name: Value header per line. Lines starting with # are ignored.";
    }
    return @"Optional. Sent exactly as typed in UTF-8. JSON is detected and sent as application/json unless you set a Content-Type header.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return indexPath.row == 0 ? 44 : 56;
    }
    return indexPath.section == 1 ? 120 : 170;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConfigManager *cm = [RCConfigManager sharedManager];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [cm tweakColorForKey:@"blockBackground" defaultVal:0.12];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = [cm tweakColorForKey:@"selectionHighlight" defaultVal:0.15];
    cell.selectedBackgroundView = selBg;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0 && indexPath.row == 0) {
        self.methodSegment.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:self.methodSegment];
        [NSLayoutConstraint activateConstraints:@[
            [self.methodSegment.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [self.methodSegment.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [self.methodSegment.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
        ]];
    } else if (indexPath.section == 0) {
        UILabel *label = [[UILabel alloc] init];
        label.text = @"URL";
        label.font = [UIFont systemFontOfSize:16];
        label.textColor = [UIColor labelColor];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [cell.contentView addSubview:label];
        [cell.contentView addSubview:self.urlField];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [self.urlField.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:12],
            [self.urlField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [self.urlField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [self.urlField.heightAnchor constraintEqualToConstant:34]
        ]];
    } else {
        UITextView *textView = indexPath.section == 1 ? self.headersView : self.bodyView;
        UILabel *placeholder = indexPath.section == 1 ? self.headersPlaceholder : self.bodyPlaceholder;
        [cell.contentView addSubview:textView];
        [cell.contentView addSubview:placeholder];
        [NSLayoutConstraint activateConstraints:@[
            [textView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
            [textView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [textView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
            [textView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
            [placeholder.topAnchor constraintEqualToAnchor:textView.topAnchor constant:12],
            [placeholder.leadingAnchor constraintEqualToAnchor:textView.leadingAnchor constant:9]
        ]];
        placeholder.hidden = textView.text.length > 0;
    }

    return cell;
}

#pragma mark - Editing

- (void)methodChanged:(UISegmentedControl *)sender {
    [self updateSaveButton];
}

- (void)textFieldDidChange:(UITextField *)textField {
    [self updateSaveButton];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.headersView becomeFirstResponder];
    return YES;
}

- (void)textViewDidChange:(UITextView *)textView {
    if (textView == self.headersView) self.headersPlaceholder.hidden = textView.text.length > 0;
    if (textView == self.bodyView) self.bodyPlaceholder.hidden = textView.text.length > 0;
    [self updateSaveButton];
}

- (void)updateSaveButton {
    NSString *url = [self.urlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL hasScheme = [url.lowercaseString hasPrefix:@"http://"] || [url.lowercaseString hasPrefix:@"https://"];
    // A variable ("{url}" or "http://{host}:8080/…") is filled in when the action runs
    BOOL hasVariable = [url rangeOfString:@"{"].location != NSNotFound && [url rangeOfString:@"}"].location != NSNotFound;
    self.saveButton.enabled = url.length > 0 && (hasScheme || hasVariable);
}

#pragma mark - Actions

- (void)cancelTapped {
    BOOL isRootOfPresentedNav = (self.navigationController.viewControllers.firstObject == self)
        && self.navigationController.presentingViewController != nil;
    if (isRootOfPresentedNav) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)saveTapped {
    [self.view endEditing:YES];

    NSString *url = [[self.urlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    BOOL hasScheme = [url.lowercaseString hasPrefix:@"http://"] || [url.lowercaseString hasPrefix:@"https://"];
    BOOL hasVariable = [url rangeOfString:@"{"].location != NSNotFound && [url rangeOfString:@"}"].location != NSNotFound;
    if (url.length == 0 || !(hasScheme || hasVariable)) {
        [self showErrorWithTitle:@"Invalid URL" message:@"Enter a full http:// or https:// URL."];
        return;
    }

    NSString *invalidLine = nil;
    NSDictionary *headers = [RCHTTPAction headersFromLines:self.headersView.text invalidLine:&invalidLine];
    if (!headers) {
        [self showErrorWithTitle:@"Invalid Header"
                         message:[NSString stringWithFormat:@"This line needs a name and a colon:\n%@", invalidLine ?: @""]];
        return;
    }

    NSString *method = @"GET";
    NSInteger selected = self.methodSegment.selectedSegmentIndex;
    if (selected >= 0 && selected < (NSInteger)self.methodSegment.numberOfSegments) {
        method = [self.methodSegment titleForSegmentAtIndex:selected] ?: method;
    }

    NSString *action = [RCHTTPAction actionStringWithMethod:method
                                                        url:url
                                                    headers:headers
                                                       body:self.bodyView.text ?: @""];
    if (self.onSave) self.onSave(action);
}

- (void)showErrorWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
