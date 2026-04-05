//
//  SPUExtractSignedFeed.h
//  Sparkle
//
//  Created on 12/25/25.
//  Copyright © 2025 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Extracts content from an appcast without the signing block, optionally returning back the signed signature & expected content length
NSData *SPUExtractAppcastContent(NSData *appcastData, NSString * _Nullable __autoreleasing * _Nullable outEdSignatureBase64, uint64_t * _Nullable outContentLength);

// Extracts HTML or markdown release notes data without the beginning sign warning comment
NSData *SPUExtractReleaseNotesContent(NSData *data);

NS_ASSUME_NONNULL_END
