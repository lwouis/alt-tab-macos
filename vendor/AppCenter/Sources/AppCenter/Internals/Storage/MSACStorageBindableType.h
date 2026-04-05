// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Defines the storage type to be bound in an sql statement.
 */
@protocol MSACStorageBindableType <NSObject>

@required

/**
 * Binds itself with a statement.
 *
 * @param query SQLite statement.
 * @param index Position of the parameter.
 *
 * @return int result code.
 */
- (int)bindWithStatement:(void *)query atIndex:(int)index;

@end

NS_ASSUME_NONNULL_END
