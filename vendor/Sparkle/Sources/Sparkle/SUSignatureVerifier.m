//
//  SUDSAVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//
//  Includes code by Zach Waldowski on 10/18/13.
//  Copyright 2014 Big Nerd Ranch. Licensed under MIT.
//
//  Includes code from Plop by Mark Hamlin.
//  Copyright 2011 Mark Hamlin. Licensed under BSD.
//

#import "SUSignatureVerifier.h"
#import "SULog.h"
#import "SUSignatures.h"
#import "SUErrors.h"
#import "SPUVerifierInformation.h"
#import "SUConstants.h"
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
#include <CommonCrypto/CommonDigest.h>
#endif
#import "ed25519.h"


#include "AppKitPrevention.h"

@implementation SUSignatureVerifier
{
    SUPublicKeys *_pubKeys;
}

+ (BOOL)validatePath:(NSString *)path withSignatures:(SUSignatures *)signatures withPublicKeys:(SUPublicKeys *)pkeys verifierInformation:(SPUVerifierInformation * _Nullable)verifierInformation error:(NSError * __autoreleasing *)error
{
    SUSignatureVerifier *verifier = [(SUSignatureVerifier *)[self alloc] initWithPublicKeys:pkeys];
    return [verifier verifyFileAtPath:path signatures:signatures verifierInformation:verifierInformation error:error];
}

- (instancetype)initWithPublicKeys:(SUPublicKeys *)pubkeys
{
    self = [super init];
    if (self != nil) {
        _pubKeys = pubkeys;
    }
    return self;
}

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
- (SecKeyRef)dsaSecKeyRef SPU_OBJC_DIRECT
{
    NSData *data = [_pubKeys.dsaPubKey dataUsingEncoding:NSASCIIStringEncoding];
    if (!self || !data.length) {
        SULog(SULogLevelError, @"Could not read public DSA key");
        return nil;
    }

    SecExternalFormat format = kSecFormatOpenSSL;
    SecExternalItemType itemType = kSecItemTypePublicKey;
    CFArrayRef items = NULL;

    OSStatus status = SecItemImport((__bridge CFDataRef)data, NULL, &format, &itemType, (SecItemImportExportFlags)0, NULL, NULL, &items);
    if (status != errSecSuccess || !items) {
        if (items) {
            CFRelease(items);
        }
        SULog(SULogLevelError, @"Public DSA key could not be imported: %d", status);
        return nil;
    }

    SecKeyRef dsaPubKeySecKey = nil;
    if (format == kSecFormatOpenSSL && itemType == kSecItemTypePublicKey && CFArrayGetCount(items) == 1) {
        // Seems silly, but we can't quiet the warning about dropping CFTypeRef's const qualifier through
        // any manner of casting I've tried, including interim explicit cast to void*. The -Wcast-qual
        // warning is on by default with -Weverything and apparently became more noisy as of Xcode 7.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-qual"
        dsaPubKeySecKey = (SecKeyRef)CFRetain(CFArrayGetValueAtIndex(items, 0));
#pragma clang diagnostic pop
    }

    CFRelease(items);
    return dsaPubKeySecKey;
}
#endif

- (BOOL)verifyFileAtPath:(NSString *)path signatures:(SUSignatures *)signatures verifierInformation:(SPUVerifierInformation * _Nullable)verifierInformation error:(NSError * __autoreleasing *)error
{
    // Data is used only in the case where ed25519 signature is present
    NSData *data;
    if (signatures.ed25519SignatureStatus != SUSigningInputStatusPresent) {
        data = nil;
    } else {
        NSError *dataError = nil;
        data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&dataError];
        
        if (data == nil || data.length == 0) {
            SULog(SULogLevelError, @"Failed to load file %@: %@", path, dataError);
            
            if (error != NULL) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
                userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"Failed to load file: %@", path];
                if (dataError != nil) {
                    userInfo[NSUnderlyingErrorKey] = dataError;
                }
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:[userInfo copy]];
            }
            
            return NO;
        }
    }
    
    return [self verifyData:data signatures:signatures fileKind:@"update" fromPath:path verifierInformation:verifierInformation error:error];
}

