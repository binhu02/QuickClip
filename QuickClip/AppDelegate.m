#import "AppDelegate.h"
#import "SnippetManager.h"
#import "AuthenticationManager.h"
#import "SecureAuthenticationManager.h"
#import "SecureSnippetStore.h"
#import "ClipboardManager.h"
#import "LoginItemManager.h"
#import "SnippetEditorWindowController.h"
#import "SettingsWindowController.h"
#import "QCPreferences.h"
#import "QCStatusImages.h"
#import "QCErrors.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <Security/Security.h>
#import <ApplicationServices/ApplicationServices.h>
#import <os/log.h>

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, strong) SnippetManager *snippetManager;
@property (nonatomic, strong) AuthenticationManager *authenticationManager;
@property (nonatomic, strong) SecureAuthenticationManager *secureAuthenticationManager;
@property (nonatomic, strong) SecureSnippetStore *secureSnippetStore;
@property (nonatomic, strong) ClipboardManager *clipboardManager;
@property (nonatomic, strong) LoginItemManager *loginItemManager;
@property (nonatomic, strong) SnippetEditorWindowController *editorController;
@property (nonatomic, strong) SettingsWindowController *settingsController;
@property (nonatomic, assign) NSInteger copyFeedbackGeneration;
@property (nonatomic, assign) BOOL showingLockedMenu;
@property (nonatomic, assign) BOOL openingWindowFromMenu;
@property (nonatomic, copy, nullable) void (^afterMenuCloses)(void);
@property (nonatomic, assign) BOOL statusMenuIsOpen;
@property (nonatomic, strong) NSTimer *timeoutTimer;
@property (nonatomic, assign) BOOL installedMainMenu;
@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [QCPreferences registerDefaults];

    self.snippetManager = [[SnippetManager alloc] init];
    self.authenticationManager = [[AuthenticationManager alloc] init];
    self.secureSnippetStore = [[SecureSnippetStore alloc] init];
    self.secureAuthenticationManager = [[SecureAuthenticationManager alloc] initWithAuthenticationManager:self.authenticationManager];
    self.clipboardManager = [[ClipboardManager alloc] init];
    self.loginItemManager = [[LoginItemManager alloc] init];

    NSError *error = nil;
    if (![self.snippetManager loadAndCreateIfNeededWithError:&error]) {
        [self presentError:error title:@"Couldn’t load snippets.json"];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(snippetsDidChange:)
                                                 name:QCSnippetsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleWindowDidBecomeKey:)
                                                 name:NSWindowDidBecomeKeyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleWindowDidBecomeMain:)
                                                 name:NSWindowDidBecomeMainNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleWindowWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:nil];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self registerSessionNotifications];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [QCStatusImages lockImage];
    self.statusItem.button.toolTip = @"QuickClip";
    self.statusItem.button.imagePosition = NSImageOnly;

    [self applyInitialLockState];

    __weak typeof(self) weakSelf = self;
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        [weakSelf checkAuthenticationTimeout];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.timeoutTimer forMode:NSRunLoopCommonModes];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self persistLockState];
    [self.clipboardManager clearSecureClipboardIfUnchanged];
    [self.secureAuthenticationManager invalidate];
    [self.authenticationManager invalidateAuthentication];
}

