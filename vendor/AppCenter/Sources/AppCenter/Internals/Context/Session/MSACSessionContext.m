// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppCenterInternal.h"
#import "MSACLogger.h"
#import "MSACSessionContextPrivate.h"
#import "MSACUtility.h"

/**
 * Storage key for history data.
 */
static NSString *const kMSACSessionIdHistoryKey = @"SessionIdHistory";

/**
 * Singleton.
 */
static MSACSessionContext *sharedInstance;
static dispatch_once_t onceToken;

@implementation MSACSessionContext

+ (instancetype)sharedInstance {
  dispatch_once(&onceToken, ^{
    if (sharedInstance == nil) {
      sharedInstance = [[MSACSessionContext alloc] init];
    }
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    NSData *data = [MSAC_APP_CENTER_USER_DEFAULTS objectForKey:kMSACSessionIdHistoryKey];
    if (data != nil) {
      _sessionHistory = (NSMutableArray *)[[MSACUtility unarchiveKeyedData:data] mutableCopy];
    }
    if (!_sessionHistory) {
      _sessionHistory = [NSMutableArray<MSACSessionHistoryInfo *> new];
    }
    NSUInteger count = [_sessionHistory count];
    MSACLogDebug([MSACAppCenter logTag], @"%tu session(s) in the history.", count);
    _currentSessionInfo = [[MSACSessionHistoryInfo alloc] initWithTimestamp:[NSDate date] andSessionId:nil];
    [_sessionHistory addObject:_currentSessionInfo];
  }
  return self;
}

+ (void)resetSharedInstance {
  onceToken = 0;
  sharedInstance = nil;
}

- (NSString *)sessionId {
  return [self currentSessionInfo].sessionId;
}

- (void)setSessionId:(nullable NSString *)sessionId {
  @synchronized(self) {
    [self.sessionHistory removeLastObject];
    self.currentSessionInfo.sessionId = sessionId;
    self.currentSessionInfo.timestamp = [NSDate date];
    [self.sessionHistory addObject:self.currentSessionInfo];
    [MSAC_APP_CENTER_USER_DEFAULTS setObject:[MSACUtility archiveKeyedData:self.sessionHistory] forKey:kMSACSessionIdHistoryKey];
    MSACLogVerbose([MSACAppCenter logTag], @"Stored new session with id:%@ and timestamp: %@.", self.currentSessionInfo.sessionId,
                   self.currentSessionInfo.timestamp);
  }
}

- (nullable NSString *)sessionIdAt:(NSDate *)date {
  @synchronized(self) {
    for (MSACSessionHistoryInfo *info in [self.sessionHistory reverseObjectEnumerator]) {
      if ([info.timestamp compare:date] == NSOrderedAscending) {
        return info.sessionId;
      }
    }
    return nil;
  }
}

- (void)clearSessionHistoryAndKeepCurrentSession:(BOOL)keepCurrentSession {
  @synchronized(self) {
    [self.sessionHistory removeAllObjects];
    if (keepCurrentSession) {
      [self.sessionHistory addObject:self.currentSessionInfo];
    }
    [MSAC_APP_CENTER_USER_DEFAULTS setObject:[MSACUtility archiveKeyedData:self.sessionHistory] forKey:kMSACSessionIdHistoryKey];
    MSACLogVerbose([MSACAppCenter logTag], @"Cleared old sessions.");
  }
}

@end
