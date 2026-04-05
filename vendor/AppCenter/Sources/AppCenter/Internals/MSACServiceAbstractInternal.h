// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACService.h"
#import "MSACServiceAbstract.h"
#import "MSACServiceCommon.h"
#import "MSACServiceInternal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Abstraction of services internal common logic.
 * This class is intended to be subclassed only not instantiated directly.
 *
 * @see MSACServiceInternal protocol, any service subclassing this class must also conform to this protocol.
 */
@interface MSACServiceAbstract () <MSACServiceCommon>

/**
 * isEnabled value storage key.
 */
@property(nonatomic, copy, readonly) NSString *isEnabledKey;

/**
 * Flag indicating if a service has been started or not.
 */
@property(nonatomic, getter=isStarted) BOOL started;

#pragma mark - Service initialization

/**
 * Create a service.
 *
 * @return A service with common logic already implemented.
 */
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
