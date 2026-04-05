// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACStorageBindableType.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSACStorageTextType : NSObject <MSACStorageBindableType>

@property(nonatomic, nullable) NSString *value;

/**
 * Initializer with a value represented as NSString.
 */
- (instancetype __nonnull)initWithValue:(nullable NSString *)value;

@end

NS_ASSUME_NONNULL_END
