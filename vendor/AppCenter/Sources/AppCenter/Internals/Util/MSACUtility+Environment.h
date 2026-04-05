// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACUtility.h"

/*
 * Workaround for exporting symbols from category object files.
 */
extern NSString *MSACUtilityEnvironmentCategory;

/**
 *  App environment
 */
typedef NS_ENUM(NSInteger, MSACEnvironment) {

  /**
   *  App has been downloaded from the AppStore.
   */
  MSACEnvironmentAppStore = 0,

  /**
   *  App has been downloaded from TestFlight.
   */
  MSACEnvironmentTestFlight = 1,

  /**
   *  App has been installed by some other mechanism.
   *  This could be Ad-Hoc, Enterprise, etc.
   */
  MSACEnvironmentOther = 99
};

/**
 * Utility class that is used throughout the SDK.
 * Environment part.
 */
@interface MSACUtility (Environment)

/**
 * Detect the environment that the app is running in.
 *
 * @return the MSACEnvironment of the app.
 */
+ (MSACEnvironment)currentAppEnvironment;

@end
