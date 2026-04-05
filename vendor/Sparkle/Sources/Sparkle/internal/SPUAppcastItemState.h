//
//  SPUAppcastItemState.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/31/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Appcast Item state that contains properties that depends on a host
SPU_OBJC_DIRECT_MEMBERS @interface SPUAppcastItemState : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithMajorUpgrade:(BOOL)majorUpgrade criticalUpdate:(BOOL)criticalUpdate informationalUpdate:(BOOL)informationalUpdate minimumUpdateVersionIsOK:(BOOL)minimumUpdateVersionIsOK minimumOperatingSystemVersionIsOK:(BOOL)minimumOperatingSystemVersionIsOK maximumOperatingSystemVersionIsOK:(BOOL)maximumOperatingSystemVersionIsOK arm64HardwareRequirementIsOK:(BOOL)arm64HardwareRequirementIsOK;

@property (nonatomic, readonly) BOOL majorUpgrade;
@property (nonatomic, readonly) BOOL criticalUpdate;
@property (nonatomic, readonly) BOOL informationalUpdate;
@property (nonatomic, readonly) BOOL minimumUpdateVersionIsOK;
@property (nonatomic, readonly) BOOL minimumOperatingSystemVersionIsOK;
@property (nonatomic, readonly) BOOL maximumOperatingSystemVersionIsOK;
@property (nonatomic, readonly) BOOL arm64HardwareRequirementIsOK;

@end

NS_ASSUME_NONNULL_END