- (BOOL)verifyData:(NSData *)data signatures:(SUSignatures *)signatures fileKind:(NSString *)fileKind verifierInformation:(SPUVerifierInformation * _Nullable)verifierInformation error:(NSError * __autoreleasing *)error
{
    return [self verifyData:data signatures:signatures fileKind:fileKind fromPath:nil verifierInformation:verifierInformation error:error];
}

// Note the path must be provided for verifying update archives
- (BOOL)verifyData:(NSData * _Nullable)data signatures:(SUSignatures *)signatures fileKind:(NSString *)fileKind fromPath:(NSString * _Nullable)path verifierInformation:(SPUVerifierInformation * _Nullable)verifierInformation error:(NSError * __autoreleasing *)error SPU_OBJC_DIRECT
{
    if (!signatures) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No signatures given to verify data for %@", fileKind] }];
        }
        return NO;
    }

    switch (_pubKeys.ed25519PubKeyStatus) {
    case SUSigningInputStatusAbsent:
        if (signatures.ed25519SignatureStatus != SUSigningInputStatusAbsent) {
            SULog(SULogLevelDefault, @"The %@ has an EdDSA signature, but it won't be used, because the old app doesn't have an EdDSA public key", fileKind);
        }
        break;
    case SUSigningInputStatusInvalid:
        if (signatures.ed25519SignatureStatus != SUSigningInputStatusAbsent) {
            NSString *message = [NSString stringWithFormat:@"The %@ has an EdDSA signature, but the app has an invalid EdDSA public key, so the %@ will automatically be rejected.", fileKind, fileKind];
            SULog(SULogLevelError, @"%@", message);
            
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            
            return NO;
        }
        SULog(SULogLevelDefault, @"The app has an invalid EdDSA public key, but there is no EdDSA signature in the %@. Falling back to DSA.", fileKind);
        break;
    case SUSigningInputStatusPresent:
        switch (signatures.ed25519SignatureStatus) {
        case SUSigningInputStatusAbsent: {
            NSString *message = [NSString stringWithFormat:@"The app has an EdDSA public key, but there is no EdDSA signature in the %@, so the %@ will be rejected.", fileKind, fileKind];
            SULog(SULogLevelError, @"%@", message);
                
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            
            return NO;
        }
        case SUSigningInputStatusInvalid: {
            NSString *message = [NSString stringWithFormat:@"The %@ has an EdDSA signature, but it's invalid, so the %@ will automatically be rejected.", fileKind, fileKind];
            
            SULog(SULogLevelError, @"%@", message);
                
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            return NO;
        }
        case SUSigningInputStatusPresent: {
            assert(data != nil);
            if (ed25519_verify(signatures.ed25519Signature, (const unsigned char *)data.bytes, data.length, _pubKeys.ed25519PubKey)) {
                SULog(SULogLevelDefault, @"OK: EdDSA signature is correct for %@", fileKind);
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                // No need to check DSA when EdDSA verification succeeded, unless a DSA signature is provided and it's
                // erroneously invalid
                if (signatures.dsaSignatureStatus != SUSigningInputStatusInvalid)
#endif
                {
                    return YES;
                }
            } else {
                NSMutableString *message = [NSMutableString stringWithFormat:@"EdDSA signature does not match. Data of the %@ being checked is different than data that has been signed, or the public key and the private key are not from the same set.", fileKind];
                
                // Elaborate on the error message if we have more information about the download archive
                // If there is verifierInformation it must be for a downloaded update (rather than feed or release notes)
                if (verifierInformation != nil) {
                    BOOL reportedDiscrepancy = NO;
                    
                    NSString *downloadedFileDescription = (path != nil) ? [NSString stringWithFormat:@"%@ (%@)", fileKind, path.lastPathComponent] : fileKind;
                    
                    if (verifierInformation.expectedContentLength > 0 && verifierInformation.actualContentLength > 0) {
                        if (verifierInformation.expectedContentLength != verifierInformation.actualContentLength) {
                            [message appendFormat:@" The downloaded %@ is likely different than the signed file because the expected content length from the appcast item (%llu bytes) differs from the downloaded file length (%llu bytes).", downloadedFileDescription, verifierInformation.expectedContentLength, verifierInformation.actualContentLength];
                            reportedDiscrepancy = YES;
                        }
                    }
                    
                    NSString *actualVersion = verifierInformation.actualVersion;
                    if (actualVersion != nil && ![verifierInformation.expectedVersion isEqualToString:actualVersion]) {
                        [message appendFormat:@" The downloaded %@ also has a CFBundleVersion (%@) which differs from the %@ in the appcast item (%@).", downloadedFileDescription, actualVersion, SUAppcastAttributeVersion, verifierInformation.expectedVersion];
                        reportedDiscrepancy = YES;
                    }
                    
                    if (!reportedDiscrepancy && verifierInformation.expectedContentLength > 0) {
                        [message appendFormat:@" The downloaded %@ is likely not signed correctly because the file has the expected content length (%llu bytes)%@ which matches the appcast item.", downloadedFileDescription, verifierInformation.actualContentLength, (actualVersion == nil ? @"" : [NSString stringWithFormat:@" and CFBundleVersion (%@)", actualVersion])];
                    }
                }
                
                SULog(SULogLevelError, @"%@", [message copy]);
                
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                // Legacy DSA verification is only applicable if archive file path is provided
                if (signatures.dsaSignatureStatus != SUSigningInputStatusAbsent && path != nil) {
                    SULog(SULogLevelDefault, @"DSA signature won't be checked, because EdDSA verification has already failed");
                }
#endif
                
                if (error != NULL) {
                    *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
                }
                
                return NO;
            }
        }
        }
        break;
    }

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
    // Legacy DSA verification is only for downloaded updates
    switch (_pubKeys.dsaPubKeyStatus) {
    case SUSigningInputStatusAbsent:
        if (signatures.dsaSignatureStatus != SUSigningInputStatusAbsent && path != nil) {
            SULog(SULogLevelDefault, @"The update has a DSA signature, but it can't be used, because the old app doesn't have a DSA public key");
        }
        break;
    case SUSigningInputStatusInvalid:
        if (signatures.dsaSignatureStatus != SUSigningInputStatusAbsent && path != nil) {
            // We will have already logged an error for this failure when the public key was read in, so just do an informational log here.
            NSString *message = @"The update has a DSA signature, but the app has an invalid DSA public key, so the update will automatically be rejected.";
            
            SULog(SULogLevelError, @"%@", message);
            
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            
            return NO;
        }
        SULog(SULogLevelDefault, @"The app has an invalid DSA public key, but there is no DSA signature in the update.");
        break;
    case SUSigningInputStatusPresent:
        switch (signatures.dsaSignatureStatus) {
        case SUSigningInputStatusAbsent:
            SULog(SULogLevelError, @"There is no DSA signature in the update");
            break;
        case SUSigningInputStatusInvalid: {
            NSString *message = @"The update has a DSA signature, but it's invalid, so the update will automatically be rejected.";
            
            SULog(SULogLevelError, @"%@", message);
                
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            
            return NO;
        }
        case SUSigningInputStatusPresent: {
            NSInputStream *dataInputStream = (path != nil) ? [NSInputStream inputStreamWithFileAtPath:(NSString * _Nonnull)path] : nil;
            return [self verifyDSASignatureOfStream:dataInputStream dsaSignature:signatures.dsaSignature error:error];
        }
        }
    }
