// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACUtility+PropertyValidation.h"

#import "MSACAppCenterInternal.h"
#import "MSACConstants+Internal.h"
#import "MSACLogger.h"

/*
 * Workaround for exporting symbols from category object files.
 */
NSString *MSACUtilityPropertyValidationCategory;

@implementation NSObject (MSACUtility_PropertyValidation)

+ (NSDictionary<NSString *, NSString *> *)validateProperties:(NSDictionary<NSString *, NSString *> *)properties
                                                  forLogName:(NSString *)logName
                                                        type:(NSString *)logType {
  NSMutableDictionary<NSString *, NSString *> *validProperties = [NSMutableDictionary new];
  for (id key in properties) {

    // Don't send more properties than we can.
    if ([validProperties count] >= kMSACMaxPropertiesPerLog) {
      MSACLogWarning([MSACAppCenter logTag], @"%@ '%@' : properties cannot contain more than %d items. Skipping other properties.", logType,
                     logName, kMSACMaxPropertiesPerLog);
      break;
    }
    if (![(NSObject *)key isKindOfClass:[NSString class]] || ![properties[key] isKindOfClass:[NSString class]]) {
      continue;
    }

    // Validate key.
    NSString *strKey = key;
    if ([strKey length] < kMSACMinPropertyKeyLength) {
      MSACLogWarning([MSACAppCenter logTag], @"%@ '%@' : a property key cannot be null or empty. Property will be skipped.", logType,
                     logName);
      continue;
    }
    if ([strKey length] > kMSACMaxPropertyKeyLength) {
      MSACLogWarning([MSACAppCenter logTag],
                     @"%@ '%@' : property %@ : property key length cannot be longer than %d characters. Property key will be truncated.",
                     logType, logName, strKey, kMSACMaxPropertyKeyLength);
      strKey = [strKey substringToIndex:kMSACMaxPropertyKeyLength];
    }

    // Validate value.
    NSString *value = properties[key];
    if ([value length] > kMSACMaxPropertyValueLength) {
      MSACLogWarning([MSACAppCenter logTag],
                     @"%@ '%@' : property '%@' : property value cannot be longer than %d characters. Property value will be truncated.",
                     logType, logName, strKey, kMSACMaxPropertyValueLength);
      value = [value substringToIndex:kMSACMaxPropertyValueLength];
    }

    // Save valid properties.
    [validProperties setObject:value forKey:strKey];
  }
  return validProperties;
}

@end
