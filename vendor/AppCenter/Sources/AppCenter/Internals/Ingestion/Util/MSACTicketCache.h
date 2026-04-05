// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MSACTicketCache : NSObject

/**
 * Dictionary to hold tickets.
 */
@property(nonatomic) NSMutableDictionary<NSString *, NSString *> *tickets;

/**
 * Return singleton instance of MSACTicketCache.
 *
 * @return the instance.
 */
+ (instancetype)sharedInstance;

/**
 * Retrieve a ticket from the ticket cache.
 *
 * @param key The key for the ticket.
 *
 * @return The ticket or nil.
 */
- (NSString *_Nullable)ticketFor:(NSString *)key;

/**
 * Add a ticket to the cache.
 *
 * @param value The ticket to cache.
 * @param key The key for the ticket to be cached.
 */
- (void)setTicket:(NSString *)value forKey:(NSString *)key;

/**
 * Clear the cache. This will be used in tests.
 */
- (void)clearCache;

@end

NS_ASSUME_NONNULL_END
