#import "RCSetupShortcuts.h"
#import "RCSSHHostEditorViewController.h"
#import "RCRCClientEditorViewController.h"

static NSString *RCSetupAddTitle(RCSetupKind kind) {
    return kind == RCSetupKindSSHHost ? @"Add Server" : @"Add Device";
}

void RCOpenSetupEditor(UIViewController *from, RCSetupKind kind, void (^then)(NSDictionary *saved)) {
    UIViewController *editor = nil;
    if (kind == RCSetupKindSSHHost) {
        RCSSHHostEditorViewController *hostEditor = [[RCSSHHostEditorViewController alloc] initWithHost:nil];
        hostEditor.onSave = then;
        editor = hostEditor;
    } else {
        RCRCClientEditorViewController *clientEditor = [[RCRCClientEditorViewController alloc] initWithClient:nil];
        clientEditor.onSave = then;
        editor = clientEditor;
    }
    if (from.navigationController) {
        [from.navigationController pushViewController:editor animated:YES];
        return;
    }
    // Presented on its own, its Cancel and Save close it (the editors handle both ways)
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    [from presentViewController:nav animated:YES completion:nil];
}

void RCPresentSetupNeeded(UIViewController *from, RCSetupKind kind, NSString *title, NSString *message, void (^then)(NSDictionary *saved)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIViewController *weakFrom = from;
    UIAlertAction *add = [UIAlertAction actionWithTitle:RCSetupAddTitle(kind) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (weakFrom) RCOpenSetupEditor(weakFrom, kind, then);
    }];
    [alert addAction:add];
    alert.preferredAction = add;
    [from presentViewController:alert animated:YES completion:nil];
}

UIAlertAction *RCSetupAddAction(UIViewController *from, RCSetupKind kind, void (^then)(NSDictionary *saved)) {
    __weak UIViewController *weakFrom = from;
    return [UIAlertAction actionWithTitle:[RCSetupAddTitle(kind) stringByAppendingString:@"…"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (weakFrom) RCOpenSetupEditor(weakFrom, kind, then);
    }];
}
