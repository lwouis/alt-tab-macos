// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACTypedProperty.h"

static NSString *const kMSACLongTypedPropertyType = @"long";

@interface MSACLongTypedProperty : MSACTypedProperty

/**
 * Long property value (64-bit signed integer).
 */
@property(nonatomic) int64_t value;

@end
