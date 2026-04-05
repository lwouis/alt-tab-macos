// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACNetProvider = @"provider";

/**
 * The network extension contains network properties.
 */
@interface MSACNetExtension : NSObject <MSACSerializableObject, MSACModel>

/**
 * The network provider.
 */
@property(nonatomic, copy) NSString *provider;

@end
