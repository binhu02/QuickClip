#import "SettingsWindowController.h"
#import "LoginItemManager.h"
#import "QCPreferences.h"

@interface SettingsWindowController ()
@property (nonatomic, strong) LoginItemManager *loginItemManager;
@property (nonatomic, strong) NSButton *loginCheckbox;
@property (nonatomic, strong) NSPopUpButton *appAuthPopup;
@property (nonatomic, strong) NSButton *lockOnSleepCheckbox;
@property (nonatomic, strong) NSPopUpButton *secureAuthPopup;
@property (nonatomic, strong) NSPopUpButton *clipboardPopup;
@end

@implementation SettingsWindowController

- (instancetype)initWithLoginItemManager:(LoginItemManager *)loginItemManager {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 520)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"QuickClip Settings";
    window.releasedWhenClosed = NO;
    window.hidesOnDeactivate = NO;
    window.restorable = NO;
    window.level = NSFloatingWindowLevel;
    window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self = [super initWithWindow:window];
    if (self != nil) {
        _loginItemManager = loginItemManager;
        [self buildUI];
        [self reloadFromPreferences];
    }
    return self;
}

- (void)show {
    [self reloadFromPreferences];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
    [self.window makeMainWindow];
}

- (NSTextField *)sectionLabel:(NSString *)title {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:13.0];
    return label;
}

- (NSTextField *)bodyLabel:(NSString *)title {
    NSTextField *label = [NSTextField wrappingLabelWithString:title];
    label.font = [NSFont systemFontOfSize:11.0];
    label.textColor = [NSColor secondaryLabelColor];
    label.preferredMaxLayoutWidth = 420.0;
    return label;
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    [content addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor]
    ]];

    [stack addArrangedSubview:[self sectionLabel:@"General"]];
    self.loginCheckbox = [NSButton checkboxWithTitle:@"Start QuickClip at Login" target:self action:@selector(loginChanged:)];
    [stack addArrangedSubview:self.loginCheckbox];
    [stack addArrangedSubview:[self bodyLabel:@"Starting at login does not unlock QuickClip. The app always starts locked."]];

    [stack addArrangedSubview:[self spacer:8]];
    [stack addArrangedSubview:[self sectionLabel:@"Security"]];

    NSTextField *appAuthLabel = [NSTextField labelWithString:@"Require QuickClip authentication:"];
    [stack addArrangedSubview:appAuthLabel];
    self.appAuthPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.appAuthPopup addItemsWithTitles:@[
        [QCPreferences titleForAppAuthTimeout:QCAppAuthTimeoutEveryTime],
        [QCPreferences titleForAppAuthTimeout:QCAppAuthTimeout1Minute],
        [QCPreferences titleForAppAuthTimeout:QCAppAuthTimeout5Minutes],
        [QCPreferences titleForAppAuthTimeout:QCAppAuthTimeout15Minutes],
        [QCPreferences titleForAppAuthTimeout:QCAppAuthTimeout30Minutes],
        [QCPreferences titleForAppAuthTimeout:QCAppAuthTimeout1Hour],
        [QCPreferences titleForAppAuthTimeout:QCAppAuthTimeoutOnlyAfterLaunch]
    ]];
    self.appAuthPopup.target = self;
    self.appAuthPopup.action = @selector(appAuthChanged:);
    [stack addArrangedSubview:self.appAuthPopup];

    self.lockOnSleepCheckbox = [NSButton checkboxWithTitle:@"Lock after Mac sleeps or screen is locked"
                                                    target:self
                                                    action:@selector(lockOnSleepChanged:)];
    [stack addArrangedSubview:self.lockOnSleepCheckbox];

    [stack addArrangedSubview:[self spacer:8]];
    [stack addArrangedSubview:[self sectionLabel:@"Secure Snippets"]];

    NSTextField *secureAuthLabel = [NSTextField labelWithString:@"Secure Snippet authentication:"];
    [stack addArrangedSubview:secureAuthLabel];
    self.secureAuthPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.secureAuthPopup addItemsWithTitles:@[
        [QCPreferences titleForSecureAuthMode:QCSecureAuthModeUseAppSession],
        [QCPreferences titleForSecureAuthMode:QCSecureAuthModeEveryCopy],
        [QCPreferences titleForSecureAuthMode:QCSecureAuthModeAfter1Minute],
        [QCPreferences titleForSecureAuthMode:QCSecureAuthModeAfter5Minutes],
        [QCPreferences titleForSecureAuthMode:QCSecureAuthModeAfter15Minutes]
    ]];
    self.secureAuthPopup.target = self;
    self.secureAuthPopup.action = @selector(secureAuthChanged:);
    [stack addArrangedSubview:self.secureAuthPopup];

    NSTextField *clipLabel = [NSTextField labelWithString:@"Clear secure clipboard after:"];
    [stack addArrangedSubview:clipLabel];
    self.clipboardPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.clipboardPopup addItemsWithTitles:@[
        [QCPreferences titleForClipboardExpiration:QCSecureClipboardExpiration15Seconds],
        [QCPreferences titleForClipboardExpiration:QCSecureClipboardExpiration30Seconds],
        [QCPreferences titleForClipboardExpiration:QCSecureClipboardExpiration60Seconds],
        [QCPreferences titleForClipboardExpiration:QCSecureClipboardExpirationNever]
    ]];
    self.clipboardPopup.target = self;
    self.clipboardPopup.action = @selector(clipboardChanged:);
    [stack addArrangedSubview:self.clipboardPopup];

    [stack addArrangedSubview:[self spacer:6]];
    [stack addArrangedSubview:[self bodyLabel:@"Keychain protects a Secure Snippet while it is stored at rest. After you copy it, the plaintext is on the system clipboard and is no longer protected by Keychain. Automatic clipboard clearing only reduces how long that copy remains if nothing else overwrites the clipboard. It cannot stop other apps from reading the clipboard while the secret is there."]];

    [self.appAuthPopup.widthAnchor constraintGreaterThanOrEqualToConstant:320].active = YES;
    [self.secureAuthPopup.widthAnchor constraintGreaterThanOrEqualToConstant:320].active = YES;
    [self.clipboardPopup.widthAnchor constraintGreaterThanOrEqualToConstant:320].active = YES;
}

