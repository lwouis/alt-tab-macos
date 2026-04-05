//
//  SUUnarchiverProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/26/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUUnarchiverProtocol <NSObject>

+ (BOOL)mustValidateBeforeExtraction;

- (void)unarchiveWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock waitForCleanup:(BOOL)waitForCleanup;

@property (nonatomic, readonly) BOOL needsVerifyBeforeExtractionKey;

- (NSString *)description;

@end

NS_ASSUME_NONNULL_END
