// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACUtility+Date.h"

/**
 * Cached date formatter instance.
 */
static NSDateFormatter *dateFormatter = nil;

/*
 * Workaround for exporting symbols from category object files.
 */
NSString *MSACUtilityDateCategory;

@implementation MSACUtility (Date)

+ (NSTimeInterval)nowInMilliseconds {
  return ([[NSDate date] timeIntervalSince1970] * 1000);
}

+ (NSString *)dateToISO8601:(NSDate *)date {
  return [[MSACUtility ISO8601DateFormatter] stringFromDate:date];
}

+ (NSDate *)dateFromISO8601:(NSString *)string {
  return [[MSACUtility ISO8601DateFormatter] dateFromString:string];
}

+ (NSDateFormatter *)ISO8601DateFormatter {
  if (!dateFormatter) {
    @synchronized(self) {
      if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setLocale:[NSLocale systemLocale]];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
      }
    }
  }
  return dateFormatter;
}

+ (void)resetDateFormatterInstance {
  dateFormatter = nil;
}

@end
