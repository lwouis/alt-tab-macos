// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

static NSString *const kMSACDevice = @"device";
static NSString *const kMSACDistributionGroupId = @"distributionGroupId";
static NSString *const kMSACSId = @"sid";
static NSString *const kMSACType = @"type";
static NSString *const kMSACTimestamp = @"timestamp";
static NSString *const kMSACUserId = @"userId";

@interface MSACAbstractLog ()

/**
 * List of transmission target tokens that this log should be sent to.
 */
@property(nonatomic) NSSet *transmissionTargetTokens;

@end
