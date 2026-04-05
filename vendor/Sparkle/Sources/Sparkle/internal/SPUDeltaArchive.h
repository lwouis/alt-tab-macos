//
//  SPUDeltaArchive.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/29/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SPUDeltaArchiveProtocol;
@class SPUDeltaArchiveHeader;

NS_ASSUME_NONNULL_BEGIN

// Opens patch file for reading and decodes the archive header
id<SPUDeltaArchiveProtocol> SPUDeltaArchiveReadPatchAndHeader(NSString *patchFile, SPUDeltaArchiveHeader * _Nullable __autoreleasing * _Nullable outHeader);

NS_ASSUME_NONNULL_END
