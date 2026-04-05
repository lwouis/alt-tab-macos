//
//  SUDiskImageUnarchiver.h
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUDISKIMAGEUNARCHIVER_H
#define SUDISKIMAGEUNARCHIVER_H

#import <Foundation/Foundation.h>
#import "SUUnarchiverProtocol.h"

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SUDiskImageUnarchiver : NSObject <SUUnarchiverProtocol>

- (instancetype)initWithArchivePath:(NSString *)archivePath extractionDirectory:(NSString *)extractionDirectory decryptionPassword:(nullable NSString *)decryptionPassword;

+ (BOOL)canUnarchivePath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END

#endif
