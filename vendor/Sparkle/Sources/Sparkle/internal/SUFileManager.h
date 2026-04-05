//
//  SUFileManager.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/18/15.
//  Copyright (c) 2015 zgcoder. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUExport.h"

NS_ASSUME_NONNULL_BEGIN

#ifndef BUILDING_SPARKLE_TESTS
#define SUFileManagerDefinitionAttribute SPU_OBJC_DIRECT_MEMBERS
#else
#define SUFileManagerDefinitionAttribute __attribute__((objc_runtime_name("SUTestFileManager")))
#endif

/**
 * A class used for performing file operations more suitable than NSFileManager for performing installation work.
 * All operations on this class may be used on thread other than the main thread.
 * This class provides just basic file operations and stays away from including much application-level logic.
 */
SUFileManagerDefinitionAttribute
@interface SUFileManager : NSObject

/**
 * Creates a temporary directory on the same volume as a provided URL
 * @param appropriateURL A URL to a directory that resides on the volume that the temporary directory will be created on. In the uncommon case, the temporary directory may be created inside this directory.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return A URL pointing to the newly created temporary directory, or nil with a populated error object if an error occurs.
 *
 * When moving an item from a source to a destination, it is desirable to create a temporary intermediate destination on the same volume as the destination to ensure
 * that the item will be moved, and not copied, from the intermediate point to the final destination. This ensures file atomicity.
 */
- (NSURL * _Nullable)makeTemporaryDirectoryAppropriateForDirectoryURL:(NSURL *)appropriateURL error:(NSError * __autoreleasing *)error;

/**
 * Creates a directory at the target URL
 * @param targetURL A URL pointing to the directory to create. The item at this URL must not exist, and the parent directory of this URL must already exist.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return YES if the item was created successfully, otherwise NO along with a populated error object
 *
 * This is an atomic operation.
 */
- (BOOL)makeDirectoryAtURL:(NSURL *)targetURL error:(NSError **)error;

/**
 * Moves an item from a source to a destination
 * @param sourceURL A URL pointing to the item to move. The item at this URL must exist.
 * @param destinationURL A URL pointing to the destination the item will be moved at. An item must not already exist at this URL.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return YES if the item was moved successfully, otherwise NO along with a populated error object
 *
 * If sourceURL and destinationURL reside on the same volume, this operation will be an atomic move operation.
 * Otherwise this will be equivalent to a copy & remove which will be a nonatomic operation.
 */
- (BOOL)moveItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL error:(NSError **)error;

/**
 * Swaps an original item with a new item atomically.
 * @param originalItemURL A URL pointing to the original item to replace. The item at this URL must exist.
 * @param newItemURL A URL pointing to the new item that will replace the original item.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return YES if the original item was replaced with the new item successfully, otherwise NO along with a populated error object
 *
 * originalItemURL and newItemURL must reside on the same volume. If the operation succeeds, this will be be an atomic operation.
 * Otherwise on failure you may need to re-try using move operations. This operation will fail on non-apfs volumes or volumes that don't support rename swapping.
 * Both originalItemURL and newItemURL must exist.
 */
- (BOOL)swapItemAtURL:(NSURL *)originalItemURL withItemAtURL:(NSURL *)newItemURL error:(NSError **)error;

/**
 * Checks if two URLs are on the same volume.
 * @param url1 A URL pointing to the first item
 * @param url2 A URL pointing to the second item
 * @return YES if both URLs are on the same volume, otherwise NO
 *
 * If any volume retrieval error occurs during the process, this method assumes both items are on the same volume (which is the common case).
 */
- (BOOL)itemAtURL:(NSURL *)url1 isOnSameVolumeItemAsURL:(NSURL *)url2;

/**
 * Copies an item from a source to a destination
 * @param sourceURL A URL pointing to the item to move. The item at this URL must exist.
 * @param destinationURL A URL pointing to the destination the item will be moved at. An item must not already exist at this URL.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return YES if the item was copied successfully, otherwise NO along with a populated error object
 *
 * This is not an atomic operation.
 */
- (BOOL)copyItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL error:(NSError **)error;

/**
 * Removes an item at a URL
 * @param url A URL pointing to the item to remove. The item at this URL must exist.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return YES if the item was removed successfully, otherwise NO along with a populated error object
 *
 * This is not an atomic operation.
 */
