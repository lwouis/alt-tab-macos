//
//  SUUpdateValidator.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUHost;
@class SUSignatures;
@class SPUVerifierInformation;

NS_ASSUME_NONNULL_BEGIN

#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT_MEMBERS
#endif
@interface SUUpdateValidator : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDownloadPath:(NSString *)downloadPath signatures:(SUSignatures *)signatures host:(SUHost *)host verifierInformation:(SPUVerifierInformation * _Nullable)verifierInformation;

- (BOOL)validateHostHasPublicKeys:(NSError **)error;

// This is "pre" validation, before the archive has been extracted
- (BOOL)validateDownloadPathWithFallbackOnCodeSigning:(BOOL)fallbackOnCodeSigning error:(NSError **)error;

// This is "post" validation, after an archive has been extracted
- (BOOL)validateWithUpdateDirectory:(NSString *)updateDirectory error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
