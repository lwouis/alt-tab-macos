//
//  SPUDownloader.m
//  Downloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUDownloader.h"
#import "SPUDownloaderDelegate.h"
#import "SPULocalCacheDirectory.h"
#import "SPUDownloadData.h"
#import "SPUDownloadDataPrivate.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

typedef NS_ENUM(NSUInteger, SPUDownloadMode)
{
    SPUDownloadModePersistent,
    SPUDownloadModeTemporary
};

static NSString *SUDownloadingReason = @"Downloading update related file";

@interface SPUDownloader () <NSURLSessionDownloadDelegate>
@end

@implementation SPUDownloader
{
    NSURLSessionTask *_sessionTask;
    NSURLSession *_downloadSession;
    NSString *_bundleIdentifier;
    NSString *_desiredFilename;
    
    // Delegate is intentionally strongly referenced; see header
    id <SPUDownloaderDelegate> _delegate;
    
    SPUDownloadMode _mode;
    
    BOOL _disabledAutomaticTermination;
    BOOL _receivedExpectedBytes;
}

- (instancetype)initWithDelegate:(id <SPUDownloaderDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)startDownloadWithRequest:(NSURLRequest *)request SPU_OBJC_DIRECT
{
    if (request == nil) {
        NSString *message = @"The download request must not be nil";
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:@{ NSLocalizedDescriptionKey: message }];
        [_delegate downloaderDidFailWithError:error];
        
        return;
    }
    
    // Prevent any unwanted URL schemes (e.g. file://)
    NSString *scheme = request.URL.scheme;
    if (scheme == nil) {
        NSString *message = @"The download request scheme must not be nil";
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:@{ NSLocalizedDescriptionKey: message }];
        [_delegate downloaderDidFailWithError:error];
        
        return;
    }
    
    if ([scheme caseInsensitiveCompare:@"http"] != NSOrderedSame && [scheme caseInsensitiveCompare:@"https"] != NSOrderedSame) {
        NSString *message = [NSString stringWithFormat:@"The download request URL must use http or https (%@)", request.URL];
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:@{ NSLocalizedDescriptionKey: message }];
        [_delegate downloaderDidFailWithError:error];
        
        return;
    }
    
    _downloadSession = [NSURLSession
        sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
        delegate:self
        delegateQueue:[NSOperationQueue mainQueue]];
    
    switch (_mode) {
        case SPUDownloadModePersistent:
            _sessionTask = [_downloadSession downloadTaskWithRequest:request];
            break;
        case SPUDownloadModeTemporary: {
            __weak __typeof__(self) weakSelf = self;
            _sessionTask = [_downloadSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                [weakSelf temporaryDownloadDidFinishWithData:data response:response error:error];
            }];
            break;
        }
    }
    
    [_sessionTask resume];
}

// Don't implement dealloc - make the client call cleanup, which is the only way to remove the reference cycle from the delegate anyway

- (void)startPersistentDownloadWithRequest:(NSURLRequest *)request bundleIdentifier:(NSString *)bundleIdentifier desiredFilename:(NSString *)desiredFilename
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_sessionTask == nil && self->_delegate != nil) {
            // Prevent service from automatically terminating while downloading the update asynchronously without any reply blocks
            [[NSProcessInfo processInfo] disableAutomaticTermination:SUDownloadingReason];
            self->_disabledAutomaticTermination = YES;
            
            self->_mode = SPUDownloadModePersistent;
            self->_desiredFilename = desiredFilename;
            self->_bundleIdentifier = [bundleIdentifier copy];
            
            [self startDownloadWithRequest:request];
        }
    });
}

- (void)startTemporaryDownloadWithRequest:(NSURLRequest *)request
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_sessionTask == nil && self->_delegate != nil) {
            // Prevent service from automatically terminating while downloading the update asynchronously without any reply blocks
            [[NSProcessInfo processInfo] disableAutomaticTermination:SUDownloadingReason];
            self->_disabledAutomaticTermination = YES;
            
            self->_mode = SPUDownloadModeTemporary;
            [self startDownloadWithRequest:request];
        }
    });
}

