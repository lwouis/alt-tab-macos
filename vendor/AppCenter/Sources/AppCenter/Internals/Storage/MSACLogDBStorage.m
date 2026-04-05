// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <sqlite3.h>

#import "MSACAppCenterInternal.h"
#import "MSACConstants+Internal.h"
#import "MSACDBStoragePrivate.h"
#import "MSACLogDBStoragePrivate.h"
#import "MSACLogDBStorageVersion.h"
#import "MSACStorageNumberType.h"
#import "MSACStorageTextType.h"
#import "MSACUtility+StringFormatting.h"

static const NSUInteger kMSACSchemaVersion = 5;

@implementation MSACLogDBStorage

#pragma mark - Initialization

- (instancetype)init {

  /*
   * DO NOT modify schema without a migration plan and bumping database version.
   */
  MSACDBSchema *schema = @{
    kMSACLogTableName : @[
      @{kMSACIdColumnName : @[ kMSACSQLiteTypeInteger, kMSACSQLiteConstraintPrimaryKey, kMSACSQLiteConstraintAutoincrement ]},
      @{kMSACGroupIdColumnName : @[ kMSACSQLiteTypeText, kMSACSQLiteConstraintNotNull ]},
      @{kMSACLogColumnName : @[ kMSACSQLiteTypeText, kMSACSQLiteConstraintNotNull ]},
      @{kMSACTargetTokenColumnName : @[ kMSACSQLiteTypeText ]}, @{kMSACTargetKeyColumnName : @[ kMSACSQLiteTypeText ]},
      @{kMSACPriorityColumnName : @[ kMSACSQLiteTypeInteger ]}
    ]
  };
  self = [self initWithSchema:schema version:kMSACSchemaVersion filename:kMSACDBFileName];
  if (self) {
    NSDictionary *columnIndexes = [MSACDBStorage columnsIndexes:schema];
    _idColumnIndex = ((NSNumber *)columnIndexes[kMSACLogTableName][kMSACIdColumnName]).unsignedIntegerValue;
    _groupIdColumnIndex = ((NSNumber *)columnIndexes[kMSACLogTableName][kMSACGroupIdColumnName]).unsignedIntegerValue;
    _logColumnIndex = ((NSNumber *)columnIndexes[kMSACLogTableName][kMSACLogColumnName]).unsignedIntegerValue;
    _targetTokenColumnIndex = ((NSNumber *)columnIndexes[kMSACLogTableName][kMSACTargetTokenColumnName]).unsignedIntegerValue;
    _batches = [NSMutableDictionary<NSString *, NSArray<NSNumber *> *> new];
    _targetTokenEncrypter = [MSACEncrypter new];
  }
  return self;
}

#pragma mark - Save logs

