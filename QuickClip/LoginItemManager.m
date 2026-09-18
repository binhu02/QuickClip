#import "LoginItemManager.h"
#import <os/log.h>

@implementation LoginItemManager

- (SMAppServiceStatus)status {
    return [SMAppService mainAppService].status;
}

- (BOOL)isEnabled {
    return self.status == SMAppServiceStatusEnabled;
}

- (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
    SMAppService *service = [SMAppService mainAppService];
    NSError *localError = nil;
    BOOL ok = YES;
    if (enabled) {
        ok = [service registerAndReturnError:&localError];
    } else {
        ok = [service unregisterAndReturnError:&localError];
    }
    if (!ok) {
        os_log_error(os_log_create("com.quickclip.QuickClip", "login"),
                     "SMAppService %{public}@ failed: %{public}@",
                     enabled ? @"register" : @"unregister",
                     localError.localizedDescription);
        if (error != NULL) {
            *error = localError;
        }
    }
    return ok;
}

@end
