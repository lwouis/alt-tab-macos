// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSConstants.h"

#define MSLog(_level, _tag, _message)                                                                                                      \
  [MSLogger logMessage:_message level:_level tag:_tag file:__FILE__ function:__PRETTY_FUNCTION__ line:__LINE__]
#define MSLogAssert(tag, format, ...)                                                                                                      \
  MSLog(MSLogLevelAssert, tag, (^{                                                                                                         \
          return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                      \
        }))
#define MSLogError(tag, format, ...)                                                                                                       \
  MSLog(MSLogLevelError, tag, (^{                                                                                                          \
          return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                      \
        }))
#define MSLogWarning(tag, format, ...)                                                                                                     \
  MSLog(MSLogLevelWarning, tag, (^{                                                                                                        \
          return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                      \
        }))
#define MSLogInfo(tag, format, ...)                                                                                                        \
  MSLog(MSLogLevelInfo, tag, (^{                                                                                                           \
          return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                      \
        }))
#define MSLogDebug(tag, format, ...)                                                                                                       \
  MSLog(MSLogLevelDebug, tag, (^{                                                                                                          \
          return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                      \
        }))
#define MSLogVerbose(tag, format, ...)                                                                                                     \
  MSLog(MSLogLevelVerbose, tag, (^{                                                                                                        \
          return [NSString stringWithFormat:(format), ##__VA_ARGS__];                                                                      \
        }))

@interface MSLogger : NSObject

+ (void)logMessage:(MSLogMessageProvider)messageProvider
             level:(MSLogLevel)loglevel
               tag:(NSString *)tag
              file:(const char *)file
          function:(const char *)function
              line:(uint)line;

@end
