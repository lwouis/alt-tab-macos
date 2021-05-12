// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MSAC_LOG_H
#define MSAC_LOG_H

#import <Foundation/Foundation.h>

@class MSACDevice;

NS_SWIFT_NAME(Log)
@protocol MSACLog <NSObject>

/**
 * Log type.
 */
@property(nonatomic, copy) NSString *type;

/**
 * Log timestamp.
 */
@property(nonatomic, strong) NSDate *timestamp;

/**
 * A session identifier is used to correlate logs together. A session is an abstract concept in the API and is not necessarily an analytics
 * session, it can be used to only track crashes.
 */
@property(nonatomic, copy) NSString *sid;

/**
 * Optional distribution group ID value.
 */
@property(nonatomic, copy) NSString *distributionGroupId;

/**
 * Optional user identifier.
 */
@property(nonatomic, copy) NSString *userId;

/**
 * Device properties associated to this log.
 */
@property(nonatomic, strong) MSACDevice *device;

/**
 * Transient object tag. For example, a log can be tagged with a transmission target. We do this currently to prevent properties being
 * applied retroactively to previous logs by comparing their tags.
 */
@property(nonatomic, strong) NSObject *tag;

/**
 * Checks if the object's values are valid.
 *
 * @return YES, if the object is valid.
 */
- (BOOL)isValid;

/**
 * Adds a transmission target token that this log should be sent to.
 *
 * @param token The transmission target token.
 */
- (void)addTransmissionTargetToken:(NSString *)token;

/**
 * Gets all transmission target tokens that this log should be sent to.
 *
 * @returns Collection of transmission target tokens that this log should be sent to.
 */
- (NSSet *)transmissionTargetTokens;

@end

#endif