- (void)dealloc {
    [self.timeoutTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Session / lock

- (void)registerSessionNotifications {
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSNotificationCenter *center = workspace.notificationCenter;
    [center addObserver:self selector:@selector(sessionShouldLock:) name:NSWorkspaceWillSleepNotification object:nil];
    [center addObserver:self selector:@selector(sessionShouldLock:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [center addObserver:self selector:@selector(sessionShouldLock:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(sessionShouldLock:)
                                                            name:@"com.apple.screenIsLocked"
                                                          object:nil
                                              suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
}

- (BOOL)needsLocking {
    return self.snippetManager.hasSecureSnippets;
}

- (void)persistLockState {
    BOOL unlocked = !self.needsLocking || self.authenticationManager.isUnlocked;
    [QCPreferences setRememberedUnlocked:unlocked];
}

- (void)applyInitialLockState {
    if (!self.needsLocking || [QCPreferences rememberedUnlocked]) {
        [self.authenticationManager unlockWithoutAuthentication];
        [self persistLockState];
        [self rebuildUnlockedMenu];
        return;
    }
    [self rebuildLockedMenu];
}

- (void)sessionShouldLock:(NSNotification *)notification {
    (void)notification;
    [self.clipboardManager clearSecureClipboardIfUnchanged];
    if ([QCPreferences lockOnSleepOrScreenLock]) {
        [self lockApplication];
    }
}

- (void)checkAuthenticationTimeout {
    if (!self.needsLocking) {
        return;
    }
    [self.secureAuthenticationManager expireIfNeeded];
    if (self.authenticationManager.hasUnlockedSession && ![self.authenticationManager isAuthenticationValid]) {
        [self lockApplication];
    }
}

- (void)lockApplication {
    if (!self.needsLocking) {
        [self.authenticationManager unlockWithoutAuthentication];
        [self persistLockState];
        if (!self.showingLockedMenu) {
            return;
        }
        [self rebuildUnlockedMenu];
        return;
    }
    [self.clipboardManager clearSecureClipboardIfUnchanged];
    [self.secureAuthenticationManager invalidate];
    [self.authenticationManager lock];
    [QCPreferences setRememberedUnlocked:NO];
    [self.editorController protectSecureFields];
    if (self.editorController.window.isVisible) {
        [self.editorController close];
    }
    if (self.settingsController.window.isVisible) {
        [self.settingsController close];
    }
    [self rebuildLockedMenu];
    [self updateStatusIcon];
    os_log(os_log_create("com.quickclip.QuickClip", "app"), "Application locked");
}

- (void)activateApp {
    [NSApp activateIgnoringOtherApps:YES];
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    }
}

- (void)configureWindowForFrontPresentation:(NSWindow *)window {
    if (window == nil) {
        return;
    }
    window.hidesOnDeactivate = NO;
    window.level = NSFloatingWindowLevel;
    window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace
        | NSWindowCollectionBehaviorFullScreenAuxiliary;
}

- (void)bringWindowToFront:(NSWindow *)window {
    if (window == nil) {
        return;
    }
    [self configureWindowForFrontPresentation:window];
    [self transformToForegroundApp];
    [self activateApp];
    [window makeKeyAndOrderFront:nil];
    [window orderFrontRegardless];
    [window makeMainWindow];
}

#pragma mark - Dock visibility

- (BOOL)isStatusRelatedWindow:(NSWindow *)window {
    if (window == nil) {
        return YES;
    }
    if (self.statusItem.button.window != nil && window == self.statusItem.button.window) {
        return YES;
    }
    NSString *name = NSStringFromClass(window.class);
    if ([name containsString:@"NSStatusBar"] ||
        [name containsString:@"NSMenu"] ||
        [name containsString:@"NSPopupMenu"] ||
        [name containsString:@"NSPopupPanel"] ||
        [name containsString:@"NSPopup"]) {
        return YES;
    }
    return NO;
}

- (BOOL)isUserFacingWindow:(NSWindow *)window {
    if (window == nil) {
        return NO;
    }
    if (window == self.editorController.window || window == self.settingsController.window) {
        return YES;
    }
    return NO;
}

- (BOOL)hasUserFacingWindowsExcluding:(NSWindow *)closingWindow {
    NSWindow *editor = self.editorController.window;
    NSWindow *settings = self.settingsController.window;
    if (editor != nil && editor != closingWindow && editor.isVisible) {
        return YES;
    }
    if (settings != nil && settings != closingWindow && settings.isVisible) {
        return YES;
    }
    return NO;
}

- (void)installMainMenuIfNeeded {
    if (self.installedMainMenu) {
        return;
    }
    self.installedMainMenu = YES;

    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"QuickClip"];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"QuickClip"];
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"About QuickClip"
                                                       action:@selector(orderFrontStandardAboutPanel:)
                                                keyEquivalent:@""];
    [appMenu addItem:aboutItem];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"Settings…"
                                                          action:@selector(showSettings:)
                                                   keyEquivalent:@","];
    settingsItem.target = self;
    [appMenu addItem:settingsItem];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Hide QuickClip" action:@selector(hide:) keyEquivalent:@"h"]];
    NSMenuItem *hideOthers = [[NSMenuItem alloc] initWithTitle:@"Hide Others"
                                                        action:@selector(hideOtherApplications:)
                                                 keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItem:hideOthers];
    [appMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""]];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit QuickClip" action:@selector(terminate:) keyEquivalent:@"q"]];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Undo" action:NSSelectorFromString(@"undo:") keyEquivalent:@"z"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Redo" action:NSSelectorFromString(@"redo:") keyEquivalent:@"Z"]];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"]];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];

    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"]];
    [windowMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"]];
    [windowMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""]];
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];
    [NSApp setWindowsMenu:windowMenu];

    NSApp.mainMenu = mainMenu;
}

