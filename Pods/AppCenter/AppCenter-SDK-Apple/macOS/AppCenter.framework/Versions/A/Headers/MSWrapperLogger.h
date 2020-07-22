// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSConstants.h"

/**
 * This is a utility for producing App Center style log messages. It is only intended for use by App Center services and wrapper SDKs of App
 * Center.
 */
@interface MSWrapperLogger : NSObject

+ (void)MSWrapperLog:(MSLogMessageProvider)message tag:(NSString *)tag level:(MSLogLevel)level;

@end
