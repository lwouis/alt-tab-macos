// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACService.h"
#import "MSACServiceCommon.h"

/**
 * Protocol declaring all the logic of a service. This is what concrete services needs to conform to. The difference is that
 * MSACServiceCommon is public, while MSACServiceInternal is private. Some properties are present in both, which is counter-intuitive but
 * the way we implemented this to achieve abstraction and not have empty implementations in MSACServiceAbstract.
 */
@protocol MSACServiceInternal <MSACService, MSACServiceCommon>

/**
 * The initialization priority for this service. Defined here as well as in MSACServiceCommon to achieve abstraction.
 */
@property(nonatomic, readonly) MSACInitializationPriority initializationPriority;

/**
 * The app secret for the SDK.
 */
@property(nonatomic) NSString *appSecret;

/**
 * Service unique key for storage purpose.
 *
 * @discussion: IMPORTANT, This string is used to point to the right storage value for this service. Changing this string results in data
 * lost if previous data is not migrated.
 */
@property(nonatomic, copy, readonly) NSString *groupId;

/**
 * Get the unique instance.
 *
 * @return The unique instance.
 */
+ (instancetype)sharedInstance;

/**
 * Get a service name.
 *
 * @return the service name.
 *
 * @discussion This is used to initialize each service.
 */
+ (NSString *)serviceName;

/**
 * Get the log tag for this service.
 *
 * @return A name of logger tag for this service.
 */
+ (NSString *)logTag;

@end