- (void)transformToForegroundApp {
    ProcessSerialNumber psn = { 0, kCurrentProcess };
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);
#pragma clang diagnostic pop
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
}

- (void)transformToMenuBarApp {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    ProcessSerialNumber psn = { 0, kCurrentProcess };
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    TransformProcessType(&psn, kProcessTransformToUIElementApplication);
#pragma clang diagnostic pop
}

- (void)revealInDock {
    [self installMainMenuIfNeeded];
    [self transformToForegroundApp];
    [self activateApp];
}

- (void)concealFromDockIfNeededExcluding:(NSWindow *)closingWindow {
    if (self.openingWindowFromMenu) {
        return;
    }
    if ([self hasUserFacingWindowsExcluding:closingWindow]) {
        return;
    }
    [self transformToMenuBarApp];
}

- (void)handleWindowDidBecomeKey:(NSNotification *)notification {
    NSWindow *window = notification.object;
    if ([self isUserFacingWindow:window]) {
        [self revealInDock];
    }
}

- (void)handleWindowDidBecomeMain:(NSNotification *)notification {
    NSWindow *window = notification.object;
    if ([self isUserFacingWindow:window]) {
        [self revealInDock];
    }
}

- (void)handleWindowWillClose:(NSNotification *)notification {
    NSWindow *window = notification.object;
    if (![self isUserFacingWindow:window]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf concealFromDockIfNeededExcluding:window];
    });
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    (void)sender;
    if (flag) {
        [self revealInDock];
        return YES;
    }
    return NO;
}

#pragma mark - Status icon

- (void)updateStatusIcon {
    if (self.authenticationManager.isUnlocked) {
        self.statusItem.button.image = [QCStatusImages clipboardImage];
    } else {
        self.statusItem.button.image = [QCStatusImages lockImage];
    }
}

- (void)flashCopySuccess {
    self.copyFeedbackGeneration += 1;
    NSInteger generation = self.copyFeedbackGeneration;
    self.statusItem.button.image = [QCStatusImages checkmarkImage];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        if (self.copyFeedbackGeneration == generation) {
            [self updateStatusIcon];
        }
    });
}

#pragma mark - Menus

- (void)rebuildLockedMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"QuickClip"];
    menu.delegate = self;
    NSMenuItem *locked = [[NSMenuItem alloc] initWithTitle:@"QuickClip is Locked" action:nil keyEquivalent:@""];
    locked.enabled = NO;
    [menu addItem:locked];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *unlock = [[NSMenuItem alloc] initWithTitle:@"Unlock QuickClip…"
                                                    action:@selector(unlockQuickClip:)
                                             keyEquivalent:@""];
    unlock.target = self;
    [menu addItem:unlock];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit QuickClip"
                                                  action:@selector(quitQuickClip:)
                                           keyEquivalent:@""];
    quit.target = self;
    [menu addItem:quit];
    self.menu = menu;
    self.statusItem.menu = menu;
    self.showingLockedMenu = YES;
    [self updateStatusIcon];
}

- (void)rebuildUnlockedMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"QuickClip"];
    menu.delegate = self;
    if (self.snippetManager.rootNodes.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No Snippets" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
    } else {
        [self addNodes:self.snippetManager.rootNodes toMenu:menu];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:@"Edit Snippets…" action:@selector(editSnippets:)];
    [self addItemToMenu:menu title:@"Reload Snippets" action:@selector(reloadSnippets:)];
    [self addItemToMenu:menu title:@"Open Config File" action:@selector(openConfigFile:)];
    [menu addItem:[NSMenuItem separatorItem]];
    if (self.needsLocking) {
        [self addItemToMenu:menu title:@"Lock Now" action:@selector(lockNow:)];
    }
    [self addItemToMenu:menu title:@"Settings…" action:@selector(showSettings:)];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:@"Quit QuickClip" action:@selector(quitQuickClip:)];
    self.menu = menu;
    self.statusItem.menu = menu;
    self.showingLockedMenu = NO;
    [self updateStatusIcon];
}

- (void)addItemToMenu:(NSMenu *)menu title:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
}

