// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACSDKEpoch = @"epoch";
static NSString *const kMSACSDKInstallId = @"installId";
static NSString *const kMSACSDKLibVer = @"libVer";
static NSString *const kMSACSDKSeq = @"seq";

/**
 * The SDK extension is used by platform specific library to record field that are specifically required for a specific SDK.
 */
@interface MSACSDKExtension : NSObject <MSACSerializableObject, MSACModel>

/**
 * The SDK version.
 */
@property(nonatomic, copy) NSString *libVer;

/**
 * ID incremented for each SDK initialization.
 */
@property(nonatomic, copy) NSString *epoch;

/**
 * ID incremented for each event.
 */
@property(nonatomic) int64_t seq;

/**
 * ID created on first-time SDK initialization. It may serves as the device.localId.
 */
@property(nonatomic) NSUUID *installId;

@end
