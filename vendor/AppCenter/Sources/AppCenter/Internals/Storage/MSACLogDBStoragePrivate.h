// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACEncrypter.h"
#import "MSACLogDBStorage.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const kMSACDBFileName = @"Logs.sqlite";
static NSString *const kMSACLogTableName = @"logs";
static NSString *const kMSACIdColumnName = @"id";
static NSString *const kMSACGroupIdColumnName = @"groupId";
static NSString *const kMSACLogColumnName = @"log";
static NSString *const kMSACTargetTokenColumnName = @"targetToken";
static NSString *const kMSACTargetKeyColumnName = @"targetKey";
static NSString *const kMSACPriorityColumnName = @"priority";

@protocol MSACDatabaseConnection;

@interface MSACLogDBStorage ()

/**
 * Keep track of logs batches per group Id associated with their logs Ids.
 */
@property(nonatomic) NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *batches;

/**
 * "id" database column index.
 */
@property(nonatomic, readonly) NSUInteger idColumnIndex;

/**
 * "groupId" database column index.
 */
@property(nonatomic, readonly) NSUInteger groupIdColumnIndex;

/**
 * "log" database column index.
 */
@property(nonatomic, readonly) NSUInteger logColumnIndex;

/**
 * "targetToken" database column index.
 */
@property(nonatomic, readonly) NSUInteger targetTokenColumnIndex;

/**
 * Encrypter for target tokens.
 */
@property(nonatomic, readonly) MSACEncrypter *targetTokenEncrypter;

/**
 * Get all logs with the given group Id from the storage.
 *
 * @param groupId The key used for grouping logs.
 *
 * @return Logs and their ids corresponding to the given group Id from the storage.
 */
- (NSArray<id<MSACLog>> *)logsFromDBWithGroupId:(NSString *)groupId;

/**
 * Builds a string for sqlite values binding: for example, (?, ?, ?).
 */
- (NSString *)buildKeyFormatWithCount:(NSUInteger)count;

@end

NS_ASSUME_NONNULL_END
