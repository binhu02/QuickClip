#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>

@class AuthenticationManager;

NS_ASSUME_NONNULL_BEGIN

typedef void (^QCSecureContextCompletion)(LAContext * _Nullable context, NSError * _Nullable error);

@interface SecureAuthenticationManager : NSObject

- (instancetype)initWithAuthenticationManager:(AuthenticationManager *)authenticationManager NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)obtainContextForSnippetTitle:(NSString *)title
                          completion:(QCSecureContextCompletion)completion;
- (BOOL)shouldInvalidateContextAfterUse;
- (void)invalidate;
- (void)expireIfNeeded;

@end

NS_ASSUME_NONNULL_END
