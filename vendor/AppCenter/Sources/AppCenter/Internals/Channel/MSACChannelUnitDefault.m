// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACChannelUnitDefault.h"
#import "MSACAbstractLogInternal.h"
#import "MSACAppCenterErrors.h"
#import "MSACAppCenterIngestion.h"
#import "MSACAppCenterInternal.h"
#import "MSACChannelUnitConfiguration.h"
#import "MSACChannelUnitDefaultPrivate.h"
#import "MSACDeviceTracker.h"
#import "MSACStorage.h"
#import "MSACUtility+StringFormatting.h"

/**
 * Key for the start timestamp.
 */
static NSString *const kMSACStartTimestampPrefix = @"ChannelStartTimer";

@implementation MSACChannelUnitDefault

@synthesize configuration = _configuration;
@synthesize logsDispatchQueue = _logsDispatchQueue;

#pragma mark - Initialization

- (instancetype)init {
  if ((self = [super init])) {
    _itemsCount = 0;
    _pendingBatchIds = [NSMutableArray new];
    _pendingBatchQueueFull = NO;
    _availableBatchFromStorage = NO;
    _enabled = YES;
    _paused = NO;
    _discardLogs = NO;
    _delegates = [NSHashTable weakObjectsHashTable];
    _pausedIdentifyingObjects = [NSHashTable weakObjectsHashTable];
    _pausedTargetKeys = [NSMutableSet new];
  }
  return self;
}

- (instancetype)initWithIngestion:(nullable id<MSACIngestionProtocol>)ingestion
                          storage:(id<MSACStorage>)storage
                    configuration:(MSACChannelUnitConfiguration *)configuration
                logsDispatchQueue:(dispatch_queue_t)logsDispatchQueue {
  if ((self = [self init])) {
    _ingestion = ingestion;
    _storage = storage;
    _configuration = configuration;
    _logsDispatchQueue = logsDispatchQueue;
  }
  return self;
}

#pragma mark - MSACChannelDelegate

- (void)addDelegate:(id<MSACChannelDelegate>)delegate {
  dispatch_async(self.logsDispatchQueue, ^{
    @synchronized(self.delegates) {
      [self.delegates addObject:delegate];
    }
  });
}

- (void)removeDelegate:(id<MSACChannelDelegate>)delegate {
  dispatch_async(self.logsDispatchQueue, ^{
    @synchronized(self.delegates) {
      [self.delegates removeObject:delegate];
    }
  });
}

#pragma mark - Managing queue

