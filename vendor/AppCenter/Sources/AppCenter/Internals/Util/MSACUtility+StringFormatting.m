// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <CommonCrypto/CommonDigest.h>

#import "MSACAppCenterInternal.h"
#import "MSACLogger.h"
#import "MSACUtility+StringFormatting.h"

/*
 * Workaround for exporting symbols from category object files.
 */
NSString *MSACUtilityStringFormattingCategory;

/*
 * We support the following formats:
 * target=<..>
 * appsecret=<..>
 * target=<..>;appsecret=<..>
 * ios=<..>;macos=<..>
 */

static NSString *kMSACTransmissionTargetKey = @"target=";
static NSString *kMSACAppSecretKey = @"appsecret=";
static NSString *kMSACSecretSeparator = @"=";

#if TARGET_OS_OSX || TARGET_OS_MACCATALYST
static NSString *kMSACAppSecretOSKey = @"macos=";
#elif TARGET_OS_IOS
static NSString *kMSACAppSecretOSKey = @"ios=";
#elif TARGET_OS_TV
static NSString *kMSACAppSecretOSKey = @"appsecret=";
#endif

@implementation NSObject (MSACUtility_StringFormatting)

+ (NSString *)sha256:(NSString *)string {

  // Hash string with SHA256.
  const char *encodedString = [string cStringUsingEncoding:NSASCIIStringEncoding];
  unsigned char hashedData[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(encodedString, (CC_LONG)strlen(encodedString), hashedData);

  // Convert hashed data to NSString.
  NSData *data = [NSData dataWithBytes:hashedData length:sizeof(hashedData)];
  NSMutableString *stringBuffer = [NSMutableString stringWithCapacity:([data length] * 2)];
  const unsigned char *dataBuffer = [data bytes];
  for (NSUInteger i = 0; i < [data length]; i++) {
    [stringBuffer appendFormat:@"%02x", dataBuffer[i]];
  }
  return [stringBuffer copy];
}

+ (NSString *)appSecretFrom:(NSString *)string {
  NSArray *components = [string componentsSeparatedByString:@";"];
  if (components == nil || components.count == 0) {
    return nil;
  } else {
    for (NSString *component in components) {
      BOOL transmissionTokenIsNotPresent = [component rangeOfString:kMSACTransmissionTargetKey].location == NSNotFound;

      // Component is app secret, return the component. Check for length > 0 as "foo;" will be parsed as 2 components.
      if (transmissionTokenIsNotPresent && component.length > 0) {
        NSString *secretString = @"";
        if ([string rangeOfString:kMSACAppSecretOSKey].location != NSNotFound) {

          // If we know the whole string contains OSKey somewhere, we start looking for it.
          if ([component rangeOfString:kMSACAppSecretOSKey].location != NSNotFound) {
            secretString = [component stringByReplacingOccurrencesOfString:kMSACAppSecretOSKey withString:@""];
          }
        } else {

          // If the whole string does not contain OSKey, we either use its value
          // or search for "appsecret" components.
          if ([component rangeOfString:kMSACAppSecretKey].location == NSNotFound &&
              [component rangeOfString:kMSACSecretSeparator].location == NSNotFound) {

            // Make sure the string is "clean" and without keys at this point.
            secretString = component;
          } else {
            secretString = [component stringByReplacingOccurrencesOfString:kMSACAppSecretKey withString:@""];
          }
        }

        // Check for string length to avoid returning empty string.
        if ((secretString != nil) && (secretString.length > 0)) {
          return secretString;
        }
      }
    }

    // String does not contain an app secret.
    return nil;
  }
}

+ (NSString *)transmissionTargetTokenFrom:(NSString *)string {
  NSArray *components = [string componentsSeparatedByString:@";"];
  if (components == nil || components.count == 0) {
    return nil;
  } else {
    for (NSString *component in components) {

      // Component is transmission target token, return the component.
      if (([component rangeOfString:kMSACTransmissionTargetKey].location != NSNotFound) && (component.length > 0)) {
        NSString *transmissionTarget = [component stringByReplacingOccurrencesOfString:kMSACTransmissionTargetKey withString:@""];

        // Check for string length to avoid returning empty string.
        if (transmissionTarget.length > 0) {
          return transmissionTarget;
        }
      }
    }

    // String does not contain a transmission target token.
    return nil;
  }
}

+ (nullable NSString *)iKeyFromTargetToken:(NSString *)token {
  NSString *targetKey = [self targetKeyFromTargetToken:token];
  return targetKey.length ? [NSString stringWithFormat:@"o:%@", targetKey] : nil;
}

+ (nullable NSString *)targetKeyFromTargetToken:(NSString *)token {
  NSString *targetKey = [token componentsSeparatedByString:@"-"][0];
  return targetKey.length ? targetKey : nil;
}

+ (nullable NSString *)prettyPrintJson:(nullable NSData *)data {
  if (!data) {
    return nil;
  }

  // Error instance for JSON parsing. Trying to format json for log. Don't need to log json error here.
  NSError *jsonError = nil;
  NSString *result = nil;
  id dictionary = [NSJSONSerialization JSONObjectWithData:(NSData *)data options:NSJSONReadingMutableContainers error:&jsonError];
  if (jsonError) {
    result = [[NSString alloc] initWithData:(NSData *)data encoding:NSUTF8StringEncoding];
  } else {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!jsonData || jsonError) {
      result = [[NSString alloc] initWithData:(NSData *)data encoding:NSUTF8StringEncoding];
    } else {

      // NSJSONSerialization escapes paths by default so we replace them.
      result = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"\\/"
                                                                                                                 withString:@"/"];
    }
  }
  return result;
}

- (NSString *)obfuscateString:(NSString *)unObfuscatedString
          searchingForPattern:(NSString *)pattern
        toReplaceWithTemplate:(NSString *)aTemplate {
  NSString *obfuscatedString;
  NSError *error = nil;
  if (unObfuscatedString) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    if (!regex) {
      MSACLogError([MSACAppCenter logTag], @"Couldn't create regular expression with pattern\"%@\": %@", pattern,
                   error.localizedDescription);
      return nil;
    }
    obfuscatedString = [regex stringByReplacingMatchesInString:unObfuscatedString
                                                       options:0
                                                         range:NSMakeRange(0, [unObfuscatedString length])
                                                  withTemplate:aTemplate];
  }
  return obfuscatedString;
}

@end
