// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAbstractLogInternal.h"
#import "MSACAppCenterInternal.h"
#import "MSACCSEpochAndSeq.h"
#import "MSACCSExtensions.h"
#import "MSACChannelUnitConfiguration.h"
#import "MSACChannelUnitProtocol.h"
#import "MSACOneCollectorChannelDelegatePrivate.h"
#import "MSACOneCollectorIngestion.h"
#import "MSACSDKExtension.h"

static NSString *const kMSACOneCollectorBaseUrl = @"https://mobile.events.data.microsoft.com"; // TODO: move to constants?
static NSString *const kMSACBaseErrorMsg = @"Log validation failed.";

/**
 * Log name regex. alnum characters, no heading or trailing periods, no heading underscores, min length of 4, max length of 100.
 */

@implementation MSACOneCollectorChannelDelegate

- (instancetype)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient installId:(NSUUID *)installId baseUrl:(NSString *)baseUrl {
  self = [self init];
  if (self) {
    _installId = installId;
    _baseUrl = baseUrl ?: kMSACOneCollectorBaseUrl;
    _oneCollectorChannels = [NSMutableDictionary new];
    _oneCollectorIngestion = [[MSACOneCollectorIngestion alloc] initWithHttpClient:httpClient baseUrl:_baseUrl];
    _epochsAndSeqsByIKey = [NSMutableDictionary new];
  }
  return self;
}

- (void)channelGroup:(id<MSACChannelGroupProtocol>)channelGroup didAddChannelUnit:(id<MSACChannelUnitProtocol>)channel {

  // Add OneCollector group based on the given channel's group id.
  NSString *groupId = channel.configuration.groupId;
  if (![self isOneCollectorGroup:groupId]) {
    NSString *oneCollectorGroupId = [NSString stringWithFormat:@"%@%@", channel.configuration.groupId, kMSACOneCollectorGroupIdSuffix];
    MSACChannelUnitConfiguration *channelUnitConfiguration =
        [[MSACChannelUnitConfiguration alloc] initDefaultConfigurationWithGroupId:oneCollectorGroupId
                                                                    flushInterval:channel.configuration.flushInterval];
    id<MSACChannelUnitProtocol> channelUnit = [channelGroup addChannelUnitWithConfiguration:channelUnitConfiguration
                                                                              withIngestion:self.oneCollectorIngestion];
    self.oneCollectorChannels[groupId] = channelUnit;
  }
}

- (void)channel:(id<MSACChannelProtocol>)__unused channel prepareLog:(id<MSACLog>)log {

  // Prepare Common Schema logs.
  if ([log isKindOfClass:[MSACCommonSchemaLog class]]) {
    MSACCommonSchemaLog *csLog = (MSACCommonSchemaLog *)log;

    // Set SDK extension values.
    MSACCSEpochAndSeq *epochAndSeq = self.epochsAndSeqsByIKey[csLog.iKey];
    if (!epochAndSeq) {
      epochAndSeq = [[MSACCSEpochAndSeq alloc] initWithEpoch:MSAC_UUID_STRING];
    }
    csLog.ext.sdkExt.epoch = epochAndSeq.epoch;
    csLog.ext.sdkExt.seq = ++epochAndSeq.seq;
    csLog.ext.sdkExt.installId = self.installId;
    self.epochsAndSeqsByIKey[csLog.iKey] = epochAndSeq;

    // Set install ID to SDK.
    csLog.ext.sdkExt.installId = self.installId;
  }
}

- (void)channel:(id<MSACChannelProtocol>)channel
    didPrepareLog:(id<MSACLog>)log
       internalId:(NSString *)__unused internalId
            flags:(MSACFlags)flags {
  id<MSACChannelUnitProtocol> channelUnit = (id<MSACChannelUnitProtocol>)channel;
  id<MSACChannelUnitProtocol> oneCollectorChannelUnit = nil;
  NSString *groupId = channelUnit.configuration.groupId;

  /*
   * Reroute Custom Schema logs to their One Collector channel if they were enqueued to a non One Collector channel. Happens to logs from
   * the log buffer after a crash.
   */
  if ([(NSObject *)log isKindOfClass:[MSACCommonSchemaLog class]] && ![self isOneCollectorGroup:groupId]) {
    oneCollectorChannelUnit = self.oneCollectorChannels[groupId];
    if (oneCollectorChannelUnit) {
      [oneCollectorChannelUnit enqueueItem:log flags:flags];
    }
    return;
  }
  if (![self shouldSendLogToOneCollector:log] || ![channel conformsToProtocol:@protocol(MSACChannelUnitProtocol)]) {
    return;
  }
  oneCollectorChannelUnit = self.oneCollectorChannels[groupId];
  if (!oneCollectorChannelUnit) {
    return;
  }
  id<MSACLogConversion> logConversion = (id<MSACLogConversion>)log;
  NSArray<MSACCommonSchemaLog *> *commonSchemaLogs = [logConversion toCommonSchemaLogsWithFlags:flags];
  for (MSACCommonSchemaLog *commonSchemaLog in commonSchemaLogs) {
    [oneCollectorChannelUnit enqueueItem:commonSchemaLog flags:flags];
  }
}

