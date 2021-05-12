// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#if __has_include(<AppCenter/MSACConstants.h>)
#import <AppCenter/MSACConstants.h>
#else
#import "MSACConstants.h"
#endif

/**
 * This is a utility for producing App Center style log messages. It is only intended for use by App Center services and wrapper SDKs of App
 * Center.
 */
NS_SWIFT_NAME(WrapperLogger)
@interface MSACWrapperLogger : NSObject

+ (void)MSACWrapperLog:(MSACLogMessageProvider)message tag:(NSString *)tag level:(MSACLogLevel)level;

@end
