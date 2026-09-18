#import "QCPreferences.h"

static NSString * const QCAppAuthTimeoutKey = @"QCAppAuthTimeout";
static NSString * const QCLockOnSleepOrScreenLockKey = @"QCLockOnSleepOrScreenLock";
static NSString * const QCSecureAuthModeKey = @"QCSecureAuthMode";
static NSString * const QCSecureClipboardExpirationKey = @"QCSecureClipboardExpiration";
static NSString * const QCRememberedUnlockedKey = @"QCRememberedUnlocked";

@implementation QCPreferences

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        QCAppAuthTimeoutKey: @(QCAppAuthTimeout15Minutes),
        QCLockOnSleepOrScreenLockKey: @YES,
        QCSecureAuthModeKey: @(QCSecureAuthModeUseAppSession),
        QCSecureClipboardExpirationKey: @(QCSecureClipboardExpiration30Seconds)
    }];
}

+ (QCAppAuthTimeout)appAuthTimeout {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:QCAppAuthTimeoutKey];
    switch (value) {
        case QCAppAuthTimeoutEveryTime:
        case QCAppAuthTimeout1Minute:
        case QCAppAuthTimeout5Minutes:
        case QCAppAuthTimeout15Minutes:
        case QCAppAuthTimeout30Minutes:
        case QCAppAuthTimeout1Hour:
        case QCAppAuthTimeoutOnlyAfterLaunch:
            return (QCAppAuthTimeout)value;
        default:
            return QCAppAuthTimeout15Minutes;
    }
}

+ (void)setAppAuthTimeout:(QCAppAuthTimeout)timeout {
    [[NSUserDefaults standardUserDefaults] setInteger:timeout forKey:QCAppAuthTimeoutKey];
}

+ (BOOL)lockOnSleepOrScreenLock {
    return [[NSUserDefaults standardUserDefaults] boolForKey:QCLockOnSleepOrScreenLockKey];
}

+ (void)setLockOnSleepOrScreenLock:(BOOL)lock {
    [[NSUserDefaults standardUserDefaults] setBool:lock forKey:QCLockOnSleepOrScreenLockKey];
}

+ (QCSecureAuthMode)secureAuthMode {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:QCSecureAuthModeKey];
    switch (value) {
        case QCSecureAuthModeUseAppSession:
        case QCSecureAuthModeEveryCopy:
        case QCSecureAuthModeAfter1Minute:
        case QCSecureAuthModeAfter5Minutes:
        case QCSecureAuthModeAfter15Minutes:
            return (QCSecureAuthMode)value;
        default:
            return QCSecureAuthModeUseAppSession;
    }
}

+ (void)setSecureAuthMode:(QCSecureAuthMode)mode {
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:QCSecureAuthModeKey];
}

+ (QCSecureClipboardExpiration)secureClipboardExpiration {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:QCSecureClipboardExpirationKey];
    switch (value) {
        case QCSecureClipboardExpirationNever:
        case QCSecureClipboardExpiration15Seconds:
        case QCSecureClipboardExpiration30Seconds:
        case QCSecureClipboardExpiration60Seconds:
            return (QCSecureClipboardExpiration)value;
        default:
            return QCSecureClipboardExpiration30Seconds;
    }
}

+ (void)setSecureClipboardExpiration:(QCSecureClipboardExpiration)expiration {
    [[NSUserDefaults standardUserDefaults] setInteger:expiration forKey:QCSecureClipboardExpirationKey];
}

+ (BOOL)rememberedUnlocked {
    return [[NSUserDefaults standardUserDefaults] boolForKey:QCRememberedUnlockedKey];
}

+ (void)setRememberedUnlocked:(BOOL)unlocked {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:unlocked forKey:QCRememberedUnlockedKey];
    [defaults synchronize];
}

+ (NSTimeInterval)secureAuthTimeoutInterval {
    switch ([self secureAuthMode]) {
        case QCSecureAuthModeAfter1Minute: return 60.0;
        case QCSecureAuthModeAfter5Minutes: return 300.0;
        case QCSecureAuthModeAfter15Minutes: return 900.0;
        default: return 0.0;
    }
}

+ (NSString *)titleForAppAuthTimeout:(QCAppAuthTimeout)timeout {
    switch (timeout) {
        case QCAppAuthTimeoutEveryTime: return @"Every time";
        case QCAppAuthTimeout1Minute: return @"After 1 minute";
        case QCAppAuthTimeout5Minutes: return @"After 5 minutes";
        case QCAppAuthTimeout15Minutes: return @"After 15 minutes";
        case QCAppAuthTimeout30Minutes: return @"After 30 minutes";
        case QCAppAuthTimeout1Hour: return @"After 1 hour";
        case QCAppAuthTimeoutOnlyAfterLaunch: return @"Only after app launch";
    }
    return @"After 15 minutes";
}

+ (NSString *)titleForSecureAuthMode:(QCSecureAuthMode)mode {
    switch (mode) {
        case QCSecureAuthModeUseAppSession: return @"Use current QuickClip unlock session";
        case QCSecureAuthModeEveryCopy: return @"Every secure copy";
        case QCSecureAuthModeAfter1Minute: return @"After 1 minute";
        case QCSecureAuthModeAfter5Minutes: return @"After 5 minutes";
        case QCSecureAuthModeAfter15Minutes: return @"After 15 minutes";
    }
    return @"Use current QuickClip unlock session";
}

+ (NSString *)titleForClipboardExpiration:(QCSecureClipboardExpiration)expiration {
    switch (expiration) {
        case QCSecureClipboardExpiration15Seconds: return @"15 seconds";
        case QCSecureClipboardExpiration30Seconds: return @"30 seconds";
        case QCSecureClipboardExpiration60Seconds: return @"60 seconds";
        case QCSecureClipboardExpirationNever: return @"Never";
    }
    return @"30 seconds";
}

@end
