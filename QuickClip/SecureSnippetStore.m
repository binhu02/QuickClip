#import "SecureSnippetStore.h"
#import "QCErrors.h"
#import <Security/Security.h>
#import <os/log.h>

/*
 SecureSnippetStore Keychain layout (Data Protection Keychain):

   class:   kSecClassGenericPassword
   service: <bundle-id>.secure-snippet
   account: snippet UUID (stable; titles are not identifiers)
   value:   UTF-8 secret bytes
   access:  SecAccessControlCreateWithFlags(
                NULL,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecAccessControlUserPresence,
                ...)
   flags:   kSecUseDataProtectionKeychain = YES when the process has an App ID
            entitlement (Apple Development / Developer ID signing)

 If Data Protection Keychain returns errSecMissingEntitlement (-34018), which
 happens for ad-hoc / unsigned local builds, QuickClip stores the same
 generic-password item in the login keychain instead. Application-level
 LocalAuthentication still gates every secure read. Sign with a development
 team to get the Data Protection Keychain and SecAccessControl user presence.

 iCloud Keychain sync is not enabled. Authenticated reads/updates run on a
 serial background queue; completions are delivered on the main queue.
 */

@interface SecureSnippetStore ()
@property (nonatomic, copy, readwrite) NSString *serviceName;
@property (nonatomic, strong) dispatch_queue_t keychainQueue;
@property (nonatomic, assign) BOOL determinedBackend;
@property (nonatomic, assign) BOOL useDataProtectionKeychain;
@end

@implementation SecureSnippetStore

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID.length == 0) {
            bundleID = @"com.quickclip.QuickClip";
        }
        _serviceName = [bundleID stringByAppendingString:@".secure-snippet"];
        _keychainQueue = dispatch_queue_create("com.quickclip.QuickClip.keychain", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (os_log_t)log {
    return os_log_create("com.quickclip.QuickClip", "keychain");
}

- (void)finishOnMain:(dispatch_block_t)block {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

- (SecAccessControlRef)createAccessControl:(NSError **)error {
    CFErrorRef cfError = NULL;
    SecAccessControlRef access = SecAccessControlCreateWithFlags(
        NULL,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAccessControlUserPresence,
        &cfError
    );
    if (access == NULL) {
        NSError *bridge = cfError != NULL ? (__bridge_transfer NSError *)cfError : nil;
        if (error != NULL) {
            *error = [QCErrors errorWithCode:QCErrorCodeKeychain
                                 description:@"Couldn’t create Keychain access control for the Secure Snippet."
                                  underlying:bridge];
        } else if (cfError != NULL) {
            CFRelease(cfError);
        }
        return NULL;
    }
    return access;
}

- (NSMutableDictionary *)queryForSnippetID:(NSString *)snippetID
                          dataProtection:(BOOL)dataProtection
                  authenticationContext:(LAContext *)context {
    NSMutableDictionary *query = [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.serviceName,
        (__bridge id)kSecAttrAccount: snippetID
    } mutableCopy];
    if (dataProtection) {
        query[(__bridge id)kSecUseDataProtectionKeychain] = @YES;
        if (context != nil) {
            query[(__bridge id)kSecUseAuthenticationContext] = context;
        }
    }
    return query;
}

- (BOOL)shouldFallbackFromDataProtectionStatus:(OSStatus)status {
    return status == errSecMissingEntitlement;
}

- (void)rememberDataProtectionAvailable:(BOOL)available {
    BOOL alreadySet = self.determinedBackend && self.useDataProtectionKeychain == available;
    if (alreadySet) {
        return;
    }
    BOOL firstDecision = !self.determinedBackend;
    self.determinedBackend = YES;
    self.useDataProtectionKeychain = available;
    if (firstDecision && !available) {
        os_log(self.log, "Data Protection Keychain is unavailable (needs an Apple Development signature). Using the login keychain. Application authentication still gates access.");
    }
}

- (OSStatus)addSecretData:(NSData *)data
            forSnippetID:(NSString *)snippetID
         dataProtection:(BOOL)dataProtection {
    SecAccessControlRef access = NULL;
    NSError *accessError = nil;
    if (dataProtection) {
        access = [self createAccessControl:&accessError];
        if (access == NULL) {
            return errSecMissingEntitlement;
        }
    }

    NSMutableDictionary *attributes = [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.serviceName,
        (__bridge id)kSecAttrAccount: snippetID,
        (__bridge id)kSecAttrLabel: @"QuickClip Secure Snippet",
        (__bridge id)kSecAttrDescription: @"Secure snippet",
        (__bridge id)kSecValueData: data
    } mutableCopy];

    if (dataProtection && access != NULL) {
        attributes[(__bridge id)kSecUseDataProtectionKeychain] = @YES;
        attributes[(__bridge id)kSecAttrAccessControl] = (__bridge id)access;
    }

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)attributes, NULL);
    if (access != NULL) {
        CFRelease(access);
    }
    return status;
}