#else
    switch (_pubKeys.dsaPubKeyStatus) {
        case SUSigningInputStatusAbsent:
            break;
        case SUSigningInputStatusInvalid:
            // We don't keep track of DSA signatures, so we will ignore this mistake and treat it as if it were absent
            break;
        case SUSigningInputStatusPresent:
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"The old app has a DSA public key but DSA support is disabled, and the old app does not have an EdDSA public key." }];
            }
            
            return NO;
    }
#endif

    if (error != NULL) {
        // Use generic failure
        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"EdDSA and DSA verification for the %@ has failed", fileKind] }];
    }
    
    return NO;
}

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
- (BOOL)verifyDSASignatureOfStream:(NSInputStream *)stream dsaSignature:(NSData *)dsaSignature error:(NSError * __autoreleasing *)outError SPU_OBJC_DIRECT
{
    if (!stream || !dsaSignature) {
        SULog(SULogLevelError, @"Invalid arguments to verifyStream");
        
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"Invalid arguments to verifyStream" }];
        }
        
        return NO;
    }

    SecKeyRef dsaPubKeySecKey = [self dsaSecKeyRef];
    if (!dsaPubKeySecKey) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to create DSA Sec Key Ref" }];
        }
        
        return NO;
    }

    // Sparkle's DSA support is deprecated
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    __block SecGroupTransformRef group = SecTransformCreateGroupTransform();
    __block SecTransformRef dataReadTransform = NULL;
    __block SecTransformRef dataDigestTransform = NULL;
    __block SecTransformRef dataVerifyTransform = NULL;
    __block CFErrorRef error = NULL;

    BOOL (^cleanup)(void) = ^{
		if (group) CFRelease(group);
		if (dataReadTransform) CFRelease(dataReadTransform);
		if (dataDigestTransform) CFRelease(dataDigestTransform);
		if (dataVerifyTransform) CFRelease(dataVerifyTransform);
		if (error) CFRelease(error);
        if (dsaPubKeySecKey) CFRelease(dsaPubKeySecKey);
		return NO;
    };

    dataReadTransform = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)stream);
    if (!dataReadTransform) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"File containing update archive could not be read (failed to create SecTransform for input stream)" }];
        }
        return cleanup();
    }

    dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA1, CC_SHA1_DIGEST_LENGTH, NULL);
    if (!dataDigestTransform) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"File containing update archive could not be read (failed to create SecDigest for input stream)" }];
        }
        
        return cleanup();
    }
    
    dataVerifyTransform = SecVerifyTransformCreate(dsaPubKeySecKey, (__bridge CFDataRef)dsaSignature, &error);
    if (!dataVerifyTransform) {
        SULog(SULogLevelError, @"Could not understand format of the signature: %@; Signature data: %@", error, dsaSignature);
        if (outError != NULL) {
            NSError *underlyingError = (__bridge NSError *)error;
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"Could not understand format of the signature data %@", dsaSignature];
            if (underlyingError != NULL) {
                userInfo[NSUnderlyingErrorKey] = underlyingError;
            }
            
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:[userInfo copy]];
        }
        
        return cleanup();
    }