- (void)enqueueItem:(id<MSACLog>)item flags:(MSACFlags)flags {

  /*
   * Set common log info.
   * Only add timestamp and device info in case the log doesn't have one. In case the log is restored after a crash or for crashes, we don't
   * want the timestamp and the device information to be updated but want the old one preserved.
   */
  if (item && !item.timestamp) {
    item.timestamp = [NSDate date];
  }
  if (item && !item.device) {
    item.device = [[MSACDeviceTracker sharedInstance] device];
  }
  if (!item || ![item isValid]) {
    MSACLogWarning([MSACAppCenter logTag], @"Log is not valid.");
    return;
  }

  // Internal ID to keep track of logs between modules.
  NSString *internalLogId = MSAC_UUID_STRING;

  @autoreleasepool {

    // Additional preparations for the log. Used to specify the session id and distribution group id.
    [self enumerateDelegatesForSelector:@selector(channel:prepareLog:)
                              withBlock:^(id<MSACChannelDelegate> delegate) {
                                [delegate channel:self prepareLog:item];
                              }];

    // Notify delegate about enqueuing as fast as possible on the current thread.
    [self enumerateDelegatesForSelector:@selector(channel:didPrepareLog:internalId:flags:)
                              withBlock:^(id<MSACChannelDelegate> delegate) {
                                [delegate channel:self didPrepareLog:item internalId:internalLogId flags:flags];
                              }];
  }

  // Return fast in case our item is empty or we are discarding logs right now.
  dispatch_async(self.logsDispatchQueue, ^{
    // Use separate autorelease pool for enqueuing logs.
    @autoreleasepool {

      // Check if the log should be filtered out. If so, don't enqueue it.
      __block BOOL shouldFilter = NO;
      [self enumerateDelegatesForSelector:@selector(channelUnit:shouldFilterLog:)
                                withBlock:^(id<MSACChannelDelegate> delegate) {
                                  shouldFilter = shouldFilter || [delegate channelUnit:self shouldFilterLog:item];
                                }];
      if (shouldFilter) {
        MSACLogDebug([MSACAppCenter logTag], @"Log of type '%@' was filtered out by delegate(s)", item.type);
        [self enumerateDelegatesForSelector:@selector(channel:didCompleteEnqueueingLog:internalId:)
                                  withBlock:^(id<MSACChannelDelegate> delegate) {
                                    [delegate channel:self didCompleteEnqueueingLog:item internalId:internalLogId];
                                  }];
        return;
      }
      if (!self.ingestion.isReadyToSend) {
        MSACLogDebug([MSACAppCenter logTag], @"Log of type '%@' was not filtered out by delegate(s) but ingestion is not ready to send it.",
                     item.type);
        [self enumerateDelegatesForSelector:@selector(channel:didCompleteEnqueueingLog:internalId:)
                                  withBlock:^(id<MSACChannelDelegate> delegate) {
                                    [delegate channel:self didCompleteEnqueueingLog:item internalId:internalLogId];
                                  }];
        return;
      }
      if (self.discardLogs) {
        MSACLogWarning([MSACAppCenter logTag], @"Channel %@ disabled in log discarding mode, discard this log.",
                       self.configuration.groupId);
        NSError *error = [NSError errorWithDomain:kMSACACErrorDomain
                                             code:MSACACConnectionPausedErrorCode
                                         userInfo:@{NSLocalizedDescriptionKey : kMSACACConnectionPausedErrorDesc}];
        [self notifyFailureBeforeSendingForItem:item withError:error];
        [self enumerateDelegatesForSelector:@selector(channel:didCompleteEnqueueingLog:internalId:)
                                  withBlock:^(id<MSACChannelDelegate> delegate) {
                                    [delegate channel:self didCompleteEnqueueingLog:item internalId:internalLogId];
                                  }];
        return;
      }

      // Save the log first.
      MSACLogDebug([MSACAppCenter logTag], @"Saving log, type: %@, flags: %u.", item.type, (unsigned int)flags);
      bool success = [self.storage saveLog:item withGroupId:self.configuration.groupId flags:flags];

      // Notify delegates of completion (whatever the result is).
      [self enumerateDelegatesForSelector:@selector(channel:didCompleteEnqueueingLog:internalId:)
                                withBlock:^(id<MSACChannelDelegate> delegate) {
                                  [delegate channel:self didCompleteEnqueueingLog:item internalId:internalLogId];
                                }];

      // If successful, check if logs can be sent now.
      if (success) {
        self.itemsCount += 1;
        [self checkPendingLogs];
      }
    }
  });
}

