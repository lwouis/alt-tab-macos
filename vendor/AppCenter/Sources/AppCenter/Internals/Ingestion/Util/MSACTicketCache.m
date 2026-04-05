// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACTicketCache.h"

@implementation MSACTicketCache

/**
 * Singleton.
 */
static MSACTicketCache *sharedInstance = nil;
static dispatch_once_t onceToken;

- (instancetype)init {
  if ((self = [super init])) {
    _tickets = [NSMutableDictionary new];
  }
  return self;
}

+ (instancetype)sharedInstance {
  dispatch_once(&onceToken, ^{
    if (sharedInstance == nil) {
      sharedInstance = [[MSACTicketCache alloc] init];
    }
  });
  return sharedInstance;
}

- (NSString *_Nullable)ticketFor:(NSString *)key {
  return [self.tickets valueForKey:key];
}

- (void)setTicket:(NSString *)ticket forKey:(NSString *)key {
  [self.tickets setValue:ticket forKey:key];
}

- (void)clearCache {
  self.tickets = [NSMutableDictionary new];
}

@end
