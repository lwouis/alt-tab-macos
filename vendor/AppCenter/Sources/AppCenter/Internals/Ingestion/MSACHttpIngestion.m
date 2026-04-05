// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACHttpIngestion.h"
#import "MSACAppCenterErrors.h"
#import "MSACAppCenterInternal.h"
#import "MSACConstants+Internal.h"
#import "MSACHttpClientPrivate.h"
#import "MSACHttpIngestionPrivate.h"
#import "MSACLoggerInternal.h"
#import "MSACUtility+StringFormatting.h"

// URL components' name within a partial URL.
static NSString *const kMSACPartialURLComponentsName[] = {@"scheme", @"user", @"password", @"host", @"port", @"path"};

@implementation MSACHttpIngestion

@synthesize baseURL = _baseURL;
@synthesize apiPath = _apiPath;

#pragma mark - Initialize

- (id)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient
                 baseUrl:(NSString *)baseUrl
                 apiPath:(NSString *)apiPath
                 headers:(NSDictionary *)headers
            queryStrings:(NSDictionary *)queryStrings {
  return [self initWithHttpClient:httpClient
                          baseUrl:baseUrl
                          apiPath:apiPath
                          headers:headers
                     queryStrings:queryStrings
                   retryIntervals:@[ @(10), @(5 * 60), @(20 * 60) ]];
}

- (id)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient
                 baseUrl:(NSString *)baseUrl
                 apiPath:(NSString *)apiPath
                 headers:(NSDictionary *)headers
            queryStrings:(NSDictionary *)queryStrings
          retryIntervals:(NSArray *)retryIntervals {
  return [self initWithHttpClient:httpClient
                          baseUrl:baseUrl
                          apiPath:apiPath
                          headers:headers
                     queryStrings:queryStrings
                   retryIntervals:retryIntervals
           maxNumberOfConnections:4];
}

- (id)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient
                   baseUrl:(NSString *)baseUrl
                   apiPath:(NSString *)apiPath
                   headers:(NSDictionary *)headers
              queryStrings:(NSDictionary *)queryStrings
            retryIntervals:(NSArray *)retryIntervals
    maxNumberOfConnections:(NSInteger)maxNumberOfConnections {
  if ((self = [super init])) {
    _httpHeaders = headers;
    _httpClient = httpClient;
    _enabled = YES;
    _callsRetryIntervals = retryIntervals;
    _apiPath = apiPath;
    _maxNumberOfConnections = maxNumberOfConnections;
    _baseURL = baseUrl;

    // Set HTTP client delegate.
    httpClient.delegate = self;

    // Set send URL which can't be null
    _sendURL = [self buildURLWithBaseURL:baseUrl apiPath:apiPath queryStrings:queryStrings];
  }
  return self;
}

#pragma mark - MSACIngestion

- (BOOL)isReadyToSend {
  return YES;
}

- (void)sendAsync:(NSObject *)data completionHandler:(MSACSendAsyncCompletionHandler)handler {
  [self sendAsync:data eTag:nil callId:MSAC_UUID_STRING completionHandler:handler];
}

- (void)sendAsync:(NSObject *)data eTag:(nullable NSString *)eTag completionHandler:(MSACSendAsyncCompletionHandler)handler {
  [self sendAsync:data eTag:eTag callId:MSAC_UUID_STRING completionHandler:handler];
}

#pragma mark - Life cycle

- (void)setEnabled:(BOOL)isEnabled andDeleteDataOnDisabled:(BOOL __unused)deleteData {
  @synchronized(self) {
    self.enabled = isEnabled;
  }
}

- (BOOL)isEnabled {
  @synchronized(self) {
    return _enabled && [[MSACAppCenter sharedInstance] isNetworkRequestsAllowed];
  }
}

#pragma mark - MSACHttpIngestion

