// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACOrderedDictionary.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACDataBaseData = @"baseData";
static NSString *const kMSACDataBaseType = @"baseType";

/**
 * The data object contains Part B and Part C properties.
 */
@interface MSACCSData : NSObject <MSACSerializableObject, MSACModel>

@property(atomic, copy) NSDictionary *properties;

@end
