// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACDBStorage.h"

NS_ASSUME_NONNULL_BEGIN

typedef int (^MSACDBStorageQueryBlock)(void *);

// 10 MiB.
static const long kMSACDefaultDatabaseSizeInBytes = 10 * 1024 * 1024;

@interface MSACDBStorage ()

/**
 * Database file name.
 */
@property(nonatomic, nullable) NSURL *dbFileURL;

/**
 * Maximum size of the database.
 */
@property(nonatomic) long maxSizeInBytes;

/**
 * Page size for database.
 */
@property(nonatomic) long pageSize;

/**
 * Schema for the table.
 */
@property(nonatomic, readonly, nullable) MSACDBSchema *schema;

/**
 * Called after the database is created. Override to customize the database.
 *
 * @param db Database handle.
 */
- (void)customizeDatabase:(void *)db;

/**
 * Called when migration is needed. Override to customize.
 *
 * @param db Database handle.
 * @param version Current database version.
 */
- (void)migrateDatabase:(void *)db fromVersion:(NSUInteger)version;

/**
 * Open database to prepare actions in callback.
 *
 * @param block Actions to perform in query.
 */
- (int)executeQueryUsingBlock:(MSACDBStorageQueryBlock)block;

/**
 * Creates a table within an existing database.
 *
 * @param tableName Table name.
 * @param columnsSchema Schema describing the columns structure.
 *
 * @return YES if table is created or already exists, NO otherwise.
 */
- (BOOL)createTable:(NSString *)tableName columnsSchema:(MSACDBColumnsSchema *)columnsSchema;

/**
 * Create table with schema.
 *
 * @param schema Database schema.
 * @param db Database handle.
 *
 * @return result `SQLITE_OK` or an error code.
 */
+ (int)createTablesWithSchema:(nullable MSACDBSchema *)schema inOpenedDatabase:(void *)db;

/**
 * Query the number of pages (i.e.: SQLite "page_count") of the database.
 *
 * @param db Database handle.
 *
 * @return The number of pages.
 */
+ (long)getPageCountInOpenedDatabase:(void *)db;

/**
 * Query the size of pages (i.e.: SQLite "page_size") of the database.
 *
 * @param db Database handle.
 *
 * @return The size of pages.
 */
+ (long)getPageSizeInOpenedDatabase:(void *)db;

/**
 * Set the auto vacuum (i.e.: SQLite "auto_vacuum") of the database.
 *
 * @param db Database handle.
 */
+ (void)enableAutoVacuumInOpenedDatabase:(void *)db;

/**
 * Check if a table exists in this database.
 *
 * @param tableName Table name.
 * @param db Database handle.
 *
 * @return `YES` if the table exists in the database, otherwise `NO`.
 */
+ (BOOL)tableExists:(NSString *)tableName inOpenedDatabase:(void *)db;

/**
 * Get current database version.
 *
 * @param db Database handle.
 * @param result `SQLITE_OK` or an error code.
 */
+ (NSUInteger)versionInOpenedDatabase:(void *)db result:(int *)result;

/**
 * Set current database version.
 *
 * @param db Database handle.
 */
+ (void)setVersion:(NSUInteger)version inOpenedDatabase:(void *)db;

/**
 * Execute a non selection SQLite query on the database (i.e.: "CREATE",
 * "INSERT", "UPDATE"... but not "SELECT").
 *
 * @param query An SQLite query to execute.
 * @param db Database handle.
 *
 * @return `YES` if the query executed successfully, otherwise `NO`.
 */
+ (int)executeNonSelectionQuery:(NSString *)query inOpenedDatabase:(void *)db;

/**
 * Execute a non selection SQLite query on the database (i.e.: "CREATE", "INSERT", "UPDATE"... but not "SELECT").
 *
 * @param query A SQLite statement to execute.
 * @param db Database handle.
 * @param values An array of query parameters to be substituted using `sqlite3_bind`.
 *
 * @return `YES` if the query executed successfully, otherwise `NO`.
 */
+ (int)executeNonSelectionQuery:(NSString *)query inOpenedDatabase:(void *)db withValues:(nullable MSACStorageBindableArray *)values;

/**
 * Execute a "SELECT" SQLite query on the database.
 *
 * @param query A SQLite "SELECT" query to execute.
 * @param db Database handle.
 * @param values An array of query parameters to be substituted using `sqlite3_bind`.
 *
 * @return The selected entries.
 */
+ (NSArray<NSArray *> *)executeSelectionQuery:(NSString *)query
                             inOpenedDatabase:(void *)db
                                   withValues:(nullable MSACStorageBindableArray *)values;

/**
 * Execute a "SELECT" SQLite query on the database.
 *
 * @param query An SQLite "SELECT" query to execute.
 * @param db Database handle.
 * @param result A reference of result code.
 *
 * @return The selected entries.
 */
+ (NSArray<NSArray *> *)executeSelectionQuery:(NSString *)query
                             inOpenedDatabase:(void *)db
                                       result:(nullable int *)result
                                   withValues:(nullable MSACStorageBindableArray *)values;

/**
 * Query the maximum number of pages (i.e.: SQLite "max_page_count") of the database.
 *
 * @param db Database handle.
 *
 * @return The maximum number of pages.
 */
+ (long)getMaxPageCountInOpenedDatabase:(void *)db;

/**
 * Set global SQLite configuration.
 *
 * @return `SQLITE_OK` if SQLite configured successfully, otherwise an error code.
 *
 * @discussion SQLite global configuration must be set before any database is opened.
 */
+ (int)configureSQLite;

@end

NS_ASSUME_NONNULL_END
