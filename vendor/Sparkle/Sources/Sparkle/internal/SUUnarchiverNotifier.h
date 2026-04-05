//
//  SUUnarchiverNotifier.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/21/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SUUnarchiverNotifier : NSObject

- (instancetype)initWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock;

- (void)notifySuccess;

- (void)notifyFailureWithError:(NSError * _Nullable)reason;

- (void)notifyProgress:(double)progress;

@end

NS_ASSUME_NONNULL_END
