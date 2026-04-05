//
//  SUBinaryDeltaUnarchiver.h
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-03.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#ifndef SUBINARYDELTAUNARCHIVER_H
#define SUBINARYDELTAUNARCHIVER_H

#import <Foundation/Foundation.h>
#import "SUUnarchiverProtocol.h"

NS_ASSUME_NONNULL_BEGIN

#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT_MEMBERS
#endif
@interface SUBinaryDeltaUnarchiver : NSObject <SUUnarchiverProtocol>

- (instancetype)initWithArchivePath:(NSString *)archivePath extractionDirectory:(NSString *)extractionDirectory updateHostBundlePath:(NSString *)updateHostBundlePath;

+ (BOOL)canUnarchivePath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END

#endif
