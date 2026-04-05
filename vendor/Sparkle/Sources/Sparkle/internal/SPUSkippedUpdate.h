//
//  SPUSkippedUpdate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/8/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost, SUAppcastItem;

#ifndef BUILDING_SPARKLE_TESTS
#define SPUSkippedUpdateDefinitionAttribute SPU_OBJC_DIRECT_MEMBERS
#else
#define SPUSkippedUpdateDefinitionAttribute __attribute__((objc_runtime_name("SPUTestSkippedUpdate")))
#endif

/*
 A skipped update tracks an optional minor version and an optional major version the user may skip.
 The minor and major versions are independent versions, so the user can choose to skip at most two separate versions.
 The intent is when the user is faced with a major upgrade, they can skip a major version.
 Otherwise they can choose to skip a minor version.
 */
SPUSkippedUpdateDefinitionAttribute
@interface SPUSkippedUpdate : NSObject

+ (nullable SPUSkippedUpdate *)skippedUpdateForHost:(SUHost *)host;

+ (void)clearSkippedUpdateForHost:(SUHost *)host;

+ (void)skipUpdate:(SUAppcastItem *)updateItem host:(SUHost *)host;

// At least one of minorVersion or majorVersion should be non-nil
- (instancetype)initWithMinorVersion:(nullable NSString *)minorVersion majorVersion:(nullable NSString *)majorVersion majorSubreleaseVersion:(nullable NSString *)majorSubreleaseVersion;

// At least one of these two version properties will be non-nil
@property (nonatomic, readonly, nullable) NSString *minorVersion;
@property (nonatomic, readonly, nullable) NSString *majorVersion;

@property (nonatomic, readonly, nullable) NSString *majorSubreleaseVersion;

@end

NS_ASSUME_NONNULL_END