- (BOOL)saveLog:(id<MSACLog>)log withGroupId:(NSString *)groupId flags:(MSACFlags)flags {
  if (!log) {
    return NO;
  }
  MSACFlags persistenceFlags = flags & kMSACPersistenceFlagsMask;

  // Insert this log to the DB.
  NSString *base64Data = [[MSACUtility archiveKeyedData:log] base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];

  MSACStorageBindableArray *addLogValues = [MSACStorageBindableArray new];
  [addLogValues addString:groupId];
  [addLogValues addString:base64Data];
  [addLogValues addNumber:@(persistenceFlags)];
  NSString *addLogQuery = [NSString stringWithFormat:@"INSERT INTO \"%@\" (\"%@\", \"%@\", \"%@\") VALUES (?, ?, ?)", kMSACLogTableName,
                                                     kMSACGroupIdColumnName, kMSACLogColumnName, kMSACPriorityColumnName];

  // Serialize target token.
  if ([(NSObject *)log isKindOfClass:[MSACCommonSchemaLog class]]) {
    NSString *targetToken = [[log transmissionTargetTokens] anyObject];
    NSString *encryptedToken = [self.targetTokenEncrypter encryptString:targetToken];
    NSString *targetKey = [MSACUtility targetKeyFromTargetToken:targetToken];

    addLogValues = [MSACStorageBindableArray new];
    [addLogValues addString:groupId];
    [addLogValues addString:base64Data];
    [addLogValues addString:encryptedToken];
    [addLogValues addString:targetKey];
    [addLogValues addNumber:@(persistenceFlags)];
    addLogQuery = [NSString stringWithFormat:@"INSERT INTO \"%@\" (\"%@\", \"%@\", \"%@\", \"%@\", \"%@\") VALUES (?, ?, ?, ?, ?)",
                                             kMSACLogTableName, kMSACGroupIdColumnName, kMSACLogColumnName, kMSACTargetTokenColumnName,
                                             kMSACTargetKeyColumnName, kMSACPriorityColumnName];
  }
  return [self executeQueryUsingBlock:^int(void *db) {
           // Check maximum size.
           NSUInteger maxSize = [MSACDBStorage getMaxPageCountInOpenedDatabase:db] * self.pageSize;
           if (base64Data.length >= maxSize) {
             MSACLogError([MSACAppCenter logTag],
                          @"Log is too large (%tu bytes) to store in database. Current maximum database size is %tu bytes.",
                          base64Data.length, maxSize);
             return SQLITE_ERROR;
           }

           // Try to insert.
           int result = [MSACDBStorage executeNonSelectionQuery:addLogQuery inOpenedDatabase:db withValues:addLogValues];
           NSMutableArray<NSNumber *> *logsCanBeDeleted = nil;
           if (result == SQLITE_FULL) {

             // Selecting logs with equal or lower priority and ordering by priority then age.
             NSString *query = [NSString stringWithFormat:@"SELECT \"%@\" FROM \"%@\" WHERE \"%@\" <= ? ORDER BY \"%@\" ASC, \"%@\" ASC",
                                                          kMSACIdColumnName, kMSACLogTableName, kMSACPriorityColumnName,
                                                          kMSACPriorityColumnName, kMSACIdColumnName];
             MSACStorageBindableArray *values = [MSACStorageBindableArray new];
             [values addNumber:@(flags)];
             NSArray<NSArray *> *entries = [MSACDBStorage executeSelectionQuery:query inOpenedDatabase:db withValues:values];
             logsCanBeDeleted = [NSMutableArray new];
             for (NSMutableArray *row in entries) {
               [logsCanBeDeleted addObject:row[0]];
             }
           }

           // If the database is full, delete logs until there is room to add the log.
           long countOfLogsDeleted = 0;
           NSUInteger index = 0;
           while (result == SQLITE_FULL && index < [logsCanBeDeleted count]) {
             result = [MSACLogDBStorage deleteLogsFromDBWithColumnValues:@[ logsCanBeDeleted[index] ]
                                                              columnName:kMSACIdColumnName
                                                        inOpenedDatabase:db];
             if (result != SQLITE_OK) {
               break;
             }
             MSACLogDebug([MSACAppCenter logTag], @"Deleted a log with id %@ to store a new log.", logsCanBeDeleted[index]);
             ++countOfLogsDeleted;
             ++index;
             result = [MSACDBStorage executeNonSelectionQuery:addLogQuery inOpenedDatabase:db withValues:addLogValues];
           }
           if (countOfLogsDeleted > 0) {
             MSACLogDebug([MSACAppCenter logTag], @"Log storage was over capacity, %ld oldest log(s) with equal or lower priority deleted.",
                          (long)countOfLogsDeleted);
           }
           if (result == SQLITE_OK) {
             MSACLogVerbose([MSACAppCenter logTag], @"Log is stored with id: '%ld'", (long)sqlite3_last_insert_rowid(db));
           } else if (result == SQLITE_FULL && index == [logsCanBeDeleted count]) {
             MSACLogError([MSACAppCenter logTag], @"Storage is full and no logs with equal or lower priority exist; discarding the log.");
           }
           return result;
         }] == SQLITE_OK;
}

#pragma mark - Load logs

