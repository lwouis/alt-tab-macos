//
//  SULocalCacheDirectory.h
//  Sparkle
//
//  Created by Mayur Pawashe on 6/23/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SPULocalCacheDirectory : NSObject

// Returns a path to a suitable cache directory to create specifically for Sparkle
// Intermediate directories to this path may not exist yet
// This path may depend on the type of running process,
// such that sandboxed vs non-sandboxed processes could yield different paths
// The caller should create a subdirectory from the path that is returned here so they don't have files that
// conflict with other callers. Once that subdirectory name is decided, the caller can remove old items inside it (using +removeOldItemsInDirectory:)
// and then create a unique temporary directory inside it (using +createUniqueDirectoryInDirectory:)
+ (NSString *)cachePathForBundleIdentifier:(NSString *)bundleIdentifier;

// Variant of cachePathForBundleIdentifier: that specifies a userName to create the cache path for
// Only use this when running from as root
+ (NSString *)cachePathForBundleIdentifier:(NSString *)bundleIdentifier userName:(NSString *)userName;

// Remove old files inside a directory
// A caller may want to invoke this on a directory they own rather than remove and re-create an entire directory
// This does nothing if the supplied directory does not exist yet
+ (void)removeOldItemsInDirectory:(NSString *)directory;

// Create a unique directory inside a parent directory
// The parent directory doesn't have to exist yet. If it doesn't exist, intermediate directories will be created.
+ (NSString * _Nullable)createUniqueDirectoryInDirectory:(NSString *)directory;
+ (NSString * _Nullable)createUniqueDirectoryInDirectory:(NSString *)directory intermediateDirectoryFileAttributes:(nullable NSDictionary<NSFileAttributeKey, id> *)attributes;

@end

NS_ASSUME_NONNULL_END
