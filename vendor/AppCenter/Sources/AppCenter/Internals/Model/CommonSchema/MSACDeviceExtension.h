// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACDeviceLocalId = @"localId";

/**
 * Device extension contains device information.
 */
@interface MSACDeviceExtension : NSObject <MSACSerializableObject, MSACModel>

@property(nonatomic, copy) NSString *localId;

@end
