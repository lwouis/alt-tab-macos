//
//  StatusInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUStatusInfoProtocol.h"

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface StatusInfo : NSObject <SUStatusInfoProtocol>

- (instancetype)initWithHostBundleIdentifier:(NSString *)bundleIdentifier;

@property (nonatomic, nullable) NSData *installationInfoData;

- (void)startListener;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
