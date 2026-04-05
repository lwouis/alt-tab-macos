// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#if __has_include(<AppCenter/MSACConstants.h>)
#import <AppCenter/MSACConstants.h>
#else
#import "MSACConstants.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@class MSACChannelUnitConfiguration;

@protocol MSACChannelGroupProtocol;
@protocol MSACChannelUnitProtocol;

/**
 * Protocol declaring public common logic for services.
 */
@protocol MSACServiceCommon <NSObject>

@required

/**
 * Flag indicating if a service is available or not. It means that the service is started and enabled.
 */
@property(nonatomic, readonly, getter=isAvailable) BOOL available;

/**
 * Flag indicating if a service is enabled or not.
 */
@property(nonatomic, getter=isEnabled) BOOL enabled;

/**
 * Channel group.
 */
@property(nonatomic) id<MSACChannelGroupProtocol> channelGroup;

/**
 * Channel unit.
 */
@property(nonatomic) id<MSACChannelUnitProtocol> channelUnit;

/**
 * The app secret for the SDK.
 */
@property(nonatomic, nonnull) NSString *appSecret;

/**
 * The default transmission target token.
 */
@property(nonatomic, nonnull) NSString *defaultTransmissionTargetToken;

@optional

/**
 * Service unique key for storage purpose.
 *
 * @discussion: IMPORTANT, This string is used to point to the right storage value for this service. Changing this string results in data
 * lost if previous data is not migrated.
 */
@property(nonatomic, copy, readonly) NSString *groupId;

/**
 * The channel configuration for this service.
 */
@property(nonatomic) MSACChannelUnitConfiguration *channelUnitConfiguration;

@required

/**
 * Apply the enabled state to the service.
 *
 * @param isEnabled A boolean value set to YES to enable the service or NO otherwise.
 */
- (void)applyEnabledState:(BOOL)isEnabled;

/**
 * The initialization priority for this service.
 */
@property(nonatomic, readonly) MSACInitializationPriority initializationPriority;

/**
 * Check if the SDK has been properly initialized and the service can be used. Logs an error in case it wasn't.
 *
 * @return a BOOL to indicate proper initialization of the SDK.
 */
- (BOOL)canBeUsed;

/**
 * Start this service with a channel group. Also sets the flag that indicates that a service has been started.
 *
 * @param channelGroup channel group used to persist and send logs.
 * @param appSecret app secret for the SDK.
 * @param token default transmission target token.
 * @param fromApplication indicates whether the service started from an application or not.
 *
 * @discussion Note that this is defined both here and in MSACServiceAbstract.h. This is intentional, and due to the way the classes are
 * factored.
 */
- (void)startWithChannelGroup:(id<MSACChannelGroupProtocol>)channelGroup
                    appSecret:(nullable NSString *)appSecret
      transmissionTargetToken:(nullable NSString *)token
              fromApplication:(BOOL)fromApplication;

/**
 * Update configuration when the service requires to start again. This method should only be called if the service is started from libraries
 * and then is being started from an application.
 *
 * @param appSecret app secret for the SDK.
 * @param token default transmission target token for this service.
 *
 * @discussion Note that this is defined both here and in MSACServiceAbstract.h. This is intentional, and due to the way the classes are
 * factored.
 */
- (void)updateConfigurationWithAppSecret:(NSString *)appSecret transmissionTargetToken:(NSString *)token;

/**
 * Checks if the service needs the application secret.
 *
 * @return `YES` if the application secret is required, `NO` otherwise.
 */
- (BOOL)isAppSecretRequired;

/**
 * Checks if the service is started from an application.
 *
 * @return `YES` if the service is started from an application, `NO` otherwise.
 */
- (BOOL)isStartedFromApplication;

@optional

/**
 * Get the unique instance.
 *
 * @return unique instance.
 */
+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
