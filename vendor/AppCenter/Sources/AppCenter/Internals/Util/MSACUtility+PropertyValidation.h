// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACUtility.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * Workaround for exporting symbols from category object files.
 */
extern NSString *MSACUtilityPropertyValidationCategory;

/**
 * Utility class that is used throughout the SDK.
 * Property validation part.
 */
@interface MSACUtility (PropertyValidation)

+ (NSDictionary<NSString *, NSString *> *)validateProperties:(NSDictionary<NSString *, NSString *> *)properties
                                                  forLogName:(NSString *)logName
                                                        type:(NSString *)logType;

@end

NS_ASSUME_NONNULL_END