- (void)sendLogContainer:(MSACLogContainer *__nonnull)container {

  // Add to pending batches.
  [self.pendingBatchIds addObject:container.batchId];
  if (self.pendingBatchIds.count >= self.configuration.pendingBatchesLimit) {

    // The maximum number of batches forwarded to the ingestion at the same time has been reached.
    self.pendingBatchQueueFull = YES;
  }

  // Optimization. If the current log level is greater than
  // MSACLogLevelDebug, we can skip it.
  if ([MSACAppCenter logLevel] <= MSACLogLevelDebug) {
    NSUInteger count = [container.logs count];
    for (NSUInteger i = 0; i < count; i++) {
      MSACLogDebug([MSACAppCenter logTag], @"Sending %tu/%tu log, group Id: %@, batch Id: %@, session Id: %@, payload:\n%@", (i + 1), count,
                   self.configuration.groupId, container.batchId, container.logs[i].sid,
                   [(MSACAbstractLog *)container.logs[i] serializeLogWithPrettyPrinting:YES]);
    }
  }

  // Notify delegates.
  [self enumerateDelegatesForSelector:@selector(channel:willSendLog:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              for (id<MSACLog> aLog in container.logs) {
                                [delegate channel:self willSendLog:aLog];
                              }
                            }];

  // Forward logs to the ingestion.
  [self.ingestion sendAsync:container
          completionHandler:^(NSString *ingestionBatchId, NSHTTPURLResponse *response, __unused NSData *data, NSError *error) {
            dispatch_async(self.logsDispatchQueue, ^{
              if (![self.pendingBatchIds containsObject:ingestionBatchId]) {
                MSACLogWarning([MSACAppCenter logTag], @"Batch Id %@ not expected, ignore.", ingestionBatchId);
                return;
              }
              BOOL succeeded = [MSACHttpUtil isSuccessStatusCode:response.statusCode];
              if (succeeded) {
                MSACLogDebug([MSACAppCenter logTag], @"Log(s) sent with success, batch Id:%@.", ingestionBatchId);

                // Notify delegates.
                [self enumerateDelegatesForSelector:@selector(channel:didSucceedSendingLog:)
                                          withBlock:^(id<MSACChannelDelegate> delegate) {
                                            for (id<MSACLog> aLog in container.logs) {
                                              [delegate channel:self didSucceedSendingLog:aLog];
                                            }
                                          }];

                // Remove the logs from storage.
                [self.storage deleteLogsWithBatchId:ingestionBatchId groupId:self.configuration.groupId];
              }

              // Failure.
              else {
                MSACLogError([MSACAppCenter logTag], @"Log(s) sent with failure, batch Id:%@, status code:%tu", ingestionBatchId,
                             response.statusCode);

                // Notify delegates.
                [self enumerateDelegatesForSelector:@selector(channel:didFailSendingLog:withError:)
                                          withBlock:^(id<MSACChannelDelegate> delegate) {
                                            for (id<MSACLog> aLog in container.logs) {
                                              [delegate channel:self didFailSendingLog:aLog withError:error];
                                            }
                                          }];

                // Disable and delete all data on fatal error.
                if (![MSACHttpUtil isRecoverableError:response.statusCode]) {
                  MSACLogError([MSACAppCenter logTag], @"Fatal error encountered; shutting down channel unit with group ID %@",
                               self.configuration.groupId);
                  [self setEnabled:NO andDeleteDataOnDisabled:YES];
                  return;
                }
              }

              // Remove from pending batches.
              [self.pendingBatchIds removeObject:ingestionBatchId];

              // Update pending batch queue state.
              if (self.pendingBatchQueueFull && self.pendingBatchIds.count < self.configuration.pendingBatchesLimit) {
                self.pendingBatchQueueFull = NO;

                if (succeeded && self.availableBatchFromStorage) {
                  [self flushQueue];
                }
              }
            });
          }];
}