- (void)enableAutomaticTermination SPU_OBJC_DIRECT
{
    if (_disabledAutomaticTermination) {
        [[NSProcessInfo processInfo] enableAutomaticTermination:SUDownloadingReason];
        _disabledAutomaticTermination = NO;
    }
}

- (NSString *)rootPersistentDownloadCachePathForBundleIdentifier:(NSString *)bundleIdentifier SPU_OBJC_DIRECT
{
    // Note: The installer verifies this "PersistentDownloads" path component
    return [[SPULocalCacheDirectory cachePathForBundleIdentifier:bundleIdentifier] stringByAppendingPathComponent:@"PersistentDownloads"];
}

- (void)removeDownloadDirectoryWithDownloadToken:(NSString *)downloadToken bundleIdentifier:(NSString *)bundleIdentifier
{
    // Only take the directory name (from the download token) and compute most of the base path ourselves
    // This way we do not have to send/trust an absolute path
    // The downloader instance that creates this temp directory isn't necessarily the same as the one
    // that clears it (eg upon skipping an already downloaded update), so we can't just preserve it here too
    dispatch_async(dispatch_get_main_queue(), ^{
        if (bundleIdentifier != nil && downloadToken != nil) {
            NSString *rootPersistentDownloadCachePath = [self rootPersistentDownloadCachePathForBundleIdentifier:bundleIdentifier];
            if (rootPersistentDownloadCachePath != nil) {
                NSString *sanitizedDownloadToken = downloadToken.lastPathComponent;
                NSString *tempDir = [rootPersistentDownloadCachePath stringByAppendingPathComponent:sanitizedDownloadToken];
                
                [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
            }
        }
    });
}

- (void)_cleanup SPU_OBJC_DIRECT
{
    [self enableAutomaticTermination];
    [_sessionTask cancel];
    [_downloadSession finishTasksAndInvalidate];
    _sessionTask = nil;
    _downloadSession = nil;
    _delegate = nil;
}

- (void)cleanup:(void (^)(void))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _cleanup];
        
        if (completionHandler != NULL) {
            completionHandler();
        }
    });
}

static bool SPUValidateStatusCodeAndFailIfInvalid(NSURLResponse * _Nullable response, NSURL *url, id<SPUDownloaderDelegate> delegate)
{
    NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 200;
    
    if ((statusCode < 200) || (statusCode >= 400))
    {
        NSString *message = [NSString stringWithFormat:@"A network error occurred while downloading %@. %@ (%ld)", url.absoluteString, [NSHTTPURLResponse localizedStringForStatusCode:statusCode], (long)statusCode];
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:@{ NSLocalizedDescriptionKey: message }];
        [delegate downloaderDidFailWithError:error];
        
        return false;
    } else {
        return true;
    }
}

- (void)temporaryDownloadDidFinishWithData:(NSData * _Nullable)data response:(NSURLResponse * _Nullable)response error:(NSError * _Nullable)error SPU_OBJC_DIRECT
{
    if (!SPUValidateStatusCodeAndFailIfInvalid(response, _sessionTask.originalRequest.URL, _delegate)) {
        return;
    }
    
    SPUDownloadData *downloadData = nil;
    if (data != nil) {
        NSURL *responseURL = response.URL;
        if (responseURL == nil) {
            responseURL = _sessionTask.currentRequest.URL;
        }
        if (responseURL == nil) {
            responseURL = _sessionTask.originalRequest.URL;
        }
        assert(responseURL != nil);

        downloadData = [[SPUDownloadData alloc] initWithData:(NSData * _Nonnull)data URL:responseURL textEncodingName:response.textEncodingName MIMEType:response.MIMEType];
    }
    
    _sessionTask = nil;
    
    if (downloadData != nil) {
        [_delegate downloaderDidFinishWithTemporaryDownloadData:downloadData];
    } else {
        NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey: @"Failed to download temporary data."} mutableCopy];
        
        if (error != nil) {
            userInfo[NSUnderlyingErrorKey] = error;
        }
        
        [_delegate downloaderDidFailWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo]];
    }
    
    [self _cleanup];
}

