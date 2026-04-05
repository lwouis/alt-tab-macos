// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACOSName = @"name";
static NSString *const kMSACOSVer = @"ver";

/**
 * The OS extension tracks common os elements that are not available in the core envelope.
 */
@interface MSACOSExtension : NSObject <MSACSerializableObject, MSACModel>

/**
 * The OS name.
 */
@property(nonatomic, copy) NSString *name;

/**
 * The OS version.
 */
@property(nonatomic, copy) NSString *ver;

@end
