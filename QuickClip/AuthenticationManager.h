#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^QCAuthenticationCompletion)(BOOL success, NSError * _Nullable error);

@interface AuthenticationManager : NSObject

@property (nonatomic, readonly) BOOL isUnlocked;
@property (nonatomic, readonly) BOOL hasUnlockedSession;
@property (nonatomic, readonly, nullable) LAContext *currentAuthenticatedContext;
@property (nonatomic, readonly, nullable) NSDate *lastAuthenticationDate;

- (BOOL)isAuthenticationValid;
- (void)authenticateWithReason:(NSString *)reason completion:(QCAuthenticationCompletion)completion;
- (void)unlockWithoutAuthentication;
- (void)lock;
- (void)invalidateAuthentication;

@end

NS_ASSUME_NONNULL_END
