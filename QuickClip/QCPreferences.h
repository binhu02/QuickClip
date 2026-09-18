#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QCAppAuthTimeout) {
    QCAppAuthTimeoutEveryTime = 0,
    QCAppAuthTimeout1Minute = 60,
    QCAppAuthTimeout5Minutes = 300,
    QCAppAuthTimeout15Minutes = 900,
    QCAppAuthTimeout30Minutes = 1800,
    QCAppAuthTimeout1Hour = 3600,
    QCAppAuthTimeoutOnlyAfterLaunch = -1
};

typedef NS_ENUM(NSInteger, QCSecureAuthMode) {
    QCSecureAuthModeUseAppSession = 0,
    QCSecureAuthModeEveryCopy = 1,
    QCSecureAuthModeAfter1Minute = 2,
    QCSecureAuthModeAfter5Minutes = 3,
    QCSecureAuthModeAfter15Minutes = 4
};

typedef NS_ENUM(NSInteger, QCSecureClipboardExpiration) {
    QCSecureClipboardExpirationNever = 0,
    QCSecureClipboardExpiration15Seconds = 15,
    QCSecureClipboardExpiration30Seconds = 30,
    QCSecureClipboardExpiration60Seconds = 60
};

@interface QCPreferences : NSObject

+ (void)registerDefaults;

+ (QCAppAuthTimeout)appAuthTimeout;
+ (void)setAppAuthTimeout:(QCAppAuthTimeout)timeout;

+ (BOOL)lockOnSleepOrScreenLock;
+ (void)setLockOnSleepOrScreenLock:(BOOL)lock;

+ (QCSecureAuthMode)secureAuthMode;
+ (void)setSecureAuthMode:(QCSecureAuthMode)mode;

+ (QCSecureClipboardExpiration)secureClipboardExpiration;
+ (void)setSecureClipboardExpiration:(QCSecureClipboardExpiration)expiration;

+ (BOOL)rememberedUnlocked;
+ (void)setRememberedUnlocked:(BOOL)unlocked;

+ (NSTimeInterval)secureAuthTimeoutInterval;

+ (NSString *)titleForAppAuthTimeout:(QCAppAuthTimeout)timeout;
+ (NSString *)titleForSecureAuthMode:(QCSecureAuthMode)mode;
+ (NSString *)titleForClipboardExpiration:(QCSecureClipboardExpiration)expiration;

@end

NS_ASSUME_NONNULL_END
