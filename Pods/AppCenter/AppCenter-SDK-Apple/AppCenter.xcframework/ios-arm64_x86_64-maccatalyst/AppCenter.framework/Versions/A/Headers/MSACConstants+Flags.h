// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MSAC_CONSTANTS_FLAGS_H
#define MSAC_CONSTANTS_FLAGS_H

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, MSACFlags) {
  MSACFlagsNone = (0 << 0),     // => 00000000
  MSACFlagsNormal = (1 << 0),   // => 00000001
  MSACFlagsCritical = (1 << 1), // => 00000010
  MSACFlagsPersistenceNormal DEPRECATED_MSG_ATTRIBUTE("please use MSACFlagsNormal") = MSACFlagsNormal,
  MSACFlagsPersistenceCritical DEPRECATED_MSG_ATTRIBUTE("please use MSACFlagsCritical") = MSACFlagsCritical,
  MSACFlagsDefault = MSACFlagsNormal
} NS_SWIFT_NAME(Flags);

#endif
