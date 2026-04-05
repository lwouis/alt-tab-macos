// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppCenterIngestion.h"
#import "MSACAppCenterErrors.h"
#import "MSACAppCenterInternal.h"
#import "MSACConstants+Internal.h"
#import "MSACHttpIngestionPrivate.h"
#import "MSACLoggerInternal.h"

@implementation MSACAppCenterIngestion

static NSString *const kMSACAPIVersion = @"1.0.0";
static NSString *const kMSACAPIVersionKey = @"api-version";
static NSString *const kMSACApiPath = @"/logs";

// URL components' name within a partial URL.
static NSString *const kMSACPartialURLComponentsName[] = {@"scheme", @"user", @"password", @"host", @"port", @"path"};

- (id)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient baseUrl:(NSString *)baseUrl installId:(NSString *)installId {
  self = [super initWithHttpClient:httpClient
                           baseUrl:baseUrl
                           apiPath:kMSACApiPath
                           headers:@{kMSACHeaderContentTypeKey : kMSACAppCenterContentType, kMSACHeaderInstallIDKey : installId}
                      queryStrings:@{kMSACAPIVersionKey : kMSACAPIVersion}];
  return self;
}

- (BOOL)isReadyToSend {
  return self.appSecret != nil;
}

- (void)sendAsync:(NSObject *)data completionHandler:(MSACSendAsyncCompletionHandler)handler
#if defined(__IPHONE_15_0)
NS_SWIFT_DISABLE_ASYNC
#endif
{
  MSACLogContainer *container = (MSACLogContainer *)data;
  NSString *batchId = container.batchId;

  /*
   * FIXME: All logs are already validated at the time the logs are enqueued to Channel. It is not necessary but it can still protect
   * against invalid logs being sent to server that are messed up somehow in Storage. If we see performance issues due to this validation,
   * we will remove `[container isValid]` call below.
   */
  // Verify container.
  if (!container || ![container isValid]) {
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : kMSACACLogInvalidContainerErrorDesc};
    NSError *error = [NSError errorWithDomain:kMSACACErrorDomain code:MSACACLogInvalidContainerErrorCode userInfo:userInfo];
    MSACLogError([MSACAppCenter logTag], @"%@", [error localizedDescription]);
    handler(batchId, 0, nil, error);
    return;
  }
  if (!self.appSecret) {
    MSACLogError([MSACAppCenter logTag], @"AppCenter ingestion is used without app secret.");
    return;
  }
  [super sendAsync:data
      completionHandler:^(NSString *_Nonnull __unused callId, NSHTTPURLResponse *_Nullable response, NSData *_Nullable responseBody,
                          NSError *_Nullable error) {
        // Ignore the given call ID so that the container's batch ID can be used instead.
        handler(batchId, response, responseBody, error);
      }];
}

- (NSDictionary *)getHeadersWithData:(nullable NSObject *__unused)data eTag:(nullable NSString *__unused)eTag {
  NSMutableDictionary *httpHeaders = [self.httpHeaders mutableCopy];
  [httpHeaders setValue:self.appSecret forKey:kMSACHeaderAppSecretKey];
  return httpHeaders;
}

- (NSData *)getPayloadWithData:(nullable NSObject *)data {
  MSACLogContainer *container = (MSACLogContainer *)data;
  NSString *jsonString = [container serializeLog];
  return [jsonString dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)obfuscateResponsePayload:(NSString *)payload {
  return payload;
}

#pragma mark - MSACHttpClientDelegate

- (void)willSendHTTPRequestToURL:(NSURL *)url withHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers {

  // Don't lose time pretty printing headers if not going to be printed.
  if ([MSACLogger currentLogLevel] <= MSACLogLevelVerbose) {

    // Obfuscate secrets.
    NSMutableArray<NSString *> *flattenedHeaders = [NSMutableArray<NSString *> new];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop __unused) {
      if ([key isEqualToString:kMSACHeaderAppSecretKey]) {
        value = [MSACHttpUtil hideSecret:value];
      }
      [flattenedHeaders addObject:[NSString stringWithFormat:@"%@ = %@", key, value]];
    }];

    // Log URL and headers.
    MSACLogVerbose([MSACAppCenter logTag], @"URL: %@", url);
    MSACLogVerbose([MSACAppCenter logTag], @"Headers: %@", [flattenedHeaders componentsJoinedByString:@", "]);
  }
}

@end
