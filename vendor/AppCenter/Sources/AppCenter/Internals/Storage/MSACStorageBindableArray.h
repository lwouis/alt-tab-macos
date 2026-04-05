// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACStorageBindableType.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSACStorageBindableArray : NSObject

/**
 * Custom array for storing values to be bound in an sqlite statement.
 * Accepts only supported types.
 */
@property(nonatomic) NSMutableArray<id<MSACStorageBindableType>> *array;

/**
 * Adds an NSString object into array.
 *
 * @param value A string value to be added to the array.
 */
- (void)addString:(nullable NSString *)value;

/**
 * Adds a number object into array.
 *
 * @param value NSNumber value to be added to the array.
 * Can not be nil since it means it's an error.
 */
- (void)addNumber:(NSNumber *)value;

/**
 * Binds all values in an array with given sqlite statement.
 *
 * @param query A SQLite statement.
 * @param db A reference to database.
 */
- (int)bindAllValuesWithStatement:(void *)query inOpenedDatabase:(void *)db;

@end

NS_ASSUME_NONNULL_END
