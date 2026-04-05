// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACTimezone = @"tz";

/**
 * Describes the location from which the event was logged.
 */
@interface MSACLocExtension : NSObject <MSACSerializableObject, MSACModel>

/**
 * Time zone on the device.
 */
@property(nonatomic, copy) NSString *tz;

@end
