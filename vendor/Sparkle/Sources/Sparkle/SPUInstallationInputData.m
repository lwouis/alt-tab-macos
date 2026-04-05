//
//  SPUInstallationInputData.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUInstallationInputData.h"
#import "SPUInstallationType.h"
#import "SUSignatures.h"

#include "AppKitPrevention.h"

static NSString *SURelaunchPathKey = @"SURelaunchPath";
static NSString *SUHostBundlePathKey = @"SUHostBundlePath";
static NSString *SUUpdateURLBookmarkDataKey = @"SUUpdateURLBookmarkData";
static NSString *SUSignaturesKey = @"SUSignatures";
static NSString *SUDecryptionPasswordKey = @"SUDecryptionPassword";
static NSString *SUInstallationTypeKey = @"SUInstallationType";
static NSString *SUExpectedVersionKey = @"SUExpectedVersion";
static NSString *SUExpectedContentLength = @"SUExpectedContentLength";

@implementation SPUInstallationInputData

@synthesize relaunchPath = _relaunchPath;
@synthesize hostBundlePath = _hostBundlePath;
@synthesize updateURLBookmarkData = _updateURLBookmarkData;
@synthesize signatures = _signatures;
@synthesize decryptionPassword = _decryptionPassword;
@synthesize installationType = _installationType;
@synthesize expectedVersion = _expectedVersion;
@synthesize expectedContentLength = _expectedContentLength;

- (instancetype)initWithRelaunchPath:(NSString *)relaunchPath hostBundlePath:(NSString *)hostBundlePath updateURLBookmarkData:(NSData *)updateURLBookmarkData installationType:(NSString *)installationType signatures:(SUSignatures * _Nullable)signatures decryptionPassword:(nullable NSString *)decryptionPassword expectedVersion:(nonnull NSString *)expectedVersion expectedContentLength:(uint64_t)expectedContentLength
{
    self = [super init];
    if (self != nil) {
        _relaunchPath = [relaunchPath copy];
        _hostBundlePath = [hostBundlePath copy];
        _updateURLBookmarkData = updateURLBookmarkData;
        
        _installationType = [installationType copy];
        assert(SPUValidInstallationType(_installationType));
        
        _signatures = signatures;
        _decryptionPassword = [decryptionPassword copy];
        
        _expectedVersion = [expectedVersion copy];
        _expectedContentLength = expectedContentLength;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)decoder
{
    NSString *relaunchPath = [decoder decodeObjectOfClass:[NSString class] forKey:SURelaunchPathKey];
    if (relaunchPath == nil) {
        return nil;
    }
    
    NSString *hostBundlePath = [decoder decodeObjectOfClass:[NSString class] forKey:SUHostBundlePathKey];
    if (hostBundlePath == nil) {
        return nil;
    }
    
    NSData *updateURLBookmarkData = [decoder decodeObjectOfClass:[NSData class] forKey:SUUpdateURLBookmarkDataKey];
    if (updateURLBookmarkData == nil) {
        return nil;
    }
    
    NSString *installationType = [decoder decodeObjectOfClass:[NSString class] forKey:SUInstallationTypeKey];
    if (!SPUValidInstallationType(installationType)) {
        return nil;
    }
    
    SUSignatures *signatures = [decoder decodeObjectOfClass:[SUSignatures class] forKey:SUSignaturesKey];
    if (signatures == nil) {
        return nil;
    }
    
    NSString *decryptionPassword = [decoder decodeObjectOfClass:[NSString class] forKey:SUDecryptionPasswordKey];
    
    NSString *expectedVersion = [decoder decodeObjectOfClass:[NSString class] forKey:SUExpectedVersionKey];
    uint64_t expectedContentLength = (uint64_t)[decoder decodeInt64ForKey:SUExpectedContentLength];
    
    return [self initWithRelaunchPath:relaunchPath hostBundlePath:hostBundlePath updateURLBookmarkData:updateURLBookmarkData installationType:installationType signatures:signatures decryptionPassword:decryptionPassword expectedVersion:expectedVersion expectedContentLength:expectedContentLength];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_relaunchPath forKey:SURelaunchPathKey];
    [coder encodeObject:_hostBundlePath forKey:SUHostBundlePathKey];
    [coder encodeObject:_updateURLBookmarkData forKey:SUUpdateURLBookmarkDataKey];
    [coder encodeObject:_installationType forKey:SUInstallationTypeKey];
    [coder encodeObject:_signatures forKey:SUSignaturesKey];
    if (_decryptionPassword != nil) {
        [coder encodeObject:_decryptionPassword forKey:SUDecryptionPasswordKey];
    }
    if (_expectedVersion != nil) {
        [coder encodeObject:_expectedVersion forKey:SUExpectedVersionKey];
    }
    [coder encodeInt64:(int64_t)_expectedContentLength forKey:SUExpectedContentLength];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
