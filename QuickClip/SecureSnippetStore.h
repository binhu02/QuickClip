#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^QCKeychainCompletion)(NSError * _Nullable error);
typedef void (^QCKeychainSecretCompletion)(NSString * _Nullable secret, NSError * _Nullable error);

@interface SecureSnippetStore : NSObject

@property (nonatomic, readonly, copy) NSString *serviceName;

- (void)addSecret:(NSString *)secret
    forSnippetID:(NSString *)snippetID
      completion:(QCKeychainCompletion)completion;

- (void)updateSecret:(NSString *)secret
       forSnippetID:(NSString *)snippetID
authenticationContext:(nullable LAContext *)context
         completion:(QCKeychainCompletion)completion;

- (void)fetchSecretForSnippetID:(NSString *)snippetID
         authenticationContext:(nullable LAContext *)context
                    completion:(QCKeychainSecretCompletion)completion;

- (void)deleteSecretForSnippetID:(NSString *)snippetID
          authenticationContext:(nullable LAContext *)context
                     completion:(QCKeychainCompletion)completion;

@end

NS_ASSUME_NONNULL_END
