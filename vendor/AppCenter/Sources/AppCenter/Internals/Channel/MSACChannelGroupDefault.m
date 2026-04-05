// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACChannelGroupDefault.h"
#import "AppCenter+Internal.h"
#import "MSACAppCenterIngestion.h"
#import "MSACChannelGroupDefaultPrivate.h"
#import "MSACChannelUnitConfiguration.h"
#import "MSACChannelUnitDefault.h"
#import "MSACDispatcherUtil.h"
#import "MSACLogDBStorage.h"

static char *const kMSACLogsDispatchQueue = "com.microsoft.appcenter.ChannelGroupQueue";

@implementation MSACChannelGroupDefault

#pragma mark - Initialization

- (instancetype)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient installId:(NSUUID *)installId logUrl:(NSString *)logUrl {
  self = [self initWithIngestion:[[MSACAppCenterIngestion alloc] initWithHttpClient:httpClient
                                                                            baseUrl:logUrl
                                                                          installId:[installId UUIDString]]];
  return self;
}

- (instancetype)initWithIngestion:(nullable MSACAppCenterIngestion *)ingestion {
  if ((self = [self init])) {
    dispatch_queue_t serialQueue = dispatch_queue_create(kMSACLogsDispatchQueue, DISPATCH_QUEUE_SERIAL);
    _logsDispatchQueue = serialQueue;
    _channels = [NSMutableArray<id<MSACChannelUnitProtocol>> new];
    _delegates = [NSHashTable weakObjectsHashTable];
    _storage = [MSACLogDBStorage new];
    if (ingestion) {
      _ingestion = ingestion;
    }
  }
  return self;
}

- (id<MSACChannelUnitProtocol>)addChannelUnitWithConfiguration:(MSACChannelUnitConfiguration *)configuration {
  return [self addChannelUnitWithConfiguration:configuration withIngestion:self.ingestion];
}

- (id<MSACChannelUnitProtocol>)addChannelUnitWithConfiguration:(MSACChannelUnitConfiguration *)configuration
                                                 withIngestion:(nullable id<MSACIngestionProtocol>)ingestion {
  MSACChannelUnitDefault *channel;
  if (configuration) {
    channel = [[MSACChannelUnitDefault alloc] initWithIngestion:(ingestion ? ingestion : self.ingestion)
                                                        storage:self.storage
                                                  configuration:configuration
                                              logsDispatchQueue:self.logsDispatchQueue];
    [channel addDelegate:self];
    dispatch_async(self.logsDispatchQueue, ^{
      // Schedule sending any pending log.
      [channel checkPendingLogs];
    });
    [self.channels addObject:channel];
    [self enumerateDelegatesForSelector:@selector(channelGroup:didAddChannelUnit:)
                              withBlock:^(id<MSACChannelDelegate> channelDelegate) {
                                [channelDelegate channelGroup:self didAddChannelUnit:channel];
                              }];
  }
  return channel;
}

- (id<MSACChannelUnitProtocol>)channelUnitForGroupId:(NSString *)groupId {
  for (MSACChannelUnitDefault *channel in self.channels) {
    if ([channel.configuration.groupId isEqualToString:groupId]) {
      return channel;
    }
  }
  return nil;
}

#pragma mark - Delegate

- (void)addDelegate:(id<MSACChannelDelegate>)delegate {
  @synchronized(self) {
    [self.delegates addObject:delegate];
  }
}

- (void)removeDelegate:(id<MSACChannelDelegate>)delegate {
  @synchronized(self) {
    [self.delegates removeObject:delegate];
  }
}

- (void)enumerateDelegatesForSelector:(SEL)selector withBlock:(void (^)(id<MSACChannelDelegate> delegate))block {
  NSArray *synchronizedDelegates;
  @synchronized(self) {

    // Don't execute the block while locking; it might be locking too and deadlock ourselves.
    synchronizedDelegates = [self.delegates allObjects];
  }
  for (id<MSACChannelDelegate> delegate in synchronizedDelegates) {
    if ([delegate respondsToSelector:selector]) {
      block(delegate);
    }
  }
}

#pragma mark - Channel Delegate

- (void)channel:(id<MSACChannelProtocol>)channel prepareLog:(id<MSACLog>)log {
  [self enumerateDelegatesForSelector:@selector(channel:prepareLog:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:channel prepareLog:log];
                            }];
}

- (void)channel:(id<MSACChannelProtocol>)channel didPrepareLog:(id<MSACLog>)log internalId:(NSString *)internalId flags:(MSACFlags)flags {
  [self enumerateDelegatesForSelector:@selector(channel:didPrepareLog:internalId:flags:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:channel didPrepareLog:log internalId:internalId flags:flags];
                            }];
}

- (void)channel:(id<MSACChannelProtocol>)channel didCompleteEnqueueingLog:(id<MSACLog>)log internalId:(NSString *)internalId {
  [self enumerateDelegatesForSelector:@selector(channel:didCompleteEnqueueingLog:internalId:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:channel didCompleteEnqueueingLog:log internalId:internalId];
                            }];
}

- (void)channel:(id<MSACChannelProtocol>)channel willSendLog:(id<MSACLog>)log {
  [self enumerateDelegatesForSelector:@selector(channel:willSendLog:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:channel willSendLog:log];
                            }];
}

