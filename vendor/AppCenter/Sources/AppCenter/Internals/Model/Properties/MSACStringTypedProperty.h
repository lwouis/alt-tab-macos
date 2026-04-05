// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACTypedProperty.h"

static NSString *const kMSACStringTypedPropertyType = @"string";

@interface MSACStringTypedProperty : MSACTypedProperty

/**
 * String property value.
 */
@property(nonatomic, copy) NSString *value;

@end
