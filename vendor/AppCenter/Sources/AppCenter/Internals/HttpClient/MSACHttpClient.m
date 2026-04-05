// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACHttpClient.h"
#import "MSACAppCenterErrors.h"
#import "MSACAppCenterInternal.h"
#import "MSACConstants+Internal.h"
#import "MSACHttpCall.h"
#import "MSACHttpClientDelegate.h"
#import "MSACHttpClientPrivate.h"
#import "MSACHttpUtil.h"
#import "MSAC_Reachability.h"

#define DEFAULT_RETRY_INTERVALS @[ @10, @(5 * 60), @(20 * 60) ]

@implementation MSACHttpClient

@synthesize delegate = _delegate;

- (instancetype)init {
  return [self initWithMaxHttpConnectionsPerHost:nil reachability:[MSAC_Reachability reachabilityForInternetConnection]];
}

- (instancetype)initWithMaxHttpConnectionsPerHost:(NSInteger)maxHttpConnectionsPerHost {
  return [self initWithMaxHttpConnectionsPerHost:@(maxHttpConnectionsPerHost)
                                    reachability:[MSAC_Reachability reachabilityForInternetConnection]];
}

- (instancetype)initWithMaxHttpConnectionsPerHost:(NSNumber *)maxHttpConnectionsPerHost reachability:(MSAC_Reachability *)reachability {
  if ((self = [super init])) {
    _sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    if (maxHttpConnectionsPerHost) {
      _sessionConfiguration.HTTPMaximumConnectionsPerHost = [maxHttpConnectionsPerHost integerValue];
    }
    _session = [NSURLSession sessionWithConfiguration:_sessionConfiguration];
    _pendingCalls = [NSMutableSet new];
    _enabled = YES;
    _paused = NO;
    _reachability = reachability;
    _delegate = nil;

    // Add listener to reachability.
    [MSAC_NOTIFICATION_CENTER addObserver:self
                                 selector:@selector(networkStateChanged:)
                                     name:kMSACReachabilityChangedNotification
                                   object:nil];
    [self.reachability startNotifier];
  }
  return self;
}

- (void)sendAsync:(NSURL *)url
               method:(NSString *)method
              headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                 data:(nullable NSData *)data
    completionHandler:(MSACHttpRequestCompletionHandler)completionHandler {
  [self sendAsync:url
                  method:method
                 headers:headers
                    data:data
          retryIntervals:DEFAULT_RETRY_INTERVALS
      compressionEnabled:YES
       completionHandler:completionHandler];
}

- (void)sendAsync:(NSURL *)url
                method:(NSString *)method
               headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                  data:(nullable NSData *)data
        retryIntervals:(NSArray *)retryIntervals
    compressionEnabled:(BOOL)compressionEnabled
     completionHandler:(MSACHttpRequestCompletionHandler)completionHandler {
  @synchronized(self) {
    if (!self.enabled) {
      NSError *error = [NSError errorWithDomain:kMSACACErrorDomain
                                           code:MSACACDisabledErrorCode
                                       userInfo:@{NSLocalizedDescriptionKey : kMSACACDisabledErrorDesc}];
      completionHandler(nil, nil, error);
      return;
    }
    MSACHttpCall *call = [[MSACHttpCall alloc] initWithUrl:url
                                                    method:method
                                                   headers:headers
                                                      data:data
                                            retryIntervals:retryIntervals
                                        compressionEnabled:compressionEnabled
                                         completionHandler:completionHandler];
    [self sendCallAsync:call];
  }
}

- (void)sendCallAsync:(MSACHttpCall *)call {
  @synchronized(self) {
    if (![self.pendingCalls containsObject:call]) {
      [self.pendingCalls addObject:call];
    }
    if (self.paused) {
      return;
    }

    // Call delegate before sending HTTP request.
    id<MSACHttpClientDelegate> strongDelegate = self.delegate;
    if ([strongDelegate respondsToSelector:@selector(willSendHTTPRequestToURL:withHeaders:)]) {
      [strongDelegate willSendHTTPRequestToURL:call.url withHeaders:call.headers];
    }

    // Send HTTP request.
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:call.url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:0];
    request.HTTPBody = call.data;
    request.HTTPMethod = call.method;
    request.allHTTPHeaderFields = call.headers;

    // Always disable cookies.
    [request setHTTPShouldHandleCookies:NO];
    call.inProgress = YES;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                   [self requestCompletedWithHttpCall:call data:data response:response error:error];
                                                 }];
    [task resume];
  }
}

