// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <array>
#import <string>
#import <unordered_map>

/**
 * Data structure for logs that need to be flushed at crash time to make sure no
 * log is lost at crash time.
 *
 * @property bufferPath The path where the buffered log should be persisted.
 * @property buffer The actual buffered data. It comes in the form of a
 * std::string but actually contains an NSData object which is a serialized log.
 * @property internalId An internal id that helps keep track of logs.
 * @property timestamp A timestamp that is used to determine which bufferedLog
 * to delete in case the buffer is full.
 */
struct MSACCrashesBufferedLog {
  std::string bufferPath;
  std::string buffer;
  std::string targetTokenPath;
  std::string targetToken;
  std::string internalId;
  NSTimeInterval timestamp;

  MSACCrashesBufferedLog() = default;

  MSACCrashesBufferedLog(NSString *path, NSData *data)
      : bufferPath(path.UTF8String),
        buffer(&reinterpret_cast<const char *>(data.bytes)[0], &reinterpret_cast<const char *>(data.bytes)[data.length]) {}
};

/**
 * Constant for size of our log buffer.
 */
const int ms_crashes_log_buffer_size = 60;

/**
 * The log buffer object where we keep out BUFFERED_LOGs which will be written
 * to disk in case of a crash.
 */
extern std::array<MSACCrashesBufferedLog, ms_crashes_log_buffer_size> msACCrashesLogBuffer;

/**
 * Save the log buffer to files.
 */
extern void ms_save_log_buffer();
