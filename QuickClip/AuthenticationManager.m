#import "AuthenticationManager.h"
#import "QCPreferences.h"
#import "QCErrors.h"
#import <os/log.h>

@interface AuthenticationManager ()
@property (nonatomic, assign) BOOL hasUnlockedSession;
@property (nonatomic, strong, nullable) LAContext *authenticatedContext;
@property (nonatomic, strong, nullable) NSDate *lastAuthenticationDate;
@end

@implementation AuthenticationManager

- (LAContext *)currentAuthenticatedContext {
    if (![self isAuthenticationValid]) {
        return nil;
    }
    return self.authenticatedContext;
}

- (BOOL)isUnlocked {
    return [self isAuthenticationValid];
}

- (BOOL)isAuthenticationValid {
    if (!self.hasUnlockedSession) {
        return NO;
    }
    QCAppAuthTimeout timeout = [QCPreferences appAuthTimeout];
    if (timeout == QCAppAuthTimeoutOnlyAfterLaunch || timeout == QCAppAuthTimeoutEveryTime) {
        return YES;
    }
    if (self.lastAuthenticationDate == nil) {
        return NO;
    }
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.lastAuthenticationDate];
    return elapsed < (NSTimeInterval)timeout;
}

- (void)authenticateWithReason:(NSString *)reason completion:(QCAuthenticationCompletion)completion {
    LAContext *context = [[LAContext alloc] init];
    context.localizedCancelTitle = @"Cancel";
    NSError *canEvalError = nil;
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&canEvalError]) {
        os_log_error(os_log_create("com.quickclip.QuickClip", "auth"),
                     "canEvaluatePolicy failed: %{public}@",
                     canEvalError.localizedDescription);
        if (completion != nil) {
            completion(NO, canEvalError ?: [QCErrors errorWithCode:QCErrorCodeAuthentication
                                                       description:@"This Mac cannot evaluate device-owner authentication."]);
        }
        return;
    }

    NSString *localizedReason = reason.length > 0 ? reason : @"Unlock QuickClip";
    __weak typeof(self) weakSelf = self;
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
            localizedReason:localizedReason
                      reply:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) {
                if (completion != nil) {
                    completion(NO, [QCErrors errorWithCode:QCErrorCodeAuthentication
                                               description:@"Authentication manager was released."]);
                }
                return;
            }
            if (success) {
                [self.authenticatedContext invalidate];
                self.authenticatedContext = context;
                self.lastAuthenticationDate = [NSDate date];
                self.hasUnlockedSession = YES;
                [QCPreferences setRememberedUnlocked:YES];
                os_log(os_log_create("com.quickclip.QuickClip", "auth"), "QuickClip unlocked");
            } else {
                os_log(os_log_create("com.quickclip.QuickClip", "auth"),
                       "Authentication failed code=%ld",
                       (long)error.code);
            }
            if (completion != nil) {
                completion(success, error);
            }
        });
    }];
}

- (void)unlockWithoutAuthentication {
    self.hasUnlockedSession = YES;
    if (self.lastAuthenticationDate == nil) {
        self.lastAuthenticationDate = [NSDate date];
    }
    [QCPreferences setRememberedUnlocked:YES];
}

- (void)lock {
    [self invalidateAuthentication];
}

- (void)invalidateAuthentication {
    BOOL wasUnlocked = self.hasUnlockedSession;
    self.hasUnlockedSession = NO;
    self.lastAuthenticationDate = nil;
    LAContext *context = self.authenticatedContext;
    self.authenticatedContext = nil;
    [context invalidate];
    if (wasUnlocked) {
        os_log(os_log_create("com.quickclip.QuickClip", "auth"), "QuickClip locked; authentication context invalidated");
    }
}

@end
