//
//  SUFileManager.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/18/15.
//  Copyright (c) 2015 zgcoder. All rights reserved.
//

#import "SUFileManager.h"
#import "SUErrors.h"

#include <sys/xattr.h>
#include <sys/errno.h>
#include <sys/time.h>
#include <sys/stat.h>


#include "AppKitPrevention.h"

extern int renamex_np(const char *, const char *, unsigned int) __attribute__((weak_import));

static char SUAppleQuarantineIdentifier[] = "com.apple.quarantine";

@implementation SUFileManager
{
    NSFileManager *_fileManager;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _fileManager = [[NSFileManager alloc] init];
    }
    return self;
}

// -[NSFileManager attributesOfItemAtPath:error:] won't follow symbolic links

- (BOOL)_itemExistsAtURL:(NSURL *)fileURL
#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT
#endif
{
    NSString *path = fileURL.path;
    if (path == nil) {
        return NO;
    }
    return [_fileManager attributesOfItemAtPath:path error:NULL] != nil;
}

- (BOOL)_itemExistsAtURL:(NSURL *)fileURL isDirectory:(BOOL *)isDirectory
#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT
#endif
{
    NSString *path = fileURL.path;
    if (path == nil) {
        return NO;
    }

    NSDictionary *attributes = [_fileManager attributesOfItemAtPath:path error:NULL];
    if (attributes == nil) {
        return NO;
    }

    if (isDirectory != NULL) {
        *isDirectory = [(NSString *)[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory];
    }

    return YES;
}

// Wrapper around getxattr()
- (ssize_t)_getXAttr:(const char *)name fromFile:(NSString *)file options:(int)options SPU_OBJC_DIRECT
{
    char path[PATH_MAX] = {0};
    if (![file getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        errno = 0;
        return -1;
    }

    return getxattr(path, name, NULL, 0, 0, options);
}

// Wrapper around removexattr()
- (int)_removeXAttr:(const char *)attr fromFile:(NSString *)file options:(int)options SPU_OBJC_DIRECT
{
    char path[PATH_MAX] = {0};
    if (![file getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        errno = 0;
        return -1;
    }

    return removexattr(path, attr, options);
}

// Removes the directory tree rooted at |root| from the file quarantine.
// The quarantine was introduced on macOS 10.5 and is described at:
//
// http://developer.apple.com/releasenotes/Carbon/RN-LaunchServices/index.html#apple_ref/doc/uid/TP40001369-DontLinkElementID_2
//
// If |root| is not a directory, then it alone is removed from the quarantine.
// Symbolic links, including |root| if it is a symbolic link, will not be
// traversed.

// Ordinarily, the quarantine is managed by calling LSSetItemAttribute
// to set the kLSItemQuarantineProperties attribute to a dictionary specifying
// the quarantine properties to be applied.  However, it does not appear to be
// possible to remove an item from the quarantine directly through any public
// Launch Services calls.  Instead, this method takes advantage of the fact
// that the quarantine is implemented in part by setting an extended attribute,
// "com.apple.quarantine", on affected files.  Removing this attribute is
// sufficient to remove files from the quarantine.

// This works by removing the quarantine extended attribute for every file we come across.
// We used to have code similar to the method below that used -[NSURL getResourceValue:forKey:error:] and -[NSURL setResourceValue:forKey:error:]
// However, those methods *really suck* - you can't rely on the return value from getting the resource value and if you set the resource value
// when the key isn't present, errors are spewed out to the console
- (BOOL)releaseItemFromQuarantineAtRootURL:(NSURL *)rootURL error:(NSError *__autoreleasing *)error
{
    static const int removeXAttrOptions = XATTR_NOFOLLOW;
    BOOL success = YES;

    // First remove quarantine on the root item
    NSString *rootURLPath = rootURL.path;
    if ([self _getXAttr:SUAppleQuarantineIdentifier fromFile:rootURLPath options:removeXAttrOptions] >= 0) {
        BOOL removedRootQuarantine = ([self _removeXAttr:SUAppleQuarantineIdentifier fromFile:rootURLPath options:removeXAttrOptions] == 0);
        if (!removedRootQuarantine) {
            success = NO;
            
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to remove file quarantine on %@.", rootURL.lastPathComponent] }];
            }
        }
    }
    
    // Only recurse if it's actually a directory.  Don't recurse into a root-level symbolic link.
    // Even if we fail removing the quarantine from the root item or any single item in the directory, we will continue trying to remove the quarantine.
    // This is because often it may not be a fatal error from the caller to not remove the quarantine of an item
    NSDictionary *rootAttributes = [_fileManager attributesOfItemAtPath:rootURLPath error:nil];
    NSString *rootType = rootAttributes[NSFileType];
    
    if ([rootType isEqualToString:NSFileTypeDirectory]) {
        // The NSDirectoryEnumerator will avoid recursing into any contained
        // symbolic links, so no further type checks are needed.
        NSDirectoryEnumerator *directoryEnumerator = [_fileManager enumeratorAtURL:rootURL includingPropertiesForKeys:nil options:(NSDirectoryEnumerationOptions)0 errorHandler:nil];
        
        for (NSURL *fileURL in directoryEnumerator) {
            if ([self _getXAttr:SUAppleQuarantineIdentifier fromFile:fileURL.path options:removeXAttrOptions] >= 0) {
                BOOL removedQuarantine = ([self _removeXAttr:SUAppleQuarantineIdentifier fromFile:fileURL.path options:removeXAttrOptions] == 0);
                
                if (!removedQuarantine && success) {
                    success = NO;
                    
                    if (error != NULL) {
                        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to remove file quarantine on %@.", fileURL.lastPathComponent] }];
                    }
                }
            }
        }
    }
    return success;
}

- (BOOL)copyItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL error:(NSError * __autoreleasing *)error
{
    return [_fileManager copyItemAtURL:sourceURL toURL:destinationURL error:error];
}

- (BOOL)_getVolumeID:(out id _Nullable __autoreleasing * _Nonnull)outVolumeIdentifier ofItemAtURL:(NSURL *)url SPU_OBJC_DIRECT
{
    NSError *error = nil;
    return [url getResourceValue:outVolumeIdentifier forKey:NSURLVolumeIdentifierKey error:&error];
}

- (BOOL)itemAtURL:(NSURL *)url1 isOnSameVolumeItemAsURL:(NSURL *)url2
{
    id volumeIdentifier1 = nil;
    BOOL foundVolume1 = [self _getVolumeID:&volumeIdentifier1 ofItemAtURL:url1];

    id volumeIdentifier2 = nil;
    BOOL foundVolume2 = [self _getVolumeID:&volumeIdentifier2 ofItemAtURL:url2];

    if (foundVolume1 && foundVolume2 && ![(NSObject *)volumeIdentifier1 isEqual:volumeIdentifier2]) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)moveItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL error:(NSError *__autoreleasing *)error
{
    if (![self _itemExistsAtURL:sourceURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Source file to move (%@) does not exist.", sourceURL.lastPathComponent] }];
        }
        return NO;
    }

    NSURL *destinationURLParent = destinationURL.URLByDeletingLastPathComponent;
    if (![self _itemExistsAtURL:destinationURLParent]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Destination parent directory to move into (%@) does not exist.", destinationURLParent.lastPathComponent] }];
        }
        return NO;
    }

    if ([self _itemExistsAtURL:destinationURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Destination file to move (%@) already exists.", destinationURL.lastPathComponent] }];
        }
        return NO;
    }

    // If the source and destination are on different volumes, we should not do a move;
    // from my experience a move may fail when moving particular files from
    // one network mount to another one. This is possibly related to the fact that
    // moving a file will try to preserve ownership but copying won't
    
    if (![self itemAtURL:sourceURL isOnSameVolumeItemAsURL:destinationURLParent]) {
        return ([self copyItemAtURL:sourceURL toURL:destinationURL error:error] && [self removeItemAtURL:sourceURL error:error]);
    }

    return [_fileManager moveItemAtURL:sourceURL toURL:destinationURL error:error];
}

- (BOOL)swapItemAtURL:(NSURL *)originalItemURL withItemAtURL:(NSURL *)newItemURL error:(NSError * __autoreleasing *)error
{
    char originalPath[PATH_MAX] = {0};
    if (![originalItemURL.path getFileSystemRepresentation:originalPath maxLength:sizeof(originalPath)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Original item %@ to replace cannot be represented as a valid file name", originalItemURL.lastPathComponent] }];
        }
        return NO;
    }
    
    char newPath[PATH_MAX] = {0};
    if (![newItemURL.path getFileSystemRepresentation:newPath maxLength:sizeof(newPath)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"New item %@ to replace cannot be represented as a valid file name", newItemURL.lastPathComponent] }];
        }
        return NO;
    }
    
    int status = renamex_np(newPath, originalPath, RENAME_SWAP);
    if (status != 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to replace %@ with %@.", originalItemURL.lastPathComponent, newItemURL.lastPathComponent] }];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)changeOwnerAndGroupOfItemAtURL:(NSURL *)targetURL ownerID:(uid_t)ownerID groupID:(gid_t)groupID error:(NSError * __autoreleasing *)error
{
    char path[PATH_MAX] = {0};
    if (![targetURL.path getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File to change owner & group (%@) cannot be represented as a valid file name.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }

    int fileDescriptor = open(path, O_RDONLY | O_SYMLINK);
    if (fileDescriptor == -1) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open file descriptor to %@", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    // We use fchown instead of chown because the latter can follow symbolic links
    BOOL success = (fchown(fileDescriptor, ownerID, groupID) == 0);
    close(fileDescriptor);
    
    if (!success) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to change owner & group for %@ with owner ID %u and group ID %u.", targetURL.path.lastPathComponent, ownerID, groupID] }];
        }
    }

    return success;
}

