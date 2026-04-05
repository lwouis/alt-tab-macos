// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACConstants+Flags.h"
#import "MSACLog.h"
#import "MSACLogContainer.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Completion handler triggered when data is loaded from the storage.
 *
 * @param logArray Array of logs loaded from the storage.
 * @param batchId Batch Id associated with the logs, `nil` if no logs available.
 */
typedef void (^MSACLoadDataCompletionHandler)(NSArray<id<MSACLog>> *_Nullable logArray, NSString *_Nullable batchId);

/**
 * Defines the storage component which is responsible for persisting logs.
 */
@protocol MSACStorage <NSObject>

@required

/**
 * Store a log.
 *
 * @param log The log to be stored.
 * @param groupId The key used for grouping logs.
 * @param flags A flag that indicates if the log has critical persistence priority.
 *
 * @return BOOL that indicates if the log was saved successfully.
 */
- (BOOL)saveLog:(id<MSACLog>)log withGroupId:(NSString *)groupId flags:(MSACFlags)flags;

/**
 * Get the number of logs stored in the storage.
 *
 * @return The number of logs.
 */
- (NSUInteger)countLogs;

/**
 * Delete logs related to given group from the storage.
 *
 * @param groupId The key used for grouping logs.
 *
 * @return The list of deleted logs.
 */
- (NSArray<id<MSACLog>> *)deleteLogsWithGroupId:(NSString *)groupId;

/**
 * Delete a log from the storage.
 *
 * @param batchId Id of the log to be deleted from storage.
 * @param groupId The key used for grouping logs.
 */
- (void)deleteLogsWithBatchId:(NSString *)batchId groupId:(NSString *)groupId;

/**
 * Return the most recent logs for a Group Id.
 *
 * @param groupId The key used for grouping.
 * @param limit Limit the maximum number of logs to be loaded from disk.
 * @param excludedTargetKeys The array of target keys to exclude for the logs.
 * @param completionHandler The completion handler for loading the logs.
 *
 * @return a list of logs.
 */
- (BOOL)loadLogsWithGroupId:(NSString *)groupId
                      limit:(NSUInteger)limit
         excludedTargetKeys:(nullable NSArray<NSString *> *)excludedTargetKeys
          completionHandler:(nullable MSACLoadDataCompletionHandler)completionHandler;

/**
 * Set the maximum size of the internal storage. This method must be called before App Center is started.
 *
 * @param sizeInBytes Maximum size of the internal storage in bytes. This will be rounded up to the nearest multiple of a SQLite page size
 * (default is 4096 bytes). Values below 24576 bytes (24 KiB) will be ignored.
 * @param completionHandler Callback that is invoked when the database size has been set. The `BOOL` parameter is `YES` if changing the size
 * is successful, and `NO` otherwise.
 *
 * @discussion  The value passed to this method is not persisted on disk. The default maximum database size is 10485760 bytes (10 MiB).
 *
 */
- (void)setMaxStorageSize:(long)sizeInBytes completionHandler:(nullable void (^)(BOOL))completionHandler;

@end

NS_ASSUME_NONNULL_END
