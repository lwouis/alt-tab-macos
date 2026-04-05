// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACOneCollectorChannelDelegate.h"

@class MSACOneCollectorIngestion;

@protocol MSACChannelUnitProtocol;
@protocol MSACLog;

@class MSACCSEpochAndSeq;

/**
 * Regex for Custom Schema log name validation.
 */
static NSString *const kMSACLogNameRegex = @"^[a-zA-Z0-9]((\\.(?!(\\.|$)))|[_a-zA-Z0-9]){3,99}$";

@interface MSACOneCollectorChannelDelegate ()

/**
 * Collection of channel unit protocols per group Id.
 */
@property(nonatomic) NSMutableDictionary<NSString *, id<MSACChannelUnitProtocol>> *oneCollectorChannels;

/**
 * Http ingestion to send logs to One Collector endpoint.
 */
@property(nonatomic) MSACOneCollectorIngestion *oneCollectorIngestion;

/**
 * Base Url for One Collector endpoint.
 */
@property(nonatomic, copy) NSString *baseUrl;

/**
 * Keep track of epoch and sequence per tenant token.
 */
@property(nonatomic) NSMutableDictionary<NSString *, MSACCSEpochAndSeq *> *epochsAndSeqsByIKey;

/**
 * UUID created on first-time SDK initialization.
 */
@property(nonatomic) NSUUID *installId;

/**
 * Returns 'YES' if the log should be sent to one collector.
 */
- (BOOL)shouldSendLogToOneCollector:(id<MSACLog>)log;

/**
 * Validate Common Schema 3.0 Log.
 *
 * @param log The Common Schema log.
 *
 * @return YES if Common Schema log is valid; NO otherwise.
 */
- (BOOL)validateLog:(MSACCommonSchemaLog *)log;

/**
 * Validate Common Schema log name.
 *
 * @param name The log name.
 *
 * @return YES if name is valid, NO otherwise.
 */
- (BOOL)validateLogName:(NSString *)name;

@end
