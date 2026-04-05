// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACConstants+Flags.h"

@class MSACCommonSchemaLog;

@protocol MSACLogConversion

/**
 * Method to transform a log into one or several common schema logs. If the log has multiple transmission target tokens, the conversion will
 * produce one log per token.
 *
 * @param flags The Common Schema flags for the log.
 *
 * @return An array of MCSCommonSchemaLog objects.
 */
- (NSArray<MSACCommonSchemaLog *> *)toCommonSchemaLogsWithFlags:(MSACFlags)flags;

@end
