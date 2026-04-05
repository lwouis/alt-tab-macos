// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@class MSACAppleErrorLog;
@class MSACErrorReport;
@class PLCrashReport;

/**
 *  Error logging error domain
 */
typedef NS_ENUM(NSInteger, MSACBinaryImageType) {

  /**
   *  App binary
   */
  MSACBinaryImageTypeAppBinary,

  /**
   *  App provided framework
   */
  MSACBinaryImageTypeAppFramework,

  /**
   *  Image not related to the app
   */
  MSACBinaryImageTypeOther
};

@interface MSACErrorLogFormatter : NSObject

+ (MSACAppleErrorLog *)errorLogFromCrashReport:(PLCrashReport *)report;

+ (MSACErrorReport *)errorReportFromCrashReport:(PLCrashReport *)report;

+ (MSACErrorReport *)errorReportFromLog:(MSACAppleErrorLog *)errorLog;

@end
