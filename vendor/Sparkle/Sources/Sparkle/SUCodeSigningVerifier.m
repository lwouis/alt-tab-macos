//
//  SUCodeSigningVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 7/5/12.
//
//

#include <Security/CodeSigning.h>
#include <Security/SecCode.h>
#import "SUCodeSigningVerifier.h"
#import "SULog.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@interface NSXPCConnection (Private)

@property (nonatomic, readonly) audit_token_t auditToken;

@end

@implementation SUCodeSigningVerifier

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)newBundleURL andMatchesSignatureAtBundleURL:(NSURL *)oldBundleURL error:(NSError * __autoreleasing *)error
{
    OSStatus result;
    SecRequirementRef requirement = NULL;
    SecStaticCodeRef staticCode = NULL;
    SecStaticCodeRef oldCode = NULL;
    CFErrorRef cfError = NULL;

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)oldBundleURL, kSecCSDefaultFlags, &oldCode);
    if (result != noErr) {
        if (error != NULL) {
            NSString *errorMessage =
                (result == errSecCSUnsigned) ?
                [NSString stringWithFormat:@"Bundle is not code signed: %@", oldBundleURL.path] :
                [NSString stringWithFormat:@"Failed to get static code (%d): %@", result, oldBundleURL.path];
        
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
        }
        
        goto finally;
    }

    result = SecCodeCopyDesignatedRequirement(oldCode, kSecCSDefaultFlags, &requirement);
    if (result != noErr) {
        NSString *message = [NSString stringWithFormat:@"Failed to copy designated requirement. Code Signing OSStatus code: %d", result];
        SULog(SULogLevelError, @"%@", message);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        
        goto finally;
    }

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)newBundleURL, kSecCSDefaultFlags, &staticCode);
    if (result != noErr) {
        NSString *message = [NSString stringWithFormat:@"Failed to get static code %d", result];
        
        SULog(SULogLevelError, @"%@", message);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        
        goto finally;
    }
    
    // Note that kSecCSCheckNestedCode may not work with pre-Mavericks code signing.
    // See https://github.com/sparkle-project/Sparkle/issues/376#issuecomment-48824267 and https://developer.apple.com/library/mac/technotes/tn2206
    // Additionally, there are several reasons to stay away from deep verification and to prefer EdDSA signing the download archive instead.
    // See https://github.com/sparkle-project/Sparkle/pull/523#commitcomment-17549302 and https://github.com/sparkle-project/Sparkle/issues/543
    result = SecStaticCodeCheckValidityWithErrors(staticCode, kSecCSCheckAllArchitectures, requirement, &cfError);
    
    if (result != errSecSuccess) {
        NSError *underlyingError;
        if (cfError != NULL) {
            NSError *tmpError = CFBridgingRelease(cfError);
            underlyingError = tmpError;
        } else {
            underlyingError = nil;
        }
        
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        if (underlyingError != nil) {
            userInfo[NSUnderlyingErrorKey] = underlyingError;
        }
        
        if (result == errSecCSUnsigned) {
            NSString *message = @"The host app is signed, but the new version of the app is not signed using Apple Code Signing. Please ensure that the new app is signed and that archiving did not corrupt the signature.";
            
            SULog(SULogLevelError, @"%@", message);
            
            if (error != NULL) {
                userInfo[NSLocalizedDescriptionKey] = message;
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        } else if (result == errSecCSReqFailed) {
            CFStringRef requirementString = nil;
            NSString *initialMessage;
            if (SecRequirementCopyString(requirement, kSecCSDefaultFlags, &requirementString) == noErr) {
                initialMessage = [NSString stringWithFormat:@"Code signature of the new version doesn't match the old version: %@. Please ensure that old and new app is signed using exactly the same certificate.", requirementString];
                
                SULog(SULogLevelError, @"%@", initialMessage);
                CFRelease(requirementString);
            } else {
                initialMessage = @"Code signature of new version doesn't match the old version. Please ensure that old and new app is signed using exactly the same certificate.";
            }
            
            NSDictionary *oldInfo = [self logSigningInfoForCode:oldCode label:@"old info"];
            NSDictionary *newInfo = [self logSigningInfoForCode:staticCode label:@"new info"];
            
            if (error != NULL) {
                userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"%@ old info: %@. new info: %@", initialMessage, oldInfo, newInfo];
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        } else {
            if (error != NULL) {
                userInfo[NSLocalizedDescriptionKey] = @"Error: Old app bundle code signing signature failed to match new bundle code signature";
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        }
    }
    
finally:
    if (oldCode) CFRelease(oldCode);
    if (staticCode) CFRelease(staticCode);
    if (requirement) CFRelease(requirement);
    return (result == noErr);
}

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL error:(NSError *__autoreleasing *)error
{
    return [self codeSignatureIsValidAtBundleURL:bundleURL checkNestedCode:NO error:error];
}

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL checkNestedCode:(BOOL)checkNestedCode error:(NSError *__autoreleasing *)error
{
    OSStatus result;
    SecStaticCodeRef staticCode = NULL;
    CFErrorRef cfError = NULL;
    // See also code further below where kSecCSCheckNestedCode may be added
    SecCSFlags flags = kSecCSCheckAllArchitectures;
    
    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)bundleURL, kSecCSDefaultFlags, &staticCode);
    if (result != noErr) {
        SULog(SULogLevelError, @"Failed to get static code %d", result);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to get static code for verifying code signature: %d", result] }];
        }
        
        goto finally;
    }

    // See in -codeSignatureIsValidAtBundleURL:andMatchesSignatureAtBundleURL:error: for why kSecCSCheckNestedCode is not always passed
    if (checkNestedCode) {
        flags |= kSecCSCheckNestedCode;
    }
    
    result = SecStaticCodeCheckValidityWithErrors(staticCode, flags, NULL, &cfError);
    
    if (result != errSecSuccess) {
        NSError *underlyingError;
        if (cfError != NULL) {
            NSError *tmpError = CFBridgingRelease(cfError);
            underlyingError = tmpError;
        } else {
            underlyingError = nil;
        }
        
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        if (underlyingError != nil) {
            userInfo[NSUnderlyingErrorKey] = underlyingError;
        }
        
        if (result == errSecCSUnsigned) {
            NSString *message = [NSString stringWithFormat:@"Error: The app is not signed using Apple Code Signing. %@", bundleURL];
            SULog(SULogLevelError, @"%@", message);
            
            if (error != NULL) {
                userInfo[NSLocalizedDescriptionKey] = message;
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        } else if (result == errSecCSReqFailed) {
            if (error != NULL) {
                NSDictionary *newInfo = [self logSigningInfoForCode:staticCode label:@"new info"];
                
                NSString *message = [NSString stringWithFormat:@"Error: The app failed Apple Code Signing checks: %@ - new info: %@", bundleURL, newInfo];
                
                userInfo[NSLocalizedDescriptionKey] = message;
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        } else {
            if (error != NULL) {
                NSString *message = [NSString stringWithFormat:@"Error: The app failed Apple Code Signing checks: %@", bundleURL];
                
                userInfo[NSLocalizedDescriptionKey] = message;
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        }
    }
    
finally:
    if (staticCode) CFRelease(staticCode);
    return (result == noErr);
}

static id valueOrNSNull(id value) {
    return value ? value : [NSNull null];
}

+ (NSDictionary *)codeSignatureInfoForCode:(SecStaticCodeRef)code SPU_OBJC_DIRECT
{
    CFDictionaryRef signingInfo = nil;
    const SecCSFlags flags = (SecCSFlags) (kSecCSSigningInformation | kSecCSRequirementInformation | kSecCSDynamicInformation | kSecCSContentInformation);
    if (SecCodeCopySigningInformation(code, flags, &signingInfo) == noErr) {
        NSDictionary *signingDict = CFBridgingRelease(signingInfo);
        NSMutableDictionary *relevantInfo = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"format", @"identifier", @"requirements", @"teamid", @"signing-time"]) {
            [relevantInfo setObject:valueOrNSNull([signingDict objectForKey:key]) forKey:key];
        }
        NSDictionary *infoPlist = [signingDict objectForKey:@"info-plist"];
        [relevantInfo setObject:valueOrNSNull([infoPlist objectForKey:@"CFBundleShortVersionString"]) forKey:@"version"];
        [relevantInfo setObject:valueOrNSNull([infoPlist objectForKey:(__bridge NSString *)kCFBundleVersionKey]) forKey:@"build"];
        return [relevantInfo copy];
    }
    return nil;
}

