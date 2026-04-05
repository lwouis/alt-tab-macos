// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppCenterInternal.h"
#import "MSACChannelGroupProtocol.h"
#import "MSACChannelUnitProtocol.h"

@implementation MSACServiceAbstract

@synthesize channelGroup = _channelGroup;
@synthesize channelUnit = _channelUnit;
@synthesize appSecret = _appSecret;
@synthesize defaultTransmissionTargetToken = _defaultTransmissionTargetToken;

- (instancetype)init {
  if ((self = [super init])) {
    _started = NO;
    _isEnabledKey = [NSString stringWithFormat:@"%@IsEnabled", self.groupId];
  }
  return self;
}

#pragma mark : - MSACServiceCommon

- (BOOL)isEnabled {

  // Get isEnabled value from persistence.
  // No need to cache the value in a property, user settings already have their cache mechanism.
  NSNumber *isEnabledNumber = [MSAC_APP_CENTER_USER_DEFAULTS objectForKey:self.isEnabledKey];

  // Return the persisted value otherwise it's enabled by default.
  return (isEnabledNumber) ? [isEnabledNumber boolValue] : YES;
}

- (void)setEnabled:(BOOL)isEnabled {
  if (self.isEnabled != isEnabled) {

    // Apply enabled state.
    [self applyEnabledState:isEnabled];

    // Persist the enabled status.
    [MSAC_APP_CENTER_USER_DEFAULTS setObject:@(isEnabled) forKey:self.isEnabledKey];
  }
}

- (void)applyEnabledState:(BOOL)isEnabled {

  // Propagate isEnabled and delete logs on disabled.
  [self.channelUnit setEnabled:isEnabled andDeleteDataOnDisabled:YES];
}

- (BOOL)canBeUsed {
  BOOL canBeUsed = [MSACAppCenter sharedInstance].sdkConfigured && self.started;
  if (!canBeUsed) {
    MSACLogError(
        [MSACAppCenter logTag],
        @"%@ service hasn't been started. You need to call [MSACAppCenter start:YOUR_APP_SECRET withServices:LIST_OF_SERVICES] first.",
        MSAC_CLASS_NAME_WITHOUT_PREFIX);
  }
  return canBeUsed;
}

- (BOOL)isAvailable {
  return self.isEnabled && self.started;
}

- (MSACInitializationPriority)initializationPriority {
  return MSACInitializationPriorityDefault;
}

- (BOOL)isAppSecretRequired {
  return YES;
}

- (BOOL)isStartedFromApplication {
  return self.startedFromApplication;
}

#pragma mark : - MSACService

- (void)startWithChannelGroup:(id<MSACChannelGroupProtocol>)channelGroup
                    appSecret:(NSString *)appSecret
      transmissionTargetToken:(NSString *)token
              fromApplication:(BOOL)fromApplication {
  self.startedFromApplication = fromApplication;
  self.channelGroup = channelGroup;
  self.appSecret = appSecret;
  self.defaultTransmissionTargetToken = token;
  self.started = YES;
  if ([self respondsToSelector:@selector(channelUnitConfiguration)]) {

    // Initialize channel unit for the service in channel group.
    self.channelUnit = [self.channelGroup addChannelUnitWithConfiguration:self.channelUnitConfiguration];
  }

  // Enable this service as needed.
  if (self.isEnabled) {
    [self applyEnabledState:self.isEnabled];
  }
}

- (void)updateConfigurationWithAppSecret:(NSString *)appSecret transmissionTargetToken:(NSString *)token {
  self.startedFromApplication = YES;
  self.appSecret = appSecret;
  self.defaultTransmissionTargetToken = token;

  // Enable this service as needed.
  if (self.isEnabled) {
    [self applyEnabledState:self.isEnabled];
  }
}

#pragma clang diagnostic push

// Ignore "Unknown warning group '-Wobjc-messaging-id'" for old XCode
#pragma clang diagnostic ignored "-Wunknown-pragmas"
#pragma clang diagnostic ignored "-Wunknown-warning-option"

// Ignore "Messaging unqualified id" for XCode 10
#pragma clang diagnostic ignored "-Wobjc-messaging-id"
+ (void)setEnabled:(BOOL)isEnabled {
  @synchronized([self sharedInstance]) {
    if ([[self sharedInstance] canBeUsed]) {
      if (![MSACAppCenter isEnabled] && ![MSACAppCenter sharedInstance].enabledStateUpdating) {
        MSACLogError([MSACAppCenter logTag],
                     @"The SDK is disabled. Re-enable the whole SDK from AppCenter first before enabling %@ service.",
                     MSAC_CLASS_NAME_WITHOUT_PREFIX);
      } else {
        [[self sharedInstance] setEnabled:isEnabled];
      }
    }
  }
}

+ (BOOL)isEnabled {
  @synchronized([self sharedInstance]) {
    return [[self sharedInstance] canBeUsed] && [[self sharedInstance] isEnabled];
  }
}
#pragma clang diagnostic pop

@end