#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SecTransformConnectTransforms(dataReadTransform, kSecTransformOutputAttributeName, dataDigestTransform, kSecTransformInputAttributeName, group, &error);
#pragma clang diagnostic pop
    if (error) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{NSLocalizedDescriptionKey : @"Failed to connect data read transform", NSUnderlyingErrorKey: (__bridge NSError *)error}];
        }
        
        return cleanup();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SecTransformConnectTransforms(dataDigestTransform, kSecTransformOutputAttributeName, dataVerifyTransform, kSecTransformInputAttributeName, group, &error);
#pragma clang diagnostic pop
    if (error) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{NSLocalizedDescriptionKey : @"Failed to connect data digest transform", NSUnderlyingErrorKey: (__bridge NSError *)error}];
        }
        
        return cleanup();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSNumber *result = CFBridgingRelease(SecTransformExecute(group, &error));
#pragma clang diagnostic pop
    if (error) {
        SULog(SULogLevelError, @"DSA signature verification failed: %@", error);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"DSA signature verification failed", NSUnderlyingErrorKey: (__bridge NSError *)error}];
        }
        
        return cleanup();
    }

    if (!result.boolValue) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"DSA signature does not match. Data of the update file being checked is different than data that has been signed, or the public key and the private key are not from the same set"}];
        }
    }

    cleanup();
    return result.boolValue;
}
#endif

@end
