// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACUtility.h"

/*
 * Workaround for exporting symbols from category object files.
 */
extern NSString *MSACUtilityDateCategory;

/**
 * Utility class that is used throughout the SDK.
 * Date part.
 */
@interface MSACUtility (Date)

/**
 * Return the current date (aka NOW) in ms.
 *
 * @return current time in ms with sub-ms precision if necessary
 *
 * @discussion Utility function that returns NOW as a NSTimeInterval but in ms instead of seconds with sub-ms precision. We're using
 * NSTimeInterval here instead of long long because we might be interested in sub-millisecond precision which we keep with NSTimeInterval as
 * NSTimeInterval is actually NSDouble.
 */
+ (NSTimeInterval)nowInMilliseconds;

/**
 * Convert a date object to an ISO 8601 formatted string.
 *
 * @return an ISO 8601 string representation of the date.
 */
+ (NSString *)dateToISO8601:(NSDate *)date;

/**
 * Convert an ISO 8601 formatted string to a date object.
 *
 * @return a date object.
 */
+ (NSDate *)dateFromISO8601:(NSString *)string;

@end