- (BOOL)channelUnit:(id<MSACChannelUnitProtocol>)channelUnit shouldFilterLog:(id<MSACLog>)log {

  // Validate Custom Schema logs, filter out invalid logs.
  if ([log isKindOfClass:[MSACCommonSchemaLog class]]) {
    if (![self isOneCollectorGroup:channelUnit.configuration.groupId]) {
      return true;
    }
    return ![self validateLog:(MSACCommonSchemaLog *)log];
  }

  // It's an App Center log. Filter out if it contains token(s) since it's already re-enqueued as CS log(s).
  return [[log transmissionTargetTokens] count] > 0;
}

- (void)channel:(id<MSACChannelProtocol>)channel didSetEnabled:(BOOL)isEnabled andDeleteDataOnDisabled:(BOOL)deletedData {
  if ([channel conformsToProtocol:@protocol(MSACChannelUnitProtocol)]) {
    NSString *groupId = ((id<MSACChannelUnitProtocol>)channel).configuration.groupId;
    if (![self isOneCollectorGroup:groupId]) {

      // Mirror disabling state to OneCollector channels.
      [self.oneCollectorChannels[groupId] setEnabled:isEnabled andDeleteDataOnDisabled:deletedData];
    }
  } else if ([channel conformsToProtocol:@protocol(MSACChannelGroupProtocol)] && !isEnabled && deletedData) {

    // Reset epoch and seq values when SDK is disabled as a whole.
    [self.epochsAndSeqsByIKey removeAllObjects];
  }
}

- (void)channel:(id<MSACChannelProtocol>)channel didPauseWithIdentifyingObject:(id<NSObject>)identifyingObject {
  if ([channel conformsToProtocol:@protocol(MSACChannelUnitProtocol)]) {
    NSString *groupId = ((id<MSACChannelUnitProtocol>)channel).configuration.groupId;
    id<MSACChannelUnitProtocol> oneCollectorChannel = self.oneCollectorChannels[groupId];
    [oneCollectorChannel pauseWithIdentifyingObject:identifyingObject];
  }
}

- (void)channel:(id<MSACChannelProtocol>)channel didResumeWithIdentifyingObject:(id<NSObject>)identifyingObject {
  if ([channel conformsToProtocol:@protocol(MSACChannelUnitProtocol)]) {
    NSString *groupId = ((id<MSACChannelUnitProtocol>)channel).configuration.groupId;
    id<MSACChannelUnitProtocol> oneCollectorChannel = self.oneCollectorChannels[groupId];
    [oneCollectorChannel resumeWithIdentifyingObject:identifyingObject];
  }
}

#pragma mark - Helper

- (BOOL)isOneCollectorGroup:(NSString *)groupId {
  return [groupId hasSuffix:kMSACOneCollectorGroupIdSuffix];
}

- (BOOL)shouldSendLogToOneCollector:(id<MSACLog>)log {
  NSObject *logObject = (NSObject *)log;
  return [[log transmissionTargetTokens] count] > 0 && [log conformsToProtocol:@protocol(MSACLogConversion)] &&
         ![logObject isKindOfClass:[MSACCommonSchemaLog class]];
}

- (BOOL)validateLog:(MSACCommonSchemaLog *)log {
  if (![self validateLogName:log.name]) {
    return NO;
  }

  // Property values are valid strings already.
  return YES;
}

- (BOOL)validateLogName:(NSString *)name {

  // Name mustn't be nil.
  if (!name.length) {
    MSACLogError([MSACAppCenter logTag], @"%@ Name must not be nil or empty.", kMSACBaseErrorMsg);
    return NO;
  }

  // The Common Schema event name must conform to a regex.
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kMSACLogNameRegex options:0 error:nil];
  NSRange range = NSMakeRange(0, name.length);
  NSUInteger count = [regex numberOfMatchesInString:name options:0 range:range];
  if (!count) {
    MSACLogError([MSACAppCenter logTag], @"%@ Name must match '%@' but was '%@'", kMSACBaseErrorMsg, kMSACLogNameRegex, name);
    return NO;
  }
  return YES;
}

- (void)setLogUrl:(NSString *)logUrl {
  self.oneCollectorIngestion.baseURL = logUrl;
}

@end
