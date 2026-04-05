// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACDateTimeTypedProperty.h"
#import "MSACSerializableObject.h"
#import "MSACUtility+Date.h"

@implementation MSACDateTimeTypedProperty

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSACDateTimeTypedPropertyType;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _value = [coder decodeObjectForKey:kMSACTypedPropertyValue];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.value forKey:kMSACTypedPropertyValue];
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];
  dict[kMSACTypedPropertyValue] = [MSACUtility dateToISO8601:self.value];
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACDateTimeTypedProperty class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACDateTimeTypedProperty *property = (MSACDateTimeTypedProperty *)object;
  return ((!self.value && !property.value) || [self.value isEqualToDate:property.value]);
}

@end
