// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACSerializableObject.h"

@class MSACAppExtension;
@class MSACDeviceExtension;
@class MSACLocExtension;
@class MSACMetadataExtension;
@class MSACNetExtension;
@class MSACOSExtension;
@class MSACProtocolExtension;
@class MSACSDKExtension;
@class MSACUserExtension;

static NSString *const kMSACCSAppExt = @"app";
static NSString *const kMSACCSDeviceExt = @"device";
static NSString *const kMSACCSLocExt = @"loc";
static NSString *const kMSACCSMetadataExt = @"metadata";
static NSString *const kMSACCSNetExt = @"net";
static NSString *const kMSACCSOSExt = @"os";
static NSString *const kMSACCSProtocolExt = @"protocol";
static NSString *const kMSACCSUserExt = @"user";
static NSString *const kMSACCSSDKExt = @"sdk";

/**
 * Part A extensions.
 */
@interface MSACCSExtensions : NSObject <MSACSerializableObject, MSACModel>

/**
 * The Metadata extension.
 */
@property(nonatomic) MSACMetadataExtension *metadataExt;

/**
 * The Protocol extension.
 */
@property(nonatomic) MSACProtocolExtension *protocolExt;

/**
 * The User extension.
 */
@property(nonatomic) MSACUserExtension *userExt;

/**
 * The Device extension.
 */
@property(nonatomic) MSACDeviceExtension *deviceExt;

/**
 * The OS extension.
 */
@property(nonatomic) MSACOSExtension *osExt;

/**
 * The App extension.
 */
@property(nonatomic) MSACAppExtension *appExt;

/**
 * The network extension.
 */
@property(nonatomic) MSACNetExtension *netExt;

/**
 * The SDK extension.
 */
@property(nonatomic) MSACSDKExtension *sdkExt;

/**
 * The Loc extension.
 */
@property(nonatomic) MSACLocExtension *locExt;

@end
