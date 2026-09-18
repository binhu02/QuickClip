#import <AppKit/AppKit.h>

@class SnippetManager;
@class SecureSnippetStore;
@class SecureAuthenticationManager;
@class AuthenticationManager;

NS_ASSUME_NONNULL_BEGIN

@interface SnippetEditorWindowController : NSWindowController

- (instancetype)initWithSnippetManager:(SnippetManager *)snippetManager
                            secureStore:(SecureSnippetStore *)secureStore
                              secureAuth:(SecureAuthenticationManager *)secureAuth
                  authenticationManager:(AuthenticationManager *)authenticationManager NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)show;
- (void)selectNodeWithIdentifier:(nullable NSString *)identifier;
- (void)protectSecureFields;

@end

NS_ASSUME_NONNULL_END