- (void)flushQueue {

  // Nothing to flush if there is no ingestion.
  if (!self.ingestion || !self.ingestion.isEnabled) {
    MSACLogDebug([MSACAppCenter logTag], @"AppCenter SDK is offline, groupId:%@.", self.configuration.groupId);
    return;
  }

  // Don't flush while disabled.
  if (!self.enabled) {
    return;
  }

  // Ingestion is not ready.
  if (!self.ingestion.isReadyToSend) {
    return;
  }

  // Cancel any timer.
  [self resetTimer];

  // Don't flush while paused or if pending bach queue is full.
  if (self.paused || self.pendingBatchQueueFull) {

    // Still close the current batch it will be flushed later.
    if (self.itemsCount >= self.configuration.batchSizeLimit) {

      // That batch becomes available.
      self.availableBatchFromStorage = YES;
      self.itemsCount = 0;
    }
    return;
  }

  // Reset item count and load data from the storage.
  self.itemsCount = 0;

  // NOTE: It isn't async operation, completion handler will be called immediately.
  self.availableBatchFromStorage = [self.storage loadLogsWithGroupId:self.configuration.groupId
                                                               limit:self.configuration.batchSizeLimit
                                                  excludedTargetKeys:[self.pausedTargetKeys allObjects]
                                                   completionHandler:^(NSArray<id<MSACLog>> *_Nonnull logArray, NSString *batchId) {
                                                     // Check if there is data to send. Logs may be deleted from storage before this flush.
                                                     if (logArray.count > 0) {
                                                       MSACLogContainer *container = [[MSACLogContainer alloc] initWithBatchId:batchId
                                                                                                                       andLogs:logArray];
                                                       [self sendLogContainer:container];
                                                     }
                                                   }];

  // Flush again if there is another batch to send.
  if (self.availableBatchFromStorage && !self.pendingBatchQueueFull) {
    [self flushQueue];
  }
}

- (void)checkPendingLogs {

  // If the interval is default and we reached batchSizeLimit flush logs now.
  if (!self.paused && self.configuration.flushInterval == kMSACFlushIntervalDefault &&
      self.itemsCount >= self.configuration.batchSizeLimit) {
    [self flushQueue];
  } else if (self.itemsCount > 0) {
    NSUInteger flushInterval = [self resolveFlushInterval];

    // Skip sending logs if the channel is paused.
    if (self.paused) {
      return;
    }

    // If the interval is over, send all logs without any additional timers.
    if (flushInterval == 0) {
      [self flushQueue];
    }

    // Postpone sending logs.
    else {
      [self startTimer:flushInterval];
    }
  }
}

#pragma mark - Timer

- (void)startTimer:(NSUInteger)flushInterval {

  // Don't start timer while disabled.
  if (!self.enabled) {
    return;
  }

  // Cancel any timer.
  [self resetTimer];

  // Create new timer.
  self.timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.logsDispatchQueue);

  /**
   * Cast (NSEC_PER_SEC * flushInterval) to (int64_t) silence warning. The compiler otherwise complains that we're using
   * a float param (flushInterval) and implicitly downcast to int64_t.
   */
  dispatch_source_set_timer(self.timerSource, dispatch_walltime(NULL, (int64_t)(NSEC_PER_SEC * flushInterval)), 1ull * NSEC_PER_SEC,
                            1ull * NSEC_PER_SEC);
  __weak typeof(self) weakSelf = self;
  dispatch_source_set_event_handler(self.timerSource, ^{
    typeof(self) strongSelf = weakSelf;

    // Flush the queue as needed.
    if (strongSelf) {
      if (strongSelf.itemsCount > 0) {
        [strongSelf flushQueue];
      }
      [strongSelf resetTimer];

      // Remove the current timestamp. All pending logs will be sent in flushQueue call.
      [MSAC_APP_CENTER_USER_DEFAULTS removeObjectForKey:[strongSelf oldestPendingLogTimestampKey]];
    }
  });
  dispatch_resume(self.timerSource);
}

- (NSUInteger)resolveFlushInterval {
  NSUInteger flushInterval = self.configuration.flushInterval;

  // If the interval is custom.
  if (flushInterval > kMSACFlushIntervalDefault) {
    NSDate *now = [NSDate date];
    NSDate *oldestPendingLogTimestamp = [MSAC_APP_CENTER_USER_DEFAULTS objectForKey:[self oldestPendingLogTimestampKey]];

    // The timer isn't started or has invalid value (start time in the future), so start it and store the current time.
    if (oldestPendingLogTimestamp == nil || [now compare:oldestPendingLogTimestamp] == NSOrderedAscending) {
      [MSAC_APP_CENTER_USER_DEFAULTS setObject:now forKey:[self oldestPendingLogTimestampKey]];
    }

    // If the interval is over.
    else if ([now compare:[oldestPendingLogTimestamp dateByAddingTimeInterval:flushInterval]] == NSOrderedDescending) {
      [MSAC_APP_CENTER_USER_DEFAULTS removeObjectForKey:[self oldestPendingLogTimestampKey]];
      return 0;
    }

    // We still have to wait for the rest of the interval.
    else {
      flushInterval -= (NSUInteger)[now timeIntervalSinceDate:oldestPendingLogTimestamp];
    }
  }
  return flushInterval;
}

