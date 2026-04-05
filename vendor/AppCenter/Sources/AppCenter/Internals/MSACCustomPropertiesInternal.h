// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MSAC_CUSTOM_PROPERTIES_INTERNAL_H
#define MSAC_CUSTOM_PROPERTIES_INTERNAL_H

#import "MSACCustomProperties.h"

/**
 *  Private declarations for MSACCustomProperties.
 */
@interface MSACCustomProperties ()

/**
 * Create an immutable copy of the properties dictionary to use in synchronized scenarios.
 *
 * @return An immutable copy of properties.
 */
- (NSDictionary<NSString *, NSObject *> *)propertiesImmutableCopy;

@end

#endif
