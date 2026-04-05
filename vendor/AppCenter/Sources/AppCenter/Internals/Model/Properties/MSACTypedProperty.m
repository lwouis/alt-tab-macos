// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACTypedProperty.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACTypedPropertyType = @"type";
static NSString *const kMSACTypedPropertyName = @"name";

@implementation MSACTypedProperty

// Subclasses need to decode "value" since the type might be saved as a primitive.
- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _type = [coder decodeObjectForKey:kMSACTypedPropertyType];
    _name = [coder decodeObjectForKey:kMSACTypedPropertyName];
  }
  return self;
}

// Subclasses need to encode "value" since the type might be saved as a primitive.
- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.type forKey:kMSACTypedPropertyType];
  [coder encodeObject:self.name forKey:kMSACTypedPropertyName];
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  dict[kMSACTypedPropertyType] = self.type;
  dict[kMSACTypedPropertyName] = self.name;
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACTypedProperty class]]) {
    return NO;
  }
  MSACTypedProperty *property = (MSACTypedProperty *)object;
  return ((!self.type && !property.type) || [self.type isEqualToString:property.type]);
}

@end
