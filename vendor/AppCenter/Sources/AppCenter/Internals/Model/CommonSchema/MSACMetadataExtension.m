// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACMetadataExtension.h"

@implementation MSACMetadataExtension

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict;
  if (self.metadata) {
    dict = [NSMutableDictionary new];
    [dict addEntriesFromDictionary:self.metadata];
  }
  return dict;
}

#pragma mark - MSACModel

- (BOOL)isValid {

  // All attributes are optional.
  return YES;
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACMetadataExtension class]]) {
    return NO;
  }
  MSACMetadataExtension *csMetadata = (MSACMetadataExtension *)object;
  return (!self.metadata && !csMetadata) || [self.metadata isEqualToDictionary:csMetadata.metadata];
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _metadata = [coder decodeObject];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeRootObject:self.metadata];
}

@end
