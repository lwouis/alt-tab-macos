// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#ifndef MSAC_LOGGER
#define MSAC_LOGGER

#if __has_include(<AppCenter/MSACConstants.h>)
#import <AppCenter/MSACConstants.h>
#else
#import "MSACConstants.h"
#endif

#define MSACLog(_level, _tag, _message)                                                                                                    \
  [MSACLogger logMessage:_message level:_level tag:_tag file:__FILE__ function:__PRETTY_FUNCTION__ line:__LINE__]
#define MSACLogAssert(tag, format, ...)                                                                                                    \
  MSACLog(MSACLogLevelAssert, tag, (^{                                                                                                     \
            return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                    \
          }))
#define MSACLogError(tag, format, ...)                                                                                                     \
  MSACLog(MSACLogLevelError, tag, (^{                                                                                                      \
            return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                    \
          }))
#define MSACLogWarning(tag, format, ...)                                                                                                   \
  MSACLog(MSACLogLevelWarning, tag, (^{                                                                                                    \
            return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                    \
          }))
#define MSACLogInfo(tag, format, ...)                                                                                                      \
  MSACLog(MSACLogLevelInfo, tag, (^{                                                                                                       \
            return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                    \
          }))
#define MSACLogDebug(tag, format, ...)                                                                                                     \
  MSACLog(MSACLogLevelDebug, tag, (^{                                                                                                      \
            return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                    \
          }))
#define MSACLogVerbose(tag, format, ...)                                                                                                   \
  MSACLog(MSACLogLevelVerbose, tag, (^{                                                                                                    \
            return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                    \
          }))

NS_SWIFT_NAME(Logger)
@interface MSACLogger : NSObject

+ (void)logMessage:(MSACLogMessageProvider)messageProvider
             level:(MSACLogLevel)loglevel
               tag:(NSString *)tag
              file:(const char *)file
          function:(const char *)function
              line:(uint)line;

@end

#endif
