//
//  SUBinaryDeltaCommon.h
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#ifndef SUBINARYDELTACOMMON_H
#define SUBINARYDELTACOMMON_H

#import <Foundation/Foundation.h>
#import "SPUDeltaCompressionMode.h"
#include <fts.h>

#define PERMISSION_FLAGS (S_IRWXU | S_IRWXG | S_IRWXO | S_ISUID | S_ISGID | S_ISVTX)
#define VALID_SYMBOLIC_LINK_PERMISSIONS 0755
// Enforcing Sparkle's executable permissions to be valid allows us to perform a preflight test before
// downloading delta items
#define VALID_SPARKLE_EXECUTABLE_PERMISSIONS 0755

#define APPLE_CODE_SIGN_XATTR_CODE_DIRECTORY_KEY "com.apple.cs.CodeDirectory"
#define APPLE_CODE_SIGN_XATTR_CODE_REQUIREMENTS_KEY "com.apple.cs.CodeRequirements"
#define APPLE_CODE_SIGN_XATTR_CODE_SIGNATURE_KEY "com.apple.cs.CodeSignature"

#define VERBOSE_DELETED "Deleted" // file is deleted from the file system when applying a patch
#define VERBOSE_REMOVED "Removed" // file is set to be removed when creating a patch
#define VERBOSE_ADDED "Added" // file is added to the patch or file system
#define VERBOSE_DIFFED "Diffed" // file is diffed when creating a patch
#define VERBOSE_PATCHED "Patched" // file is patched when applying a patch
#define VERBOSE_UPDATED "Updated" // file's contents are updated
#define VERBOSE_MODIFIED "Modified" // file's metadata is modified
#define VERBOSE_CLONED "Cloned" // file is cloned in content from a differently named file

// Relative path of custom icon data that may be set on a bundle via a resource fork
#define CUSTOM_ICON_PATH @"/Icon\r"

// Changes that break backwards compatibility will have different major versions
// Changes that affect creating but not applying patches will have different minor versions
typedef NS_ENUM(uint16_t, SUBinaryDeltaMajorVersion)
{
    // Note: support for creating or applying version 1 deltas have been removed
    SUBinaryDeltaMajorVersion1 = 1,
    SUBinaryDeltaMajorVersion2 = 2,
    SUBinaryDeltaMajorVersion3 = 3,
    SUBinaryDeltaMajorVersion4 = 4,
};

extern SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionDefault;
extern SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionLatest;
extern SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionFirst;
extern SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionFirstSupported;

// Additional compression methods for version 3 or 4 patches that we have for debugging are zlib, bzip2, none
#define COMPRESSION_METHOD_ARGUMENT_DESCRIPTION @"The compression method to use for generating delta updates. Supported methods for version 3 delta files are 'lzma' (best compression, slowest), 'lzfse' (good compression, fast), 'lz4' (worse compression, fastest), and 'default'. Note that version 2 delta files only support 'bzip2', and 'default' so other methods will be ignored if version 2 files are being generated. The 'default' compression for version 3 or 4 delta files is currently lzma."

//#define COMPRESSION_LEVEL_ARGUMENT_DESCRIPTION @"The compression level to use for generating delta updates. This only applies if the compression method used is bzip2 which accepts values from 1 - 9. A special value of 0 will use the default compression level."

// This is the same as CC_SHA1_DIGEST_LENGTH
// Major versions >= 4 use a crc32 hash (using a subset of these bytes) while older versions use a sha1 hash
#define BINARY_DELTA_HASH_LENGTH 20

SPUDeltaCompressionMode deltaCompressionModeFromDescription(NSString *description, BOOL *requestValid);
NSString *deltaCompressionStringFromMode(SPUDeltaCompressionMode mode);

extern int compareFiles(const FTSENT **a, const FTSENT **b);
BOOL getRawHashOfTreeWithVersion(void *hashBuffer, NSString *path, uint16_t majorVersion);
BOOL getRawHashOfTreeAndFileTablesWithVersion(void *hashBuffer, NSString *path, uint16_t majorVersion, NSMutableDictionary<NSData *, NSMutableArray<NSString *> *> *hashToFileKeyDictionary, NSMutableDictionary<NSString *, NSData *> *fileKeyToHashDictionary);
NSString *displayHashFromRawHash(const unsigned char *hash);
void getRawHashFromDisplayHash(unsigned char *hash, NSString *hexHash);
extern NSString *hashOfTreeWithVersion(NSString *path, uint16_t majorVersion);
extern NSString *hashOfTree(NSString *path);
extern BOOL removeTree(NSString *path);
extern BOOL copyTree(NSFileManager *fileManager, NSString *source, NSString *dest);
extern BOOL modifyPermissions(NSString *path, mode_t desiredPermissions);
extern NSString *pathRelativeToDirectory(NSString *directory, NSString *path);
NSString *temporaryFilename(NSString *base);
NSString *temporaryDirectory(NSString *base);
NSString *stringWithFileSystemRepresentation(const char*);
uint16_t latestMinorVersionForMajorVersion(SUBinaryDeltaMajorVersion majorVersion);
#endif
