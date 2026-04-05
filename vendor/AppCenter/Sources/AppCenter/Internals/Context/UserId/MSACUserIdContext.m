// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppCenterInternal.h"
#import "MSACConstants+Internal.h"
#import "MSACLogger.h"
#import "MSACUserIdContextDelegate.h"
#import "MSACUserIdContextPrivate.h"
#import "MSACUtility.h"

/**
 * Maximum allowed length for user identifier for App Center server.
 */
static const int kMSACMaxUserIdLength = 256;

/*
 * Custom User ID prefix for Common Schema.
 */
static NSString *const kMSACUserIdCustomPrefix = @"c";

/**
 * User Id history key.
 */
static NSString *const kMSACUserIdHistoryKey = @"UserIdHistory";

/**
 * Singleton.
 */
static MSACUserIdContext *sharedInstance;
static dispatch_once_t onceToken;

@implementation MSACUserIdContext

+ (instancetype)sharedInstance {
  dispatch_once(&onceToken, ^{
    if (sharedInstance == nil) {
      sharedInstance = [[MSACUserIdContext alloc] init];
    }
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    NSData *data = [MSAC_APP_CENTER_USER_DEFAULTS objectForKey:kMSACUserIdHistoryKey];
    if (data != nil) {
      _userIdHistory = (NSMutableArray *)[[MSACUtility unarchiveKeyedData:data] mutableCopy];
    }
    if (!_userIdHistory) {
      _userIdHistory = [NSMutableArray<MSACUserIdHistoryInfo *> new];
    }
    NSUInteger count = [_userIdHistory count];
    MSACLogDebug([MSACAppCenter logTag], @"%tu userId(s) in the history.", count);

    // Set nil to current userId so that it can return nil for the userId between App Center start and setUserId call.
    _currentUserIdInfo = [[MSACUserIdHistoryInfo alloc] initWithTimestamp:[NSDate date] andUserId:nil];
    [_userIdHistory addObject:_currentUserIdInfo];

    /*
     * Persist nil userId as a current userId to NSUserDefaults so that Crashes can retrieve a correct userId when apps crash between App
     * Center start and setUserId call.
     */
    [MSAC_APP_CENTER_USER_DEFAULTS setObject:[MSACUtility archiveKeyedData:self.userIdHistory] forKey:kMSACUserIdHistoryKey];
    _delegates = [NSHashTable weakObjectsHashTable];
  }
  return self;
}

+ (void)resetSharedInstance {
  onceToken = 0;
  sharedInstance = nil;
}

- (NSString *)userId {
  return [self currentUserIdInfo].userId;
}

- (void)setUserId:(nullable NSString *)userId {
  NSArray *synchronizedDelegates;
  @synchronized(self) {
    BOOL sameUserId =
        (!userId && !self.currentUserIdInfo.userId) || (userId && [self.currentUserIdInfo.userId isEqualToString:(NSString *)userId]);
    if (sameUserId) {
      return;
    }
    self.currentUserIdInfo.timestamp = [NSDate date];
    self.currentUserIdInfo.userId = userId;

    /*
     * Replacing the last userId from history because the userId has changed within a same lifecycle without crashes.
     * The userId history is only used to correlate a crashes log with a userId, previous userId won't be used at all since there is no
     * crashes on apps between previous userId and current userId.
     */
    [self.userIdHistory removeLastObject];
    [self.userIdHistory addObject:self.currentUserIdInfo];
    [MSAC_APP_CENTER_USER_DEFAULTS setObject:[MSACUtility archiveKeyedData:self.userIdHistory] forKey:kMSACUserIdHistoryKey];
    MSACLogVerbose([MSACAppCenter logTag], @"Stored new userId:%@ and timestamp: %@.", self.currentUserIdInfo.userId,
                   self.currentUserIdInfo.timestamp);
    synchronizedDelegates = [self.delegates allObjects];
  }
  for (id<MSACUserIdContextDelegate> delegate in synchronizedDelegates) {
    if ([delegate respondsToSelector:@selector(userIdContext:didUpdateUserId:)]) {
      [delegate userIdContext:self didUpdateUserId:userId];
    }
  }
}

- (nullable NSString *)userIdAt:(NSDate *)date {
  @synchronized(self) {
    for (MSACUserIdHistoryInfo *info in [self.userIdHistory reverseObjectEnumerator]) {
      if ([info.timestamp compare:date] == NSOrderedAscending) {
        return info.userId;
      }
    }
    return nil;
  }
}

- (void)clearUserIdHistory {
  @synchronized(self) {
    [self.userIdHistory removeAllObjects];
    [self.userIdHistory addObject:self.currentUserIdInfo];
    [MSAC_APP_CENTER_USER_DEFAULTS setObject:[MSACUtility archiveKeyedData:self.userIdHistory] forKey:kMSACUserIdHistoryKey];
    MSACLogVerbose([MSACAppCenter logTag], @"Cleared old userIds while keeping current userId.");
  }
}

+ (BOOL)isUserIdValidForAppCenter:(nullable NSString *)userId {
  if (userId && userId.length > kMSACMaxUserIdLength) {
    MSACLogError([MSACAppCenter logTag], @"userId is limited to %d characters.", kMSACMaxUserIdLength);
    return NO;
  }
  return YES;
}

+ (BOOL)isUserIdValidForOneCollector:(nullable NSString *)userId {
  if (!userId) {
    return YES;
  }
  NSRange separator = [userId rangeOfString:kMSACCommonSchemaPrefixSeparator];
  if (userId.length == 0) {
    MSACLogError([MSACAppCenter logTag], @"userId must not be empty.");
    return NO;
  }
  if (separator.location != NSNotFound) {
    NSString *prefix = [userId substringToIndex:separator.location];
    if (![prefix isEqualToString:kMSACUserIdCustomPrefix]) {
      MSACLogError([MSACAppCenter logTag], @"userId prefix must be '%@', '%@' is not supported.", kMSACUserIdCustomPrefix, prefix);
      return NO;
    } else if (separator.location == userId.length - 1) {
      MSACLogError([MSACAppCenter logTag], @"userId must not be empty.");
      return NO;
    }
  }
  return YES;
}

+ (nullable NSString *)prefixedUserIdFromUserId:(nullable NSString *)userId {
  if (userId && [userId rangeOfString:kMSACCommonSchemaPrefixSeparator].location == NSNotFound) {
    return [NSString stringWithFormat:@"%@%@%@", kMSACUserIdCustomPrefix, kMSACCommonSchemaPrefixSeparator, userId];
  }
  return userId;
}

- (void)addDelegate:(id<MSACUserIdContextDelegate>)delegate {
  @synchronized(self) {
    [self.delegates addObject:delegate];
  }
}

- (void)removeDelegate:(id<MSACUserIdContextDelegate>)delegate {
  @synchronized(self) {
    [self.delegates removeObject:delegate];
  }
}

@end
