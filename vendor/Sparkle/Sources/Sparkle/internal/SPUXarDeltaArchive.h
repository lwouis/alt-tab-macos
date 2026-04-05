//
//  SPUXarDeltaArchive.h
//  Autoupdate
//
//  Created by Mayur Pawashe on 12/28/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_LEGACY_DELTA_SUPPORT

#import <Foundation/Foundation.h>

#import "SPUDeltaArchiveProtocol.h"
#import "SPUDeltaCompressionMode.h"

NS_ASSUME_NONNULL_BEGIN

// Legacy container format for binary delta archives
SPU_OBJC_DIRECT_MEMBERS @interface SPUXarDeltaArchive : NSObject <SPUDeltaArchiveProtocol>

- (instancetype)initWithPatchFileForWriting:(NSString *)patchFile SPU_OBJC_DIRECT;
- (instancetype)initWithPatchFileForReading:(NSString *)patchFile SPU_OBJC_DIRECT;

@end

NS_ASSUME_NONNULL_END

#endif
