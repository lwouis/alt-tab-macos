//
//  SPUUpdaterSettings+Debug.h
//  Sparkle
//
//  Created on 11/16/25.
//  Copyright © 2025 Sparkle Project. All rights reserved.
//

#import "SPUUpdaterSettings.h"

/**
 * Private settings which may be debug gated for the Sparkle Test App under DEBUG
 */
@interface SPUUpdaterSettings (Debug)

/**
 * The minimum update check interval
 */
@property (nonatomic, readonly) NSTimeInterval minimumUpdateCheckInterval;

/**
 * The amount of time the system can defer our update check (for improved performance)
 */
@property (nonatomic, readonly) uint64_t leewayUpdateCheckInterval;

/**
 * The amount of time the app is allowed to be idle for us to consider showing an update prompt right away when the app is active.
 *
 * This is for the standard user driver.
 */
@property (nonatomic, readonly) NSTimeInterval standardUIScheduledUpdateIdleEventLeewayInterval;

@end
