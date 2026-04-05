//
//  SPUDownloadDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem, SUHost, SPUDownloadedUpdate, SPUDownloadData;

@protocol SPUDownloadDriverDelegate <NSObject>

- (void)downloadDriverDidFailToDownloadFileWithError:(NSError *)error;

@optional

- (void)downloadDriverWillBeginDownload;

// For persistent update downloads
- (void)downloadDriverDidDownloadUpdate:(SPUDownloadedUpdate *)downloadedUpdate;

// For temporary downloads
- (void)downloadDriverDidDownloadData:(SPUDownloadData *)downloadData;

// Only for persistent downloads
- (void)downloadDriverDidReceiveExpectedContentLength:(uint64_t)expectedContentLength;

// Only for persistent downloads
- (void)downloadDriverDidReceiveDataOfLength:(uint64_t)length;

@end

#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT_MEMBERS
#endif
@interface SPUDownloadDriver : NSObject

- (instancetype)initWithRequestURL:(NSURL *)requestURL host:(SUHost *)host userAgent:(NSString * _Nullable)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background delegate:(id<SPUDownloadDriverDelegate>)delegate;

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem secondaryUpdateItem:(SUAppcastItem * _Nullable)secondaryUpdateItem host:(SUHost *)host userAgent:(NSString * _Nullable)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background delegate:(id<SPUDownloadDriverDelegate>)delegate;

- (instancetype)initWithHost:(SUHost *)host;

- (void)downloadFile;

- (void)removeDownloadedUpdate:(SPUDownloadedUpdate *)downloadedUpdate;

@property (nonatomic, readonly) NSMutableURLRequest *request;
@property (nonatomic, readonly) BOOL inBackground;

- (void)cleanup:(void (^)(void))completionHandler;

@end

NS_ASSUME_NONNULL_END
