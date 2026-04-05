// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACSDKExtension.h"

@implementation MSACSDKExtension

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  if (self.libVer) {
    dict[kMSACSDKLibVer] = self.libVer;
  }
  if (self.epoch) {
    dict[kMSACSDKEpoch] = self.epoch;
  }
  if (self.installId) {
    dict[kMSACSDKInstallId] = [self.installId UUIDString];
  }

  // The initial value corresponding to an epoch on a device should be 1, 0 means no seq attributes.
  if (self.seq) {
    dict[kMSACSDKSeq] = @(self.seq);
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
  if (![(NSObject *)object isKindOfClass:[MSACSDKExtension class]]) {
    return NO;
  }
  MSACSDKExtension *sdkExt = (MSACSDKExtension *)object;
  return ((!self.libVer && !sdkExt.libVer) || [self.libVer isEqualToString:sdkExt.libVer]) &&
         ((!self.epoch && !sdkExt.epoch) || [self.epoch isEqualToString:sdkExt.epoch]) && (self.seq == sdkExt.seq) &&
         ((!self.installId && !sdkExt.installId) || [self.installId isEqual:sdkExt.installId]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _libVer = [coder decodeObjectForKey:kMSACSDKLibVer];
    _epoch = [coder decodeObjectForKey:kMSACSDKEpoch];
    _seq = [coder decodeInt64ForKey:kMSACSDKSeq];
    _installId = [coder decodeObjectForKey:kMSACSDKInstallId];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.libVer forKey:kMSACSDKLibVer];
  [coder encodeObject:self.epoch forKey:kMSACSDKEpoch];
  [coder encodeInt64:self.seq forKey:kMSACSDKSeq];
  [coder encodeObject:self.installId forKey:kMSACSDKInstallId];
}

@end