- (void)requestCompletedWithHttpCall:(MSACHttpCall *)httpCall
                                data:(NSData *)data
                            response:(NSURLResponse *)response
                               error:(NSError *)error {
  NSHTTPURLResponse *httpResponse;
  @synchronized(self) {
    httpCall.inProgress = NO;

    // If the call was removed, do not invoke the completion handler as that will have been done already by set enabled.
    if (![self.pendingCalls containsObject:httpCall]) {
      MSACLogDebug([MSACAppCenter logTag], @"HTTP call was canceled; do not process further.");
      return;
    }

    // Handle NSError (low level error where we don't even get a HTTP response).
    BOOL internetIsDown = [MSACHttpUtil isNoInternetConnectionError:error];
    BOOL couldNotEstablishSecureConnection = [MSACHttpUtil isSSLConnectionError:error];
    if (error) {
      if (internetIsDown || couldNotEstablishSecureConnection) {

        // Reset the retry count, will retry once the (secure) connection is established again.
        [httpCall resetRetry];
        NSString *logMessage = internetIsDown ? @"Internet connection is down." : @"Could not establish secure connection.";
        MSACLogInfo([MSACAppCenter logTag], @"HTTP call failed with error: %@", logMessage);
        return;
      } else {
        MSACLogError([MSACAppCenter logTag], @"HTTP request error with code: %td, domain: %@, description: %@", error.code, error.domain,
                     error.localizedDescription);
      }
    }

    // Handle HTTP error.
    else {
      httpResponse = (NSHTTPURLResponse *)response;
      if ([MSACHttpUtil isRecoverableError:httpResponse.statusCode]) {
        if ([httpCall hasReachedMaxRetries]) {
          [self pause];
        } else {

          // Check if there is a "retry after" header in the response
          NSString *retryAfter = httpResponse.allHeaderFields[kMSACRetryHeaderKey];
          NSNumber *retryAfterMilliseconds;
          if (retryAfter) {
            NSNumberFormatter *formatter = [NSNumberFormatter new];
            retryAfterMilliseconds = [formatter numberFromString:retryAfter];
          }
          [httpCall startRetryTimerWithStatusCode:httpResponse.statusCode
                                       retryAfter:retryAfterMilliseconds
                                            event:^{
                                              [self sendCallAsync:httpCall];
                                            }];
          return;
        }
      } else if (![MSACHttpUtil isSuccessStatusCode:httpResponse.statusCode]) {

        // Removing the call from pendingCalls and invoking completion handler must be done before disabling to avoid duplicate invocations.
        [self.pendingCalls removeObject:httpCall];

        // Unblock the caller now with the outcome of the call.
        httpCall.completionHandler(data, httpResponse, error);
        [self setEnabled:NO andDeleteDataOnDisabled:YES];

        // Return so as not to re-invoke completion handler.
        return;
      }
    }
    [self.pendingCalls removeObject:httpCall];
  }

  // Unblock the caller now with the outcome of the call.
  httpCall.completionHandler(data, httpResponse, error);
}

- (void)networkStateChanged:(__unused NSNotificationCenter *)notification {
  if ([self.reachability currentReachabilityStatus] == NotReachable) {
    MSACLogInfo([MSACAppCenter logTag], @"Internet connection is down.");
    [self pause];
  } else {
    MSACLogInfo([MSACAppCenter logTag], @"Internet connection is up.");
    [self resume];
  }
}

- (void)pause {
  @synchronized(self) {
    if (self.paused) {
      return;
    }
    MSACLogInfo([MSACAppCenter logTag], @"Pause HTTP client.");
    self.paused = YES;

    // Reset retry for all calls.
    for (MSACHttpCall *call in self.pendingCalls) {
      [call resetRetry];
    }
  }
}

- (void)resume {
  @synchronized(self) {

    // Resume only while enabled.
    if (self.paused && self.enabled) {
      MSACLogInfo([MSACAppCenter logTag], @"Resume HTTP client.");
      self.paused = NO;

      // Resume calls.
      for (MSACHttpCall *call in self.pendingCalls) {
        if (!call.inProgress) {
          [self sendCallAsync:call];
        }
      }
    }
  }
}

- (void)setEnabled:(BOOL)isEnabled andDeleteDataOnDisabled:(BOOL)deleteData {
  @synchronized(self) {
    if (self.enabled != isEnabled) {
      self.enabled = isEnabled;
      if (isEnabled) {
        self.session = [NSURLSession sessionWithConfiguration:self.sessionConfiguration];
        [self.reachability startNotifier];
        [self resume];
      } else {
        [self.reachability stopNotifier];
        [self pause];
        if (deleteData) {

          // Cancel all the tasks and invalidate current session to free resources.
          [self.session invalidateAndCancel];
          self.session = nil;

          // Remove pending calls and invoke their completion handler.
          for (MSACHttpCall *call in self.pendingCalls) {
            NSError *error = [NSError errorWithDomain:kMSACACErrorDomain
                                                 code:MSACACCanceledErrorCode
                                             userInfo:@{NSLocalizedDescriptionKey : kMSACACCanceledErrorDesc}];
            call.completionHandler(nil, nil, error);
          }
          [self.pendingCalls removeAllObjects];
        }
      }
    }
  }
}

- (void)dealloc {
  [self.reachability stopNotifier];
  [MSAC_NOTIFICATION_CENTER removeObserver:self name:kMSACReachabilityChangedNotification object:nil];
  [self.session finishTasksAndInvalidate];
}

@end
