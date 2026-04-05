// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACErrorReport.h"
#import "MSACErrorReportPrivate.h"

@interface MSACErrorReport ()

@property(nonatomic, copy) NSString *signal;

@end

@implementation MSACErrorReport

- (instancetype)initWithErrorId:(NSString *)errorId
                    reporterKey:(NSString *)reporterKey
                         signal:(NSString *)signal
                  exceptionName:(NSString *)exceptionName
                exceptionReason:(NSString *)exceptionReason
                   appStartTime:(NSDate *)appStartTime
                   appErrorTime:(NSDate *)appErrorTime
                         device:(MSACDevice *)device
           appProcessIdentifier:(NSUInteger)appProcessIdentifier {

  if ((self = [super init])) {
    _incidentIdentifier = errorId;
    _reporterKey = reporterKey;
    _signal = signal;
    _exceptionName = exceptionName;
    _exceptionReason = exceptionReason;
    _appStartTime = appStartTime;
    _appErrorTime = appErrorTime;
    _device = device;
    _appProcessIdentifier = appProcessIdentifier;
  }
  return self;
}

- (BOOL)isAppKill {
  BOOL result = NO;

  if (self.signal && [[self.signal uppercaseString] isEqualToString:kMSACErrorReportKillSignal])
    result = YES;

  return result;
}

@end
