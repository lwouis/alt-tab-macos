// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACWrapperLogger.h"
#import "MSACLogger.h"

@implementation MSACWrapperLogger

+ (void)MSACWrapperLog:(MSACLogMessageProvider)message tag:(NSString *)tag level:(MSACLogLevel)level {
  MSACLog(level, tag, message);
}

@end
