//
//  SPUInstallationInputData.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUSignatures;

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SPUInstallationInputData : NSObject <NSSecureCoding>

/*
 * relaunchPath - path to application bundle to relaunch and listen for termination
 * hostBundlePath - path to host bundle to update & replace
 * updateDirectoryPath - path to update directory (i.e, temporary directory containing the new update archive)
 * downloadName - name of update archive in update directory
 * signatures - signatures for the update that came from the appcast item
 * decryptionPassword - optional decryption password for dmg archives
 * expectedVersion - optional expected version of the new update
 * expectedContentLength - optional expected content length of the new download archive
 */
- (instancetype)initWithRelaunchPath:(NSString *)relaunchPath hostBundlePath:(NSString *)hostBundlePath updateURLBookmarkData:(NSData *)updateURLBookmarkData installationType:(NSString *)installationType signatures:(SUSignatures * _Nullable)signatures decryptionPassword:(nullable NSString *)decryptionPassword expectedVersion:(NSString *)expectedVersion expectedContentLength:(uint64_t)expectedContentLength;

@property (nonatomic, copy, readonly) NSString *relaunchPath;
@property (nonatomic, copy, readonly) NSString *hostBundlePath;
@property (nonatomic, copy, readonly) NSData *updateURLBookmarkData;
@property (nonatomic, copy, readonly) NSString *installationType;
@property (nonatomic, readonly, nullable) SUSignatures *signatures; // nullable because although not using signatures is deprecated, it's still supported
@property (nonatomic, copy, readonly, nullable) NSString *decryptionPassword;
@property (nonatomic, copy, readonly, nullable) NSString *expectedVersion;
@property (nonatomic, readonly) uint64_t expectedContentLength;

@end

NS_ASSUME_NONNULL_END