- (NSString *)oldestPendingLogTimestampKey {
  return [NSString stringWithFormat:@"%@:%@", kMSACStartTimestampPrefix, self.configuration.groupId];
}

- (void)resetTimer {
  if (self.timerSource) {
    dispatch_source_cancel(self.timerSource);
  }
}

#pragma mark - Life cycle

- (void)setEnabled:(BOOL)isEnabled andDeleteDataOnDisabled:(BOOL)deleteData {
  dispatch_async(self.logsDispatchQueue, ^{
    if (self.enabled != isEnabled) {
      self.enabled = isEnabled;
      if (isEnabled) {
        [self resumeWithIdentifyingObjectSync:self];
      } else {
        [self pauseWithIdentifyingObjectSync:self];
      }
    }

    // Even if it's already disabled we might also want to delete logs this time.
    if (!isEnabled && deleteData) {
      MSACLogDebug([MSACAppCenter logTag], @"Delete all logs for group Id %@", self.configuration.groupId);
      NSError *error = [NSError errorWithDomain:kMSACACErrorDomain
                                           code:MSACACConnectionPausedErrorCode
                                       userInfo:@{NSLocalizedDescriptionKey : kMSACACConnectionPausedErrorDesc}];
      [self deleteAllLogsWithErrorSync:error];

      // Reset states.
      self.itemsCount = 0;
      self.availableBatchFromStorage = NO;
      self.pendingBatchQueueFull = NO;
      [MSAC_APP_CENTER_USER_DEFAULTS removeObjectForKey:[self oldestPendingLogTimestampKey]];

      // Prevent further logs from being persisted.
      self.discardLogs = YES;
    } else {

      // Allow logs to be persisted.
      self.discardLogs = NO;
    }

    // Notify delegates.
    [self enumerateDelegatesForSelector:@selector(channel:didSetEnabled:andDeleteDataOnDisabled:)
                              withBlock:^(id<MSACChannelDelegate> delegate) {
                                [delegate channel:self didSetEnabled:isEnabled andDeleteDataOnDisabled:deleteData];
                              }];
  });
}

- (void)pauseWithIdentifyingObject:(id<NSObject>)identifyingObject {
  dispatch_async(self.logsDispatchQueue, ^{
    [self pauseWithIdentifyingObjectSync:identifyingObject];
  });
}

- (void)resumeWithIdentifyingObject:(id<NSObject>)identifyingObject {
  dispatch_async(self.logsDispatchQueue, ^{
    [self resumeWithIdentifyingObjectSync:identifyingObject];
  });
}

- (void)pauseWithIdentifyingObjectSync:(id<NSObject>)identifyingObject {
  [self.pausedIdentifyingObjects addObject:identifyingObject];
  MSACLogVerbose([MSACAppCenter logTag], @"Identifying object %@ added to pause lane for channel %@.", identifyingObject,
                 self.configuration.groupId);
  if (!self.paused) {
    MSACLogDebug([MSACAppCenter logTag], @"Pause channel %@.", self.configuration.groupId);
    self.paused = YES;
    [self resetTimer];
  }
  [self enumerateDelegatesForSelector:@selector(channel:didPauseWithIdentifyingObject:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:self didPauseWithIdentifyingObject:identifyingObject];
                            }];
}

