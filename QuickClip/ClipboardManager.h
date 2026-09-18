#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ClipboardManager : NSObject

- (void)copyNormalString:(NSString *)string;
- (void)copySecureString:(NSString *)string;
- (void)clearSecureClipboardIfUnchanged;
- (void)cancelSecureExpirationTimer;

@end

NS_ASSUME_NONNULL_END
