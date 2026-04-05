//
//  SUReleaseNotesView.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import <Foundation/Foundation.h>

@class NSView;

NS_ASSUME_NONNULL_BEGIN

@protocol SUReleaseNotesView <NSObject>

@property (nonatomic, readonly) NSView *view;

- (void)loadString:(NSString *)string baseURL:(NSURL * _Nullable)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler;

- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)textEncodingName baseURL:(NSURL *)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler;

- (void)stopLoading;

- (void)setDrawsBackground:(BOOL)drawsBackground;

@end

NS_ASSUME_NONNULL_END

#endif
