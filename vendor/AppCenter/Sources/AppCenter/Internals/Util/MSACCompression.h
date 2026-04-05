// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@interface MSACCompression : NSObject

/**
 * Compress given data using zlib.
 *
 * @param data Data to compress.
 *
 * @return Compressed data.
 */
+ (NSData *)compressData:(NSData *)data;

@end