- (NSURL *)buildURLWithBaseURL:(NSString *)baseURL apiPath:(NSString *)apiPath queryStrings:(NSDictionary *)queryStrings {

  // Construct the URL string with the query string.
  NSMutableString *urlString = [NSMutableString stringWithFormat:@"%@%@", baseURL, apiPath];
  __block NSMutableString *queryStringForEncoding = [NSMutableString new];

  // Set query parameter.
  [queryStrings enumerateKeysAndObjectsUsingBlock:^(id _Nonnull key, id _Nonnull queryString, __unused BOOL *_Nonnull stop) {
    [queryStringForEncoding
        appendString:[NSString stringWithFormat:@"%@%@=%@", [queryStringForEncoding length] > 0 ? @"&" : @"", key, queryString]];
  }];
  if ([queryStringForEncoding length] > 0) {
    [urlString appendFormat:@"?%@", [queryStringForEncoding
                                        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
  }

  return (NSURL * _Nonnull)[NSURL URLWithString:urlString];
}

// This method will be overridden by subclasses.
- (NSDictionary *)getHeadersWithData:(NSObject *__unused)data eTag:(NSString *__unused)eTag {
  return nil;
}

// This method will be overridden by subclasses.
- (NSData *)getPayloadWithData:(NSObject *__unused)data {
  return nil;
}

// This method will be overridden by subclasses.
- (NSString *)obfuscateResponsePayload:(NSString *__unused)payload {
  return nil;
}

- (NSString *)getHttpMethod {
  return kMSACHttpMethodPost;
};

#pragma mark - Private

- (void)setBaseURL:(NSString *)baseURL {
  @synchronized(self) {
    BOOL success = false;
    NSURLComponents *components;
    _baseURL = baseURL;
    NSURL *partialURL = [NSURL URLWithString:[baseURL stringByAppendingString:self.apiPath]];

    // Merge new parial URL and current full URL.
    if (partialURL) {
      components = [NSURLComponents componentsWithURL:self.sendURL resolvingAgainstBaseURL:NO];
      @try {
        for (u_long i = 0; i < sizeof(kMSACPartialURLComponentsName) / sizeof(*kMSACPartialURLComponentsName); i++) {
          NSString *propertyName = kMSACPartialURLComponentsName[i];
          [components setValue:[partialURL valueForKey:propertyName] forKey:propertyName];
        }
      } @catch (NSException *ex) {
        MSACLogInfo([MSACAppCenter logTag], @"Error while updating HTTP URL %@ with %@: \n%@", self.sendURL.absoluteString, baseURL, ex);
      }

      // Update full URL.
      if (components.URL) {
        self.sendURL = (NSURL * _Nonnull) components.URL;
        success = true;
      }
    }

    // Notify failure.
    if (!success) {
      MSACLogInfo([MSACAppCenter logTag], @"Failed to update HTTP URL %@ with %@", self.sendURL.absoluteString, baseURL);
    }
  }
}

- (void)sendAsync:(NSObject *)data
                 eTag:(nullable NSString *)eTag
               callId:(NSString *)callId
    completionHandler:(MSACSendAsyncCompletionHandler)handler {
  @synchronized(self) {
    if (!self.isEnabled) {
      MSACLogWarning([MSACAppCenter logTag], @"%@ is disabled.", NSStringFromClass([self class]));
      NSError *error = [NSError errorWithDomain:kMSACACErrorDomain
                                           code:MSACACDisabledErrorCode
                                       userInfo:@{NSLocalizedDescriptionKey : kMSACACDisabledErrorDesc}];
      handler(callId, nil, nil, error);
      return;
    }
    NSDictionary *httpHeaders = [self getHeadersWithData:data eTag:eTag];
    NSData *payload = [self getPayloadWithData:data];
    [self.httpClient sendAsync:self.sendURL
                        method:[self getHttpMethod]
                       headers:httpHeaders
                          data:payload
                retryIntervals:self.callsRetryIntervals
            compressionEnabled:YES
             completionHandler:^(NSData *_Nullable responseBody, NSHTTPURLResponse *_Nullable response, NSError *_Nullable error) {
               [self printResponse:response body:responseBody error:error];
               handler(callId, response, responseBody, error);
             }];
  }
}

#pragma mark - Printing

- (void)printResponse:(NSHTTPURLResponse *)response body:(NSData *)responseBody error:(NSError *)error {

  // Don't lose time pretty printing if not going to be printed.
  if (error) {
    MSACLogDebug([MSACAppCenter logTag], @"HTTP request error with code: %td, domain: %@, description: %@", error.code, error.domain,
                 error.localizedDescription);
  } else if ([MSACAppCenter logLevel] <= MSACLogLevelVerbose) {
    NSString *contentType = response.allHeaderFields[kMSACHeaderContentTypeKey];
    NSString *payload;

    // Obfuscate payload.
    if (responseBody.length > 0) {
      if ([contentType hasPrefix:@"application/json"]) {
        payload = [self obfuscateResponsePayload:[MSACUtility prettyPrintJson:responseBody]];
      } else if (!contentType.length || [contentType hasPrefix:@"text/"] || [contentType hasPrefix:@"application/"]) {
        payload = [self obfuscateResponsePayload:[[NSString alloc] initWithData:responseBody encoding:NSUTF8StringEncoding]];
      } else {
        payload = @"<binary>";
      }
    }
    MSACLogVerbose([MSACAppCenter logTag], @"HTTP response received with status code: %tu, payload:\n%@", response.statusCode, payload);
  }
}

#pragma mark - Helper

+ (nullable NSString *)eTagFromResponse:(NSHTTPURLResponse *)response {

  // Response header keys are case-insensitive but NSHTTPURLResponse contains case-sensitive keys in Dictionary.
  for (NSString *key in response.allHeaderFields.allKeys) {
    if ([[key lowercaseString] isEqualToString:kMSACETagResponseHeader]) {
      return response.allHeaderFields[key];
    }
  }
  return nil;
}

@end