- (void)resumeWithIdentifyingObjectSync:(id<NSObject>)identifyingObject {
  [self.pausedIdentifyingObjects removeObject:identifyingObject];
  MSACLogVerbose([MSACAppCenter logTag], @"Identifying object %@ removed from pause lane for channel %@.", identifyingObject,
                 self.configuration.groupId);
  if ([self.pausedIdentifyingObjects count] == 0) {
    MSACLogDebug([MSACAppCenter logTag], @"Resume channel %@.", self.configuration.groupId);
    self.paused = NO;
    [self checkPendingLogs];
  }
  [self enumerateDelegatesForSelector:@selector(channel:didResumeWithIdentifyingObject:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:self didResumeWithIdentifyingObject:identifyingObject];
                            }];
}

- (void)pauseSendingLogsWithToken:(NSString *)token {
  NSString *targetKey = [MSACUtility targetKeyFromTargetToken:token];
  dispatch_async(self.logsDispatchQueue, ^{
    MSACLogDebug([MSACAppCenter logTag], @"Pause channel for target key %@.", targetKey);
    [self.pausedTargetKeys addObject:targetKey];
  });
}

- (void)resumeSendingLogsWithToken:(NSString *)token {
  NSString *targetKey = [MSACUtility targetKeyFromTargetToken:token];
  dispatch_async(self.logsDispatchQueue, ^{
    MSACLogDebug([MSACAppCenter logTag], @"Resume channel for target key %@.", targetKey);
    [self.pausedTargetKeys removeObject:targetKey];

    // Update item count and check logs if it meets the conditions to send logs.
    // This solution is not ideal since it might create a batch with fewer logs than expected as the log count contains logs with paused
    // keys, this would be an optimization that doesn't seem necessary for now. Aligned with Android implementation.
    self.itemsCount = [self.storage countLogs];
    [self checkPendingLogs];
  });
}

#pragma mark - Storage

- (void)deleteAllLogsWithError:(NSError *)error {
  dispatch_async(self.logsDispatchQueue, ^{
    [self deleteAllLogsWithErrorSync:error];
  });
}

- (void)deleteAllLogsWithErrorSync:(NSError *)error {
  NSArray<id<MSACLog>> *deletedLogs;

  // Delete pending batches first.
  for (NSString *batchId in self.pendingBatchIds) {
    [self.storage deleteLogsWithBatchId:batchId groupId:self.configuration.groupId];
  }
  [self.pendingBatchIds removeAllObjects];

  // Delete remaining logs.
  deletedLogs = [self.storage deleteLogsWithGroupId:self.configuration.groupId];

  // Notify failure of remaining logs.
  for (id<MSACLog> log in deletedLogs) {
    [self notifyFailureBeforeSendingForItem:log withError:error];
  }
}

#pragma mark - Helper

- (void)enumerateDelegatesForSelector:(SEL)selector withBlock:(void (^)(id<MSACChannelDelegate> delegate))block {
  NSArray *synchronizedDelegates;
  @synchronized(self.delegates) {

    // Don't execute the block while locking; it might be locking too and deadlock ourselves.
    synchronizedDelegates = [self.delegates allObjects];
  }
  for (id<MSACChannelDelegate> delegate in synchronizedDelegates) {
    if ([delegate respondsToSelector:selector]) {
      block(delegate);
    }
  }
}

- (void)notifyFailureBeforeSendingForItem:(id<MSACLog>)item withError:(nullable NSError *)error {
  NSArray *synchronizedDelegates;
  @synchronized(self.delegates) {

    // Don't execute the block while locking; it might be locking too and deadlock ourselves.
    synchronizedDelegates = [self.delegates allObjects];
  }
  for (id<MSACChannelDelegate> delegate in synchronizedDelegates) {

    // Call willSendLog before didFailSendingLog
    if ([delegate respondsToSelector:@selector(channel:willSendLog:)]) {
      [delegate channel:self willSendLog:item];
    }

    // Call didFailSendingLog
    if ([delegate respondsToSelector:@selector(channel:didFailSendingLog:withError:)]) {
      [delegate channel:self didFailSendingLog:item withError:error];
    }
  }
}

@end