- (NSString *)buildKeyFormatWithCount:(NSUInteger)count {
  NSString *keyFormat = [@"(" stringByPaddingToLength:count * 2 withString:@"?," startingAtIndex:0];
  keyFormat = [keyFormat stringByAppendingString:@")"];
  return keyFormat;
}

- (BOOL)loadLogsWithGroupId:(NSString *)groupId
                      limit:(NSUInteger)limit
         excludedTargetKeys:(nullable NSArray<NSString *> *)excludedTargetKeys
          completionHandler:(nullable MSACLoadDataCompletionHandler)completionHandler {
  BOOL logsAvailable;
  BOOL moreLogsAvailable = NO;
  NSString *batchId;
  NSMutableArray<NSArray *> *logEntries;
  NSMutableArray<NSNumber *> *dbIds = [NSMutableArray<NSNumber *> new];
  NSMutableArray<id<MSACLog>> *logs = [NSMutableArray<id<MSACLog>> new];

  // Get ids from batches.
  NSMutableArray<NSNumber *> *idsInBatches = [NSMutableArray<NSNumber *> new];
  for (NSString *batchKey in [self.batches allKeys]) {
    if ([batchKey hasPrefix:groupId]) {
      [idsInBatches addObjectsFromArray:(NSArray<NSNumber *> *_Nonnull)self.batches[batchKey]];
    }
  }

  // Build the "WHERE" clause's conditions.
  NSMutableString *condition = [NSMutableString stringWithFormat:@"\"%@\" = ?", kMSACGroupIdColumnName];
  MSACStorageBindableArray *values = [MSACStorageBindableArray new];
  [values addString:groupId];

  // Filter out paused target keys.
  if (excludedTargetKeys != nil && excludedTargetKeys.count > 0) {
    NSString *keyFormat = [self buildKeyFormatWithCount:excludedTargetKeys.count];
    [condition appendFormat:@" AND \"%@\" NOT IN %@", kMSACTargetKeyColumnName, keyFormat];
    for (NSString *item in excludedTargetKeys) {
      [values addString:item];
    }
  }

  // Take only logs that are not already part of a batch.
  if (idsInBatches.count > 0) {
    NSString *keyFormat = [self buildKeyFormatWithCount:idsInBatches.count];
    [condition appendFormat:@" AND \"%@\" NOT IN %@", kMSACIdColumnName, keyFormat];
    for (NSNumber *item in idsInBatches) {
      [values addNumber:item];
    }
  }

  // Build the "ORDER BY" clause's conditions.
  [condition appendFormat:@" ORDER BY \"%@\" DESC, \"%@\" ASC", kMSACPriorityColumnName, kMSACIdColumnName];

  /*
   * There is a need to determine if there will be more logs available than those under the limit. This is just about knowing if there is at
   * least 1 log above the limit.
   *
   * FIXME: We should simply use a count API from the consumer object instead of the "limit + 1" technique, it only requires 1 SQL request
   * instead of 2 for the count but it is a bit confusing and doesn't really fit a database storage.
   */
  [condition appendFormat:@" LIMIT %lu", (unsigned long)((limit < NSUIntegerMax) ? limit + 1 : limit)];

  // Get log entries from DB.
  logEntries = [[self logsWithCondition:condition andValues:values] mutableCopy];

  // More logs available for the next batch, remove the log in excess for this batch.
  if (logEntries.count > 0 && logEntries.count > limit) {
    [logEntries removeLastObject];
    moreLogsAvailable = YES;
  }

  // Get lists of logs and DB ids.
  for (NSArray *logEntry in logEntries) {
    [dbIds addObject:logEntry[self.idColumnIndex]];
    [logs addObject:logEntry[self.logColumnIndex]];
  }

  // Generate batch Id.
  logsAvailable = logEntries.count > 0;
  if (logsAvailable) {
    batchId = MSAC_UUID_STRING;
    self.batches[[groupId stringByAppendingString:batchId]] = dbIds;
    MSACLogVerbose([MSACAppCenter logTag], @"Load log(s) with id(s) '%@' as batch Id:%@", [dbIds componentsJoinedByString:@"','"], batchId);
  }

  // Load completed.
  if (completionHandler) {
    completionHandler(logs, batchId);
  }

  // Return YES if more logs available.
  return moreLogsAvailable;
}

