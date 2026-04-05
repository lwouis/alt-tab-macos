//
//  SPUUpdaterTimer.m
//  Sparkle
//
//  Created by Mayur Pawashe on 8/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdaterTimer.h"
#import "SUConstants.h"


#include "AppKitPrevention.h"

@implementation SPUUpdaterTimer
{
    dispatch_source_t _source;
    
    __weak id<SPUUpdaterTimerDelegate> _delegate;
}

- (instancetype)initWithDelegate:(id<SPUUpdaterTimerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)startAndFireAfterDelay:(NSTimeInterval)delay leewayUpdateCheckInterval:(uint64_t)leewayUpdateCheckInterval
{
    _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    
    // We use the wall time instead of cpu time for our dispatch timer
    // So eg if the computer sleeps we want to include that time spent in our timer
    dispatch_time_t timeToFire = dispatch_walltime(NULL, (int64_t)(delay * NSEC_PER_SEC));
    dispatch_source_set_timer(_source, timeToFire, DISPATCH_TIME_FOREVER, leewayUpdateCheckInterval * NSEC_PER_SEC);
    
    __weak __typeof__(self) weakSelf = self;
    dispatch_source_set_event_handler(_source, ^{
        __typeof__(self) strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf->_delegate updaterTimerDidFire];
        }
    });
    
    dispatch_resume(_source);
}

- (void)invalidate
{
    if (_source != nil) {
        dispatch_source_cancel(_source);
        _source = nil;
    }
}

@end