+ (NSDictionary *)logSigningInfoForCode:(SecStaticCodeRef)code label:(NSString*)label SPU_OBJC_DIRECT
{
    NSDictionary *relevantInfo = [self codeSignatureInfoForCode:code];
    SULog(SULogLevelDefault, @"%@: %@", label, relevantInfo);
    return relevantInfo;
}

+ (BOOL)bundleAtURLIsCodeSigned:(NSURL *)bundleURL
{
    OSStatus result;
    SecStaticCodeRef staticCode = NULL;

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)bundleURL, kSecCSDefaultFlags, &staticCode);
    if (result == errSecCSUnsigned) {
        return NO;
    }

    SecRequirementRef requirement = NULL;
    result = SecCodeCopyDesignatedRequirement(staticCode, kSecCSDefaultFlags, &requirement);
    if (staticCode) {
        CFRelease(staticCode);
    }
    if (requirement) {
        CFRelease(requirement);
    }
    if (result == errSecCSUnsigned) {
        return NO;
    }
    return (result == 0);
}

static NSString * _Nullable SUTeamIdentifierFromCode(SecStaticCodeRef staticCode)
{
    CFDictionaryRef cfSigningInformation = NULL;
    OSStatus copySigningInfoCode = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation,
        &cfSigningInformation);
    
    NSDictionary *signingInformation = CFBridgingRelease(cfSigningInformation);
    
    if (copySigningInfoCode != noErr) {
        SULog(SULogLevelError, @"Failed to get signing information for retrieving team identifier: %d", copySigningInfoCode);
        return nil;
    }
    
    // Note this will return nil for ad-hoc or unsigned binaries
    return signingInformation[(NSString *)kSecCodeInfoTeamIdentifier];
}

