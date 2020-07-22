// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MS_LOG_WITH_PROPERTIES_H
#define MS_LOG_WITH_PROPERTIES_H

#import <Foundation/Foundation.h>

#import "MSAbstractLog.h"

@interface MSLogWithProperties : MSAbstractLog

/**
 * Additional key/value pair parameters. [optional]
 */
@property(nonatomic, strong) NSDictionary<NSString *, NSString *> *properties;

@end

#endif
