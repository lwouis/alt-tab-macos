// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MS_CONSTANTS_FLAGS_H
#define MS_CONSTANTS_FLAGS_H

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, MSFlags) {
  MSFlagsNone = (0 << 0),     // => 00000000
  MSFlagsNormal = (1 << 0),   // => 00000001
  MSFlagsCritical = (1 << 1), // => 00000010
  MSFlagsPersistenceNormal DEPRECATED_MSG_ATTRIBUTE("please use MSFlagsNormal") = MSFlagsNormal,
  MSFlagsPersistenceCritical DEPRECATED_MSG_ATTRIBUTE("please use MSFlagsCritical") = MSFlagsCritical,
  MSFlagsDefault = MSFlagsNormal
};

#endif
