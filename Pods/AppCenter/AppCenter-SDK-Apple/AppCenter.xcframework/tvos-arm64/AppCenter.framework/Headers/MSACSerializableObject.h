// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#ifndef SERIALIZABLE_OBJECT_H
#define SERIALIZABLE_OBJECT_H

@protocol MSACSerializableObject <NSCoding>

/**
 * Serialize this object to a dictionary.
 *
 * @return A dictionary representing this object.
 */
- (NSMutableDictionary *)serializeToDictionary;

@end
#endif
