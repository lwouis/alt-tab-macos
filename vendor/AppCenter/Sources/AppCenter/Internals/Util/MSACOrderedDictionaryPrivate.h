// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACOrderedDictionary.h"

@interface MSACOrderedDictionary ()

/**
 * An array containing the keys that are used to maintain the order.
 */
@property(nonatomic) NSMutableArray *order;

/**
 * The backing store for our ordered dictionary.
 */
@property(nonatomic) NSMutableDictionary *dictionary;

@end
