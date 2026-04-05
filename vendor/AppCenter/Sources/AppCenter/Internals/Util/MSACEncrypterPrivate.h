// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <CommonCrypto/CommonCryptor.h>
#import <Foundation/Foundation.h>

#import "MSACEncrypter.h"

NS_ASSUME_NONNULL_BEGIN

static int const kMSACEncryptionAlgorithm = kCCAlgorithmAES;
static NSString *const kMSACEncryptionAlgorithmName = @"AES";
static NSString *const kMSACEncryptionCipherMode = @"CBC";
static NSString *const kMSACEncryptionAlgorithmAesAndEtmName = @"AES/HmacSHA256";
static const int kMSACEncryptionSubkeyLength = 32;
static const int kMSACAuthenticationSubkeyLength = 16;

// One year.
static NSTimeInterval const kMSACEncryptionKeyLifetimeInSeconds = 365 * 24 * 60 * 60;
static int const kMSACEncryptionKeySize = kCCKeySizeAES256;
static NSString *const kMSACEncryptionKeyMetadataKey = @"EncryptionKeyMetadata";
static NSString *const kMSACEncryptionKeyTagAlternate = @"kMSEncryptionKeyTagAlternate";
static NSString *const kMSACEncryptionKeyTagOriginal = @"kMSEncryptionKeyTag";

// This separator is used for key metadata, as well as between metadata that is prepended to the cipher text.
static NSString *const kMSACEncryptionMetadataInternalSeparator = @"/";

// This separator is only used between the metadata and cipher text of the encryption result.
static NSString *const kMSACEncryptionMetadataSeparator = @":";
static NSString *const kMSACEncryptionPaddingMode = @"PKCS7";

@interface MSACEncrypter ()

@end

NS_ASSUME_NONNULL_END
