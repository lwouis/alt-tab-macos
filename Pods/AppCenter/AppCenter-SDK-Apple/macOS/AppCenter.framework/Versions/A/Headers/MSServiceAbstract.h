// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MS_SERVICE_ABSTRACT_H
#define MS_SERVICE_ABSTRACT_H

#import <Foundation/Foundation.h>

#import "MSService.h"

@protocol MSChannelGroupProtocol;

/**
 * Abstraction of services common logic.
 * This class is intended to be subclassed only not instantiated directly.
 */
@interface MSServiceAbstract : NSObject <MSService>

/**
 * The flag indicates whether the service is started from application or not.
 */
@property(nonatomic, assign) BOOL startedFromApplication;

/**
 * Start this service with a channel group. Also sets the flag that indicates that a service has been started.
 *
 * @param channelGroup channel group used to persist and send logs.
 * @param appSecret app secret for the SDK.
 * @param token default transmission target token for this service.
 * @param fromApplication indicates whether the service started from an application or not.
 */
- (void)startWithChannelGroup:(id<MSChannelGroupProtocol>)channelGroup
                    appSecret:(NSString *)appSecret
      transmissionTargetToken:(NSString *)token
              fromApplication:(BOOL)fromApplication;

/**
 * Update configuration when the service requires to start again. This method should only be called if the service is started from libraries
 * and then is being started from an application.
 *
 * @param appSecret app secret for the SDK.
 * @param token default transmission target token for this service.
 */
- (void)updateConfigurationWithAppSecret:(NSString *)appSecret transmissionTargetToken:(NSString *)token;

/**
 * Checks if the service needs the application secret.
 *
 * @return `YES` if the application secret is required, `NO` otherwise.
 */
- (BOOL)isAppSecretRequired;

@end

#endif
