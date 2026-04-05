// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACCompression.h"
#import "MSACAppCenterInternal.h"
#import "MSACLogger.h"
#import "zlib.h"

@implementation MSACCompression

// See https://www.zlib.net/manual.html for more details on zlib usage.
+ (NSData *)compressData:(NSData *)data {
  if (data == nil || data.length < 1) {
    return nil;
  }

  // set struct values
  z_stream zStreamStruct;
  zStreamStruct.zalloc = NULL; // use default values for these 3
  zStreamStruct.zfree = NULL;
  zStreamStruct.opaque = NULL;
  zStreamStruct.total_out = 0; // # of bytes written out
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-qual"
  zStreamStruct.next_in = (Bytef *)[data bytes];
#pragma clang diagnostic pop
  zStreamStruct.avail_in = (unsigned int)data.length;

  // Init zlib. windowBits is 31: (15 max compression rate + 16 gzip header and trailer), memLevel is 8: default memory allocation.
  int initError = deflateInit2(&zStreamStruct, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY);
  if (initError != Z_OK) {
    NSString *errorMsg = nil;
    switch (initError) {
    case Z_STREAM_ERROR:
      errorMsg = @"Invalid parameter passed in to function.";
      break;
    case Z_MEM_ERROR:
      errorMsg = @"Not enough memory.";
      break;
    case Z_VERSION_ERROR:
      errorMsg = @"Version of zlib.h & libz library do not match!";
      break;
    default:
      errorMsg = @"Unknown error!";
      break;
    }
    MSACLogError(MSACAppCenter.logTag, @"Compression failed with error: %@", errorMsg);
    return nil;
  }

  // zlib documentation says it should be this size.
  NSMutableData *compressedData = [NSMutableData dataWithLength:(NSUInteger)([data length] * 1.01 + 12)];

  // Deflate data.
  int deflateStatus;
  do {

    // Set next_out to be beginning of mutable data + the total already output.
    zStreamStruct.next_out = (unsigned char *)[compressedData mutableBytes] + zStreamStruct.total_out;

    // Set avail_out to total length - the total already output.
    zStreamStruct.avail_out = (unsigned int)([compressedData length] - zStreamStruct.total_out);

    // Call deflate, which will update total_out & return Z_STREAM_END if done, Z_OK if more to do, or an error message.
    deflateStatus = deflate(&zStreamStruct, Z_FINISH);
  } while (deflateStatus == Z_OK);
  if (deflateStatus != Z_STREAM_END) {
    NSString *errorMsg = nil;
    switch (deflateStatus) {
    case Z_BUF_ERROR:
      errorMsg = @"No progress is possible.";
      break;
    case Z_STREAM_ERROR:
      errorMsg = @"Inconsistent stream state.";
      break;
    default:
      errorMsg = @"Unknown error!";
      break;
    }
    MSACLogError(MSACAppCenter.logTag, @"Deflate failed with error: %@", errorMsg);
    deflateEnd(&zStreamStruct);
    return nil;
  }
  deflateEnd(&zStreamStruct);
  [compressedData setLength:zStreamStruct.total_out];
  return compressedData;
}

@end
