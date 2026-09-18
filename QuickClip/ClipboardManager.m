#import "ClipboardManager.h"
#import "QCPreferences.h"
#import <AppKit/AppKit.h>
#import <os/log.h>

@interface ClipboardManager ()
@property (nonatomic, assign) NSInteger secureChangeCount;
@property (nonatomic, assign) BOOL hasSecureClipboard;
@property (nonatomic, strong, nullable) NSTimer *expirationTimer;
@end

@implementation ClipboardManager

- (void)dealloc {
    [self cancelSecureExpirationTimer];
}

- (void)copyNormalString:(NSString *)string {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:(string ?: @"") forType:NSPasteboardTypeString];
}

- (void)copySecureString:(NSString *)string {
    [self cancelSecureExpirationTimer];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:(string ?: @"") forType:NSPasteboardTypeString];
    self.secureChangeCount = pasteboard.changeCount;
    self.hasSecureClipboard = YES;
    os_log(os_log_create("com.quickclip.QuickClip", "clipboard"),
           "Secure snippet copied; changeCount=%ld",
           (long)self.secureChangeCount);

    NSTimeInterval seconds = (NSTimeInterval)[QCPreferences secureClipboardExpiration];
    if (seconds > 0) {
        __weak typeof(self) weakSelf = self;
        self.expirationTimer = [NSTimer scheduledTimerWithTimeInterval:seconds repeats:NO block:^(NSTimer * _Nonnull timer) {
            (void)timer;
            [weakSelf clearSecureClipboardIfUnchanged];
        }];
    }
}

- (void)clearSecureClipboardIfUnchanged {
    [self cancelSecureExpirationTimer];
    if (!self.hasSecureClipboard) {
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    if (pasteboard.changeCount == self.secureChangeCount) {
        [pasteboard clearContents];
        os_log(os_log_create("com.quickclip.QuickClip", "clipboard"),
               "Cleared still-current secure clipboard (changeCount=%ld)",
               (long)self.secureChangeCount);
    } else {
        os_log(os_log_create("com.quickclip.QuickClip", "clipboard"),
               "Skipped clipboard clear; changeCount changed from %ld to %ld",
               (long)self.secureChangeCount,
               (long)pasteboard.changeCount);
    }
    self.hasSecureClipboard = NO;
}

- (void)cancelSecureExpirationTimer {
    [self.expirationTimer invalidate];
    self.expirationTimer = nil;
}

@end
