//
//  SUAppcast+Private.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifdef BUILDING_SPARKLE_SOURCES_EXTERNALLY
// Ignore incorrect warning
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wquoted-include-in-framework-header"
#import "SUAppcast.h"
#import "SPUAppcastSigningValidationStatus.h"
#pragma clang diagnostic pop
#else
#import <Sparkle/SUAppcast.h>
#import <Sparkle/SPUAppcastSigningValidationStatus.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class SPUAppcastItemStateResolver;

@interface SUAppcast (Private)

- (nullable instancetype)initWithXMLData:(NSData *)xmlData relativeToURL:(NSURL * _Nullable)relativeURL stateResolver:(SPUAppcastItemStateResolver *)stateResolver signingValidationStatus:(SPUAppcastSigningValidationStatus)signingValidationStatus error:(NSError * __autoreleasing *)error;

- (SUAppcast *)copyByFilteringItems:(BOOL (^)(SUAppcastItem *))filterBlock;

@end

NS_ASSUME_NONNULL_END
