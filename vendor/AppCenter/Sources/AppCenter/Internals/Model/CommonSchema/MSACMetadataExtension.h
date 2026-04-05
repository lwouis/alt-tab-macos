// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACModel.h"
#import "MSACSerializableObject.h"
#import <Foundation/Foundation.h>

static NSString *const kMSACFieldDelimiter = @"f";

/**
 * The metadata section contains additional typing/schema-related information for each field in the Part B or Part C payload.
 */
@interface MSACMetadataExtension : NSObject <MSACSerializableObject, MSACModel>

/**
 * Additional typing/schema-related information for each field in the Part B or Part C payload.
 */
@property(atomic, copy) NSDictionary *metadata;

@end