- (void)channel:(id<MSACChannelProtocol>)channel didSucceedSendingLog:(id<MSACLog>)log {
  [self enumerateDelegatesForSelector:@selector(channel:didSucceedSendingLog:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:channel didSucceedSendingLog:log];
                            }];
}

- (void)channel:(id<MSACChannelProtocol>)channel didSetEnabled:(BOOL)isEnabled andDeleteDataOnDisabled:(BOOL)deletedData {
  [self enumerateDelegatesForSelector:@selector(channel:didSetEnabled:andDeleteDataOnDisabled:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:channel didSetEnabled:isEnabled andDeleteDataOnDisabled:deletedData];
                            }];
}

- (void)channel:(id<MSACChannelProtocol>)channel didFailSendingLog:(id<MSACLog>)log withError:(nullable NSError *)error {
  [self enumerateDelegatesForSelector:@selector(channel:didFailSendingLog:withError:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:channel didFailSendingLog:log withError:error];
                            }];
}

- (BOOL)channelUnit:(id<MSACChannelUnitProtocol>)channelUnit shouldFilterLog:(id<MSACLog>)log {
  __block BOOL shouldFilter = NO;
  [self enumerateDelegatesForSelector:@selector(channelUnit:shouldFilterLog:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              shouldFilter = shouldFilter || [delegate channelUnit:channelUnit shouldFilterLog:log];
                            }];
  return shouldFilter;
}

- (void)channel:(id<MSACChannelProtocol>)channel didPauseWithIdentifyingObject:(id<NSObject>)identifyingObject {
  [self enumerateDelegatesForSelector:@selector(channel:didPauseWithIdentifyingObject:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:channel didPauseWithIdentifyingObject:identifyingObject];
                            }];
}

- (void)channel:(id<MSACChannelProtocol>)channel didResumeWithIdentifyingObject:(id<NSObject>)identifyingObject {
  [self enumerateDelegatesForSelector:@selector(channel:didResumeWithIdentifyingObject:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:channel didResumeWithIdentifyingObject:identifyingObject];
                            }];
}

#pragma mark - Enable / Disable

- (void)setEnabled:(BOOL)isEnabled andDeleteDataOnDisabled:(BOOL)deleteData {

#if !TARGET_OS_OSX
  if (isEnabled) {
    [MSAC_NOTIFICATION_CENTER addObserver:self
                                 selector:@selector(applicationWillTerminate:)
                                     name:UIApplicationWillTerminateNotification
                                   object:nil];
  } else {
    [MSAC_NOTIFICATION_CENTER removeObserver:self];
  }
#endif

  // Propagate to ingestion.
  [self.ingestion setEnabled:isEnabled andDeleteDataOnDisabled:deleteData];

  // Propagate to initialized channels.
  for (id<MSACChannelProtocol> channel in self.channels) {
    [channel setEnabled:isEnabled andDeleteDataOnDisabled:deleteData];
  }

  // Notify delegates.
  [self enumerateDelegatesForSelector:@selector(channel:didSetEnabled:andDeleteDataOnDisabled:)
                            withBlock:^(id<MSACChannelDelegate> delegate) {
                              [delegate channel:self didSetEnabled:isEnabled andDeleteDataOnDisabled:deleteData];
                            }];

  /**
   * TODO: There should be some concept of logs on disk expiring to avoid leaks when a channel is disabled with lingering logs but never
   * enabled again.
   *
   * Note that this is an unlikely scenario. Solving this issue is more of a proactive measure.
   */
}

#if !TARGET_OS_OSX
- (void)applicationWillTerminate:(__unused UIApplication *)application {

  // Block logs queue so that it isn't killed before app termination.
  [MSACDispatcherUtil dispatchSyncWithTimeout:1
                                      onQueue:self.logsDispatchQueue
                                    withBlock:^{
                                    }];
}
#endif

#pragma mark - Pause / Resume

- (void)pauseWithIdentifyingObject:(id<NSObject>)identifyingObject {

  // Disable ingestion, sending log will not be possible but they'll still be stored.
  [self.ingestion setEnabled:NO andDeleteDataOnDisabled:NO];

  // Pause each channel asynchronously.
  for (id<MSACChannelProtocol> channel in self.channels) {
    [channel pauseWithIdentifyingObject:identifyingObject];
  }
}

- (void)resumeWithIdentifyingObject:(id<NSObject>)identifyingObject {

  // Resume ingestion, logs can be sent again. Pending logs are sent.
  [self.ingestion setEnabled:YES andDeleteDataOnDisabled:NO];

  // Resume each channel asynchronously.
  for (id<MSACChannelProtocol> channel in self.channels) {
    [channel resumeWithIdentifyingObject:identifyingObject];
  }
}

#pragma mark - Other public methods

- (void)setLogUrl:(NSString *)logUrl {
  self.ingestion.baseURL = logUrl;
}

- (void)setAppSecret:(NSString *)appSecret {
  self.ingestion.appSecret = appSecret;
}

- (NSString *)appSecret {
  return self.ingestion.appSecret;
}

- (NSString *)logUrl {
  return self.ingestion.baseURL;
}

- (void)setMaxStorageSize:(long)sizeInBytes completionHandler:(nullable void (^)(BOOL))completionHandler {
  dispatch_async(self.logsDispatchQueue, ^{
    [self.storage setMaxStorageSize:sizeInBytes completionHandler:completionHandler];
  });
}

@end