- (void)URLSession:(NSURLSession *)__unused session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    if (!SPUValidateStatusCodeAndFailIfInvalid(downloadTask.response, downloadTask.originalRequest.URL, _delegate)) {
        return;
    }
    
    // Remove our old caches path so we don't start accumulating files in there
    NSString *rootPersistentDownloadCachePath = [self rootPersistentDownloadCachePathForBundleIdentifier:_bundleIdentifier];

    [SPULocalCacheDirectory removeOldItemsInDirectory:rootPersistentDownloadCachePath];
    
    NSString *tempDir = [SPULocalCacheDirectory createUniqueDirectoryInDirectory:rootPersistentDownloadCachePath];
    if (tempDir == nil)
    {
        // Okay, something's really broken with this user's file structure.
        [_sessionTask cancel];
        _sessionTask = nil;
        
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.", tempDir] }];
        
        [_delegate downloaderDidFailWithError:error];
    } else {
        NSString *downloadFileName = _desiredFilename;
        NSString *downloadFileNameDirectory = [tempDir stringByAppendingPathComponent:downloadFileName];
        
        NSError *createError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:downloadFileNameDirectory withIntermediateDirectories:NO attributes:nil error:&createError]) {
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a download file name %@ directory inside temporary directory for the update download at %@.", downloadFileName, downloadFileNameDirectory] }];
            
            [_delegate downloaderDidFailWithError:error];
        } else {
            NSString *name = _sessionTask.response.suggestedFilename;
            if (!name) {
                name = location.lastPathComponent; // This likely contains nothing useful to identify the file (e.g. CFNetworkDownload_87LVIz.tmp)
            }
            NSString *toPath = [downloadFileNameDirectory stringByAppendingPathComponent:name];
            NSString *fromPath = location.path; // suppress moveItemAtPath: non-null warning
            NSError *error = nil;
            if ([[NSFileManager defaultManager] moveItemAtPath:fromPath toPath:toPath error:&error]) {
                // Create a bookmark for the download
                // Don't pass any options (we don't want a persistent security scoped bookmark)
                
                NSURL *downloadURL = [NSURL fileURLWithPath:toPath isDirectory:NO];
                
                NSError *bookmarkError = nil;
                NSData *bookmarkData = [downloadURL bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)0 includingResourceValuesForKeys:@[] relativeToURL:nil error:&bookmarkError];
                if (bookmarkData == nil) {
                    [_delegate downloaderDidFailWithError:bookmarkError];
                } else {
                    // The download token may be provided later to the downloader for removing a download
                    // and its temporary directory
                    NSString *downloadToken = tempDir.lastPathComponent;
                    [_delegate downloaderDidSetDownloadBookmarkData:bookmarkData downloadToken:downloadToken];
                    
                    _sessionTask = nil;
                    
                    [_delegate downloaderDidFinishWithTemporaryDownloadData:nil];
                }
            } else {
                [_delegate downloaderDidFailWithError:error];
            }
        }
    }
}

- (void)URLSession:(NSURLSession *)__unused session downloadTask:(NSURLSessionDownloadTask *)__unused downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)__unused totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    if (_mode != SPUDownloadModePersistent) {
        return;
    }
    
    if (totalBytesExpectedToWrite > 0 && !_receivedExpectedBytes) {
        _receivedExpectedBytes = YES;
        [_delegate downloaderDidReceiveExpectedContentLength:totalBytesExpectedToWrite];
    }
    
    if (bytesWritten >= 0) {
        [_delegate downloaderDidReceiveDataOfLength:(uint64_t)bytesWritten];
    }
}

- (void)URLSession:(NSURLSession *)__unused session task:(NSURLSessionTask *)__unused task didCompleteWithError:(NSError *)error
{
    _sessionTask = nil;
    if (error != nil) {
        [_delegate downloaderDidFailWithError:error];
    }
}

@end
