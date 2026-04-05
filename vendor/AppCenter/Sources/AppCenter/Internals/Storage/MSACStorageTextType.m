// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <sqlite3.h>

#import "MSACStorageTextType.h"

@implementation MSACStorageTextType

- (instancetype)initWithValue:(nullable NSString *)value {
  if ((self = [super init])) {
    _value = value;
  }
  return self;
}

- (int)bindWithStatement:(void *)query atIndex:(int)index {
  if (self.value) {
    return sqlite3_bind_text(query, index, [self.value UTF8String], -1, SQLITE_TRANSIENT);
  } else {
    return sqlite3_bind_null(query, index);
  }
}

@end
