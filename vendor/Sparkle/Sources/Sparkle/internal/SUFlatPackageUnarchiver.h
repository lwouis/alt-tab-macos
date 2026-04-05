//
//  SUFlatPackageUnarchiver.h
//  Autoupdate
//
//  Created by Mayur Pawashe on 1/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_PACKAGE_SUPPORT

#import <Foundation/Foundation.h>
#import "SUUnarchiverProtocol.h"

NS_ASSUME_NONNULL_BEGIN

// An unarchiver for flat packages that doesn't really do any unarchiving
SPU_OBJC_DIRECT_MEMBERS @interface SUFlatPackageUnarchiver : NSObject <SUUnarchiverProtocol>

- (instancetype)initWithFlatPackagePath:(NSString *)flatPackagePath extractionDirectory:(NSString *)extractionDirectory expectingInstallationType:(NSString *)installationType;

+ (BOOL)canUnarchivePath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END

#endif
