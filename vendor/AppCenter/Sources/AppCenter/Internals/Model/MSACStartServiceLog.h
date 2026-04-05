// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACAbstractLogInternal.h"
#import "MSACNoAutoAssignSessionIdLog.h"

@interface MSACStartServiceLog : MSACAbstractLog <MSACNoAutoAssignSessionIdLog>

/**
 * Services which started with SDK
 */
@property(nonatomic) NSArray<NSString *> *services;

@end
