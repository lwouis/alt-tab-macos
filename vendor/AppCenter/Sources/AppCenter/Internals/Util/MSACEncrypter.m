// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "CommonCrypto/CommonHMAC.h"
#import <CommonCrypto/CommonCryptor.h>

#import "MSACAppCenterInternal.h"
#import "MSACConstants+Internal.h"
#import "MSACEncrypterPrivate.h"
#import "MSACKeychainUtil.h"
#import "MSACLogger.h"

static NSObject *const classLock;

@interface MSACEncrypter ()

@property(atomic) NSData *originalKeyData;
@property(atomic) NSData *alternateKeyData;

@end

@implementation MSACEncrypter

- (NSString *_Nullable)encryptString:(NSString *)string {
  NSData *dataToEncrypt = [string dataUsingEncoding:NSUTF8StringEncoding];
  NSData *encryptedData = [self encryptData:dataToEncrypt];
  return [encryptedData base64EncodedStringWithOptions:0];
}

- (NSData *_Nullable)encryptData:(NSData *)data {
  NSString *keyTag = [MSACEncrypter getCurrentKeyTag];
  NSData *secretKey = [self getKeyWithKeyTag:keyTag];

  // Get subkeys.
  NSData *encryptionSubkey = [self getSubkey:secretKey outputSize:kMSACEncryptionSubkeyLength];
  NSData *authenticationSubkey = [self getSubkey:secretKey outputSize:kMSACAuthenticationSubkeyLength];

  // Encrypt data.
  NSData *initializationVector = [MSACEncrypter generateInitializationVector];
  NSData *encryptData = [MSACEncrypter performCryptoOperation:kCCEncrypt
                                                        input:data
                                         initializationVector:initializationVector
                                                          key:encryptionSubkey];

  // Calculate hMac.
  NSData *hMac = [self getMacBytes:authenticationSubkey keySize:encryptData];

  // Calculate metadata.
  NSData *metadata = [MSACEncrypter getMetadataStringWithKeyTag:keyTag encryptionAlgorithmName:kMSACEncryptionAlgorithmAesAndEtmName];

  // Build encrypted data.
  NSMutableData *mutableData = [NSMutableData new];
  [mutableData appendData:metadata];
  [mutableData appendBytes:(const void *)[kMSACEncryptionMetadataSeparator UTF8String] length:1];
  [mutableData appendData:initializationVector];
  [mutableData appendData:hMac];
  [mutableData appendData:encryptData];
  encryptData = mutableData;
  return encryptData;
}

- (NSString *_Nullable)decryptString:(NSString *)string {
  NSString *result = nil;
  NSData *dataToDecrypt = [[NSData alloc] initWithBase64EncodedString:string options:0];
  if (dataToDecrypt) {
    NSData *decryptedBytes = [self decryptData:dataToDecrypt];
    result = [[NSString alloc] initWithData:decryptedBytes encoding:NSUTF8StringEncoding];
    if (!result) {
      MSACLogWarning([MSACAppCenter logTag], @"Converting decrypted NSData to NSString failed.");
    }
  } else {
    MSACLogWarning([MSACAppCenter logTag], @"Conversion of encrypted string to NSData failed.");
  }
  return result;
}

