// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACWrapperSdk.h"
#import "MSACWrapperSdkInternal.h"

@implementation MSACWrapperSdk

- (instancetype)initWithWrapperSdkVersion:(NSString *)wrapperSdkVersion
                           wrapperSdkName:(NSString *)wrapperSdkName
                    wrapperRuntimeVersion:(NSString *)wrapperRuntimeVersion
                   liveUpdateReleaseLabel:(NSString *)liveUpdateReleaseLabel
                  liveUpdateDeploymentKey:(NSString *)liveUpdateDeploymentKey
                    liveUpdatePackageHash:(NSString *)liveUpdatePackageHash {
  self = [super init];
  if (self) {
    _wrapperSdkVersion = wrapperSdkVersion;
    _wrapperSdkName = wrapperSdkName;
    _wrapperRuntimeVersion = wrapperRuntimeVersion;
    _liveUpdateReleaseLabel = liveUpdateReleaseLabel;
    _liveUpdateDeploymentKey = liveUpdateDeploymentKey;
    _liveUpdatePackageHash = liveUpdatePackageHash;
  }
  return self;
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];

  if (self.wrapperSdkVersion) {
    dict[kMSACWrapperSDKVersion] = self.wrapperSdkVersion;
  }
  if (self.wrapperSdkName) {
    dict[kMSACWrapperSDKName] = self.wrapperSdkName;
  }
  if (self.wrapperRuntimeVersion) {
    dict[kMSACWrapperRuntimeVersion] = self.wrapperRuntimeVersion;
  }
  if (self.liveUpdateReleaseLabel) {
    dict[kMSACLiveUpdateReleaseLabel] = self.liveUpdateReleaseLabel;
  }
  if (self.liveUpdateDeploymentKey) {
    dict[kMSACLiveUpdateDeploymentKey] = self.liveUpdateDeploymentKey;
  }
  if (self.liveUpdatePackageHash) {
    dict[kMSACLiveUpdatePackageHash] = self.liveUpdatePackageHash;
  }
  return dict;
}

- (BOOL)isValid {
  return YES;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACWrapperSdk class]]) {
    return NO;
  }
  MSACWrapperSdk *wrapperSdk = (MSACWrapperSdk *)object;
  return ((!self.wrapperSdkVersion && !wrapperSdk.wrapperSdkVersion) ||
          [self.wrapperSdkVersion isEqualToString:wrapperSdk.wrapperSdkVersion]) &&
         ((!self.wrapperSdkName && !wrapperSdk.wrapperSdkName) || [self.wrapperSdkName isEqualToString:wrapperSdk.wrapperSdkName]) &&
         ((!self.wrapperRuntimeVersion && !wrapperSdk.wrapperRuntimeVersion) ||
          [self.wrapperRuntimeVersion isEqualToString:wrapperSdk.wrapperRuntimeVersion]) &&
         ((!self.liveUpdateReleaseLabel && !wrapperSdk.liveUpdateReleaseLabel) ||
          [self.liveUpdateReleaseLabel isEqualToString:wrapperSdk.liveUpdateReleaseLabel]) &&
         ((!self.liveUpdateDeploymentKey && !wrapperSdk.liveUpdateDeploymentKey) ||
          [self.liveUpdateDeploymentKey isEqualToString:wrapperSdk.liveUpdateDeploymentKey]) &&
         ((!self.liveUpdatePackageHash && !wrapperSdk.liveUpdatePackageHash) ||
          [self.liveUpdatePackageHash isEqualToString:wrapperSdk.liveUpdatePackageHash]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _wrapperSdkVersion = [coder decodeObjectForKey:kMSACWrapperSDKVersion];
    _wrapperSdkName = [coder decodeObjectForKey:kMSACWrapperSDKName];
    _wrapperRuntimeVersion = [coder decodeObjectForKey:kMSACWrapperRuntimeVersion];
    _liveUpdateReleaseLabel = [coder decodeObjectForKey:kMSACLiveUpdateReleaseLabel];
    _liveUpdateDeploymentKey = [coder decodeObjectForKey:kMSACLiveUpdateDeploymentKey];
    _liveUpdatePackageHash = [coder decodeObjectForKey:kMSACLiveUpdatePackageHash];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.wrapperSdkVersion forKey:kMSACWrapperSDKVersion];
  [coder encodeObject:self.wrapperSdkName forKey:kMSACWrapperSDKName];
  [coder encodeObject:self.wrapperRuntimeVersion forKey:kMSACWrapperRuntimeVersion];
  [coder encodeObject:self.liveUpdateReleaseLabel forKey:kMSACLiveUpdateReleaseLabel];
  [coder encodeObject:self.liveUpdateDeploymentKey forKey:kMSACLiveUpdateDeploymentKey];
  [coder encodeObject:self.liveUpdatePackageHash forKey:kMSACLiveUpdatePackageHash];
}

@end
