//
//  SUSignatureVerifier.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//
//  Includes code by Zach Waldowski on 10/18/13.
//  Copyright 2014 Big Nerd Ranch. Licensed under MIT.
//
//  Includes code from Plop by Mark Hamlin.
//  Copyright 2011 Mark Hamlin. Licensed under BSD.
//

#ifndef SUDSAVERIFIER_H
#define SUDSAVERIFIER_H

#import <Foundation/Foundation.h>
@class SUSignatures;
@class SUPublicKeys;
@class SPUVerifierInformation;

NS_ASSUME_NONNULL_BEGIN

#ifndef BUILDING_SPARKLE_TESTS
#define SUSignatureVerifierDefinitionAttribute SPU_OBJC_DIRECT_MEMBERS
#else
#define SUSignatureVerifierDefinitionAttribute __attribute__((objc_runtime_name("SUTestSignatureVerifier")))
#endif

SUSignatureVerifierDefinitionAttribute @interface SUSignatureVerifier : NSObject

// Helper for verifying downloaded updates
+ (BOOL)validatePath:(NSString *)path withSignatures:(SUSignatures *)signatures withPublicKeys:(SUPublicKeys *)pkeys verifierInformation:(SPUVerifierInformation * _Nullable)verifierInformation error:(NSError * __autoreleasing *)error;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPublicKeys:(SUPublicKeys *)pkeys;

// Used for verifying downloaded updates
- (BOOL)verifyFileAtPath:(NSString *)path signatures:(SUSignatures *)signatures verifierInformation:(SPUVerifierInformation * _Nullable)verifierInformation error:(NSError * __autoreleasing *)error;

// Used for verifying non-update data (like release notes)
- (BOOL)verifyData:(NSData *)data signatures:(SUSignatures *)signatures fileKind:(NSString *)fileKind verifierInformation:(SPUVerifierInformation * _Nullable)verifierInformation error:(NSError * __autoreleasing *)error;

@end

NS_ASSUME_NONNULL_END

#endif