- (NSData *_Nullable)decryptData:(NSData *)data {
  NSData *secretKey;
    
  // Load metadata.
  size_t metadataLocation = [self loadMetadataLocation:data];
  NSString *metadata = [self loadMetadata:data metadataLocation:metadataLocation];
  NSString *keyTag = [metadata componentsSeparatedByString:kMSACEncryptionMetadataInternalSeparator][0];

  // Load data.
  NSData *initializationVector;
  NSData *cipherText;
  NSData *hMac;
  if (metadata) {
      
    // Get secret key.
    NSData *key = [self getKeyWithKeyTag:keyTag];
    NSRange ivRange = NSMakeRange(metadataLocation + 1, kCCBlockSizeAES128);
    if ([self hasOldMetadata:metadata keyTag:keyTag]) {
      secretKey = key;

      // Metadata, separator, and initialization vector.
      size_t cipherTextPrefixLength = metadataLocation + 1 + kCCBlockSizeAES128;
      NSRange cipherTextRange = NSMakeRange(cipherTextPrefixLength, [data length] - cipherTextPrefixLength);
      initializationVector = [data subdataWithRange:ivRange];
      cipherText = [data subdataWithRange:cipherTextRange];
    } else {

      // Get subkeys.
      secretKey = [self getSubkey:key outputSize:kMSACEncryptionSubkeyLength];
      NSData *authenticationSubkey = [self getSubkey:key outputSize:kMSACAuthenticationSubkeyLength];

      // Metadata, separator, initialization vector, MAC, cipher text.
      NSRange hMacRange = NSMakeRange(metadataLocation + 1 + kCCBlockSizeAES128, kCCKeySizeAES256);
      size_t cipherTextPrefixLength = metadataLocation + 1 + kCCBlockSizeAES128 + kCCKeySizeAES256;
      NSRange cipherTextRange = NSMakeRange(cipherTextPrefixLength, [data length] - cipherTextPrefixLength);
      initializationVector = [data subdataWithRange:ivRange];
      hMac = [data subdataWithRange:hMacRange];
      cipherText = [data subdataWithRange:cipherTextRange];

      // Calculate hMac.
      NSData *expectedMac = [self getMacBytes:authenticationSubkey keySize:cipherText];
      if (![expectedMac isEqual:hMac]) {
        NSException *macAuthenticateException = [NSException exceptionWithName:@"Authenticate MAC exception."
                                                                        reason:@"Could not authenticate MAC value."
                                                                      userInfo:nil];
        @throw macAuthenticateException;
      }
    }
  } else {

    // If there is no metadata, this is old data, so use the old key and an empty initialization vector.
    secretKey = [self getKeyWithKeyTag:kMSACEncryptionKeyTagOriginal];
    cipherText = data;
  }
  return [MSACEncrypter performCryptoOperation:kCCDecrypt input:cipherText initializationVector:initializationVector key:secretKey];
}

- (BOOL)hasOldMetadata:(NSString *)metadata keyTag:(NSString *)keyTag {
  NSString *oldMetadata = [[NSString alloc] initWithData:[MSACEncrypter getMetadataStringWithKeyTag:keyTag] encoding:NSUTF8StringEncoding];
  return [metadata isEqual:oldMetadata];
}

- (size_t)loadMetadataLocation:(NSData *)data {
  NSRange dataRange = NSMakeRange(0, [data length]);
  NSData *separatorAsData = [kMSACEncryptionMetadataSeparator dataUsingEncoding:NSUTF8StringEncoding];
  return [data rangeOfData:separatorAsData options:0 range:dataRange].location;
}

- (NSString *)loadMetadata:(NSData *)data metadataLocation:(size_t)metadataLocation {

  // Load metadata.
  NSString *metadata;
  if (metadataLocation != NSNotFound) {
    NSData *subdata = [data subdataWithRange:NSMakeRange(0, metadataLocation)];
    metadata = [[NSString alloc] initWithData:subdata encoding:NSUTF8StringEncoding];
  }
  return metadata;
}

+ (NSString *)getCurrentKeyTag {
  @synchronized(classLock) {
    NSString *keyMetadata = [MSAC_APP_CENTER_USER_DEFAULTS objectForKey:kMSACEncryptionKeyMetadataKey];
    if (!keyMetadata) {
      [self rotateToNewKeyTag:kMSACEncryptionKeyTagAlternate];
      return kMSACEncryptionKeyTagAlternate;
    }

    // Format is {keyTag}/{expiration as iso}.
    NSArray *keyMetadataComponents = [keyMetadata componentsSeparatedByString:kMSACEncryptionMetadataInternalSeparator];
    NSString *keyTag = keyMetadataComponents[0];
    NSString *expirationIso = keyMetadataComponents[1];
    NSDate *expiration = [MSACUtility dateFromISO8601:expirationIso];
    BOOL isNotExpired = [[expiration laterDate:[NSDate date]] isEqualToDate:expiration];
    if (isNotExpired) {
      return keyTag;
    }

    // Key is expired and must be rotated.
    if ([keyTag isEqualToString:kMSACEncryptionKeyTagOriginal]) {
      keyTag = kMSACEncryptionKeyTagAlternate;
    } else {
      keyTag = kMSACEncryptionKeyTagOriginal;
    }
    [self rotateToNewKeyTag:keyTag];
    return keyTag;
  }
}

