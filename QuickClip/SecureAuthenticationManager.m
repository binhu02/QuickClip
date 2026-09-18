#import "SecureAuthenticationManager.h"
#import "AuthenticationManager.h"
#import "QCPreferences.h"
#import "QCErrors.h"
#import <os/log.h>

@interface SecureAuthenticationManager ()
@property (nonatomic, weak) AuthenticationManager *authenticationManager;
@property (nonatomic, strong, nullable) LAContext *secureAuthenticationContext;
@property (nonatomic, strong, nullable) NSDate *secureAuthenticationDate;
@end

@implementation SecureAuthenticationManager

- (instancetype)initWithAuthenticationManager:(AuthenticationManager *)authenticationManager {
    self = [super init];
    if (self != nil) {
        _authenticationManager = authenticationManager;
    }
    return self;
}

- (void)invalidate {
    LAContext *context = self.secureAuthenticationContext;
    self.secureAuthenticationContext = nil;
    self.secureAuthenticationDate = nil;
    [context invalidate];
}

- (void)expireIfNeeded {
    if (![self isSecureSessionValid]) {
        if (self.secureAuthenticationContext != nil) {
            os_log(os_log_create("com.quickclip.QuickClip", "auth"), "Secure authentication session expired");
            [self invalidate];
        }
    }
}

- (BOOL)isSecureSessionValid {
    QCSecureAuthMode mode = [QCPreferences secureAuthMode];
    NSTimeInterval timeout = [QCPreferences secureAuthTimeoutInterval];
    if (mode != QCSecureAuthModeAfter1Minute &&
        mode != QCSecureAuthModeAfter5Minutes &&
        mode != QCSecureAuthModeAfter15Minutes) {
        return NO;
    }
    if (self.secureAuthenticationContext == nil || self.secureAuthenticationDate == nil) {
        return NO;
    }
    if (self.authenticationManager == nil || !self.authenticationManager.isUnlocked) {
        return NO;
    }
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.secureAuthenticationDate];
    return elapsed < timeout;
}

- (BOOL)shouldInvalidateContextAfterUse {
    return [QCPreferences secureAuthMode] == QCSecureAuthModeEveryCopy;
}

- (void)obtainContextForSnippetTitle:(NSString *)title
                          completion:(QCSecureContextCompletion)completion {
    if (completion == nil) {
        return;
    }

    AuthenticationManager *auth = self.authenticationManager;
    if (auth == nil || !auth.isUnlocked) {
        completion(nil, [QCErrors errorWithCode:QCErrorCodeAuthentication
                                    description:@"QuickClip is locked."]);
        return;
    }

    QCSecureAuthMode mode = [QCPreferences secureAuthMode];
    NSString *reason = [NSString stringWithFormat:@"Copy secure snippet “%@”", title.length > 0 ? title : @"item"];

    switch (mode) {
        case QCSecureAuthModeUseAppSession: {
            LAContext *context = auth.currentAuthenticatedContext;
            if (context != nil) {
                completion(context, nil);
                return;
            }
            __weak typeof(self) weakSelf = self;
            [auth authenticateWithReason:reason completion:^(BOOL success, NSError * _Nullable error) {
                __strong typeof(weakSelf) self = weakSelf;
                if (self == nil) {
                    completion(nil, error);
                    return;
                }
                completion(success ? self.authenticationManager.currentAuthenticatedContext : nil, error);
            }];
            break;
        }
        case QCSecureAuthModeEveryCopy:
            [self authenticateFreshWithReason:reason completion:completion];
            break;
        case QCSecureAuthModeAfter1Minute:
        case QCSecureAuthModeAfter5Minutes:
        case QCSecureAuthModeAfter15Minutes: {
            [self expireIfNeeded];
            if ([self isSecureSessionValid]) {
                completion(self.secureAuthenticationContext, nil);
                return;
            }
            __weak typeof(self) weakSelf = self;
            [self authenticateFreshWithReason:reason completion:^(LAContext * _Nullable context, NSError * _Nullable error) {
                __strong typeof(weakSelf) self = weakSelf;
                if (self == nil) {
                    completion(nil, error);
                    return;
                }
                if (context != nil) {
                    [self.secureAuthenticationContext invalidate];
                    self.secureAuthenticationContext = context;
                    self.secureAuthenticationDate = [NSDate date];
                }
                completion(context, error);
            }];
            break;
        }
    }
}

- (void)authenticateFreshWithReason:(NSString *)reason completion:(QCSecureContextCompletion)completion {
    LAContext *context = [[LAContext alloc] init];
    context.localizedCancelTitle = @"Cancel";
    NSError *canEvalError = nil;
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&canEvalError]) {
        completion(nil, canEvalError ?: [QCErrors errorWithCode:QCErrorCodeAuthentication
                                                    description:@"This Mac cannot evaluate device-owner authentication."]);
        return;
    }
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
            localizedReason:reason
                      reply:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                completion(context, nil);
            } else {
                [context invalidate];
                completion(nil, error);
            }
        });
    }];
}

@end
