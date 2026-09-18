#import "QCErrors.h"
#import <Security/Security.h>

NSErrorDomain const QCErrorDomain = @"com.quickclip.QuickClip";

@implementation QCErrors

+ (NSError *)errorWithCode:(QCErrorCode)code description:(NSString *)description {
    return [self errorWithCode:code description:description underlying:nil];
}

+ (NSError *)errorWithCode:(QCErrorCode)code description:(NSString *)description underlying:(NSError *)underlying {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = description ?: @"An unknown error occurred.";
    if (underlying != nil) {
        info[NSUnderlyingErrorKey] = underlying;
    }
    return [NSError errorWithDomain:QCErrorDomain code:code userInfo:info];
}

+ (NSError *)keychainErrorWithOSStatus:(OSStatus)status operation:(NSString *)operation {
    NSString *description = nil;
    switch (status) {
        case errSecSuccess:
            description = @"The Keychain operation succeeded.";
            break;
        case errSecItemNotFound:
            description = @"The secure value for this snippet could not be found in Keychain.";
            break;
        case errSecAuthFailed:
            description = @"Authentication failed.";
            break;
        case errSecUserCanceled:
            description = @"Authentication was cancelled.";
            break;
        case errSecInteractionNotAllowed:
            description = @"Keychain interaction is not allowed right now. Unlock your Mac and try again.";
            break;
        case errSecDuplicateItem:
            description = @"A Keychain item for this snippet already exists.";
            break;
        case errSecMissingEntitlement:
            description = @"Secure storage isn’t available with the current code signature. Sign QuickClip with an Apple Development team to use the Data Protection Keychain.";
            break;
        default: {
            NSString *op = operation.length > 0 ? operation : @"Keychain";
            description = [NSString stringWithFormat:@"%@ failed (OSStatus %d).", op, (int)status];
            break;
        }
    }
    NSDictionary *info = @{
        NSLocalizedDescriptionKey: description,
        @"QCKeychainOSStatus": @(status)
    };
    return [NSError errorWithDomain:QCErrorDomain code:QCErrorCodeKeychain userInfo:info];
}

+ (NSError *)jsonErrorAtPath:(NSString *)path reason:(NSString *)reason {
    NSString *description = nil;
    if (path.length > 0) {
        description = [NSString stringWithFormat:@"Couldn’t parse snippets.json at %@: %@", path, reason];
    } else {
        description = [NSString stringWithFormat:@"Couldn’t parse snippets.json: %@", reason];
    }
    return [self errorWithCode:QCErrorCodeJSONMalformed description:description];
}

@end
