// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACBinary.h"

static NSString *const kMSACId = @"id";
static NSString *const kMSACStartAddress = @"startAddress";
static NSString *const kMSACEndAddress = @"endAddress";
static NSString *const kMSACName = @"name";
static NSString *const kMSACPath = @"path";
static NSString *const kMSACArchitecture = @"architecture";
static NSString *const kMSACPrimaryArchitectureId = @"primaryArchitectureId";
static NSString *const kMSACArchitectureVariantId = @"architectureVariantId";

@implementation MSACBinary

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];

  if (self.binaryId) {
    dict[kMSACId] = self.binaryId;
  }
  if (self.startAddress) {
    dict[kMSACStartAddress] = self.startAddress;
  }
  if (self.endAddress) {
    dict[kMSACEndAddress] = self.endAddress;
  }
  if (self.name) {
    dict[kMSACName] = self.name;
  }
  if (self.path) {
    dict[kMSACPath] = self.path;
  }
  if (self.architecture) {
    dict[kMSACArchitecture] = self.architecture;
  }
  if (self.primaryArchitectureId) {
    dict[kMSACPrimaryArchitectureId] = self.primaryArchitectureId;
  }
  if (self.architectureVariantId) {
    dict[kMSACArchitectureVariantId] = self.architectureVariantId;
  }

  return dict;
}

- (BOOL)isValid {
  return MSACLOG_VALIDATE_NOT_NIL(binaryId) && MSACLOG_VALIDATE_NOT_NIL(startAddress) && MSACLOG_VALIDATE_NOT_NIL(endAddress) &&
         MSACLOG_VALIDATE_NOT_NIL(name) && MSACLOG_VALIDATE_NOT_NIL(path);
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACBinary class]]) {
    return NO;
  }
  MSACBinary *binary = (MSACBinary *)object;
  return ((!self.binaryId && !binary.binaryId) || [self.binaryId isEqualToString:binary.binaryId]) &&
         ((!self.startAddress && !binary.startAddress) || [self.startAddress isEqualToString:binary.startAddress]) &&
         ((!self.endAddress && !binary.endAddress) || [self.endAddress isEqualToString:binary.endAddress]) &&
         ((!self.name && !binary.name) || [self.name isEqualToString:binary.name]) &&
         ((!self.path && !binary.path) || [self.path isEqualToString:binary.path]) &&
         ((!self.architecture && !binary.architecture) || [self.architecture isEqualToString:binary.architecture]) &&
         ((!self.primaryArchitectureId && !binary.primaryArchitectureId) ||
          [self.primaryArchitectureId isEqual:binary.primaryArchitectureId]) &&
         ((!self.architectureVariantId && !binary.architectureVariantId) ||
          [self.architectureVariantId isEqual:binary.architectureVariantId]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _binaryId = [coder decodeObjectForKey:kMSACId];
    _startAddress = [coder decodeObjectForKey:kMSACStartAddress];
    _endAddress = [coder decodeObjectForKey:kMSACEndAddress];
    _name = [coder decodeObjectForKey:kMSACName];
    _path = [coder decodeObjectForKey:kMSACPath];
    _architecture = [coder decodeObjectForKey:kMSACArchitecture];
    _primaryArchitectureId = [coder decodeObjectForKey:kMSACPrimaryArchitectureId];
    _architectureVariantId = [coder decodeObjectForKey:kMSACArchitectureVariantId];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.binaryId forKey:kMSACId];
  [coder encodeObject:self.startAddress forKey:kMSACStartAddress];
  [coder encodeObject:self.endAddress forKey:kMSACEndAddress];
  [coder encodeObject:self.name forKey:kMSACName];
  [coder encodeObject:self.path forKey:kMSACPath];
  [coder encodeObject:self.architecture forKey:kMSACArchitecture];
  [coder encodeObject:self.primaryArchitectureId forKey:kMSACPrimaryArchitectureId];
  [coder encodeObject:self.architectureVariantId forKey:kMSACArchitectureVariantId];
}

@end
