//
//  SPUInstallationInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem;

SPU_OBJC_DIRECT_MEMBERS @interface SPUInstallationInfo : NSObject <NSSecureCoding>

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem;

@property (nonatomic, readonly) SUAppcastItem *appcastItem;

@property (nonatomic) BOOL systemDomain;

@end

NS_ASSUME_NONNULL_END