+ (NSString * _Nullable)teamIdentifierAtURL:(NSURL *)url
{
    SecStaticCodeRef staticCode = NULL;
    OSStatus staticCodeResult = SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &staticCode);
    if (staticCodeResult != errSecSuccess) {
        SULog(SULogLevelError, @"Failed to get static code for retrieving team identifier: %d", staticCodeResult);
        return nil;
    }
    
    NSString *teamIdentifier = SUTeamIdentifierFromCode(staticCode);
    
    if (staticCode != NULL) {
        CFRelease(staticCode);
    }
    
    return teamIdentifier;
}

+ (NSString * _Nullable)teamIdentifierFromMainExecutable
{
    SecCodeRef code = NULL;
    OSStatus result = SecCodeCopySelf(kSecCSDefaultFlags, &code);
    if (result != errSecSuccess) {
        SULog(SULogLevelError, @"Failed to get code for retrieving team identifier of main executable: %d", result);
        return nil;
    }
    
    NSString *teamIdentifier = SUTeamIdentifierFromCode(code);
    
    CFRelease(code);
    
    return teamIdentifier;
}

+ (BOOL)codeSignatureIsValidAtDownloadURL:(NSURL *)downloadURL andMatchesDeveloperIDTeamFromOldBundleURL:(NSURL *)oldBundleURL error:(NSError * __autoreleasing *)error
{
    NSString *teamIdentifier = nil;
    NSString *requirementString = nil;
    SecRequirementRef requirement = NULL;
    SecStaticCodeRef oldStaticCode = NULL;
    SecStaticCodeRef downloadStaticCode = NULL;
    OSStatus result;
    
    NSError *resultError = nil;
    CFErrorRef cfError = NULL;
    
    NSString *commonErrorMessage = @"The download archive cannot be validated with Apple Developer ID code signing as fallback (after (Ed)DSA verification has failed)";
    
    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)oldBundleURL, kSecCSDefaultFlags, &oldStaticCode);
    if (result != errSecSuccess) {
        NSString *errorMessage =
            (result == errSecCSUnsigned) ?
            [NSString stringWithFormat:@"%@. The original app is not code signed: %@", commonErrorMessage, oldBundleURL.path] :
            [NSString stringWithFormat:@"%@. The static code could not be retrieved from the original app (%d): %@", commonErrorMessage, result, oldBundleURL.path];
        
        resultError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
        
        goto finally;
    }
    
    teamIdentifier = SUTeamIdentifierFromCode(oldStaticCode);
    if (teamIdentifier == nil) {
        resultError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@. The team identifier could not be retrieved from the original app: %@", commonErrorMessage, oldBundleURL.path] }];
        
        goto finally;
    }
    
    // Create a designated requirement with developer ID signing with this team ID
    // Validate it against code signing check of this archive
    // CertificateIssuedByApple = anchor apple generic
    // IssuerIsDeveloperID = certificate 1[field.1.2.840.113635.100.6.2.6]
    // LeafIsDeveloperIDApp = certificate leaf[field.1.2.840.113635.100.6.1.13]
    // DeveloperIDTeamID = certificate leaf[subject.OU]
    // https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements#Xcode-designated-requirement-for-Developer-ID-code
    requirementString = [NSString stringWithFormat:@"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"%@\"", teamIdentifier];
    
    result = SecRequirementCreateWithString((__bridge CFStringRef)requirementString, kSecCSDefaultFlags, &requirement);
    if (result != errSecSuccess) {
        resultError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@. The designated requirement string with a Developer ID requirement with team identifier '%@' could not be created with error %d", commonErrorMessage, teamIdentifier, result] }];
        
        goto finally;
    }
    
    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)downloadURL, kSecCSDefaultFlags, &downloadStaticCode);
    if (result != errSecSuccess) {
        NSString *message = [NSString stringWithFormat:@"%@. The static code could not be retrieved from the download archive with error %d. The download archive may not be Apple code signed.", commonErrorMessage, result];
        
        SULog(SULogLevelError, @"%@", message);
        
        resultError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: message }];
        
        goto finally;
    }
    
    result = SecStaticCodeCheckValidityWithErrors(downloadStaticCode, kSecCSDefaultFlags, requirement, &cfError);
    if (result != errSecSuccess) {
        NSError *underlyingError;
        if (cfError != NULL) {
            NSError *tmpError = CFBridgingRelease(cfError);
            underlyingError = tmpError;
        } else {
            underlyingError = nil;
        }
        
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        if (underlyingError != nil) {
            userInfo[NSUnderlyingErrorKey] = underlyingError;
        }
        
        if (result == errSecCSUnsigned) {
            NSString *message = [NSString stringWithFormat:@"%@. The download archive is not Apple code signed.", commonErrorMessage];
            
            SULog(SULogLevelError, @"%@", message);
            
            userInfo[NSLocalizedDescriptionKey] = message;
            
            resultError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
        } else if (result == errSecCSReqFailed) {
            NSString *initialMessage = [NSString stringWithFormat:@"%@. The Apple code signature of new downloaded archive is either not Developer ID code signed, or doesn't have a Team ID that matches the old app version (%@). Please ensure that the archive and app are signed using the same Developer ID certificate.", commonErrorMessage, teamIdentifier];
            
            NSDictionary *oldInfo = [self logSigningInfoForCode:oldStaticCode label:@"old info"];
            NSDictionary *newInfo = [self logSigningInfoForCode:downloadStaticCode label:@"new info"];
            
            userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"%@ old info: %@. new info: %@", initialMessage, oldInfo, newInfo];
            
            resultError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
        } else {
            userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"%@. The downloaded archive code signing signature failed to validate with an unknown error (%d).", commonErrorMessage, result];
            
            resultError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
        }
        
        goto finally;
    }
    