- (BOOL)removeItemAtURL:(NSURL *)url error:(NSError **)error;

/**
 * Changes the owner and group IDs of an item at a specified target URL to match another URL
 * @param targetURL A URL pointing to the target item whose owner and group IDs to alter. This will be applied recursively if the item is a directory. The item at this URL must exist.
 * @param matchURL A URL pointing to the item whose owner and group IDs will be used for changing on the targetURL. The item at this URL must exist.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return YES if the target item's owner and group IDs have changed to match the origin's ones, otherwise NO along with a populated error object
 *
 * If the owner and group IDs match on the root items of targetURL and matchURL, this method stops and assumes that nothing needs to be done.
 * Otherwise this method recursively changes the IDs if the target is a directory. If an item in the directory is encountered that is unable to be changed,
 * then this method stops and returns NO.
 * While this method will try to change the group ID, being unable to change the group ID does not result in a failure if the owner ID can be changed or matched.
 *
 * This is not an atomic operation.
 */
- (BOOL)changeOwnerAndGroupOfItemAtRootURL:(NSURL *)targetURL toMatchURL:(NSURL *)matchURL error:(NSError **)error;

/**
 Changes the owner and group ID of an item at a specified target URL
 @param targetURL A URL pointing to the target item whose owner and group IDs to alter. The item at this URL must exist.
 @param ownerID The new owner ID to set on the item.
 @param groupID The new group ID to set on the item.
 @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 @return YES if the target item's owner and group IDs have changed, otherwise NO along with a populated error object.
 
 Unlike -changeOwnerAndGroupOfItemAtRootURL:toMatchURL:error: this method does not recursively try to change the owner and group IDs if the target item is a directory.
 */
- (BOOL)changeOwnerAndGroupOfItemAtURL:(NSURL *)targetURL ownerID:(uid_t)ownerID groupID:(gid_t)groupID error:(NSError * __autoreleasing *)error;

/**
 * Updates the modification and access time of an item at a specified target URL to the current time
 * @param targetURL A URL pointing to the target item whose modification and access time to update. The item at this URL must exist.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return YES if the target item's modification and access times have been updated, otherwise NO along with a populated error object
 *
 * This method updates the modification and access time of an item to the current time, ideal for letting the system know we installed a new file or
 * application.
 *
 * This is not an atomic operation.
 */
- (BOOL)updateModificationAndAccessTimeOfItemAtURL:(NSURL *)targetURL error:(NSError **)error;

/**
 * Updates the access time of an item at a specified root URL to the current time
 * @param targetURL A URL pointing to the target item whose access time to update to the current time.
 * This will be applied recursively if the item is a directory. The item at this URL must exist.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return YES if the target item's access times have been updated, otherwise NO along with a populated error object
 *
 * This method updates the access time of an item to the current time, ideal for letting the system know not to remove a file or directory when placing it
 * at a temporary directory.
 *
 * This is not an atomic operation.
 */
- (BOOL)updateAccessTimeOfItemAtRootURL:(NSURL *)targetURL error:(NSError * __autoreleasing *)error;

/**
 * Releases Apple's quarantine extended attribute from the item at the specified root URL
 * @param rootURL A URL pointing to the item to release from Apple's quarantine. This will be applied recursively if the item is a directory. The item at this URL must exist.
 * @param error If an error occurs, upon returns contains an NSError object that describes the problem. If you are not interested in possible errors, you may pass in NULL.
 * @return YES if all the items at the target could be released from quarantine, otherwise NO if any items couldn't along with a populated error object
 *
 * This method removes quarantine attributes from an item, ideally an application, so that when the user launches a new application themselves, they
 * don't have to witness the system dialog alerting them that they downloaded an application from the internet and asking if they want to continue.
 * Note that this may not exactly mimic the system behavior when a user opens an application for the first time (i.e, the xattr isn't deleted),
 * but this should be sufficient enough for our purposes.
 *
 * This method may return NO even if some items do get released from quarantine if the target URL is pointing to a directory.
 * Thus if an item cannot be released from quarantine, this method still continues on to the next enumerated item.
 *
 * This is not an atomic operation.
 */
- (BOOL)releaseItemFromQuarantineAtRootURL:(NSURL *)rootURL error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
