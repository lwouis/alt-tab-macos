//
//  SPUXPCServiceInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL SPUXPCServiceIsEnabled(NSString *enabledKey);

BOOL SPUHelperHasExecutablePermission(NSString *component, NSString * _Nullable __autoreleasing * _Nullable failureReason);

BOOL SPUXPCServiceHasExecutablePermission(NSString *serviceName, NSString * _Nullable __autoreleasing * _Nullable failureReason);

NS_ASSUME_NONNULL_END
