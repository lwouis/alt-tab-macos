//
//  SUInstallerProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUInstallerProtocol <NSObject>

// Any installation work can be done prior to user application being terminated and relaunched
// No UI should occur during this stage (i.e, do not show package installer apps, etc..)
// Should be able to be called from non-main thread
- (BOOL)performInitialInstallation:(NSError **)error;

// Any installation work after the user application has has been terminated. This is where the final installation work can be done.
// After this stage is done, the user application may be relaunched.
// Should be able to be called from non-main thread
- (BOOL)performFinalInstallationProgressBlock:(nullable void(^)(double))cb error:(NSError **)error;

// Any clean up work can be done here
// This is work that may be performed after the user application may have been updated / relaunched,
// or after an error occurred in the previous stages.
// Should be able to be called from any thread
- (void)performCleanup;

@end

NS_ASSUME_NONNULL_END
