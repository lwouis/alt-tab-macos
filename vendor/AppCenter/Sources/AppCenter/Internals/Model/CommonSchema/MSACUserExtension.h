// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACUserLocale = @"locale";
static NSString *const kMSACUserLocalId = @"localId";

/**
 * The “user” extension tracks common user elements that are not available in the core envelope.
 */
@interface MSACUserExtension : NSObject <MSACSerializableObject, MSACModel>

/**
 * Local Id.
 */
@property(nonatomic, copy) NSString *localId;

/**
 * User's locale.
 */
@property(nonatomic, copy) NSString *locale;

@end