- (BOOL)changeOwnerAndGroupOfItemAtRootURL:(NSURL *)targetURL toMatchURL:(NSURL *)matchURL error:(NSError * __autoreleasing *)error
{
    BOOL isTargetADirectory = NO;
    if (![self _itemExistsAtURL:targetURL isDirectory:&isTargetADirectory]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to change owner & group IDs because %@ does not exist.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }

    if (![self _itemExistsAtURL:matchURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to match owner & group IDs because %@ does not exist.", matchURL.path.lastPathComponent] }];
        }
        return NO;
    }

    NSError *matchFileAttributesError = nil;
    NSString *matchURLPath = matchURL.path;
    NSDictionary *matchFileAttributes = [_fileManager attributesOfItemAtPath:matchURLPath error:&matchFileAttributesError];
    if (matchFileAttributes == nil) {
        if (error != NULL) {
            *error = matchFileAttributesError;
        }
        return NO;
    }

    NSError *targetFileAttributesError = nil;
    NSString *targetURLPath = targetURL.path;
    NSDictionary *targetFileAttributes = [_fileManager attributesOfItemAtPath:targetURLPath error:&targetFileAttributesError];
    if (targetFileAttributes == nil) {
        if (error != NULL) {
            *error = targetFileAttributesError;
        }
        return NO;
    }

    NSNumber *ownerID = [matchFileAttributes objectForKey:NSFileOwnerAccountID];
    if (ownerID == nil) {
        // shouldn't be possible to error here, but just in case
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoPermissionError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Owner ID could not be read from %@.", matchURL.path.lastPathComponent] }];
        }
        return NO;
    }

    NSNumber *groupID = [matchFileAttributes objectForKey:NSFileGroupOwnerAccountID];
    if (groupID == nil) {
        // shouldn't be possible to error here, but just in case
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoPermissionError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Group ID could not be read from %@.", matchURL.path.lastPathComponent] }];
        }
        return NO;
    }

    NSNumber *targetOwnerID = [targetFileAttributes objectForKey:NSFileOwnerAccountID];
    NSNumber *targetGroupID = [targetFileAttributes objectForKey:NSFileGroupOwnerAccountID];

    if ((targetOwnerID != nil && [ownerID isEqualToNumber:targetOwnerID]) && (targetGroupID != nil && [groupID isEqualToNumber:targetGroupID])) {
        // Assume they're the same even if we don't check every file recursively
        // Speeds up the common case
        return YES;
    }
    
    // If we can't change both the new owner & group, try to only change the owner
    // If this works, this is sufficient enough for performing the update
    NSNumber *groupIDToUse;
    if (![self changeOwnerAndGroupOfItemAtURL:targetURL ownerID:ownerID.unsignedIntValue groupID:groupID.unsignedIntValue error:NULL]) {
        if ((targetOwnerID != nil && [ownerID isEqualToNumber:targetOwnerID])) {
            // Assume they're the same even if we don't check every file recursively
            // Speeds up the common case like above
            return YES;
        }
        
        if (![self changeOwnerAndGroupOfItemAtURL:targetURL ownerID:ownerID.unsignedIntValue groupID:targetGroupID.unsignedIntValue error:error]) {
            return NO;
        }
        
        groupIDToUse = targetGroupID;
    } else {
        groupIDToUse = groupID;
    }

    if (isTargetADirectory) {
        NSDirectoryEnumerator *directoryEnumerator = [_fileManager enumeratorAtURL:targetURL includingPropertiesForKeys:nil options:(NSDirectoryEnumerationOptions)0 errorHandler:nil];
        for (NSURL *url in directoryEnumerator) {
            if (![self changeOwnerAndGroupOfItemAtURL:url ownerID:ownerID.unsignedIntValue groupID:groupIDToUse.unsignedIntValue error:error]) {
                return NO;
            }
        }
    }
    
    return YES;
}