+ (void)rotateToNewKeyTag:(NSString *)newKeyTag {
  NSDate *expiration = [[NSDate date] dateByAddingTimeInterval:kMSACEncryptionKeyLifetimeInSeconds];
  NSString *expirationIso = [MSACUtility dateToISO8601:expiration];

  // Format is {keyTag}/{expiration as iso}.
  NSString *keyMetadata = [@[ newKeyTag, expirationIso ] componentsJoinedByString:kMSACEncryptionMetadataInternalSeparator];
  [MSAC_APP_CENTER_USER_DEFAULTS setObject:keyMetadata forKey:kMSACEncryptionKeyMetadataKey];
}

- (NSData *)getKeyWithKeyTag:(NSString *)keyTag {
  NSData *keyData;
  BOOL isOriginalKeyTag = [keyTag isEqualToString:kMSACEncryptionKeyTagOriginal];
  keyData = isOriginalKeyTag ? self.originalKeyData : self.alternateKeyData;

  // Key was found in memory.
  if (keyData) {
    return keyData;
  }

  // If key is not in memory; try loading it from Keychain.
  NSString *stringKey = [MSACKeychainUtil stringForKey:keyTag statusCode:nil];
  if (stringKey) {
    keyData = [[NSData alloc] initWithBase64EncodedString:stringKey options:0];
  } else {

    // If key is not saved in Keychain, create one and save it. This will only happen at most twice after an app is installed.
    @synchronized(classLock) {

      // Recheck if the key has been written from another thread.
      stringKey = [MSACKeychainUtil stringForKey:keyTag statusCode:nil];
      if (!stringKey) {
        keyData = [MSACEncrypter generateAndSaveKeyWithTag:keyTag];
      }
    }
    if (isOriginalKeyTag) {
      self.originalKeyData = keyData;
    } else {
      self.alternateKeyData = keyData;
    }
  }
  return keyData;
}

+ (NSData *_Nullable)performCryptoOperation:(CCOperation)operation
                                      input:(NSData *)input
                       initializationVector:(NSData *)initializationVector
                                        key:(NSData *)key {
  NSData *result;

  // Create a buffer whose size is at least one block plus 1. This is not needed for decryption, but it works.
  size_t outputBufferSize = [input length] + kCCBlockSizeAES128 + 1;
  uint8_t *outputBuffer = malloc(outputBufferSize * sizeof(uint8_t));
  size_t numBytesNeeded = 0;
  CCCryptorStatus status =
      CCCrypt(operation, kMSACEncryptionAlgorithm, kCCOptionPKCS7Padding, [key bytes], kMSACEncryptionKeySize, [initializationVector bytes],
              [input bytes], input.length, outputBuffer, outputBufferSize, &numBytesNeeded);
  if (status != kCCSuccess) {

    // Do not print the status; it is a security requirement that specific crypto errors are not printed.
    MSACLogError([MSACAppCenter logTag], @"Error performing encryption or decryption.");
  } else {
    result = [NSData dataWithBytes:outputBuffer length:numBytesNeeded];
    if (!result) {
      MSACLogError([MSACAppCenter logTag], @"Could not create NSData object from encrypted or decrypted bytes.");
    }
  }
  free(outputBuffer);
  return result;
}

+ (NSData *)generateAndSaveKeyWithTag:(NSString *)keyTag {
  NSData *resultKey = nil;
  uint8_t *keyBytes = nil;
  keyBytes = malloc(kMSACEncryptionKeySize * sizeof(uint8_t));
  OSStatus status = SecRandomCopyBytes(kSecRandomDefault, kMSACEncryptionKeySize, keyBytes);
  if (status != errSecSuccess) {
    MSACLogError([MSACAppCenter logTag], @"Error generating encryption key. Error code: %d", (int)status);
  }
  resultKey = [[NSData alloc] initWithBytes:keyBytes length:kMSACEncryptionKeySize];
  free(keyBytes);

  // Save key to the Keychain.
  NSString *stringKey = [resultKey base64EncodedStringWithOptions:0];
  [MSACKeychainUtil storeString:stringKey forKey:keyTag];
  return resultKey;
}

