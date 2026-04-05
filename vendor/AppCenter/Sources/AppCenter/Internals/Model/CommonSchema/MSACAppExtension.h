// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACModel.h"
#import "MSACSerializableObject.h"

static NSString *const kMSACAppId = @"id";
static NSString *const kMSACAppLocale = @"locale";
static NSString *const kMSACAppName = @"name";
static NSString *const kMSACAppVer = @"ver";
static NSString *const kMSACAppUserId = @"userId";

/**
 * The App extension contains data specified by the application.
 */
@interface MSACAppExtension : NSObject <MSACSerializableObject, MSACModel>

/**
 * The application's bundle identifier.
 */
@property(nonatomic, copy) NSString *appId;

/**
 * The application's version.
 */
@property(nonatomic, copy) NSString *ver;

/**
 * The application's name.
 */
@property(nonatomic, copy) NSString *name;

/**
 * The application's locale.
 */
@property(nonatomic, copy) NSString *locale;

/**
 * The application's userId.
 */
@property(nonatomic, copy) NSString *userId;

@end