finally:
    
    if (oldStaticCode != NULL) {
        CFRelease(oldStaticCode);
    }
    
    if (requirement != NULL) {
        CFRelease(requirement);
    }
    
    if (downloadStaticCode != NULL) {
        CFRelease(downloadStaticCode);
    }
    
    if (resultError != nil && error != NULL) {
        *error = resultError;
    }
    
    return (resultError == nil);
}

+ (SUValidateConnectionStatus)validateConnection:(NSXPCConnection *)connection error:(NSError * __autoreleasing *)error
{
    // Check if code signing requirement is required
    NSString *hostTeamIdentifier = [self teamIdentifierFromMainExecutable];
    if (hostTeamIdentifier == nil) {
        return SUValidateConnectionStatusSetNoRequirementSuccess;
    }
    
    // Build the default team ID signing requirement
    NSString *codeSigningRequirement = [NSString stringWithFormat:@"(anchor apple generic and certificate leaf[subject.OU] = \"%@\")", hostTeamIdentifier];
    
    if (@available(macOS 13.0, *)) {
        [connection setCodeSigningRequirement:codeSigningRequirement];
        
        return SUValidateConnectionStatusSetCodeSigningRequirementSuccess;
    }
    
    // Fall back to audit token on older OS's
    if ([connection respondsToSelector:@selector(auditToken)]) {
        audit_token_t auditToken = [connection auditToken];
        NSData *auditTokenData = [NSData dataWithBytes:&auditToken length:sizeof(auditToken)];
        
        NSDictionary *attributes = @{
            (NSString *)kSecGuestAttributeAudit: auditTokenData
        };
        
        SecCodeRef code = NULL;
        OSStatus result = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef _Nullable)(attributes), kSecCSDefaultFlags, &code);
        if (result != errSecSuccess) {
            CFRelease(code);
            
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The client connection could not be validated because SecCodeCopyGuestWithAttributes() failed with error %d", result] }];
            }
            
            return SUValidateConnectionStatusAPIFailure;
        }
        
        // Check if the client is code signed with our signing requirement
        
        SecRequirementRef requirement = NULL;
        result = SecRequirementCreateWithString((__bridge CFStringRef)codeSigningRequirement, kSecCSDefaultFlags, &requirement);
        
        if (result != errSecSuccess) {
            CFRelease(code);
            
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The client connection could not be validated because SecRequirementCreateWithString() failed with error %d", result] }];
            }
            
            return SUValidateConnectionStatusAPIFailure;
        }
        
        CFErrorRef cfError = NULL;
        // This is not a static code, so we don't pass kSecCSCheckAllArchitectures
        result = SecCodeCheckValidityWithErrors(code, kSecCSDefaultFlags, requirement, &cfError);
        
        CFRelease(requirement);
        requirement = NULL;
        
        if (result != errSecSuccess) {
            NSError *cfBridgedError = (NSError *)CFBridgingRelease(cfError);
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The client connection could not be validated because validating the code signature failed with error %d (%@). Does the app meet the designated requirement: %@", result, cfBridgedError.localizedDescription, codeSigningRequirement] }];
            }
            
            [self logSigningInfoForCode:code label:@"Client"];
            
            CFRelease(code);
            
            return SUValidateConnectionStatusCodeSigningRequirementFailure;
        }
        
        CFRelease(code);
        
        return SUValidateConnectionStatusSetCodeSigningRequirementSuccess;
    }
    
    // Not much we can do if auditToken is not supported. This code should not be reached though.
    return SUValidateConectionNoSupportedValidationMethodFailure;
}

@end
