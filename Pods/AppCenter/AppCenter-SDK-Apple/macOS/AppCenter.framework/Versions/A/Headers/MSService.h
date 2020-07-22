// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MS_SERVICE_H
#define MS_SERVICE_H

#import <Foundation/Foundation.h>

/**
 * Protocol declaring service logic.
 */
@protocol MSService <NSObject>

/**
 * Enable or disable this service.
 * The state is persisted in the device's storage across application launches.
 *
 * @param isEnabled Whether this service is enabled or not.
 *
 * @see isEnabled
 */
+ (void)setEnabled:(BOOL)isEnabled;

/**
 * Indicates whether this service is enabled.
 *
 * @return `YES` if this service is enabled, `NO` if it is not.
 *
 * @see setEnabled:
 */
+ (BOOL)isEnabled;

@end

#endif