+ (NSData *)generateInitializationVector {
  uint8_t *ivBytes = malloc(kCCBlockSizeAES128 * sizeof(uint8_t));
  OSStatus status = SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, ivBytes);
  if (status != errSecSuccess) {
    MSACLogError([MSACAppCenter logTag], @"Error generating initialization vector. Error code: %d", (int)status);
  }
  NSData *initializationVector = [NSData dataWithBytes:ivBytes length:kCCBlockSizeAES128];
  free(ivBytes);
  return initializationVector;
}

+ (NSData *)getMetadataStringWithKeyTag:(NSString *)keyTag encryptionAlgorithmName:(NSString *)encryptionAlgorithmName {

  // Format is {key tag}/{algorithm}/{cipher mode}/{padding mode}/{key length}
  NSArray *metadata =
      @[ keyTag, encryptionAlgorithmName, kMSACEncryptionCipherMode, kMSACEncryptionPaddingMode, @(kMSACEncryptionKeySize) ];
  NSString *metadataString = [metadata componentsJoinedByString:kMSACEncryptionMetadataInternalSeparator];
  return [metadataString dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSData *)getMetadataStringWithKeyTag:(NSString *)keyTag {
  return [MSACEncrypter getMetadataStringWithKeyTag:keyTag encryptionAlgorithmName:kMSACEncryptionAlgorithmName];
}

- (NSData *)getMacBytes:(NSData *_Nonnull)key keySize:(NSData *_Nonnull)cipherText {
  unsigned char cHMAC[CC_SHA256_DIGEST_LENGTH];
  CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, cipherText.bytes, cipherText.length, cHMAC);
  return [[NSData alloc] initWithBytes:cHMAC length:sizeof(cHMAC)];
}

/**
 * Get subkey from the secret key.
 * This method uses HKDF simple key derivation function (KDF) based on a hash-based message authentication code (HMAC).
 * See more: https://en.wikipedia.org/wiki/HKDF
 *
 * @param secretKey Secret key.
 * @param outputDataLength Subkey length.
 * @return Data of the calculated subkey.
 */
- (NSData *_Nonnull)getSubkey:(NSData *_Nonnull)secretKey outputSize:(int)outputDataLength {

  // Check output data length.
  if (outputDataLength < 1) {
    NSException *outputDataLengthException = [NSException exceptionWithName:@"Invalid output data length."
                                                                     reason:@"Output data length must be greater than zero."
                                                                   userInfo:nil];
    @throw outputDataLengthException;
  }

  // Calculate iterations.
  int iterations = (int)(ceil((double)outputDataLength / (double)CC_SHA256_DIGEST_LENGTH));

  // Prepare data.
  NSData *tempData = [NSData data];
  NSMutableData *results = [NSMutableData data];

  // Calculate subkey.
  for (int i = 0; i < iterations; i++) {
    CCHmacContext hMacCtx;
    CCHmacInit(&hMacCtx, kCCHmacAlgSHA256, secretKey.bytes, secretKey.length);
    CCHmacUpdate(&hMacCtx, tempData.bytes, tempData.length);
    unsigned char updateData = (char)i;
    CCHmacUpdate(&hMacCtx, &updateData, 1);

    // Calculate result.
    unsigned char outputFinal[CC_SHA256_DIGEST_LENGTH];
    CCHmacFinal(&hMacCtx, outputFinal);
    NSData *tempResult = [NSData dataWithBytes:outputFinal length:sizeof(outputFinal)];
    [results appendData:tempResult];
    tempData = [tempResult copy];
  }
  return [[NSData dataWithData:results] subdataWithRange:NSMakeRange(0, outputDataLength)];
}

@end
