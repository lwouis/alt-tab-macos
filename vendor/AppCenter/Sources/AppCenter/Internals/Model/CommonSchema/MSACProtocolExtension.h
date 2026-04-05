// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACDevMake = @"devMake";
static NSString *const kMSACDevModel = @"devModel";
static NSString *const kMSACTicketKeys = @"ticketKeys";

/**
 * The Protocol extension contains device specific information.
 */
@interface MSACProtocolExtension : NSObject <MSACSerializableObject, MSACModel>

/**
 * Ticket keys.
 */
@property(nonatomic) NSArray<NSString *> *ticketKeys;

/**
 * The device's manufacturer.
 */
@property(nonatomic, copy) NSString *devMake;

/**
 * The device's model.
 */
@property(nonatomic, copy) NSString *devModel;

@end
