// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACAppCenterInternal.h"
#import "MSACKeychainUtilPrivate.h"
#import "MSACLogger.h"
#import "MSACUtility.h"

@implementation MSACKeychainUtil

static NSString *AppCenterKeychainServiceName(NSString *suffix) {
  static NSString *serviceName = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    serviceName = [NSString stringWithFormat:@"%@.%@", [MSAC_APP_MAIN_BUNDLE bundleIdentifier], suffix];
  });
  return serviceName;
}

+ (BOOL)storeString:(NSString *)string forKey:(NSString *)key withServiceName:(NSString *)serviceName {
  NSMutableDictionary *attributes = [MSACKeychainUtil generateItem:key withServiceName:serviceName];

  // By default the keychain is not accessible when the device is locked, this will make it accessible after the first unlock.
  attributes[(__bridge id)kSecAttrAccessible] = (__bridge id)(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly);
  attributes[(__bridge id)kSecValueData] = [string dataUsingEncoding:NSUTF8StringEncoding];
  OSStatus status = [self addSecItem:attributes];

  // Delete item if already exists.
  if (status == errSecDuplicateItem) {
    [self deleteSecItem:attributes];
    status = [self addSecItem:attributes];
  }
  if (status == noErr) {
    MSACLogVerbose([MSACAppCenter logTag], @"Stored a string with key='%@', service='%@' to keychain.", key, serviceName);
    return YES;
  }
  MSACLogWarning([MSACAppCenter logTag], @"Failed to store item with key='%@', service='%@' to keychain. OS Status code %i", key,
                 serviceName, (int)status);
  return NO;
}

+ (BOOL)storeString:(NSString *)string forKey:(NSString *)key {
  return [MSACKeychainUtil storeString:string forKey:key withServiceName:AppCenterKeychainServiceName(kMSACServiceSuffix)];
}

+ (NSString *)deleteStringForKey:(NSString *)key withServiceName:(NSString *)serviceName {
  NSString *string = [MSACKeychainUtil stringForKey:key statusCode:nil];
  if (string) {
    NSMutableDictionary *query = [MSACKeychainUtil generateItem:key withServiceName:serviceName];
    OSStatus status = [self deleteSecItem:query];
    if (status == noErr) {
      MSACLogVerbose([MSACAppCenter logTag], @"Deleted a string with key='%@', service='%@' from keychain.", key, serviceName);
      return string;
    }
    MSACLogWarning([MSACAppCenter logTag], @"Failed to delete item with key='%@', service='%@' from keychain. OS Status code %i", key,
                   serviceName, (int)status);
  }
  return nil;
}

+ (NSString *)deleteStringForKey:(NSString *)key {
  return [MSACKeychainUtil deleteStringForKey:key withServiceName:AppCenterKeychainServiceName(kMSACServiceSuffix)];
}

+ (NSString *)stringForKey:(NSString *)key withServiceName:(NSString *)serviceName statusCode:(OSStatus *)statusCode {
  NSMutableDictionary *query = [MSACKeychainUtil generateItem:key withServiceName:serviceName];
  query[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;
  query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
  CFTypeRef result = nil;

  // Create placeholder to use in case given status code pointer is NULL. Can't put it inside the if statement or it can get deallocated too
  // early.
  OSStatus statusPlaceholder;
  if (!statusCode) {
    statusCode = &statusPlaceholder;
  }
  *statusCode = [self secItemCopyMatchingQuery:query result:&result];
  if (*statusCode == noErr) {
    MSACLogVerbose([MSACAppCenter logTag], @"Retrieved a string with key='%@', service='%@' from keychain.", key, serviceName);
    return [[NSString alloc] initWithData:(__bridge_transfer NSData *)result encoding:NSUTF8StringEncoding];
  }
  MSACLogWarning([MSACAppCenter logTag], @"Failed to retrieve item with key='%@', service='%@' from keychain. OS Status code %i", key,
                 serviceName, (int)*statusCode);
  return nil;
}

+ (NSString *)stringForKey:(NSString *)key statusCode:(OSStatus *)statusCode {
  return [MSACKeychainUtil stringForKey:key withServiceName:AppCenterKeychainServiceName(kMSACServiceSuffix) statusCode:statusCode];
}

+ (BOOL)clear {
  NSMutableDictionary *query = [NSMutableDictionary new];
  query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
  query[(__bridge id)kSecAttrService] = AppCenterKeychainServiceName(kMSACServiceSuffix);
  OSStatus status = [self deleteSecItem:query];
  return status == noErr;
}

+ (NSMutableDictionary *)generateItem:(NSString *)key withServiceName:(NSString *)serviceName {
  NSMutableDictionary *item = [NSMutableDictionary new];
  item[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
  item[(__bridge id)kSecAttrService] = serviceName;
  item[(__bridge id)kSecAttrAccount] = key;
  return item;
}

#pragma mark - Keychain wrapper

+ (OSStatus)deleteSecItem:(NSMutableDictionary *)query {
  return SecItemDelete((__bridge CFDictionaryRef)query);
}

+ (OSStatus)addSecItem:(NSMutableDictionary *)attributes {
  return SecItemAdd((__bridge CFDictionaryRef)attributes, nil);
}

+ (OSStatus)secItemCopyMatchingQuery:(NSMutableDictionary *)query result:(CFTypeRef *__nullable CF_RETURNS_RETAINED)result {
  return SecItemCopyMatching((__bridge CFDictionaryRef)query, result);
}

@end