- (void)addNodes:(NSArray<SnippetNode *> *)nodes toMenu:(NSMenu *)menu {
    for (SnippetNode *node in nodes) {
        switch (node.type) {
            case SnippetNodeTypeSeparator:
                [menu addItem:[NSMenuItem separatorItem]];
                break;
            case SnippetNodeTypeGroup: {
                NSMenu *submenu = [[NSMenu alloc] initWithTitle:node.displayTitle];
                if (node.items.count == 0) {
                    NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"Empty" action:nil keyEquivalent:@""];
                    empty.enabled = NO;
                    [submenu addItem:empty];
                } else {
                    [self addNodes:node.items toMenu:submenu];
                }
                NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:node.displayTitle action:nil keyEquivalent:@""];
                groupItem.image = [QCStatusImages groupImage];
                groupItem.submenu = submenu;
                [menu addItem:groupItem];
                break;
            }
            case SnippetNodeTypeSecureItem: {
                NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:node.displayTitle
                                                              action:@selector(copySnippet:)
                                                       keyEquivalent:@""];
                item.target = self;
                item.representedObject = node;
                item.image = [QCStatusImages secureSnippetImage];
                [menu addItem:item];
                break;
            }
            case SnippetNodeTypeItem: {
                NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:node.displayTitle
                                                              action:@selector(copySnippet:)
                                                       keyEquivalent:@""];
                item.target = self;
                item.representedObject = node;
                [menu addItem:item];
                break;
            }
        }
    }
}

- (void)runAfterMenuCloses:(void (^)(void))block {
    self.openingWindowFromMenu = YES;
    if (!self.statusMenuIsOpen) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block();
        });
        return;
    }
    self.afterMenuCloses = [block copy];
}

- (void)menuWillOpen:(NSMenu *)menu {
    if (menu == self.menu) {
        self.statusMenuIsOpen = YES;
    }
}

- (void)menuDidClose:(NSMenu *)menu {
    if (menu == self.menu) {
        self.statusMenuIsOpen = NO;
    }
    void (^pending)(void) = self.afterMenuCloses;
    self.afterMenuCloses = nil;
    if (pending != nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            pending();
        });
        return;
    }
    if (!self.needsLocking) {
        return;
    }
    if ([QCPreferences appAuthTimeout] != QCAppAuthTimeoutEveryTime) {
        return;
    }
    if (self.openingWindowFromMenu) {
        return;
    }
    if (self.editorController.window.isVisible || self.settingsController.window.isVisible) {
        return;
    }
    if (self.authenticationManager.isUnlocked) {
        [self lockApplication];
    }
}

#pragma mark - Actions

- (void)unlockQuickClip:(id)sender {
    (void)sender;
    __weak typeof(self) weakSelf = self;
    [self.authenticationManager authenticateWithReason:@"Unlock QuickClip" completion:^(BOOL success, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        if (!success) {
            if (error != nil && error.code != LAErrorUserCancel && error.code != LAErrorAppCancel && error.code != LAErrorSystemCancel) {
                [self presentError:error title:@"Couldn’t unlock QuickClip"];
            }
            return;
        }
        [self rebuildUnlockedMenu];
        [self.statusItem.button performClick:nil];
    }];
}

- (void)lockNow:(id)sender {
    (void)sender;
    [self lockApplication];
}

- (void)quitQuickClip:(id)sender {
    (void)sender;
    [NSApp terminate:self];
}

- (void)copySnippet:(NSMenuItem *)sender {
    SnippetNode *node = sender.representedObject;
    if (![node isKindOfClass:[SnippetNode class]]) {
        return;
    }
    if (node.type == SnippetNodeTypeItem) {
        [self.clipboardManager copyNormalString:node.text ?: @""];
        [self flashCopySuccess];
        return;
    }
    if (node.type == SnippetNodeTypeSecureItem) {
        [self copySecureNode:node];
    }
}

