//
//  SUSignatures.h
//  Sparkle
//
//  Created by Kornel on 15/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, SUSigningInputStatus) {
    /// An input was not provided at all.
    SUSigningInputStatusAbsent = 0,

    /// An input was provided, but did not have the correct format.
    SUSigningInputStatusInvalid,

    /// An input was provided and can be used for verifying signing information.
    SUSigningInputStatusPresent,
    SUSigningInputStatusLastValidCase = SUSigningInputStatusPresent
};

#ifndef BUILDING_SPARKLE_TESTS
#define SUSignaturesDefinitionAttribute SPU_OBJC_DIRECT_MEMBERS
#else
#define SUSignaturesDefinitionAttribute __attribute__((objc_runtime_name("SUTestSignatures")))
#endif

SUSignaturesDefinitionAttribute
@interface SUSignatures : NSObject <NSSecureCoding>
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
@property (nonatomic, readonly, nullable) NSData *dsaSignature;
@property (nonatomic, readonly) SUSigningInputStatus dsaSignatureStatus;
#endif

@property (nonatomic, readonly, nullable) const unsigned char *ed25519Signature;
@property (nonatomic, readonly) SUSigningInputStatus ed25519SignatureStatus;

- (instancetype)initWithEd:(NSString * _Nullable)ed
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                       dsa:(NSString * _Nullable)dsa
#endif
;
@end

#ifndef BUILDING_SPARKLE_TESTS
#define SUPublicKeysDefinitionAttribute SPU_OBJC_DIRECT_MEMBERS
#else
#define SUPublicKeysDefinitionAttribute __attribute__((objc_runtime_name("SUTestPublicKeys")))
#endif

SUPublicKeysDefinitionAttribute
@interface SUPublicKeys : NSObject

@property (nonatomic, readonly, nullable) NSString *dsaPubKey;
@property (nonatomic, readonly) SUSigningInputStatus dsaPubKeyStatus;

@property (nonatomic, readonly, nullable) const unsigned char *ed25519PubKey;
@property (nonatomic, readonly) SUSigningInputStatus ed25519PubKeyStatus;

/// Returns YES if either key is present (though they may be invalid).
@property (nonatomic, readonly) BOOL hasAnyKeys;

- (instancetype)initWithEd:(NSString * _Nullable)ed
                       dsa:(NSString * _Nullable)dsa;

@end

NS_ASSUME_NONNULL_END
