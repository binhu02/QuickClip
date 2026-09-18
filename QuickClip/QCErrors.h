#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const QCErrorDomain;

typedef NS_ERROR_ENUM(QCErrorDomain, QCErrorCode) {
    QCErrorCodeUnknown = 1,
    QCErrorCodeJSONMalformed = 2,
    QCErrorCodeJSONWriteFailed = 3,
    QCErrorCodeKeychain = 4,
    QCErrorCodeAuthentication = 5,
    QCErrorCodeMissingSecureValue = 6,
    QCErrorCodeValidation = 7,
    QCErrorCodeRollback = 8
};

@interface QCErrors : NSObject

+ (NSError *)errorWithCode:(QCErrorCode)code description:(NSString *)description;
+ (NSError *)errorWithCode:(QCErrorCode)code description:(NSString *)description underlying:(nullable NSError *)underlying;
+ (NSError *)keychainErrorWithOSStatus:(OSStatus)status operation:(NSString *)operation;
+ (NSError *)jsonErrorAtPath:(NSString *)path reason:(NSString *)reason;

@end

NS_ASSUME_NONNULL_END