- (NSView *)spacer:(CGFloat)height {
    NSView *view = [[NSView alloc] init];
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
    return view;
}

- (void)reloadFromPreferences {
    self.loginCheckbox.state = self.loginItemManager.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self.appAuthPopup selectItemAtIndex:[self indexForAppAuth:[QCPreferences appAuthTimeout]]];
    self.lockOnSleepCheckbox.state = [QCPreferences lockOnSleepOrScreenLock] ? NSControlStateValueOn : NSControlStateValueOff;
    [self.secureAuthPopup selectItemAtIndex:[self indexForSecureAuth:[QCPreferences secureAuthMode]]];
    [self.clipboardPopup selectItemAtIndex:[self indexForClipboard:[QCPreferences secureClipboardExpiration]]];
}

- (NSInteger)indexForAppAuth:(QCAppAuthTimeout)timeout {
    switch (timeout) {
        case QCAppAuthTimeoutEveryTime: return 0;
        case QCAppAuthTimeout1Minute: return 1;
        case QCAppAuthTimeout5Minutes: return 2;
        case QCAppAuthTimeout15Minutes: return 3;
        case QCAppAuthTimeout30Minutes: return 4;
        case QCAppAuthTimeout1Hour: return 5;
        case QCAppAuthTimeoutOnlyAfterLaunch: return 6;
    }
    return 3;
}

- (QCAppAuthTimeout)appAuthForIndex:(NSInteger)index {
    switch (index) {
        case 0: return QCAppAuthTimeoutEveryTime;
        case 1: return QCAppAuthTimeout1Minute;
        case 2: return QCAppAuthTimeout5Minutes;
        case 3: return QCAppAuthTimeout15Minutes;
        case 4: return QCAppAuthTimeout30Minutes;
        case 5: return QCAppAuthTimeout1Hour;
        case 6: return QCAppAuthTimeoutOnlyAfterLaunch;
        default: return QCAppAuthTimeout15Minutes;
    }
}

- (NSInteger)indexForSecureAuth:(QCSecureAuthMode)mode {
    switch (mode) {
        case QCSecureAuthModeUseAppSession: return 0;
        case QCSecureAuthModeEveryCopy: return 1;
        case QCSecureAuthModeAfter1Minute: return 2;
        case QCSecureAuthModeAfter5Minutes: return 3;
        case QCSecureAuthModeAfter15Minutes: return 4;
    }
    return 0;
}

- (QCSecureAuthMode)secureAuthForIndex:(NSInteger)index {
    switch (index) {
        case 0: return QCSecureAuthModeUseAppSession;
        case 1: return QCSecureAuthModeEveryCopy;
        case 2: return QCSecureAuthModeAfter1Minute;
        case 3: return QCSecureAuthModeAfter5Minutes;
        case 4: return QCSecureAuthModeAfter15Minutes;
        default: return QCSecureAuthModeUseAppSession;
    }
}

- (NSInteger)indexForClipboard:(QCSecureClipboardExpiration)expiration {
    switch (expiration) {
        case QCSecureClipboardExpiration15Seconds: return 0;
        case QCSecureClipboardExpiration30Seconds: return 1;
        case QCSecureClipboardExpiration60Seconds: return 2;
        case QCSecureClipboardExpirationNever: return 3;
    }
    return 1;
}

- (QCSecureClipboardExpiration)clipboardForIndex:(NSInteger)index {
    switch (index) {
        case 0: return QCSecureClipboardExpiration15Seconds;
        case 1: return QCSecureClipboardExpiration30Seconds;
        case 2: return QCSecureClipboardExpiration60Seconds;
        case 3: return QCSecureClipboardExpirationNever;
        default: return QCSecureClipboardExpiration30Seconds;
    }
}

- (void)loginChanged:(NSButton *)sender {
    BOOL enabled = sender.state == NSControlStateValueOn;
    NSError *error = nil;
    if (![self.loginItemManager setEnabled:enabled error:&error]) {
        sender.state = self.loginItemManager.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = @"Couldn’t update Login Item";
        alert.informativeText = error.localizedDescription ?: @"macOS refused to change the login item. Try moving QuickClip to /Applications, then allow it in System Settings → General → Login Items.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
}

- (void)appAuthChanged:(NSPopUpButton *)sender {
    [QCPreferences setAppAuthTimeout:[self appAuthForIndex:sender.indexOfSelectedItem]];
}

- (void)lockOnSleepChanged:(NSButton *)sender {
    [QCPreferences setLockOnSleepOrScreenLock:sender.state == NSControlStateValueOn];
}

- (void)secureAuthChanged:(NSPopUpButton *)sender {
    [QCPreferences setSecureAuthMode:[self secureAuthForIndex:sender.indexOfSelectedItem]];
}

- (void)clipboardChanged:(NSPopUpButton *)sender {
    [QCPreferences setSecureClipboardExpiration:[self clipboardForIndex:sender.indexOfSelectedItem]];
}

@end
