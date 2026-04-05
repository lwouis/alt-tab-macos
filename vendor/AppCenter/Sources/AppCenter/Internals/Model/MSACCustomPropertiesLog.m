// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACCustomPropertiesLog.h"
#import "MSACUtility+Date.h"

static NSString *const kMSACCustomProperties = @"customProperties";
static NSString *const kMSACProperties = @"properties";
static NSString *const kMSACPropertyType = @"type";
static NSString *const kMSACPropertyName = @"name";
static NSString *const kMSACPropertyValue = @"value";
static NSString *const kMSACPropertyTypeClear = @"clear";
static NSString *const kMSACPropertyTypeBoolean = @"boolean";
static NSString *const kMSACPropertyTypeNumber = @"number";
static NSString *const kMSACPropertyTypeDateTime = @"dateTime";
static NSString *const kMSACPropertyTypeString = @"string";

@implementation MSACCustomPropertiesLog

@synthesize type = _type;
@synthesize properties = _properties;

- (instancetype)init {
  self = [super init];
  if (self) {
    self.type = kMSACCustomProperties;
  }
  return self;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACCustomPropertiesLog class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACCustomPropertiesLog *log = (MSACCustomPropertiesLog *)object;
  return ((!self.properties && !log.properties) || [self.properties isEqualToDictionary:log.properties]);
}

- (BOOL)isValid {
  return [super isValid] && MSACLOG_VALIDATE(properties, self.properties && self.properties.count > 0);
}

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];
  if (self.properties) {
    NSMutableArray *propertiesArray = [NSMutableArray array];
    for (NSString *key in self.properties) {
      NSObject *value = [self.properties objectForKey:key];
      NSMutableDictionary *property = [MSACCustomPropertiesLog serializeProperty:value];
      if (property) {
        [property setObject:key forKey:kMSACPropertyName];
        [propertiesArray addObject:property];
      }
    }
    dict[kMSACProperties] = propertiesArray;
  }
  return dict;
}

/**
 * Serialize the value as custom property.
 */
+ (NSMutableDictionary *)serializeProperty:(NSObject *)value {
  NSMutableDictionary *property = [NSMutableDictionary new];
  if ([value isKindOfClass:[NSNull class]]) {
    [property setObject:kMSACPropertyTypeClear forKey:kMSACPropertyType];
  } else if ([value isKindOfClass:[NSNumber class]]) {

    /**
     * NSNumber is “toll-free bridged” with its Core Foundation counterparts:
     * CFNumber for integer and floating point values, and CFBoolean for Boolean values.
     *
     * NSCFBoolean is a private class in the NSNumber class cluster.
     */
    if ([NSStringFromClass([value class]) isEqualToString:@"__NSCFBoolean"]) {
      [property setObject:kMSACPropertyTypeBoolean forKey:kMSACPropertyType];
      [property setObject:value forKey:kMSACPropertyValue];
    } else {
      [property setObject:kMSACPropertyTypeNumber forKey:kMSACPropertyType];
      [property setObject:value forKey:kMSACPropertyValue];
    }
  } else if ([value isKindOfClass:[NSDate class]]) {
    [property setObject:kMSACPropertyTypeDateTime forKey:kMSACPropertyType];
    [property setObject:[MSACUtility dateToISO8601:(NSDate *)value] forKey:kMSACPropertyValue];
  } else if ([value isKindOfClass:[NSString class]]) {
    [property setObject:kMSACPropertyTypeString forKey:kMSACPropertyType];
    [property setObject:value forKey:kMSACPropertyValue];
  } else {
    return nil;
  }
  return property;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    self.type = [coder decodeObjectForKey:kMSACCustomProperties];
    self.properties = [coder decodeObjectForKey:kMSACProperties];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.type forKey:kMSACCustomProperties];
  [coder encodeObject:self.properties forKey:kMSACProperties];
}

@end