- (void)copySecureNode:(SnippetNode *)node {
    if (!self.authenticationManager.isUnlocked) {
        [self lockApplication];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.secureAuthenticationManager obtainContextForSnippetTitle:node.displayTitle
                                                        completion:^(LAContext * _Nullable context, NSError * _Nullable authError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        if (context == nil) {
            if (authError != nil && authError.code != LAErrorUserCancel && authError.code != LAErrorAppCancel && authError.code != LAErrorSystemCancel && authError.code != errSecUserCanceled) {
                [self presentError:authError title:@"Couldn’t copy secure snippet"];
            }
            return;
        }
        NSString *snippetID = node.identifier;
        BOOL invalidateAfterUse = [self.secureAuthenticationManager shouldInvalidateContextAfterUse];
        [self.secureSnippetStore fetchSecretForSnippetID:snippetID
                                  authenticationContext:context
                                             completion:^(NSString * _Nullable secret, NSError * _Nullable error) {
            if (invalidateAfterUse) {
                [context invalidate];
            }
            if (secret == nil) {
                if (error.code == errSecUserCanceled || error.code == LAErrorUserCancel ||
                    error.code == LAErrorAppCancel || error.code == LAErrorSystemCancel) {
                    return;
                }
                NSError *display = error ?: [QCErrors errorWithCode:QCErrorCodeMissingSecureValue
                                                        description:@"The secure value for this snippet could not be found in Keychain."];
                [self presentMissingSecureValue:display forNode:node];
                return;
            }
            if (!self.authenticationManager.isUnlocked) {
                return;
            }
            [self.clipboardManager copySecureString:secret];
            [self flashCopySuccess];
        }];
    }];
}

- (void)presentMissingSecureValue:(NSError *)error forNode:(SnippetNode *)node {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Secure value missing";
    alert.informativeText = error.localizedDescription ?: @"The secure value for this snippet could not be found in Keychain.";
    [alert addButtonWithTitle:@"Edit Snippet"];
    [alert addButtonWithTitle:@"OK"];
    [self revealInDock];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        [self showEditorSelecting:node];
        return;
    }
    [self concealFromDockIfNeededExcluding:nil];
}

- (void)editSnippets:(id)sender {
    (void)sender;
    [self showEditorSelecting:nil];
}

- (void)showEditorSelecting:(SnippetNode *)node {
    NSString *identifier = [node.identifier copy];
    __weak typeof(self) weakSelf = self;
    [self runAfterMenuCloses:^{
        [weakSelf presentEditorSelectingIdentifier:identifier];
    }];
}

- (void)presentEditorSelectingIdentifier:(NSString *)identifier {
    if (self.editorController == nil) {
        self.editorController = [[SnippetEditorWindowController alloc] initWithSnippetManager:self.snippetManager
                                                                                   secureStore:self.secureSnippetStore
                                                                                     secureAuth:self.secureAuthenticationManager
                                                                         authenticationManager:self.authenticationManager];
    }
    self.openingWindowFromMenu = YES;
    [self revealInDock];
    [self.editorController show];
    if (identifier.length > 0) {
        [self.editorController selectNodeWithIdentifier:identifier];
    }
    [self bringWindowToFront:self.editorController.window];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        [self bringWindowToFront:self.editorController.window];
        self.openingWindowFromMenu = NO;
    });
}

- (void)reloadSnippets:(id)sender {
    (void)sender;
    NSError *error = nil;
    if (![self.snippetManager reloadWithError:&error]) {
        [self presentError:error title:@"Couldn’t reload snippets.json"];
        return;
    }
    if (!self.needsLocking) {
        [self.authenticationManager unlockWithoutAuthentication];
        [self persistLockState];
        [self rebuildUnlockedMenu];
        return;
    }
    if (self.authenticationManager.isUnlocked) {
        [self rebuildUnlockedMenu];
    }
}

- (void)openConfigFile:(id)sender {
    (void)sender;
    NSURL *url = self.snippetManager.snippetsFileURL;
    if (url == nil) {
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)showSettings:(id)sender {
    (void)sender;
    if (!self.authenticationManager.isUnlocked) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self runAfterMenuCloses:^{
        [weakSelf presentSettings];
    }];
}

- (void)presentSettings {
    if (self.settingsController == nil) {
        self.settingsController = [[SettingsWindowController alloc] initWithLoginItemManager:self.loginItemManager];
    }
    self.openingWindowFromMenu = YES;
    [self revealInDock];
    [self.settingsController show];
    [self bringWindowToFront:self.settingsController.window];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        [self bringWindowToFront:self.settingsController.window];
        self.openingWindowFromMenu = NO;
    });
}

- (void)snippetsDidChange:(NSNotification *)notification {
    (void)notification;
    if (!self.needsLocking) {
        [self.authenticationManager unlockWithoutAuthentication];
        [self persistLockState];
        [self rebuildUnlockedMenu];
        return;
    }
    if (self.authenticationManager.isUnlocked) {
        [self rebuildUnlockedMenu];
    }
}

- (void)presentError:(NSError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
    [alert addButtonWithTitle:@"OK"];
    [self revealInDock];
    [alert runModal];
    [self concealFromDockIfNeededExcluding:nil];
}

@end
