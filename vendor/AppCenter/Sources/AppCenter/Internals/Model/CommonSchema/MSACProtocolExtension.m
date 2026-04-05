// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACProtocolExtension.h"

@implementation MSACProtocolExtension

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  if (self.ticketKeys) {
    dict[kMSACTicketKeys] = self.ticketKeys;
  }
  if (self.devMake) {
    dict[kMSACDevMake] = self.devMake;
  }
  if (self.devModel) {
    dict[kMSACDevModel] = self.devModel;
  }
  return dict.count == 0 ? nil : dict;
}

#pragma mark - MSACModel

- (BOOL)isValid {

  // All attributes are optional.
  return YES;
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACProtocolExtension class]]) {
    return NO;
  }
  MSACProtocolExtension *protocolExt = (MSACProtocolExtension *)object;
  return ((!self.ticketKeys && !protocolExt.ticketKeys) || [self.ticketKeys isEqualToArray:protocolExt.ticketKeys]) &&
         ((!self.devMake && !protocolExt.devMake) || [self.devMake isEqualToString:protocolExt.devMake]) &&
         ((!self.devModel && !protocolExt.devModel) || [self.devModel isEqualToString:protocolExt.devModel]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _ticketKeys = [coder decodeObjectForKey:kMSACTicketKeys];
    _devMake = [coder decodeObjectForKey:kMSACDevMake];
    _devModel = [coder decodeObjectForKey:kMSACDevModel];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.ticketKeys forKey:kMSACTicketKeys];
  [coder encodeObject:self.devMake forKey:kMSACDevMake];
  [coder encodeObject:self.devModel forKey:kMSACDevModel];
}

@end
