//
//  SPUDownloadDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUDownloadDriver.h"
#import "SPUDownloaderDelegate.h"
#import "SPUDownloader.h"
#import "SPUXPCServiceInfo.h"
#import "SUAppcastItem.h"
#import "SUFileManager.h"
#import "SULocalizations.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUErrors.h"
#import "SPUDownloadedUpdate.h"
#import "SPUDownloadData.h"
#import "SUConstants.h"


#include "AppKitPrevention.h"

@interface SPUDownloadDriver () <SPUDownloaderDelegate>
@end

@implementation SPUDownloadDriver
{
    id<SPUDownloaderProtocol> _downloader;
#if DOWNLOADER_XPC_SERVICE_EMBEDDED
    NSXPCConnection *_connection;
#endif
    SUAppcastItem *_updateItem;
    SUAppcastItem * _Nullable _secondaryUpdateItem;
    SUHost *_host;
    NSData *_downloadBookmarkData;
    NSString *_downloadToken;
    
    __weak id<SPUDownloadDriverDelegate> _delegate;
    
    uint64_t _expectedContentLength;
    
    BOOL _retrievedDownloadResult;
    BOOL _cleaningUp;
}

@synthesize request = _request;
@synthesize inBackground = _inBackground;

- (instancetype)initWithHost:(SUHost *)host
{
    self = [super init];
    if (self != nil) {
        _host = host;
        
#if DOWNLOADER_XPC_SERVICE_EMBEDDED
        if (SPUXPCServiceIsEnabled(SUEnableDownloaderServiceKey)) {
            _connection = [[NSXPCConnection alloc] initWithServiceName:@DOWNLOADER_BUNDLE_ID];
            _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUDownloaderProtocol)];
            _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUDownloaderDelegate)];
            _connection.exportedObject = self;
            
            _downloader = _connection.remoteObjectProxy;
            
            __weak __typeof__(self) weakSelf = self;
            
            _connection.interruptionHandler = ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    __typeof__(self) strongSelf = weakSelf;
                    if (strongSelf != nil && !strongSelf->_retrievedDownloadResult) {
                        [strongSelf->_connection invalidate];
                    }
                });
            };
            
            _connection.invalidationHandler = ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    __typeof__(self) strongSelf = weakSelf;
                    if (strongSelf != nil && !strongSelf->_retrievedDownloadResult && !strongSelf->_cleaningUp) {
                        strongSelf->_downloader = nil;
                        
                        NSString *additionalFailureReason;
                        {
                            NSString *executableFailureReason;
                            if (!SPUXPCServiceHasExecutablePermission(@DOWNLOADER_NAME, &executableFailureReason)) {
                                additionalFailureReason = [NSString stringWithFormat:@" %@", executableFailureReason];
                            } else {
                                additionalFailureReason = @"";
                            }
                        }
                        
                        NSDictionary *userInfo =
                        @{
                          NSLocalizedDescriptionKey: SULocalizedStringFromTableInBundle(@"An error occurred while downloading the update. Please try again later.", SPARKLE_TABLE, SUSparkleBundle(), nil),
                          NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"If your app is not sandboxed or has com.apple.security.network.client set to YES, please remove %@ from your Info.plist. Please also check Console logs for "@DOWNLOADER_NAME" if there are any additional details.%@", SUEnableDownloaderServiceKey, additionalFailureReason]
                          };
                        
                        NSError *downloadError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo];
                        
                        [strongSelf->_delegate downloadDriverDidFailToDownloadFileWithError:downloadError];
                    }
                });
            };
            
            [_connection resume];
        } else
#endif
        {
            _downloader = [[SPUDownloader alloc] initWithDelegate:self];
        }
    }
    return self;
}

- (instancetype)initWithRequestURL:(NSURL *)requestURL host:(SUHost *)host userAgent:(NSString * _Nullable)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background delegate:(id<SPUDownloadDriverDelegate>)delegate
{
    self = [self initWithHost:host];
    if (self != nil) {
        _delegate = delegate;
        _inBackground = background;
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
        // Note the cachePolicy has no effect on persistent downloads on disk (i.e downloading update archives)
        // It impacts temporary in-memory downloads such as appcast feeds and release notes.
        // For now we don't use caching, but with more testing/experimenting that could change
        // (e.g. not downloading same feed unmodified from previous request).
        request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        
        if (userAgent != nil) {
            [request setValue:(NSString * _Nonnull)userAgent forHTTPHeaderField:@"User-Agent"];
        }
        
        request.networkServiceType = background ? NSURLNetworkServiceTypeBackground : NSURLNetworkServiceTypeDefault;

        if (httpHeaders != nil) {
            for (NSString *key in httpHeaders) {
                NSString *value = [httpHeaders objectForKey:key];
                [request setValue:value forHTTPHeaderField:key];
            }
        }
        
        _request = request;
    }
    return self;
}

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem secondaryUpdateItem:(SUAppcastItem * _Nullable)secondaryUpdateItem host:(SUHost *)host userAgent:(NSString * _Nullable)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background delegate:(id<SPUDownloadDriverDelegate>)delegate
{
    NSURL *updateFileURL = updateItem.fileURL;
    assert(updateFileURL != nil);
    
    self = [self initWithRequestURL:updateFileURL host:host userAgent:userAgent httpHeaders:httpHeaders inBackground:background delegate:delegate];
    if (self != nil) {
        _updateItem = updateItem;
        _secondaryUpdateItem = secondaryUpdateItem;
    }
    return self;
}

