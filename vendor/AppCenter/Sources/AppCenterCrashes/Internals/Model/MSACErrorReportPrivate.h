// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACErrorReport.h"

static NSString *const kMSACErrorReportKillSignal = @"SIGKILL";

@interface MSACErrorReport ()

- (instancetype)initWithErrorId:(NSString *)errorId
                    reporterKey:(NSString *)reporterKey
                         signal:(NSString *)signal
                  exceptionName:(NSString *)exceptionName
                exceptionReason:(NSString *)exceptionReason
                   appStartTime:(NSDate *)appStartTime
                   appErrorTime:(NSDate *)appErrorTime
                         device:(MSACDevice *)device
           appProcessIdentifier:(NSUInteger)appProcessIdentifier;

@end
