// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACOneCollectorIngestion.h"

@interface MSACOneCollectorIngestion ()

/**
 * Hide secret from the given token string.
 *
 * @param tokenString A token string.
 *
 * @return A obfuscated token string.
 */
- (NSString *)obfuscateTargetTokens:(NSString *)tokenString;

/**
 * Hide secret from the given ticket string.
 *
 * @param ticketString A ticket string.
 *
 * @return A obfuscated ticket string.
 */
- (NSString *)obfuscateTickets:(NSString *)ticketString;

@end