- (void)addSecret:(NSString *)secret
    forSnippetID:(NSString *)snippetID
      completion:(QCKeychainCompletion)completion {
    if (snippetID.length == 0) {
        if (completion != nil) {
            completion([QCErrors errorWithCode:QCErrorCodeValidation
                                   description:@"A Secure Snippet must have a UUID before it can be stored."]);
        }
        return;
    }
    if (secret == nil) {
        if (completion != nil) {
            completion([QCErrors errorWithCode:QCErrorCodeValidation
                                   description:@"A Secure Snippet needs a secret value."]);
        }
        return;
    }

    NSString *secretCopy = [secret copy];
    NSString *account = [snippetID copy];
    dispatch_async(self.keychainQueue, ^{
        NSData *data = [secretCopy dataUsingEncoding:NSUTF8StringEncoding];
        OSStatus status = errSecParam;
        BOOL usedDataProtection = NO;

        if (!self.determinedBackend || self.useDataProtectionKeychain) {
            status = [self addSecretData:data forSnippetID:account dataProtection:YES];
            usedDataProtection = YES;
            if (status == errSecSuccess) {
                [self rememberDataProtectionAvailable:YES];
            } else if ([self shouldFallbackFromDataProtectionStatus:status] ||
                       (self.determinedBackend && self.useDataProtectionKeychain == NO)) {
                os_log(self.log, "SecItemAdd Data Protection failed status=%d; falling back to login keychain", (int)status);
                [self rememberDataProtectionAvailable:NO];
                status = [self addSecretData:data forSnippetID:account dataProtection:NO];
                usedDataProtection = NO;
            }
        } else {
            status = [self addSecretData:data forSnippetID:account dataProtection:NO];
            usedDataProtection = NO;
        }

        data = nil;

        if (status == errSecDuplicateItem) {
            os_log(self.log, "SecItemAdd duplicate for snippet %{public}@; updating existing item", account);
            [self updateSecretOnCurrentQueue:secretCopy
                               forSnippetID:account
                     authenticationContext:nil
                                completion:completion];
            return;
        }

        NSError *error = nil;
        if (status != errSecSuccess) {
            os_log_error(self.log, "SecItemAdd failed for snippet %{public}@ status=%d", account, (int)status);
            error = [QCErrors keychainErrorWithOSStatus:status operation:@"Store secure snippet"];
        } else {
            os_log(self.log, "SecItemAdd succeeded for snippet %{public}@ dataProtection=%{public}@",
                   account, usedDataProtection ? @"YES" : @"NO");
        }
        [self finishOnMain:^{ if (completion) completion(error); }];
    });
}

- (OSStatus)updateSecretData:(NSData *)data
               forSnippetID:(NSString *)snippetID
            dataProtection:(BOOL)dataProtection
    authenticationContext:(LAContext *)context {
    NSMutableDictionary *query = [self queryForSnippetID:snippetID dataProtection:dataProtection authenticationContext:context];
    NSDictionary *attributes = @{
        (__bridge id)kSecValueData: data
    };
    return SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
}