#pragma mark - Delete logs

- (NSArray<id<MSACLog>> *)deleteLogsWithGroupId:(NSString *)groupId {
  NSArray<id<MSACLog>> *logs = [self logsFromDBWithGroupId:groupId];

  // Delete logs.
  [self deleteLogsFromDBWithColumnValue:groupId columnName:kMSACGroupIdColumnName];

  // Delete related batches.
  for (NSString *batchKey in [self.batches allKeys]) {
    if ([batchKey hasPrefix:groupId]) {
      [self.batches removeObjectForKey:batchKey];
    }
  }
  return logs;
}

- (void)deleteLogsWithBatchId:(NSString *)batchId groupId:(NSString *)groupId {

  // Get log Ids.
  NSString *batchIdKey = [groupId stringByAppendingString:batchId];
  NSArray<NSNumber *> *ids = self.batches[batchIdKey];

  // Delete logs and associated batch.
  if (ids.count > 0) {
    [self deleteLogsFromDBWithColumnValues:ids columnName:kMSACIdColumnName];
    [self.batches removeObjectForKey:batchIdKey];
  }
}

#pragma mark - DB selection

- (NSArray<id<MSACLog>> *)logsFromDBWithGroupId:(NSString *)groupId {

  // Get log entries for the given group Id.
  NSString *condition = [NSString stringWithFormat:@"\"%@\" = ?", kMSACGroupIdColumnName];
  MSACStorageBindableArray *values = [MSACStorageBindableArray new];
  [values addString:groupId];
  NSArray<NSArray *> *logEntries = [self logsWithCondition:condition andValues:values];

  // Get logs only.
  NSMutableArray<id<MSACLog>> *logs = [NSMutableArray<id<MSACLog>> new];
  for (NSArray *logEntry in logEntries) {
    [logs addObject:logEntry[self.logColumnIndex]];
  }
  return logs;
}

- (NSArray<NSArray *> *)logsWithCondition:(NSString *_Nullable)condition andValues:(nullable MSACStorageBindableArray *)values {
  NSMutableArray<NSArray *> *logEntries = [NSMutableArray<NSArray *> new];
  NSMutableString *query = [NSMutableString stringWithFormat:@"SELECT * FROM \"%@\"", kMSACLogTableName];
  if (condition.length > 0) {
    [query appendFormat:@" WHERE %@", condition];
  }
  NSArray<NSArray *> *entries = [self executeSelectionQuery:query withValues:values];

  // Get logs from DB.
  for (NSMutableArray *row in entries) {
    NSNumber *dbId = row[self.idColumnIndex];
    NSData *logData = [[NSData alloc] initWithBase64EncodedString:row[self.logColumnIndex]
                                                          options:NSDataBase64DecodingIgnoreUnknownCharacters];
    id<MSACLog> log;

    // Deserialize the log.
    log = (id<MSACLog>)[MSACUtility unarchiveKeyedData:logData];
    if (!log) {

      // The archived log is not valid.
      MSACLogError([MSACAppCenter logTag], @"Deserialization failed for log with Id %@", dbId);
      [self deleteLogFromDBWithId:dbId];
      continue;
    }

    // Deserialize target token. A token value from the row dictionary can't be `nil` but can be of class `NSNull`.
    NSString *encryptedToken = row[self.targetTokenColumnIndex];
    if ([encryptedToken isKindOfClass:[NSString class]]) {
      if (encryptedToken.length > 0) {
        NSString *targetToken = [self.targetTokenEncrypter decryptString:encryptedToken];
        if (targetToken) {
          [log addTransmissionTargetToken:targetToken];
        } else {
          MSACLogError([MSACAppCenter logTag], @"Failed to decrypt the target token for log with Id %@.", dbId);
        }
      } else {
        MSACLogError([MSACAppCenter logTag], @"Unexpected empty target token for log with Id %@.", dbId);
      }
    }

    // Update with deserialized log.
    row[self.logColumnIndex] = log;
    [logEntries addObject:row];
  }
  return logEntries;
}

