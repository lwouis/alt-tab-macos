// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACLoggerInternal.h"

@implementation MSACLogger

static MSACLogLevel _currentLogLevel = MSACLogLevelAssert;
static MSACLogHandler currentLogHandler;
static BOOL _isUserDefinedLogLevel = NO;

MSACLogHandler const msDefaultLogHandler = ^(MSACLogMessageProvider messageProvider, MSACLogLevel logLevel, NSString *tag,
                                             __attribute__((unused)) const char *file, const char *function, uint line) {
  if (messageProvider) {
    if (_currentLogLevel > logLevel) {
      return;
    }
    NSString *level;
    switch (logLevel) {
    case MSACLogLevelVerbose:
      level = @"VERBOSE";
      break;
    case MSACLogLevelDebug:
      level = @"DEBUG";
      break;
    case MSACLogLevelInfo:
      level = @"INFO";
      break;
    case MSACLogLevelWarning:
      level = @"WARNING";
      break;
    case MSACLogLevelError:
      level = @"ERROR";
      break;
    case MSACLogLevelAssert:
      level = @"ASSERT";
      break;
    case MSACLogLevelNone:
      return;
    }
    NSLog(@"[%@] %@: %@/%d %@", tag, level, [NSString stringWithCString:function encoding:NSUTF8StringEncoding], line, messageProvider());
  }
};

+ (void)initialize {
  currentLogHandler = msDefaultLogHandler;
}

+ (MSACLogLevel)currentLogLevel {
  @synchronized(self) {
    return _currentLogLevel;
  }
}

+ (MSACLogHandler)logHandler {
  @synchronized(self) {
    return currentLogHandler;
  }
}

+ (void)setCurrentLogLevel:(MSACLogLevel)currentLogLevel {
  @synchronized(self) {
    _isUserDefinedLogLevel = YES;
    _currentLogLevel = currentLogLevel;
  }
}

+ (void)setLogHandler:(MSACLogHandler)logHandler {
  @synchronized(self) {
    _isUserDefinedLogLevel = YES;
    currentLogHandler = logHandler;
  }
}

+ (void)logMessage:(MSACLogMessageProvider)messageProvider
             level:(MSACLogLevel)loglevel
               tag:(NSString *)tag
              file:(const char *)file
          function:(const char *)function
              line:(uint)line {
  if (currentLogHandler) {
    currentLogHandler(messageProvider, loglevel, tag, file, function, line);
  }
}

+ (BOOL)isUserDefinedLogLevel {
  return _isUserDefinedLogLevel;
}

+ (void)setIsUserDefinedLogLevel:(BOOL)isUserDefinedLogLevel {
  _isUserDefinedLogLevel = isUserDefinedLogLevel;
}

@end
