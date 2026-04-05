//
//  SPUDeltaCompressionMode.h
//  Sparkle
//
//  Created by Mayur Pawashe on 1/3/22.
//  Copyright © 2022 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

// Compression mode to use during patch creation
typedef NS_ENUM(uint8_t, SPUDeltaCompressionMode) {
    SPUDeltaCompressionModeNone = 0,
    SPUDeltaCompressionModeBzip2,
    SPUDeltaCompressionModeLZMA,
    SPUDeltaCompressionModeLZFSE,
    SPUDeltaCompressionModeLZ4,
    SPUDeltaCompressionModeZLIB
};

// For Swift access
extern SPUDeltaCompressionMode SPUDeltaCompressionModeDefault;
