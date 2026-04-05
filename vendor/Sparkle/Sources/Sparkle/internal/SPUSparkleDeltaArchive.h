//
//  SPUSparkleDeltaArchive.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SPUDeltaArchiveProtocol.h"
#import "SPUDeltaCompressionMode.h"

NS_ASSUME_NONNULL_BEGIN

#define SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN @"Sparkle Delta Archive"
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_MAGIC 1
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_COMPRESSION_VALUE 2
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_CHUNK_SIZE 3
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_CLONE_LOOKUP 4
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_TOO_MANY_FILES 5
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_LINK_TOO_LONG 6

/*
 Modern container format for binary delta archives.
 
 Delta archive format has four sections which are the header, the relative file path table, the commands, and the data blobs.
 
 The relative file path table records all the file paths the archive needs to know about.
 The commands are the operations to be recorded (eg: extract, clone, binary diff, delete).
 The commands may additionally have more metadata such as file permission modes, relative path indexes in the case of clones, or file sizes for the data blobs.
 The data blobs contain all file data from extract and binary diff outputs.
 
 The implementation design of this archive is such that we do not seek backwards or skip ahead to fetch data.
 We go through the archive when writing or reading from it in a single pass.
 
 -- UNCOMPRESSED --
 
 [ HEADER (part 1) ]
 magic (length: 4)
 compression (length: 1)
 metadata (See format below. length: 1)
 
    -- METADATA --
    compressionLevel (bits [0, 4])
    (bits [5, 6] reserved)
    fileSystemCompression (bit 7)
 
 -- COMPRESSED --
 
 [ HEADER (part 2)]
 majorVersion (length: 2)
 minorVersion (length: 2)
 beforeTreeHash (length: 40)
 afterTreeHash (length: 40)
 
 [ RELATIVE_FILE_PATH_TABLE ]
 sizeOfRelativeFilePathTable (length: 8 bytes)
 List of null terminated path strings joined together (N paths)
 
 [ COMMANDS ]
    [ Command ]
        Set of command types for entry (length: 1 byte)
        Additional metadata for command (see below section)
    (M commands where M <= N paths)
    (Indexes for commands refer to indexes to relative file path table, excluding extraneous trailing entries in relative path table used for clones)
    (Last command must be a ZERO COMMAND (a null terminating command))
 
    [COMMAND METADATA]
        [COMMAND: DELETE]
            N/A: no additional data
 
        [COMMAND: MODIFY_PERMISSIONS]
            fileMode (length: 2)
 
        [COMMAND: CLONE_FILE]
            sourceRelativePathIndex (length: 4)
        
        [COMMAND: EXTRACT_FILE]
            dataLength (length: 8 for regular files, 2 for symbolic links, 0 for directories)
        
        [COMMAND: BINARY_DIFF_FILE]
            dataLength (length: 8)
 
        Note: These command types may be OR'd or combined. In those cases, different commands
        that have the same attribute (eg dataLength) are not repeated. This list of metadata is also
        in order in what will be encoded/decoded first.
    
        EXTRACT_FILE and BINARY_DIFF_FILE cannot be combined.
        CLONE_FILE and EXTRACT_FILE cannot be combined.
        MODIFY_PERMISSIONS can be combined with either CLONE_FILE, EXTRACT_FILE, BINARY_DIFF_FILE, or just by itself.
        CLONE_FILE can be combined with BINARY_DIFF_FILE or just by itself.
        DELETE can be combined with EXTRACT_FILE, or just by itself. It is only combined with EXTRACT_FILE when the file type (regular, directory, or symlink) changes.
 
 [ DATA_BLOBS ]
 All raw binary data joined together
 (P number of blobs where P <= M commands)
 (Indexes for data blobs correspond to indexes for a filtered list of applicable commands (EXTRACT_FILE, BINARY_DIFF_FILE) that have data content)
 */
SPU_OBJC_DIRECT_MEMBERS @interface SPUSparkleDeltaArchive : NSObject <SPUDeltaArchiveProtocol>

- (instancetype)initWithPatchFileForWriting:(NSString *)patchFile;
- (instancetype)initWithPatchFileForReading:(NSString *)patchFile;

@end

NS_ASSUME_NONNULL_END
