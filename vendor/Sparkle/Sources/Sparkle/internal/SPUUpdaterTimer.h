//
//  SPUUpdaterTimer.h
//  Sparkle
//
//  Created by Mayur Pawashe on 8/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SPUUpdaterTimerDelegate <NSObject>

- (void)updaterTimerDidFire;

@end

// This notifies the updater for scheduled update checks
// This class is used so that an updater instance isn't kept alive by a scheduled update check
SPU_OBJC_DIRECT_MEMBERS @interface SPUUpdaterTimer : NSObject

- (instancetype)initWithDelegate:(id<SPUUpdaterTimerDelegate>)delegate;

- (void)startAndFireAfterDelay:(NSTimeInterval)delay leewayUpdateCheckInterval:(uint64_t)leewayUpdateCheckInterval;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