- (BOOL)_updateItemAtURL:(NSURL *)targetURL withAccessTime:(struct timeval)accessTime error:(NSError * __autoreleasing *)error SPU_OBJC_DIRECT
{
    char path[PATH_MAX] = {0};

    // NOTE: At least on Mojave 10.14.1, running on an APFS filesystem, the act of asking
    // for a path's file system representation causes the access time of the containing folder
    // to be updated. Callers should take care when attempting to set a recursive directory's
    // access time to ensure that the inner-most items get set first, so that the implicitly
    // updated access times are replaced after this side-effect occurs.
    if (![targetURL.path getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File to update modification & access time (%@) cannot be represented as a valid file name.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }

    int fileDescriptor = open(path, O_RDONLY | O_SYMLINK);
    if (fileDescriptor == -1) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open file descriptor to %@", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    struct stat statInfo;
    if (fstat(fileDescriptor, &statInfo) != 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to stat file descriptor to %@", targetURL.path.lastPathComponent] }];
        }
        close(fileDescriptor);
        return NO;
    }

    // Preserve the modification time
    struct timeval modTime;
    TIMESPEC_TO_TIMEVAL(&modTime, &statInfo.st_mtimespec)
    
    const struct timeval timeInputs[] = {accessTime, modTime};
    
    // Using futimes() because utimes() follows symbolic links
    BOOL updatedTime = (futimes(fileDescriptor, timeInputs) == 0);
    
    close(fileDescriptor);
    
    if (!updatedTime) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to update modification & access time for %@", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)updateAccessTimeOfItemAtRootURL:(NSURL *)targetURL error:(NSError * __autoreleasing *)error
{
    if (![self _itemExistsAtURL:targetURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to update modification & access time recursively because %@ does not exist.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    // We want to update all files with the same exact time
    struct timeval currentTime = {0, 0};
    if (gettimeofday(&currentTime, NULL) != 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to update modification & access time recursively because gettimeofday failed."] }];
        }
        return NO;
    }

    NSString *rootURLPath = targetURL.path;
    NSDictionary *rootAttributes = [_fileManager attributesOfItemAtPath:rootURLPath error:nil];
    NSString *rootType = [rootAttributes objectForKey:NSFileType];

    // Only recurse if it's actually a directory.  Don't recurse into a
    // root-level symbolic link.
    if ([rootType isEqualToString:NSFileTypeDirectory]) {
        // The NSDirectoryEnumerator will avoid recursing into any contained
        // symbolic links, so no further type checks are needed.
        NSDirectoryEnumerator *directoryEnumerator = [_fileManager enumeratorAtURL:targetURL includingPropertiesForKeys:nil options:(NSDirectoryEnumerationOptions)0 errorHandler:nil];
        
        for (NSURL *file in directoryEnumerator) {
            if (![self _updateItemAtURL:file withAccessTime:currentTime error:error]) {
                return NO;
            }
        }
    }

    // Set the access time on the container last because the process of setting the access
    // time on children actually causes the access time of the container directory to be
    // updated.
    if (![self _updateItemAtURL:targetURL withAccessTime:currentTime error:error]) {
        return NO;
    }

    return YES;
}

// /usr/bin/touch can be used to update an application, as described in:
// https://developer.apple.com/library/mac/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html
// The document says LSRegisterURL() can be used as well but this hasn't worked out well for me in practice
// Anyway, updating the modification time of the application is important because the system will be aware a new version of your app is available,
// Finder will report the correct file size and other metadata for it, URL schemes your app may register will be updated, etc.
// Behind the scenes, touch calls to utimes() which is what we use here
- (BOOL)updateModificationAndAccessTimeOfItemAtURL:(NSURL *)targetURL error:(NSError * __autoreleasing *)error
{
    if (![self _itemExistsAtURL:targetURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to update modification & access time because %@ does not exist.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }

    char path[PATH_MAX] = {0};
    if (![targetURL.path getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File to update modification & access time (%@) cannot be represented as a valid file name.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }

    int fileDescriptor = open(path, O_RDONLY | O_SYMLINK);
    if (fileDescriptor == -1) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open file descriptor to %@", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    // Using futimes() because utimes() follows symbolic links
    BOOL updatedTime = (futimes(fileDescriptor, NULL) == 0);
    close(fileDescriptor);
    
    if (!updatedTime) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to update modification & access time for %@", targetURL.path.lastPathComponent] }];
        }
    }
    
    return updatedTime;
}

// Creates a directory at the item pointed by url
// An item cannot already exist at the url, but the parent must be a directory that exists
- (BOOL)makeDirectoryAtURL:(NSURL *)url error:(NSError * __autoreleasing *)error
{
    if ([self _itemExistsAtURL:url]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create directory because file %@ already exists.", url.path.lastPathComponent] }];
        }
        return NO;
    }

    NSURL *parentURL = [url URLByDeletingLastPathComponent];
    BOOL isParentADirectory = NO;
    if (![self _itemExistsAtURL:parentURL isDirectory:&isParentADirectory] || !isParentADirectory) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create directory because parent directory %@ does not exist.", parentURL.path.lastPathComponent] }];
        }
        return NO;
    }

    NSError *createDirectoryError = nil;
    if (![_fileManager createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:&createDirectoryError]) {
        if (error != NULL) {
            *error = createDirectoryError;
        }
        return NO;
    }

    return YES;
}

- (NSURL *)makeTemporaryDirectoryAppropriateForDirectoryURL:(NSURL *)directoryURL error:(NSError * __autoreleasing *)error
{
    return [_fileManager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:directoryURL create:YES error:error];
}

- (BOOL)removeItemAtURL:(NSURL *)url error:(NSError * __autoreleasing *)error
{
    if (![self _itemExistsAtURL:url]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to remove file %@ because it does not exist.", url.path.lastPathComponent] }];
        }
        return NO;
    }

    NSError *removeError = nil;
    if (![_fileManager removeItemAtURL:url error:&removeError]) {
        if (error != NULL) {
            *error = removeError;
        }
        return NO;
    }

    return YES;
}

@end