- (void)updateSecretOnCurrentQueue:(NSString *)secret
                     forSnippetID:(NSString *)snippetID
           authenticationContext:(LAContext *)context
                      completion:(QCKeychainCompletion)completion {
    NSData *data = [secret dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus status = errSecParam;

    BOOL tryDataProtection = !self.determinedBackend || self.useDataProtectionKeychain;
    BOOL tryFileBased = !self.determinedBackend || !self.useDataProtectionKeychain;

    if (tryDataProtection) {
        status = [self updateSecretData:data forSnippetID:snippetID dataProtection:YES authenticationContext:context];
        if (status == errSecSuccess) {
            [self rememberDataProtectionAvailable:YES];
        } else if ([self shouldFallbackFromDataProtectionStatus:status] || status == errSecItemNotFound) {
            tryFileBased = YES;
            if ([self shouldFallbackFromDataProtectionStatus:status]) {
                [self rememberDataProtectionAvailable:NO];
            }
        }
    }

    if (status != errSecSuccess && tryFileBased) {
        OSStatus fileStatus = [self updateSecretData:data forSnippetID:snippetID dataProtection:NO authenticationContext:nil];
        if (fileStatus == errSecSuccess) {
            status = fileStatus;
            if (!self.determinedBackend) {
                [self rememberDataProtectionAvailable:NO];
            }
        } else if (status == errSecParam || [self shouldFallbackFromDataProtectionStatus:status] || status == errSecItemNotFound) {
            status = fileStatus;
        }
    }

    data = nil;
    NSError *error = nil;
    if (status != errSecSuccess) {
        os_log_error(self.log, "SecItemUpdate failed for snippet %{public}@ status=%d", snippetID, (int)status);
        error = [QCErrors keychainErrorWithOSStatus:status operation:@"Update secure snippet"];
    } else {
        os_log(self.log, "SecItemUpdate succeeded for snippet %{public}@", snippetID);
    }
    [self finishOnMain:^{ if (completion) completion(error); }];
}

- (void)updateSecret:(NSString *)secret
       forSnippetID:(NSString *)snippetID
authenticationContext:(LAContext *)context
         completion:(QCKeychainCompletion)completion {
    if (snippetID.length == 0 || secret == nil) {
        if (completion != nil) {
            completion([QCErrors errorWithCode:QCErrorCodeValidation
                                   description:@"A Secure Snippet update requires a UUID and a new value."]);
        }
        return;
    }
    NSString *secretCopy = [secret copy];
    NSString *account = [snippetID copy];
    dispatch_async(self.keychainQueue, ^{
        [self updateSecretOnCurrentQueue:secretCopy
                           forSnippetID:account
                 authenticationContext:context
                            completion:completion];
    });
}

- (void)fetchSecretForSnippetID:(NSString *)snippetID
         authenticationContext:(LAContext *)context
                    completion:(QCKeychainSecretCompletion)completion {
    if (completion == nil) {
        return;
    }
    if (snippetID.length == 0) {
        completion(nil, [QCErrors errorWithCode:QCErrorCodeValidation
                                    description:@"This Secure Snippet is missing its UUID."]);
        return;
    }
    NSString *account = [snippetID copy];
    dispatch_async(self.keychainQueue, ^{
        NSString *secret = nil;
        OSStatus status = [self copySecretForSnippetID:account
                                authenticationContext:context
                                               secret:&secret];
        if (status != errSecSuccess) {
            os_log_error(self.log, "SecItemCopyMatching failed for snippet %{public}@ status=%d", account, (int)status);
            NSError *error = [QCErrors keychainErrorWithOSStatus:status operation:@"Read secure snippet"];
            if (status == errSecItemNotFound) {
                error = [QCErrors errorWithCode:QCErrorCodeMissingSecureValue
                                    description:@"The secure value for this snippet could not be found in Keychain."];
            }
            [self finishOnMain:^{ completion(nil, error); }];
            return;
        }
        if (secret == nil) {
            [self finishOnMain:^{
                completion(nil, [QCErrors errorWithCode:QCErrorCodeKeychain
                                            description:@"The Keychain item is not valid UTF-8 text."]);
            }];
            return;
        }
        os_log(self.log, "SecItemCopyMatching succeeded for snippet %{public}@", account);
        [self finishOnMain:^{
            completion(secret, nil);
        }];
    });
}

- (OSStatus)copyMatchingForSnippetID:(NSString *)snippetID
                     dataProtection:(BOOL)dataProtection
             authenticationContext:(LAContext *)context
                            result:(CFTypeRef *)result {
    NSMutableDictionary *query = [self queryForSnippetID:snippetID dataProtection:dataProtection authenticationContext:context];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    return SecItemCopyMatching((__bridge CFDictionaryRef)query, result);
}

- (OSStatus)copySecretForSnippetID:(NSString *)snippetID
            authenticationContext:(LAContext *)context
                           secret:(NSString **)outSecret {
    CFTypeRef result = NULL;
    OSStatus status = errSecItemNotFound;

    BOOL tryDataProtection = !self.determinedBackend || self.useDataProtectionKeychain;
    BOOL tryFileBased = !self.determinedBackend || !self.useDataProtectionKeychain;

    if (tryDataProtection) {
        status = [self copyMatchingForSnippetID:snippetID dataProtection:YES authenticationContext:context result:&result];
        if (status == errSecSuccess) {
            [self rememberDataProtectionAvailable:YES];
        } else {
            if (result != NULL) {
                CFRelease(result);
                result = NULL;
            }
            if ([self shouldFallbackFromDataProtectionStatus:status] || status == errSecItemNotFound) {
                tryFileBased = YES;
                if ([self shouldFallbackFromDataProtectionStatus:status]) {
                    [self rememberDataProtectionAvailable:NO];
                }
            }
        }
    }

    if (status != errSecSuccess && tryFileBased) {
        OSStatus fileStatus = [self copyMatchingForSnippetID:snippetID dataProtection:NO authenticationContext:nil result:&result];
        if (fileStatus == errSecSuccess) {
            status = fileStatus;
            if (!self.determinedBackend) {
                [self rememberDataProtectionAvailable:NO];
            }
        } else if (result != NULL) {
            CFRelease(result);
            result = NULL;
            if (status == errSecItemNotFound || [self shouldFallbackFromDataProtectionStatus:status]) {
                status = fileStatus;
            }
        } else if (status == errSecItemNotFound || [self shouldFallbackFromDataProtectionStatus:status]) {
            status = fileStatus;
        }
    }

    if (status != errSecSuccess) {
        if (result != NULL) {
            CFRelease(result);
        }
        return status;
    }

    NSData *data = (__bridge_transfer NSData *)result;
    NSString *secret = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    data = nil;
    if (secret == nil) {
        return errSecParam;
    }
    if (outSecret != NULL) {
        *outSecret = secret;
    }
    return errSecSuccess;
}

- (void)deleteSecretForSnippetID:(NSString *)snippetID
          authenticationContext:(LAContext *)context
                     completion:(QCKeychainCompletion)completion {
    if (snippetID.length == 0) {
        if (completion != nil) {
            completion([QCErrors errorWithCode:QCErrorCodeValidation
                                   description:@"Cannot delete a Secure Snippet without a UUID."]);
        }
        return;
    }
    NSString *account = [snippetID copy];
    dispatch_async(self.keychainQueue, ^{
        OSStatus status = errSecItemNotFound;
        BOOL tryDataProtection = !self.determinedBackend || self.useDataProtectionKeychain;
        BOOL tryFileBased = !self.determinedBackend || !self.useDataProtectionKeychain;

        if (tryDataProtection) {
            NSMutableDictionary *query = [self queryForSnippetID:account dataProtection:YES authenticationContext:context];
            status = SecItemDelete((__bridge CFDictionaryRef)query);
            if (status == errSecSuccess) {
                [self rememberDataProtectionAvailable:YES];
            } else if ([self shouldFallbackFromDataProtectionStatus:status] || status == errSecItemNotFound) {
                tryFileBased = YES;
                if ([self shouldFallbackFromDataProtectionStatus:status]) {
                    [self rememberDataProtectionAvailable:NO];
                }
            }
        }

        if (status != errSecSuccess && tryFileBased) {
            NSMutableDictionary *query = [self queryForSnippetID:account dataProtection:NO authenticationContext:nil];
            OSStatus fileStatus = SecItemDelete((__bridge CFDictionaryRef)query);
            if (fileStatus == errSecSuccess || status == errSecItemNotFound || [self shouldFallbackFromDataProtectionStatus:status]) {
                status = fileStatus;
            }
        }

        NSError *error = nil;
        if (status == errSecItemNotFound) {
            os_log(self.log, "SecItemDelete: item already absent for snippet %{public}@", account);
        } else if (status != errSecSuccess) {
            os_log_error(self.log, "SecItemDelete failed for snippet %{public}@ status=%d", account, (int)status);
            error = [QCErrors keychainErrorWithOSStatus:status operation:@"Delete secure snippet"];
        } else {
            os_log(self.log, "SecItemDelete succeeded for snippet %{public}@", account);
        }
        [self finishOnMain:^{ if (completion) completion(error); }];
    });
}

@end
