//
//  SPUStandardVersionDisplay.h
//  Sparkle
//
//  Created on 2/18/23.
//  Copyright © 2023 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUVersionDisplayProtocol.h"

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SPUStandardVersionDisplay : NSObject <SUVersionDisplay>

+ (instancetype)standardVersionDisplay;

@end

NS_ASSUME_NONNULL_END
