//
//  SPUDeltaArchiveProtocol.h
//  Autoupdate
//
//  Created by Mayur Pawashe on 12/28/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUDeltaCompressionMode.h"

NS_ASSUME_NONNULL_BEGIN

// Attributes for an item we extract/write to the archive

// Note: BinaryDiff cannot coexist together with Delete
typedef NS_ENUM(uint8_t, SPUDeltaItemCommands) {
    SPUDeltaItemCommandEndMarker = 0,
    SPUDeltaItemCommandDelete = (1u << 0),
    SPUDeltaItemCommandExtract = (1u << 1),
    SPUDeltaItemCommandModifyPermissions = (1u << 2),
    SPUDeltaItemCommandBinaryDiff = (1u << 3),
    SPUDeltaItemCommandClone = (1u << 4),
};

// Represents header for our archive
SPU_OBJC_DIRECT_MEMBERS @interface SPUDeltaArchiveHeader : NSObject

- (instancetype)initWithCompression:(SPUDeltaCompressionMode)compression compressionLevel:(uint8_t)compressionLevel fileSystemCompression:(bool)fileSystemCompression majorVersion:(uint16_t)majorVersion minorVersion:(uint16_t)minorVersion beforeTreeHash:(const unsigned char *)beforeTreeHash afterTreeHash:(const unsigned char *)afterTreeHash bundleCreationDate:(nullable NSDate *)bundleCreationDate;

@property (nonatomic, readonly) SPUDeltaCompressionMode compression;
@property (nonatomic, readonly) uint8_t compressionLevel;
@property (nonatomic, readonly) bool fileSystemCompression;
@property (nonatomic, readonly) uint16_t majorVersion;
@property (nonatomic, readonly) uint16_t minorVersion;
@property (nonatomic, readonly) unsigned char *beforeTreeHash;
@property (nonatomic, readonly) unsigned char *afterTreeHash;
@property (nonatomic, readonly, nullable) NSDate *bundleCreationDate;

@end

// Represents an item we read or write to in our delta archive
SPU_OBJC_DIRECT_MEMBERS @interface SPUDeltaArchiveItem : NSObject

- (instancetype)initWithRelativeFilePath:(NSString *)relativeFilePath commands:(SPUDeltaItemCommands)commands mode:(uint16_t)mode;

// The relative file path of the item, eg /Contents/MacOS/Foo
@property (nonatomic, readonly) NSString *relativeFilePath;
// For extraction, the path where the item will be extracted. For creation, the path to the item to add to the archive.
@property (nonatomic, nullable) NSString *itemFilePath;
// The relative file path of the originating item for clones. This may be null.
// For example, if /Contents/Resources/hello/foo.txt moves to /Contents/Resources/hello2/foo.txt, the former is the relative path
@property (nonatomic, nullable) NSString *clonedRelativePath;
// The source path of the item to extract file metadata from such as file size.
@property (nonatomic, nullable) NSString *sourcePath;
// The commands that describe the actions to take for this item.
@property (nonatomic, readonly) SPUDeltaItemCommands commands;
// Provided change in permissions for item or tracking file mode for the item
@property (nonatomic) uint16_t mode;

// Private properties
#if SPARKLE_BUILD_LEGACY_DELTA_SUPPORT
// xar_file context for Xar delta archiver
@property (nonatomic, nullable) const void *xarContext;
#endif
// Tracking length of item's data in data section, when encoding items and when extracting items
@property (nonatomic) uint64_t codedDataLength;

@end

// A protocol for reading and writing binary delta patches
// Operations must be done in order. The header must first be read or written before any other operations.
// For reading, file items cannot be extracted out of order.
@protocol SPUDeltaArchiveProtocol <NSObject>

@property (nonatomic, readonly, class) BOOL maySupportSafeExtraction;

// If non-nil, there was an error with reading or writing data from the archive
@property (nonatomic, readonly, nullable) NSError *error;

// Closes file for reading/writing, called in -dealloc if it's not called manually
- (void)close;

// For reading

// Retrieves metadata for the archive including major/minor version and expected bundle hashes
- (nullable SPUDeltaArchiveHeader *)readHeader;

// Enumerate through items in the patch file and read the path, attributes, permissions (if permission attribute is available), and way to stop enumeration
- (void)enumerateItems:(void (^)(SPUDeltaArchiveItem *item, BOOL *stop))itemHandler;

// Extract a file item from the patch file to a destination file
// The item's physical file path must be set as a destination
- (BOOL)extractItem:(SPUDeltaArchiveItem *)item;

// ------------

// For writing

// Set metadata for archive including major/minor version and expected bundle hashes
- (void)writeHeader:(SPUDeltaArchiveHeader *)header;

// Add item to patch file
// Physical file path must be provided if there is an extract or binary delta attribute
// Permissions are used only if there is a modify permissions attribute
- (void)addItem:(SPUDeltaArchiveItem *)item;

// Finishes encoding items after having added all of them
- (void)finishEncodingItems;

@end

NS_ASSUME_NONNULL_END
