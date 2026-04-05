// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACTypedProperty.h"

static NSString *const kMSACBooleanTypedPropertyType = @"boolean";

@interface MSACBooleanTypedProperty : MSACTypedProperty

/**
 * Boolean property value.
 */
@property(nonatomic) BOOL value;

@end