#pragma mark - DB deletion

- (void)deleteLogFromDBWithId:(NSNumber *)dbId {
  [self deleteLogsFromDBWithColumnValue:dbId columnName:kMSACIdColumnName];
}

- (void)deleteLogsFromDBWithColumnValue:(id)columnValue columnName:(NSString *)columnName {
  [self deleteLogsFromDBWithColumnValues:@[ columnValue ] columnName:columnName];
}

- (void)deleteLogsFromDBWithColumnValues:(NSArray *)columnValues columnName:(NSString *)columnName {
  [self executeQueryUsingBlock:^int(void *db) {
    return [MSACLogDBStorage deleteLogsFromDBWithColumnValues:columnValues columnName:columnName inOpenedDatabase:db];
  }];
}

+ (int)deleteLogsFromDBWithColumnValues:(NSArray *)columnValues columnName:(NSString *)columnName inOpenedDatabase:(void *)db {
  NSString *deletionTrace = [NSString
      stringWithFormat:@"Deletion of log(s) by %@ with value(s) '%@'", columnName, [columnValues componentsJoinedByString:@"','"]];

  // Build up delete query.
  char surroundingChar = (char)(([(NSObject *)[columnValues firstObject] isKindOfClass:[NSString class]]) ? '\'' : '\0');
  NSString *valuesSeparation = [NSString stringWithFormat:@"%c, %c", surroundingChar, surroundingChar];
  NSString *whereCondition = [NSString stringWithFormat:@"\"%@\" IN (%c%@%c)", columnName, surroundingChar,
                                                        [columnValues componentsJoinedByString:valuesSeparation], surroundingChar];
  NSString *deleteLogsQuery = [NSString stringWithFormat:@"DELETE FROM \"%@\" WHERE %@", kMSACLogTableName, whereCondition];

  // Execute.
  int result = [MSACDBStorage executeNonSelectionQuery:deleteLogsQuery inOpenedDatabase:db];
  if (result == SQLITE_OK) {
    MSACLogVerbose([MSACAppCenter logTag], @"%@ succeeded.", deletionTrace);
  } else {
    MSACLogError([MSACAppCenter logTag], @"%@ failed.", deletionTrace);
  }
  return result;
}

#pragma mark - DB count

- (NSUInteger)countLogs {
  return [self countEntriesForTable:kMSACLogTableName condition:nil withValues:nil];
}

#pragma mark - DB migration

- (void)createPriorityIndex:(void *)db {
  NSString *indexStatement = [NSString stringWithFormat:@"CREATE INDEX \"ix_%@_%@\" ON \"%@\" (\"%@\")", kMSACLogTableName,
                                                        kMSACPriorityColumnName, kMSACLogTableName, kMSACPriorityColumnName];
  [MSACDBStorage executeNonSelectionQuery:indexStatement inOpenedDatabase:db];
}

- (void)customizeDatabase:(void *)db {
  [self createPriorityIndex:db];
}

/*
 * Migration process is implemented through database versioning.
 * After altering current schema, database version should be bumped and actions for migration should be implemented in this method.
 */
- (void)migrateDatabase:(void *)db fromVersion:(NSUInteger __unused)version {

  /*
   * With version 3.0 of the SDK we decided to remove timestamp column and as
   * it's a major SDK version and SQLite does not support removing column we just start over.
   * When adding a new column in a future version, update this code by something like
   * if (version <= kMSACDropTableVersion) {drop/create} else {add missing columns}
   */
  [self dropTable:kMSACLogTableName];
  [MSACDBStorage createTablesWithSchema:self.schema inOpenedDatabase:db];
  [self customizeDatabase:db];
}

@end
