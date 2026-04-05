// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACSerializableObject.h"

static NSString *const kMSACTypedPropertyValue = @"value";

@interface MSACTypedProperty : NSObject <MSACSerializableObject>

/**
 * Property type.
 */
@property(nonatomic, copy) NSString *type;

/**
 * Property name.
 */
@property(nonatomic, copy) NSString *name;

@end
