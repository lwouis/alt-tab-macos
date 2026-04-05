//
//  SPUDownloadedUpdate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 1/8/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUResumableUpdate.h"

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SPUDownloadedUpdate : NSObject <SPUResumableUpdate>

- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryItem downloadBookmarkData:(NSData *)downloadBookmarkData downloadToken:(NSString *)downloadToken;

@property (nonatomic, readonly) NSData *downloadBookmarkData;
@property (nonatomic, readonly) NSString *downloadToken;

@end

NS_ASSUME_NONNULL_END
