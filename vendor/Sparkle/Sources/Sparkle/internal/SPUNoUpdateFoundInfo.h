//
//  SPUNoUpdateFoundInfo.h
//  Sparkle
//
//  Created on 2/18/23.
//  Copyright © 2023 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SUVersionDisplayProtocol.h"
#import "SUErrors.h"

@class SUAppcastItem;
@class SUHost;

NS_ASSUME_NONNULL_BEGIN

NSString *SPUNoUpdateFoundRecoverySuggestion(SPUNoUpdateFoundReason reason, SUAppcastItem * _Nullable latestAppcastItem, SUHost *host, id<SUVersionDisplay> versionDisplayer, NSBundle * _Nullable sparkleBundle);

NS_ASSUME_NONNULL_END
