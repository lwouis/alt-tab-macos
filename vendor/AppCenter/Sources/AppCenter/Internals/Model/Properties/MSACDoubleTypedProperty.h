// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACTypedProperty.h"

static NSString *const kMSACDoubleTypedPropertyType = @"double";

@interface MSACDoubleTypedProperty : MSACTypedProperty

/**
 * Double property value.
 */
@property(nonatomic) double value;

@end
