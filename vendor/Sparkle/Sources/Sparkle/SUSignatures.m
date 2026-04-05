//
//  SUSignatures.m
//  Sparkle
//
//  Created by Kornel on 15/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

#import "SUSignatures.h"
#import <assert.h>
#import "SULog.h"


#include "AppKitPrevention.h"

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
static NSString *SUDSASignatureKey = @"SUDSASignature";
static NSString *SUDSASignatureStatusKey = @"SUDSASignatureStatus";
#endif
static NSString *SUEDSignatureKey = @"SUEDSignature";
static NSString *SUEDSignatureStatusKey = @"SUEDSignatureStatus";

@implementation SUSignatures
{
    unsigned char _ed25519_signature[64];
}

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
@synthesize dsaSignature = _dsaSignature;
@synthesize dsaSignatureStatus = _dsaSignatureStatus;
#endif
@synthesize ed25519SignatureStatus = _ed25519SignatureStatus;

static SUSigningInputStatus decode(NSString *str, NSData * __strong *outData) {
    if (str == nil) {
        return SUSigningInputStatusAbsent;
    }

    NSString *stripped = [str stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSData *result = [[NSData alloc] initWithBase64EncodedString:stripped options:(NSDataBase64DecodingOptions)0];
    if (!result) {
        return SUSigningInputStatusInvalid;
    }
    *outData = result;
    return SUSigningInputStatusPresent;
}

- (instancetype)initWithEd:(NSString * _Nullable)maybeEd25519
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                       dsa:(NSString * _Nullable)maybeDsa
#endif
{
    self = [super init];
    if (self) {
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
        _dsaSignatureStatus = decode(maybeDsa, &_dsaSignature);
        if (_dsaSignatureStatus == SUSigningInputStatusInvalid) {
            SULog(SULogLevelError, @"The provided DSA signature could not be decoded.");
        }
#endif
        if (maybeEd25519 != nil) {
            NSData *data = nil;
            _ed25519SignatureStatus = decode(maybeEd25519, &data);
            if (data) {
                if ([data length] == sizeof(_ed25519_signature)) {
                    [data getBytes:_ed25519_signature length:sizeof(_ed25519_signature)];
                } else {
                    _ed25519SignatureStatus = SUSigningInputStatusInvalid;
                }
            }

            if (_ed25519SignatureStatus == SUSigningInputStatusInvalid) {
                SULog(SULogLevelError, @"The provided EdDSA signature could not be decoded.");
            }
        }
    }
    return self;
}

- (const unsigned char *)ed25519Signature {
    if (_ed25519SignatureStatus == SUSigningInputStatusPresent) {
        return _ed25519_signature;
    }
    return NULL;
}

static BOOL decodeStatus(NSCoder *decoder, NSString *key, SUSigningInputStatus *outStatus) {
    NSInteger rawValue = [decoder decodeIntegerForKey:key];
    if (rawValue > SUSigningInputStatusLastValidCase) {
        return NO;
    }
    *outStatus = (SUSigningInputStatus)rawValue;
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (self) {
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
        if (!decodeStatus(decoder, SUDSASignatureStatusKey, &_dsaSignatureStatus)) {
            return nil;
        }

        NSData *dsaSignature = [decoder decodeObjectOfClass:[NSData class] forKey:SUDSASignatureKey];
        if (dsaSignature) {
            _dsaSignature = dsaSignature;
        }
#endif

        if (!decodeStatus(decoder, SUEDSignatureStatusKey, &_ed25519SignatureStatus)) {
            return nil;
        }

        NSData *edSignature = [decoder decodeObjectOfClass:[NSData class] forKey:SUEDSignatureKey];
        if (edSignature) {
            if (edSignature.length != sizeof(_ed25519_signature)) {
                return nil;
            }
            [edSignature getBytes:_ed25519_signature length:sizeof(_ed25519_signature)];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
    [coder encodeInteger:_dsaSignatureStatus forKey:SUDSASignatureStatusKey];
    if (_dsaSignature) {
        [coder encodeObject:_dsaSignature forKey:SUDSASignatureKey];
    }
#endif
    [coder encodeInteger:_ed25519SignatureStatus forKey:SUEDSignatureStatusKey];
    if ([self ed25519Signature] != NULL) {
        NSData *edSignature = [NSData dataWithBytesNoCopy:&_ed25519_signature length:sizeof(_ed25519_signature) freeWhenDone:false];
        [coder encodeObject:edSignature forKey:SUEDSignatureKey];
    }
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@implementation SUPublicKeys
{
    unsigned char _ed25519_public_key[32];
}

@synthesize dsaPubKey = _dsaPubKey;
@synthesize ed25519PubKeyStatus = _ed25519PubKeyStatus;

- (instancetype)initWithEd:(NSString * _Nullable)maybeEd25519
                       dsa:(NSString * _Nullable)maybeDsa
{
    self = [super init];
    if (self) {
        _dsaPubKey = maybeDsa;
        if (maybeEd25519 != nil) {
            NSData *ed = nil;
            _ed25519PubKeyStatus = decode(maybeEd25519, &ed);
            if (ed) {
                if ([ed length] == sizeof(_ed25519_public_key)) {
                    [ed getBytes:_ed25519_public_key length:sizeof(_ed25519_public_key)];
                } else {
                    _ed25519PubKeyStatus = SUSigningInputStatusInvalid;
                }
            }

            if (_ed25519PubKeyStatus == SUSigningInputStatusInvalid) {
                SULog(SULogLevelError, @"The provided EdDSA key could not be decoded.");
            }
        }
    }
    return self;
}

- (SUSigningInputStatus)dsaPubKeyStatus {
    // We don't currently do any prevalidation of DSA public keys,
    // so this is always going to be "present" or "absent".
    return (_dsaPubKey != nil) ? SUSigningInputStatusPresent : SUSigningInputStatusAbsent;
}

- (const unsigned char *)ed25519PubKey {
    if (_ed25519PubKeyStatus == SUSigningInputStatusPresent) {
        return _ed25519_public_key;
    }
    return NULL;
}

- (BOOL)hasAnyKeys {
    return (_ed25519PubKeyStatus != SUSigningInputStatusAbsent) ||
            ([self dsaPubKeyStatus] != SUSigningInputStatusAbsent);
}

@end
