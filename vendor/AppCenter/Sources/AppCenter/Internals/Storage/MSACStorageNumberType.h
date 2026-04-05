// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACStorageBindableType.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSACStorageNumberType : NSObject <MSACStorageBindableType>

@property(nonatomic) NSNumber *value;

/**
 * Initializer with a value represented as NSNumber.
 */
- (instancetype)initWithValue:(NSNumber *)value;

@end

NS_ASSUME_NONNULL_END