- (void)downloadFile
{
    assert(NSThread.isMainThread);
    
    id<SPUDownloadDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(downloadDriverWillBeginDownload)]) {
        [delegate downloadDriverWillBeginDownload];
    }
    
    if (_updateItem != nil) {
        NSString *desiredFilename = [NSString stringWithFormat:@"%@ %@", [_host name], [_updateItem versionString]];
        
        NSString *bundleIdentifier = _host.bundle.bundleIdentifier;
        assert(bundleIdentifier != nil);
        
        [_downloader startPersistentDownloadWithRequest:_request bundleIdentifier:bundleIdentifier desiredFilename:desiredFilename];
    } else {
        [_downloader startTemporaryDownloadWithRequest:_request];
    }
}

- (void)removeDownloadedUpdate:(SPUDownloadedUpdate *)downloadedUpdate
{
    NSString *bundleIdentifier = _host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    
    [_downloader removeDownloadDirectoryWithDownloadToken:downloadedUpdate.downloadToken bundleIdentifier:bundleIdentifier];
}

- (void)cleanup:(void (^)(void))completionHandler
{
    void (^cleanupBlock)(void) = ^{
        self->_cleaningUp = YES;
        
#if DOWNLOADER_XPC_SERVICE_EMBEDDED
        if (self->_connection != nil) {
            [self->_connection invalidate];
            self->_connection = nil;
        }
#endif
        self->_downloadBookmarkData = nil;
        self->_downloadToken = nil;
        self->_downloader = nil;
        
        completionHandler();
    };
    
    if (_downloader == nil) {
        cleanupBlock();
    } else {
        [_downloader cleanup:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                cleanupBlock();
            });
        }];
    }
}

- (void)downloaderDidFinishWithTemporaryDownloadData:(SPUDownloadData * _Nullable)downloadData
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_retrievedDownloadResult = YES;
        
        id<SPUDownloadDriverDelegate> delegate = self->_delegate;
        if (self->_updateItem != nil) {
            if (self->_expectedContentLength > 0 && self->_updateItem.contentLength > 0 && self->_expectedContentLength != self->_updateItem.contentLength) {
                SULog(SULogLevelError, @"Warning: Downloader's expected content length (%llu) != Appcast item's length (%llu)", self->_expectedContentLength, self->_updateItem.contentLength);
            }
            
            SPUDownloadedUpdate *downloadedUpdate = [[SPUDownloadedUpdate alloc] initWithAppcastItem:self->_updateItem secondaryAppcastItem:self->_secondaryUpdateItem downloadBookmarkData:self->_downloadBookmarkData downloadToken:self->_downloadToken];
            
            if ([delegate respondsToSelector:@selector(downloadDriverDidDownloadUpdate:)]) {
                [delegate downloadDriverDidDownloadUpdate:downloadedUpdate];
            }
        } else {
            assert(downloadData != nil);
            SPUDownloadData *nonNullDownloadData = downloadData;
            if ([delegate respondsToSelector:@selector(downloadDriverDidDownloadData:)]) {
                [delegate downloadDriverDidDownloadData:nonNullDownloadData];
            }
        }
    });
}

- (void)downloaderDidFailWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_retrievedDownloadResult = YES;
        
        NSURL *failingUrl = error.userInfo[NSURLErrorFailingURLErrorKey];
        if (!failingUrl) {
            failingUrl = [self->_updateItem fileURL];
        }
        
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                        NSLocalizedDescriptionKey: SULocalizedStringFromTableInBundle(@"An error occurred while downloading the update. Please try again later.", SPARKLE_TABLE, SUSparkleBundle(), nil),
                                                                                        NSUnderlyingErrorKey: error,
                                                                                        }];
        if (failingUrl) {
            userInfo[NSURLErrorFailingURLErrorKey] = failingUrl;
        }
        
        NSError *downloadError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo];
        [self->_delegate downloadDriverDidFailToDownloadFileWithError:downloadError];
    });
}

- (void)downloaderDidSetDownloadBookmarkData:(NSData *)downloadBookmarkData downloadToken:(NSString *)downloadToken
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_downloadBookmarkData = downloadBookmarkData;
        self->_downloadToken = [downloadToken copy];
    });
}

- (void)downloaderDidReceiveExpectedContentLength:(int64_t)expectedContentLength
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Fallback to appcast item's content length if we don't get the length from HTTP header
        id<SPUDownloadDriverDelegate> delegate = self->_delegate;
        if ([delegate respondsToSelector:@selector(downloadDriverDidReceiveExpectedContentLength:)]) {
            [delegate downloadDriverDidReceiveExpectedContentLength:expectedContentLength > 0 ? (uint64_t)expectedContentLength : self->_updateItem.contentLength];
        }
        
        // Reset expected content length from downloader
        // Later we verify if the total length matches with the content length from the appcast
        if (expectedContentLength > 0) {
            self->_expectedContentLength = (uint64_t)expectedContentLength;
        }
    });
}

- (void)downloaderDidReceiveDataOfLength:(uint64_t)length
{
    dispatch_async(dispatch_get_main_queue(), ^{
        id<SPUDownloadDriverDelegate> delegate = self->_delegate;
        if ([delegate respondsToSelector:@selector(downloadDriverDidReceiveDataOfLength:)]) {
            [delegate downloadDriverDidReceiveDataOfLength:length];
        }
    });
}

@end
