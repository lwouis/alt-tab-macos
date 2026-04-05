//
//  SULocalCacheDirectory.m
//  Sparkle
//
//  Created by Mayur Pawashe on 6/23/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPULocalCacheDirectory.h"
#import "SULog.h"


#include "AppKitPrevention.h"

static NSTimeInterval OLD_ITEM_DELETION_INTERVAL = 86400 * 10; // 10 days

@implementation SPULocalCacheDirectory

+ (NSString *)_cachePathForCacheDirectory:(NSURL *)cacheURL bundleIdentifier:(NSString *)bundleIdentifier SPU_OBJC_DIRECT
{
    NSString *resultPath = [[[cacheURL URLByAppendingPathComponent:bundleIdentifier isDirectory:YES] URLByAppendingPathComponent:@SPARKLE_BUNDLE_IDENTIFIER isDirectory:YES] path];
    assert(resultPath != nil);
    
    return resultPath;
}

// It is important to note this may return a different path whether invoked from a sanboxed vs non-sandboxed process
// For this reason, this method should not be a part of SUHost because its behavior depends on what kind of process it's being invoked from
+ (NSString *)cachePathForBundleIdentifier:(NSString *)bundleIdentifier
{
    NSURL *cacheURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];
    assert(cacheURL != nil);
    
    return [self _cachePathForCacheDirectory:cacheURL bundleIdentifier:bundleIdentifier];
}

+ (NSString *)cachePathForBundleIdentifier:(NSString *)bundleIdentifier userName:(NSString *)userName
{
    NSString *homeDirectory = NSHomeDirectoryForUser(userName);
    assert(homeDirectory != nil);
    
    NSURL *homeDirectoryURL = [NSURL fileURLWithPath:homeDirectory isDirectory:YES];
    
    NSURL *cacheURL = [[homeDirectoryURL URLByAppendingPathComponent:@"Library" isDirectory:YES] URLByAppendingPathComponent:@"Caches" isDirectory:YES];
    assert(cacheURL != nil);
    
    return [self _cachePathForCacheDirectory:cacheURL bundleIdentifier:bundleIdentifier];
}

+ (void)removeOldItemsInDirectory:(NSString *)directory
{
    NSMutableArray<NSString *> *filePathsToRemove = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:directory]) {
        NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:directory];
        NSDate *currentDate = [NSDate date];
        for (NSString *filename in directoryEnumerator)
        {
            NSDictionary<NSString *, id> *fileAttributes = [fileManager attributesOfItemAtPath:[directory stringByAppendingPathComponent:filename] error:NULL];
            if (fileAttributes != nil)
            {
                NSDate *lastModificationDate = [fileAttributes objectForKey:NSFileModificationDate];
                if ([currentDate timeIntervalSinceDate:lastModificationDate] >= OLD_ITEM_DELETION_INTERVAL)
                {
                    [filePathsToRemove addObject:[directory stringByAppendingPathComponent:filename]];
                }
            }
            
            [directoryEnumerator skipDescendants];
        }
        
        for (NSString *filename in filePathsToRemove)
        {
            [fileManager removeItemAtPath:filename error:NULL];
        }
    }
}

+ (NSString * _Nullable)createUniqueDirectoryInDirectory:(NSString *)directory intermediateDirectoryFileAttributes:(NSDictionary<NSFileAttributeKey, id> *)intermediateDirectoryFileAttributes
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *createError = nil;
    if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:intermediateDirectoryFileAttributes error:&createError]) {
        SULog(SULogLevelError, @"Failed to create directory with intermediate components at %@ with error %@", directory, createError);
        return nil;
    }
    
    NSString *templateString = [directory stringByAppendingPathComponent:@"XXXXXXXXX"];
    char buffer[PATH_MAX] = {0};
    if ([templateString getFileSystemRepresentation:buffer maxLength:sizeof(buffer)]) {
        if (mkdtemp(buffer) != NULL) {
            return [[NSString alloc] initWithUTF8String:buffer];
        }
    }
    return nil;
}

+ (NSString * _Nullable)createUniqueDirectoryInDirectory:(NSString *)directory
{
    return [self createUniqueDirectoryInDirectory:directory intermediateDirectoryFileAttributes:nil];
}

@end
